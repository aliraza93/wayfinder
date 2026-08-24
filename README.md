# Waypoint

Hands-free navigation. Never touches your work.

Waypoint is a macOS menu-bar app that runs user-defined, **strictly read-only** navigation workflows across already-open apps (Chrome, VS Code / editors, Finder, and others). It can switch apps/windows, scroll, page, wait, and return — and it logs the truth about what it did.

**Bundle identifier:** `com.twixrsolutions.waypoint`

## What it will never do

- **Read-only for editors and everything.** Waypoint emits only inert navigation primitives: scroll-wheel events and the inert key set (arrows, Page Up/Down, Home/End). It does not type characters, press Return, Delete/Backspace, paste, save, run editor commands, or send Cmd/Ctrl navigation chords. Nothing that mutates text is in the action set.
- **No deception.** Waypoint does not fabricate activity, falsify or manipulate screenshots, defeat idle detection, deceive time-tracking, or mislead any monitoring system. There is no screenshot-capture pipeline. Logs are truthful and content-free (`timestamp`, `actionKind`, `targetBundleID`, `result` only).

## Status

Buildable menu-bar app with Domain/Config/Safety/engine packages, app detection, and Accessibility permission handling. Further interaction milestones follow.

## Accessibility permission (dev note)

Waypoint needs **Accessibility** (TCC). The grant is tied to the app’s **code signature**. Ad-hoc / constantly re-signed **dev builds often lose the grant on rebuild**, so System Settings may show a stale or missing entry after each build.

**Recommendation:** use a **stable local signing identity** (Apple Development or a shared Developer ID for local runs) so the bundle id + signing identity stay constant across rebuilds. After a signature change, toggle Waypoint off/on again under **System Settings → Privacy & Security → Accessibility**.

The menu bar exposes a small debug affordance: current grant state, **Request Accessibility…** (prompts at most once, then deep-links), and **Open Accessibility Settings**. Re-check runs when the app becomes active so enabling the toggle can flip to granted without relaunching.

## Development

```bash
# Pure-logic package tests
swift test

# App build
xcodebuild -project Waypoint.xcodeproj -scheme Waypoint -destination 'platform=macOS' build

# Full local CI
./scripts/ci.sh
```

Requires Xcode (full app, not only Command Line Tools) for `xcodebuild` and running the menu-bar app.

## Layout

- `App/` — thin SwiftUI `MenuBarExtra` host
- `Sources/` — local Swift package modules (`Domain`, `Config`, `Safety`, `CoreEngine`, `Timing`, and platform modules)
- `Tests/` — package unit tests
- `docs/` — architecture and milestone documentation
- `AGENTS.md` — binding rules for coding agents

## License

See [LICENSE](LICENSE).
