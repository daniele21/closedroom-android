#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE_DIR="$ROOT/tools/probe"
BUILD_DIR="$PROBE_DIR/build"
SRC_DIR="$PROBE_DIR/src"

SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [[ -z "$SDK_ROOT" ]]; then
  echo "error: set ANDROID_SDK_ROOT or ANDROID_HOME" >&2
  exit 2
fi

for cmd in javac jar; do
  command -v "$cmd" >/dev/null || { echo "error: missing $cmd" >&2; exit 2; }
done

ANDROID_JAR="$(find "$SDK_ROOT/platforms" -maxdepth 2 -name android.jar -type f 2>/dev/null | sort -V | tail -n 1)"
D8="$(find "$SDK_ROOT/build-tools" -maxdepth 2 -name d8 -type f 2>/dev/null | sort -V | tail -n 1)"

[[ -n "$ANDROID_JAR" && -f "$ANDROID_JAR" ]] || { echo "error: android.jar not found under $SDK_ROOT/platforms" >&2; exit 2; }
[[ -n "$D8" && -x "$D8" ]] || { echo "error: d8 not found under $SDK_ROOT/build-tools" >&2; exit 2; }

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/classes" "$BUILD_DIR/dex"

mapfile -t SOURCES < <(find "$SRC_DIR" -name '*.java' -type f | sort)
[[ "${#SOURCES[@]}" -gt 0 ]] || { echo "error: no Java sources found" >&2; exit 2; }

javac   -encoding UTF-8   --release 11   -classpath "$ANDROID_JAR"   -d "$BUILD_DIR/classes"   "${SOURCES[@]}"

jar cf "$BUILD_DIR/closedroom-probe-classes.jar" -C "$BUILD_DIR/classes" .
"$D8"   --min-api 31   --lib "$ANDROID_JAR"   --output "$BUILD_DIR/dex"   "$BUILD_DIR/closedroom-probe-classes.jar"

[[ -f "$BUILD_DIR/dex/classes.dex" ]] || { echo "error: d8 did not produce classes.dex" >&2; exit 2; }
jar cf "$BUILD_DIR/closedroom-probe.jar" -C "$BUILD_DIR/dex" classes.dex

echo "built: $BUILD_DIR/closedroom-probe.jar"
echo "android.jar: $ANDROID_JAR"
echo "d8: $D8"
