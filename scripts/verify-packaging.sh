#!/usr/bin/env bash
# Local checks that do not require Developer ID: sandbox off, Info.plist, entitlements, Release build.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> Entitlements must not enable App Sandbox"
if grep -E '<key>com\.apple\.security\.app-sandbox</key>' App/Waypoint.entitlements; then
  echo "FAIL: App Sandbox present in App/Waypoint.entitlements" >&2
  exit 1
fi
echo "OK: no app-sandbox in entitlements file"

echo "==> Info.plist present"
test -f App/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' App/Info.plist >/dev/null
/usr/libexec/PlistBuddy -c 'Print :NSAppleEventsUsageDescription' App/Info.plist >/dev/null
echo "OK: App/Info.plist"

echo "==> Release build (ad-hoc; packaging re-signs with Developer ID)"
xcodebuild \
  -project Waypoint.xcodeproj \
  -scheme Waypoint \
  -configuration Release \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" \
  ENABLE_APP_SANDBOX=NO \
  ENABLE_HARDENED_RUNTIME=YES \
  build

APP="$(find ~/Library/Developer/Xcode/DerivedData -path '*/Build/Products/Release/Waypoint.app' -type d 2>/dev/null | head -1 || true)"
if [[ -z "$APP" ]]; then
  # Fallback: ask xcodebuild for CONFIGURATION_BUILD_DIR
  APP="$(xcodebuild -project Waypoint.xcodeproj -scheme Waypoint -configuration Release -showBuildSettings 2>/dev/null | awk -F' = ' '/CONFIGURATION_BUILD_DIR/ {print $2; exit}')/Waypoint.app"
fi

if [[ -d "$APP" ]]; then
  echo "==> Built app: $APP"
  if codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q 'com.apple.security.app-sandbox'; then
    echo "FAIL: built app has App Sandbox entitlement" >&2
    exit 1
  fi
  echo "OK: built app has no App Sandbox entitlement"
  plutil -p "$APP/Contents/Info.plist" | head -n 40
else
  echo "WARN: could not locate Release Waypoint.app for entitlement inspect (build still succeeded)"
fi

echo "==> Packaging config verification OK"
