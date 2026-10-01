# Privileged call recorder V0

Status: active  
Owner: ClosedRoom Android  
Read when: implementing or coordinating the first Android call-recording feasibility slice

## Product intent

- Product depth: PRODUCT_STRATEGIC
- User: repository owner using a sideloaded/debug APK on a personal Android phone.
- Problem/job: record a normal carrier call locally on the same device, capturing local + remote speech without cloud processing or Play Store distribution.
- Desired outcome: after a small privileged bootstrap, manual Record/Stop creates a local playable file with both sides intelligible.
- Product risks:
  - VALUE LOW — requested job is explicit.
  - USABILITY MEDIUM — Developer Options/ADB setup is acceptable for V0 but needs clear readiness/recovery.
  - FEASIBILITY HIGH — shell-UID capture depends on Android/OEM/audio-stack behavior.
  - VIABILITY MEDIUM — hidden/internal APIs and ADB behavior can change across Android/OEM versions.
- Material assumptions:
  - A1 shell UID can capture both sides of a carrier call on the target device.
  - A2 this can work without root.
  - A3 a minimal `app_process` recorder can be controlled safely from the APK.
  - A4 the app can own the final file while the privileged process writes through an explicit IPC/FD boundary.
  - A5 embedded ADB is feasible, but is not required to answer A1-A4.
  - A6 GPL recorder projects remain reference-only unless licensing is deliberately changed.
- Success:
  - Acceptance: APK + documented debug bootstrap can start/stop and save a valid local recording.
  - Outcome: real carrier call on the target phone records intelligible local + remote speech.
  - Product impact: owner can repeat the workflow reliably enough for personal use; no analytics required.
- Post-release question: is maintaining compatibility beyond the target phone/Android build worth the cost?

Decision: BUILD as a bounded feasibility-first V0.

## Goal

Prove the real-device audio path first, then wrap only the proven path in a minimal Android app:

```text
physical-device capability
-> own shell capture
-> app <-> daemon control
-> app-owned local file
-> one-screen manual UX
-> embedded ADB bootstrap
-> target-device reliability
```

Do not implement later layers to compensate for an unproven capture path.

## Non-goals

- Drive/cloud sync.
- Transcription, diarization, summaries or AI.
- Play Store/public distribution.
- WhatsApp/Signal/Telegram/Meet/Teams capture.
- Automatic call detection or automatic recording.
- Contacts/call-history metadata.
- Universal OEM support.
- Root/Magisk as the primary path.
- Polished onboarding before capture works.
- Separate near/far tracks; a usable mixed two-sided stream is enough.
- Lossy encoding in the first diagnostic if PCM/WAV is simpler.
- Copying GPL application code from ShizuCallRecorder/CallVault.

## Invariants

- Audio stays on-device.
- Recording starts only from an explicit user action in V0.
- Privilege remains in a narrowly scoped shell process; the ordinary APK never claims shell/root privileges.
- App-facing recorder protocol exposes no arbitrary shell execution.
- Hidden/internal API use has one capture owner.
- One active recording maximum; stop/error paths clean up idempotently.
- Final recordings belong to app-owned storage; no permanent private audio in `/data/local/tmp`.
- Logs/evidence contain no private call audio or phone-number payloads.
- Emulator evidence never proves carrier-call audio capture.
- Early physical-device runs are discovery evidence for feasibility, not substitutes for automatable gates.
- GPL reference apps are read-only architecture/behavior references unless an explicit license decision changes that boundary.

## Target architecture

```text
ClosedRoom APK
  Compose UI
     |
  RecorderController
     | IPC + app-owned output FD
     v
ClosedRoom Recorder Daemon
  app_process / shell UID
     |
  PrivilegedAudioCapture
     |
  Android audio stack / proven source
```

Bootstrap evolves separately:

```text
diagnostic: host ADB -> daemon
usable V0:  embedded ADB -> daemon
fallback:   Shizuku only if it is materially simpler
root:       separate later decision if shell cannot satisfy target device
```

The exact call-audio source/API is intentionally unresolved until the physical spike proves it.

## Reference boundary

- `kitsumed/ShizuCallRecorder` — evidence that shell-privileged non-root carrier recording is possible on modern Android; GPL-3.0.
- `madkongo/CallVault` — evidence for embedded ADB + detached `app_process` + privileged recorder architecture; GPL-3.0.
- `Genymobile/scrcpy` — Apache-2.0 reference for shell-side Android audio capture and `app_process`.
- `RikkaApps/Shizuku` — Apache-2.0 reference for privileged bootstrap/Binder patterns.
- `MuntashirAkon/libadb-android` — candidate embedded-ADB transport; license/dependency review required before adoption.

Do not transplant GPL recorder implementation code into ClosedRoom just because V0 is personal.

## Decision gates

