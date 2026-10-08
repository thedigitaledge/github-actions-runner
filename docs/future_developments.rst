===================================================================
FUTURE DEVELOPMENTS & INFRASTRUCTURE ROADMAP
===================================================================

This document outlines the roadmap for future infrastructure developments, resiliency enhancements, build optimizations, and security features for the Containerized Lima KVM & GitHub Actions Runner infrastructure.

-------------------------------------------------------------------
RECENTLY IMPLEMENTED MILESTONES
-------------------------------------------------------------------

* **[COMPLETED] Container Workflow Support**: Enabled podman.socket passthrough allowing "container:" job execution inside workflows.
* **[COMPLETED] Galaxy Collection Refactoring**: Converted container tasks to declarative containers.podman modules with auto-installation via requirements.yml.
* **[COMPLETED] Shared ccache Volume**: Mounted persistent /var/cache/ccache to accelerate embedded firmware compilation.
* **[COMPLETED] Ephemeral Runner Isolation**: Configured --once flag on runner registration for automatic container recycling upon job completion.
* **[COMPLETED] Keyring & Env Vault Resolution**: Implemented .secrets/vault_pass.sh for hierarchical, non-plaintext vault key lookup.
* **[COMPLETED] Persistent Hardware Mapping**: Implemented auto-resolution of /dev/ttyACM* to /dev/serial/by-id/ symlinks with disk persistence back to vars/runners.yml.
* **[COMPLETED] USB Power Cycling**: Integrated uhubctl inside guest VM for VBUS power cycling when hardware freezes occur.
* **[COMPLETED] Hot-Plug Auto-Recovery**: Deployed SEGGER USB udev rules to automatically recover offline runner containers on probe connection.
* **[COMPLETED] Self-Healing Watchdog**: Deployed 15-minute host systemd timer executing 3-tier health checks via self_healing_check.sh.
* **[COMPLETED] Modular Asset Architecture**: Refactored playbooks to pull configurations, templates, and scripts directly from assets/.

-------------------------------------------------------------------
1. SECURITY & ACCESS CONTROL
-------------------------------------------------------------------

1.1 GitHub App Authentication (Replacing PATs)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Replace static Personal Access Tokens (PATs) with GitHub App installation authentication.
* **Architecture Location**: **Guest VM / Playbook Controller Layer**.
* **Rationale**: PATs are tied to individual developer accounts and require periodic manual token rotation. GitHub Apps generate short-lived, repository-scoped installation tokens programmatically.
* **Implementation**:
  1. Store GitHub App ID and RSA private key (.pem) in encrypted vars/vault.yml.
  2. Update [Task 21] in deploy_github-runners_lima-vm.yml to generate a JSON Web Token (JWT) and request short-lived access tokens via POST /app/installations/{installation_id}/access_tokens.

1.2 Fully Rootless Podman Execution inside Guest VM
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Transition guest runner containers from root execution to unprivileged rootless Podman user namespaces.
* **Architecture Location**: **Guest VM / Controller Layer**.
* **Rationale**: Prevents potential container escape vulnerabilities from gaining root privilege inside the Lima guest VM.
* **Implementation**:
  1. Update user configuration inside assets/github-runner.yaml.j2 to configure subuid and subgid mappings for the lima user.
  2. Adjust device permissions for /dev/bus/usb and /dev/serial/by-id/ to grant write access to unprivileged runner user IDs via udev ACLs.

1.3 Automated Hardware Code Signing via PKCS#11 HSM / YubiKey
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Expose host USB Hardware Security Modules (HSMs) or YubiKeys to runner containers for secure boot firmware signing.
* **Architecture Location**: **Hybrid (USB Passthrough on Guest VM; Signing Engine in Runner Container)**.
* **Rationale**: Guarantees production-candidate firmware binaries produced in CI are signed using private keys stored in tamper-proof hardware that never leaves the test bench.
* **Implementation**:
  1. Pass the HSM USB smartcard device node into runner containers via volume/device flags in deploy_github-runners_lima-vm.yml.
  2. Invoke imgtool or OpenSSL via PKCS#11 engine drivers (/usr/lib/x86_64-linux-gnu/pkcs11/) inside the runner container build image.

