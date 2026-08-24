# Waypoint — Implementation Roadmap (for Cursor)

This turns the **revised architecture** into an ordered set of small, PR-sized milestones you can hand to Cursor one at a time. Each milestone is self-contained: it has a single objective, ships with tests, leaves the repo building and green, and avoids depending on milestones that come after it.

**How to use this with Cursor:** treat each milestone as one focused session/PR. Do *not* paste the whole roadmap as a single prompt — you'll get sprawling, unfocused output. Instead, later we'll expand each milestone into its own tight Cursor prompt. This document is the map; the prompts come next.

---

## Why this order differs from the suggested one

Your suggested progression is close, but the architecture forces three changes:

1. **Safety is a keystone, not an afterthought.** The single policy gate + capability tags + inert-primitive allowlist must exist and be tested **before** anything performs a real action. It's pure logic, so it's cheap to build early and it makes every later milestone safe by construction. It becomes **M4**, ahead of the engine and all interaction.

2. **"Safe application/window interaction" is really four separate testable units.** App detection, permission handling, coarse read-only AX + focus guard, and tagged input synthesis + kill switch each deserve their own milestone (**M6–M9**) because they fail for different reasons and test differently.

3. **There's an explicit Walking-Skeleton MVP milestone (M10).** After the four interaction units exist, one milestone wires them into a single hardcoded scroll loop against the frontmost app. This is the architecture-proof point — if it holds, everything after is low-risk addition. Chrome and editor adapters come *after* the skeleton, not before.

**Resulting sequence:** M0 foundation → M1 domain+tags → M2 config → M3 logging → **M4 safety** → M5 engine+simulation → M6 app detection → M7 permission → M8 coarse AX + focus guard → M9 input synthesis + kill switch → **M10 walking-skeleton MVP** → M11 Chrome adapter → M12 editor adapter → M13 workflow-config surface → M14 UI → M15 error recovery → M16 testing pass → M17 packaging.

Milestones **M0–M5 need no macOS permissions and run fully in CI.** The macOS-specific risk starts at M6.

---

## Milestone template

Every milestone below uses the same shape:

- **Objective** — the one thing it delivers.
- **Cursor implements** — what to actually build.
- **Files/modules** — created or modified.
- **Tests** — what proves it.
- **Acceptance criteria** — done means all of these.
- **Failure modes** — what to watch for.
- **Depends on** — earlier milestones only.

---

## M0 — Project foundation

**Objective:** an empty but correctly-structured, buildable macOS app + Swift package layout, with CI running pure-logic tests.

**Cursor implements:** an Xcode app target (SwiftUI, `MenuBarExtra` showing only "Quit") plus local Swift packages matching the module layout. A CI script (GitHub Actions or local `xcodebuild`/`swift test`) that builds and runs unit tests for the pure-logic packages. README stating what the app does and the read-only/anti-deception invariants. `.gitignore`, license.

**Files/modules:** `App/` (entry point, MenuBarExtra), `Sources/{Domain,Config,Safety,CoreEngine,Actions,Observability,Accessibility,InputSynthesis,AppControl,Permissions,Adapters,Timing}` as empty package stubs, `Tests/` mirrors, `Package.swift`, `scripts/ci.sh`, `README.md`.

**Tests:** a trivial `XCTest` in one pure package so CI has something green to run.

**Acceptance criteria:** app launches and quits; `swift test` passes; CI is green; every module folder exists and compiles as an empty target.

**Failure modes:** mixing app-only Apple frameworks into pure-logic packages (breaks CI on Linux/headless) — keep `Domain/Config/Safety/CoreEngine/Timing` free of AppKit/AX imports. Xcode "package can't find product" wiring mistakes.

**Depends on:** nothing.

---

## M1 — Domain model & capability tags

**Objective:** the closed action set and workflow types, with safety metadata baked into each action.

