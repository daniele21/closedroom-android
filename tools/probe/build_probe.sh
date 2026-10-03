#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE_DIR="$ROOT/tools/probe"
BUILD_DIR="$PROBE_DIR/build"
SRC_DIR="$PROBE_DIR/src"

SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
PLATFORM_API="${ANDROID_PLATFORM_API:-35}"
BUILD_TOOLS_VERSION="${ANDROID_BUILD_TOOLS_VERSION:-35.0.0}"

if [[ -z "$SDK_ROOT" ]]; then
  echo "error: set ANDROID_SDK_ROOT or ANDROID_HOME" >&2
  exit 2
fi

for cmd in javac jar; do
  command -v "$cmd" >/dev/null || { echo "error: missing $cmd" >&2; exit 2; }
done

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

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/classes" "$BUILD_DIR/dex"

SOURCES=()
while IFS= read -r source; do
  SOURCES+=("$source")
done < <(find "$SRC_DIR" -name '*.java' -type f | sort)

[[ "${#SOURCES[@]}" -gt 0 ]] || { echo "error: no Java sources found" >&2; exit 2; }

javac \
  -encoding UTF-8 \
  --release 11 \
  -classpath "$ANDROID_JAR" \
  -d "$BUILD_DIR/classes" \
  "${SOURCES[@]}"

jar cf "$BUILD_DIR/closedroom-probe-classes.jar" -C "$BUILD_DIR/classes" .
"$D8" \
  --min-api 31 \
  --lib "$ANDROID_JAR" \
  --output "$BUILD_DIR/dex" \
  "$BUILD_DIR/closedroom-probe-classes.jar"

[[ -f "$BUILD_DIR/dex/classes.dex" ]] || { echo "error: d8 did not produce classes.dex" >&2; exit 2; }
jar cf "$BUILD_DIR/closedroom-probe.jar" -C "$BUILD_DIR/dex" classes.dex

echo "built: $BUILD_DIR/closedroom-probe.jar"
echo "platform_api: $PLATFORM_API"
echo "build_tools: $BUILD_TOOLS_VERSION"
