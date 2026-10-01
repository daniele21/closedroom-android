# Privileged call recorder V0

Status: active  
Owner: ClosedRoom Android  
Read when: implementing or coordinating the first Android call-recording feasibility slice

## Product intent

- Product depth: PRODUCT_STRATEGIC
- User / consumer: the repository owner, using a sideloaded/debug APK on a personal Android phone.
- Problem / job: record a normal carrier phone call locally from the same Android device, capturing both the local speaker and the remote party without cloud processing and without depending on Play Store distribution.
- Desired outcome: after a small privileged bootstrap, the user can manually start and stop a recording and obtain a local audio file in which both sides of the call are intelligible.
- Product risks:
  - VALUE: LOW — the requested job and desired outcome are explicit.
  - USABILITY: MEDIUM — Developer Options / ADB bootstrap is acceptable for V0 but still needs clear readiness and recovery.
  - FEASIBILITY: HIGH — the decisive uncertainty is whether shell-UID capture works on the target Android/OEM/audio stack and remains usable across routing modes.
  - VIABILITY: MEDIUM — hidden/internal Android APIs and ADB behavior can change by Android version/OEM; the product is intentionally personal/internal rather than generally supported.
- Material assumptions:
  - A1: a process running as Android shell UID can capture an audio path containing both sides of a carrier call on the target device.
  - A2: the required capture path can be implemented without root for the target device.
  - A3: a minimal out-of-process recorder can be launched with `app_process` and controlled safely from the APK.
  - A4: the app can own the destination file while the privileged process writes audio through an explicit IPC/file-descriptor boundary.
  - A5: a self-contained embedded-ADB bootstrap is feasible only after A1-A4 are proven; it is not required to answer the first feasibility question.
  - A6: GPL reference applications are used only as behavioral/architecture references unless an explicit licensing decision changes that boundary.
- Success evidence:
  - Acceptance: one APK plus a documented debug/ADB bootstrap can start/stop a recording and create a valid local file.
  - Outcome: on the target physical phone, a real carrier call produces an intelligible recording of both local and remote speech.
  - Product impact: owner can repeat the workflow reliably enough for personal use without cloud transfer; no analytics required.
- Post-release question: which Android/OEM/version changes break the privileged capture path, and is maintaining compatibility worth expanding beyond the target device?

Decision: BUILD AS A BOUNDED FEASIBILITY-FIRST V0.

## Goal

Prove, with the smallest possible implementation, that ClosedRoom Android can capture both sides of a real carrier call on the target physical device using a shell-privileged recorder, then wrap only the proven path in a minimal local Android UI.

The implementation order is deliberately:

```text
physical-device capability
-> own minimal shell capture
-> app <-> daemon control
-> local file ownership
-> one-screen manual UX
-> embedded ADB bootstrap
-> reliability hardening
```

Do not implement the later layers to compensate for an unproven capture path.

## Non-goals

- Google Drive upload or any cloud sync.
- Transcription, diarization, summaries, LLMs or other AI.
- Play Store publication or compliance work for public distribution.
- WhatsApp, Signal, Telegram, Meet, Teams or other third-party VoIP capture in V0.
- Automatic call detection or automatic start/stop in V0.
- Contact lookup, phone-number metadata or call-history integration.
- Universal Android/OEM compatibility.
- Root/Magisk as the primary implementation.
- Polished product onboarding before the capture path works.
- Background reliability beyond what is necessary for the manual V0.
- Separate near/far tracks as a requirement; a mixed two-sided stream is sufficient for V0.
- Lossy encoding as part of the first diagnostic experiment; start with PCM/WAV when that reduces variables.
- Copying GPL implementation code from ShizuCallRecorder/CallVault into ClosedRoom Android.

## Invariants

