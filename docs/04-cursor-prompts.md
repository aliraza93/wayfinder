# Waypoint — Cursor Prompts

One prompt per milestone (CURSOR-01 → CURSOR-18), mapping to roadmap M0 → M17. **Paste exactly one prompt into Cursor at a time.** Complete and verify a milestone before moving to the next. Each prompt is self-contained and repeats the standing rules, because you'll use them individually.

**Project one-liner (for your own reference):** a macOS menu-bar app that runs user-defined, strictly read-only navigation workflows (switch/scroll/page/wait/return) across already-open apps. Code editors are never modified. It performs real, user-configured navigation and logs the truth — it must never fabricate activity, falsify screenshots, manipulate time tracking, or deceive monitoring systems.

---

## STANDING RULES (apply to every prompt)

> These are restated inside each prompt. If you ever paste a prompt without them, add them.

1. Implement **only** the current milestone. Do not start work from later milestones.
2. Do **not** redesign the architecture. Follow the specified module boundaries.
3. **Build and run the tests** for what you implement. Do not report success unless build + tests pass.
4. If something fails or you're blocked, **report the failure honestly** with the exact error. Never hide, stub-over, or fake a passing result.
5. Do **not** modify unrelated files. Touch only the files this milestone names (plus test files for them).
6. Leave the project in a **working, buildable state** at the end.
7. Code-editor automation must remain **strictly read-only**: no typing, paste, delete, save, or command execution; only inert navigation (scroll-wheel, arrows, Page Up/Down, Home/End).
8. Do **not** implement anything intended to fabricate activity, falsify screenshots, manipulate time tracking, or deceive monitoring systems. No screenshot capture pipeline. Logs record only truthful action metadata.

---

# CURSOR-01 — Project foundation

**Context:** New macOS app project. This milestone creates the repository skeleton, the module layout, and CI for pure-logic tests. Nothing macOS-permission-related yet. Modules `Domain`, `Config`, `Safety`, `CoreEngine`, `Timing` must stay free of AppKit/Accessibility imports so they run in headless CI.

**Objective:** A buildable Xcode app (SwiftUI menu-bar app showing only "Quit") plus empty Swift Package modules, with CI that builds and runs unit tests.

**Requirements:**
- Xcode macOS app target using SwiftUI lifecycle and `MenuBarExtra` with a single "Quit" item.
- Local Swift package(s) with these module targets (empty but compiling): `Domain`, `Config`, `Safety`, `CoreEngine`, `Actions`, `Observability`, `Accessibility`, `InputSynthesis`, `AppControl`, `Permissions`, `Adapters`, `Timing`.
- Pure-logic modules (`Domain`, `Config`, `Safety`, `CoreEngine`, `Timing`) must not import AppKit/ApplicationServices.
- A CI script (`scripts/ci.sh`) that runs `swift test` (packages) and an `xcodebuild build` of the app.
- `README.md` stating what the app does and the read-only + anti-deception invariants; add `LICENSE` and `.gitignore`.

**Files/modules to create:** `Package.swift`; `Sources/<each module>/Placeholder.swift`; `Tests/DomainTests/SmokeTests.swift`; `App/NavigatorApp.swift`, `App/MenuBar/RootMenu.swift`; `scripts/ci.sh`; `README.md`; `LICENSE`; `.gitignore`.

**Technical implementation guidance:** Keep the app target thin. Wire packages as local dependencies of the app. The smoke test can assert `true`. Do not add third-party dependencies.

**Tests to write:** `SmokeTests` in `DomainTests` (one trivial passing assertion) so CI has a green target.

**Acceptance criteria:** App launches and quits; `swift test` passes; `xcodebuild build` succeeds; `scripts/ci.sh` exits 0; every listed module compiles.

**What must NOT be changed:** N/A (first milestone) — but do not add any real functionality beyond the skeleton.

**Expected output/report:** List files created, the exact `swift test`/`xcodebuild` commands run, their pass/fail output, and confirmation the app launches. Report any build issue verbatim.

**Standing rules:** implement only this milestone; don't redesign; build+test; report failures honestly; don't touch unrelated files; leave it buildable; editors read-only; no deceptive functionality.

---

# CURSOR-02 — Domain model & capability tags

**Context:** Building on CURSOR-01. This defines the closed action set and workflow types, with safety metadata (capability tags) on each action. This is pure logic in `Domain`. No macOS APIs.

**Objective:** Implement `ActionKind` (closed enum), capability tags, and the `Workflow`/`Step`/`TargetApp` types plus the error taxonomy.

