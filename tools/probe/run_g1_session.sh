#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE_DIR="$ROOT/tools/probe"
EVIDENCE_DIR="$PROBE_DIR/evidence/local"

SOURCE="${G1_SOURCE:-voice-call}"
DURATION_SECONDS="${G1_DURATION_SECONDS:-60}"
CHANNELS="${G1_CHANNELS:-stereo}"
ROUTE="${G1_ROUTE:-earpiece}"
CARRIER_MODE="${G1_CARRIER_MODE:-unknown}"
SCREEN_STATE="${G1_SCREEN_STATE:-foreground}"
RUNS="${G1_RUNS:-3}"

case "$SOURCE" in
  voice-call|voice-uplink|voice-downlink|voice-communication|mic|remote-submix) ;;
  *) echo "error: unsupported G1_SOURCE '$SOURCE'" >&2; exit 2 ;;
esac
[[ "$DURATION_SECONDS" =~ ^[0-9]+$ ]] && (( DURATION_SECONDS >= 60 && DURATION_SECONDS <= 120 )) || {
  echo "error: G1_DURATION_SECONDS must be 60..120 for acceptance evidence" >&2
  exit 2
}
case "$CHANNELS" in mono|stereo) ;; *) echo "error: G1_CHANNELS must be mono or stereo" >&2; exit 2 ;; esac
case "$ROUTE" in earpiece|speaker|headset|bluetooth) ;; *) echo "error: G1_ROUTE must be earpiece|speaker|headset|bluetooth" >&2; exit 2 ;; esac
case "$CARRIER_MODE" in volte|vowifi|other|unknown) ;; *) echo "error: G1_CARRIER_MODE must be volte|vowifi|other|unknown" >&2; exit 2 ;; esac
case "$SCREEN_STATE" in foreground|screen-off|background) ;; *) echo "error: G1_SCREEN_STATE must be foreground|screen-off|background" >&2; exit 2 ;; esac
[[ "$RUNS" =~ ^[0-9]+$ ]] && (( RUNS >= 1 && RUNS <= 5 )) || {
  echo "error: G1_RUNS must be 1..5" >&2
  exit 2
}

ADB="${ADB:-adb}"
if [[ -n "${ANDROID_SERIAL:-}" ]]; then
  ADB_ARGS=(-s "$ANDROID_SERIAL")
else
  ADB_ARGS=()
fi

mkdir -p "$EVIDENCE_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
EVIDENCE_FILE="$EVIDENCE_DIR/g1-${ROUTE}-${STAMP}.md"

cleanup_on_exit() {
  set +e
  "$PROBE_DIR/cleanup.sh" >/dev/null 2>&1 || true
}
trap cleanup_on_exit EXIT INT TERM HUP

prompt_enum() {
  local prompt="$1"
  shift
  local answer
  while true; do
    printf "%s" "$prompt"
    IFS= read -r answer
    for allowed in "$@"; do
      if [[ "$answer" == "$allowed" ]]; then
        printf "%s" "$answer"
        return 0
      fi
    done
    echo "Invalid value. Allowed: $*" >&2
  done
}

echo "ClosedRoom G1 physical-device session"
echo "====================================="
echo "source=$SOURCE duration=$DURATION_SECONDS channels=$CHANNELS route=$ROUTE carrier_mode=$CARRIER_MODE screen_state=$SCREEN_STATE runs=$RUNS"
echo
echo "Privacy boundary: audio remains on the phone. This script writes technical/verdict metadata only."
echo

"$PROBE_DIR/doctor.sh"
"$PROBE_DIR/build_probe.sh"
"$PROBE_DIR/cleanup.sh"

REVISION="$(git -C "$ROOT" rev-parse HEAD)"
UID_VALUE="$("$ADB" "${ADB_ARGS[@]}" shell id -u | tr -d '\r')"
SELINUX="$("$ADB" "${ADB_ARGS[@]}" shell getenforce 2>/dev/null | tr -d '\r' || true)"
API="$("$ADB" "${ADB_ARGS[@]}" shell getprop ro.build.version.sdk | tr -d '\r')"
MODEL="$("$ADB" "${ADB_ARGS[@]}" shell getprop ro.product.model | tr -d '\r')"
MANUFACTURER="$("$ADB" "${ADB_ARGS[@]}" shell getprop ro.product.manufacturer | tr -d '\r')"
BUILD="$("$ADB" "${ADB_ARGS[@]}" shell getprop ro.build.fingerprint | tr -d '\r')"
ABI="$("$ADB" "${ADB_ARGS[@]}" shell getprop ro.product.cpu.abi | tr -d '\r')"

cat >"$EVIDENCE_FILE" <<EOF
# ClosedRoom G1 local evidence

- source_revision: `$REVISION`
- manufacturer: `$MANUFACTURER`
- model: `$MODEL`
- android_api: `$API`
- build_fingerprint: `$BUILD`
- abi: `$ABI`
- adb_shell_uid: `$UID_VALUE`
- selinux: `${SELINUX:-unknown}`
- source: `$SOURCE`
- format: `PCM16/48000Hz/$CHANNELS`
- duration_seconds: `$DURATION_SECONDS`
- route: `$ROUTE`
- carrier_mode: `$CARRIER_MODE`
- screen_state: `$SCREEN_STATE`
- requested_runs: `$RUNS`

