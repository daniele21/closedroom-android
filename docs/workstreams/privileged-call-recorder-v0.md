# Privileged call recorder V0

Status: active  
Owner: ClosedRoom Android  
Read when: resuming V0 recorder development

## Product intent and milestones

- PRODUCT_STRATEGIC: personal sideloaded APK; local manual carrier recording, intelligible local (TX) + remote (RX).
- Risks: VALUE LOW; USABILITY MEDIUM (ADB recovery); FEASIBILITY HIGH (OEM/audio); VIABILITY MEDIUM (internal APIs).
- Hypotheses: shell captures RX+TX without root; APK controls `app_process`; app-owned FD works across IPC. Embedded ADB is separate; GPL references stay read-only.
- V0: documented host-ADB bootstrap -> Record/Stop -> playable file; repeatable target-phone use/cleanup.
- Optional V0.1: one APK pairs/connects/starts/recovers daemon. Not required for V0.
- Outcome: repeatable personal use, no analytics. Later: is broader compatibility worth maintaining?

Decision: BUILD bounded V0; evaluate V0.1 after acceptance. Shizuku is an explicit alternative, not one-APK evidence.

## Scope and invariants

Non-goals: cloud/AI/public distribution/VoIP; automatic recording/detection; contacts; universal OEM support; root-first; separate tracks; early polish; GPL code copying.

- Audio stays on-device, including diagnostic inspection/playback; never forward it to desktop.
- Explicit user start; one recording; bounded idempotent cleanup. Shell privilege/hidden APIs stay in daemon; no arbitrary shell protocol.
- Final audio app-private; delete probe audio after inspection, leave none in `/data/local/tmp`.
- Logs/commits: technical metadata only, no audio/numbers/pairing secrets.
- Emulator never proves carrier audio; discovery never replaces automated gates.

## Architecture and references

```text
Compose -> Controller -> authenticated IPC + app-owned FD
                     -> app_process / shell UID -> PrivilegedAudioCapture
bootstrap: host ADB (V0); embedded ADB (optional V0.1); Shizuku (explicit alternative)
```

Capture API unresolved until G1; IPC separate. Recheck/pin references:

- [ShizuCallRecorder](https://github.com/kitsumed/ShizuCallRecorder), [CallVault](https://github.com/madkongo/CallVault): GPL-3.0 references only.
- [scrcpy](https://github.com/Genymobile/scrcpy/blob/master/doc/audio.md): Apache-2.0 voice-call reference; default output capture is insufficient.
- [Android](https://developer.android.com/reference/android/media/MediaRecorder.AudioSource#VOICE_CALL): VOICE_CALL requires privileged CAPTURE_AUDIO_OUTPUT.
- [Shizuku API](https://github.com/RikkaApps/Shizuku-API): Apache-2.0 Binder patterns; shell is not an app process. `MuntashirAkon/libadb-android`: candidate requiring license/dependency/support review.

## Gates and work graph

| Gate | GO evidence | Otherwise |
| --- | --- | --- |
| G1 | own probe: target/required routes, intelligible RX+TX, no root | narrow scope or stop non-root/evaluate alternatives |
| G0 | adopted baseline + reproducible Android skeleton build/launch | finish adoption |
| G-IPC | APK discovers/authenticates shell daemon; FD writes/closes app-private file; clean restart | solve IPC first |
| G2 | own daemon reproduces G1; ping/start/stop/cleanup | diagnose adapter vs probe |
| G3 | host ADB -> Ready -> Record -> Stop -> file -> playback, both voices | fix flow first |
| G4 optional | one APK pairs/connects/ensures daemon and recovers failures | defer V0.1, preserve V0 |

G1 before adoption; G0/G-IPC before product code; no embedded ADB before G3.

| ID | Work / owns | Depends on | Parallel | State |
| --- | --- | --- | --- | --- |
| WS-0a | minimum probe build/launch tooling | — | WS-1 | DONE |
| WS-1 | target experiment contract/evidence | — | WS-0a | DONE |
| WS-2 | own shell probe/debug script | WS-0a, WS-1 | no | DONE |
| WS-3 | physical experiments/G1 | WS-2 | no | ACTIVE |
| WS-0b | full adoption/Android skeleton/G0 | G1 | no | BLOCKED |
| WS-6a | IPC/FD spike/shared contract/G-IPC | G0 | no | BLOCKED |
| WS-4 | daemon/capture adapter/G2 | G-IPC | WS-5 | BLOCKED |
| WS-5 | app/controller/store/basic recovery | G-IPC | WS-4 | BLOCKED |
| WS-6 | integrated IPC/lifecycle/output | WS-4 (G2), WS-5 | no | BLOCKED |
| WS-7 | complete manual journey/G3 | WS-6 | no | BLOCKED |
| WS-10a | target reliability with host ADB | G3 | no | BLOCKED |
| WS-11a | V0 reference APK/release evidence | WS-10a | no | BLOCKED |
| WS-8 | optional embedded ADB/G4 | WS-11a, V0.1 selected | WS-9 | DEFERRED |
| WS-9 | optional pairing/recovery UX | WS-11a, V0.1 selected | WS-8 | DEFERRED |
| WS-10b | bootstrap/affected recording reliability | WS-8 (G4), WS-9 | no | DEFERRED |
| WS-11b | optional V0.1 APK/release evidence | WS-10b | no | DEFERRED |

States: READY, ACTIVE, BLOCKED, DONE, DEFERRED (optional). Evidence closes gates.

## Discovery

WS-0a: probe build/ADB/cleanup only. WS-1: identify phone; control can run immediately but never replaces G1.

Contract: model/OEM/build/ABI, carrier/mode (VoLTE/VoWiFi/other/unknown), required routes/screen/background, ADB authorization. Earpiece first; Bluetooth if required; missing facts unresolved.

Run metadata: revision, UID/SELinux, API/attribution, format/duration, route/mode/screen, each voice present/intelligible, errors/verdict/cleanup. Inspect/delete audio locally.

1. Own `app_process`: verify shell; ping/version/status; smallest AOSP/Apache capture; PCM/WAV if simpler; explicit stop/kill/cleanup.
2. Alternate distinct fixed phrases/silence; assess each voice. Speaker acoustic leakage is not direct RX proof; preserve call audibility.
3. G1: three 60–120 s successes per required route, expected screen/background, no competing recorder. Declare optional-route limits.
4. Earpiece P0; screen/background P0 if required; repeat start/stop and speaker P1 unless required; Bluetooth/app-kill after base success.
5. Stop control before probe. Vary identity/permissions/source/attribution/policy/route singly; hold successful source fixed for format diagnosis.

Default budget: eight engineering hours across WS-0a/1/2/3, excluding device-access waiting. Pivot after two same-signature repairs. At expiry choose GO/NARROW_SCOPE/STOP; extension requires explicit scope/budget decision. Missing device access is pending evidence, not failed feasibility.

## Adoption — WS-0b

Adopt baseline 0.11.0 with android + product-ui: Kotlin/Compose, one module, Gradle wrapper/pinned JDK/SDK; preserve probe/evidence.

Specialize `.engineering/*.json`, AGENTS.md, product/architecture/current-state docs, UX/brand. Code-first design/tokens/accessibility; retain adopter needs, remove maintainer material. Native operations/risk gates. G0: `./gradlew assembleDebug`, launch, no placeholders, truthful metadata. FULL bootstrap locally or in repository automation.

## Boundary and product

G-IPC: APK/shell daemon, fixture bytes. Resolve discovery/Binder delivery, authentication, identities, FD ownership/death. Binder/PFD preferred; socket/pipe requires peer/auth, bounded buffers/cleanup. Reject unauthorized clients.

Freeze contract before disjoint WS-4/5 work. Daemon owns serialized control, capture adapter/errors/cleanup; WS-4 explicitly proves G2 physically before G3.

```text
ping() -> protocolVersion, daemonInstanceId, capabilities
status() -> state, sessionId?, terminalResult?
start(requestId, outputFd, config) -> sessionId
stop(sessionId) -> terminalResult
shutdown() -> result
```

Duplicate requests reuse results; competing starts reject; stale IDs cannot stop new sessions; idle stop is no-op. Status reconciles lost responses; distinguish restart/bound retention. Only G1-required config.

App opens generated `.partial`; daemon completes header/closes FD; app validates payload/format/duration/bytes then finalizes, atomically where supported. Failure/timeout never means saved. Failed partials stay app-private for explicit deletion; restart never silently promotes them. Final files: play/delete; advanced partial cleanup.

Provisional bounds: 60 min or 512 MiB, whichever first; start/stop 10 s; death detection 5 s, termination 10 s. Test shortened limits and physical long sessions. Terminate stuck workers.

| Event | V0 result |
| --- | --- |
| Activity background/screen off | continue while controller lives; status/Stop accessible |
| Controller death/link lost | bounded stop; unfinished file partial; reconnect never restarts capture |
| Call ends before Stop | manual Stop required; EOF/error stops, otherwise caps apply; no call detection |
| Stop during start/rapid taps | stop/cancel same session; no second writer |
| FD/storage failure/daemon death | terminate; visible failure; never false saved |
| Lost stop response/app reopen | reconcile result/file; unresolved output partial |

WS-5 before G3: not ready/ready/starting/recording/stopping/saved/unavailable/failed. One Record/Stop, elapsed status, local play/delete, contextual host-ADB recovery, advanced diagnostics. Semantic labels, adequate targets, non-color/accessibility feedback; no elapsed announcement every second.

## Usable V0

G3: APK install -> documented host-ADB launch -> Ready -> carrier call -> Record -> alternate phrases -> Stop -> file -> playback -> both voices intelligible.

Reliability: ten sessions on primary route; check other required routes, immediate Stop, call ending first, screen/background, existing/killed daemon, app reopen/kill, lost response, storage/FD failure, caps/long duration, reboot/host bootstrap, post-stop cleanup. Inject impractical physical faults deterministically. Classify capture/bootstrap/lifecycle/IPC/storage/OEM/evidence failures.

WS-11a: FULL final-APK install/smoke/target evidence.

## Optional V0.1

Select after V0; timebox WS-8. Review license/dependencies/API/OEM, TLS pairing/connect, mDNS/own-device verification, keys/timeouts/cancellation. App-private keys; no stored/logged pairing code; fixed daemon command allowlist.

Journey: Developer Options/Wireless debugging -> own-device pairing/code/key -> connect -> compatible daemon -> Ready. Bound retries/recovery: debugging off, pairing lost, timeout/start/version failure. Test reboot/network/no Wi-Fi/debugging loss; document re-bootstrap. No assumed unattended/offline recovery; Shizuku changes scope, not G4.

## Validation and evidence

- ITERATION: SCOPED UI/storage compile/tests; STRONG protocol/lifecycle/capture contracts; FULL for global build/toolchain/dependency/selector changes.
- INTEGRATION: affected static/lint/unit/contracts, APK build/install/cleanup and emulator E2E. Actual shell daemon via host ADB, real IPC/FD/store; fake only daemon audio source with samples/faults. In-app fake cannot prove G-IPC/lifecycle.
- UI journey: FULL_MEDIA assertions, privacy-safe screenshots + continuous emulator video; source/artifact/environment identity, bounded retention. System-only contracts may use ASSERTIONS. Missing selected media is incomplete; no downgrade.
- REAL_ENVIRONMENT: target phone/build/carrier/routes/ADB. G1/G2/G3 are discovery/diagnostic gates, not physical testing on every commit. Residual fidelity gaps defer to RELEASE; FULL release closes blocking gaps on final APK.
- Emulator never proves RX+TX. Reuse evidence only with justified source/tree/base/gates/environment identity.

## Resume and completion

Next: execute the prepared WS-3 / G1 session on the target phone. WS-0a/WS-1/WS-2 are implemented; WS-3 host orchestration/evidence capture is implemented and ACTIVE. Probe compile/dex plus Android 15 emulator `adb push -> app_process -> info` passed for source head `bf749fcd15fe7160a47540035c0d23ec0475bcde` in Probe check run `36976990799`; observed `uid=2000`, API 35 and probe version 0.1.0. Real carrier-call RX+TX, G1, adoption and IPC gates remain unexecuted.

Recheck head/base. Unresolved: target/routes/source/discovery/auth/FD. Embedded ADB deferred; references are hypotheses.

Disjoint owners/early convergence, no stacked PRs. Project plan only; no baseline bump.

Durable owners: `docs/{product,architecture,current-state}.md`, `docs/features/recording.md`, `.engineering/*.json`, `design/{ux-contract,brand-kit}.json`, tests. Transfer facts at gates.

Complete V0: adopted repo, own non-root target capture, host-ADB recovery, playable RX+TX, bounded lifecycle/partials, repeated cleanup, automated gates and final-APK physical evidence. V0.1 adds G4/reliability/release evidence. After durable transfer, delete plan if V0.1 deferred; otherwise retain only that active slice.
