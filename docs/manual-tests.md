# Manual tests — App detection

## App enumeration & frontmost (AppControl)

Prerequisites: build/run Waypoint on a Mac **without** App Sandbox. Have Chrome, VS Code (or another editor), and Finder available.

Checklist:

1. [ ] Call live `AppEnumerator(provider: WorkspaceRunningAppsProvider()).userFacingApps()`.
2. [ ] Confirm the list includes **Google Chrome** (or Chromium), **Visual Studio Code** / Cursor / your editor, and **Finder** when those apps are running.
3. [ ] Confirm Chrome/Electron **helper** processes do **not** appear as separate user-facing apps (`.regular` filter).
4. [ ] Note the current `FrontmostAppResolver().frontmostApp()` bundle id + display name.
5. [ ] Switch focus to another app (e.g. Chrome → Finder → editor) and re-query frontmost; confirm bundle id / display name update to match the app you brought forward.
6. [ ] `isRunning(bundleID:)` returns `true` for a running app’s bundle id and `false` for one that is quit.
7. [ ] `resolve(TargetApp…)` returns a `RunningAppInfo` for a running target and `nil` when that app is not running.

Notes / observed results:

- Live snapshot (2026-08-24, this machine): `.regular` apps included Finder (`com.apple.finder`) and Google Chrome (`com.google.Chrome`). Frontmost was Cursor (`com.todesktop.230313mzl4w4u92`). VS Code was not running at check time — re-run checklist when it is.
- Automated `FilteringTests` cover helper exclusion and resolve/frontmost mapping with injected fakes.

---

## Accessibility permission (Permissions)

Prerequisites: run the **Waypoint.app** target (not sandboxed), signed with a stable local identity when possible.

Checklist:

1. [ ] Fresh run shows Accessibility state (Unknown → Denied/Granted after refresh).
2. [ ] **Request Accessibility…** shows the system prompt **once** (if not already decided).
3. [ ] After denial (or second request), **Open Accessibility Settings** / auto deep-link opens **Privacy & Security → Accessibility**.
4. [ ] Enable Waypoint in that list; return to the app (or click the menu bar icon) — state becomes **Granted** **without relaunch**.
5. [ ] Rebuild with a **changed** ad-hoc signature; observe grant missing/stale — toggle again. Prefer a stable Development identity to avoid this churn.

Notes / observed results:

- _(fill after live Waypoint.app run)_
- Unit `StateTests` cover prompt-once, deep-link on denial, and foreground re-check → granted with an injected probe.

---

## Coarse AX + focus guard (Accessibility)

Prerequisites: Accessibility permission **granted** for Waypoint. Chrome / editor / Finder available.

Checklist:

1. [ ] `CoarseAX().frontmostAppBundleID()` matches the app you have frontmost (Chrome / VS Code / Finder / etc.).
2. [ ] `focusedWindowExists()` is `true` when that app has a focused window.
3. [ ] `focusedElementBundleID()` matches the frontmost/focused app bundle id (identity only — no titles/text).
4. [ ] `FocusGuard.assert(target:)` for the frontmost app returns `.ok` after the debounce.
5. [ ] Switch to another app mid-check (or assert against a non-frontmost target) → `.changed`.
6. [ ] Confirm logs/APIs never capture window titles or document content (only bundle ids / bools).

Notes / observed results:

- Live peek without Waypoint AX grant (`AXIsProcessTrusted() == false`): frontmost bundle id via `NSWorkspace` was `com.apple.systempreferences`; `focusedWindowExists` via AX returned false (untrusted). Re-run checklist after enabling Waypoint in Accessibility Settings.
- Confirmed: APIs only expose bundle ids / bools — **no document content read**.
- `FocusGuardTests` cover stable → ok, other app → changed, missing → lost, mid-debounce change → changed.
- Swift module product is named `WaypointAccessibility` (sources remain under `Sources/Accessibility/`) because a module named `Accessibility` circularly conflicts with Apple’s Accessibility.framework through AppKit.

---

## Input synthesis + sovereignty (InputSynthesis)

Prerequisites: Accessibility granted; frontmost Chrome or editor for live posts (optional for unit tests).

Checklist:

1. [ ] Start a run that emits tagged scrolls — the run does **not** stop on its own scrolls.
2. [ ] Real trackpad/mouse scroll stops the run within ~100 ms.
3. [ ] Global stop hot-key stops the run within ~100 ms.
4. [ ] Focus a Secure Input field (e.g. password) — synthesis surfaces a precondition failure (no retry loop).
5. [ ] Confirm no character/Cmd/Ctrl events can be constructed (`InertKeyPrimitive.make` rejects them).

Notes / observed results:

- Unit tests cover allowlist construction, focus/safety gating, Secure Input probe failure, tagged-ignore / untagged-intervene filter, and self-tag userData.
- Walking skeleton wires `SovereigntyListenTap` + `GlobalStopHotKey` (Ctrl+Opt+.). Re-check items 1–4 under **Walking-skeleton MVP** below.

---

## Walking-skeleton MVP (Actions / RealExecutor)