**Requirements:**
- `ActionKind` closed enum with exactly: `activateApp(bundleID)`, `switchWindow(direction)`, `scroll(direction, amount)`, `pageNavigate(PageMove)`, `openExistingFile(path)`, `wait(seconds)`, `returnToPrevious`. **No `switchTab`. No text/paste/delete/save case may exist.**
- Capability tags per action: `mutatesText: Bool` (must be `false` for all), `requiresFocusGuard: Bool`, `verifiable: Bool`, `primitive: Primitive` where `Primitive ∈ {scrollWheel, inertKey, appControl, none}`.
- Tag lookup must be an **exhaustive switch** so adding an action forces a tag decision at compile time.
- `Workflow` (name, targets, ordered steps, loop settings), `Step` (action, timeout, retryPolicy, onError), `TargetApp` (bundleID, class ∈ {browser, editor, finder, generic}).
- `DomainError` enum stub for the taxonomy (permission, precondition, action, forbidden, timeout).

**Files/modules to create:** `Sources/Domain/{ActionKind.swift, CapabilityTags.swift, Primitive.swift, Workflow.swift, Step.swift, TargetApp.swift, DomainError.swift}`; `Tests/DomainTests/{ActionTagTests.swift}`.

**Technical implementation guidance:** Model directions/page moves as small enums. Do not add a generic "arbitrary keystroke with String" parameter anywhere. Keep everything `Equatable`. No AppKit imports.

**Tests to write:** assert every `ActionKind` has `mutatesText == false`; assert the tag switch is exhaustive (compile-time) and returns tags for every case; assert `Primitive` for each action matches intent (e.g., `scroll` → `.scrollWheel`).

**Acceptance criteria:** module compiles; `ActionTagTests` pass; no action can be constructed that mutates text; adding a hypothetical case would fail to compile until tagged.

**What must NOT be changed:** Do not modify CURSOR-01 skeleton beyond adding these files. Do not touch other modules.

**Expected output/report:** List new files, show the `ActionKind` cases and their tags, report `swift test` output for `DomainTests`.

**Standing rules:** only this milestone; no redesign; build+test; honest failures; no unrelated edits; buildable; editors read-only; no deceptive features.

---

# CURSOR-03 — Configuration system

**Context:** Building on CURSOR-02. Adds JSON persistence, versioning, and a validator for workflows. Pure logic in `Config`; file I/O via `Foundation` only (no AppKit).

**Objective:** Load, validate, save, and version workflow config as JSON.

**Requirements:**
- `Codable` for all `Domain` types with a **pinned, tested** encoding for the enum-with-associated-values `ActionKind`.
- `ConfigStore` reading/writing `~/Library/Application Support/Waypoint/workflows.json`.
- Top-level `schemaVersion` + a `Migration` hook (v(N-1) → v(N)).
- `WorkflowValidator` that rejects any workflow whose step is illegal for its target class (use CURSOR-02 tags — e.g., editor targets may only carry `mutatesText == false` actions), returning a typed error. Strict on unknown keys (clear error, not silent accept).

**Files/modules to create/modify:** create `Sources/Config/{ConfigStore.swift, SchemaVersion.swift, Migration.swift, WorkflowValidator.swift, Codable+Domain.swift}`; `Tests/ConfigTests/{RoundTripTests.swift, ValidatorTests.swift, MigrationTests.swift}`. May add `Codable` conformances alongside `Domain` types **without changing their semantics**.

**Technical implementation guidance:** Use a discriminator key (e.g., `"type"`) for `ActionKind` encoding and test the exact JSON shape. Inject the base directory so tests use a temp dir, not the real Application Support.

**Tests to write:** encode/decode round-trip equality; validator accepts a legal workflow and rejects an illegal one (mutating action on editor target) with the right error; a v1→v2 migration fixture upgrades correctly; unknown key → clear error.

**Acceptance criteria:** sample JSON loads, validates, round-trips stably; invalid configs rejected with typed errors; migration test passes; tests use a temp dir.

**What must NOT be changed:** Do not alter `ActionKind` cases or tags from CURSOR-02. Do not touch non-config modules.

**Expected output/report:** show the pinned JSON shape for one action, list files, report `ConfigTests` results.

**Standing rules:** only this milestone; no redesign; build+test; honest failures; no unrelated edits; buildable; editors read-only; no deceptive features.

---

# CURSOR-04 — Logging & redaction

**Context:** Building on prior milestones. Adds truthful, **content-free** logging. Critical safety property: there must be **no API path** to log window text, document content, keystrokes, or file contents.

**Objective:** Implement OSLog categories and a `RunRecorder` that emits structured JSONL of only `{timestamp, actionKind, targetBundleID, result}`.

**Requirements:**
- `os.Logger` categories: engine, executor, safety, permissions, adapter.
- `RunEvent` struct with **exactly** the allowed fields; `RunRecorder` accepts only `RunEvent`s and writes JSONL.
- **No** convenience `log(_ message: String)` that accepts free-form app content. Diagnostic OSLog messages must never include other apps' content.
- Log file rotation / size cap.

**Files/modules to create:** `Sources/Observability/{Log.swift, RunEvent.swift, RunRecorder.swift}`; `Tests/ObservabilityTests/{RedactionTests.swift, RecorderTests.swift}`.

**Technical implementation guidance:** `timestamp` injectable (clock) for deterministic tests. `RunEvent.result` is a small enum (`completed/failed/denied/skipped`), not free text. Serialize with a fixed field order.

