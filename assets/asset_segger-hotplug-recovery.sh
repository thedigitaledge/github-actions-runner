#!/bin/bash
logger -t segger-hotplug "SEGGER J-Link probe hot-plug detected. Refreshing udev and recovering offline runners..."
udevadm control --reload-rules && udevadm trigger
for container in $(podman ps -a --filter "ancestor=ghcr.io/actions/actions-runner:latest" --format "{{.Names}}"); do
  if ! podman ps --format "{{.Names}}" | grep -q "^${container}$"; then
    logger -t segger-hotplug "Restarting offline runner container: ${container}"
    podman restart "${container}" || true
  fi
done
