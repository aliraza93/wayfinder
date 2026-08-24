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
