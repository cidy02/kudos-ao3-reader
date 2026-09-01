#!/bin/bash
# Codex's review pass over the other agents' work.
#
# Backfilling a missing third verdict is already a review — it either confirms
# what Gemini and Grok agreed or contests it. But that only catches disagreement.
# It cannot catch the failure we have never measured: an exception BOTH agents
# missed the same way, which by construction looks unanimous and never reaches
# the human queue.
#
# So this runs two passes with the framing deliberately inverted:
#
#   keeps    — every agreed KEEP re-checked. These are the high-consequence calls;
#              a wrong KEEP means a real disambiguator is left shouting.
#   demotes  — a sample of agreed DEMOTEs, asked adversarially: "find the ones
#              that are really titles". Same names, opposite prior. If the two
#              agents share a blind spot, this is what surfaces it.
#
#   ./codex-audit.sh [sample-size]

set -u
cd "$(dirname "$0")/../.." || exit 1

SAMPLE="${1:-200}"
WORK="${TMPDIR:-/tmp}/fandom-audit-codex"
CODEX="/Users/cidy02/.claude/plugins/cache/openai-codex/codex/1.0.6/scripts/codex-companion.mjs"
mkdir -p "$WORK"

python3 - "$SAMPLE" > "$WORK/keeps.txt" <<'PY'
import sqlite3, sys
db = sqlite3.connect("Scripts/fandom-audit/fandom-audit.sqlite")
rows = db.execute("""
    SELECT f.primary_name FROM fandom f JOIN verdict v ON v.name = f.name
    GROUP BY f.name HAVING count(DISTINCT v.decision) = 1 AND max(v.decision) = 'KEEP'
    ORDER BY f.work_count DESC""").fetchall()
for i, (name,) in enumerate(rows, 1):
    print(f"{i}\t{name}")
PY

python3 - "$SAMPLE" > "$WORK/demotes.txt" <<'PY'
import sqlite3, sys
size = int(sys.argv[1])
db = sqlite3.connect("Scripts/fandom-audit/fandom-audit.sqlite")
# Highest exposure first — a shared blind spot matters most where readers look.
rows = db.execute("""
    SELECT f.primary_name FROM fandom f JOIN verdict v ON v.name = f.name
    GROUP BY f.name HAVING count(DISTINCT v.decision) = 1 AND max(v.decision) = 'DEMOTE'
    ORDER BY f.work_count DESC LIMIT ?""", (size,)).fetchall()
for i, (name,) in enumerate(rows, 1):
    print(f"{i}\t{name}")
PY

echo "== pass 1: re-check every agreed KEEP ($(wc -l < "$WORK/keeps.txt" | tr -d ' ') names) =="
{
cat <<'EOF'
REVIEW PASS. Two other agents agreed each of these is a KEEP: the text after the
last spaced dash is part of the work's REAL TITLE, not a disambiguator, so the UI
should render the whole name at full strength.

You are checking their work. SEARCH THE WEB — do not answer from memory.

Mark AGREE if the tail really is part of the title.
Mark WRONG if it is actually a disambiguator (author, creator, studio, medium,
year, language) and the other two got it wrong.

OUTPUT — one line each, nothing else:
<number><TAB>AGREE|WRONG<TAB><short reason, max 10 words>

INPUT:
EOF
cat "$WORK/keeps.txt"
} > "$WORK/keeps.prompt"
node "$CODEX" task "$(cat "$WORK/keeps.prompt")" > "$WORK/keeps.out" 2>&1
echo "  WRONG calls found: $(grep -cE '^[0-9]+[[:space:]]+WRONG' "$WORK/keeps.out" 2>/dev/null || true)"
grep -E '^[0-9]+[[:space:]]+WRONG' "$WORK/keeps.out" 2>/dev/null | head -20

echo
echo "== pass 2: adversarial sweep of agreed DEMOTEs ($(wc -l < "$WORK/demotes.txt" | tr -d ' ') names) =="
{
cat <<'EOF'
ADVERSARIAL REVIEW. Two other agents agreed each of these is a DEMOTE: the text
after the last spaced dash is a disambiguator (author, creator, studio, medium,
year), so the UI renders it small and grey.

Your job is to find the ones they got WRONG — where that text is really part of
the work's title and should not be greyed. Assume they made mistakes and look for
them. SEARCH THE WEB; do not answer from memory.

Examples of what a mistake looks like:
  "InuYasha - A Feudal Fairy Tale"   -> "A Feudal Fairy Tale" is the real subtitle
  "Dragon Age: Origins - Awakening"  -> "Awakening" is the expansion's actual name

Most of these will be correct. Say so. But find every one that is not.

OUTPUT — one line each, nothing else:
<number><TAB>AGREE|WRONG<TAB><short reason, max 10 words>

INPUT:
EOF
cat "$WORK/demotes.txt"
} > "$WORK/demotes.prompt"
node "$CODEX" task "$(cat "$WORK/demotes.prompt")" > "$WORK/demotes.out" 2>&1
WRONG=$(grep -cE '^[0-9]+[[:space:]]+WRONG' "$WORK/demotes.out" 2>/dev/null || true)
echo "  missed exceptions found: $WRONG"
grep -E '^[0-9]+[[:space:]]+WRONG' "$WORK/demotes.out" 2>/dev/null | head -30

echo
echo "Anything marked WRONG is a candidate for the human queue, not an automatic"
echo "change: it is one agent against two. Raw output in $WORK."