| Gate | Question | GO | If not |
| --- | --- | --- | --- |
| G0 | Is this a real Android app repo rather than copied template source? | Baseline specialized, Gradle/Compose skeleton builds | finish bootstrap before feature code |
| G1 | Can shell UID capture both sides on the target phone? | real carrier call has intelligible local + remote speech without root | NARROW_SCOPE by route/OEM, or STOP non-root and evaluate root/native import |
| G2 | Can our own daemon reproduce G1? | own shell daemon pings, records, stops, cleans up | diagnose implementation vs reference path |
| G3 | Does the complete manual app flow work with host-ADB bootstrap? | Record -> Stop -> local file -> playback -> both sides | fix app/daemon/storage boundary before embedded ADB |
| G4 | Can one APK bootstrap/recover the daemon? | in-app pairing/connect/ensure-daemon reaches Ready | keep host-ADB/Shizuku if embedded ADB costs more than it saves |

**Do not start embedded ADB before G3.**

## Work graph

| ID | Work | Owns/writes | Depends on | Parallel | State |
| --- | --- | --- | --- | --- | --- |
| WS-0 | Specialize repo + Android skeleton | root, `.engineering/`, docs, Gradle | — | no | READY |
| WS-1 | Define target-device experiment contract | recording feature doc + diagnostic evidence shape | WS-0 | with WS-2 | BLOCKED |
| WS-2 | Host-ADB shell capture probe | privileged spike + debug launch script | WS-0 | with WS-1 | BLOCKED |
| WS-3 | Execute G1 physical-device experiments | bounded device evidence | WS-1, WS-2 | no | BLOCKED |
| WS-4 | ClosedRoom-owned recorder daemon | daemon, capture owner, protocol | G1 | with WS-5 | BLOCKED |
| WS-5 | Minimal app shell + local store | Compose, controller, storage/playback | WS-0 | with WS-4 | BLOCKED |
| WS-6 | App/daemon IPC + output ownership | IPC/FD boundary | WS-4, WS-5 | no | BLOCKED |
| WS-7 | Prove G3 complete manual flow | integration harness | WS-6 | no | BLOCKED |
| WS-8 | Embedded ADB bootstrap | pairing/connect/daemon lifecycle | G3 | with WS-9 | BLOCKED |
| WS-9 | Minimal readiness/recovery UX | one-screen states | G3 | with WS-8 | BLOCKED |
| WS-10 | Target-device reliability pass | lifecycle/route/recovery evidence | WS-8, WS-9 | no | BLOCKED |
| WS-11 | Integration/docs/internal APK | canonical docs + exact artifact evidence | WS-10 | no | BLOCKED |

Allowed states: `READY`, `ACTIVE`, `BLOCKED`, `DONE`.

## WS-0 — repository bootstrap

Current repository truth: root is the **repo-template-sw 0.11.0 maintainer/source tree**, not yet an adopted Android project.

Work:

1. Adopt/specialize repo-template-sw 0.11.0 instead of developing inside the template-maintainer layout.
2. Select `android` + `product-ui`; no `local-ai` profile.
3. Create Kotlin + Jetpack Compose app, initially one module.
4. Commit Gradle wrapper and pin compatible JDK/SDK values.
5. Specialize:
   - `.engineering/baseline.json`
   - `.engineering/product.json`
   - `.engineering/commands.json`
   - `.engineering/e2e.json`
   - `AGENTS.md`
   - `docs/product.md`
   - `docs/architecture.md`
   - `docs/current-state.md`
6. Remove template-maintainer-only root material after copying/specializing what the adopter needs.
7. Map canonical operations to native Gradle/Android tooling.
8. Configure automatable repository-health/build gates.

Acceptance:

- repository identity is ClosedRoom Android everywhere;
- no unresolved adopter placeholders;
- minimal app launches;
- `./gradlew assembleDebug` is canonical;
- baseline metadata truthfully records 0.11.0 + selected profiles.

Validation: FULL, because repository/build/toolchain/selector ownership is established here.

## WS-1/2/3 — prove the audio path before product code

### Experiment contract

Record only technical metadata:

- target model/OEM/Android build/ABI;
- call route;
- daemon UID;
- attempted capture API/source;
- sample format;
- duration;
- local signal present?;
- remote signal present?;
- intelligible?;
- bounded relevant logcat/errors.

Do not commit private recordings.

Initial matrix:

| Case | Priority |
| --- | --- |
| carrier call + earpiece | P0 |
| carrier call + speaker | P1 |
| repeated start/stop | P1 |
| Bluetooth/headset | P2 after base success |
| background/app kill | P2 after base success |

### Host-ADB probe

Use desktop ADB only to reduce variables:

