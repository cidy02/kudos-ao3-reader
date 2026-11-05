#!/bin/sh
# Injected into every Antigravity (agy/Gemini) session opened in this repo.
#
# Delivers two things: the Kudos house rules below, and every *.md in
# .agents/rules/. agy only auto-discovers AGENTS.md / GEMINI.md reliably —
# .agents/rules/*.md was observed on disk but absent from session context —
# so this hook delivers them instead of relying on that discovery.
# Drop a new .md in rules/ and it is injected from the next session on.
#
# Also logs the transcript path, so a future PreToolUse guard can be built
# against agy's real tool names rather than guessed ones.
payload=$(cat)
printf '%s' "$payload" | /usr/bin/grep -o '"transcriptPath":"[^"]*"' >> /tmp/agy-transcripts.log 2>/dev/null

HOUSE='Kudos house rules (each one exists because an agent broke it):
1. NEVER delete a branch on dynamicTypeSize.isAccessibilitySize, or any other accessibility special case. It is there because the ordinary layout was tried first and failed at large text sizes, and the comment above it usually says how. Replacing it with the modern native way re-creates that bug. If you believe one is redundant, say so in your handback and LEAVE THE CODE ALONE.
2. A test must prove a human can reach the content, not that a modifier is present. Asserting that safeAreaInset exists proves nothing.
3. Run /Users/cidy02/kudos-redesign-work/build-check.sh <your worktree> before handing back, and never write BUILD OK unless you saw it print that. Never run xcodebuild yourself. It COMPILES ONLY — it does not run the tests, so BUILD OK is no evidence that a test you added passes. Say so in your handback, and make any new test depend only on what a plain test host has (no launch routes, no shot state).
4. Edit only the files your brief names. If the fix needs a file outside them, say so in the handback instead of reaching for it.
5. If a screenshot-based claim cannot be confirmed in the code, say it is unconfirmed. Do not invent a fix for it, and do not weaken a guard to make a screenshot match a mockup.
6. Say plainly what you could not verify. An honest gap is worth more than a confident wrong claim.
6b. Hand back facts, not prose: what you changed (file:line), what you left alone and why, what you could not verify. No restating the brief. Evidence (quotes, line numbers) is never waffle — narration is.
7. You have the context7 MCP tools. Before relying on how a SwiftUI API behaves, look it up — guessing has cost this project real build cycles (.controlSize does nothing to a segmented Picker on iOS).'

# Where this worktree actually is, so a fresh session starts oriented instead of
# asking. Cheap, and the orchestrator no longer has to put it in every brief.
STATE=$(
  b=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0
  t=$(git log --oneline -1 2>/dev/null)
  d=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  printf 'Where this worktree is right now:\n- branch: %s\n- tip: %s\n- uncommitted files: %s\n- recent: %s' \
    "$b" "$t" "$d" "$(git log --oneline -4 2>/dev/null | tail -3 | tr '\n' ';')"
)

export HOUSE STATE
python3 -c '
import json, os, glob
parts = [os.environ["HOUSE"]]
state = os.environ.get("STATE", "").strip()
if state:
    parts.append(state)
for f in sorted(glob.glob("rules/*.md")):
    try:
        t = open(f, encoding="utf-8").read().strip()
    except Exception:
        continue
    if t:
        parts.append(t)
msg = "\n\n".join(parts)
print(json.dumps({"injectSteps": [{"systemMessage": {"systemMessage": msg}}]}))
' 2>/dev/null || printf '{"injectSteps":[]}'
