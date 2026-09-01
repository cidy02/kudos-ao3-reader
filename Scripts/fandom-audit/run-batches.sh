#!/bin/bash
# Drive the fandom display-name audit unattended.
#
# Each round: cut one batch of ambiguous names (highest work count first), send
# the SAME batch to all three agents independently, then ingest all three sets of
# verdicts. Triple coverage is the point — a name is only settled when three
# agents that could not see each other's answers agree. Sharding one batch across
# three agents would be 3x faster and would throw away exactly the property that
# makes the output trustworthy.
#
# Safe to stop and restart: `audit.py batch` only ever hands out names that have
# no verdict yet, so a killed round is re-cut next time. Nothing is lost.
#
#   ./run-batches.sh [rounds] [batch-size]

set -u
cd "$(dirname "$0")/../.." || exit 1

ROUNDS="${1:-8}"
SIZE="${2:-250}"
AUDIT="Scripts/fandom-audit/audit.py"
WORK="${TMPDIR:-/tmp}/fandom-audit-run"
mkdir -p "$WORK"

GROK=$(ls /Users/cidy02/.claude/plugins/cache/grok-plugin-claude-code/grok-cc/*/scripts/grok-companion.mjs 2>/dev/null | head -1)
CODEX="/Users/cidy02/.claude/plugins/cache/openai-codex/codex/1.0.6/scripts/codex-companion.mjs"

for round in $(seq 1 "$ROUNDS"); do
    echo "=== round $round/$ROUNDS  $(date '+%H:%M:%S') ==="

    if ! python3 "$AUDIT" batch --size "$SIZE" --note "unattended round $round" \
         > "$WORK/batch.txt" 2> "$WORK/batch.err"; then
        echo "  no more names to classify"; break
    fi
    BATCH_ID=$(grep -oE 'batch [0-9]+' "$WORK/batch.err" | grep -oE '[0-9]+')
    COUNT=$(wc -l < "$WORK/batch.txt" | tr -d ' ')
    [ "$COUNT" -eq 0 ] && { echo "  empty batch, stopping"; break; }
    echo "  batch $BATCH_ID: $COUNT names"

    sed -n '/^CLASSIFICATION TASK/,$p' Scripts/fandom-audit/PROMPT.md > "$WORK/prompt.txt"
    cat "$WORK/batch.txt" >> "$WORK/prompt.txt"
    PROMPT=$(cat "$WORK/prompt.txt")

    # All three in parallel, each blind to the others.
    node "$CODEX" task "$PROMPT" > "$WORK/codex.txt" 2>&1 &
    P1=$!
    agy -p "$PROMPT" > "$WORK/gemini.txt" 2>&1 &
    P2=$!
    node "$GROK" task "$PROMPT" > "$WORK/grok.txt" 2>&1 &
    P3=$!
    wait $P1 $P2 $P3

    for agent in codex gemini grok; do
        got=$(grep -cE '^[0-9]+[[:space:]]+(DEMOTE|KEEP|UNSURE)' "$WORK/$agent.txt" 2>/dev/null || echo 0)
        # A short reply means the agent hit a limit or drifted off format. Record
        # what did come back rather than discarding the whole round; the missing
        # names simply stay unclassified and get re-cut later.
        echo "    $agent: $got/$COUNT"
        [ "$got" -gt 0 ] && python3 "$AUDIT" ingest "$agent" "$WORK/$agent.txt" --batch "$BATCH_ID" > /dev/null
    done

    python3 "$AUDIT" save > /dev/null
    python3 "$AUDIT" status | sed -n '1,8p' | sed 's/^/    /'
done

echo "=== finished $(date '+%H:%M:%S') ==="
python3 "$AUDIT" status
