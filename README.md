# Waypoint

Hands-free navigation. Never touches your work.

Waypoint is a macOS menu-bar app that runs user-defined, **strictly read-only** navigation workflows across already-open apps (Chrome, VS Code / editors, Finder, and others). It can switch apps/windows, scroll, page, wait, and return — and it logs the truth about what it did.

**Bundle identifier:** `com.twixrsolutions.waypoint`

## What it will never do

- **Read-only for editors and everything.** Waypoint emits only inert navigation primitives: scroll-wheel events and the inert key set (arrows, Page Up/Down, Home/End). It does not type characters, press Return, Delete/Backspace, paste, save, run editor commands, or send Cmd/Ctrl navigation chords. Nothing that mutates text is in the action set.
- **No deception.** Waypoint does not fabricate activity, falsify or manipulate screenshots, defeat idle detection, deceive time-tracking, or mislead any monitoring system. There is no screenshot-capture pipeline. Logs are truthful and content-free (`timestamp`, `actionKind`, `targetBundleID`, `result` only).

## Status

Project foundation (CURSOR-01): buildable menu-bar shell, empty Swift package modules, and CI for package tests + app build. Real workflow functionality comes in later milestones.

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
