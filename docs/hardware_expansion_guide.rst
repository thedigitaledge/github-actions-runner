===================================================================
HARDWARE EXPANSION & NEW TARGET ONBOARDING GUIDE
===================================================================

This guide explains how to onboard new target microcontrollers, serial debug probes (e.g., FTDI USB-Serial, ESP32, ST-Link, CMSIS-DAP), and runner instances into the Ansible infrastructure.

-------------------------------------------------------------------
1. IDENTIFYING DEVICE MAJOR NUMBERS & DRIVERS
-------------------------------------------------------------------

When adding a new type of USB debug probe or serial converter:

1. Connect the hardware probe to the host system.
2. Inspect kernel device creation using ``ls -l /dev/tty*`` or ``lsusb``:

   .. code-block:: bash

       ls -l /dev/ttyACM* /dev/ttyUSB* 2>/dev/null

3. Note the major number (the first integer in the device specifications):
   - **CDC-ACM Interfaces** (SEGGER J-Link, nRF DK, Arduino): Major ``166`` (``/dev/ttyACM*``)
   - **FTDI Chips** (FT232R, FT2232H, ESP32 Prog, OpenOCD probes): Major ``188`` (``/dev/ttyUSB*``)
   - **Prolific / CP210x Chips**: Major ``188`` (``/dev/ttyUSB*``)

-------------------------------------------------------------------
2. UPDATING DEPLOYMENT CGROUP RULES
-------------------------------------------------------------------

If your new probe uses FTDI or CP210x serial adapters (Major ``188``), update the container Cgroup rules in ``deploy_github-runners_lima-vm.yml``:

.. code-block:: yaml

    --device-cgroup-rule='c 166:* rmw'
    --device-cgroup-rule='c 188:* rmw'

This permits unprivileged containers to access both ``/dev/ttyACM*`` and ``/dev/ttyUSB*`` interfaces dynamically upon USB re-enumeration.

-------------------------------------------------------------------
3. ADDING RUNNER TARGETS TO `vars/runners.yml`
-------------------------------------------------------------------

Append new target repositories and serial device assignments to ``vars/runners.yml``:

.. code-block:: yaml

    github_runners:
      - owner: "thedigitaledge"
        repo: "tde-esp32-sensor-node"
        name: "bender-esp32-runner"
        labels: "self-hosted,Linux,x64,usb,esp32,cp210x"
        devices:
          - "/dev/ttyUSB0"

-------------------------------------------------------------------
4. DEPLOYING & VERIFYING NEW TARGETS
-------------------------------------------------------------------

1. Test dry-run execution:

   .. code-block:: bash

       ./system_setup.sh --dry-run

2. Apply configuration and deploy the new runner:

   .. code-block:: bash

       ./system_setup.sh

3. Check new runner online registration and serial write access:

   .. code-block:: bash

       ./status.sh