1. confirm device authorization + shell UID;
2. launch a tiny ClosedRoom-owned entrypoint via `app_process`;
3. implement `ping/version/status`;
4. add the smallest shell capture path based on AOSP/Apache-licensed references;
5. use PCM/WAV when possible so codec bugs cannot masquerade as capture bugs;
6. explicitly kill/clean the recorder after each run.

Do **not** add pairing UI, embedded ADB, call-state detection or recording library UI yet.

### G1 diagnostic strategy

1. Optionally run a known working shell-capable recorder as a control on the same phone/route.
2. Run the ClosedRoom probe under the same conditions.
3. If remote audio is absent, compare one variable at a time:
   - process identity/permissions;
   - capture API/source;
   - attribution context;
   - audio policy/logcat;
   - one materially different capture route.
4. If both sides exist but quality is poor, keep the successful source fixed and vary only format/routing.
5. Record limitations instead of prematurely adding compatibility abstraction.

After two failed repairs with the same failure signature, change diagnostic strategy.

G1 completion chooses **one canonical capture strategy for the target device** or explicitly stops/narrows the non-root approach.

## WS-4 — recorder daemon

After G1 only.

Responsibilities:

- shell entrypoint;
- version/capabilities handshake;
- single-session ownership;
- start/stop/status;
- app-supplied output destination;
- structured errors;
- cleanup on stop/error/disconnect;
- isolated Android-version/OEM capture adapter.

Minimal protocol target:

```text
ping() -> version/capabilities
status() -> idle | recording | error
start(outputFd, config) -> sessionId
stop(sessionId) -> result
shutdown() -> result
```

Keep `config` tiny; expose only knobs G1 proved necessary.

Validation: STRONG contract/lifecycle coverage.

## WS-5/6/7 — first usable vertical slice

### Minimal app

One primary surface:

```text
ClosedRoom
Recorder: Ready / Not ready

      [ RECORD ]

Previous recordings
timestamp · duration · play
```

During capture:

```text
● Recording 00:42
      [ STOP ]
```

Required states:

- not ready;
- ready;
- starting;
- recording;
- stopping;
- saved;
- recorder unavailable;
- failed.

Storage:

- app-private final files;
- stable generated filename;
- incomplete vs finalized file distinction;
- atomic finalize when practical;
- playback + delete only.

### IPC/output boundary

Preferred design:

- app opens the destination file;
- app passes writable `ParcelFileDescriptor`/FD via IPC;
- daemon writes through that handle;
- app finalizes metadata on successful stop.

This keeps shell privilege out of storage ownership.

If Binder/FD passing is disproportionate for the spike, a local socket/pipe is allowed temporarily only with explicit peer/auth, backpressure, disconnect and cleanup semantics.

Required contract cases:

- duplicate start;
- stop while idle;
- broken output FD;
- daemon unavailable/death;
- reconnect;
- writer failure.

### G3 critical journey

```text
install debug APK
-> launch daemon with documented host-ADB command
-> open app: Ready
-> make/answer carrier call
-> Record
-> speak both sides
-> Stop
-> local file appears
-> playback
-> both sides intelligible
```

This is the first coherent product outcome.

## WS-8/9 — make bootstrap self-contained

Only after G3.

### Embedded ADB

Before adopting a library, verify:

- license/dependency obligations;
- API level support;
- TLS pairing + mDNS discovery;
- key persistence;
- timeouts/cancellation;
- pairing expiry/recovery;
- OEM Developer Options constraints.

Journey:

```text
first launch
-> explain Developer Options/Wireless debugging
-> discover pairing endpoint
-> enter pairing code
-> persist app-owned key
-> connect local adbd
-> ensure daemon
-> Ready
```

ADB owner exposes a **fixed narrow allowlist** of operations needed to verify/start/stop the ClosedRoom daemon; no generic shell API reaches the product layer.

Recovery:

- debugging disabled;
- pairing required/lost;
- connection timeout;
- daemon start failure;
- daemon version mismatch.

If embedded ADB becomes more complex than the recorder, reconsider host-ADB or Shizuku for this personal tool.

### Minimal UX

Critical task:

```text
open -> readiness -> Record -> elapsed status -> Stop -> saved -> play
```

Progressive disclosure:

- default: readiness, Record, recordings;
- contextual: one-line recovery action;
- advanced: diagnostics;
- expert: ADB/daemon details only inside diagnostics.

Accessibility: semantic labels, adequate targets, non-color recording indication, accessible elapsed/status feedback.

## WS-10 — target-device reliability

After one-APK bootstrap:

- 10 sequential recordings;
- Stop immediately after Start;
- call ends before Stop;
- daemon already running;
- daemon killed between launches;
- app reopened while daemon idle;
- app killed during recording;
- storage failure where practical;
- pairing lost/unavailable;
- reboot/re-bootstrap;
- earpiece + speaker;
- Bluetooth only if materially needed.