- Local-first: audio never leaves the device in V0.
- Explicit recording: V0 starts recording only from an intentional user action.
- Privilege is narrow: the privileged process exposes only recorder lifecycle/status functionality required by ClosedRoom.
- The ordinary APK never pretends to hold shell/root privileges; privilege remains in the explicitly bootstrapped process.
- No arbitrary shell-command execution is exposed through the app-facing recorder protocol.
- Audio content, phone numbers and call payloads are not written to repository logs or committed test fixtures.
- Diagnostic evidence records only bounded technical metadata unless the owner explicitly chooses otherwise.
- The target output file is owned by the app or transferred through an explicit controlled boundary; do not leave private recordings permanently in `/data/local/tmp`.
- Hidden/internal API use is isolated behind one capture owner so Android-version/OEM adaptations do not spread through the app.
- Daemon start/stop/error paths are bounded and idempotent; a failed recording attempt must not leave multiple capture processes competing for the same audio input.
- Reference-code licensing is explicit. Apache-2.0 references such as scrcpy/Shizuku may inform or be reused according to their licenses; GPL reference apps remain read-only references unless the repository deliberately adopts compatible licensing.
- Emulator evidence must never be presented as proof of carrier-call audio capture.
- A real-device diagnostic may be used early because feasibility itself is the discovery question; this does not turn manual physical-device execution into a substitute for automatable build/test gates.

## Architecture target

The intended V0 boundary is:

```text
┌─────────────────────────────────────────────┐
│ ClosedRoom APK                              │
│                                             │
│  Compose screen                             │
│      │                                      │
│  RecorderController                         │
│      │ IPC + app-owned output FD            │
└──────┼──────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────────┐
│ ClosedRoom Recorder Daemon                  │
│ launched by app_process as shell UID        │
│                                             │
│  RecorderProtocol                           │
│      │                                      │
│  PrivilegedAudioCapture                     │
│      │                                      │
│  Android audio stack / proven call source   │
└─────────────────────────────────────────────┘
```

Bootstrap evolves independently:

```text
V0 diagnostic: host ADB -> daemon
V0 usable:     embedded ADB -> daemon
fallback:      Shizuku only if it materially simplifies a blocked step
root:          separate later decision only if shell UID cannot satisfy the target device
```

The exact Android audio source/API is intentionally not fixed in this document. The feasibility spike must establish the working path on the target device before that path becomes architecture truth.

## Reference projects and licensing boundary

Use these as evidence/reference, not as authority over ClosedRoom design:

- `kitsumed/ShizuCallRecorder`: demonstrates current non-root carrier-call recording using shell privileges; GPL-3.0.
- `madkongo/CallVault`: demonstrates embedded ADB + detached `app_process` + Binder-style privileged recorder patterns; GPL-3.0.
- `Genymobile/scrcpy`: Apache-2.0 reference for shell-side Android audio capture and `app_process` server execution.
- `RikkaApps/Shizuku`: Apache-2.0 reference for shell/root bootstrap and Binder IPC patterns.
- `MuntashirAkon/libadb-android`: candidate embedded-ADB transport; license/dependency review is a required gate before adoption.

Do not transplant code from a GPL reference app into this repository merely because the APK is currently for personal use. Keep provenance and future licensing options clean.

## Decision gates

### G0 — repository is an application, not a template source

Before product implementation, the repository must be specialized from the copied `repo-template-sw` source tree into a self-contained Android project.

GO when:

- project identity is ClosedRoom Android rather than repo-template-sw;
- baseline 0.11.0 is adopted/specialized rather than copied as maintainer source;
- Android + product-ui profiles are selected;
- Kotlin/Gradle project and canonical commands exist.

### G1 — target device supports shell-privileged two-sided capture

This is the decisive feasibility gate.

GO when a real carrier call on the target physical device yields a file with:

- non-silent local speech;
- non-silent remote speech;
- both sides intelligible;
- no requirement for root.

NARROW_SCOPE when only one routing mode works or a recoverable OEM/version constraint exists.

STOP the non-root approach when shell UID cannot produce a usable remote+local call stream after discriminating experiments. At that point choose explicitly among:

- root/Magisk experiment;
- OEM/native recorder import;
- microphone-only recorder;
- abandon carrier-call recording for this device.

Do not build embedded ADB before G1.

### G2 — own daemon path works without GPL application code

GO when ClosedRoom's own minimal daemon:

- launches under shell UID;
- can be pinged;
- starts/stops capture;
- produces the same usable two-sided result established at G1;
- cleans up on stop/error.

### G3 — complete manual app flow works with external ADB bootstrap

GO when:

```text
launch APK
-> recorder ready
-> tap Record
-> real call audio is captured
-> tap Stop
-> recording appears locally
-> playback succeeds
```

At this point the product is already a useful developer V0 even if a computer is still required to bootstrap the daemon.

### G4 — one-APK bootstrap works

