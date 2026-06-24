#!/bin/sh
# Lint + format check for Kudos. Used locally and by CI.
#
#   Scripts/lint.sh            # run SwiftLint (the gate) + a SwiftFormat advisory
#   Scripts/lint.sh --fix      # auto-format in place (SwiftFormat + SwiftLint --fix)
#
# Install the tools with: brew install swiftlint swiftformat
#
# SwiftLint determines the exit code. SwiftFormat is advisory only: the codebase
# is hand-wrapped and a bulk reformat would be pure churn, so `--lint` here just
# reports how many files differ from the house style — run `--fix` to apply.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SOURCES="kudos-ao3-reader"
status=0

if [ "${1:-}" = "--fix" ]; then
  command -v swiftformat >/dev/null 2>&1 && { echo "› swiftformat (in place)"; swiftformat "$SOURCES"; }
  command -v swiftlint   >/dev/null 2>&1 && { echo "› swiftlint --fix";        swiftlint --fix --quiet "$SOURCES"; }
fi

if command -v swiftlint >/dev/null 2>&1; then
  echo "› swiftlint"
  swiftlint lint --quiet "$SOURCES" || status=1   # warnings exit 0; only errors fail
else
  echo "warning: swiftlint not installed (brew install swiftlint)"
fi

if command -v swiftformat >/dev/null 2>&1 && [ "${1:-}" != "--fix" ]; then
  echo "› swiftformat available — run 'Scripts/lint.sh --fix' to apply house style"
fi

exit "$status"
