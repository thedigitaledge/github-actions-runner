===================================================================
FUTURE FEATURES & INFRASTRUCTURE ENHANCEMENTS
===================================================================

This document outlines recommended roadmap features, resiliency enhancements, build optimizations, and security improvements for the Containerized Lima VM & GitHub Actions Runner infrastructure.

-------------------------------------------------------------------
1. AUTO-HEALING & OBSERVABILITY
-------------------------------------------------------------------

1.1 Automated Self-Healing Daemon / Cron Task
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Continuously monitor and automatically recover offline runner containers or dead VM instances.
* **Rationale**: Prevents runners from remaining offline indefinitely if network hiccups or GitHub API token glitches occur.
* **Implementation**:
  Schedule a systemd timer (running every 15 minutes) executing a headless status check. If a runner container is offline while the VM is active, automatically run ``./system_setup.sh -r``.

1.2 Webhook Alerting (Slack / Discord / Teams / Matrix)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Provide immediate real-time notifications to engineering teams upon hardware disconnects or pipeline health degradation.
* **Rationale**: Reduces mean-time-to-detection (MTTD) for physical infrastructure failures.
* **Implementation**:
  Extend ``status.sh`` or insert an Ansible ``ansible.builtin.uri`` task into ``diagnose_github-runner_system.yml`` to post JSON alert payloads to webhook endpoints on state changes (PASS -> FAIL).

1.3 Prometheus & Grafana Metrics Exporter
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Aggregate telemetry on serial port availability, VM resource utilization, and build job duration trends.
* **Rationale**: Provides long-term visibility into hardware usage and capacity requirements.
* **Implementation**:
  Deploy a lightweight Node Exporter sidecar container inside Cockpit or the Lima VM to expose hardware metrics to Prometheus scraping.

-------------------------------------------------------------------
2. BUILD PERFORMANCE & CI OPTIMIZATION
-------------------------------------------------------------------

2.1 Pre-Baked Base Runner Container Images
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Minimize build setup overhead per job run.
* **Rationale**: Stock runner images download large embedded toolchains (Zephyr SDK, West, CMake, Ninja) on every build.
* **Implementation**:
  Maintain a custom base image (``ghcr.io/your-org/embedded-runner-base:latest``) pre-installed with required toolchains and Python dependencies.