-------------------------------------------------------------------
2. BUILD PERFORMANCE & CI OPTIMIZATION
-------------------------------------------------------------------

2.1 Pre-Baked Base Runner Container Images
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Eliminate recurring toolchain download overhead during workflow job setup.
* **Architecture Location**: **Runner Container Layer**.
* **Rationale**: Standard runner images download large embedded toolchains (Zephyr SDK, ARM GCC, West, Ninja, CMake) on every job run, wasting bandwidth and adding several minutes to CI runtimes.
* **Implementation**:
  1. Create assets/Runner.Containerfile pre-packaging embedded toolchains and dependencies into a custom base image (e.g., ghcr.io/thedigitaledge/embedded-runner-base:latest).
  2. Update [Task 22] in deploy_github-runners_lima-vm.yml to pull and execute the pre-baked base image.

2.2 Workspace Directory Persistence & Caching
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Cache intermediate build artifacts and Zephyr workspace modules across workflow runs.
* **Architecture Location**: **Hybrid (Persistent Directory on Guest VM; Volume Mount in Runner Container)**.
* **Rationale**: Fetching sub-manifest repositories via `west update` consumes significant network time on clean runs.
* **Implementation**:
  1. Mount persistent host volume /var/cache/zephyr-workspace into runner containers at /gh-runner/workspace-cache.
  2. Configure `west` cache directories to reuse local modules without re-downloading git trees.

2.3 Local On-Premise Binary Artifact Storage (MinIO S3 Sidecar)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Deploy a local, zero-latency S3-compatible object store for caching build binaries (.elf, .hex, .bin) across workflow pipeline stages.
* **Architecture Location**: **Guest VM / Controller Layer**.
* **Rationale**: Bypasses GitHub Actions artifact upload/download bandwidth throttles and storage limits when passing large firmware binaries between compile and flash steps.
* **Implementation**:
  1. Deploy a minio/minio sidecar container alongside Cockpit in deploy_cockpit.yml.
  2. Configure workflow steps to push and pull artifacts locally via `aws s3` or `mc` CLI tools at gigabit speed.

-------------------------------------------------------------------
3. OBSERVABILITY, ALERTING & TELEMETRY
-------------------------------------------------------------------

3.1 Real-Time Webhook Alerting (Slack / Teams / Discord / Matrix)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Send immediate notifications to engineering teams upon hardware disconnects or pipeline failures.
* **Architecture Location**: **Host / Guest VM Controller Layer**.
* **Rationale**: Decreases mean-time-to-detection (MTTD) when physical debug boards disconnect or enter unrecoverable states.
* **Implementation**:
  1. Define webhook_url in encrypted vars/vault.yml.
  2. Update self_healing_check.sh and diagnose_github-runner_system.yml to post JSON payloads to Webhook endpoints whenever hardware checks fail or recovery actions are triggered.

3.2 Prometheus & Grafana Metrics Exporter
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Capture historical telemetry on serial port availability, VM resource utilization, and build job queue durations.
* **Architecture Location**: **Guest VM / Controller Layer**.
* **Rationale**: Provides long-term insights into hardware utilization, probe stability, and infrastructure capacity planning.
* **Implementation**:
  1. Deploy a lightweight prom/node-exporter sidecar container alongside Cockpit in deploy_cockpit.yml.
  2. Expose Prometheus metrics on port 9100 for scraping by central monitoring servers.

3.3 OpenTelemetry & Audit Logging Pipeline
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Stream structured JSON audit logs for container lifecycle events and serial access attempts.
* **Architecture Location**: **Host / Guest VM Controller Layer**.
* **Rationale**: Enforces compliance and auditability for physical hardware bench operations in regulated engineering environments.
* **Implementation**:
  1. Configure journald and Podman log drivers to emit JSON formatted events.
  2. Forward events to Vector or Fluent Bit sidecar containers for ingestion into Elastic/Grafana Loki.

