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
PLATFORM_API="${ANDROID_PLATFORM_API:-35}"
BUILD_TOOLS_VERSION="${ANDROID_BUILD_TOOLS_VERSION:-35.0.0}"

[[ -n "$SDK_ROOT" ]] || { echo "error: set ANDROID_SDK_ROOT or ANDROID_HOME" >&2; exit 2; }

ANDROID_JAR="$SDK_ROOT/platforms/android-$PLATFORM_API/android.jar"
D8="$SDK_ROOT/build-tools/$BUILD_TOOLS_VERSION/d8"

[[ -f "$ANDROID_JAR" ]] || {
  echo "error: missing $ANDROID_JAR" >&2
  echo "install: sdkmanager \"platforms;android-$PLATFORM_API\"" >&2
  exit 2
}
[[ -x "$D8" ]] || {
  echo "error: missing $D8" >&2
  echo "install: sdkmanager \"build-tools;$BUILD_TOOLS_VERSION\"" >&2
  exit 2
}

"$ADB" "${ADB_ARGS[@]}" get-state >/dev/null
UID_VALUE="$("$ADB" "${ADB_ARGS[@]}" shell id -u | tr -d '\r')"
API="$("$ADB" "${ADB_ARGS[@]}" shell getprop ro.build.version.sdk | tr -d '\r')"
MODEL="$("$ADB" "${ADB_ARGS[@]}" shell getprop ro.product.model | tr -d '\r')"
MANUFACTURER="$("$ADB" "${ADB_ARGS[@]}" shell getprop ro.product.manufacturer | tr -d '\r')"
BUILD="$("$ADB" "${ADB_ARGS[@]}" shell getprop ro.build.fingerprint | tr -d '\r')"
ABI="$("$ADB" "${ADB_ARGS[@]}" shell getprop ro.product.cpu.abi | tr -d '\r')"

echo "probe_toolchain=ok"
echo "adb_shell_uid=$UID_VALUE"
echo "android_api=$API"
echo "manufacturer=$MANUFACTURER"
echo "model=$MODEL"
echo "abi=$ABI"
echo "build_fingerprint=$BUILD"
echo "compile_platform_api=$PLATFORM_API"
echo "compile_build_tools=$BUILD_TOOLS_VERSION"

if [[ "$UID_VALUE" != "2000" ]]; then
  echo "error: expected adb shell uid 2000, got $UID_VALUE" >&2
  exit 3
fi
if (( API < 31 )); then
  echo "error: initial probe supports Android 12/API 31+; got API $API" >&2
  exit 4
fi