**Cursor implements:** `ActionKind` as a closed enum (the v1 actions: `activateApp`, `switchWindow`, `scroll`, `pageNavigate`, `openExistingFile`, `wait`, `returnToPrevious` — **note: no `switchTab`, no text/paste/delete/save cases exist**). Each action exposes **capability tags**: `mutatesText: Bool` (always `false`), `requiresFocusGuard: Bool`, `verifiable: Bool`, `primitive: .scrollWheel | .inertKey | .appControl | .none`. `Workflow`, `Step` (action + timeout + retry policy + on-error), `TargetApp` (bundle id + class: `browser | editor | finder | generic`), and the error taxonomy enum.

**Files/modules:** `Sources/Domain/{ActionKind.swift, CapabilityTags.swift, Workflow.swift, Step.swift, TargetApp.swift, DomainError.swift}`.

**Tests:** assert every `ActionKind` reports `mutatesText == false`; assert tag lookups are total (a compile-time-exhaustive switch, so adding an action forces a tag decision).

**Acceptance criteria:** types compile; a test enumerates all actions and confirms tags exist for each; no action can be constructed that mutates text.

**Failure modes:** using a non-exhaustive switch for tags (a future action silently gets default/unsafe tags) — enforce exhaustiveness. Leaking a "generic keystroke with arbitrary string" parameter into the enum — forbidden.

**Depends on:** M0.

---

## M2 — Configuration system

**Objective:** load, validate, save, and version workflow config as JSON.

**Cursor implements:** `Codable` conformances for the domain types; a `ConfigStore` that reads/writes `~/Library/Application Support/Waypoint/workflows.json`; a top-level `schemaVersion` with a migration hook; and a **validator** that rejects any workflow whose step is illegal for its target class (leaning on M1 tags — e.g., an editor target may only carry `mutatesText == false` actions, which all v1 actions satisfy, plus future-proofing the check).

**Files/modules:** `Sources/Config/{ConfigStore.swift, SchemaVersion.swift, Migration.swift, WorkflowValidator.swift}`, `Tests/ConfigTests/`.

**Tests:** round-trip encode/decode equality; validator rejects a hand-crafted illegal workflow and accepts a legal one; a v(N-1)→v(N) migration fixture upgrades correctly.

**Acceptance criteria:** a sample JSON loads, validates, and round-trips byte-stably; invalid configs are rejected with a clear typed error; migration test passes.

**Failure modes:** enum-with-associated-values JSON is fiddly — pin the encoding format and test it. Silent acceptance of unknown future keys (decide: strict vs lenient) — choose strict-with-clear-error for v1.

**Depends on:** M1.

---

## M3 — Logging & redaction

**Objective:** truthful, content-free run logging.

**Cursor implements:** `os.Logger` categories (engine, executor, safety, permissions, adapter); a `RunRecorder` writing structured JSONL of `{timestamp, actionKind, targetBundleID, result}` — **and nothing else**. A **redaction rule**: the recorder API accepts only these fields; there is no path to log window text, document content, keystrokes, or file contents.

**Files/modules:** `Sources/Observability/{Log.swift, RunRecorder.swift, RunEvent.swift}`, `Tests/ObservabilityTests/`.

**Tests:** a test that constructs run events and asserts the serialized output contains only the allowed fields; a compile/shape test that there's no API accepting free-form content strings for the log.

**Acceptance criteria:** JSONL output matches the fixed schema exactly; no API surface allows logging app content; logs are human-readable and truthful.

**Failure modes:** a convenience `log(_ message: String)` sneaking back in and becoming a content leak — do not add one. Unbounded log growth — add rotation/size cap.

**Depends on:** M0 (uses Domain types from M1 for `actionKind`).

---

## M4 — Safety policy engine (the keystone)

**Objective:** the single gate that enforces read-only, inert-primitive-only execution.

**Cursor implements:** `SafetyPolicy.validate(action:, target:) -> Decision` (`allow` / `deny(reason)`), driven by M1 capability tags: editors (and everything) require `mutatesText == false`; only `.scrollWheel` and `.inertKey` primitives may be emitted as synthetic input; `.appControl` is allowed but must be `verifiable`. The **inert-key allowlist** (arrows, Page Up/Down, Home/End — *no* Cmd/Ctrl chords, *no* character/Return/Delete keys) lives here as data. A `ForbiddenActionError` that is always logged, never swallowed.

