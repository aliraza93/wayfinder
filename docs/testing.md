# Testing — Waypoint

How we test, what CI can prove, and what must stay manual.

## Test pyramid

| Tier | Location | Runs in merge CI? | What it proves |
|------|----------|-------------------|----------------|
| **Pure logic** | `DomainTests`, `ConfigTests`, `SafetyTests`, `EngineTests`, `ObservabilityTests` (redaction), `AdapterTests` (probe/selection, mutation-guard hash), `AppTests` (view models) | **Yes** | State machine, safety allowlist/matrix, config validation, content-free logs, adapter selection, editor VM validation |
| **Component (simulation)** | `EngineTests` + `RunnerTests` via `SimulationExecutor` / recording posters | **Yes** | Multi-step workflows, loop caps, sovereignty stop, recovery injections — **no** real CGEvents |
| **Mutation guard** | `AdapterTests/MutationGuardTests` | **Yes** | Scratch file SHA-256 unchanged after inert navigation loop (default + vim-assumed) |
| **App build** | `xcodebuild` Waypoint scheme | **Yes** (compile only) | App target links packages |
| **XCUITest** | `Tests/UITests` / `WaypointUITests` | **No** (optional local) | Menu/onboarding host affordances — can be environment-flaky |
| **Live / manual** | `docs/manual-tests.md` + matrix below | **No** | Real Chrome/VS Code/Finder, TCC, focus, hot-key |

**Merge gate:** `SafetyTests` must be green. `scripts/ci.sh` runs the full package suite, then **re-runs `SafetyTests` alone** so a red safety suite fails CI even if other filters change later. Do **not** put live CGEvent / TCC / menu-bar flakiness into the gate.

## What ordinary CI cannot do

- Grant or exercise **Accessibility (TCC)** — requires user consent or a pre-provisioned machine.
- Drive a real frontmost Chrome / VS Code / Finder window with synthetic input.
- Reliably click the **MenuBarExtra** (often zero-size / not hittable under XCUITest).

Do not pretend generic GitHub-hosted macOS runners can replace a provisioned GUI agent for end-to-end AX.

## Provisioned integration path

For true end-to-end (scroll a frontmost app, hot-key stop, permission onboarding):

1. **Self-hosted macOS runner** (or dedicated Mac mini) with GUI session logged in.
2. Pre-grant Accessibility via **PPPC** (Privacy Preferences Policy Control) / MDM profile for `com.twixrsolutions.waypoint` (and keep a **stable Developer ID** so the grant survives updates).
3. Install Chrome, VS Code (optional Vim keymap), Finder available.
4. Run a scripted smoke: launch app → Start workflow → assert content-free log → Stop via hot-key / real input.
5. Keep that job **out of the merge gate**; run on a schedule or release candidate.

Sample PPPC payload fields (illustrative — tailor to your MDM):

- Identifier: `com.twixrsolutions.waypoint`
- Code requirement: Developer ID Application certificate of your team
- Service: `Accessibility` → Allow

## Manual matrix

Supported OS for v1 documentation: **macOS 13+** (deployment target). Record one pass on the machines you ship against.

| Target \ Host | macOS 13 | macOS 14 | macOS 15 | macOS 26* |
|---------------|----------|----------|----------|-----------|
| Google Chrome | | | | |
| VS Code (no Vim) | | | | |
| VS Code + Vim keymap | | | | |
| Finder | | | | |

\*Apple versioning on this build machine reported Darwin 25 / macOS SDK 26.x — treat as current shipping macOS family when filling cells.

### Per-cell checklist (abbreviated)

1. Accessibility granted for Waypoint.
2. Bring target frontmost with scrollable content / scratch file.
3. Run a short read-only workflow (scroll ± page).
4. Confirm **no text mutation**; file hash unchanged for editors.
5. Real input or Ctrl+Opt+. stops promptly; log is content-free.

### Recorded pass (this repo)

| Date | Host | Results |
|------|------|---------|
| 2026-08-24 | Developer Mac (darwin 25.6 / Xcode 17F113) | **`./scripts/ci.sh` green** (pure logic + SafetyTests gate + MutationGuardTests + app build). **Gate proof:** temporary `XCTFail` in `AllowlistTests` → `swift test --filter SafetyTests` exit 1 and `./scripts/ci.sh` exit 1 → revert → green. **Live matrix:** Chrome/Finder enumeration exercised earlier on this host; VS Code + full scroll/hash cells still to fill before release — see `docs/manual-tests.md`. |

Detail checklists: [`docs/manual-tests.md`](manual-tests.md).

## Local commands

```bash
# Full merge-style CI (no XCUITest)
./scripts/ci.sh

# Safety gate only
swift test --filter SafetyTests

# Mutation guard
swift test --filter MutationGuardTests

# Optional UI tests (not gated)
xcodebuild test -project Waypoint.xcodeproj -scheme Waypoint \
  -destination 'platform=macOS' -only-testing:WaypointUITests
```

## Proving the safety merge gate

1. Temporarily break an assertion in `Tests/SafetyTests` (e.g. force `XCTFail`).
2. `swift test --filter SafetyTests` → **must fail** (non-zero).
3. Revert the break.
4. Re-run → **must pass**.

Never “fix” a red SafetyTests suite by editing the test expectations to match unsafe code — fix the product instead (`AGENTS.md`).
