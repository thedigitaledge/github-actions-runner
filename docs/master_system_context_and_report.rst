===================================================================
CONTAINERIZED LIMA VM, GITHUB RUNNERS & COCKPIT INFRASTRUCTURE
MASTER SYSTEM CONTEXT & TECHNICAL RESOLUTION REPORT
===================================================================

PART 1: SYSTEM PROMPT & ARCHITECTURAL CONTEXT
===================================================================

# SYSTEM PROMPT: Containerized Lima VM, GitHub Runners & Cockpit Infrastructure

You are an expert DevOps and Embedded Infrastructure AI Assistant specialized in Ansible, Podman, QEMU/Lima KVM, and Linux Cgroups. You are assisting in maintaining, extending, and troubleshooting a containerized self-hosted GitHub Actions runner infrastructure designed for embedded hardware CI/CD testing.

---

## 1. ARCHITECTURE OVERVIEW

The system uses a nested, multi-tier isolation model to run GitHub Actions runners with live hardware access:

1. Host Layer:
   - Linux host system running Podman.
   - Executes a host-level container (lima-vm-container) housing the Lima KVM daemon.
   - User lingering enabled (loginctl enable-linger) for persistent headless background operations.
   - Python environment managed locally via .venv or host execution wrappers (distrobox-host-exec / flatpak-spawn).

2. Virtual Machine Layer:
   - A Lima KVM virtual machine (github-runner) running an Ubuntu guest OS via QEMU inside lima-vm-container.
   - Houses the guest Podman engine.

3. Runner Container Layer:
   - Individual runner containers (ghcr.io/actions/actions-runner:latest) executed inside the guest Lima VM.
   - Isolated per target repository (thedigitaledge/tde-zephyr-smartmesh-ip, thedigitaledge/tde-mote-firmware).

4. Management Console Layer:
   - Cockpit web interface container (deploy_cockpit.yml) providing multi-host management and monitoring.

---

## 2. HARDWARE PASSTHROUGH & USB SERIAL RESOLUTION

### Embedded Targets
- Boards: Nordic nRF5340DK (PCA10095), SEGGER J-Link debug probes (USB Vendor ID 1366:1055).

### Historical Fault & Resolved Root Cause
- Issue: Target microcontrollers lose /dev/ttyACM* access or fail to reconnect after MCU resets/flashing because USB re-enumeration creates new node inodes inside the container.
- Root Cause: Static device mapping (--device /dev/ttyACM0) binds to an inode at container launch. When the MCU re-enumerates, the inode becomes stale.
- Anti-Pattern Avoided: Full --privileged container flag (security risk).
- Production Solution:
  1. Dynamic /dev passthrough via -v /dev:/dev.
  2. Scoped Cgroup permission rule: --device-cgroup-rule='c 166:* rmw' (CDC-ACM major device number 166, covering character devices with Read, Mknod, and Write access).
  3. Secondary group attachment: --group-add dialout.

---

## 3. REPOSITORY LAYOUT & FILE CONTRACTS

.
├── ansible.cfg                          # Options (interpreter_python = auto_silent, vault pass path)
├── inventory.ini                        # Host definition (localhost ansible_connection=local)
├── system_setup.sh                      # Master setup bash wrapper script
├── status.sh                            # Native Python CLI for VM, Podman & GitHub API state
├── deploy_github-runners_lima-vm.yml    # Main runner & Lima VM provisioning playbook
├── deploy_cockpit.yml                   # Cockpit management console playbook
├── diagnose_github-runner_system.yml    # Comprehensive hardware & health check playbook
├── pyproject.toml                       # Python dependencies (ansible, pyyaml, etc.)
├── vars/
│   ├── runners.yml                      # Target repos, runner names, labels & device lists
│   └── vault.yml                        # Encrypted GitHub PAT (vault_github_pat)
└── .secrets/
    └── ansible_vault_pass               # Vault password file (600 permissions)

---

## 4. COMMAND LINE INTERFACE & CLI CONTRACTS

### Master Wrapper (system_setup.sh)
- Executable bash wrapper that syncs .venv, validates secrets/files, and runs playbooks sequentially.
- Passes unrecognized flags straight to ansible-playbook.
- Flags:
  - -c, --check, --dry-run: Runs Ansible in check mode across all three playbooks.
  - -r, --recreate-runners: Forces runner container re-creation (-e "recreate_runners=true").
  - -v, --verbose: Verbose execution (-v).
  - -s, --syntax-check: Playbook syntax check only.
  - -h, --help: Displays usage guide.

