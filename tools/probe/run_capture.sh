#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE_DIR="$ROOT/tools/probe"
JAR="$PROBE_DIR/build/closedroom-probe.jar"
REMOTE_JAR="/data/local/tmp/closedroom-probe.jar"
DEVICE_DIR="/sdcard/Download/ClosedRoomProbe"

SOURCE="${1:-voice-call}"
SECONDS="${2:-60}"
CHANNELS="${3:-stereo}"

case "$SOURCE" in
  voice-call|voice-uplink|voice-downlink|voice-communication|mic|remote-submix) ;;
  *) echo "error: unsupported source '$SOURCE'" >&2; exit 2 ;;
esac
[[ "$SECONDS" =~ ^[0-9]+$ ]] && (( SECONDS >= 1 && SECONDS <= 180 )) || {
  echo "error: seconds must be 1..180" >&2
  exit 2
}
case "$CHANNELS" in mono|stereo) ;; *) echo "error: channels must be mono or stereo" >&2; exit 2 ;; esac

ADB="${ADB:-adb}"
if [[ -n "${ANDROID_SERIAL:-}" ]]; then
  ADB_ARGS=(-s "$ANDROID_SERIAL")
else
  ADB_ARGS=()
fi

"$PROBE_DIR/doctor.sh"
[[ -f "$JAR" ]] || "$PROBE_DIR/build_probe.sh"

STAMP="$(date +%Y%m%d-%H%M%S)"
DEVICE_WAV="$DEVICE_DIR/closedroom-${SOURCE}-${CHANNELS}-${STAMP}.wav"

"$ADB" "${ADB_ARGS[@]}" shell mkdir -p "$DEVICE_DIR"
"$ADB" "${ADB_ARGS[@]}" push "$JAR" "$REMOTE_JAR" >/dev/null

echo "== probe identity =="
"$ADB" "${ADB_ARGS[@]}" shell env CLASSPATH="$REMOTE_JAR" app_process / com.closedroom.probe.CallAudioProbe info

echo
echo "== capture =="
echo "source=$SOURCE seconds=$SECONDS channels=$CHANNELS"
echo "Keep the call audible and alternate short fixed phrases between local and remote speakers."
"$ADB" "${ADB_ARGS[@]}" shell env CLASSPATH="$REMOTE_JAR" app_process / com.closedroom.probe.CallAudioProbe   record   --source "$SOURCE"   --seconds "$SECONDS"   --sample-rate 48000   --channels "$CHANNELS"   --output "$DEVICE_WAV"

"$ADB" "${ADB_ARGS[@]}" shell ls -lh "$DEVICE_WAV"
"$ADB" "${ADB_ARGS[@]}" shell am broadcast   -a android.intent.action.MEDIA_SCANNER_SCAN_FILE   -d "file://$DEVICE_WAV" >/dev/null 2>&1 || true

"$ADB" "${ADB_ARGS[@]}" shell rm -f "$REMOTE_JAR"

echo
echo "Capture stayed on the phone."
echo "Inspect locally in Files > Downloads > ClosedRoomProbe:"
echo "  $DEVICE_WAV"
echo "After inspection, run tools/probe/cleanup.sh to delete probe audio."
