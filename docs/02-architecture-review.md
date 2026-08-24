# Waypoint — Architecture Review

**Reviewer stance:** second senior engineer, adversarial. My job is to break the v1 design before macOS does. I'm reviewing the plan I was handed (the phased build plan) and being deliberately hard on it. Below: problems by category, each with a concrete fix; then a revised architecture; then the smallest slice that actually proves the risky parts.

Severity key: 🔴 will bite hard / 🟠 will bite / 🟡 annoyance or future debt.

---

## 1. The one that matters most: synthetic input doesn't go "into an app"

🔴 **Problem.** The plan talks about "post a navigation key *into VS Code*." macOS doesn't work that way. `CGEvent.post(tap:)` injects into the **system event stream**, which is delivered to whatever app+view currently owns keyboard focus. There is no reliable "send this key to that PID." (`CGEvent.postToPid` exists but is inconsistent across apps and frameworks, especially Electron/web content.) So every keystroke action is implicitly "send to the frontmost focused element," and the plan's `activateApp` → `pressKey` sequence is a **race**: activation is asynchronous and best-effort, focus may not have landed, and the key can be delivered to the wrong app or the wrong field.

**Why it's severe:** the two flagship targets (Chrome, VS Code) are the worst cases — see §3.

**Fix (architectural):**
- Make **focus-guarded execution** a first-class rule. Before *any* synthetic event, the executor asserts an invariant: *the intended target is frontmost, and has been stable for a short debounce.* If the invariant fails, the action is refused and the run stops — never "post anyway and hope."
- Reframe the primitive: the app **operates on the app the user already has in front**, and treats cross-app *activation* as a rare, explicitly-confirmed, best-effort step — not as something sprinkled before every keystroke. This removes most of the race by removing most of the forced activation.
- Prefer **scroll-wheel events** and **AX actions** (which can target an element) over posted keystrokes wherever possible (see §2, §9).

---

## 2. The design over-trusts the Accessibility tree of the exact apps it targets

🔴 **Problem.** The plan leans on `AXUIElement` to "navigate through documents," "switch windows/tabs," and read structure. That's reliable for *native Cocoa* apps. It is **not** reliable for:
- **Google Chrome** — web content is not a normal AX tree; Chrome only exposes a rich tree when it believes an assistive client needs it, and even then it's huge, dynamic, and not addressed by "window/tab" the way you'd hope. Browser **tabs are not AX windows.**
- **VS Code / Electron** — the editor surface is web content (Monaco) inside Electron; the AX tree is partial, changes across releases, and often needs accessibility mode toggled on (`AXManualAccessibility`) to be usable at all — which is heavyweight and app-version-fragile.

So the very apps in the requirements are the ones where "navigate via AX" is least dependable, and they change every few weeks.

**Fix (architectural):**
- **Lower AX's job to what it's reliable at:** *coarse, read-only verification* — "which app is frontmost," "does a window exist," "what is the focused app's bundle id/window title." Do **not** depend on AX to traverse internal document structure of Chrome/VS Code.
- Do the *movement* with **app-agnostic primitives**: scroll-wheel events (scrolling), and a tiny set of universally-non-mutating navigation keys (arrows, Page Up/Down, Home/End). These work without a good AX tree.
- Introduce a **per-target Adapter** with **capability probing**: at run start, probe what the target actually supports (does it expose scrollable AX? does the standard tab shortcut apply?) and **degrade gracefully** to the app-agnostic primitive when it doesn't. Adapters isolate the app-specific fragility so the engine stays stable.

---

## 3. "Navigation keys are always safe" is not quite true — and it's the read-only guarantee's blind spot

🔴 **Problem.** The read-only guarantee rests on "we only send navigation keys, which can't mutate text." Two holes:
1. **App-specific keybindings/modes.** In VS Code with the **Vim extension**, or Emacs keybindings, or custom keymaps, keys you consider "navigation" can be bound to editing commands in some modes. Arrow keys are safe almost everywhere, but "navigation shortcut" chords (Cmd/Ctrl combos) are exactly the space apps love to rebind — including to destructive commands.
2. **Misdelivery (from §1).** If focus is wrong, a keystroke lands somewhere unexpected. Arrows/Page are still harmless there, but a rebindable chord may not be.