**Files/modules:** `Sources/Safety/{SafetyPolicy.swift, InertKeyAllowlist.swift, Decision.swift}`, `Tests/SafetyTests/` (the suite that must never go red).

**Tests:** the **safety suite** — for every `ActionKind` × target class, assert the decision; assert every key outside the allowlist is denied; assert no primitive other than scroll-wheel/inert-key can be emitted. Property test: no input can produce an `allow` for a mutating operation.

**Acceptance criteria:** safety suite is comprehensive and green; a deliberately-added mutating fixture is denied; CI is wired so a red safety suite **blocks merge**.

**Failure modes:** policy checks duplicated in multiple places and drifting — this is the *single* gate; later milestones must route through it. Allowlist defined as code branches instead of data — keep it declarative and testable.

**Depends on:** M1.

---

## M5 — Workflow/state-machine engine + SimulationExecutor

**Objective:** run whole workflows deterministically with zero real events, provable in CI.

**Cursor implements:** the engine state machine (`Idle → Arming → Running ⇄ Paused → Stopping → Idle`, with `Error → Stopping`); per-step lifecycle (`Pending → Validating → Executing → Settling → Completed | Failed → {Retry|Skip|Abort}`); loop support with **max-iteration and wall-clock caps**; a **`TimingPolicy`** abstraction for predicate-based waits with timeouts (injected, so tests use a fake clock); an `ActionExecutor` protocol; and a **`SimulationExecutor`** that records "would do X" without touching macOS. The engine calls `SafetyPolicy.validate` (M4) before every action and emits `RunRecorder` events (M3). A `UserSovereigntySignal` protocol (abstract "user intervened" / "stop requested") so the engine is testable without a real event tap.

**Files/modules:** `Sources/CoreEngine/{WorkflowEngine.swift, EngineState.swift, StepLifecycle.swift, TimingPolicy.swift, ActionExecutor.swift, UserSovereigntySignal.swift}`, `Sources/Actions/SimulationExecutor.swift`, `Tests/EngineTests/`.

**Tests:** drive a multi-step looping workflow through the SimulationExecutor with a fake clock; assert order, loop caps, retry/skip/abort paths, and that a fired `UserSovereigntySignal` transitions to `Stopping` promptly; assert every action passed through the safety gate.

**Acceptance criteria:** full workflows run in CI with no macOS APIs; all lifecycle transitions covered; injected stop signal halts within one step; logs produced are correct and content-free.

**Failure modes:** hidden real sleeps making tests slow/flaky — all timing must go through the injected `TimingPolicy`/clock. Engine touching AppKit (breaks CI purity) — keep it framework-free; real executors come later.

**Depends on:** M1, M3, M4.

---

## M6 — macOS application detection

**Objective:** reliably enumerate and identify targetable, user-facing apps and the frontmost app.

**Cursor implements:** `AppControl` over `NSWorkspace`/`NSRunningApplication`: list apps filtered to `.regular` activation policy (drop helpers/agents), expose `frontmostApp()`, resolve a `TargetApp` by bundle id, and detect "is this bundle id currently running." No activation yet.

**Files/modules:** `Sources/AppControl/{AppEnumerator.swift, FrontmostApp.swift}`, `Tests/AppControlTests/` (thin — mostly manual, see below).

**Tests:** unit-test the *filtering/mapping* logic with injected fake process lists; **manual** test that the live enumerator lists Chrome/VS Code/Finder and correctly reports the frontmost app as you switch.

**Acceptance criteria:** enumerator excludes helper processes; frontmost detection matches reality as you switch apps; resolving a known bundle id works.

**Failure modes:** Chrome/Electron spawn many helper PIDs — filtering by `.regular` + bundle id is essential. Multiple instances/profiles share a bundle id — treat bundle id as "an app," not "a window." Sandboxing would block this — confirm the app is **not** sandboxed (architectural: no App Sandbox).

