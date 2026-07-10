#!/bin/sh
# The whole definition-of-done as one command (docs/AGENT_ONBOARDING.md):
#   invariants → lint → full iOS suite → macOS build → whitespace check.
# Agents: run this before claiming any change is done. Pass a destination to
# override the canonical simulator.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-platform=iOS Simulator,name=iPhone 17,OS=26.5}"

echo "== 1/5 invariants =="
"$ROOT/Scripts/check-invariants.sh"

echo "== 2/5 lint =="
"$ROOT/Scripts/lint.sh"

echo "== 3/5 iOS test suite ($DEST) =="
"$ROOT/Scripts/test.sh" "$DEST"

echo "== 4/5 macOS build =="
"$ROOT/Scripts/build-macos.sh"

echo "== 5/5 whitespace =="
git -C "$ROOT" diff --check
echo "verify: ALL GREEN"