**Fix (architectural):**
- **Shrink the keystroke allowlist to the provably-inert core:** arrows, Page Up/Down, Home/End — keys that are movement in virtually every app and mode, and are never text mutation. **Drop Cmd/Ctrl navigation chords from v1** (they're the rebindable, risky ones). Tab-switching, if kept, is a single well-known shortcut gated behind the focus guard and the "not an editor content view" check.
- **Make scrolling use scroll-wheel events, not Page-Down keystrokes** — a scroll-wheel event categorically cannot alter text, in any app or mode. This is a strictly safer primitive for the most common action.
- Keep the four-layer safety model, but note the honest bound: the guarantee is now "we only ever emit inert movement primitives," which is *defensible across modes*, rather than "navigation keys are safe" (which isn't universally true).

---

## 4. The engine will trip its own kill switch (self-event feedback loop)

🟠 **Problem.** The plan says an observing event tap watches for "real user input" to stop the run — while the engine is itself posting synthetic input. Your own scroll/key events will be seen by that tap. Naively, the app injects a scroll, sees "user input!", and stops itself on step one.

**Fix:** tag every synthetic event with a **source signature** (`CGEventSource` state id / a `CGEventField` user-data marker) and have the input monitor **ignore events carrying that marker**. Only untagged input counts as "the human intervened." This must be designed in, not patched later.

---

## 5. Cross-app activation is best-effort and has gotten *stricter*, not looser

🟠 **Problem.** The plan uses `NSRunningApplication.activate` and a `returnToPrevious()` that both assume you can reliably bring an arbitrary app forward. Modern macOS has tightened app-activation: an app can't freely yank focus; cooperative activation APIs exist but the target app has a say, activation can silently no-op, and it can drag you across Spaces or fail if the window is on another Space/display. So both "switch to app X" and "restore focus at the end" are unreliable.

**Fix:**
- Treat activation as **best-effort with verification**: request activation, then **poll (with timeout) until AX confirms the expected app is actually frontmost**; if it doesn't become frontmost, abort that step per policy rather than proceeding blind.
- For `returnToPrevious()`, snapshot the prior frontmost app at `Arming`, attempt restore at `Stopping`, **verify**, and if restore fails, **log honestly** ("could not restore focus") rather than pretending it worked.
- Minimize forced activation in v1 by centering the product on the already-frontmost app.

---

## 6. Fixed `wait(seconds)` and a "Settling" sleep are brittle

🟠 **Problem.** Timing via fixed sleeps is a classic UI-automation smell: too short → race; too long → sluggish; and it never adapts to machine load. The plan's `Settling` state is a guessed sleep.

**Fix:** replace blind sleeps between steps with **condition-based waiting**: "wait until *predicate* is true, or timeout." Predicates use the *coarse, reliable* AX reads from §2 (front app is X, a window exists). Keep the user-facing `wait(seconds)` action (it's a legitimate, intended feature), but internal step sequencing should be predicate-driven with a hard timeout and a defined fallback (abort/skip), centralized in one **timing policy** rather than scattered constants.

---

## 7. TOCTOU: the target can vanish between "validate" and "execute"

🟠 **Problem.** The state machine validates preconditions (target running, window present) then executes. Between those, the user can quit the app, close the window, or switch Spaces. The plan's per-step `Validating → Executing` has a gap.

**Fix:** collapse the check-and-act window. Re-assert the focus-guard invariant (§1) **immediately before** the synthetic event, not in an earlier state, and make the executor itself return a typed `PreconditionFailed` if the target changed. Treat "front app changed unexpectedly mid-run" as an implicit user-intervention signal → stop.

---

## 8. App/window/tab "detection" promises more than macOS gives you

🟠 **Problem.** The action palette implies real detection of windows and tabs. Reality:
- `runningApplications` is noisy (helper/agent processes, multiple instances, Chrome's many helper PIDs). Bundle id ≠ a single targetable thing.
- **Browser tabs and editor tabs are not enumerable as AX windows.** `switchTab` is really "send the app's next-tab shortcut and hope," with no verification of what tab you're on.
- Full-screen apps, menu-bar-only apps, and multi-display/Spaces layouts break naive window enumeration.

**Fix:**
- Be honest in the model: distinguish **verifiable** operations (front app, window existence — via coarse AX) from **fire-and-hope** operations (tab switching). Mark the latter explicitly as *unverified* in both the type system and the UI/logs, so nobody assumes guarantees that don't exist.
- Filter `runningApplications` to `.regular` activation-policy apps with a UI; ignore helpers.
- **Cut `switchTab` from v1** (it's unverifiable and app-specific). Reintroduce later per-adapter if a target has a reliable mechanism.

---

## 9. Security/privacy: AX read access is a firehose, and logs can leak

🟠 **Problem.** Accessibility permission lets the app **read on-screen content of other apps** — email bodies, chat messages, form fields, window titles containing sensitive data. The plan's "truthful run log" could inadvertently record that content (e.g., logging a window title that contains a customer name or a document path). Also: an app holding Accessibility is a high-value target; the *future* "plugin policies" idea risks introducing a code-execution path into a highly-privileged process.

**Fix:**
- **Log identity and outcome, never content.** Record `{action kind, target bundle id, result, timestamp}` — never window text, never document content, never keystrokes. Add a redaction rule and a test that asserts no free-form app content reaches the log.
- Read the **minimum** AX attributes needed for the coarse guard; don't walk the tree for its own sake.
- Put a hard architectural line under "no dynamically-loaded third-party code in this process, ever." Future "plugins" must be **declarative config**, not executable code — otherwise you've built a privileged RCE surface.
- Keep the **no-network** stance as a stated invariant; it's the single biggest thing shrinking the app's risk.

---

## 10. Accidental source-code modification — where it can still sneak in

🟡→🟠 **Problem.** The closed action set removes the obvious paths, but two residual risks remain:
- **Rebindable chords** landing on a destructive editor command (§3).
- **`openExistingFile` via `NSWorkspace`** opens in the *default* app for that type, which may not be the target editor, can spawn a new window, steal focus, and — combined with a following keystroke and wrong focus — puts input somewhere unintended. It also can't *modify* a file, but it changes the world in ways the plan under-specifies.

**Fix:**
- Resolve §3 (inert primitives only; drop rebindable chords; scroll-wheel for scrolling).
- Scope `openExistingFile` tightly: it may only *reveal/open* an existing file, must never create/rename, and after opening, the focus guard (§1) re-establishes the known target before any further step. Consider deferring `openExistingFile` out of the walking-skeleton MVP since it complicates the focus model.

---

## 11. Testing: the plan implies more automated coverage than macOS permits

🟠 **Problem.** You cannot grant TCC **Accessibility** programmatically, and you can't post real events meaningfully in a headless CI box. So "integration tests driving a real app" won't run on ordinary CI. The plan's testing pyramid is right in spirit but glosses over this wall.

**Fix (set expectations correctly):**
- **Automated, in CI:** pure logic only — the state machine, the safety policy/allowlist (the suite that must never go red), config validation/migration, the redaction rule. These need no GUI, no permissions.
- **Automated, but only on a provisioned runner:** end-to-end needs a **logged-in GUI, self-hosted runner with a PPPC/MDM profile** pre-granting Accessibility to the signed test build. Document this as the one way to automate integration; don't pretend generic CI can.
- **Simulation harness** (`SimulationExecutor`) is your real workhorse for behavior tests — drive whole workflows with no real events and assert the *decisions*.
- **Manual matrix** (Chrome/VS Code/Finder × supported macOS versions) is a permanent, documented reality, because those apps' AX behavior drifts.

---

## 12. Unnecessary complexity to cut for v1

🟡 **Problem.** A few things are heavier than the problem needs yet:
- **Per-target policy class hierarchy** (`EditorReadOnlyPolicy`, `BrowserPolicy`, …) before there's any per-app behavioral difference. Premature.
- **A full ceremony state machine** (`Arming/Settling/…`) is more than the walking skeleton needs to prove itself.
- **Two executor paths** (real + simulation) are worth it — keep — but everything else should shrink.

**Fix:** collapse safety to **one policy engine + capability tags on each `ActionKind`** (e.g., `mutatesText:false`, `requiresFocusGuard:true`, `verifiable:false`). Editors simply require `mutatesText == false` — which every v1 action already satisfies — so you get the guarantee without a class per app. Add per-app adapters (§2) only for *capability probing*, not for policy.

---

## 13. Maintainability: you're coupled to apps you don't control

🟡 **Problem.** Reliability depends on Chrome/VS Code/macOS internals that change on their own schedule. Without isolation, every Chrome update is a potential fire.

**Fix:** the **Adapter + capability-probe** layer (§2) is the maintenance firewall — app-specific fragility lives there and falls back to app-agnostic primitives; the engine, safety, and UI never change when an app updates. Centralize timing (§6) so tuning is one file, not fifty constants.

---

## Revised architecture

**Same spine, three deliberate downgrades in ambition and three new invariants.**

**Downgrades (make it reliable):**
1. **AX is for coarse read-only *verification* only** (front app, window exists, focused bundle id) — not for traversing Chrome/VS Code document structure.
2. **Movement uses app-agnostic, inert primitives** — scroll-wheel events for scrolling; arrows/Page/Home/End for paging. No rebindable Cmd/Ctrl chords. `switchTab` deferred.
3. **The product centers on the already-frontmost app.** Cross-app activation is a rare, verified, best-effort step, not a per-keystroke assumption.

**New invariants (make it safe & correct):**
1. **Focus guard:** no synthetic event is emitted unless AX confirms the intended target is frontmost and stable; otherwise refuse + stop. (Kills §1, §7.)
2. **Self-event tagging:** every synthetic event is signed so the user-intervention monitor ignores it; only untagged input stops the run. (Kills §4.)
3. **Content never logged:** logs carry `{action, target bundle id, result, time}` only, with a test enforcing redaction. (Kills §9.)

**Component picture (revised):**

- **UI (SwiftUI/MenuBarExtra)** — present state, capture intent. Unchanged.
- **CoreEngine** — sequencer + minimal state machine; owns the run, the global stop hot-key, the tagged-input monitor (user sovereignty), and verified focus restoration.
- **Actions** — the closed `ActionKind` set, each carrying **capability tags** (`mutatesText`, `verifiable`, `requiresFocusGuard`). One real executor + one `SimulationExecutor`.
- **Safety (single policy engine)** — one gate on the only execution path; validates via capability tags + the inert-primitive allowlist. No per-app policy classes.
- **Adapters (new, thin)** — per target (browser/editor/finder/generic): **probe capabilities** and choose the primitive; degrade to app-agnostic movement when the app's AX/shortcuts aren't dependable. The maintenance firewall.
- **Accessibility (read-only, coarse)** — `frontmostApp()`, `windowExists()`, `focusedBundleID()`. Nothing that traverses foreign document trees.
- **InputSynthesis** — the only place emitting `CGEvent`s: scroll-wheel + the inert key set, every event tagged, every emission preceded by the focus guard.
- **AppControl** — list `.regular` apps, best-effort *verified* activation, open-existing-file (scoped, deferred from MVP).
- **Config** — Codable JSON, versioned, load-time validation against capability tags.
- **Timing policy (new, centralized)** — predicate-based waits with timeouts + fallbacks; the one place sleeps live.
- **Observability** — OSLog + JSONL run recorder with enforced content redaction.
- **Permissions** — TCC Accessibility detect/guide/re-check; handles the dev-signature-reset reality.

**What got deleted vs. the first design:** per-app policy classes, AX document traversal, `switchTab`, Cmd/Ctrl navigation chords, blind settle-sleeps, and the assumption that activation "just works."

---

## The smallest useful MVP — a "walking skeleton"

**Purpose:** prove the *spine and the scary invariants* with the least code, before building any of the product surface. If this slice is solid, the architecture is sound; if it isn't, you've spent days, not months.

**The single vertical slice:** Against **the app the user currently has in front** (chosen by clicking a menu-bar "Start" — no app-switching, no editor, no JSON), run one hardcoded loop:

`verify frontmost app via coarse AX` → `focus-guard check` → `scroll down (tagged scroll-wheel event)` → `predicate-wait` → `scroll up (tagged)` → repeat N times → stop → `verify + log`.

**It must include (these are the risky hypotheses being tested):**
- TCC **Accessibility** permission onboarding, including the dev-signature-reset pain (Phase-1 reality).
- The **focus guard**: if the front app changes, it refuses/stops — demonstrate by clicking away mid-run.
- **Self-event tagging**: the run does *not* stop itself on its own scroll events, but *does* stop instantly on a real user scroll/keypress and on the **global stop hot-key**.
- The **single safety gate** on the execution path, with the safety unit-test suite green (assert a mutating action would be denied — even though the MVP never issues one).
- **Content-free logging** with the redaction test.
- **Verified focus** at stop (or an honest "couldn't restore" log).

**It deliberately omits:** app switching/activation, tab switching, `openExistingFile`, AX document traversal, the workflow editor UI, JSON config, per-app adapters (stub one generic adapter), multi-workflow, and packaging/notarization.

**Definition of done for the MVP:** on your Mac, you point it at a frontmost Chrome or VS Code window, hit Start, watch it scroll the document up and down on a timer *without ever touching text*, prove it stops the instant you touch the mouse or hit the hot-key, and read a truthful, content-free log afterward — with the safety and state-machine unit tests passing in CI.

**Why this is the right smallest slice:** it exercises every genuinely hard thing at once — permissions, targeting the right app, the inert primitive, the self-event feedback problem, user sovereignty, and honest logging — using the *safest possible* action (scroll-wheel, which can never mutate anything). Everything the full product adds later (more actions, app switching, config, UI, adapters, packaging) is comparatively low-risk once this holds.