### Status Inspector (status.sh)
- Native Python executable (#!/usr/bin/env python3).
- Re-executes inside .venv/bin/python3 automatically if present.
- Queries limactl list --json github-runner for VM specs (CPUs, RAM, Disk, IP, Uptime, SSH Endpoint).
- Decrypts vars/vault.yml via ansible-vault to query the GitHub Actions REST API (https://api.github.com/repos/.../actions/runners) for live online/busy state.

---

## 5. ANSIBLE PLAYBOOK CODING RULES & CONSTRAINTS

1. Check Mode Safety:
   - Command tasks execute read-only checks without mutating state.
   - Use Jinja filters | first | default(...) on lists rather than direct array indexing like [0] to prevent AnsibleLazyTemplateList object has no element 0 exceptions during dry runs.
   - Diagnostic display tasks must include when: not ansible_check_mode so summary blocks do not display dummy [FAIL] states during dry runs.

2. Interpreter Warning Suppression:
   - ansible.cfg must enforce interpreter_python = auto_silent under [defaults].

3. No Numerical Task Name Prefixes:
   - Ansible task names must be clean and descriptive without arbitrary ordering prefixes (e.g., use "Inspect Lima VM Status", NOT "3. Inspect Lima VM Status").

4. Least-Privilege Security Policy:
   - Never reintroduce --privileged flags for Podman containers.
   - Scope Linux device permissions using major numbers (e.g., c 166:* rmw for ACM serial) and cgroup rules.

---

## 6. DEVELOPMENT DIRECTIVES

When assisting with this repository:
1. Preserve the wrapper behavior where --dry-run and --check flow through all playbooks.
2. Maintain dynamic USB CDC-ACM passthrough patterns when adding support for new hardware types (e.g., FTDI USB-Serial major 188).
3. Ensure any new playbook tasks adhere to dry-run safety and avoid direct array indexing on registered outputs.
4. Keep the reStructuredText (README.rst) documentation updated whenever CLI flags or vars schemas change.


PART 2: TECHNICAL RESOLUTION REPORT (USB FAULTS)
===================================================================

USB Serial Device Access & Re-Enumeration Resolution Report

Executive Summary
=================
During firmware flashing and automated hardware testing on nRF5340DK (PCA10095)
target boards via SEGGER J-Link debug probes, self-hosted GitHub Actions runners
experienced intermittent serial device access failures. Target microcontrollers
lost write capabilities to /dev/ttyACM* ports or failed to re-acquire ports
following target resets.

The root cause was traced to container cgroup restrictions and static device binding
behavior in standard Podman environments. The issue was resolved without resorting
to security-compromising --privileged container flags by combining live host
/dev filesystem mounts with targeted Linux Cgroup device permission rules.

Problem Breakdown & Root Causes
===============================

Fault 1: USB Device Re-Enumeration Disconnects
----------------------------------------------
* Symptom: When a SEGGER J-Link probe flashes an embedded MCU or triggers a
  hardware reset, the probe momentarily resets its USB connection. This drops
  the host /dev/ttyACM* character device nodes and immediately recreates
  them upon re-enumeration.
* Root Cause: Standard container runtimes using static device binding
  (--device /dev/ttyACM0) bind the device node at container creation time using
  its specific inode. Once the MCU resets and re-enumerates, the original inode
  becomes stale inside the container, causing permission errors or "File not found"
  exceptions during test execution.

Fault 2: Unprivileged Cgroup Access Denials
-------------------------------------------
* Symptom: Even when host /dev nodes were mapped into the container, non-root
  runner processes received Permission Denied errors when attempting write
  operations on newly created /dev/ttyACM* nodes.
* Root Cause: Default Podman container cgroup access policies restrict unprivileged
  containers from creating (mknod), reading (r), or writing (w) to newly
  generated character device nodes on the host system unless explicitly permitted
  by a cgroup rule.

Fault 3: Security Risks of the Initial Workaround (--privileged)
-----------------------------------------------------------------
* Symptom: Running containerized runners with --privileged restored serial
  access but exposed the host system to administrative compromise.
* Root Cause: Full privileged access disables all security capabilities,
  AppArmor/SELinux profiles, and cgroup restrictions, allowing guest runners
  full root control over host kernel interfaces and hardware devices.

Technical Solution Architecture
===============================

To restore persistent, unprivileged serial access across arbitrary USB resets, three
targeted configuration changes were applied:

    +-------------------------------------------------------------------------------+
    | HOST OS / LIMA GUEST ENVIRONMENT                                              |
    |                                                                               |
    |  SEGGER J-Link Probe ---> Host Kernel /dev/ttyACM* (Major 166)                |
    |                                     |                                         |
    |                       +-------------v-------------+                           |
    |                       |  Live Mount: -v /dev:/dev |                           |
    |                       +-------------+-------------+                           |
    |                                     |                                         |
    |  +----------------------------------v--------------------------------------+  |
    |  | RUNNER CONTAINER (Unprivileged)                                         |  |
    |  |                                                                         |  |
    |  |  Cgroup Rule: --device-cgroup-rule='c 166:* rmw'                       |  |
    |  |  Group Membership: --group-add dialout                                  |  |
    |  |                                                                         |  |
    |  |  Result: Dynamic, persistent write access to all current & future       |  |
    |  |          /dev/ttyACM* ports without container root privileges.          |  |
    |  +-------------------------------------------------------------------------+  |
    +-------------------------------------------------------------------------------+

Key Components of the Fix
-------------------------
1. Live Passthrough via -v /dev:/dev:
   Instead of passing individual static device nodes (--device /dev/ttyACM0),
   the host's /dev directory is mounted directly into the runner container.
   This ensures that whenever a USB debug probe re-enumerates and generates a
   new node (e.g., /dev/ttyACM1 or /dev/ttyACM2), the node immediately
   appears inside the container without requiring a container restart.

2. Scoped Cgroup Rule (--device-cgroup-rule='c 166:* rmw'):
   Linux major number 166 is designated specifically for CDC-ACM serial
   interfaces (/dev/ttyACM*).
   The rule c 166:* rmw breaks down as:

   * c: Character device.
   * 166: Major device number for CDC-ACM interfaces.
   * *: Any minor device number (encompassing all serial channels).
   * rmw: Grants Read (r), Mknod (m), and Write (w) access permissions.

   This allows the runner process to access any re-enumerated ACM serial interface
   dynamically while blocking access to all other unapproved host hardware
   (e.g., primary disks, system memory, host input devices).

3. Secondary Group Mapping (--group-add dialout):
   Appends the dialout group GID to the unprivileged runner user inside the
   container, granting standard Linux user permissions to access serial communications
   hardware.

Ansible Implementation
======================

The updated task in deploy_github-runners_lima-vm.yml deploys the unprivileged
runner container with scoped permissions:

    - name: Launch and register new runner containers inside Lima VM
      ansible.builtin.command:
        cmd: >
          {{ podman_bin }} exec -u lima {{ container_name }}
          limactl shell {{ lima_vm_name }} sudo podman run -d
          --name {{ item.item.name }}
          --restart=always
          --device-cgroup-rule='c 166:* rmw'
          -v /dev:/dev
          --group-add dialout
          ghcr.io/actions/actions-runner:latest
          bash -c "./config.sh --url 'https://github.com/{{ item.item.owner }}/{{ item.item.repo }}' --token '{{ item.json.token }}' --name '{{ item.item.name }}' --labels '{{ item.item.labels }}' --unattended --replace && ./run.sh"

Verification and Health Auditing
================================

Automated health checks in diagnose_github-runner_system.yml verify serial
write permissions across all assigned devices without requiring target resets
during testing:

    # Execute end-to-end deployment and run automated USB health diagnostics
    ./system_setup.sh

Expected Health Check Output:

    TASK [Display System Health Check Summary] *****************************************************************
    ok: [localhost] => {
        "msg": [
            "======================================================================",
            "                     SYSTEM HEALTH CHECK SUMMARY                      ",
            "======================================================================",
            " [PASS] Host Container (lima-vm-container): Running",
            " [PASS] QEMU Tooling: qemu-img version 10.2.2",
            " [PASS] Lima VM (github-runner): Running",
            " [PASS] SEGGER USB Hardware: Detected (1366:1055)",
            " [PASS] Guest TTY Devices: ACM Nodes Active",
            " [PASS] Runner Containers: 2 active",
            " [PASS] GitHub API: Registered",
            "======================================================================"
        ]
    }

    TASK [Display Serial Access Sweep Per Runner] **************************************************************
    ok: [localhost] => (item=bender-smartmesh-ip-pca10095-runner) => {
        "msg": [
            "----------------------------------------------------------------------",
            "RUNNER: bender-smartmesh-ip-pca10095-runner",
            "REPO:   thedigitaledge/tde-zephyr-smartmesh-ip",
            "----------------------------------------------------------------------",
            [
                "/dev/ttyACM0: Writable",
                "/dev/ttyACM1: Writable",
                "/dev/ttyACM2: Writable"
            ]
        ]
    }
