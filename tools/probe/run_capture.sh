#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE_DIR="$ROOT/tools/probe"
JAR="$PROBE_DIR/build/closedroom-probe.jar"
REMOTE_JAR="/data/local/tmp/closedroom-probe.jar"
DEVICE_DIR="/sdcard/Download/ClosedRoomProbe"

SOURCE="${1:-voice-call}"
DURATION_SECONDS="${2:-60}"
CHANNELS="${3:-stereo}"

case "$SOURCE" in
  voice-call|voice-uplink|voice-downlink|voice-communication|mic|remote-submix) ;;
  *) echo "error: unsupported source '$SOURCE'" >&2; exit 2 ;;
esac
[[ "$DURATION_SECONDS" =~ ^[0-9]+$ ]] && (( DURATION_SECONDS >= 1 && DURATION_SECONDS <= 180 )) || {
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

DEVICE_WAV=""
CAPTURE_SUCCEEDED=0
CAPTURE_PID=""
WATCHDOG_PID=""

cleanup_remote() {
  set +e

  if [[ -n "$WATCHDOG_PID" ]]; then
    kill "$WATCHDOG_PID" >/dev/null 2>&1 || true
    wait "$WATCHDOG_PID" >/dev/null 2>&1 || true
  fi

  if [[ -n "$CAPTURE_PID" ]]; then
    kill "$CAPTURE_PID" >/dev/null 2>&1 || true
    wait "$CAPTURE_PID" >/dev/null 2>&1 || true
  fi

  "$ADB" "${ADB_ARGS[@]}" shell "pkill -f '[c]om.closedroom.probe.CallAudioProbe' >/dev/null 2>&1 || true" >/dev/null 2>&1 || true
  "$ADB" "${ADB_ARGS[@]}" shell rm -f "$REMOTE_JAR" >/dev/null 2>&1 || true

  if [[ "$CAPTURE_SUCCEEDED" != "1" && -n "$DEVICE_WAV" ]]; then
    "$ADB" "${ADB_ARGS[@]}" shell rm -f "$DEVICE_WAV" >/dev/null 2>&1 || true
  fi
}

trap cleanup_remote EXIT INT TERM HUP

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
echo "source=$SOURCE seconds=$DURATION_SECONDS channels=$CHANNELS"
echo "Keep the call audible and alternate short fixed phrases between local and remote speakers."

"$ADB" "${ADB_ARGS[@]}" shell env CLASSPATH="$REMOTE_JAR" app_process / com.closedroom.probe.CallAudioProbe \
  record \
  --source "$SOURCE" \
  --seconds "$DURATION_SECONDS" \
  --sample-rate 48000 \
  --channels "$CHANNELS" \
  --output "$DEVICE_WAV" &
CAPTURE_PID=$!

(
  sleep $((DURATION_SECONDS + 15))
  if kill -0 "$CAPTURE_PID" >/dev/null 2>&1; then
    echo "error: capture exceeded host deadline; terminating" >&2
    kill "$CAPTURE_PID" >/dev/null 2>&1 || true
  fi
) &
WATCHDOG_PID=$!

set +e
wait "$CAPTURE_PID"
CAPTURE_STATUS=$?
set -e
CAPTURE_PID=""

kill "$WATCHDOG_PID" >/dev/null 2>&1 || true
wait "$WATCHDOG_PID" >/dev/null 2>&1 || true
WATCHDOG_PID=""

if [[ "$CAPTURE_STATUS" -ne 0 ]]; then
  echo "error: probe capture failed with status $CAPTURE_STATUS" >&2
  exit "$CAPTURE_STATUS"
fi

"$ADB" "${ADB_ARGS[@]}" shell ls -lh "$DEVICE_WAV"
"$ADB" "${ADB_ARGS[@]}" shell am broadcast \
  -a android.intent.action.MEDIA_SCANNER_SCAN_FILE \
  -d "file://$DEVICE_WAV" >/dev/null 2>&1 || true

CAPTURE_SUCCEEDED=1

echo
echo "Capture stayed on the phone."
echo "Inspect locally in Files > Downloads > ClosedRoomProbe:"
echo "  $DEVICE_WAV"
echo "After inspection, run tools/probe/cleanup.sh to delete probe audio."
