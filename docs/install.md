# Install Waypoint

Hands-free navigation. Never touches your work.

## What it does

Waypoint is a macOS **menu-bar** app. You define read-only navigation workflows (switch among already-open apps, scroll, page, wait, return). It runs those steps for you and logs what it did.

## What it never does

- Types characters, Return, Delete/Backspace, paste, or save
- Sends Cmd/Ctrl navigation chords or editor commands
- Mutates text in editors or other apps
- Captures screenshots or fabricates activity for monitoring tools
- Talks to the network in v1

## Requirements

- macOS 13 or later
- **Accessibility** permission for `com.twixrsolutions.waypoint`

**Personal / same-Mac use:** build and run from Xcode (ad-hoc or Apple Development signing). No notarization required. Grant Accessibility after each signature change if the grant disappears.

**Distributing to other Macs:** ship a **Developer ID–signed, notarized** DMG (Gatekeeper-trusted). That path is optional and documented under “Build & release” below — skip it for local-only use.

Waypoint is **not** on the Mac App Store. Controlling other apps via Accessibility is incompatible with the App Sandbox.

## Install from DMG

1. Download `Waypoint-<version>-<build>.dmg`.
2. Open the DMG (Gatekeeper should accept a stapled notarized image without “unidentified developer” blocks).
3. Drag **Waypoint** to **Applications**.
4. Eject the DMG.
5. Launch **Waypoint** from Applications (menu-bar icon appears).

If macOS quarantines an unsigned or un-notarized build, System Settings → Privacy & Security may offer **Open Anyway**. Prefer shipping only stapled notarized DMGs.

## Grant Accessibility

1. Open the Waypoint menu → follow onboarding, or choose **Request Accessibility…** / **Open Accessibility Settings**.
2. Enable **Waypoint** under **System Settings → Privacy & Security → Accessibility**.
3. Return to the menu bar; the grant should show without relaunching.

The grant is tied to the **code signature**. Keep a **stable Developer ID** across releases so users do not have to re-toggle Accessibility after every update. Ad-hoc / constantly re-signed **dev** builds often lose the grant on rebuild.

## Run a workflow

1. Ensure Chrome, VS Code, Finder, or another target is open with scrollable content.
2. Create or select a workflow in the editor (inert actions only).
3. **Start** from the menu. Stop with the menu control, real input, or **Ctrl+Option+.** .

## Read logs

Run logs are **content-free**: only `timestamp`, `actionKind`, `targetBundleID`, and `result`. Export or view them from the in-app timeline / export affordance. They never include window text, document contents, or keystrokes.

Workflows persist at:

`~/Library/Application Support/Waypoint/workflows.json`

## Build & release (maintainers)

```bash
# Config checks + Release build (no Developer ID required)
./scripts/verify-packaging.sh

# Full ship pipeline (requires Developer ID + notary credentials)
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
export NOTARYTOOL_PROFILE="WaypointNotary"   # from: xcrun notarytool store-credentials …
./scripts/release.sh
# → dist/Waypoint-<version>-<build>.dmg (signed, notarized, stapled)
```

Individual steps: `scripts/sign.sh` → `scripts/make-dmg.sh` → `scripts/notarize.sh` → `scripts/staple.sh`.

Optional fancy DMG layout: `brew install create-dmg` (otherwise `hdiutil`).

**Sparkle auto-updates** are intentionally omitted in v1 (no network).

## Clean-machine checklist

On a second Mac or fresh user account:

1. [ ] Download the stapled DMG; open without Gatekeeper block.
2. [ ] Drag to Applications; launch; menu bar icon appears.
3. [ ] Accessibility prompt / Settings toggle works; state becomes Granted.
4. [ ] Start a short scroll workflow on Chrome or VS Code; content unchanged.
5. [ ] Stop via hot-key or real input; timeline/log is content-free.
