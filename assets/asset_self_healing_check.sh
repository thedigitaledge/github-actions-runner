#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

export PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

PODMAN_BIN="podman"
if [ -f /run/.containerenv ]; then
  if command -v distrobox-host-exec &>/dev/null; then
    PODMAN_BIN="distrobox-host-exec podman"
  elif command -v flatpak-spawn &>/dev/null; then
    PODMAN_BIN="flatpak-spawn --host podman"
  fi
fi

CONTAINER_NAME="lima-vm-container"
LIMA_VM_NAME="github-runner"

logger -t gh-runner-self-healing "Running automated infrastructure health check..."

if ! $PODMAN_BIN inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | grep -q "true"; then
  logger -t gh-runner-self-healing "Host container $CONTAINER_NAME is down. Triggering full infrastructure rebuild (-a)..."
  ./system_setup.sh -a
  exit 0
fi

VM_STATUS=$($PODMAN_BIN exec -u lima "$CONTAINER_NAME" limactl list "$LIMA_VM_NAME" --format '{{.Status}}' 2>/dev/null || true)
if [[ "$VM_STATUS" != *"Running"* ]]; then
  logger -t gh-runner-self-healing "Lima VM $LIMA_VM_NAME is '$VM_STATUS' (not Running). Triggering full infrastructure restart (-a)..."
  ./system_setup.sh -a
  exit 0
fi

ACTIVE_RUNNERS=$($PODMAN_BIN exec -u lima "$CONTAINER_NAME" limactl shell "$LIMA_VM_NAME" sudo podman ps --format '{{.Names}}' 2>/dev/null || true)

RUNNER_COUNT=$(echo "$ACTIVE_RUNNERS" | grep -c "runner" || true)

if [ "$RUNNER_COUNT" -eq 0 ]; then
  logger -t gh-runner-self-healing "No active runner containers detected inside $LIMA_VM_NAME. Triggering runner recovery (-r)..."
  ./system_setup.sh -r
  exit 0
fi

logger -t gh-runner-self-healing "Infrastructure health check PASSED ($RUNNER_COUNT active runner containers)."
