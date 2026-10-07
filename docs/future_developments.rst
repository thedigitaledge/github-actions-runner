===================================================================
FUTURE FEATURES & INFRASTRUCTURE ENHANCEMENTS
===================================================================

This document outlines recommended roadmap features, resiliency enhancements, build optimizations, and security improvements for the Containerized Lima VM & GitHub Actions Runner infrastructure.

-------------------------------------------------------------------
1. CONTAINER WORKFLOW SUPPORT ("container:" KEYWORD)
-------------------------------------------------------------------

1.1 Podman Socket Passthrough for Container-in-Container Execution
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Enable GitHub Actions workflows to utilize the ``container:`` job syntax for running steps inside isolated Docker/Podman build environments.
* **Rationale**: Many embedded CI pipelines (e.g., Zephyr RTOS, ARM GCC) rely on pre-built container images (e.g., ``ghcr.io/zephyrproject-rtos/zephyr-build``) for reproducible compilation environments.
* **Implementation**:
  1. **Enable Podman Socket**: Enable and start ``podman.socket`` inside the Lima VM in ``deploy_github-runners_lima-vm.yml``:

     .. code-block:: yaml

         - name: Ensure Podman socket service is enabled in Lima VM
           ansible.builtin.command:
             cmd: >
               {{ podman_bin }} exec -u lima {{ container_name }}
               limactl shell {{ lima_vm_name }} sudo systemctl enable --now podman.socket

  2. **Mount Socket into Runner Containers**: Mount the Unix socket into runner containers as ``/var/run/docker.sock`` and set ``DOCKER_HOST``:

     .. code-block:: yaml

         -v /run/podman/podman.sock:/var/run/docker.sock
         -e DOCKER_HOST=unix:///var/run/docker.sock

  3. **Workflow Hardware Options**: Pass hardware cgroup rules in the workflow file for serial access inside job containers:

     .. code-block:: yaml

         jobs:
           build:
             runs-on: [self-hosted, nrf5340dk]
             container:
               image: ghcr.io/zephyrproject-rtos/zephyr-build:v0.26.4
               options: --device-cgroup-rule='c 166:* rmw' -v /dev:/dev

-------------------------------------------------------------------
2. ANSIBLE GALAXY COLLECTION REFACTORING (containers.podman)
-------------------------------------------------------------------

2.1 Eliminating Custom Shell Invocations via Galaxy Modules
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Replace raw ``ansible.builtin.command`` Podman invocations with official Ansible Galaxy collections (``containers.podman`` and ``fedora.linux_system_roles``) to simplify playbooks and eliminate custom shell scripting.
* **Rationale**: Using declarative collections provides native idempotency, built-in dry-run (check mode) validation, and direct structure for device rules, environment variables, and volume mounts without complex Jinja string escaping.
* **Implementation**:
  1. **Declare Galaxy Dependencies**: Create a ``requirements.yml`` file in the repository root:

     .. code-block:: yaml

         ---
         collections:
           - name: containers.podman
             version: ">=1.12.0"
           - name: community.general
           - name: fedora.linux_system_roles

  2. **Auto-Install Collections in Wrapper**: Update ``system_setup.sh`` to automatically install dependencies before running playbooks:

     .. code-block:: bash

         if [ -f "requirements.yml" ]; then
           ansible-galaxy collection install -r requirements.yml --upgrade
         fi

  3. **Refactor Container Deployment**: Replace command tasks in ``deploy_github-runners_lima-vm.yml`` with native module parameters:

     .. code-block:: yaml

         - name: Launch and register new runner container
           containers.podman.podman_container:
             name: "{{ item.item.name }}"
             image: "ghcr.io/actions/actions-runner:latest"
             state: started
             restart_policy: "always"
             device_cgroup_rules:
               - "c 166:* rmw"
             volumes:
               - "/dev:/dev"
               - "/run/podman/podman.sock:/var/run/docker.sock"
             groups:
               - "dialout"
             env:
               DOCKER_HOST: "unix:///var/run/docker.sock"

-------------------------------------------------------------------
3. HARDWARE RESILIENCY & DEVICE MANAGEMENT
-------------------------------------------------------------------

3.1 Persistent Hardware Mapping via udev Symlinks (/dev/serial/by-id/)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Eliminate reliance on non-deterministic ``/dev/ttyACM*`` device paths across host reboots or USB resets.
* **Rationale**: Standard Linux kernel enumeration can swap device paths (e.g., ``/dev/ttyACM0`` becoming ``/dev/ttyACM1``) when multiple debug probes are attached.
* **Implementation**:
  Update ``vars/runners.yml`` and container volume/cgroup bindings to use persistent hardware symlinks:

  .. code-block:: yaml

      github_runners:
        - name: "bender-smartmesh-ip-pca10095-runner"
          devices:
            - "/dev/serial/by-id/usb-SEGGER_J-Link_000683888888-if00"

