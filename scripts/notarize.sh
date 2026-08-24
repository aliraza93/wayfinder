#!/usr/bin/env bash
# Submit a signed .app or .dmg to Apple notarization via notarytool.
# Prefer a keychain profile created once with:
#   xcrun notarytool store-credentials "WaypointNotary" --apple-id ... --team-id ... --password ...
#
# Env:
#   NOTARYTOOL_PROFILE  (preferred)  — keychain profile name
#   or APPLE_ID + APPLE_TEAM_ID + APPLE_APP_SPECIFIC_PASSWORD
#   SUBMIT_PATH         — path to .dmg or .app (default: dist/Waypoint-*.dmg newest, else dist/Waypoint.app)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
DIST="${DIST:-$ROOT/dist}"

SUBMIT_PATH="${SUBMIT_PATH:-}"
if [[ -z "$SUBMIT_PATH" ]]; then
  if ls "$DIST"/Waypoint-*.dmg >/dev/null 2>&1; then
    SUBMIT_PATH="$(ls -t "$DIST"/Waypoint-*.dmg | head -1)"
  elif [[ -d "$DIST/Waypoint.app" ]]; then
    SUBMIT_PATH="$DIST/Waypoint.app"
  else
    echo "ERROR: nothing to notarize. Set SUBMIT_PATH or run sign.sh / make-dmg.sh first." >&2
    exit 1
  fi
fi

if [[ ! -e "$SUBMIT_PATH" ]]; then
  echo "ERROR: SUBMIT_PATH not found: $SUBMIT_PATH" >&2
  exit 1
fi

AUTH_ARGS=()
if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
  AUTH_ARGS=(--keychain-profile "$NOTARYTOOL_PROFILE")
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
  AUTH_ARGS=(
    --apple-id "$APPLE_ID"
    --team-id "$APPLE_TEAM_ID"
    --password "$APPLE_APP_SPECIFIC_PASSWORD"
  )
else
  echo "ERROR: notarization credentials missing." >&2
  echo "  Set NOTARYTOOL_PROFILE=WaypointNotary" >&2
  echo "  or APPLE_ID + APPLE_TEAM_ID + APPLE_APP_SPECIFIC_PASSWORD" >&2
  exit 1
fi

UPLOAD="$SUBMIT_PATH"
CLEANUP=""
if [[ -d "$SUBMIT_PATH" && "$SUBMIT_PATH" == *.app ]]; then
  UPLOAD="$DIST/Waypoint-notarize-upload.zip"
  echo "==> Zipping app for upload: $UPLOAD"
  rm -f "$UPLOAD"
  ditto -c -k --keepParent "$SUBMIT_PATH" "$UPLOAD"
  CLEANUP="$UPLOAD"
fi

echo "==> notarytool submit: $UPLOAD"
# Do not print password / profile secrets.
xcrun notarytool submit "$UPLOAD" \
  "${AUTH_ARGS[@]}" \
  --wait \
  --timeout 30m

echo "==> Fetching most recent log (redact as needed)"
# History may include submission IDs only — safe to show.
xcrun notarytool history "${AUTH_ARGS[@]}" 2>&1 | head -n 20 || true

if [[ -n "$CLEANUP" ]]; then
  rm -f "$CLEANUP"
fi

echo "Notarization finished for $SUBMIT_PATH"
echo "Next: ./scripts/staple.sh"
