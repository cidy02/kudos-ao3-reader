#!/bin/sh
# Cheap, push-time-only leak check. This repo is public — a paid Apple
# Developer team ID must never leave this machine. Deliberately narrower
# than Scripts/check-invariants.sh (no lint, no tests): this exists to stay
# fast enough that nobody is tempted to skip it.
#
# Install (once per clone — git does not version-control hooks):
#   ln -sf ../../Scripts/pre-push.sh "$(git rev-parse --git-common-dir)/hooks/pre-push"
set -eu

# Not `dirname "$0"`: this script is invoked through a symlink from
# .git/hooks/pre-push, and $0 there is the symlink path, not this file's
# real location — dirname on it points at .git/hooks, not the repo root.
ROOT="$(git rev-parse --show-toplevel)"
FAIL=0

fail() {
  FAIL=1
  printf 'PRE-PUSH BLOCKED: %s\n%s\n\n' "$1" "$2"
}

PUBLIC_PLACEHOLDER_TEAM="NQH85H7343"

BAD_TEAM_LINES="$(grep -nE 'DEVELOPMENT_TEAM = [^";]' "$ROOT/AO3_App_OpenSource.xcodeproj/project.pbxproj" \
  | grep -v "DEVELOPMENT_TEAM = ${PUBLIC_PLACEHOLDER_TEAM};" || true)"
if [ -n "$BAD_TEAM_LINES" ]; then
  fail "project.pbxproj pins a non-placeholder DEVELOPMENT_TEAM" "${BAD_TEAM_LINES}"
fi

LEAKED_IDENTITY="$(grep -rInE 'Apple (Development|Distribution|Developer ID [A-Za-z]+): .*\([A-Z0-9]{10}\)' \
  "$ROOT" --include='*.md' --include='*.sh' --include='*.swift' --include='*.kt' --include='*.yml' \
  --exclude-dir=.git --exclude-dir=DerivedData --exclude-dir=build 2>/dev/null || true)"
if [ -n "$LEAKED_IDENTITY" ]; then
  fail "a signing identity with a team ID is embedded in a tracked file" "${LEAKED_IDENTITY}"
fi

if git -C "$ROOT" ls-files --error-unmatch "Config/LocalSigning.xcconfig" >/dev/null 2>&1; then
  fail "Config/LocalSigning.xcconfig is tracked by git" \
    "git rm --cached Config/LocalSigning.xcconfig"
fi

if [ "$FAIL" -ne 0 ]; then
  echo "pre-push: BLOCKED — fix the above, or this push may publish a private team ID."
  exit 1
fi
exit 0
