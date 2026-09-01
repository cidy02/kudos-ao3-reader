#!/bin/bash
# Keep the audit running without needing anyone to check on it.
#
# The runner can die — a crashed agent CLI, a killed subshell, a machine that
# slept. Supervision that depends on someone being awake to notice is
# supervision that stops when they are not. This does not: it restarts the
# runner, records progress every few minutes, and stops on its own when every
# ambiguous name has three verdicts.
#
# Only one may run at a time; a second exits immediately rather than racing the
# first and double-sending batches to the agents.
#
#   ./watchdog.sh &

set -u
cd "$(dirname "$0")/../.." || exit 1

AUDIT="Scripts/fandom-audit/audit.py"
LOG="Scripts/fandom-audit/watchdog.log"
LOCK="${TMPDIR:-/tmp}/fandom-audit-watchdog.lock"

if ! mkdir "$LOCK" 2>/dev/null; then
    echo "watchdog already running (lock $LOCK); exiting" >&2
    exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

say() { echo "$(date '+%m-%d %H:%M') $*" >> "$LOG"; }

say "watchdog up"
stalled=0
last_total=-1

while true; do
    # 1. Runner alive? A bare `pgrep -f run-agents.sh` also matches the script's
    #    own parallel agent subshells, so count only the parent (PPID 1).
    parent=$(pgrep -f "run-agents.sh" 2>/dev/null | while read -r pid; do
        [ "$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')" = "1" ] && echo "$pid"
    done | head -1)

    if [ -z "$parent" ]; then
        say "runner down — restarting"
        nohup ./Scripts/fandom-audit/run-agents.sh 200 250 0400 \
            >> Scripts/fandom-audit/runner.log 2>&1 &
        sleep 20
    fi

    # 2. Progress, and whether it has stopped.
    total=$(python3 - <<'PY'
import sqlite3
db = sqlite3.connect("Scripts/fandom-audit/fandom-audit.sqlite")
print(db.execute("SELECT count(*) FROM verdict").fetchone()[0])
PY
)
    if [ "$total" = "$last_total" ]; then
        stalled=$((stalled + 1))
        [ "$stalled" -ge 3 ] && say "no new verdicts for $stalled checks (total $total)"
    else
        stalled=0
    fi
    last_total="$total"

    # 3. Done when every ambiguous name has three verdicts.
    remaining=$(python3 - <<'PY'
import sqlite3
db = sqlite3.connect("Scripts/fandom-audit/fandom-audit.sqlite")
print(db.execute(
    "SELECT count(*) FROM fandom f WHERE f.ambiguous = 1 AND ("
    "  SELECT count(*) FROM verdict v WHERE v.name = f.name) < 3").fetchone()[0])
PY
)
    say "verdicts $total   names still short of three verdicts: $remaining"

    if [ "${remaining:-1}" -eq 0 ]; then
        say "complete — every ambiguous name has three verdicts"
        python3 "$AUDIT" save > /dev/null
        python3 "$AUDIT" export kudos-ao3-reader/Features/Search/FandomDisplayExceptions.swift >> "$LOG" 2>&1
        break
    fi

    python3 "$AUDIT" save > /dev/null
    sleep 300
done
