===================================================================
OPERATIONS RUNBOOK & TROUBLESHOOTING GUIDE
===================================================================

This runbook covers Day-2 maintenance, service monitoring, log collection, credential rotation, and troubleshooting procedures for the Containerized Lima VM & GitHub Actions Runner infrastructure.

-------------------------------------------------------------------
1. DAY-2 MAINTENANCE & DAILY OPERATIONS
-------------------------------------------------------------------

1.1 Checking Infrastructure Health
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Use ``status.sh`` for an instantaneous health and registration check:

.. code-block:: bash

    ./status.sh

To run full hardware access diagnostics:

.. code-block:: bash

    ansible-playbook diagnose_github-runner_system.yml

1.2 Secret & Token Rotation (GitHub PAT)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
When rotating your GitHub Personal Access Token (PAT):

1. Edit the encrypted vault variable file:

   .. code-block:: bash

       ansible-vault edit vars/vault.yml --vault-password-file .secrets/ansible_vault_pass

2. Update the token string:

   .. code-block:: yaml

       github_pat: "ghp_NEW_TOKEN_HERE"

3. Re-deploy the runner containers to apply the updated token:

   .. code-block:: bash

       ./system_setup.sh -r

1.3 Managing Host User Session Lingering
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
To ensure Lima VM and Podman containers remain active after host SSH logout:

.. code-block:: bash

    loginctl enable-linger $USER
    loginctl show-user $USER | grep Linger

-------------------------------------------------------------------
2. LOG COLLECTION & SERVICE INSPECTION
-------------------------------------------------------------------

2.1 Host Container Logs (Lima VM Engine)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Inspect logs for the top-level container housing the Lima daemon:

.. code-block:: bash

    podman logs -f lima-vm-container

2.2 Guest VM Logs & Serial Output
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Access the guest Lima VM shell directly:

.. code-block:: bash

    podman exec -it -u lima lima-vm-container limactl shell github-runner

From inside the VM shell, inspect systemd services or guest kernel messages:

.. code-block:: bash

    sudo dmesg -w | grep -i tty
    journalctl -u podman -f

2.3 Runner Container Logs
~~~~~~~~~~~~~~~~~~~~~~~~~
To inspect GitHub runner agent execution logs inside the guest VM:

.. code-block:: bash

    podman exec -u lima lima-vm-container limactl shell github-runner \
      sudo podman logs -f bender-smartmesh-ip-pca10095-runner

-------------------------------------------------------------------
3. TROUBLESHOOTING PROCEDURES
-------------------------------------------------------------------

3.1 Fault: Runner Appears "Offline" in GitHub UI
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Symptom**: Runner shows offline status on GitHub, but ``podman ps`` shows container running.
* **Resolution Steps**:
  1. Verify outbound network connectivity from inside the Lima VM:

     .. code-block:: bash

         podman exec -u lima lima-vm-container limactl shell github-runner curl -I https://api.github.com

  2. Re-register the runner container with a fresh token using the recreate flag:

     .. code-block:: bash

         ./system_setup.sh -r

3.2 Fault: Serial Port Permission Denied (`/dev/ttyACM*`)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Symptom**: Firmware flashing fails with `Permission denied` when opening `/dev/ttyACM0`.
* **Resolution Steps**:
  1. Run the diagnostic sweep:

     .. code-block:: bash

         ansible-playbook diagnose_github-runner_system.yml

  2. Confirm the host `/dev` directory is mounted and the Cgroup rule is applied:

     .. code-block:: bash

         podman exec -u lima lima-vm-container limactl shell github-runner \
           sudo podman inspect bender-smartmesh-ip-pca10095-runner --format '{{.HostConfig.DeviceCgroupRules}}'

     Expected output: ``[c 166:* rmw]``

3.3 Fault: Stale Container Storage / Disk Full
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Symptom**: Podman fails to pull runner images or start containers due to missing disk space inside Lima VM.
* **Resolution Steps**:
  1. Prune unused Podman images and containers inside the Lima VM:

     .. code-block:: bash

         podman exec -u lima lima-vm-container limactl shell github-runner sudo podman system prune -a --volumes -f

3.4 Fault: Lima VM Fails to Start or Times Out
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Symptom**: `limactl list` reports status as `Stopped` or `Broken`.
* **Resolution Steps**:
  1. Force restart the host container and Lima VM:

     .. code-block:: bash

         podman restart lima-vm-container
         podman exec -u lima lima-vm-container limactl start github-runner
