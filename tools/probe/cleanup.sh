#!/usr/bin/env bash
set -euo pipefail

ADB="${ADB:-adb}"
if [[ -n "${ANDROID_SERIAL:-}" ]]; then
  ADB_ARGS=(-s "$ANDROID_SERIAL")
else
  ADB_ARGS=()
fi

REMOTE_JAR="/data/local/tmp/closedroom-probe.jar"
DEVICE_DIR="/sdcard/Download/ClosedRoomProbe"

"$ADB" "${ADB_ARGS[@]}" shell rm -f "$REMOTE_JAR"
"$ADB" "${ADB_ARGS[@]}" shell rm -rf "$DEVICE_DIR"

echo "removed privileged probe payload and all ClosedRoomProbe audio from the device"
