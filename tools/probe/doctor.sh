#!/usr/bin/env bash
set -euo pipefail

ADB="${ADB:-adb}"
if [[ -n "${ANDROID_SERIAL:-}" ]]; then
  ADB_ARGS=(-s "$ANDROID_SERIAL")
else
  ADB_ARGS=()
fi

for cmd in "$ADB" javac jar; do
  command -v "$cmd" >/dev/null || { echo "error: missing $cmd" >&2; exit 2; }
done

SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
[[ -n "$SDK_ROOT" ]] || { echo "error: set ANDROID_SDK_ROOT or ANDROID_HOME" >&2; exit 2; }

ANDROID_JAR="$(find "$SDK_ROOT/platforms" -maxdepth 2 -name android.jar -type f 2>/dev/null | sort -V | tail -n 1)"
D8="$(find "$SDK_ROOT/build-tools" -maxdepth 2 -name d8 -type f 2>/dev/null | sort -V | tail -n 1)"
[[ -f "$ANDROID_JAR" ]] || { echo "error: android.jar missing" >&2; exit 2; }
[[ -x "$D8" ]] || { echo "error: d8 missing" >&2; exit 2; }

"$ADB" "${ADB_ARGS[@]}" get-state >/dev/null
UID="$("$ADB" "${ADB_ARGS[@]}" shell id -u | tr -d '\r')"
API="$("$ADB" "${ADB_ARGS[@]}" shell getprop ro.build.version.sdk | tr -d '\r')"
MODEL="$("$ADB" "${ADB_ARGS[@]}" shell getprop ro.product.model | tr -d '\r')"
MANUFACTURER="$("$ADB" "${ADB_ARGS[@]}" shell getprop ro.product.manufacturer | tr -d '\r')"
BUILD="$("$ADB" "${ADB_ARGS[@]}" shell getprop ro.build.fingerprint | tr -d '\r')"
ABI="$("$ADB" "${ADB_ARGS[@]}" shell getprop ro.product.cpu.abi | tr -d '\r')"

echo "probe_toolchain=ok"
echo "adb_shell_uid=$UID"
echo "android_api=$API"
echo "manufacturer=$MANUFACTURER"
echo "model=$MODEL"
echo "abi=$ABI"
echo "build_fingerprint=$BUILD"
echo "android_jar=$ANDROID_JAR"
echo "d8=$D8"

if [[ "$UID" != "2000" ]]; then
  echo "error: expected adb shell uid 2000, got $UID" >&2
  exit 3
fi
if (( API < 31 )); then
  echo "error: initial probe supports Android 12/API 31+; got API $API" >&2
  exit 4
fi