**Tests to write:** construct events and assert serialized JSONL contains only the four allowed fields; assert (by API shape/review) there is no recorder method accepting arbitrary content strings; rotation triggers at the cap.

**Acceptance criteria:** JSONL matches the fixed schema exactly; no content-logging path exists; rotation works; `ObservabilityTests` pass.

**What must NOT be changed:** Do not add content fields to `RunEvent`. Do not modify `Domain`/`Config` semantics.

**Expected output/report:** show a sample JSONL line, list files, report test output, and explicitly confirm "no free-form content logging API exists."

**Standing rules:** only this milestone; no redesign; build+test; honest failures; no unrelated edits; buildable; editors read-only; no deceptive features.

---

# CURSOR-05 — Safety policy engine (KEYSTONE)

**Context:** Building on prior milestones. This is the single gate enforcing read-only, inert-primitive-only execution. It is pure logic in `Safety`. Everything that later performs actions must route through it. Its test suite becomes a merge gate.

**Objective:** Implement `SafetyPolicy.validate(action:, target:) -> Decision`, the inert-key allowlist, and `ForbiddenActionError`.

**Requirements:**
- `Decision` = `allow | deny(reason)`.
- `validate` uses CURSOR-02 tags: deny anything with `mutatesText == true` (defense-in-depth even though none exist); only `.scrollWheel` and `.inertKey` primitives may be emitted as synthetic input; `.appControl` allowed only if `verifiable`.
- `InertKeyAllowlist` as **declarative data**: arrows, Page Up/Down, Home/End. **No Cmd/Ctrl chords; no character/Return/Delete keys.** Any key outside the list → deny.
- `ForbiddenActionError` is always surfaced (return/throw + log via Observability), never swallowed.

**Files/modules to create:** `Sources/Safety/{SafetyPolicy.swift, InertKeyAllowlist.swift, Decision.swift, ForbiddenActionError.swift}`; `Tests/SafetyTests/{PolicyMatrixTests.swift, AllowlistTests.swift, PropertyTests.swift}`.

**Technical implementation guidance:** Keep the allowlist as a `Set` of key codes, not `if/else`. `validate` must be the only decision point — do not scatter checks. Pure Swift, no AppKit.

**Tests to write:** full matrix of every `ActionKind` × target class → expected decision; every non-allowlisted key denied; property test that no input yields `allow` for a mutating operation; a deliberately-added mutating fixture is denied.

**Acceptance criteria:** `SafetyTests` comprehensive and green; CI wired so a red safety suite blocks merge (update `scripts/ci.sh` to fail on `SafetyTests` failure).

**What must NOT be changed:** Do not weaken tags or add mutating actions. Do not duplicate policy logic elsewhere.

**Expected output/report:** show the decision matrix table, the allowlist contents, confirm CI gate wiring, report `SafetyTests` output.

**Standing rules:** only this milestone; no redesign; build+test; honest failures; no unrelated edits; buildable; editors read-only; no deceptive features.

---

# CURSOR-06 — Workflow engine + SimulationExecutor

**Context:** Building on prior milestones. Implements the state machine and a simulation executor so whole workflows run deterministically in CI with zero real events. No macOS APIs — real execution comes later.

**Objective:** Implement `WorkflowEngine` (state machine), `TimingPolicy`, `ActionExecutor` protocol, `SimulationExecutor`, and a `UserSovereigntySignal` abstraction.

**Requirements:**
- Engine states: `Idle → Arming → Running ⇄ Paused → Stopping → Idle`, plus `Error → Stopping`.
- Step lifecycle: `Pending → Validating → Executing → Settling → Completed | Failed → {Retry | Skip | Abort}`.
- Loop support with **max-iteration and wall-clock caps**.
- `TimingPolicy` = predicate-based wait with timeout; **injectable clock** (no real sleeps in tests).
- Engine calls `SafetyPolicy.validate` (CURSOR-05) before every action and emits `RunEvent`s (CURSOR-04).
- `UserSovereigntySignal` protocol (abstract "stop requested"/"user intervened"); firing it transitions to `Stopping` promptly.
- `SimulationExecutor` records "would do X" without touching macOS.
- Engine must not import AppKit/Accessibility.

**Files/modules to create:** `Sources/CoreEngine/{WorkflowEngine.swift, EngineState.swift, StepLifecycle.swift, TimingPolicy.swift, ActionExecutor.swift, UserSovereigntySignal.swift}`; `Sources/Actions/SimulationExecutor.swift`; `Tests/EngineTests/{TransitionTests.swift, LoopCapTests.swift, SovereigntyTests.swift, SafetyRoutingTests.swift}`.

**Technical implementation guidance:** Use Swift concurrency (`actor`/`Task`) with cancellation. All timing through the injected clock. The engine depends on abstractions (`ActionExecutor`, `UserSovereigntySignal`, clock), never concretes.

**Tests to write:** multi-step looping workflow via `SimulationExecutor` + fake clock asserts order, caps, retry/skip/abort; fired sovereignty signal halts within one step; every action passed through the safety gate; error path reaches `Stopping`.