GO when the APK can pair/connect to the device's own debugging endpoint, ensure the daemon is running and recover from a missing daemon without a desktop command.

This gate is intentionally later than G1-G3.

## Work graph

| ID | Work | Owns/writes | Depends on | Parallel | State |
| --- | --- | --- | --- | --- | --- |
| WS-0 | Convert copied template source into a specialized ClosedRoom Android repository | root project structure, `.engineering/`, `AGENTS.md`, `docs/`, Gradle skeleton | — | no | READY |
| WS-1 | Establish target-device diagnostic contract and bounded evidence format | `docs/features/recording.md`, diagnostic scripts/docs, test matrix | WS-0 | yes with WS-2 after bootstrap | BLOCKED |
| WS-2 | Create the smallest host-ADB shell capture probe | privileged recorder spike, debug-only launch scripts | WS-0 | yes with WS-1 | BLOCKED |
| WS-3 | Execute G1 real-device capture experiments and identify the canonical audio path | target-device evidence only; no broad product code | WS-1, WS-2 | no | BLOCKED |
| WS-4 | Implement ClosedRoom-owned recorder daemon + narrow protocol | recorder daemon module, capture owner, lifecycle/status contract | G1 | yes with WS-5 | BLOCKED |
| WS-5 | Build minimal Android app shell and app-owned local recording store | Compose screen, controller/viewmodel, local storage/playback | WS-0 | yes with WS-4 after protocol shape fixed | BLOCKED |
| WS-6 | Connect app and daemon using the smallest robust IPC/output-file boundary | IPC/Binder or proven equivalent, FD transfer/stream ownership | WS-4, WS-5 | no | BLOCKED |
| WS-7 | Prove G3 complete manual flow using external ADB bootstrap | integration harness, app+daemon lifecycle | WS-6 | no | BLOCKED |
| WS-8 | Add embedded ADB pairing/bootstrap only after G3 | ADB transport, pairing/readiness/restart owner | G3 | yes with WS-9 | BLOCKED |
| WS-9 | Add minimal recording UX states and recovery | one-screen Compose UI, error/readiness states, accessibility basics | G3 | yes with WS-8 | BLOCKED |
| WS-10 | Reliability pass on the target device | process death, repeated sessions, route matrix, storage/error recovery | WS-8, WS-9 | no | BLOCKED |
| WS-11 | Integration/docs/internal debug artifact | canonical docs, exact-head validation, installable debug APK | WS-10 | no | BLOCKED |

Allowed states: `READY`, `ACTIVE`, `BLOCKED`, `DONE`.

## WS-0 — repository bootstrap and specialization

Purpose: remove ambiguity before app work. The repository currently contains the reusable repo-template-sw maintainer tree rather than an adopted Android application.

Work:

1. Treat the current copied template tree as bootstrap input, not product architecture.
2. Adopt/specialize repo-template-sw 0.11.0 into the repository.
3. Select:
   - Android profile;
   - product-ui profile;
   - no local-ai profile for V0.
4. Create the minimal Android application skeleton:
   - Kotlin;
   - Jetpack Compose;
   - single app module initially;
   - committed Gradle wrapper;
   - pinned compatible JDK/Android SDK values;
   - minSdk chosen from the actual target-device strategy, not from hypothetical broad compatibility.
5. Specialize:
   - `.engineering/baseline.json`;
   - `.engineering/product.json`;
   - `.engineering/commands.json`;
   - `.engineering/e2e.json`;
   - root `AGENTS.md`;
   - `docs/product.md`;
   - `docs/architecture.md`;
   - `docs/current-state.md`.
6. Preserve only reusable baseline artifacts needed by the app; remove repo-template-sw maintainer docs/tests/profiles from the adopter root.
7. Define canonical commands around Gradle:
   - setup/doctor;
   - check;
   - test;
   - build;
   - e2e/smoke when the harness exists;
   - clean.
8. Configure repository health so ordinary deterministic Android gates are automatable.

Acceptance:

- README and AGENTS describe ClosedRoom Android, not repo-template-sw.
- `./gradlew assembleDebug` is the canonical debug build.
- a minimal app launches on emulator/device.
- baseline metadata truthfully says 0.11.0 and selected profiles.
- no unresolved adopter placeholders remain in claimed configuration.

Validation profile: FULL for the bootstrap because build/selector/toolchain/repository structure is being established.

## WS-1 — target-device experiment contract

