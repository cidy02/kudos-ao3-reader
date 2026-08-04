#!/bin/sh
# Mechanical scar-tissue gates for the Android product line (Apple verify step 1 analogue).
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/app/src/main/java"

fail() {
  echo "INVARIANT FAIL: $*" >&2
  exit 1
}

echo "check-invariants: scanning $SRC"

# 1) User-Agent only defined in AO3UserAgent
ua_hits=$(grep -RIn --include='*.kt' 'Mozilla/5.0' "$SRC" | grep -v 'AO3UserAgent.kt' || true)
if [ -n "$ua_hits" ]; then
  echo "$ua_hits"
  fail "Mozilla/5.0 appears outside AO3UserAgent.kt"
fi
grep -q 'KudosReader/' "$SRC/io/github/cidy02/kudos/network/ao3/AO3UserAgent.kt" || \
  fail "AO3UserAgent must include KudosReader/<version> token"

# 2) Backup must never touch credentials.
# Comment lines are allowed (they document *why* passwords aren't stored);
# any real code reference is a failure. The previous version of this check
# could never fail: its `then` branch was a no-op, and its own filter stripped
# every line the first grep matched.
# Allowed: comment lines, and UI copy that promises passwords are NOT stored.
pw_hits=$(grep -RIn --include='*.kt' -iE 'password' \
  "$SRC/io/github/cidy02/kudos/backup" \
  | grep -vE ':[0-9]+: *(//|\*|/\*)' \
  | grep -viE 'never (stored|saved|written|included)' || true)
if [ -n "$pw_hits" ]; then
  echo "$pw_hits"
  fail "backup package must not reference passwords in code"
fi

# 3) Backup must not touch session/cookie stores
if grep -RIn --include='*.kt' -E 'CookieStore|sessionStore|AO3Session' \
  "$SRC/io/github/cidy02/kudos/backup" | grep -v BackupScreen >/dev/null 2>&1; then
  fail "backup package must not reference AO3 session/cookie stores"
fi

# 4) Backup version ceiling matches Apple current (v8)
grep -q 'const val CURRENT = 8' "$SRC/io/github/cidy02/kudos/backup/BackupVersion.kt" || \
  fail "BackupVersion.CURRENT must be 8 (Apple manifest currentVersion)"

# 5) Politeness default 600ms
grep -q 'minDelayBetweenRequestsMillis: Long = 600' \
  "$SRC/io/github/cidy02/kudos/network/ao3/AO3NetworkConfig.kt" || \
  fail "AO3NetworkConfig default pace must be 600ms"

echo "check-invariants: OK"
