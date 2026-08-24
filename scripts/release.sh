#!/usr/bin/env bash
# Full release pipeline: sign → DMG → notarize → staple.
# Does not commit secrets. Fails clearly when Developer ID / notary credentials are missing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

./scripts/sign.sh
./scripts/make-dmg.sh
export SUBMIT_PATH="$(ls -t dist/Waypoint-*.dmg | head -1)"
export STAPLE_PATH="$SUBMIT_PATH"
./scripts/notarize.sh
./scripts/staple.sh

echo "==> Release artifact"
ls -la "$STAPLE_PATH"
echo "Ship: $STAPLE_PATH"
echo "See docs/install.md for clean-machine verification."
