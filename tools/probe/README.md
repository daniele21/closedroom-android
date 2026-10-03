# ClosedRoom privileged call-audio probe

This directory owns the **pre-app feasibility spike** for G1 in
`docs/workstreams/privileged-call-recorder-v0.md`.

It deliberately uses host ADB only. Do not add embedded ADB, Compose UI, automatic call detection or
product storage here.

## What the probe proves

The only decisive question is whether an `app_process` Java program running as Android shell UID
`2000` can capture intelligible **local (TX) + remote (RX)** speech from a real carrier call on the
target phone without root.

A WAV file is created on the phone under `Downloads/ClosedRoomProbe`. Scripts never `adb pull`
audio. Inspect it on-device and delete it after the verdict.

The first implementation targets Android 12/API 31+ so attribution is explicit. If the target device
is Android 11, treat that as an unresolved compatibility branch rather than silently changing the
experiment.

## Prerequisites

- JDK with `javac` and `jar`.
- Android SDK platform **35** and Build Tools **35.0.0** by default.
- `ANDROID_SDK_ROOT` or `ANDROID_HOME`.
- `adb` authorized for exactly the target phone, or set `ANDROID_SERIAL`.
- Developer options/USB debugging or another ordinary host-ADB connection.

The compile SDK pins can be overridden explicitly with `ANDROID_PLATFORM_API` and
`ANDROID_BUILD_TOOLS_VERSION`, but do not change them merely to obtain a green run.

Run:

```bash
tools/probe/doctor.sh
tools/probe/build_probe.sh
```

`doctor.sh` prints only technical device/build metadata. Do not paste phone numbers, call audio,
pairing codes or other private payloads into issues/logs.

## Repeatable G1 session

For the primary physical gate, prefer the session runner over invoking individual captures manually:

```bash
G1_ROUTE=earpiece \
G1_CARRIER_MODE=unknown \
G1_SCREEN_STATE=foreground \
tools/probe/run_g1_session.sh
```

It performs doctor/build/cleanup once, runs the required three 60-second captures, pauses after each
capture for **on-device** listening, records only human verdicts + technical device metadata, and
verifies cleanup before the next run. Generated evidence is kept under
`tools/probe/evidence/local/` and ignored by Git.

The script deliberately cannot decide intelligibility itself because moving call audio to the host
would violate the diagnostic privacy boundary. The only manual inputs are the call readiness and
local/remote intelligibility/leakage verdicts.

## G1 run

Start with the direct combined call source:

```bash
tools/probe/run_capture.sh voice-call 60 stereo
```

During the 60 seconds:

1. use a normal carrier call;
2. keep the route on **earpiece** for the P0 case;
3. local speaker says a short fixed phrase;
4. remote speaker answers with a different short fixed phrase;
5. alternate speech and short silences so the two sides are distinguishable.

The host wrapper applies a bounded deadline and attempts to kill the specific probe process if ADB
or the capture blocks. A failed/interrupted run removes its generated WAV. A successful WAV remains
on-device for inspection.

After capture, inspect the WAV **on the phone**. Speakerphone acoustic leakage is not proof of direct
remote capture; earpiece is the primary discriminator.

Record a verdict using only technical metadata:

| Field | Value |
| --- | --- |
| source revision | |
| model / OEM | |
| Android API / build | |
| ABI | |
| carrier mode | VoLTE / VoWiFi / other / unknown |
| route | earpiece / speaker / headset / Bluetooth |
| screen/background state | |
| probe UID | must be 2000 |
| source | voice-call |
| format | PCM16, 48 kHz, stereo unless changed |
| local voice | absent / present / intelligible |
| remote voice | absent / present / intelligible |
| acoustic leakage concern | yes / no |
| result | GO / FAIL / INCONCLUSIVE |
| bounded error signature | |

Then delete audio:

```bash
tools/probe/cleanup.sh
```

## Diagnostic order after a failure

Do not random-walk through flags.

1. Preserve the exact error/result signature.
2. Verify `uid=2000`, Android API and output byte/signal counters.
3. Retry `voice-call` with `mono` only if initialization/format is implicated.
4. Use `voice-uplink` and `voice-downlink` as discriminating probes, not as an automatic fallback.
5. Use `mic` only as a control that the AudioRecord plumbing itself works.
6. Use `remote-submix` only as an output-capture control; it is not carrier-call proof.
7. Change one dimension at a time: identity/attribution, source, format, route.

After two repairs with the same failure signature, change the diagnostic strategy as required by the
workstream.

## G1 acceptance

Do not close G1 on one lucky sample.

The workstream requires **three 60–120 second successful runs per required route/state** with:

- non-root shell UID;
- local voice intelligible;
- remote voice intelligible;
- no competing recorder;
- cleanup verified after each run.

Missing physical-device access is pending evidence, not a failed feasibility result.

## Reference boundary

The shell-context/audio-capture approach is informed by Android framework behavior and
`Genymobile/scrcpy` at commit
`19c1261d2e2cbf2b5e6a71a8b64cc1dd3ede06ac` (Apache-2.0), especially its shell-side direct-audio
capture and `app_process` model.

GPL applications such as ShizuCallRecorder and CallVault remain behavioral/architecture references
only; do not copy their implementation into this probe.