**Depends on:** M1. (Independent of M2–M5 at runtime.)

---

## M7 — Accessibility permission handling

**Objective:** detect, request, guide, and re-check the TCC Accessibility permission — including the dev-signature-reset reality.

**Cursor implements:** `Permissions` wrapping `AXIsProcessTrustedWithOptions`; a state model (`unknown/denied/granted`); a deep-link to System Settings → Privacy & Security → Accessibility; a re-check on app foreground; and clear handling of the fact that the grant is tied to the app's code signature (so unsigned/ad-hoc dev builds lose it on rebuild).

**Files/modules:** `Sources/Permissions/{AccessibilityPermission.swift, PermissionState.swift}`, plus a tiny debug UI or CLI affordance to show current state; `Tests/PermissionsTests/` (logic only).

**Tests:** unit-test the state transitions with an injected "trusted?" probe; **manual** test the real prompt/deep-link/re-check loop, and the rebuild-loses-grant behavior during development.

**Acceptance criteria:** app correctly reports granted vs denied; deep-link opens the right pane; re-check flips to granted without relaunch after you toggle it; the dev-signature caveat is documented in README.

**Failure modes:** the prompt only appears once — after denial you must deep-link, not re-prompt. Development builds constantly losing the grant confuses testing — use a stable local signing identity to reduce churn.

**Depends on:** M0. (Independent of others.)

---

## M8 — Coarse read-only AX + focus guard

**Objective:** the minimal, reliable Accessibility reads, plus the focus-guard invariant that gates all synthetic input.

**Cursor implements:** `Accessibility` module exposing only **coarse, read-only** queries: `frontmostAppBundleID()`, `focusedWindowExists()`, `focusedElementBundleID()`. Built on these, a `FocusGuard.assert(target:)` that returns `ok` only if the intended target is frontmost and has been stable for a short debounce, else `changed`/`lost`. **No traversal of foreign document trees.** All reads are content-free (no titles/text captured into logs).

**Files/modules:** `Sources/Accessibility/{CoarseAX.swift, FocusGuard.swift}`, `Tests/AccessibilityTests/` (logic with injected AX probe).

**Tests:** unit-test `FocusGuard` decision logic against a fake AX probe (stable → ok; changed → changed; missing → lost); **manual** test that live coarse reads return correct frontmost/window state for Chrome/VS Code/Finder.

**Acceptance criteria:** focus guard returns `ok` only when the target is genuinely frontmost and stable; changing apps mid-check yields `changed`; no document content is ever read or logged.

**Failure modes:** over-reading the AX tree (privacy + fragility) — restrict to the three coarse queries. Debounce too short (races) or too long (sluggish) — make it a `TimingPolicy` value. Electron/Chrome AX quirks — you're only reading app/window identity, which is dependable; do not go deeper.

**Depends on:** M1, M7 (needs permission to read AX). Uses `TimingPolicy` from M5.

---

## M9 — Input synthesis + self-event tagging + user-sovereignty monitor

**Objective:** emit only inert, tagged synthetic input, and stop instantly on untagged human input or the global hot-key.

**Cursor implements:** `InputSynthesis` as the **only** place emitting `CGEvent`s — tagged scroll-wheel events and inert-key events (arrows/Page/Home/End), each stamped with a source signature so they're identifiable as self-generated. Every emission is preceded by `FocusGuard.assert` (M8) and `SafetyPolicy.validate` (M4). A `UserSovereigntyMonitor` implementing the M5 signal: a **listen-only** event tap that ignores events carrying the self-tag and fires "user intervened" on any untagged input; plus a global stop hot-key (Carbon `RegisterEventHotKey`).

**Files/modules:** `Sources/InputSynthesis/{EventSynth.swift, SelfEventTag.swift, ScrollPrimitive.swift, InertKeyPrimitive.swift}`, `Sources/CoreEngine/UserSovereigntyMonitor.swift`, `Tests/InputSynthesisTests/`.

