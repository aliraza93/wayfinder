# Privacy — Waypoint

## Summary

Waypoint runs **on your Mac only**. v1 makes **no outbound network calls**. It navigates already-open apps with inert input (scroll wheel and a small allowlisted key set) and records a **content-free** run log.

## Data Waypoint stores

| What | Where | Contents |
|------|--------|----------|
| Workflows | `~/Library/Application Support/Waypoint/workflows.json` | Workflow names, target bundle IDs, step kinds/parameters you configured |
| Run timeline / export | In-memory during a run; export only what you choose to save | `{timestamp, actionKind, targetBundleID, result}` only |

Waypoint does **not** store window titles as free-form surveillance, document text, keystroke content, screenshots, or file contents in logs.

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
