#!/usr/bin/env bash
# Fast regression checks for check-binding-drift.sh's destructive/fail-open paths.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$(mktemp -d "${TMPDIR:-/tmp}/kudos-binding-drift.XXXXXX")"
trap 'rm -rf "$FIXTURES"' EXIT

fail() {
  echo "test-binding-drift: FAILED — $1"
  exit 1
}

fixture() {
  local name="$1"
  local has_cargo="${2:-yes}"
  local dir="$FIXTURES/$name"
  mkdir -p "$dir/Scripts" "$dir/bin" "$dir/kudos-ao3-reader/Generated/KudosMail"
  cp "$ROOT/Scripts/check-binding-drift.sh" "$dir/Scripts/check-binding-drift.sh"
  chmod +x "$dir/Scripts/check-binding-drift.sh"
  printf 'original\n' > "$dir/kudos-ao3-reader/Generated/KudosMail/kudos_mail_core.swift"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -eu' \
    'ROOT="$(cd "$(dirname "$0")/.." && pwd)"' \
    ': > "$ROOT/build-called"' \
    'case "${STUB_MODE:-same}" in' \
    '  fail) printf "changed\n" > "$ROOT/kudos-ao3-reader/Generated/KudosMail/kudos_mail_core.swift"; exit 23 ;;' \
    '  drift) printf "changed\n" > "$ROOT/kudos-ao3-reader/Generated/KudosMail/kudos_mail_core.swift" ;;' \
    'esac' \
    > "$dir/Scripts/build-mail-xcframework.sh"
  chmod +x "$dir/Scripts/build-mail-xcframework.sh"
  if [ "$has_cargo" = "yes" ]; then
    printf '#!/bin/sh\nexit 0\n' > "$dir/bin/cargo"
    chmod +x "$dir/bin/cargo"
  fi
  git -C "$dir" init -q
  git -C "$dir" add .
  git -C "$dir" -c user.name=Test -c user.email=test@example.invalid \
    -c commit.gpgSign=false -c core.hooksPath=/dev/null commit -qm fixture
  printf '%s\n' "$dir"
}

run_check() {
  local dir="$1"
  local mode="${2:-same}"
  set +e
  KUDOS_RUST_PATH="$dir/bin" PATH="/usr/bin:/bin" STUB_MODE="$mode" \
    "$dir/Scripts/check-binding-drift.sh" > "$dir/output" 2>&1
  CHECK_STATUS=$?
  set -e
}

no_cargo="$(fixture no-cargo no)"
run_check "$no_cargo"
[ "$CHECK_STATUS" -ne 0 ] || fail "missing cargo passed"
grep -q 'FAILED (no cargo on PATH)' "$no_cargo/output" || fail "missing-cargo reason absent"
[ ! -e "$no_cargo/build-called" ] || fail "build ran without cargo"

staged="$(fixture staged)"
printf 'staged\n' > "$staged/kudos-ao3-reader/Generated/KudosMail/kudos_mail_core.swift"
git -C "$staged" add kudos-ao3-reader/Generated/KudosMail/kudos_mail_core.swift
run_check "$staged"
[ "$CHECK_STATUS" -ne 0 ] || fail "staged binding passed"
grep -qx 'staged' "$staged/kudos-ao3-reader/Generated/KudosMail/kudos_mail_core.swift" \
  || fail "staged binding was overwritten"
[ ! -e "$staged/build-called" ] || fail "build ran with a staged binding"

failed="$(fixture failed-build)"
run_check "$failed" fail
[ "$CHECK_STATUS" -eq 23 ] || fail "failed build status was not preserved"
grep -qx 'original' "$failed/kudos-ao3-reader/Generated/KudosMail/kudos_mail_core.swift" \
  || fail "failed regeneration did not restore the binding"
grep -q 'restored' "$failed/output" || fail "restore was not reported"

drift="$(fixture drift)"
run_check "$drift" drift
# Exit code AND message: a bare non-zero would also be satisfied by the script
# dying for an unrelated reason, which is the failure mode this test exists to
# catch.
[ "$CHECK_STATUS" -eq 1 ] || fail "binding drift did not exit 1 (got $CHECK_STATUS)"
grep -q 'does not match the crate' "$drift/output" || fail "drift was not reported as drift"
grep -qx 'changed' "$drift/kudos-ao3-reader/Generated/KudosMail/kudos_mail_core.swift" \
  || fail "drift evidence was restored instead of preserved"

clean="$(fixture clean)"
run_check "$clean"
[ "$CHECK_STATUS" -eq 0 ] || fail "matching binding failed"

echo "test-binding-drift: OK"