Prerequisites: Accessibility **Granted** for Waypoint; Chrome or VS Code open with a scrollable document; frontmost that app (not Waypoint).

Checklist:

1. [ ] Menu shows Accessibility state; Start is disabled until **Granted**.
2. [ ] Bring Chrome/VS Code frontmost → **Start Skeleton** → window scrolls **down** then **up** on a timer; no text typed, deleted, or saved.
3. [ ] Run does **not** stop itself on its own tagged scrolls.
4. [ ] Real mouse/trackpad scroll or keypress stops the run promptly; status updates; log summary is content-free (`scroll`/`wait` + result + bundle id only).
5. [ ] **Ctrl+Opt+.** (global stop) stops a running skeleton promptly.
6. [ ] Menu **Stop Skeleton** also stops; after stop, status reports focus ok or honest "couldn't restore focus".

Notes / observed results:

- _(fill after live Waypoint.app run)_
- CI: `SkeletonWiringTests` exercise `RealExecutor` via `RecordingEventPoster` (no live CGEvents) and `SimulationExecutor` seam.

---

## Chrome browser adapter (Adapters / BrowserAdapter)

Prerequisites: Accessibility granted; Google Chrome open on a **long article** (scrollable page); Chrome frontmost.

Checklist:

1. [ ] Probe at run start: Chrome with a window → capabilities = dependable (scroll-wheel + Page/Home/End). Probe failure (e.g. no window) → **degrades** to the same dependable primitives (does not error).
2. [ ] Scroll actions move only the Chrome **viewport** (wheel primitive); nothing typed into the page.
3. [ ] Page Up / Page Down / Home / End move the viewport via inert keys; address bar / tab strip / page content are not edited.
4. [ ] Confirm **no tab switching** occurs and no web AX tree is used for navigation.
5. [ ] Run log (when driven by RealExecutor) remains content-free: `{timestamp, actionKind, targetBundleID, result}` only.

Notes / observed results:

- _(fill after live Chrome article run)_
- Unit `BrowserProbeTests` cover probe→primitive selection, probe-failure → degrade, page-keys-unreliable → scroll-wheel, scroll-wheel-unreliable → arrows, amount caps, and no tab primitive.

---

## Read-only editor adapter (Adapters / EditorAdapter)

Prerequisites: Accessibility granted; VS Code (or Cursor) open on a **scratch source file**; editor frontmost. Optional: enable the **Vim** keymap/extension and repeat.

Checklist:

1. [ ] `EditorAdapter` selects only scroll-wheel + arrows/Page/Home/End (all ⊆ inert allowlist); Start/run never emits characters, Return, Delete, paste, save, or Cmd/Ctrl chords.
2. [ ] Open a scratch file, note content; run a navigation loop (scroll + page + arrows). File **content unchanged**; hash/mtime identical before/after.
3. [ ] Repeat with **Vim** keymap enabled — file still unchanged (inert keys stay non-mutating in insert/normal).
4. [ ] Safety suite still green; logs content-free when driven by RealExecutor.

Notes / observed results:

- _(fill after live VS Code ± Vim run)_
- CI: `EditorAdapterTests` + `MutationGuardTests` (scratch SHA-256 before/after inert loop, with and without vim-keymap-assumed).

---

## Workflow configuration surface (WorkflowRunner)

Prerequisites: Accessibility granted; Chrome / VS Code / Finder as needed by the workflow targets; `workflows.json` seeded (menu **Seed Sample Workflows**).

Checklist:

1. [ ] **Seed Sample Workflows** writes `~/Library/Application Support/Waypoint/workflows.json` with `multi-target-scroll`.
2. [ ] Select workflow → **Run Selected Workflow** — validates, resolves running targets, selects browser/editor/generic adapters, runs via RealExecutor; content-free log summary appears.
3. [ ] If a configured target is not running, run refuses with a clear error and executes nothing.
4. [ ] Illegal / safety-denied workflows never start (CI covers this).
5. [ ] Loop caps and per-step on-error from JSON are honored.

Notes / observed results:

- _(fill after live multi-app run)_
- CI: `RunnerTests` (simulation seam) + `ResolutionTests` (target class → adapter).

---

## UI / control layer

Prerequisites: fresh Accessibility state helpful; run **Waypoint.app**.

Checklist:

1. [ ] First launch shows **Onboarding** with honest copy (what it does / never does); Request Accessibility + Settings deep-link; recheck flips to granted without relaunch.
2. [ ] **Workflow Editor**: add targets from running apps, add palette steps (scroll/page/wait only), validate, save — illegal/empty drafts cannot save.
3. [ ] Menu bar: pick saved workflow, **Start** / **Stop**, live status shows current/next/elapsed; engine does not block the menu.
4. [ ] **Run Timeline** lists content-free events after a run.
5. [ ] Full create → save → run path works without editing JSON by hand.

Notes / observed results:

- _(fill after live UI run)_
- CI: `AppTests` / `ViewModelTests`; XCUITest target `WaypointUITests` (onboarding + start/stop menu).