Before implementing privileged capture, define what counts as success.

Record at execution time:

- phone model;
- OEM;
- Android version/build;
- ABI;
- default dialer/carrier context;
- call route: earpiece first;
- whether VoLTE/VoWiFi is involved when observable;
- daemon UID;
- capture API/source attempted;
- sample rate/channels;
- duration;
- start/stop outcome;
- local-side signal present?;
- remote-side signal present?;
- audible/intelligible?;
- warnings/errors;
- relevant bounded logcat excerpts.

Do not commit the actual private recording. Store only a tiny synthetic/non-sensitive sample if a durable fixture later becomes necessary.

Initial route matrix:

| Case | Priority | Purpose |
| --- | --- | --- |
| Carrier call + earpiece | P0 | prove basic two-sided path |
| Carrier call + speaker | P1 | determine route sensitivity |
| Carrier call + wired/USB headset | P2 | optional after base success |
| Carrier call + Bluetooth | P2 | optional after base success |
| repeated start/stop | P1 | lifecycle sanity |
| app foreground/background | P2 | not needed for first proof |

Acceptance:

- experiment result can distinguish “capture path failed” from “encoding/storage/bootstrap failed”.
- G1 criteria are objective and reproducible.

## WS-2 — host-ADB privileged capture probe

Use the desktop ADB client only to answer feasibility cheaply.

Preferred progression:

1. Confirm device authorization and shell UID.
2. Launch a tiny ClosedRoom-owned Java/Kotlin entrypoint through `app_process`.
3. First implement `ping/version/status`, not recording.
4. Add the smallest capture path inspired by documented/AOSP/Apache-licensed references.
5. Write diagnostic PCM/WAV to a temporary test location or stream it to the host only for the spike.
6. Keep encoding out of the first experiment unless the API only exposes an encoded stream.
7. Add explicit process cleanup and prove no duplicate recorder remains.

Do not yet build:

- embedded ADB;
- pairing UI;
- call-state detection;
- Compose recording library;
- automatic lifecycle.

Iteration validation:

- compile daemon payload;
- launch under shell;
- assert UID/process identity;
- ping/status;
- start/stop without a call;
- deterministic cleanup.

## WS-3 — G1 real-device feasibility experiments

Run discriminating experiments rather than repeatedly changing random audio flags.

Experiment order:

1. Run a known shell-capable reference as a control if useful, without integrating its code.
2. Run ClosedRoom's shell probe against the same call/routing condition.
3. If remote audio is absent:
   - compare process identity/permissions;
   - compare capture API/source and attribution context;
   - inspect audio-policy/logcat evidence;
   - test one materially different shell capture path.
4. If both sides exist but quality is poor:
   - keep the successful source fixed;
   - vary only sample/channel/routing assumptions.
5. If one route works and another does not, record the limitation rather than broadening the code prematurely.

Required evidence:

- successful/failed capture matrix;
- bounded technical logs;
- no private call payload committed.

Completion:

- choose one canonical capture strategy for the target device;
- or stop/narrow per G1.

## WS-4 — ClosedRoom recorder daemon

After G1 only.

Responsibilities:

- shell process entrypoint;
- version handshake;
- single active recording invariant;
- capture-engine ownership;
- start/stop/status;
- explicit output destination handle;
- structured error codes;
- cleanup on stop/error/disconnect;
- no arbitrary command execution.

Suggested protocol surface:

```text
ping() -> version/capabilities
status() -> idle | recording | error
start(outputFd, config) -> sessionId
stop(sessionId) -> result
shutdown() -> result
```

Keep `config` tiny. Do not expose every possible Android audio knob unless G1 proved it is necessary.

Capture engine owns:

- hidden/internal API adaptation;
- Android-version-specific branching;
- audio source selection;
- sample format;
- codec only after raw capture is stable.

Validation profile: STRONG because this is a privileged process/lifecycle/shared contract.

## WS-5 — minimal app shell and local storage

Build only enough UI to operate the recorder.

Primary surface:

```text
ClosedRoom

Recorder: Ready / Not ready

        [ RECORD ]

Previous recordings
- timestamp · duration · play
```

Recording state:

```text
ClosedRoom

● Recording 00:42

         [ STOP ]
```

Required states:

- bootstrap not ready;
- ready;
- starting;
- recording;
- stopping;
- saved;
- recorder unavailable;
- recording failed.

