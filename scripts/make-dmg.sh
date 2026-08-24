#!/usr/bin/env bash
# Package dist/Waypoint.app into a versioned DMG.
# Prefers `create-dmg` when installed (brew install create-dmg); otherwise hdiutil.
# Env: APP_PATH (default dist/Waypoint.app), DIST
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
DIST="${DIST:-$ROOT/dist}"
APP_PATH="${APP_PATH:-$DIST/Waypoint.app}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: app not found at $APP_PATH — run ./scripts/sign.sh first." >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
DMG_NAME="Waypoint-${VERSION}-${BUILD}.dmg"
DMG_PATH="$DIST/$DMG_NAME"
STAGE="$DIST/dmg-stage"

rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP_PATH" "$STAGE/Waypoint.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG_PATH"

echo "==> Creating $DMG_PATH"
if command -v create-dmg >/dev/null 2>&1; then
  create-dmg \
    --volname "Waypoint ${VERSION}" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "Waypoint.app" 150 190 \
    --app-drop-link 450 185 \
    --hide-extension "Waypoint.app" \
    "$DMG_PATH" \
    "$STAGE"
else
  echo "note: create-dmg not found; using hdiutil (brew install create-dmg for fancy layout)"
  TEMP_DMG="$DIST/Waypoint-temp.dmg"
  rm -f "$TEMP_DMG"
  hdiutil create \
    -volname "Waypoint ${VERSION}" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    "$TEMP_DMG"
  mv "$TEMP_DMG" "$DMG_PATH"
fi

rm -rf "$STAGE"

# Sign the DMG if Developer ID is available (recommended before notarize).
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  echo "==> codesign DMG"
  codesign --force --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
fi

echo "DMG ready: $DMG_PATH"
echo "$DMG_PATH"