**Acceptance criteria:** full workflows run in CI with no macOS APIs; all transitions covered; tests fast (no real sleeps); logs correct and content-free.

**What must NOT be changed:** Do not add real event execution here. Do not weaken the safety routing.

**Expected output/report:** state diagram (text), list files, report `EngineTests` output, confirm no AppKit import in `CoreEngine`.

**Standing rules:** only this milestone; no redesign; build+test; honest failures; no unrelated edits; buildable; editors read-only; no deceptive features.

---

# CURSOR-07 — macOS application detection

**Context:** First macOS-specific milestone. Implements enumeration of user-facing apps and frontmost detection via `NSWorkspace`. No activation, no input, no AX traversal. The app is **not** sandboxed.

**Objective:** Implement `AppControl` enumeration + frontmost app resolution, with testable filtering logic.

**Requirements:**
- List running apps filtered to `.regular` activation policy (drop helpers/agents).
- `frontmostApp()` returning bundle id + display name.
- Resolve a `TargetApp` by bundle id; detect "is this bundle id running."
- Filtering/mapping logic must be unit-testable via an injected process list (protocol-wrap `NSRunningApplication`).

**Files/modules to create:** `Sources/AppControl/{AppEnumerator.swift, FrontmostApp.swift, RunningAppsProvider.swift}`; `Tests/AppControlTests/{FilteringTests.swift}`.

**Technical implementation guidance:** Wrap `NSWorkspace.shared.runningApplications` behind a `RunningAppsProvider` protocol; tests inject fakes. Treat bundle id as "an app," not "a window." Do not activate anything.

**Tests to write (automated logic + documented manual):** unit-test that helper/non-`.regular` apps are excluded and mapping is correct with injected data; **manual checklist** (in `docs/manual-tests.md`): live enumerator lists Chrome/VS Code/Finder; frontmost updates as you switch apps.

**Acceptance criteria:** enumerator excludes helpers; frontmost detection correct live; resolve-by-bundle-id works; `FilteringTests` pass; manual checklist documented.

**What must NOT be changed:** No activation, no input synthesis, no AX. Do not modify pure-logic modules' semantics.

