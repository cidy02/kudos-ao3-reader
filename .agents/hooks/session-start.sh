#!/bin/sh
# Injected into every Antigravity (agy/Gemini) session opened in this repo.
# These rules exist because an agent broke each one. Keep it short: it is spent
# context on every session.
#
# Also records the session's transcript path, so the tool names needed for a
# future PreToolUse guard can be read from a real run instead of guessed.
payload=$(cat)
printf '%s' "$payload" | /usr/bin/grep -o '"transcriptPath":"[^"]*"' >> /tmp/agy-transcripts.log 2>/dev/null

cat <<'JSON'
{"injectSteps":[{"systemMessage":{"systemMessage":"Kudos house rules (each one exists because an agent broke it):\n1. NEVER delete a branch on dynamicTypeSize.isAccessibilitySize, or any other accessibility special case. It is there because the ordinary layout was tried first and failed at large text sizes, and the comment above it usually says how. Replacing it with the modern native way re-creates that bug. If you believe one is now redundant, say so in your handback and LEAVE THE CODE ALONE.\n2. A test must prove a human can reach the content, not that a modifier is present. Asserting that safeAreaInset exists proves nothing.\n3. Run /Users/cidy02/kudos-redesign-work/build-check.sh <your worktree> before handing back, and never write BUILD OK unless you saw it print that. Never run xcodebuild yourself.\n4. Edit only the files your brief names. If the fix needs a file outside them, say so in the handback instead of reaching for it.\n5. If a screenshot-based claim cannot be confirmed in the code, say it is unconfirmed. Do not invent a fix for it, and do not weaken a guard to make a screenshot match a mockup.\n6. Say plainly what you could not verify. An honest gap is worth more than a confident wrong claim."}}]}
JSON