Local storage:

- app-private by default;
- stable generated filename;
- atomic finalize/rename after successful stop;
- incomplete/failed files distinguishable and recoverable/deletable;
- basic playback and delete only.

Do not add settings unless a proven capture limitation requires one.

## WS-6 — app/daemon IPC and file ownership

Choose the smallest robust mechanism after the daemon contract is known.

Preferred design:

- app opens the final/in-progress file;
- app passes a writable `ParcelFileDescriptor`/FD through IPC;
- daemon writes captured data through that handle;
- app finalizes metadata after successful stop.

Benefits:

- recording stays in app-owned storage;
- daemon does not need app sandbox access;
- no permanent audio in shell-owned temp paths;
- cleanup ownership is explicit.

If Binder/file-descriptor passing proves disproportionately complex for the spike, a local socket/pipe may be used temporarily, but document:

- peer/authentication boundary;
- ownership;
- backpressure;
- disconnect semantics;
- why the temporary choice is safe enough for personal debug V0.

Contract tests must cover:

- duplicate start rejected;
- stop when idle;
- app process reconnect;
- daemon unavailable;
- broken output FD;
- writer failure;
- daemon death during recording.

## WS-7 — G3 manual end-to-end flow

Still use external ADB to bootstrap the daemon.

Critical journey:

```text
install debug APK
-> launch shell daemon from documented ADB command
-> open app
-> readiness = Ready
-> place/answer carrier call
-> tap Record
-> speak on both sides
-> tap Stop
-> file appears
-> play file
-> both sides intelligible
```

This is the first coherent vertical product outcome.

Automated integration evidence should cover everything except the physical carrier-audio fidelity gap:

- APK build/install/launch;
- daemon protocol against a fake/test capture backend;
- file lifecycle;
- UI state transition;
- playback-visible saved file;
- cleanup.

Physical target-device evidence confirms only the actual call-audio path.

## WS-8 — embedded ADB bootstrap

Only start after G3.

Goal: remove the desktop from normal use while keeping the same daemon/capture contract.

Investigate before dependency adoption:

- candidate embedded ADB library license;
- minimum Android API;
- TLS/pairing support;
- mDNS discovery behavior;
- connection timeouts/cancellation;
- key persistence;
- pairing expiry/recovery;
- OEM-specific Developer Options constraints.

Bootstrap journey:

```text
first launch
-> explain Developer Options / Wireless debugging
-> discover pairing endpoint
-> user enters pairing code
-> store app-owned ADB key
-> connect to local adbd
-> launch/ensure daemon
-> readiness = Ready
```

Do not expose generic shell execution from the UI or domain layer.

The embedded ADB owner may execute only the commands necessary to:

- discover/verify identity;
- start/verify/stop the ClosedRoom daemon;
- perform bounded diagnostics needed for recovery.

Recovery states:

- Developer Options unavailable;
- wireless debugging off;
- pairing required;
- pairing expired/lost;
- connection timeout;
- daemon failed to start;
- daemon version mismatch.

If embedded ADB becomes more complex than the whole recorder, stop and reconsider keeping Shizuku or host-ADB as the personal-tool bootstrap.

## WS-9 — minimal UX/recovery

Structural UX remains intentionally tiny.

Critical journey:

```text
open -> readiness -> record -> visible elapsed state -> stop -> saved -> play
```

Progressive disclosure:

- default: Ready + Record + recordings.
- contextual: one-line error/recovery action.
- advanced: diagnostic details behind a disclosure only when needed.
- expert: ADB/daemon version and logs behind diagnostics; never the default screen.

Accessibility basics:

- touch targets;
- semantic labels;
- non-color recording indication;
- elapsed status readable by accessibility services;
- clear destructive delete action.

No visual design expansion until G3 works.

## WS-10 — target-device reliability pass

After one-APK bootstrap works.

Test the target device for:

- 10 sequential recording sessions;
- call ended before Stop;
- Stop immediately after Start;
- daemon already running;
- daemon killed between app launches;
- app killed/reopened while daemon is idle;
- app killed during recording;
- storage write failure / insufficient space where practical;
- pairing unavailable/lost;
- reboot and re-bootstrap behavior;
- earpiece and speaker;
- Bluetooth only if it matters to actual use.

Classify every failure:

