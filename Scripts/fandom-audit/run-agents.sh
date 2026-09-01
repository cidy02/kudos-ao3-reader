#!/bin/bash
# Drive the audit to completeness: every ambiguous name judged by all three agents.
#
# Each round cuts a SEPARATE batch per agent — the names that agent has not voted
# on yet — instead of one shared batch. That is what makes the run self-healing:
# when an agent is rate-limited the other two carry on, and the gap it left is
# picked up automatically when it returns, rather than leaving those names on two
# verdicts where the design calls for three.
#
# Triple coverage is the point. A name is settled when three agents that could
# not see each other's answers agree; sharding one batch three ways would be 3x
# faster and would throw away exactly that.
#
# Safe to stop and restart at any point: batches are cut from what is missing, so
# an interrupted round costs nothing but the round.
#
#   ./run-agents.sh [rounds] [batch-size] [codex-not-before-HHMM]

set -u
cd "$(dirname "$0")/../.." || exit 1

ROUNDS="${1:-100}"
SIZE="${2:-250}"
CODEX_AFTER="${3:-}"          # e.g. 0400 — Codex is rate-limited until then
AUDIT="Scripts/fandom-audit/audit.py"
WORK="${TMPDIR:-/tmp}/fandom-audit-agents"
mkdir -p "$WORK"

GROK=$(ls /Users/cidy02/.claude/plugins/cache/grok-plugin-claude-code/grok-cc/*/scripts/grok-companion.mjs 2>/dev/null | head -1)
CODEX="/Users/cidy02/.claude/plugins/cache/openai-codex/codex/1.0.6/scripts/codex-companion.mjs"

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

    case "$agent" in
        codex)  node "$CODEX" task "$prompt" > "$out" 2>&1 ;;
        gemini) agy -p "$prompt" > "$out" 2>&1 ;;
        grok)   node "$GROK" task "$prompt" > "$out" 2>&1 ;;
    esac

    local got
    got=$(grep -cE '^[0-9]+[[:space:]]+(DEMOTE|KEEP|UNSURE)' "$out" 2>/dev/null || echo 0)
    echo "    $agent: $got/$count"
    # A short reply means a limit or a format drift. Keep what came back; the rest
    # stay unassigned for this agent and are re-cut next round.
    [ "${got:-0}" -gt 0 ] && python3 "$AUDIT" ingest "$agent" "$out" --batch "$id" > /dev/null
}

for round in $(seq 1 "$ROUNDS"); do
    echo "=== round $round/$ROUNDS  $(date '+%H:%M:%S') ==="
    run_agent codex  &  P1=$!
    run_agent gemini &  P2=$!
    run_agent grok   &  P3=$!
    wait $P1 $P2 $P3

    python3 "$AUDIT" save > /dev/null
    python3 "$AUDIT" status | grep -E "classified|unanimous|split|KEEP|per-agent|under 3" | sed 's/^/    /'

    remaining=$(python3 "$AUDIT" status | awk '/under 3 verdicts/{print $4}')
    unseen=$(python3 - <<'PY'
import sqlite3
db=sqlite3.connect("Scripts/fandom-audit/fandom-audit.sqlite")
print(db.execute("SELECT count(*) FROM fandom f WHERE f.ambiguous=1 AND NOT EXISTS "
                 "(SELECT 1 FROM verdict v WHERE v.name=f.name)").fetchone()[0])
PY
)
    if [ "${unseen:-1}" -eq 0 ] && [ "${remaining:-1}" -eq 0 ]; then
        echo "=== complete: every ambiguous name has three verdicts ==="
        break
    fi
done

python3 "$AUDIT" status
