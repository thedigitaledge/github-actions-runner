=======================================================
Lima VM GitHub Runners & Cockpit Ansible Infrastructure
=======================================================

Architecture Overview
---------------------
This infrastructure provisions containerized GitHub Actions self-hosted runners inside a Lima KVM virtual machine, deploys the Cockpit web management console, and performs automated hardware and system health diagnostics.

Key architectural highlights include:

* **Host Container Isolation**: Runs a Fedora-based container (``lima-vm-container``) on the host system to house the Lima KVM daemon.
* **Lima KVM Virtual Machine**: Runs a lightweight Ubuntu virtual machine (``github-runner``) inside the container via QEMU.
* **Guest Podman Containers**: Executes individual GitHub Actions runner containers inside the Lima VM, isolated from each other.
* **Dynamic USB CDC-ACM Passthrough**: Mounts live ``/dev`` into runner containers with Cgroup rules (``c 166:* rmw``) to ensure persistent write permissions for SEGGER J-Link debugging probes across resets and re-enumerations.
* **Management Console**: Deploys a Cockpit container to provide web-based multi-host management and monitoring.

Repository Structure
--------------------

.. code-block:: text

    .
    ├── ansible.cfg                          # Ansible configuration settings
    ├── inventory.ini                        # Target host definition (localhost)
    ├── system_setup.sh                      # Master setup and wrapper script
    ├── deploy_github-runners_lima-vm.yml    # Playbook for Lima VM and GitHub Runners
    ├── deploy_cockpit.yml                   # Playbook for Cockpit management console
    ├── diagnose_github-runner_system.yml    # Diagnostic health check playbook
    ├── pyproject.toml                       # Python package dependencies
    ├── vars/
    │   ├── runners.yml                      # GitHub runner target configurations
    │   └── vault.yml                        # Vault-encrypted secrets (PAT tokens)
    └── .secrets/
        └── ansible_vault_pass               # Vault password file

Initial Setup & Configuration
-----------------------------

1. **Vault Password Configuration**:
   Create the vault password file in ``.secrets/ansible_vault_pass``:

   .. code-block:: bash

       mkdir -p .secrets
       echo "your-vault-password" > .secrets/ansible_vault_pass
       chmod 600 .secrets/ansible_vault_pass

2. **Encrypted Vault Variables**:
   Ensure ``vars/vault.yml`` contains your encrypted GitHub Personal Access Token (PAT):

   .. code-block:: yaml

       vault_github_pat: "ghp_your_personal_access_token"

Configure Runner Target Specifications
--------------------------------------
Define target repositories, runner names, labels, and assigned serial devices in ``vars/runners.yml``:

.. code-block:: yaml

    ---
    github_runners:
      - owner: "thedigitaledge"
        repo: "tde-zephyr-smartmesh-ip"
        name: "bender-smartmesh-ip-pca10095-runner"
        labels: "self-hosted,Linux,x64,usb,nrf5340dk,pca10095,iks01a2"
        devices:
          - "/dev/ttyACM0"
          - "/dev/ttyACM1"
          - "/dev/ttyACM2"

      - owner: "thedigitaledge"
        repo: "tde-mote-firmware"
        name: "bender-mote-firmware-pca10095-runner"
        labels: "self-hosted,Linux,x64,usb,nrf5340dk,pca10095,iks01a2"
        devices:
          - "/dev/ttyACM0"
          - "/dev/ttyACM1"
          - "/dev/ttyACM2"

Quick Start
-----------
Run the master setup script to build dependencies, deploy containers, and run health checks:

.. code-block:: bash

    ./system_setup.sh

Command Reference
-----------------

System Setup Script
~~~~~~~~~~~~~~~~~~~
The ``system_setup.sh`` script manages virtual environment setup, installs dependencies, and runs playbooks in sequence:

.. code-block:: bash

    # Dry-run / Check mode (preview changes across all playbooks)
    ./system_setup.sh --dry-run

    # Full deployment and health diagnostics
    ./system_setup.sh

    # Force re-creation of runner containers
    ./system_setup.sh -r

    # Run in verbose mode
    ./system_setup.sh -v

    # Validate playbook syntax only
    ./system_setup.sh -s

    # View all available CLI flags
    ./system_setup.sh -h

Standalone Playbook Execution
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Run individual playbooks directly using ``ansible-playbook``:

.. code-block:: bash

    # Deploy GitHub runners only
    ansible-playbook deploy_github-runners_lima-vm.yml

    # Deploy Cockpit console only
    ansible-playbook deploy_cockpit.yml

    # Run system diagnostics
    ansible-playbook diagnose_github-runner_system.yml

Serial Device Access & USB Passthrough
--------------------------------------
To preserve write access when SEGGER J-Link boards re-enumerate during target resets or flashing:

1. Live ``/dev`` mounting is configured using ``-v /dev:/dev``.
2. Granular device permissions are granted to CDC-ACM serial devices (Major `166`) without requiring full container privileges:

   .. code-block:: yaml

       --device-cgroup-rule='c 166:* rmw'

Configuration Files
-------------------

* **ansible.cfg**: Configures inventory paths, vault password file locations, default callbacks, and suppresses Python interpreter discovery warnings (``interpreter_python = auto_silent``).
* **inventory.ini**: Defines the local host target (``localhost ansible_connection=local``).
* **vars/runners.yml**: Defines runner repository targets, names, labels, and device assignments.
* **vars/vault.yml**: Stores encrypted GitHub Personal Access Tokens and runner secrets.
