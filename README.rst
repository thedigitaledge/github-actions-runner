=============================================================================
Containerized Lima KVM & GitHub Actions Runner Infrastructure
=============================================================================

This repository provides an automated, enterprise-grade Ansible deployment system for self-hosted **GitHub Actions Runners** executing inside a **Containerized Lima KVM Virtual Machine** with native hardware USB passthrough, `uhubctl` USB power cycling, persistent `udev` device mapping, workflow container execution (`container:` syntax), automated hot-plug recovery, and background self-healing watchdogs.

-----------------------------------------------------------------------------
ARCHITECTURE OVERVIEW
-----------------------------------------------------------------------------

.. code-block:: text

  +-------------------------------------------------------------------------+
  | Host System (Linux / Silverblue / Fedora / RHEL)                        |
  |                                                                         |
  |  +-------------------------------------------------------------------+  |
  |  | Podman Container: lima-vm-container                               |  |
  |  |                                                                   |  |
  |  |  +-------------------------------------------------------------+  |  |
  |  |  | Lima KVM Virtual Machine: github-runner (Ubuntu 24.04)      |  |  |
  |  |  |                                                             |  |  |
  |  |  |  - Podman Systemd Socket: /run/podman/podman.sock           |  |  |
  |  |  |  - Shared Compilation Cache: /var/cache/ccache              |  |  |
  |  |  |  - udev Hot-Plug Handler: /usr/local/bin/segger-hotplug...  |  |  |
  |  |  |  - USB Power Control: uhubctl                               |  |  |
  |  |  |                                                             |  |  |
  |  |  |  +-------------------------------------------------------+  |  |  |
  |  |  |  | Runner Containers: actions-runner                     |  |  |  |
  |  |  |  |  - Mounted Socket: /var/run/docker.sock               |  |  |  |
  |  |  |  - Mounted Devices: /dev/serial/by-id/... & /dev/ttyACM* |  |  |  |
  |  |  |  - Mounted ccache: /gh-runner/.cache/ccache              |  |  |  |
  |  |  |  - Ephemeral Mode: --once (auto-recreates on exit)       |  |  |  |
  |  |  |  +-------------------------------------------------------+  |  |  |
  |  |  +-------------------------------------------------------------+  |  |
  |  +-------------------------------------------------------------------+  |
  +-------------------------------------------------------------------------+

-----------------------------------------------------------------------------
KEY FEATURES & CAPABILITIES
-----------------------------------------------------------------------------

1. **Persistent Hardware Mapping via udev (`/dev/serial/by-id/`)**
   * Automatically resolves non-deterministic `/dev/ttyACM*` paths in ``vars/runners.yml`` to immutable `/dev/serial/by-id/usb-SEGGER_J-Link_*` symlinks.
   * Auto-saves resolved symlinks back into ``vars/runners.yml`` during deployment.

2. **USB Hub Power Cycling (`uhubctl` Integration)**
   * Integrates `uhubctl` inside the guest VM to power cycle USB VBUS power lines when hardware probes freeze or hang in deep-sleep states.
   * Diagnostics automatically attempt USB port cycling when serial permissions or write access checks fail.

3. **Automated udev Hot-Plug Recovery**
   * Configures a guest VM `udev` rule matching SEGGER USB IDs (Vendor `1366`, Product `1055`).
   * Automatically reloads `udev` rules and restarts offline runner containers when physical debug probes are re-connected.

4. **Automated 15-Minute Self-Healing Watchdog**
   * Deploys host systemd user timer (`github-runner-self-healing.timer`) and script (`self_healing_check.sh`).
   * Continuously monitors host container, guest VM, and runner container states, automatically triggering recovery flags (`-a` or `-r`) upon failure.

5. **GitHub Actions Workflow Container Execution (`container:` Keyword)**
   * Enables `podman.socket` inside the guest VM.
   * Bind-mounts `/run/podman/podman.sock` as `/var/run/docker.sock` into runner containers, allowing job steps to execute inside Docker/Podman build containers.