- capture regression;
- bootstrap/ADB;
- daemon lifecycle;
- IPC/backpressure;
- storage/finalization;
- OEM/system behavior;
- stale evidence/test issue.

Do not paper over repeated identical failures. After two failed repairs with the same signature, change the diagnostic experiment.

## WS-11 — integration and internal artifact

Durable docs at completion:

- `docs/product.md`: durable Android product boundary and local-first promise.
- `docs/architecture.md`: APK / embedded ADB / daemon / capture / storage ownership.
- `docs/features/recording.md`: supported carrier-call behavior and known target-device limitations.
- `docs/current-state.md`: integrated state, known blockers and next step.
- ADR only if a durable choice such as embedded ADB vs Shizuku vs root needs rationale beyond architecture docs.

Internal artifact:

- debug/internal APK only;
- no Play Store/AAB requirement;
- unique build identity and source revision;
- no signing secrets committed.

## Validation strategy

### Product discovery / feasibility

The G1 physical-device run is intentionally early because it answers the material feasibility assumption. It is evidence for product shaping, not a substitute for deterministic engineering validation.

### ITERATION

Use the narrowest sufficient checks.

Examples:

- UI/local storage: SCOPED Kotlin compile + focused unit tests.
- daemon protocol/capture owner: STRONG focused contract/lifecycle tests.
- Gradle/build config/dependency changes: FULL when narrowing/toolchain/build behavior changes.

### INTEGRATION

Automate:

- Kotlin/static/lint gates;
- unit/contract tests;
- debug APK assembly;
- emulator install/launch;
- app <-> fake/test daemon complete journey;
- persisted recording metadata/file lifecycle;
- recovery when daemon is unavailable;
- cleanup/no duplicate helper process in the automated harness.

Residual target gap:

- emulator cannot prove real carrier-call RX+TX.
- mark that evidence as REAL_ENVIRONMENT / target device.

### RELEASE / personal reference checkpoint

For a stable internal APK, require:

- FULL selected deterministic gates;
- exact APK/source identity;
- target-device successful carrier-call recording;
- both voices intelligible;
- no stale helper process after stop;
- documented setup/recovery;
- known Android/OEM limitation recorded.

## E2E environment model to adopt in WS-0

Target environment:

- actual personal Android phone;
- actual Android/OEM build;
- carrier call stack;
- real microphone/telephony/audio routing;
- Developer Options/ADB state used by the product.

Automated environment:

- Android emulator with built debug APK;
- fake/test capture backend replacing telephony audio;
- sufficient for app/daemon protocol, lifecycle, storage and UI orchestration;
- explicitly insufficient for real call-audio capture.

Critical journeys:

1. `manual-recording-success`
   - readiness -> Record -> Stop -> saved file.
2. `daemon-unavailable-recovery`
   - app detects missing helper and reaches recoverable state.
3. `recording-interrupted`
   - helper/capture failure leaves no falsely finalized successful recording.
4. `bootstrap-ready` after embedded ADB exists
   - pairing/connection -> daemon running -> ready.

UI evidence should remain proportional: the UI is mainly a harness for the privileged recorder during V0, so assertions/screenshots are sufficient until UX itself becomes a material integration outcome.

## Security / privacy review points

Before G3:

- daemon API has no arbitrary shell execution;
- app authenticates/validates the daemon endpoint or Binder identity sufficiently for the selected IPC;
- daemon accepts only one active session;
- output handles/paths are validated;
- no recording content in logs;
- app-private final storage;
- temporary diagnostic files cleaned.

Before G4:

- ADB private key stored in app-private storage;
- pairing code never persisted;
- mDNS/network discovery limited to bootstrap need;
- no remote host connectivity is introduced;
- local ADB commands are a fixed narrow allowlist;
- timeouts/cancellation on every connection attempt;
- explicit diagnostic/recovery state instead of silent retries forever.

## Current executable slice

`WS-0`

Acceptance:

- repository is a specialized ClosedRoom Android app repository aligned to repo-template-sw 0.11.0;
- Kotlin/Compose debug app skeleton builds;
- Android/product-ui profiles are installed;
- canonical product/architecture/current-state owners exist;
- commands and validation routing are specialized to Gradle/Android;
- the active workstream remains linked from current state after bootstrap.

Validation:

- repository-template adoption verifiers during bootstrap;
- Gradle debug compile/build after skeleton creation;
- selected FULL bootstrap validation because build/toolchain/selector ownership is changing.

