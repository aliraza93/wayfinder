#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> swift build (all package modules)"
swift build

echo "==> swift test (packages)"
swift test

echo "==> SafetyTests merge gate"
swift test --filter SafetyTests
# Explicit gate: a red SafetyTests suite must block merge even if other filters change later.

echo "==> xcodebuild build (app)"
xcodebuild \
  -project Waypoint.xcodeproj \
  -scheme Waypoint \
  -destination 'platform=macOS' \
  -configuration Debug \
  build

echo "==> CI OK"
