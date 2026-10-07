===================================================================
USB Serial Device Access & Re-Enumeration Resolution Report
===================================================================

Executive Summary
=================
During firmware flashing and automated hardware testing on nRF5340DK (PCA10095)
target boards via SEGGER J-Link debug probes, self-hosted GitHub Actions runners
experienced intermittent serial device access failures. Target microcontrollers
lost write capabilities to ``/dev/ttyACM*`` ports or failed to re-acquire ports
following target resets.

The root cause was traced to container cgroup restrictions and static device binding
behavior in standard Podman environments. The issue was resolved without resorting
to security-compromising ``--privileged`` container flags by combining live host
``/dev`` filesystem mounts with targeted Linux Cgroup device permission rules.

The USB Problem
===============

The SEGGER J-Link USB board (Vendor ID 0x1366) connected to the host machine failed
to pass through into the guest VM (github-runner), causing runner deployments to
fail with Error: stat /dev/ttyACM0: no such file or directory.

The failure was caused by two underlying issues:

- Host USB Permission Restrictions:
  - The host character device nodes under /dev/bus/usb/ defaulted to 0644 (crw-rw-r--) read-only permissions for non-root users.
  - During initial troubleshooting, a chmod -R 0666 command stripped directory execute (x) bits from /dev/bus/usb/001/ (drw-rw-rw-), blocking non-root directory traversal.
  - Because qemu-system-x86_64 runs under the unprivileged lima user inside lima-vm-container, libusb encountered access errors (LIBUSB_ERROR_ACCESS) and could not claim the physical USB device.

- Missing QEMU Passthrough Arguments:
  - Lima's QEMU VM instance does not pass host USB devices into guest VMs by default. Without explicit parameters (-device qemu-xhci,id=xhci -device usb-host,vendorid=0x1366), QEMU boots without attaching the SEGGER hardware interface.

How It Was Fixed
----------------

Restored Host Directory & Device Permissions:

Restored directory traversal permissions (0755) on /dev/bus/usb/ folders while maintaining 0666 read/write access on character device nodes:

..code-block:: bash
        sudo find /dev/bus/usb/ -type d -exec chmod 0755 {} +
        sudo find /dev/bus/usb/ -type c -exec chmod 0666 {} +

Installed the official SEGGER udev rules (/etc/udev/rules.d/99-segger-jlink.rules) and ran sudo udevadm trigger so hotplugged J-Link devices automatically receive 0666 permissions.

Configured QEMU Host USB Passthrough:

Configured Lima to pass the USB hardware to the guest by executing limactl start with environment flags or adding qemu.extraArgs to lima.yaml:
        YAML

..code-block:
    qemu:
      extraArgs:
        - "-device"
        - "qemu-xhci,id=xhci"
        - "-device"
        - "usb-host,vendorid=0x1366"

Activated Guest Serial Drivers:

Loaded the cdc_acm kernel module and triggered udevadm inside the guest Ubuntu OS, generating the serial nodes /dev/ttyACM0, /dev/ttyACM1, and /dev/ttyACM2.
Verification: Running limactl shell github-runner lsusb lists ID 1366:xxxx SEGGER System GmbH, and ls -la /dev/ttyACM* displays all three active TTY serial devices inside the VM.



Problem Breakdown & Root Causes
===============================

Fault 1: USB Device Re-Enumeration Disconnects
----------------------------------------------
* **Symptom**: When a SEGGER J-Link probe flashes an embedded MCU or triggers a
  hardware reset, the probe momentarily resets its USB connection. This drops
  the host ``/dev/ttyACM*`` character device nodes and immediately recreates
  them upon re-enumeration.
* **Root Cause**: Standard container runtimes using static device binding
  (``--device /dev/ttyACM0``) bind the device node at container creation time using
  its specific inode. Once the MCU resets and re-enumerates, the original inode
  becomes stale inside the container, causing permission errors or "File not found"
  exceptions during test execution.

Fault 2: Unprivileged Cgroup Access Denials
-------------------------------------------
* **Symptom**: Even when host ``/dev`` nodes were mapped into the container, non-root
  runner processes received ``Permission Denied`` errors when attempting write
  operations on newly created ``/dev/ttyACM*`` nodes.
* **Root Cause**: Default Podman container cgroup access policies restrict unprivileged
  containers from creating (``mknod``), reading (``r``), or writing (``w``) to newly
  generated character device nodes on the host system unless explicitly permitted
  by a cgroup rule.

Fault 3: Security Risks of the Initial Workaround (--privileged)
-----------------------------------------------------------------
* **Symptom**: Running containerized runners with ``--privileged`` restored serial
  access but exposed the host system to administrative compromise.
* **Root Cause**: Full privileged access disables all security capabilities,
  AppArmor/SELinux profiles, and cgroup restrictions, allowing guest runners
  full root control over host kernel interfaces and hardware devices.

Technical Solution Architecture
===============================

To restore persistent, unprivileged serial access across arbitrary USB resets, three
targeted configuration changes were applied:

.. code-block:: text

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
    |  |  Cgroup Rule: --device-cgroup-rule='c 166:* rmw'                        |  |
    |  |  Group Membership: --group-add dialout                                  |  |
    |  |                                                                         |  |
    |  |  Result: Dynamic, persistent write access to all current & future       |  |
    |  |          /dev/ttyACM* ports without container root privileges.          |  |
    |  +-------------------------------------------------------------------------+  |
    +-------------------------------------------------------------------------------+

Key Components of the Fix
-------------------------
1. **Live Passthrough via -v /dev:/dev**:
   Instead of passing individual static device nodes (``--device /dev/ttyACM0``),
   the host's ``/dev`` directory is mounted directly into the runner container.
   This ensures that whenever a USB debug probe re-enumerates and generates a
   new node (e.g., ``/dev/ttyACM1`` or ``/dev/ttyACM2``), the node immediately
   appears inside the container without requiring a container restart.

2. **Scoped Cgroup Rule (--device-cgroup-rule='c 166:* rmw')**:
   Linux major number ``166`` is designated specifically for CDC-ACM serial
   interfaces (``/dev/ttyACM*``).
   The rule ``c 166:* rmw`` breaks down as:

   * ``c``: Character device.
   * ``166``: Major device number for CDC-ACM interfaces.
   * ``*``: Any minor device number (encompassing all serial channels).
   * ``rmw``: Grants Read (``r``), Mknod (``m``), and Write (``w``) access permissions.

   This allows the runner process to access any re-enumerated ACM serial interface
   dynamically while blocking access to all other unapproved host hardware
   (e.g., primary disks, system memory, host input devices).

3. **Secondary Group Mapping (--group-add dialout)**:
   Appends the ``dialout`` group GID to the unprivileged runner user inside the
   container, granting standard Linux user permissions to access serial communications
   hardware.

Ansible Implementation
======================

The updated task in ``deploy_github-runners_lima-vm.yml`` deploys the unprivileged
runner container with scoped permissions:

.. code-block:: yaml

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

Automated health checks in ``diagnose_github-runner_system.yml`` verify serial
write permissions across all assigned devices without requiring target resets
during testing:

.. code-block:: bash

    # Execute end-to-end deployment and run automated USB health diagnostics
    ./system_setup.sh

Expected Health Check Output:

.. code-block:: text

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