6. **Shared `ccache` Compilation Cache**
   * Mounts persistent `/var/cache/ccache` into runner containers as `/gh-runner/.cache/ccache`.
   * Accelerates embedded firmware compilation (Zephyr RTOS, ARM GCC) across workflow jobs.

7. **Ephemeral Runner Isolation (`--once`)**
   * Registers runner containers with the `--once` flag.
   * After processing a single workflow job, the container exits and Podman automatically spawns a fresh, isolated runner container instance.

8. **Secure Keyring Secret Resolution**
   * Configures ``ansible.cfg`` to execute ``.secrets/vault_pass.sh``.
   * Resolves vault passwords hierarchically from `ANSIBLE_VAULT_PASSWORD` environment variable, GNOME Keyring (`secret-tool`), or `.secrets/ansible_vault_pass`.

9. **Ansible Galaxy Collection Integration**
   * Uses ``containers.podman`` modules for declarative container management.
   * Automated dependency installation via ``requirements.yml`` during setup.

-----------------------------------------------------------------------------
QUICK START & COMMAND REFERENCE
-----------------------------------------------------------------------------

All operations are managed through the ``./system_setup.sh`` setup wrapper script:

.. code-block:: bash

  # Display available command line options
  ./system_setup.sh --help

  # Standard deployment (idempotent setup + health diagnostics)
  ./system_setup.sh

  # Force re-creation of GitHub runner containers only
  ./system_setup.sh -r

  # Force re-creation of the Lima VM and VM container only
  ./system_setup.sh -m

  # Force re-creation of BOTH the Lima VM and runner containers
  ./system_setup.sh -a

  # Force update/re-installation of Python & Ansible Galaxy dependencies
  ./system_setup.sh -u

  # Perform a dry-run execution across playbooks (Ansible check mode)
  ./system_setup.sh -c

  # Perform playbook syntax validation without executing
  ./system_setup.sh -s

  # Run playbooks in verbose mode
  ./system_setup.sh -v

-----------------------------------------------------------------------------
CONFIGURATION & VAULT SETUP
-----------------------------------------------------------------------------

1. **Define Runners in ``vars/runners.yml``**:

   .. code-block:: yaml

     github_runners:
       - owner: "thedigitaledge"
         repo: "tde-zephyr-smartmesh-ip"
         name: "bender-smartmesh-ip-pca10095-runner"
         labels: "self-hosted,Linux,x64,usb,nrf5340dk,pca10095,iks01a2"
         devices:
           - "/dev/ttyACM0"
           - "/dev/ttyACM1"

2. **Configure Encrypted Credentials in ``vars/vault.yml``**:

   .. code-block:: yaml

     github_pat: "ghp_yourPersonalAccessTokenHere"

-----------------------------------------------------------------------------
INFRASTRUCTURE ROADMAP (FUTURE DEVELOPMENTS)
-----------------------------------------------------------------------------

For detailed specifications on upcoming enhancements, see ``future_developments.rst.txt``:
* **Security**: GitHub App Authentication, Rootless Podman Execution, PKCS#11 HSM Code Signing.
* **Performance**: Pre-baked base runner container images, Workspace caching, MinIO S3 local storage.
* **Observability**: Real-time Webhook alerting, Prometheus `node-exporter`, Live Serial/RTT Web Console streaming.
* **Resiliency**: Hardware Probe `flock` Mutex Locking, Targeted `uhubctl` resets, USB fault injection harness.
* **HIL Testing**: Sigrok Logic Analyzers, SocketCAN Passthrough, Remote Debug Server, SCPI PSU Control, Vision OCR UI Verification, RF Attenuator Control, Nordic PPK2 Power Profiling, Dynamic Hardware Board Farm Router.
* **Resource Management**: Dynamic VM CPU/RAM auto-scaling & Podman image/volume auto-pruning.
* **Tooling**: Interactive Terminal UI (`manage.sh`) & ARM64 Apple Silicon host support.

-----------------------------------------------------------------------------
DIAGNOSTICS & MONITORING
-----------------------------------------------------------------------------

Run system diagnostics at any time to inspect hardware, serial permissions, and container health:

.. code-block:: bash

  ansible-playbook diagnose_github-runner_system.yml