Audio is intentionally not stored in this evidence file and must not be copied off-device.

EOF

echo
COMPETING="$(prompt_enum "Confirm no competing recorder is active? [yes/no]: " yes no)"
if [[ "$COMPETING" != "yes" ]]; then
  echo "error: stop the competing recorder before G1" >&2
  exit 3
fi

GO_COUNT=0

for ((run=1; run<=RUNS; run++)); do
  echo
  echo "---- G1 run $run/$RUNS ----"
  printf "Start/keep a real carrier call active on route '%s', then press Enter to record..." "$ROUTE"
  IFS= read -r _

  CAPTURE_LOG="$(mktemp -t closedroom-g1-capture.XXXXXX)"
  set +e
  "$PROBE_DIR/run_capture.sh" "$SOURCE" "$DURATION_SECONDS" "$CHANNELS" 2>&1 | tee "$CAPTURE_LOG"
  CAPTURE_STATUS=${PIPESTATUS[0]}
  set -e

  if [[ "$CAPTURE_STATUS" -ne 0 ]]; then
    ERROR_SIGNATURE="$(grep -E 'CRPROBE result=error|error:' "$CAPTURE_LOG" | tail -n 3 | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' || true)"
    {
      echo "## Run $run"
      echo
      echo "- capture_status: `FAIL`"
      echo "- bounded_error_signature: `${ERROR_SIGNATURE:-capture command exited $CAPTURE_STATUS}`"
      echo "- cleanup_verified: `pending`"
      echo
    } >>"$EVIDENCE_FILE"
    rm -f "$CAPTURE_LOG"
    "$PROBE_DIR/cleanup.sh"
    echo "Capture failed. Evidence recorded; stop this session and diagnose before varying another dimension." >&2
    exit "$CAPTURE_STATUS"
  fi
  rm -f "$CAPTURE_LOG"

  echo
  echo "Inspect the generated WAV locally on the phone before continuing."
  echo "Do not copy the audio to the host."
  printf "After listening on-device, press Enter to record the verdict..."
  IFS= read -r _

  LOCAL_VOICE="$(prompt_enum "Local voice [absent/present/intelligible]: " absent present intelligible)"
  REMOTE_VOICE="$(prompt_enum "Remote voice [absent/present/intelligible]: " absent present intelligible)"
  LEAKAGE="$(prompt_enum "Acoustic leakage concern [yes/no/unknown]: " yes no unknown)"

  if [[ "$LOCAL_VOICE" == "intelligible" && "$REMOTE_VOICE" == "intelligible" && "$LEAKAGE" == "no" ]]; then
    RUN_RESULT="GO"
    GO_COUNT=$((GO_COUNT + 1))
  elif [[ "$LEAKAGE" == "yes" || "$LEAKAGE" == "unknown" ]]; then
    RUN_RESULT="INCONCLUSIVE"
  else
    RUN_RESULT="FAIL"
  fi

  "$PROBE_DIR/cleanup.sh"

  CLEANUP_VERIFIED="yes"
  if "$ADB" "${ADB_ARGS[@]}" shell test -e /data/local/tmp/closedroom-probe.jar; then
    CLEANUP_VERIFIED="no"
  fi
  if "$ADB" "${ADB_ARGS[@]}" shell test -d /sdcard/Download/ClosedRoomProbe; then
    CLEANUP_VERIFIED="no"
  fi
  if "$ADB" "${ADB_ARGS[@]}" shell "pgrep -f '[c]om.closedroom.probe.CallAudioProbe' >/dev/null"; then
    CLEANUP_VERIFIED="no"
  fi

  {
    echo "## Run $run"
    echo
    echo "- local_voice: `$LOCAL_VOICE`"
    echo "- remote_voice: `$REMOTE_VOICE`"
    echo "- acoustic_leakage_concern: `$LEAKAGE`"
    echo "- result: `$RUN_RESULT`"
    echo "- cleanup_verified: `$CLEANUP_VERIFIED`"
    echo
  } >>"$EVIDENCE_FILE"

  echo "run_result=$RUN_RESULT cleanup_verified=$CLEANUP_VERIFIED"

  if [[ "$CLEANUP_VERIFIED" != "yes" ]]; then
    echo "error: cleanup verification failed; stop before another run" >&2
    exit 5
  fi
done

if (( GO_COUNT == RUNS )); then
  SESSION_RESULT="GO"
else
  SESSION_RESULT="NOT_GO"
fi

{
  echo "## Session verdict"
  echo
  echo "- successful_runs: `$GO_COUNT/$RUNS`"
  echo "- session_result: `$SESSION_RESULT`"
  echo
} >>"$EVIDENCE_FILE"

trap - EXIT INT TERM HUP
"$PROBE_DIR/cleanup.sh"

echo
echo "G1 session complete."
echo "session_result=$SESSION_RESULT"
echo "technical evidence: $EVIDENCE_FILE"
echo "No call audio was copied to the host."
echo
if [[ "$SESSION_RESULT" == "GO" ]]; then
  echo "This route has the required repeated evidence. Use the metadata file to update the workstream; do not commit audio."
else
  echo "Do not advance G1 yet. Diagnose the first failing/inconclusive dimension before changing multiple variables."
fi
