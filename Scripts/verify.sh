#!/bin/sh
# The whole definition-of-done as one command (docs/AGENT_ONBOARDING.md):
#   invariants → lint → full iOS suite → macOS build → whitespace check.
# Agents: run this before claiming any change is done. Pass a booted simulator
# UDID, or set KUDOS_CASEFOLD_SIMULATOR_UDID, so the case-sensitive test harness
# can mount inside the app container.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIMULATOR_UDID="${1:-${KUDOS_CASEFOLD_SIMULATOR_UDID:-}}"
if [ -z "$SIMULATOR_UDID" ]; then
    echo "Usage: KUDOS_CASEFOLD_SIMULATOR_UDID=<udid> $0 [udid]" >&2
    exit 64
fi

# Vendor/ is gitignored (~48 MB of built binaries), so a fresh clone or a new
# git worktree has none — and without it the run dies four minutes in, at the
# test build, with "There is no XCFramework found at ...", which reads like a
# project misconfiguration rather than a missing prerequisite. Fail up front
# with the command that fixes it instead.
if [ ! -d "$ROOT/Vendor/MuPDF.xcframework" ]; then
    echo "verify: missing Vendor/MuPDF.xcframework (gitignored — it is built, not cloned)." >&2
    echo "        Build it once with:  Scripts/build-mupdf.sh" >&2
    echo "        Or, if another worktree already has one, symlink it:" >&2
    echo "        mkdir -p '$ROOT/Vendor' && ln -s /path/to/other/Vendor/MuPDF.xcframework '$ROOT/Vendor/'" >&2
    exit 1
fi

echo "== 1/5 invariants =="
"$ROOT/Scripts/check-invariants.sh"

echo "== 2/5 lint =="
"$ROOT/Scripts/lint.sh"

echo "== 3/5 iOS test suite ($SIMULATOR_UDID) =="
KUDOS_CASEFOLD_SIMULATOR_UDID="$SIMULATOR_UDID" "$ROOT/Scripts/test.sh"

echo "== 4/5 macOS build =="
"$ROOT/Scripts/build-macos.sh"

echo "== 5/5 whitespace =="
git -C "$ROOT" diff --check
echo "verify: ALL GREEN"
