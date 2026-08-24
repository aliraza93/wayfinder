#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> swift build (all package modules)"
swift build

echo "==> Pure-logic + component package tests (merge CI)"
# Includes Safety, Engine (state machine / simulation), Config, Domain, Observability redaction,
# Adapters (incl. mutation-guard), AppTests. Does NOT run XCUITest.
swift test

echo "==> SafetyTests merge gate (explicit)"
# A red SafetyTests suite must fail CI even if the broader `swift test` invocation changes.
if ! swift test --filter SafetyTests; then
  echo "ERROR: SafetyTests merge gate FAILED — do not merge." >&2
  exit 1
fi
echo "SafetyTests merge gate OK"

echo "==> Mutation-guard (editor read-only hash)"
swift test --filter MutationGuardTests

echo "==> xcodebuild build (app compile only — no live AX)"
xcodebuild \
  -project Waypoint.xcodeproj \
  -scheme Waypoint \
  -destination 'platform=macOS' \
  -configuration Debug \
  build

echo "==> CI OK (pure logic + safety gate + app build; UITests/live AX not gated)"
echo "See docs/testing.md for manual matrix and provisioned runner path."
