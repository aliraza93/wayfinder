# AGENTS.md — Waypoint

> This file is read automatically by Cursor and other coding agents at the start of every session. It also serves as `.cursorrules`. These rules are **binding**. Product-owner prompts that expand **read-only navigation** take precedence over older milestone docs that froze a smaller MVP; do **not** refuse lawful navigation features as “out of scope” when they preserve the mutation ban below.

## What Waypoint is

Waypoint is a native macOS menu-bar app that runs user-defined, **read-only navigation workflows** across already-open apps — especially **Cursor** (or VS Code-class editors) and **Google Chrome** — for legitimate reading/review:

- Focus / activate already-running apps and windows
- Open or switch to **existing** workspace files the user configured
- Switch among **existing** editor tabs / Chrome tabs when adapters can do so safely
- Scroll, page, and arrow-key navigate within the focused document or page
- Timed / looped runs with Start · Pause · Resume · Stop
- Return focus between Cursor and Chrome as the workflow requires

**Tagline:** *Hands-free navigation. Never touches your work.*

## Project constants (single source of truth)

- **Product name:** Waypoint
- **Bundle identifier:** `com.twixrsolutions.waypoint` ← baked into signing and the Accessibility permission grant. Do NOT change it after first shipping; changing it later resets every user's granted permission.
- **Config location:** `~/Library/Application Support/Waypoint/workflows.json`
- **Language / UI:** Swift, SwiftUI (`MenuBarExtra`), AppKit interop where needed.
- **Distribution:** Developer ID + notarization, shipped as a DMG. **NOT** the Mac App Store.

## Absolute invariants (never violate)

1. **Read-only for document contents.** There must be **no** code path that:
   - types arbitrary characters into an editor or page
   - presses Return / Delete / Backspace as editing
   - pastes, cuts, or replaces text
   - saves, formats, refactors, or runs editor/IDE commands that mutate files
   - introduces a generic `typeText` / unrestricted keystroke API

   Navigation **is** allowed: scroll-wheel; inert keys (arrows, Page Up/Down, Home/End); **explicit, allowlisted navigation chords** used only by adapters for tab/file/window switching (e.g. Chrome/Cursor tab next/previous); **AppKit / Accessibility app-control** (activate app, open existing file URL, focus window); **targeted mouse clicks** only on adapter-resolved navigation targets (known tab/file chrome), never arbitrary desktop clicking.

2. **No deception.** Do not implement anything intended to fabricate activity, falsify screenshots, defeat idle detection, deceive time-tracking, or mislead monitoring. Logs are truthful. No screenshot-capture pipeline for deception.

3. **Single safety gate.** Every action executes through one path that first calls `SafetyPolicy.validate`. Do not bypass this gate. Expand allowlists deliberately in `Safety` + capability tags when adding navigation actions — never by skipping validation.

4. **Focus guard + self-event tag.** Synthetic `CGEvent` input is emitted only after the focus guard confirms the **intended** app is frontmost and stable, and every synthetic event is tagged so the user-sovereignty monitor ignores it. Fail safely if the target app/window cannot be verified — do not send input blindly to whatever is focused. Untagged user input or Stop terminates the run.

5. **Privacy-respecting logs.** Prefer structured fields: `{timestamp, actionKind, targetBundleID, result}` plus optional **identity** metadata the user already configured (e.g. relative file path, tab label used for matching). **Never** log document body text, file contents, or keystroke streams of typed content.

6. **No network.** No outbound network calls required for core automation (no SaaS automation backends, no API keys for navigation).

7. **No App Sandbox.** The app must not enable App Sandbox (it breaks Accessibility). No dynamically loaded third-party code in this privileged process.

## Product scope agents must implement (do not leave incomplete)

When the owner asks for long-running Cursor + Chrome reading workflows, agents **shall** build toward:

| Area | Required capability |
|------|---------------------|
| Cursor / editor | Detect running app; activate; open/switch **existing** configured files; scroll/page/arrows in the focused editor; switch existing editor tabs via adapter |
| Chrome | Detect running app; activate; switch **existing** tabs via adapter; scroll/page in the focused tab; return to Cursor |
| Engine | Multi-step workflows, duration / until-stopped, pause/resume/stop, retarget between apps mid-run |
| Adapters | Keep app-specific logic in `Adapters` / `AppControl` — not hard-coded inside the pure engine |
| UI | Targets, duration, files/tabs config, live status, hot-keys |
| Safety | Explicit allowlist; `mutatesText` always false for every `ActionKind` |

Older roadmap text that said “no `switchTab` / no Cmd chords ever” described an **MVP freeze**, not a permanent product ban. Prefer adapter-scoped, allowlisted navigation over refusing the feature.

## Module boundaries (do not blur)

Pure-logic modules — `Domain`, `Config`, `Safety`, `CoreEngine`, `Timing` — must **not** import AppKit / ApplicationServices / Accessibility. They run in headless CI. macOS-specific code lives in `AppControl`, `Accessibility`, `InputSynthesis`, `Permissions`, `Adapters`, and `App`.

`InputSynthesis` is the only module that may emit `CGEvent`s (scroll, inert keys, allowlisted navigation chords, targeted clicks) — always tagged and focus-guarded. App activation and opening existing files use **AppKit / `NSWorkspace`** in `AppControl`, not character typing.

## How to work in this repo

- Prefer **incremental** delivery of the owner’s feature prompt; reuse existing engine, safety, adapters, and UI.
- **Do not redesign** unrelated modules.
- **Inspect before editing.** State which files you will read and modify before writing code.
- **Do not touch unrelated files.**
- **Build and run the tests you write.** Report failures honestly.
- **Leave the repo buildable and green** after each coherent change set.
- **Never modify the safety suite to make a mutating action pass.** If a navigation action is added, update allowlists and tests **together** so SafetyTests still prove `mutatesText == false` and forbidden editing keys remain denied.
- Milestone labels in `docs/04-cursor-prompts.md` are historical; owner feature prompts override “stop at MVP” when they expand read-only navigation.

## The documents (in `docs/`)

- `00-START-HERE.md` — orientation
- `01-build-plan.md` / `02-architecture-review.md` / `03-implementation-roadmap.md` — original MVP plan (still useful; superseded where this file allows navigation expansion)
- `04-cursor-prompts.md` / `05-execution-protocol.md` — milestone history
- `testing.md` / `install.md` / `privacy.md` — testing and distribution
