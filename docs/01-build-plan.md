# Waypoint — Engineering Build Plan

**A step-by-step plan to design and ship a production-quality, read-only macOS navigation-automation app.**

Audience: you (new to Swift/macOS) building toward a real, distributable product, plus any engineer you hand this to later.

---

## 0. How to read this document

This is deliberately different from a flat "here is the architecture" dump. It is a **sequenced roadmap**: ten phases, each one building on the last. Every phase has the same four parts:

- **Goal** — what "done" means for the phase.
- **Build** — the concrete things you construct.
- **Learn** — the macOS/Swift concepts you must understand to do it (you're new to this, so these matter).
- **Exit criteria** — the check that proves the phase is really finished before you move on.

The full reference material the original prompt asked for (requirements, non-functional requirements, security, repo layout, etc.) is embedded where it first becomes relevant, and also collected in the reference appendices at the end so you can hand a single document to another engineer.

**One principle drives every decision below:** the app performs *real* navigation that the user explicitly configured, and it tells the truth about what it did. It is not built to fabricate activity, spoof time trackers, or manipulate screenshots. That is not just an ethics note — it's an architectural constraint that keeps the design simple (no fake-input paths, no screenshot pipeline, truthful logs).

---

## 1. What you are actually building (the product in one paragraph)

A macOS menu-bar utility that runs **user-defined navigation workflows** across already-open apps (Chrome, VS Code / editors, Finder, and other user-picked apps). A workflow is an ordered list of small, safe steps — *switch to app*, *next window/tab*, *scroll*, *open an existing file*, *page through a document*, *press a navigation shortcut*, *wait N seconds*, *return to the previous app*. For code editors the app is **strictly read-only**: it can move around and scroll, but it structurally cannot type, paste, delete, save, or run editor commands. The user is always in control — any real keypress or mouse move, or a global hot-key, instantly stops the run.

**Legitimate use cases** that justify this (worth writing into your project report): a hands-free document/code *reading* review that pages through files on a timer; a kiosk/presentation walkthrough that cycles through open windows; an accessibility aid for users who find repetitive navigation painful; a QA aid that drives an app through a fixed navigation path.

---

## 2. Product requirements (the "why" and "what")

**Primary goals**

- Let a non-technical user assemble a navigation workflow from a small palette of safe steps, and run it against apps that are already open.
- Guarantee, by design, that code editors and similar text surfaces are never modified.
- Keep the user in control at all times, with an instant, obvious stop.
- Be honest and transparent: what the app does is exactly what its logs and UI say it does.

**Target users:** individual macOS users who want hands-free navigation/reading assistance; not IT-managed fleets (v1).

**Explicit non-goals (write these down — they protect the design):**

- No fabrication of activity, no simulated "presence," no defeating idle detection, no time-tracker spoofing.
- No screenshot capture or manipulation.
- No text entry, editing, or command execution in code editors.
- No arbitrary-shell or arbitrary-AppleScript execution engine.
- No headless/background operation the user can't see and stop.

---

## 3. Functional requirements (what it must do)

1. Detect and list currently running, user-facing applications.
2. Let the user define a **workflow**: an ordered list of steps, optional looping, and per-workflow guardrails.
3. Support this fixed, closed **action palette** for v1:
   - `activateApp(bundleID)` — bring an already-running app to the front.
   - `switchWindow(direction)` — cycle windows of the front app.
   - `switchTab(direction)` — next/previous tab (browser/editor tab-nav shortcut).
   - `scroll(direction, amount)` — scroll the focused view.
   - `pageNavigate(pageUp/pageDown/home/end)` — document paging via navigation keys.
   - `openExistingFile(path)` — open a file that already exists (via Finder/`NSWorkspace`), never create or modify.
   - `pressNavigationShortcut(named)` — from an allowlisted set of *navigation-only* shortcuts.
   - `wait(seconds)` — configurable delay.
   - `returnToPrevious()` — go back to the app/window that was frontmost before the workflow started.
4. Start/stop a workflow from the menu bar and from a global hot-key.
5. Show live run status (current step, elapsed time, next step).
6. Persist workflows to disk and reload them.
7. Onboard the user through the required macOS permissions.
8. Record a truthful run log the user can view and export.

**Explicitly excluded actions (must not exist as capabilities):** typing characters, paste, cut, delete/backspace, save, "run"/"build"/command-palette execution, find-and-replace, any file write/rename/delete, any network posting of activity.

---

## 4. Non-functional requirements (how well it must behave)

- **Safety-first:** the read-only guarantee for editors must be enforced in code at a single choke point, not by convention.
- **Responsiveness:** stop/kill must take effect within ~100 ms; UI never blocks on a running workflow (engine runs off the main thread; UI updates on main).
- **Reliability:** a failed step degrades gracefully (retry/skip/abort per policy) and always leaves the user's focus in a sane state.
- **Transparency:** every executed action is logged with a timestamp; logs match reality.
- **Least privilege:** request only the permissions actually needed (Accessibility; *not* Screen Recording, because v1 reads the accessibility tree, not pixels).
- **No network by default:** v1 makes no outbound connections — this eliminates a whole class of security and privacy concerns and is a strong point for your report.
- **Portability of config:** workflows are plain, versioned JSON.
- **Performance:** idle CPU ~0%; a running workflow should be light (event posting + short polls), not a busy loop.

---

## 5. Technology choices (and why — matters because you're new to this)

| Concern | Choice | Why |
|---|---|---|
| Language | **Swift** | First-class access to macOS frameworks; what the platform is built for. |
| UI | **SwiftUI** with `MenuBarExtra` for the menu-bar app, plus a settings/editor window; drop to **AppKit** (`NSWorkspace`, `NSRunningApplication`) where SwiftUI lacks coverage | Menu-bar-first fits the product; SwiftUI is the modern, beginner-friendlier path. |
| Enumerate & switch apps | **`NSWorkspace` / `NSRunningApplication`** | Official API to list running apps and activate one. |
| Inspect windows/UI & navigate | **Accessibility API (`AXUIElement`)** | The supported way to read another app's window/element tree and perform safe UI actions **without** modifying content. This is the heart of the app. |
| Synthesize navigation keys / scroll | **Quartz Event Services (`CGEvent`)** | Post specific key events (arrows, Page Up/Down, Cmd+`) and scroll-wheel events. You restrict this to an allowlist of navigation key codes. |
| Global hot-key (stop/start) | Carbon `RegisterEventHotKey` or a small hot-key library | Reliable system-wide stop control. |
| Config storage | **`Codable` → JSON** in `~/Library/Application Support/Waypoint/` | Simple, versioned, human-inspectable. |
| Logging | **`os.Logger` / OSLog** + a structured run recorder (JSONL) | Native unified logging + an exportable truthful run log. |
| Packaging | **Xcode app**, **Developer ID** signing, **hardened runtime**, **notarization** via `notarytool`, shipped as a **DMG** | The only viable path for this app class (see the trap below). |
| Auto-update (optional) | **Sparkle** | Standard for Developer-ID-distributed Mac apps. |

**The single most important platform trap — learn this now, not in month three:**
Controlling *other* applications via the Accessibility API is **incompatible with the App Sandbox**. The Mac App Store requires the App Sandbox. Therefore **this app cannot ship on the Mac App Store.** You distribute it yourself as a **Developer ID–signed, notarized DMG**. Design for that from day one (it affects entitlements, update mechanism, and your project's distribution story).

**Why AX-first instead of AppleScript/Apple Events:** using Apple Events to script each target app would pull you into per-app "Automation" (`NSAppleEventsUsageDescription`) permissions and app-specific scripting dictionaries. Reading the accessibility tree plus posting navigation-only `CGEvent`s keeps the model uniform across apps and needs essentially one permission (Accessibility). Simpler and safer.

---

## 6. The core mental model (read before coding anything)

Three ideas hold the whole design together:

1. **Closed action set.** There is a Swift `enum ActionKind` listing *every* action the app can ever perform. There is no "run arbitrary command" case, and there is no "type text" case for editor targets. If a capability isn't in the enum, the app literally cannot do it.

2. **Policy choke point.** Every action, without exception, is executed through one `ActionExecutor`, and every execution first passes a `SafetyPolicy.validate(action, target)` gate. Read-only-ness is enforced *there*, once, not sprinkled across the code.

3. **User sovereignty.** The engine watches for real user input (via an event tap that *observes*, never blocks) and a global hot-key. Either one halts the run and restores focus. The human always wins.

Everything in the phases below is in service of these three.

---

## 7. The phased roadmap (your steps, one by one)

### Phase 0 — Environment & Swift foundations
**Goal:** a signed, running (empty) menu-bar app on your machine, in version control.
**Build:**
- Install Xcode; create a new macOS App (SwiftUI lifecycle).
- Get an Apple Developer account (needed later for Developer ID + notarization; free tier lets you build/run locally).
- Create the git repo with the structure from §16.
- Ship a `MenuBarExtra` that just shows a menu with "Quit."
**Learn:** Swift basics (optionals, structs vs classes, enums with associated values, `async/await`), the Xcode project/target/scheme model, code signing at the "run on my Mac" level, `Codable`.
**Exit criteria:** the empty menu-bar app launches, appears in the menu bar, quits cleanly; repo is initialized with a README and license.

### Phase 1 — Feasibility spike: permissions + app control
**Goal:** prove the risky part works before investing in architecture.
**Build (throwaway spike, kept in a branch):**
- Request and detect **Accessibility** permission (`AXIsProcessTrustedWithOptions`), and deep-link the user to System Settings → Privacy & Security → Accessibility.
- List running apps with `NSWorkspace.shared.runningApplications`.
- Activate a chosen app (`NSRunningApplication.activate`).
- Read the front app's window list via `AXUIElement` (window titles).
- Post one scroll event and one Page-Down key event with `CGEvent`, into a scratch document.
**Learn:** the macOS **TCC** permission model (why the app must be *added* to the Accessibility list, and why toggling it kills/relaunches the process during development), `AXUIElement` basics, `CGEvent` key codes.
**Exit criteria:** you can, from your app, bring Chrome/VS Code/Finder to the front, read their window titles, scroll them, and page through a document — with the Accessibility toggle on.

> This phase de-risks the entire project. If something here is impossible on your macOS version, you learn it in week one, not month two.

### Phase 2 — Domain model & configuration
**Goal:** the data structures that describe workflows, with save/load.
**Build:**
- `ActionKind` enum (the closed set from §3) with associated parameters.
- `Step` (action + timeout + retry policy + on-error behavior), `Workflow` (name, targets, ordered steps, loop settings, guardrails), and a `TargetApp` (bundle ID + classification: `browser`, `editor`, `finder`, `other`).
- `Codable` JSON persistence in Application Support, with a top-level `schemaVersion` and a migration hook.
- A config **validator** that rejects any workflow referencing an action not allowed for its target class.
**Learn:** `Codable` custom coding, enum-with-associated-values encoding, schema versioning/migration patterns, where app data belongs on macOS (`FileManager` + Application Support).
**Exit criteria:** you can hand-write a workflow JSON, load it, validate it, round-trip it back to disk unchanged, and the validator rejects a deliberately illegal step.

### Phase 3 — Safety & policy layer (build this *before* the executors)
**Goal:** the read-only guarantee, as code, tested in isolation.
**Build:**
- `SafetyPolicy` with `validate(action:, target:) -> Decision` (`allow` / `deny(reason)`).
- Per-target policies: `EditorReadOnlyPolicy` denies anything outside the read-only navigation set; `BrowserPolicy`, `FinderPolicy`, `GenericPolicy` similarly scoped.
- A **navigation-key allowlist**: an explicit set of key codes/chords the app may synthesize (arrows, Page Up/Down, Home/End, Cmd+arrow, Ctrl+Tab, Cmd+`, Cmd+Shift+`). Character keys, Return, Delete/Backspace, Cmd+V/C/X, Cmd+S are **not in the set and have no code path**.
- A `ForbiddenActionError` that is impossible to swallow silently (always logged).
**Learn:** defense-in-depth thinking, how to make an invariant structural rather than advisory, unit-testing pure logic.
**Exit criteria:** a **safety test suite** proves that for an `editor` target, every mutating/text action is denied at the policy layer, and only navigation actions pass. This suite must stay green forever.

### Phase 4 — Action executors
**Goal:** each allowed action actually works, routed through the policy gate.
**Build:**
- `ActionExecutor` protocol; one executor per `ActionKind`.
- Implement them against `NSWorkspace` (activate/openFile), `AXUIElement` (window/tab focus, scroll actions), and the navigation-key `CGEvent` sender.
- **Every** executor call goes: `policy.validate` → (allow) execute → record. No executor is reachable except through this path.
- A `SimulationExecutor` (a.k.a. dry-run) that performs no real events, only records "would do X." This is your testing and demo backbone.
**Learn:** `AXUIElement` actions vs. `CGEvent` posting and when to use each; focus/target resolution; `async/await` for the wait/settle timing.
**Exit criteria:** each action runs correctly against a real app in live mode and produces a truthful record in simulation mode; the policy gate is provably on the only path.

### Phase 5 — Workflow engine & state machine
**Goal:** run a whole workflow reliably, pausably, stoppably.
**Build:**
- **Engine states:** `Idle → Arming (check permissions/preconditions) → Running → Paused → Stopping → Idle`, plus an `Error` path.
- **Per-step lifecycle:** `Pending → Validating → Executing → Settling → Completed | Failed`, and on `Failed`: `Retry | Skip | Abort` per the step's policy.
- Loop support with a max-iteration cap and a per-run wall-clock cap (never-run-forever guardrails).
- **Kill switch:** a global hot-key *and* an observing event tap — any real user keypress/mouse move transitions to `Stopping`. On stop, `returnToPrevious()` restores focus.
- Engine runs off the main actor; publishes state to the UI on the main actor.
**Learn:** modeling a finite state machine in Swift, Swift concurrency (actors, tasks, cancellation), event taps in *listen-only* mode.
**Exit criteria:** a multi-step looping workflow runs end to end; pause/resume works; hot-key and a real keypress each stop it within ~100 ms and restore the original front app.

### Phase 6 — User interface
**Goal:** a real person can build and run a workflow without touching JSON.
**Build:**
- Menu-bar controls: start/stop, pick workflow, live status (current step, elapsed, next).
- A workflow editor window: add/reorder/remove steps from the action palette, set waits and loop count, choose target apps from the running-apps list.
- A **permission onboarding flow**: detect missing Accessibility permission, explain why it's needed in plain language, deep-link to the exact Settings pane, re-check on return.
- A run timeline view (the truthful log, live).
**Learn:** `MenuBarExtra`, SwiftUI windows/scenes, list editing/reordering, observing engine state (`@Observable`/Combine), writing honest permission-rationale copy.
**Exit criteria:** you build, save, and run a workflow entirely through the UI, including first-run permission setup on a fresh account.

### Phase 7 — Observability, error handling & recovery hardening
**Goal:** when something goes wrong, the app degrades safely and tells the truth.
**Build:**
- `os.Logger` categories (engine, executor, policy, permissions) + a structured **run recorder** writing JSONL, exportable from the UI.
- Typed error taxonomy: `PermissionError`, `PreconditionError` (target app not running / window missing), `ActionError`, `ForbiddenActionError`, `TimeoutError`.
- Precondition checks before each step (is the target still running? is a window present?); mid-run permission-loss detection → safe stop with a clear message.
- Instruments **signposts** around step execution for profiling.
**Learn:** OSLog/unified logging, structured logging design, Instruments, defensive precondition patterns.
**Exit criteria:** killing the target app mid-run, or revoking Accessibility mid-run, produces a clean stop, a clear user message, and an accurate log — never a crash or a stuck state.

### Phase 8 — Testing pass
**Goal:** confidence that safety and behavior hold.
**Build/confirm the test pyramid:**
- **Unit (most):** policy/safety suite (§3), state-machine transitions, config validation/migration, key-allowlist.
- **Component:** engine driving the `SimulationExecutor` through whole workflows (no real events).
- **Integration (few):** a dedicated **sandbox test app** you own, driven live, asserting real navigation happened and nothing was mutated.
- **UI:** XCUITest for the critical onboarding + start/stop paths.
- **Manual matrix:** Chrome, VS Code, Finder across your supported macOS versions.
**Learn:** XCTest, XCUITest, test doubles, building a controllable test target.
**Exit criteria:** CI (even a local script to start) runs unit + component tests green; the safety suite is wired to block a release if red.

### Phase 9 — Packaging, signing, notarization & distribution
**Goal:** a DMG a stranger can download, open, and trust.
**Build:**
- Enable **hardened runtime**; set the minimal entitlements (no App Sandbox — see §5 trap; add only what AX/CGEvent need).
- Sign with **Developer ID Application**; **notarize** with `notarytool`; **staple** the ticket; package with `create-dmg`.
- Write the required `Info.plist` usage strings and a clear first-run explanation.
- (Optional) integrate **Sparkle** for signed auto-updates.
- Ship a short docs set: what it does, what it will never do, how to grant permission, how to read logs.
**Learn:** code signing identities, hardened runtime, the notarization pipeline, DMG creation, release versioning.
**Exit criteria:** on a *second* Mac / fresh user account, the downloaded DMG opens without Gatekeeper blocking it, the app requests Accessibility correctly, and a workflow runs.

### Phase 10 — Future expansion (after v1 ships)
- Workflow **scheduling** (run at a time / on trigger) — with the same visible, stoppable, truthful constraints.
- Richer **conditionals** (e.g., "if window titled X exists, then…") driven by read-only AX queries.
- Import/export and sharing of workflow files.
- Per-app **plugin policies** so new target apps get well-scoped read-only rules.
- Accessibility-focused presets (reading-pace paging, etc.).
- Localization; light/dark polish; optional signed telemetry that is opt-in and truthful.
- Team/managed configuration (MDM-deployable workflow files) — only with strong transparency guarantees.

---

## 8. State-machine design (reference)

**Engine (global):**
`Idle → Arming → Running ⇄ Paused → Stopping → Idle`, with any state able to jump to `Stopping` on kill-switch, and `Arming`/`Running` able to enter `Error → Stopping` on failure.

- `Arming`: verify Accessibility permission, verify target apps are running, snapshot the current frontmost app for `returnToPrevious()`.
- `Running`: execute steps in order; honor loop/iteration/wall-clock caps.
- `Paused`: timers suspended; no events posted.
- `Stopping`: cancel outstanding tasks, restore original focus, flush logs.

**Step (local):**
`Pending → Validating → Executing → Settling → Completed`, or `→ Failed → {Retry | Skip | Abort}`.

- `Validating`: policy gate + preconditions.
- `Settling`: post-action wait so the UI catches up before the next step reads state.

Invariant: the machine can only *leave* the app in `Idle`, and `Stopping` always runs `returnToPrevious()` and focus restoration.

---

## 9. Read-only safety architecture (reference — the crux)

Four layers of defense so the editor guarantee can't be violated by a bug:

1. **Capability closure:** no "type/paste/delete/save/run" action exists in `ActionKind`. You can't call what isn't there.
2. **Load-time validation:** the config validator rejects any workflow whose steps aren't allowed for their target class, before a run can start.
3. **Runtime policy gate:** `SafetyPolicy.validate` runs on the single execution path for *every* action; editors get `EditorReadOnlyPolicy`.
4. **Key allowlist:** the `CGEvent` sender can only emit codes from the navigation allowlist; character/Return/Delete/save/paste chords have no code path.

Plus the **anti-deception constraint**: no screenshot capture/edit pipeline exists, no synthetic input aimed at idle-detection or time trackers, and the run log records exactly what happened. These are design invariants, backed by the Phase 3 safety test suite that must stay green to release.

---

## 10. Security & privacy (reference)

- **Least privilege:** Accessibility only; explicitly *not* Screen Recording (v1 reads the AX tree, not pixels) and *not* per-app Automation.
- **No network in v1:** nothing to exfiltrate; a strong, simple security story.
- **Local, inspectable data:** workflows are plain JSON in Application Support; no secrets stored.
- **Signed & notarized:** hardened runtime, Developer ID, notarization — users get a trusted, tamper-evident binary.
- **Transparency:** the app's behavior, logs, and docs match; no hidden actions; the user can always see and stop what's running.
- **Consent:** each workflow is user-authored and user-launched; nothing runs unattended in v1.

---

## 11. MVP scope (what ships first — cut everything else)

**In:** single active workflow; the nine v1 actions from §3; menu-bar start/stop + global stop hot-key; running-apps picker; JSON persistence; permission onboarding; live status + exportable run log; the four-layer safety architecture; Developer-ID-signed, notarized DMG.

**Out (v2+):** scheduling, conditionals/branching, multi-workflow orchestration, Sparkle auto-update, import/export UI, per-app plugin policies, localization, telemetry.

**MVP definition of done:** on a clean Mac, a user downloads the DMG, grants Accessibility, builds a workflow in the UI that switches between Chrome/VS Code/Finder, scrolls and pages through a document read-only, waits, loops a few times, and returns to where they started — and can stop it instantly at any moment, with a truthful log to show for it.

---

## 12. Repository structure & module responsibilities (reference)

```
NavigatorApp/
├─ README.md                     ← what it does + what it will never do
├─ LICENSE
├─ Package.swift / .xcodeproj     ← app target + local Swift packages
├─ App/                           ← SwiftUI entry point, MenuBarExtra, windows, onboarding UI
│  ├─ NavigatorApp.swift
│  ├─ MenuBar/
│  ├─ Editor/                     ← workflow editor UI
│  └─ Onboarding/                 ← permission flow
├─ Sources/
│  ├─ CoreEngine/                 ← WorkflowEngine + finite state machine, task/loop control, kill switch
│  ├─ Actions/                    ← ActionKind enum + one executor per action; SimulationExecutor
│  ├─ Safety/                     ← SafetyPolicy, per-target policies, navigation-key allowlist
│  ├─ Accessibility/              ← AXUIElement wrappers (read + safe navigation only)
│  ├─ InputSynthesis/             ← CGEvent scroll/key sender, gated by the allowlist
│  ├─ AppControl/                 ← NSWorkspace/NSRunningApplication (list, activate, openFile)
│  ├─ Config/                     ← Codable models, load/save, schemaVersion + migrations, validator
│  ├─ Permissions/                ← TCC checks, deep-links, re-check logic
│  ├─ Observability/              ← os.Logger categories, JSONL run recorder, signposts
│  └─ Domain/                     ← Workflow, Step, TargetApp, error taxonomy
├─ Tests/
│  ├─ SafetyTests/                ← MUST prove editors reject all mutating actions
│  ├─ EngineTests/                ← state-machine transitions
│  ├─ ConfigTests/                ← validation + migration round-trips
│  └─ UITests/                    ← XCUITest onboarding + start/stop
├─ TestSupport/                   ← fixtures, the sandbox test app, fakes
└─ scripts/                       ← sign / notarize / staple / make-dmg
```

**Module responsibilities in one line each:**

- **App** — all SwiftUI/AppKit UI; owns no business rules, only presents engine state and captures user intent.
- **CoreEngine** — the sequencer and state machine; the only thing that decides *when* an action runs; owns the kill switch and focus restoration.
- **Actions** — defines the closed action set and how each one is performed; every executor calls Safety first; includes the simulation executor.
- **Safety** — the read-only guarantee: policies + key allowlist; the single validation gate.
- **Accessibility** — thin, read-and-navigate-only wrappers over `AXUIElement`.
- **InputSynthesis** — the *only* place that posts `CGEvent`s, and it can only post allowlisted navigation codes.
- **AppControl** — list/activate apps, open existing files; never creates/modifies files.
- **Config** — typed models, persistence, versioning/migration, and load-time validation.
- **Permissions** — detect/guide/re-check TCC Accessibility permission.
- **Observability** — truthful logging and the exportable run record.
- **Domain** — shared value types and the error taxonomy.

---

## 13. Why this plan is better than a flat architecture spec

- It is **sequenced for a beginner shipping a real product**: risky platform work (permissions, `AXUIElement`, `CGEvent`) is de-risked in Phase 1 before you commit to architecture.
- **Safety is built before behavior** (Phase 3 before Phase 4), so the read-only guarantee is foundational, tested, and enforced at one choke point — not retrofitted.
- It calls out the **App Sandbox / Mac App Store trap** up front, which silently derails people who assume they'll ship on the store.
- It bakes in the **anti-deception constraint as architecture** (no fake-input or screenshot paths exist), which is both the right thing and a simpler design.
- Every phase has an **exit/verification criterion**, so you always know whether you're actually done.

---

## Appendix A — First things to do this week

1. Install Xcode, create the SwiftUI menu-bar app, get it running (Phase 0).
2. Do the Phase 1 spike: grant Accessibility, activate Chrome/VS Code/Finder, scroll and page a document. This tells you the project is viable.
3. Write the `ActionKind` enum and one workflow JSON by hand (start of Phase 2).
4. Only then start building outward.

## Appendix B — Concepts to study, in order

TCC / Accessibility permission model → `AXUIElement` (read + actions) → `CGEvent` key/scroll posting → Swift concurrency (actors, task cancellation) → finite state machines in Swift → `Codable` with enums → hardened runtime + notarization pipeline.