3.4 Live Serial & RTT Console Web Streaming (ser2net / WebSocket Proxy)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Stream real-time microcontroller serial logs and SEGGER RTT console output directly to web browsers or Cockpit panels.
* **Architecture Location**: **Guest VM / Controller Layer**.
* **Rationale**: Gives engineers real-time visibility into target board console outputs during active CI runs without requiring direct SSH or terminal attaches. Ephemeral runner recycling would disconnect active streams if hosted inside containers.
* **Implementation**:
  1. Deploy ser2net or a lightweight WebSocket bridge inside the Lima VM mapped to /dev/serial/by-id/* ports.
  2. Embed live console streaming widgets directly into the Cockpit web interface.

-------------------------------------------------------------------
4. ADVANCED HARDWARE RESILIENCY & CONTROL
-------------------------------------------------------------------

4.1 Hardware Probe Concurrency Locking (flock Mutex)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Prevent race conditions and device lockouts when multiple workflow steps or parallel jobs attempt to flash or inspect the same SEGGER probe simultaneously.
* **Architecture Location**: **Hybrid (Shared Lock File on Guest VM; Mutex Execution in Runner Container)**.
* **Rationale**: Concurrent execution of JLinkExe or nrfjprog on the same physical probe corrupts flashing procedures and crashes active RTT streams.
* **Implementation**:
  1. Bind-mount shared directory /var/lock/HIL into runner containers.
  2. Wrap all hardware flashing and reset scripts inside a `flock` wrapper tied to the probe's serial number (e.g., flock -x /var/lock/HIL/jlink-${SERIAL}.lock -c "nrfjprog ...").

4.2 Targeted Per-Port uhubctl Power Reset Mapping
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Power cycle individual frozen USB ports without disrupting adjacent running debug probes.
* **Architecture Location**: **Guest VM / Controller Layer**.
* **Rationale**: Running global "uhubctl -a cycle" resets power to all connected USB ports simultaneously, which can interrupt active build jobs on neighboring boards.
* **Implementation**:
  1. Extend vars/runners.yml with physical USB topology metadata (e.g., usb_location: "1-1.2", usb_port: "2").
  2. Update diagnostic and recovery tasks to target specific hub locations (e.g., uhubctl -l 1-1.2 -p 2 -a cycle).

4.3 Simulated USB Fault Injection & Testing Harness
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Provide automated integration tests that simulate hardware disconnects and VBUS power drops.
* **Architecture Location**: **Guest VM / Controller Layer**.
* **Rationale**: Ensures hot-plug recovery rules and self-healing scripts function correctly without requiring physical cable unplugging.
* **Implementation**:
  1. Create test_fault_injection.sh using uhubctl to toggle port power off for 5 seconds and measure recovery latency.
  2. Verify that self_healing_check.sh successfully detects the offline state and recovers the runner container within 15 minutes.

4.4 Multi-Probe SEGGER J-Link Serial Multiplexing
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Support simultaneous flashing and RTT logging across 4+ attached J-Link probes without USB bandwidth saturation.
* **Architecture Location**: **Guest VM / Controller Layer**.
* **Rationale**: High-density hardware integration benches require isolated USB endpoints to prevent bulk transfer drops.
* **Implementation**:
  1. Configure USB host controller isolation parameters in assets/github-runner.yaml.j2.
  2. Bind individual QEMU USB host passthrough definitions for each SEGGER vendor/product serial pair.

-------------------------------------------------------------------
5. EMBEDDED HIL TESTING & PROTOCOL VALIDATION
-------------------------------------------------------------------

5.1 Energy Telemetry & Power Regression Capture (Nordic PPK2 / Joulescope)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Automatically measure and record microamp-level power consumption profiles during CI firmware execution runs.
* **Architecture Location**: **Hybrid (USB Passthrough on Guest VM; Trace Parsing in Runner Container)**.
* **Rationale**: Automatically catches firmware power consumption regressions (such as missed deep-sleep states or floating GPIO pins) before PRs are merged.
* **Implementation**:
  1. Pass Nordic Power Profiler Kit II (PPK2) or Joulescope USB nodes into guest VM runner containers via deploy_github-runners_lima-vm.yml.
  2. Execute automated Python measurement scripts inside the runner container during workflow jobs and attach power trace plots (.png / .csv) directly to GitHub Actions build artifacts.

5.2 Logic Analyzer Protocol Decoding (sigrok / PulseView Integration)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Automatically capture and decode hardware bus transactions (I2C, SPI, UART, CAN, SWD) during CI test executions.
* **Architecture Location**: **Hybrid (USB Logic Analyzer Passthrough on Guest VM; Decoder in Runner Container)**.
* **Rationale**: Software assertions on microcontrollers can miss signal timing issues, glitching, or bus protocol violations.
* **Implementation**:
  1. Pass low-cost USB logic analyzers (Saleae, FX2LP 24MHz probes) into runner containers via /dev/bus/usb.
  2. Execute `sigrok-cli` inside the runner container test step to capture digital traces and automatically assert protocol correctness in CI.

5.3 Automotive & Industrial SocketCAN Bridge Passthrough
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Expose host USB-to-CAN adapters (CandleLight, Kvaser, PEAK PCAN) directly into runner containers for CAN/CAN-FD testing.
* **Architecture Location**: **Guest VM / Controller Layer (Kernel Drivers & Network Interface)**.
* **Rationale**: Kernel CAN drivers (can, can_raw, vcan) and network interface instantiation cannot be executed inside unprivileged containers.
* **Implementation**:
  1. Enable SocketCAN drivers in the guest VM kernel via assets/github-runner.yaml.j2 and initialize interfaces (can0, vcan0) via `ip link`.
  2. Pass the network interface to runner containers, allowing Python scripts (`python-can`) or `candump` to send and receive frames directly.

5.4 Remote Hardware Bench Debug Tunneling (J-Link Remote Server)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Allow developers to remotely attach desktop IDEs (Ozone, VS Code, IAR, Keil) to physical bench probes without interrupting active CI runners.
* **Architecture Location**: **Guest VM / Controller Layer**.
* **Rationale**: Ephemeral container destructions (`--once`) would abruptly terminate active IDE debugging sessions when a job completes.
* **Implementation**:
  1. Expose `JLinkRemoteServerCLExe` as a persistent background service inside the Lima VM.
  2. Route port 19020 through Cockpit or SSH tunneling so remote developers can connect GDB/Ozone to localhost:19020 to debug live MCUs.

5.5 Programmable SCPI Power Supply Control (Brownout Testing)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Programmatically sweep target supply voltages (e.g., 1.8V to 3.6V) via SCPI USB/serial bench power supplies during regression runs.
* **Architecture Location**: **Hybrid (Serial Passthrough on Guest VM; Test Script in Runner Container)**.
* **Rationale**: Validates MCU brownout reset (BOR) circuits, power-on reset (POR) logic, and low-voltage flash programming stability.
* **Implementation**:
  1. Pass SCPI power supply serial nodes (/dev/serial/by-id/*) into runner containers.
  2. Execute Python `pyvisa` scripts inside the runner container to adjust VDD dynamically and verify target survival.

5.6 Computer Vision HIL UI & LED Verification (USB Camera + OpenCV/OCR)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Automatically verify target board display outputs (e-paper, LCD, OLED) and status LED blink patterns using a USB webcam.
* **Architecture Location**: **Hybrid (Video Node Passthrough on Guest VM; OpenCV/OCR in Runner Container)**.
* **Rationale**: Isolates heavy computer vision dependencies (OpenCV, Tesseract OCR) to specific runner container images rather than bloating the base guest VM.
* **Implementation**:
  1. Pass USB video devices (/dev/video0) into runner containers.
  2. Run OpenCV and `tesseract` OCR inside runner container scripts to capture frame images and assert displayed text or LED pulse timing.

5.7 Programmable RF Attenuation & Shielded Enclosure Control
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Control USB RF attenuators and RF-shielded box relays during wireless IoT testing (BLE, Thread, Zigbee, Wi-Fi).
* **Architecture Location**: **Hybrid (USB Node Passthrough on Guest VM; RF Control Script in Runner Container)**.
* **Rationale**: Tests wireless link budget, signal degradation handling, and automatic Mesh node failover without moving physical hardware.
* **Implementation**:
  1. Connect USB-controlled RF attenuators (Mini-Circuits, Vaunix Lab Brick) to the guest VM.
  2. Execute Python test drivers in runner container workflow steps to sweep attenuation from 0dB to -90dB and measure packet error rates (PER).

5.8 Dynamic Hardware Label Dispatcher (Board Farm Router)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Automatically detect connected target microcontroller boards and dynamically update GitHub Actions runner labels in real time.
* **Architecture Location**: **Guest VM / Controller Layer**.
* **Rationale**: Operates outside runner container lifecycles to manage GitHub API runner registrations continuously as physical test bench boards are swapped.
* **Implementation**:
  1. Deploy a background daemon on the guest VM that queries nrfjprog --ids / JLinkExe to identify attached target MCU signatures (e.g., nRF5340, nRF52840, STM32F4).
  2. Invoke the GitHub REST API to update the corresponding runner container's labels dynamically.

-------------------------------------------------------------------
6. COST & RESOURCE MANAGEMENT
-------------------------------------------------------------------

6.1 Dynamic Auto-Scaling of Runner VM Memory & CPU Resources
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Automatically scale Lima VM CPU/RAM allocation based on workload demand.
* **Architecture Location**: **Host / Guest VM Controller Layer**.
* **Rationale**: Reduces resource footprint on developer workstations during idle periods while providing maximum compute during heavy Zephyr compilation jobs.
* **Implementation**:
  1. Define dynamic variables in vars/runners.yml for minimum and maximum vCPU / RAM limits.
  2. Utilize limactl configuration hooks to adjust VM resource limits prior to execution.

6.2 Automated Disk Space & Podman Image Pruning
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Prevent disk exhaustion inside the Lima VM caused by dangling image layers or build caches.
* **Architecture Location**: **Guest VM / Controller Layer**.
* **Rationale**: Running workflow container steps generates untagged Podman images that accumulate over time.
* **Implementation**:
  1. Add a daily scheduled systemd timer task executing `podman system prune -af --volumes` inside the guest VM.
  2. Set maximum cache size thresholds for /var/cache/ccache with automatic cleanup triggers.

-------------------------------------------------------------------
7. DEVELOPER EXPERIENCE & TOOLING
-------------------------------------------------------------------

7.1 Interactive Terminal User Interface (TUI / CLI Management)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Provide an interactive terminal dashboard for managing runners, viewing logs, and inspecting serial ports.
* **Architecture Location**: **Host System Level**.
* **Rationale**: Simplifies everyday developer interactions with the runner infrastructure without requiring knowledge of raw Ansible or Podman commands.
* **Implementation**:
  1. Create an interactive wrapper `./manage.sh` using `dialog` or `whiptail` to present menus for restarting runners, triggering USB cycles, or tailing logs.

7.2 Multi-Architecture Runner VM Support (ARM64 & x86_64)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* **Objective**: Allow identical deployment scripts to run seamlessly on Apple Silicon (M-series macOS) and Linux x86_64 hosts.
* **Architecture Location**: **Host / Guest VM Controller Layer**.
* **Rationale**: Enables developers on ARM64 macOS machines to run local HIL test benches using identical playbook workflows.
* **Implementation**:
  1. Parameterize QEMU architecture settings (`qemu-system-aarch64` vs `qemu-system-x86_64`) dynamically in assets/lima-vm-container.service.j2 based on host facts.
