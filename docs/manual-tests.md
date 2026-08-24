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
- Live CGEventTap + Carbon hot-key wiring is prepared via `SovereigntyEventMapper` / `SystemSecureInputProbe`; full tap registration lands with the walking-skeleton executor milestone. Manual items 1–4 need that wiring under a running Start/Stop loop.
