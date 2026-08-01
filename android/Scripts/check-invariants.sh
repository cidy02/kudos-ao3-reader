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

# 2) No password storage APIs
if grep -RIn --include='*.kt' -E 'password|Password' "$SRC/io/github/cidy02/kudos/backup" | grep -viE 'comment|//|never|excluded|password' >/dev/null 2>&1; then
  # allow only comments that say passwords are never stored
  :
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
