#!/bin/bash
# Drive the audit to completeness: every ambiguous name judged by every agent.
#
# Each round cuts a SEPARATE batch per agent — the names that agent has not voted
# on yet — instead of one shared batch. That is what makes the run self-healing:
# when an agent is rate-limited the other two carry on, and the gap it left is
# picked up automatically when it returns, rather than leaving those names on two
# verdicts where the design calls for three.
#
# Independent coverage is the point. A name is settled when agents that could not
# see each other's answers agree; sharding one batch across them would be faster
# and would throw away exactly that.
#
# Safe to stop and restart at any point: batches are cut from what is missing, so
# an interrupted round costs nothing but the round.
#
# Which agents run is set by AUDIT_AGENTS, so an agent that is out of quota or
# out of credit can be dropped and added back without editing this file:
#
#   AUDIT_AGENTS="gemini codex" ./run-agents.sh [rounds] [batch-size] [codex-not-before-HHMM]

set -u
cd "$(dirname "$0")/../.." || exit 1

ROUNDS="${1:-100}"
SIZE="${2:-250}"
CODEX_AFTER="${3:-}"          # e.g. 0400 — Codex is rate-limited until then
AGENTS="${AUDIT_AGENTS:-gemini grok codex}"
TIMEOUT="${AGENT_TIMEOUT:-900}"
AUDIT="Scripts/fandom-audit/audit.py"
WORK="${TMPDIR:-/tmp}/fandom-audit-agents"
mkdir -p "$WORK"

GROK=$(ls /Users/cidy02/.claude/plugins/cache/grok-plugin-claude-code/grok-cc/*/scripts/grok-companion.mjs 2>/dev/null | head -1)
CODEX="/Users/cidy02/.claude/plugins/cache/openai-codex/codex/1.0.6/scripts/codex-companion.mjs"

# Killing a round used to orphan its CLI. The agent ran inside a subshell, so $!
# was the subshell, not the node/agy process; killing the subshell left the CLI
# reparented to PID 1, still holding its memory. Hundreds of interrupted rounds
# of that exhausted the VM compressor and panicked the machine. Two fixes: start
# the CLI directly so $! is the real process, and record every pid so they can
# be reaped on timeout and on exit. Reaping walks the tree — node spawns helpers.
PIDFILE="$WORK/tracked.pids"
: > "$PIDFILE"
track() { echo "$1" >> "$PIDFILE"; }

reap() {                       # a pid and everything under it, deepest first
    local pid="$1" kid
    for kid in $(pgrep -P "$pid" 2>/dev/null); do reap "$kid"; done
    kill -TERM "$pid" 2>/dev/null
}

cleanup() {
    local pid
    while read -r pid; do
        [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && reap "$pid"
    done < "$PIDFILE"
    sleep 1
    while read -r pid; do      # anything that ignored TERM
        [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null
    done < "$PIDFILE"
}
trap cleanup EXIT INT TERM

run_agent() {                  # $1 agent
    local agent="$1" out="$WORK/$1.out" batch="$WORK/$1.batch" err="$WORK/$1.err"

    if [ "$agent" = "codex" ] && [ -n "$CODEX_AFTER" ] && [ "$(date +%H%M)" -lt "$CODEX_AFTER" ]; then
        echo "    codex: skipped (rate-limited until $CODEX_AFTER)"
        return
    fi

    python3 "$AUDIT" batch --size "$SIZE" --for-agent "$agent" \
        --note "$agent backfill" > "$batch" 2> "$err" || { echo "    $agent: nothing left"; return; }
    local id count
    id=$(grep -oE 'batch [0-9]+' "$err" | grep -oE '[0-9]+')
    count=$(wc -l < "$batch" | tr -d ' ')
    [ "${count:-0}" -eq 0 ] && { echo "    $agent: nothing left"; return; }

    { sed -n '/^CLASSIFICATION TASK/,$p' Scripts/fandom-audit/PROMPT.md; cat "$batch"; } > "$WORK/$agent.prompt"
    local prompt; prompt=$(cat "$WORK/$agent.prompt")

    # Started directly, not in a subshell, so $! is the process holding the memory.
    case "$agent" in
        codex)  node "$CODEX" task "$prompt" > "$out" 2>&1 & ;;
        gemini) agy -p "$prompt"             > "$out" 2>&1 & ;;
        grok)   node "$GROK" task "$prompt"  > "$out" 2>&1 & ;;
        *)      echo "    $agent: unknown agent"; return ;;
    esac
    local cli=$!
    track "$cli"

    # Bound the call: a hung agent used to stall its round indefinitely.
    local waited=0
    while kill -0 "$cli" 2>/dev/null && [ "$waited" -lt "$TIMEOUT" ]; do
        sleep 5
        waited=$((waited + 5))
    done
    if kill -0 "$cli" 2>/dev/null; then
        echo "    $agent: timed out after ${TIMEOUT}s — reaping"
        reap "$cli"
        sleep 2
        kill -KILL "$cli" 2>/dev/null
    fi
    wait "$cli" 2>/dev/null

    local got
    # grep -c already prints 0 on no match; only its exit status needs ignoring.
    got=$(grep -cE '^[0-9]+[[:space:]]+(DEMOTE|KEEP|UNSURE)' "$out" 2>/dev/null || true)
    got=${got:-0}
    echo "    $agent: $got/$count"
    # A short reply means a limit or a format drift. Keep what came back; the rest
    # stay unassigned for this agent and are re-cut next round.
    [ "$got" -gt 0 ] && python3 "$AUDIT" ingest "$agent" "$out" --batch "$id" > /dev/null
    return 0
}

echo "agents: $AGENTS   timeout: ${TIMEOUT}s"

for round in $(seq 1 "$ROUNDS"); do
    echo "=== round $round/$ROUNDS  $(date '+%H:%M:%S') ==="
    pids=""
    for a in $AGENTS; do
        run_agent "$a" &
        pids="$pids $!"
        track "$!"
    done
    wait $pids

    python3 "$AUDIT" save > /dev/null
    python3 "$AUDIT" status | grep -E "classified|unanimous|split|KEEP|per-agent|under 3" | sed 's/^/    /'

    # Done when no agent in AGENTS has anything left — not "three verdicts",
    # which is unreachable whenever an agent is sitting out.
    left=$(python3 - "$AGENTS" <<'PY'
import sqlite3, sys
db = sqlite3.connect("Scripts/fandom-audit/fandom-audit.sqlite")
print(sum(db.execute(
    "SELECT count(*) FROM fandom f WHERE f.ambiguous=1 AND NOT EXISTS "
    "(SELECT 1 FROM verdict v WHERE v.name=f.name AND v.agent=?)", (a,)).fetchone()[0]
    for a in sys.argv[1].split()))
PY
)
    if [ "${left:-1}" -eq 0 ]; then
        echo "=== complete: $AGENTS have voted on every ambiguous name ==="
        break
    fi
    echo "    names still owed by [$AGENTS]: $left"
done

python3 "$AUDIT" status