**Expected output/report:** list files, report `FilteringTests` output, paste the manual checklist, and the live enumeration result you observed (or state you couldn't run it and why).

**Standing rules:** only this milestone; no redesign; build+test; honest failures; no unrelated edits; buildable; editors read-only; no deceptive features.

---

# CURSOR-08 — Accessibility permission handling

**Context:** Building on prior milestones. Adds TCC Accessibility permission detection, guidance, and re-check. The grant is tied to the app's code signature (dev builds may lose it on rebuild) — document this.

**Objective:** Implement `Permissions` around `AXIsProcessTrustedWithOptions` with a testable state model and Settings deep-link.

**Requirements:**
- `PermissionState` = `unknown | denied | granted`, derived from an injectable "trusted?" probe.
- Request/prompt once; on denial, deep-link to System Settings → Privacy & Security → Accessibility (do not attempt to re-prompt).
- Re-check on app foreground (flip to granted without relaunch).
- README note on the signature-reset dev reality; recommend a stable local signing identity.

**Files/modules to create:** `Sources/Permissions/{AccessibilityPermission.swift, PermissionState.swift, TrustProbe.swift}`; `Tests/PermissionsTests/{StateTests.swift}`; update `docs/manual-tests.md` and `README.md`.

**Technical implementation guidance:** Wrap the trust check behind `TrustProbe` for tests. Provide the correct Settings URL. Keep UI minimal (a debug affordance is fine).

**Tests to write:** unit-test state transitions with an injected probe; **manual checklist**: real prompt appears, deep-link opens the right pane, toggling grants without relaunch, rebuild-loses-grant observed.

**Acceptance criteria:** correct granted/denied reporting; deep-link works; re-check flips to granted; `StateTests` pass; dev caveat documented.

**What must NOT be changed:** Do not read any AX content yet. Do not touch unrelated modules.

**Expected output/report:** list files, report `StateTests` output, paste manual checklist + what you observed live.

**Standing rules:** only this milestone; no redesign; build+test; honest failures; no unrelated edits; buildable; editors read-only; no deceptive features.

---

# CURSOR-09 — Coarse read-only AX + focus guard

**Context:** Building on prior milestones. Implements the minimal read-only Accessibility queries and the focus-guard invariant that gates all synthetic input. **No traversal of foreign document trees. No content is read or logged.**

**Objective:** Implement `CoarseAX` (three queries) and `FocusGuard`.

**Requirements:**
- `CoarseAX`: `frontmostAppBundleID()`, `focusedWindowExists()`, `focusedElementBundleID()` — nothing more.
- `FocusGuard.assert(target:) -> ok | changed | lost`: `ok` only if the target is frontmost and stable for a short debounce (debounce is a `TimingPolicy` value).
- All reads content-free; never capture titles/text into logs.
- Requires Accessibility permission (CURSOR-08).

**Files/modules to create:** `Sources/Accessibility/{CoarseAX.swift, FocusGuard.swift, AXProbe.swift}`; `Tests/AccessibilityTests/{FocusGuardTests.swift}`.

**Technical implementation guidance:** Wrap the raw AX calls behind an `AXProbe` protocol so `FocusGuard` logic is unit-tested with fakes (stable → ok, changed → changed, missing → lost). Use the injected clock/`TimingPolicy` for the debounce.

**Tests to write:** unit-test `FocusGuard` decisions against a fake probe; **manual checklist**: live coarse reads return correct frontmost/window state for Chrome/VS Code/Finder; changing apps mid-check yields `changed`.

**Acceptance criteria:** focus guard returns `ok` only when genuinely frontmost+stable; content never read/logged; `FocusGuardTests` pass; manual checklist documented.

**What must NOT be changed:** Do not deepen AX reads beyond the three queries. Do not synthesize input yet.

**Expected output/report:** list files, report `FocusGuardTests` output, confirm "no document content read," paste manual observations.

**Standing rules:** only this milestone; no redesign; build+test; honest failures; no unrelated edits; buildable; editors read-only; no deceptive features.

---

# CURSOR-10 — Input synthesis + self-event tagging + sovereignty monitor

**Context:** Building on prior milestones. Implements the **only** place that emits `CGEvent`s — tagged, inert, focus-guarded — plus the listen-only monitor that stops the run on real user input or a global hot-key while ignoring the app's own events.

**Objective:** Implement `InputSynthesis` (tagged scroll-wheel + inert keys) and `UserSovereigntyMonitor` (tag-filtered event tap + hot-key).

**Requirements:**
- Only allowlisted primitives can be constructed: scroll-wheel events and inert keys (arrows/Page/Home/End). Every emission is stamped with a **self-event tag** (source signature / event field) and is preceded by `FocusGuard.assert` (CURSOR-09) + `SafetyPolicy.validate` (CURSOR-05).
- `UserSovereigntyMonitor`: a **listen-only** event tap that **ignores** events carrying the self-tag and fires "user intervened" on any untagged input; plus a global stop hot-key (Carbon `RegisterEventHotKey`). Implements the CURSOR-06 `UserSovereigntySignal`.
- Detect Secure Input mode and surface it as a precondition failure (do not loop).

**Files/modules to create:** `Sources/InputSynthesis/{EventSynth.swift, SelfEventTag.swift, ScrollPrimitive.swift, InertKeyPrimitive.swift}`; `Sources/CoreEngine/UserSovereigntyMonitor.swift`; `Tests/InputSynthesisTests/{AllowlistConstructionTests.swift, TagFilterTests.swift}`.

**Technical implementation guidance:** Deliver events to the **frontmost focused target** (guaranteed by the focus guard), not a PID. Make the tag-filter logic unit-testable with injected events. Do not emit any Cmd/Ctrl chord or character key.

**Tests to write:** unit-test that only allowlisted primitives can be built; unit-test the monitor ignores tagged events and fires on untagged; **manual checklist**: a run's own scrolls don't stop it, but a real trackpad scroll and the hot-key stop it within ~100 ms; Secure Input surfaces a precondition failure.

**Acceptance criteria:** synthetic events fire only after focus guard + safety pass; monitor ignores self-events, reacts to real input + hot-key promptly; no non-inert event constructable; tests pass.

**What must NOT be changed:** Do not add character/chord keys. Do not bypass the focus guard or safety gate. Do not modify the safety allowlist.

**Expected output/report:** list files, report unit-test output, paste manual observations (self-scroll ignored, real input stops, hot-key stops, secure-input handled).

**Standing rules:** only this milestone; no redesign; build+test; honest failures; no unrelated edits; buildable; editors read-only; no deceptive features.

---

# CURSOR-11 — Walking-skeleton MVP (architecture proof)

**Context:** Building on prior milestones. Wires the spine into one hardcoded scroll loop against the frontmost app — the smallest end-to-end proof. First time the **real executor** is plugged into the engine. **Do not start any adapter (CURSOR-12+) until this holds.**

**Objective:** A menu-bar-driven hardcoded workflow that scrolls the frontmost app up/down on a timer, read-only, stoppable, truthfully logged.

**Requirements:**
- `RealExecutor` implementing `ActionExecutor` (CURSOR-06), routing every action through `SafetyPolicy.validate` → `FocusGuard.assert` → `InputSynthesis`.
- One hardcoded loop (no JSON, no editor UI): `FocusGuard.assert` → tagged **scroll down** → predicate-wait → tagged **scroll up** → repeat N → stop → verify + content-free log.
- Menu-bar Start/Stop + global hot-key drive it; permission onboarding (CURSOR-08) gates Start.

**Files/modules to create:** `Sources/Actions/{ScrollAction.swift, RealExecutor.swift}`; `App/MenuBar/SkeletonControls.swift`; update `docs/manual-tests.md`.

**Technical implementation guidance:** Reuse the engine, timing, safety, focus guard, input synthesis, and monitor as-is — this is wiring, not new subsystems. Keep the workflow literally hardcoded.

**Tests to write:** engine + `RealExecutor` exercised via `SimulationExecutor` seam in CI (no real events); **manual acceptance**: point at a frontmost Chrome or VS Code window, Start, observe scroll up/down touching no text; stop instantly on mouse/keyboard/hot-key; read the truthful log.

**Acceptance criteria (MVP done):** permission onboarding works on a fresh account; loop scrolls frontmost app without mutating anything; run never self-stops but stops instantly on real input/hot-key; focus verified/restored; log truthful + content-free; safety + engine unit tests green.

**What must NOT be changed:** Do not add new actions beyond scroll. Do not bypass safety/focus guard. Do not implement JSON/UI editor here.

**Expected output/report:** list files, report CI test output, paste the full manual acceptance run (what you did, what happened, the log lines). If any acceptance point fails, report it plainly — do not proceed to CURSOR-12.

**Standing rules:** only this milestone; no redesign; build+test; honest failures; no unrelated edits; buildable; editors read-only; no deceptive features.

---

# CURSOR-12 — Chrome navigation adapter

**Context:** Building on the proven skeleton (CURSOR-11). Adds a browser adapter that navigates an already-frontmost Chrome window using app-agnostic inert primitives, with capability probing and graceful degradation. **Tab switching is out of scope** (unverifiable).

**Objective:** Implement `BrowserAdapter` for scroll + page navigation in Chrome via inert primitives.

**Requirements:**
- At run start, **probe** what Chrome reliably supports; otherwise **degrade** to scroll-wheel + inert keys (the dependable path).
- Actions: scroll, page (Page Up/Down/Home/End). All route through the CURSOR-11 real-executor path (safety → focus guard → input synthesis).
- **No tab switching**; if ever added later it must be marked `unverified`. Do not read Chrome's web AX tree for navigation.

**Files/modules to create:** `Sources/Adapters/BrowserAdapter.swift`; `Tests/AdapterTests/{BrowserProbeTests.swift}`; update `docs/manual-tests.md`.

**Technical implementation guidance:** Make probe → primitive selection unit-testable with injected probe results. Cap scroll/page amounts. Rely on the focus guard to ensure Chrome is frontmost.

**Tests to write:** unit-test probe→primitive selection with injected results (including probe-failure → degrade); **manual**: scroll/page a long Chrome article, confirm only the viewport moves and nothing is entered/changed.

**Acceptance criteria:** Chrome scroll/page works via inert primitives; probe failure degrades rather than errors; no tab/content mutation; logs content-free; tests pass.

**What must NOT be changed:** Do not add tab switching. Do not deepen AX usage. Do not modify safety/engine.

**Expected output/report:** list files, report unit-test output, paste manual observations for Chrome.

**Standing rules:** only this milestone; no redesign; build+test; honest failures; no unrelated edits; buildable; editors read-only; no deceptive features.

---

# CURSOR-13 — Read-only code-editor navigation

**Context:** Building on prior milestones. Adds an editor adapter (VS Code) that is **strictly read-only** and proven not to mutate files. **No Cmd/Ctrl chords** (rebindable to destructive commands under keymaps like Vim).

**Objective:** Implement `EditorAdapter` for `editor`-class targets: scroll + arrows/Page/Home/End only, with a mutation-guard integration test.

**Requirements:**
- Editor targets may emit **only** inert primitives (scroll-wheel + arrows/Page/Home/End); safety gate enforces `mutatesText == false` and the inert-key allowlist.
- Absolutely no character keys, Return, Delete, paste, save, or command execution. No Cmd/Ctrl navigation chords.
- Route through the CURSOR-11 real-executor path.

**Files/modules to create:** `Sources/Adapters/EditorAdapter.swift`; `Tests/AdapterTests/{EditorAdapterTests.swift, MutationGuardTests.swift}`; update `docs/manual-tests.md`.

**Technical implementation guidance:** The mutation-guard test hashes a scratch source file before/after a navigation run and asserts equality. Run the manual version with the VS Code Vim extension enabled to confirm inert keys stay inert.

**Tests to write:** unit-test that the editor adapter can only emit inert primitives; **mutation-guard integration/manual**: open a scratch file in VS Code, run the loop, assert file hash + mtime unchanged; repeat with Vim keymap.

**Acceptance criteria:** editor navigation scrolls/pages/moves caret via arrows without changing the file; hash identical before/after; safety suite still green; works with and without Vim keymap.

**What must NOT be changed:** Do not add any non-inert key. Do not relax the safety allowlist. Do not modify engine/safety internals.

**Expected output/report:** list files, report unit-test output + the before/after file hashes from the mutation-guard test (with and without Vim). If the file changed at all, report it as a failure and stop.

**Standing rules:** only this milestone; no redesign; build+test; honest failures; no unrelated edits; buildable; **editors strictly read-only**; no deceptive features.

---

# CURSOR-14 — Workflow configuration surface

**Context:** Building on prior milestones. Wires user-authored, validated workflows (CURSOR-03 config) through the engine and adapters — replacing the hardcoded skeleton loop. Minimal selector UI is fine; the rich editor comes in CURSOR-15.

**Objective:** Implement `WorkflowRunner` that loads → validates → resolves targets → selects adapters → runs on the engine.

**Requirements:**
- Load a `Workflow` via `ConfigStore` (CURSOR-03), validate (CURSOR-03 + CURSOR-05), resolve targets (CURSOR-07), select adapter (Browser/Editor/Generic), run on the engine (CURSOR-06) via `RealExecutor` (CURSOR-11).
- Honor loop caps and per-step on-error policy.
- A target with no specific adapter falls back to a `GenericAdapter` (inert primitives) or is refused with a clear error.

**Files/modules to create:** `Sources/CoreEngine/WorkflowRunner.swift`; `Sources/Adapters/GenericAdapter.swift`; `Tests/EngineTests/{RunnerTests.swift}`; `Tests/AdapterTests/{ResolutionTests.swift}`.

**Technical implementation guidance:** Keep adapter selection a pure function of `TargetApp.class` for testability. Validate before any action runs.

**Tests to write:** load a sample multi-target workflow JSON and run it via the simulation seam (CI); assert validation rejects illegal workflows before any action; assert target→adapter resolution is correct; **manual**: run a small multi-app workflow live.

**Acceptance criteria:** JSON-defined workflows run end-to-end with correct adapter selection, caps, and content-free logs; invalid workflows never start; tests pass.

**What must NOT be changed:** Do not bypass the validator or safety gate. Do not build the rich editor UI here.

**Expected output/report:** list files, report `RunnerTests`/`ResolutionTests` output, paste a manual multi-target run summary.

**Standing rules:** only this milestone; no redesign; build+test; honest failures; no unrelated edits; buildable; editors read-only; no deceptive features.

---

# CURSOR-15 — UI / control layer

**Context:** Building on prior milestones. Adds the real user-facing UI so a person builds, runs, and monitors workflows without touching JSON.

**Objective:** Implement `MenuBarExtra` controls, a workflow editor window, permission onboarding UI, and a live run-timeline view.

**Requirements:**
- Menu-bar: start/stop, pick workflow, live status (current step/elapsed/next).
- Editor window: add/reorder/remove steps from the action palette, set waits/loop count, choose targets from the running-apps list (CURSOR-07). Validate composed steps using CURSOR-03/CURSOR-05 so illegal steps can't be saved.
- Permission onboarding flow (CURSOR-08).
- Live run timeline backed by the `RunRecorder` (CURSOR-04).
- Engine runs off the main thread; UI updates on main.
- Honest UX copy: what it does and what it will never do.

**Files/modules to create:** `App/{MenuBar/, Editor/, Onboarding/, Timeline/}` views + view models; `Tests/UITests/{OnboardingUITests.swift, StartStopUITests.swift}`; `Tests/AppTests/{ViewModelTests.swift}`.

**Technical implementation guidance:** Keep business logic in view models observing engine state; views are thin. Use XCUITest for the two critical flows only.

**Tests to write:** XCUITest for onboarding + start/stop happy paths; view-model logic tests; **manual**: full build-and-run of a workflow through the UI on a fresh account.

**Acceptance criteria:** you create, save, and run a workflow entirely via UI including first-run permission setup; live status + timeline reflect reality; UI never blocks on the engine; tests pass.

**What must NOT be changed:** Do not let the editor compose illegal (mutating) steps. Do not move business logic into views. Do not alter safety/engine internals.

**Expected output/report:** list files, report UI + view-model test output, paste a manual end-to-end UI run summary.

**Standing rules:** only this milestone; no redesign; build+test; honest failures; no unrelated edits; buildable; editors read-only; no deceptive features.

---

# CURSOR-16 — Error recovery hardening

**Context:** Building on prior milestones. Makes every failure degrade safely, restore focus, and log the truth. Threads the typed error taxonomy end-to-end.

**Objective:** Implement recovery: TOCTOU handling, mid-run permission loss, Secure Input, verified focus restoration, and typed errors throughout.

**Requirements:**
- Typed errors end-to-end: `PermissionError`, `PreconditionError`, `ActionError`, `ForbiddenActionError`, `TimeoutError`.
- Re-assert the focus guard **immediately before** each event; unexpected front-app change → treat as user intervention → stop.
- Mid-run permission loss (AX calls failing) → stop with a clear message.
- Secure Input detected → `PreconditionError`, no loop.
- Verified focus restoration at stop; if it fails, log an honest "couldn't restore focus."
- Cap retries per step.

**Files/modules to create/modify:** `Sources/CoreEngine/Recovery.swift`; thread error handling through engine/executor/adapters (modify those files minimally); `Tests/EngineTests/{RecoveryTests.swift}`.

**Technical implementation guidance:** Inject failures via the simulation seam to test transitions deterministically. Never swallow `ForbiddenActionError` or permission loss.

**Tests to write:** inject each failure (simulated) and assert correct transition, message, and safe stop; **manual**: quit the target app mid-run and revoke Accessibility mid-run — both produce clean stops, clear messages, accurate logs, no crash.

**Acceptance criteria:** all failure injections yield safe stops + truthful logs; focus restoration verified or honestly reported; no failure leaves the engine stuck or crashes; tests pass.

**What must NOT be changed:** Do not swallow forbidden/permission errors. Do not add retry loops without caps. Do not change safety semantics.

**Expected output/report:** list modified files, report `RecoveryTests` output, paste manual failure-injection observations.

**Standing rules:** only this milestone; no redesign; build+test; honest failures; no unrelated edits; buildable; editors read-only; no deceptive features.

---

# CURSOR-17 — Testing pass

**Context:** Building on prior milestones. Consolidates the test pyramid and documents realistic automation boundaries (TCC can't be granted in ordinary CI).

**Objective:** Lock in the safety-suite merge gate, consolidate tests, and document manual + provisioned-runner testing.

**Requirements:**
- Ensure pure-logic tests (state machine, safety, config, redaction) run in CI; safety suite is a **merge gate**.
- Component tests drive whole workflows via `SimulationExecutor`.
- Keep the mutation-guard test (CURSOR-13) green.
- Document a **manual matrix** (Chrome/VS Code/Finder × supported macOS versions) and a **provisioned integration** path (self-hosted GUI runner with PPPC/MDM profile pre-granting Accessibility).

**Files/modules to create/modify:** consolidate `Tests/`; `docs/testing.md`; update `scripts/ci.sh` to enforce the safety gate.

**Technical implementation guidance:** Keep flaky live tests **out** of the merge gate; gate on pure logic only. Don't pretend generic CI can do end-to-end.

**Tests to write:** ensure the full pure-logic suite is green in CI; add any missing coverage for the state machine and safety matrix; verify the gate fails on a deliberately broken safety test (then revert the break).

**Acceptance criteria:** CI green; safety-suite gate enforced (proven by a temporary break); testing boundaries documented; manual matrix executed once and recorded.

**What must NOT be changed:** Do not add live/flaky tests to the merge gate. Do not weaken existing tests to make them pass.

**Expected output/report:** report the full CI run, show the gate failing then passing (break/revert), paste `docs/testing.md` outline and the manual-matrix results.

**Standing rules:** only this milestone; no redesign; build+test; honest failures; no unrelated edits; buildable; editors read-only; no deceptive features.

---

# CURSOR-18 — Packaging & distribution

**Context:** Final milestone. Produces a Developer-ID-signed, notarized DMG. **The app must NOT enable App Sandbox** (AX control of other apps is sandbox-incompatible; this also rules out the Mac App Store).

**Objective:** Sign, notarize, staple, and package the app as a DMG a clean machine can install and trust.

**Requirements:**
- Enable **hardened runtime**; set **minimal entitlements**; **no App Sandbox**.
- Required `Info.plist` usage strings.
- Sign with **Developer ID Application**; notarize via `notarytool`; staple; package with `create-dmg`.
- Optional: Sparkle signed auto-updates (only if time permits; keep it isolated).
- Ship short user docs (what it does / never does / how to grant permission / how to read logs).

**Files/modules to create:** `scripts/{sign.sh, notarize.sh, staple.sh, make-dmg.sh}`; entitlements file; updated `Info.plist`; `docs/{install.md, privacy.md}`.

**Technical implementation guidance:** Keep a stable Developer ID so the Accessibility grant survives updates. Double-check App Sandbox is **off** (turning it on silently breaks AX).

**Tests to write:** **manual** — on a second Mac / fresh user account, the downloaded DMG opens without Gatekeeper blocking, the app requests Accessibility correctly, and a workflow runs.

**Acceptance criteria:** notarization succeeds and is stapled; clean-machine install works; permission flow works post-install; versioned release artifact produced.

**What must NOT be changed:** Do not enable App Sandbox. Do not change signing identity casually. Do not alter app behavior — this milestone is packaging only.

**Expected output/report:** report the sign/notarize/staple output (redact secrets), confirm sandbox is off, paste the clean-machine install + run results. Report any Gatekeeper/notarization rejection verbatim.

**Standing rules:** only this milestone; no redesign; build+test; honest failures; no unrelated edits; buildable; editors read-only; no deceptive features.

---

## Using these prompts

- Run them **in order**. Do not begin CURSOR-12 until CURSOR-11 (the walking skeleton) fully passes its acceptance run.
- If Cursor reports a failure, fix within the **same** milestone before advancing — don't let breakage roll forward.
- If Cursor tries to redesign, add scope, or touch unrelated files, stop it and re-paste the "What must NOT be changed" + standing rules.
- Keep the safety suite (CURSOR-05) green at all times; it's your merge gate and your read-only guarantee.
