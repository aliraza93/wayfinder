# Privacy — Waypoint

## Summary

Waypoint runs **on your Mac only**. Core automation makes **no outbound network calls**. It navigates already-open apps with read-only navigation (scroll, inert keys, allowlisted tab/file navigation, AppKit activate/open-existing-file) and records a **privacy-respecting** run log.

## Data Waypoint stores

| What | Where | Contents |
|------|--------|----------|
| Workflows | `~/Library/Application Support/Waypoint/workflows.json` | Workflow names, target bundle IDs, step kinds/parameters you configured (including file paths / tab labels you enter) |
| Session history | `~/Library/Application Support/Waypoint/session-history.json` | Start/end times, duration, workflow name, bundle IDs visited, configured target identities, action-kind counts, failure counts — never document body text or screenshots |
| Run timeline / export | In-memory during a run; export only what you choose to save | `{timestamp, actionKind, targetBundleID, result}` plus optional identity metadata you configured (e.g. relative file path, tab label) — never document body text |

Waypoint does **not** store document text, keystroke streams of typed content, screenshots, or file contents in logs.

## Permissions

- **Accessibility** — required to detect frontmost apps/windows coarsely and to synthesize inert navigation events. Granted by you in System Settings. Tied to the app’s code signature (`com.twixrsolutions.waypoint`).
- **No App Sandbox** — required for Accessibility control of other apps; distribution is Developer ID + notarized DMG, not the Mac App Store.
- **Apple Events / Automation** — not used to drive target apps. An `NSAppleEventsUsageDescription` exists only in case macOS asks when opening System Settings.

## What Waypoint never does

- Type or delete text, paste, save, or run editor commands
- Capture or alter screenshots to fake activity
- Defeat idle detection or deceive time-tracking / monitoring systems
- Load third-party plug-ins into its privileged process
- Phone home (v1)

## Updates & signing

Release builds are signed with a **stable Developer ID Application** identity, notarized with Apple’s notary service, and stapled so Gatekeeper can trust them offline. Keeping the same Developer ID across versions preserves your Accessibility grant.

## Contact

Privacy questions about Waypoint: contact Twixr Solutions (bundle id `com.twixrsolutions.waypoint`).
