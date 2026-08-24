#!/usr/bin/env bash
# Staple a notarization ticket onto a .app or .dmg.
# Env: STAPLE_PATH — default newest dist/Waypoint-*.dmg, else dist/Waypoint.app
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
DIST="${DIST:-$ROOT/dist}"

STAPLE_PATH="${STAPLE_PATH:-}"
if [[ -z "$STAPLE_PATH" ]]; then
  if ls "$DIST"/Waypoint-*.dmg >/dev/null 2>&1; then
    STAPLE_PATH="$(ls -t "$DIST"/Waypoint-*.dmg | head -1)"
  elif [[ -d "$DIST/Waypoint.app" ]]; then
    STAPLE_PATH="$DIST/Waypoint.app"
  else
    echo "ERROR: nothing to staple. Set STAPLE_PATH." >&2
    exit 1
  fi
fi

if [[ ! -e "$STAPLE_PATH" ]]; then
  echo "ERROR: STAPLE_PATH not found: $STAPLE_PATH" >&2
  exit 1
fi

echo "==> stapler staple: $STAPLE_PATH"
xcrun stapler staple "$STAPLE_PATH"
xcrun stapler validate "$STAPLE_PATH"

echo "==> Gatekeeper assessment (may still warn until stapled DMG is distributed)"
spctl --assess --type open --context context:primary-signature -v "$STAPLE_PATH" 2>&1 || true

echo "Stapled: $STAPLE_PATH"