3.2 USB Hub Power Cycling (uhubctl Integration)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Automatically recover embedded microcontrollers or J-Link probes that experience physical-layer USB freeze states.
* **Rationale**: Microcontrollers occasionally hang during deep sleep or flashing faults, requiring hard VBUS power cycling rather than software resets.
* **Implementation**:
  Integrate ``uhubctl`` into diagnostic playbooks or health scripts to power cycle individual USB ports upon serial health check failure:

  .. code-block:: bash

      uhubctl -l 1-1 -p 2 -a cycle -d 2

3.3 Automated udev Trigger for Hot-Plug Recovery
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Instantly re-verify hardware state or trigger runner container recovery upon USB hardware insertion.
* **Rationale**: Eliminates manual intervention when physical debug boards are re-connected.
* **Implementation**:
  Deploy a host-level ``udev`` rule matching SEGGER USB IDs (Vendor ``1366``, Product ``1055``) to trigger a systemd service executing ``./status.sh`` or a targeted runner restart.

-------------------------------------------------------------------
4. AUTO-HEALING & OBSERVABILITY
-------------------------------------------------------------------

4.1 Automated Self-Healing Daemon / Cron Task
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Continuously monitor and automatically recover offline runner containers or dead VM instances.
* **Rationale**: Prevents runners from remaining offline indefinitely if network hiccups or GitHub API token glitches occur.
* **Implementation**:
  Schedule a systemd timer (running every 15 minutes) executing a headless status check. If a runner container is offline while the VM is active, automatically run ``./system_setup.sh -r``.

4.2 Webhook Alerting (Slack / Discord / Teams / Matrix)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Provide immediate real-time notifications to engineering teams upon hardware disconnects or pipeline health degradation.
* **Rationale**: Reduces mean-time-to-detection (MTTD) for physical infrastructure failures.
* **Implementation**:
  Extend ``status.sh`` or insert an Ansible ``ansible.builtin.uri`` task into ``diagnose_github-runner_system.yml`` to post JSON alert payloads to webhook endpoints on state changes (PASS -> FAIL).

4.3 Prometheus & Grafana Metrics Exporter
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Aggregate telemetry on serial port availability, VM resource utilization, and build job duration trends.
* **Rationale**: Provides long-term visibility into hardware usage and capacity requirements.
* **Implementation**:
  Deploy a lightweight Node Exporter sidecar container inside Cockpit or the Lima VM to expose hardware metrics to Prometheus scraping.

-------------------------------------------------------------------
5. BUILD PERFORMANCE & CI OPTIMIZATION
-------------------------------------------------------------------

5.1 Shared ccache & Zephyr Workspace Volume Caching
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Dramatically reduce embedded compilation times across CI workflow runs.
* **Rationale**: Embedded toolchains (Zephyr SDK, GCC ARM) frequently re-compile unchanged board abstraction layers.
* **Implementation**:
  Mount a persistent shared cache directory into runner containers:

  .. code-block:: yaml

      -v /var/cache/ccache:/gh-runner/.cache/ccache

  Configure ``CCACHE_DIR=/gh-runner/.cache/ccache`` inside the runner environment settings.

5.2 Pre-Baked Base Runner Container Images
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Minimize build setup overhead per job run.
* **Rationale**: Stock runner images download large embedded toolchains (Zephyr SDK, West, CMake, Ninja) on every build.
* **Implementation**:
  Maintain a custom base image (``ghcr.io/your-org/embedded-runner-base:latest``) pre-installed with required toolchains and Python dependencies.

-------------------------------------------------------------------
6. SECURITY & ACCESS CONTROL
-------------------------------------------------------------------

6.1 Automated Ephemeral Runner Mode (--once)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Guarantee absolute clean-slate isolation for every single CI build.
* **Rationale**: Prevents build-to-build contamination or stale firmware artifacts.
* **Implementation**:
  Register runner containers with the ``--once`` flag and wrap them inside a Podman systemd template unit that automatically restarts a fresh container instance upon exit.

6.2 Vault Password Resolution via Host Keyring / Environment
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Remove plaintext vault password files from disk.
* **Rationale**: Enhances credential security against unprivileged host processes.
* **Implementation**:
  Configure ``ansible.cfg`` with ``vault_password_file = .secrets/vault_pass.sh``, where the script retrieves the vault key from GNOME Keyring (``secret-tool``) or environment variables.
  