**Tests:** unit-test that only allowlisted key codes/scroll primitives can be constructed; unit-test the monitor's tag-filtering logic with injected events (tagged → ignored, untagged → fires); **manual** test that a run's own scrolls don't stop it, but a real trackpad scroll or the hot-key does, within ~100 ms.

**Acceptance criteria:** synthetic scroll/inert-key events fire only after focus guard + safety pass; the monitor ignores self-events and reacts to real ones and the hot-key promptly; no non-inert event can be emitted.

**Failure modes:** the self-event feedback loop (app stops itself) — the tag filter is mandatory and must be tested. Secure Input mode (password fields/some terminals) silently drops synthetic events — detect and surface as a `PreconditionFailed`, don't loop. `postToPid` unreliability — deliver to the frontmost focused target (guaranteed by the focus guard), not a PID.

**Depends on:** M4, M5, M8.

---

## M10 — Walking-skeleton MVP (architecture proof)

**Objective:** wire the spine into one hardcoded scroll loop against the frontmost app — the smallest thing that proves the whole architecture.

**Cursor implements:** a single hardcoded workflow (no editor UI, no JSON): against **the app the user currently has in front**, loop N times: `FocusGuard.assert` → tagged **scroll down** → predicate-wait → tagged **scroll up** → stop → verify + content-free log. A menu-bar "Start"/"Stop" and the global hot-key drive it. This is the real executor plugged into the M5 engine for the first time.

**Files/modules:** `Sources/Actions/{ScrollAction.swift, RealExecutor.swift}` (real executor routing through Safety+FocusGuard+InputSynthesis), `App/MenuBar/SkeletonControls.swift`, `Tests/` integration notes.

**Tests:** engine + RealExecutor exercised via the SimulationExecutor in CI; **manual acceptance**: point at a frontmost Chrome or VS Code window, Start, watch it scroll up/down on a timer touching no text, and confirm instant stop on mouse/keyboard/hot-key with a truthful log.

**Acceptance criteria (this is the MVP definition of done):** permission onboarding works on a fresh account; the loop scrolls the frontmost app without mutating anything; the run never self-stops but stops instantly on real input or hot-key; focus is verified/restored; the log is truthful and content-free; safety + engine unit tests pass in CI.

**Failure modes:** all the earlier ones surfacing together — this milestone is where the integration risk lives, which is exactly why it's isolated and comes before adapters.

**Depends on:** M4, M5, M8, M9. (This is the gate; do not start M11+ until M10 holds.)

---

## M11 — Chrome navigation adapter

**Objective:** navigate an already-frontmost Chrome window using app-agnostic inert primitives, with capability probing.

**Cursor implements:** a `BrowserAdapter` that, at run start, **probes** what Chrome reliably supports and otherwise **degrades** to scroll-wheel + inert keys (the dependable path). Actions: scroll, page (Page Up/Down/Home/End). **Tab switching stays out** (unverifiable; explicitly deferred and marked `unverified` if ever added). Everything routes through the M10 real executor path.

**Files/modules:** `Sources/Adapters/BrowserAdapter.swift`, `Tests/AdapterTests/` (probe/degrade logic with fakes).

**Tests:** unit-test probe→primitive selection with injected capability results; **manual** test scrolling/paging a real Chrome page (including a long article) touches nothing but the viewport.

**Acceptance criteria:** Chrome scroll/page works via inert primitives; when a probe fails, it degrades rather than erroring; no tab/content mutation; logs content-free.

**Failure modes:** relying on Chrome's AX web tree (fragile) — don't; use inert primitives. Chrome not frontmost — focus guard refuses. Scroll overshoot — acceptable (read-only), but cap amounts.

**Depends on:** M10.

---

## M12 — Read-only code-editor navigation

**Objective:** navigate a frontmost editor (VS Code) strictly read-only, proven not to mutate.