Classify failures as capture, bootstrap, daemon lifecycle, IPC/backpressure, storage/finalization, OEM/system, or stale test evidence.

## Validation / E2E model

### ITERATION

- UI/storage: SCOPED compile + focused tests.
- daemon/shared protocol/capture: STRONG focused contracts/lifecycle.
- Gradle/build/dependency/selector changes: FULL when narrowing/build machinery changes.

### INTEGRATION

Automate what does not require real telephony:

- Kotlin/static/lint;
- unit/contract tests;
- debug APK assembly;
- emulator install/launch;
- app + fake/test capture backend journey;
- recording file lifecycle;
- daemon-unavailable recovery;
- bounded cleanup.

Automated environment: Android emulator + built debug APK + fake/test capture backend.

Residual gap: emulator cannot prove real carrier-call RX+TX.

### REAL_ENVIRONMENT

Target environment is the actual personal phone/OEM/Android build + carrier call stack + Developer Options/ADB state.

Early G1 physical execution is required because feasibility itself is unknown. For a stable personal-reference APK, target-device evidence must confirm:

- both sides intelligible;
- start/stop reliable;
- no stale competing recorder after stop;
- setup/recovery documented.

## Security/privacy gates

Before G3:

- no arbitrary shell command API;
- one active recorder;
- output FD/path validated;
- no call payload in logs;
- temporary diagnostic audio cleaned;
- app-private final storage.

Before G4:

- ADB private key app-private;
- pairing code never persisted;
- local discovery limited to bootstrap;
- no remote host/cloud path;
- fixed command allowlist;
- bounded timeouts/cancellation;
- explicit recovery rather than endless silent retry.

## Current executable slice

`WS-0`

Acceptance:

- specialized ClosedRoom Android repo;
- Kotlin/Compose skeleton builds;
- Android/product-ui baseline installed;
- canonical product/architecture/current-state owners exist;
- Gradle commands + validation routing configured;
- this active workstream is linked from `docs/current-state.md`.

Validation:

- baseline adoption verifiers;
- debug compile/build;
- FULL bootstrap validation.

## Resume checkpoint

- Source: `daniele21/closedroom-android`, branch `docs/privileged-recorder-v0-workstream`, base main `b2fedfa4c7d6dfa5fce3dd13b122079161f52698`.
- Confirmed:
  - current root is repo-template-sw 0.11.0 source, not an adopted app;
  - Android + product-ui profiles exist;
  - current reference projects demonstrate shell-UID/`app_process` call-recording architectures;
  - ShizuCallRecorder/CallVault are GPL-3.0 reference-only for this plan;
  - scrcpy/Shizuku are Apache-2.0 references.
- Excluded: Drive/AI/automatic recording/public distribution/embedded ADB before G3.
- Unresolved: target phone/OEM/build, exact working call-audio source/API, final IPC choice, embedded-ADB dependency.
- Next: execute WS-0, then WS-1 + WS-2 in parallel and run G1 before productizing anything else.

Recheck revisions and evidence before acting; reference-project behavior is evidence, not a ClosedRoom contract.

## Integration / parallelism

```text
WS-0
 ├─> WS-1 experiment contract ─┐
 └─> WS-2 shell probe ─────────┴─> WS-3 / G1

G1
 ├─> WS-4 daemon ─┐
 └─> WS-5 app ────┴─> WS-6 -> WS-7 / G3

G3
 ├─> WS-8 embedded ADB ─┐
 └─> WS-9 UX ───────────┴─> WS-10 -> WS-11
```

Parallel work must own non-conflicting paths/contracts and converge early onto one coherent feature branch; no stacked PR chain for technical layers.

## Durable documentation destinations

- `docs/product.md`: personal/internal Android mission, boundaries and local-first promise.
- `docs/architecture.md`: app / daemon / bootstrap / capture / IPC / storage ownership.
- `docs/features/recording.md`: supported carrier-call behavior, setup, failures and target-device limits.
- `docs/current-state.md`: integrated/blocked/next truth + active workstream pointer.
- `.engineering/product.json`, `commands.json`, `e2e.json`: product, execution and fidelity routing.
- `design/ux-contract.json`: readiness/recording/recovery task semantics.
- tests/contracts: executable protocol, lifecycle and storage truth.

## Completion

Complete only when:

- repo is a real ClosedRoom Android project;
- non-root shell capture is proven on the target phone;
- implementation is ClosedRoom-owned rather than copied GPL app code;
- one APK can bootstrap/recover the recorder with accepted Developer Options/ADB setup;
- manual Record/Stop saves a playable local file with both sides intelligible;
- repeated sessions leave no competing recorder/falsely finalized file;
- automated gates prove app/protocol/storage behavior;
- physical evidence closes the real carrier-audio gap;
- canonical docs match integrated truth.

Then transfer durable facts to the owners above and delete this workstream by default.
