#!/usr/bin/env bash
# Build Release Waypoint.app and sign with Developer ID Application + hardened runtime.
# Requires: DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DIST="${DIST:-$ROOT/dist}"
APP_NAME="Waypoint"
SCHEME="Waypoint"
PROJECT="Waypoint.xcodeproj"
IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
ENTITLEMENTS="$ROOT/App/Waypoint.entitlements"

if [[ -z "$IDENTITY" ]]; then
  echo "ERROR: Set DEVELOPER_ID_APPLICATION to your Developer ID Application identity." >&2
  echo "  Example: export DEVELOPER_ID_APPLICATION=\"Developer ID Application: Twixr Solutions (XXXXXXXXXX)\"" >&2
  echo "  List identities: security find-identity -v -p codesigning" >&2
  exit 1
fi

if [[ ! -f "$ENTITLEMENTS" ]]; then
  echo "ERROR: missing entitlements at $ENTITLEMENTS" >&2
  exit 1
fi

if grep -E '<key>com\.apple\.security\.app-sandbox</key>' "$ENTITLEMENTS"; then
  echo "ERROR: App Sandbox must stay OFF (breaks Accessibility). Remove app-sandbox from entitlements." >&2
  exit 1
fi

mkdir -p "$DIST"
ARCHIVE_PATH="$DIST/Waypoint.xcarchive"
EXPORT_DIR="$DIST/export"
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"

echo "==> Archive Release ($SCHEME)"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  ENABLE_HARDENED_RUNTIME=YES \
  ENABLE_APP_SANDBOX=NO \
  archive

APP_SRC="$ARCHIVE_PATH/Products/Applications/${APP_NAME}.app"
if [[ ! -d "$APP_SRC" ]]; then
  echo "ERROR: archived app not found at $APP_SRC" >&2
  exit 1
fi

APP_DST="$DIST/${APP_NAME}.app"
rm -rf "$APP_DST"
ditto "$APP_SRC" "$APP_DST"

echo "==> codesign (Developer ID + hardened runtime + timestamp)"
# Deep sign nested code first, then the bundle.
codesign \
  --force \
  --deep \
  --options runtime \
  --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$IDENTITY" \
  "$APP_DST"

echo "==> Verify signature"
codesign --verify --deep --strict --verbose=2 "$APP_DST"
spctl --assess --type execute --verbose=4 "$APP_DST" 2>&1 || true

echo "==> Confirm App Sandbox is OFF"
if codesign -d --entitlements :- "$APP_DST" 2>/dev/null | grep -q 'com.apple.security.app-sandbox'; then
  echo "ERROR: signed app contains App Sandbox entitlement" >&2
  exit 1
fi
echo "Sandbox check OK (no app-sandbox entitlement)"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DST/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_DST/Contents/Info.plist")"
echo "Signed $APP_DST (version $VERSION build $BUILD)"
echo "$APP_DST"