**Cursor implements:** an `EditorAdapter` for `editor`-class targets: scroll + arrows/Page/Home/End **only**, with the safety gate enforcing `mutatesText == false` and the inert-key allowlist. Explicitly **no Cmd/Ctrl chords** (they're rebindable to destructive commands, e.g., under a Vim keymap). Same real-executor path.

**Files/modules:** `Sources/Adapters/EditorAdapter.swift`, `Tests/AdapterTests/`, plus a **mutation-guard integration test** using a scratch file.

**Tests:** unit-test that the editor adapter can only emit inert primitives; **manual/integration**: open a scratch source file in VS Code, run the navigation loop, then assert (by file hash/mtime) the file is **unchanged**; repeat with the Vim extension enabled to confirm inert keys stay inert.

**Acceptance criteria:** editor navigation scrolls/pages/moves the caret via arrows without changing the file; file hash identical before/after; safety suite still green; works with and without a Vim keymap.

**Failure modes:** a "helpful" chord slipping into the allowlist — forbidden. Editor in a modal/insert state — inert keys (arrows/page) remain non-mutating; character keys never exist in the code path. Misdelivery — focus guard prevents; and even a misdelivered arrow/page key is non-destructive.

**Depends on:** M10.

---

## M13 — Workflow configuration surface

**Objective:** run user-authored, validated workflows (from M2 config) through the engine and adapters — not just hardcoded ones.

**Cursor implements:** the glue that loads a `Workflow` via `ConfigStore` (M2), validates it (M2 validator + M4 safety), resolves targets (M6), selects adapters (M11/M12), and runs it on the engine (M5) via the real executor (M10). Loop caps and per-step on-error policy honored. Still no rich UI — a minimal selector is fine.

**Files/modules:** `Sources/CoreEngine/WorkflowRunner.swift` (or extend engine wiring), `Tests/EngineTests/` integration with real adapters behind the simulation seam where possible.

**Tests:** load a sample multi-target workflow JSON and run it (simulated in CI; live manual); assert validation rejects illegal workflows before any action; assert target→adapter resolution is correct.

**Acceptance criteria:** a JSON-defined workflow runs end-to-end across Chrome/editor/Finder targets with correct adapter selection, caps, and content-free logs; invalid workflows never start.

**Failure modes:** a target with no matching adapter — fall back to `GenericAdapter` (inert primitives) or refuse clearly. Config drift vs engine expectations — the validator is the guard.

**Depends on:** M2, M6, M10, M11, M12.

---

## M14 — UI / control layer

**Objective:** a real person builds, runs, and monitors workflows without touching JSON.

**Cursor implements:** `MenuBarExtra` controls (start/stop, pick workflow, live status: current step/elapsed/next); a workflow editor window (add/reorder/remove steps from the action palette, set waits/loop count, choose targets from the running-apps list via M6); the permission onboarding flow (M7); and a live run-timeline view backed by the M3 recorder. Honest UX copy (what it does, what it will never do).

**Files/modules:** `App/{MenuBar/, Editor/, Onboarding/, Timeline/}`, view models observing engine state.

**Tests:** XCUITest for onboarding + start/stop happy paths; snapshot/logic tests for view models; **manual** full build-and-run of a workflow through the UI on a fresh account.

**Acceptance criteria:** you create, save, and run a workflow entirely via UI, including first-run permission setup; live status and timeline reflect reality.

**Failure modes:** UI blocking on the running engine — engine off-main, UI updates on main. Editor letting users compose illegal steps — validate in the editor using M2/M4.

**Depends on:** M6, M7, M13.

---

## M15 — Error recovery hardening

**Objective:** every failure degrades safely, restores focus, and logs the truth.

**Cursor implements:** the typed error taxonomy end-to-end (`PermissionError`, `PreconditionError`, `ActionError`, `ForbiddenActionError`, `TimeoutError`); TOCTOU handling (re-assert focus guard immediately before each event; treat unexpected front-app change as user intervention → stop); mid-run permission loss detection (AX calls failing → stop with clear message); Secure Input detection → `PreconditionFailed`; verified focus restoration at stop with an honest "couldn't restore" log path.

**Files/modules:** `Sources/CoreEngine/Recovery.swift`, error handling threaded through engine/executor/adapters, `Tests/EngineTests/`.

**Tests:** inject each failure into the engine (simulated) and assert the correct transition, message, and safe stop; **manual**: quit the target app mid-run and revoke Accessibility mid-run — both produce clean stops, clear messages, accurate logs, no crash.

**Acceptance criteria:** all failure injections yield safe stops and truthful logs; focus restoration is verified or honestly reported; no failure leaves the engine stuck or crashes the app.

**Failure modes:** swallowing errors to "keep going" — never for `ForbiddenActionError` or permission loss. Retry loops overshooting — cap retries per step.

**Depends on:** M5, M10, M13.

---

## M16 — Testing pass

**Objective:** lock in confidence and set realistic automation boundaries.

**Cursor implements:** consolidate the test pyramid — pure-logic unit tests (state machine, safety suite, config, redaction) in CI; component tests driving whole workflows via SimulationExecutor; the mutation-guard integration test (M12); a documented **manual matrix** (Chrome/VS Code/Finder × supported macOS versions); and a documented path for **provisioned integration** (self-hosted GUI runner with a PPPC/MDM profile pre-granting Accessibility) — because TCC can't be granted in ordinary CI.

**Files/modules:** `Tests/` consolidation, `docs/testing.md`, CI config wiring the safety suite as a **merge gate**.

**Tests:** the suite runs green in CI; the safety suite blocks merge when red; manual matrix documented and executed once.

**Acceptance criteria:** CI green; safety-suite gate enforced; testing boundaries (what can/can't be automated) written down; manual matrix passes on your macOS versions.

**Failure modes:** pretending generic CI can do end-to-end (it can't) — document the provisioned-runner reality instead. Flaky live tests — keep them out of the merge gate; gate on pure logic.

**Depends on:** everything through M15.

---

## M17 — Packaging & distribution

**Objective:** a Developer-ID-signed, notarized DMG a stranger can install and trust.

**Cursor implements:** enable **hardened runtime**; set **minimal entitlements** (**no App Sandbox** — required, since AX control of other apps is sandbox-incompatible and this rules out the Mac App Store); required `Info.plist` usage strings; sign with **Developer ID Application**; **notarize** via `notarytool`; **staple**; package with `create-dmg`. Optional: **Sparkle** signed auto-updates. Ship short user docs (what it does / never does / how to grant permission / how to read logs).

**Files/modules:** `scripts/{sign.sh, notarize.sh, staple.sh, make-dmg.sh}`, entitlements + Info.plist, `docs/`.

**Tests:** **manual** — on a *second* Mac / fresh user account, the downloaded DMG opens without Gatekeeper blocking, the app requests Accessibility correctly, and a workflow runs.

**Acceptance criteria:** notarization succeeds and is stapled; clean-machine install works; permission flow works post-install; versioned release artifact produced.

**Failure modes:** accidentally enabling App Sandbox (breaks AX entirely). Notarization rejects due to hardened-runtime/entitlement mismatch. Grant lost across updates if signing identity changes — keep a stable Developer ID.

**Depends on:** M14, M16.

---

## Dependency shape at a glance

```
M0 ─ M1 ─ M2 ─┐
         ├ M3 ─┤
         └ M4 ─ M5 ───────────────┐
M6 ──────────────────────────────┤
M7 ─ M8 ──────────────────────────┤
              M9 ──────────────────┤
                         M10 (MVP gate) ─ M11 ─┐
                                          M12 ─┤
                                   M13 ─────────┤
                              M14 ─ M15 ─ M16 ─ M17
```

**The critical line to protect:** M4 (safety) and M10 (walking skeleton). Nothing that emits real input should exist before M4 is green, and no adapter (M11+) should start before M10 proves the spine.

---

## What's next (not in this document)

Once you approve the milestone breakdown, the next step is to expand each milestone into its own **tight, self-contained Cursor prompt** — objective, the exact files to create/modify, the tests to write, the acceptance checklist, and the guardrails to respect — one per session so Cursor stays focused. We deliberately did **not** collapse this into one giant prompt.