## Resume checkpoint

- Source: `daniele21/closedroom-android`, plan branch `docs/privileged-recorder-v0-workstream`, based on initial `main` commit `b2fedfa4c7d6dfa5fce3dd13b122079161f52698`.
- Confirmed:
  - the repository currently contains the repo-template-sw 0.11.0 maintainer/source tree rather than a specialized adopter project;
  - repo-template-sw includes an Android profile and workstream/product-shaping contracts suitable for this project;
  - current reference projects demonstrate shell-UID/`app_process` carrier-call recording patterns on modern Android;
  - ShizuCallRecorder and CallVault are GPL-3.0 and must not be copied into a differently licensed ClosedRoom implementation without an explicit licensing decision;
  - scrcpy and Shizuku are Apache-2.0 references.
- Excluded:
  - implementing Drive, AI, automatic call detection or public-store distribution before basic capture works;
  - implementing embedded ADB before shell capture feasibility is proven;
  - treating emulator audio evidence as proof of carrier-call capture.
- Unresolved:
  - target phone/OEM/Android build;
  - exact shell-side Android audio API/source that works on that device;
  - whether Binder + app-owned FD is the smallest successful IPC boundary;
  - embedded ADB dependency/license/expiry behavior to adopt after G3.
- Next: execute WS-0, then run the host-ADB privileged capture spike before building the self-contained bootstrap.

Recheck current branch/head and repository contents before acting. Reference-project behavior is evidence, not a contract for ClosedRoom.

## Integration points

- WS-4 publishes one minimal recorder protocol consumed by WS-6; WS-5 must not depend on capture internals.
- WS-5 owns app storage/file lifecycle; WS-4 owns audio capture; WS-6 owns transport between them.
- WS-8 owns privilege bootstrap only; it must not absorb recorder/capture behavior.
- WS-9 owns presentation/recovery states only; readiness truth comes from recorder/bootstrap owners.
- All parallel work converges onto one coherent feature branch before integration; do not create a stacked PR chain for technical layers.

## Parallel execution guidance

Before G1:

```text
WS-0
 ├─> WS-1 experiment contract
 └─> WS-2 host-ADB probe
          \ /
          WS-3 G1 physical proof
```

After G1:

```text
              ┌─> WS-4 daemon/capture ─┐
G1 success ───┤                        ├─> WS-6 IPC -> WS-7 G3
              └─> WS-5 app/storage ────┘

G3 success
              ┌─> WS-8 embedded ADB ───┐
              └─> WS-9 minimal UX ─────┴─> WS-10 -> WS-11
```

Do not parallelize work that changes the same Gradle ownership, IPC contract or capture owner without an explicit integration point.

## Durable documentation destinations

- `docs/product.md`: personal/internal Android product mission, non-goals, local-first/privacy promise.
- `docs/architecture.md`: normal app, privileged daemon, bootstrap, capture, IPC and storage ownership.
- `docs/features/recording.md`: current supported call type, setup, behavior, failure/recovery and target-device limitations.
- `docs/current-state.md`: integrated/blocked/next truth and active-workstream pointer while this file exists.
- `.engineering/product.json`: product-depth routing.
- `.engineering/commands.json`: Gradle/Android command and validation routing.
- `.engineering/e2e.json`: emulator vs physical-target fidelity and critical journeys.
- `design/ux-contract.json`: minimal task model/readiness/recording/recovery semantics once UI is implemented.
- tests/contracts: executable daemon protocol, file lifecycle and recovery truth.

## Completion

The workstream is complete only when:

- the repository is a real ClosedRoom Android project rather than a template-source copy;
- the chosen non-root shell capture path is proven on the target phone;
- ClosedRoom owns the implementation rather than depending on copied GPL application code;
- a single APK can bootstrap or recover its privileged recorder with the accepted Developer Options/ADB setup;
- manual Record/Stop produces a local playable file with both sides intelligible;
- repeated sessions do not leave competing recorder processes or falsely successful files;
- local-first/privacy boundaries are preserved;
- deterministic automated gates and emulator journeys pass for what they can truthfully prove;
- target-device evidence closes the real carrier-audio gap;
- product/architecture/feature/current-state docs reflect the integrated truth.

Then transfer durable facts into the canonical owners above and delete this workstream by default.
