===================================================================
FUTURE FEATURES & INFRASTRUCTURE ENHANCEMENTS
===================================================================

This document outlines recommended roadmap features, resiliency enhancements, build optimizations, and security improvements for the Containerized Lima VM & GitHub Actions Runner infrastructure.

-------------------------------------------------------------------
1. HARDWARE RESILIENCY & DEVICE MANAGEMENT
-------------------------------------------------------------------

1.1 Persistent Hardware Mapping via udev Symlinks (/dev/serial/by-id/)
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

1.2 USB Hub Power Cycling (uhubctl Integration)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Automatically recover embedded microcontrollers or J-Link probes that experience physical-layer USB freeze states.
* **Rationale**: Microcontrollers occasionally hang during deep sleep or flashing faults, requiring hard VBUS power cycling rather than software resets.
* **Implementation**:
  Integrate ``uhubctl`` into diagnostic playbooks or health scripts to power cycle individual USB ports upon serial health check failure:

  .. code-block:: bash

      uhubctl -l 1-1 -p 2 -a cycle -d 2

1.3 Automated udev Trigger for Hot-Plug Recovery
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Instantly re-verify hardware state or trigger runner container recovery upon USB hardware insertion.
* **Rationale**: Eliminates manual intervention when physical debug boards are re-connected.
* **Implementation**:
  Deploy a host-level ``udev`` rule matching SEGGER USB IDs (Vendor ``1366``, Product ``1055``) to trigger a systemd service executing ``./status.sh`` or a targeted runner restart.

-------------------------------------------------------------------
2. AUTO-HEALING & OBSERVABILITY
-------------------------------------------------------------------

2.1 Automated Self-Healing Daemon / Cron Task
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Continuously monitor and automatically recover offline runner containers or dead VM instances.
* **Rationale**: Prevents runners from remaining offline indefinitely if network hiccups or GitHub API token glitches occur.
* **Implementation**:
  Schedule a systemd timer (running every 15 minutes) executing a headless status check. If a runner container is offline while the VM is active, automatically run ``./system_setup.sh -r``.

2.2 Webhook Alerting (Slack / Discord / Teams / Matrix)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Provide immediate real-time notifications to engineering teams upon hardware disconnects or pipeline health degradation.
* **Rationale**: Reduces mean-time-to-detection (MTTD) for physical infrastructure failures.
* **Implementation**:
  Extend ``status.sh`` or insert an Ansible ``ansible.builtin.uri`` task into ``diagnose_github-runner_system.yml`` to post JSON alert payloads to webhook endpoints on state changes (PASS -> FAIL).

2.3 Prometheus & Grafana Metrics Exporter
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Aggregate telemetry on serial port availability, VM resource utilization, and build job duration trends.
* **Rationale**: Provides long-term visibility into hardware usage and capacity requirements.
* **Implementation**:
  Deploy a lightweight Node Exporter sidecar container inside Cockpit or the Lima VM to expose hardware metrics to Prometheus scraping.

-------------------------------------------------------------------
3. BUILD PERFORMANCE & CI OPTIMIZATION
-------------------------------------------------------------------

3.1 Pre-Baked Base Runner Container Images
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Minimize build setup overhead per job run.
* **Rationale**: Stock runner images download large embedded toolchains (Zephyr SDK, West, CMake, Ninja) on every build.
* **Implementation**:
  Maintain a custom base image (``ghcr.io/your-org/embedded-runner-base:latest``) pre-installed with required toolchains and Python dependencies.
