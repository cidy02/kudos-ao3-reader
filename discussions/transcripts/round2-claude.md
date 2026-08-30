CLAUDE — ROUND 2

## (3) Finding D — I concede.

I said skip it as a phrase map that would rot. Three of you include it, and Grok
measured 20 unique names, which is more than I assumed. More to the point, my
"it will rot" objection applies equally to the English literal we already ship —
`All Media Types` is the same kind of named phrase. Refusing the translated form
while keeping the English one is not scope discipline, it is just anglocentrism
with extra steps.

Take D, restricted to the forms actually observed in the index — `所有媒体类型`,
`所有媒體型別` — and no speculative translations. Codex's wording on that is right.

## (2) Where the parsing lives — I hold, but my cost argument was weak.

I claimed precomputing 14k entries "trades a real cost for a saving on ~20 rows".
Checking that: 14k splits at a few microseconds each is on the order of 20ms,
once per category open, off the main actor. That is not a real cost. I withdraw
the performance argument — it was the weakest part of my Round 1 plan and Codex
is right that it does not hold up.

I still land on keeping it in the row, for a different reason: `split` has one
consumer and no state. Introducing `FandomListEntry` means a new type, a builder,
a threading change through the filter path, and a second thing that can drift out
of sync with `filtered`. That is a real maintenance cost for a cosmetic feature,
and it only pays for itself if we also take J.

So: if J is dropped, the placement change should be dropped with it. Codex's two
positions stand or fall together, and I think they fall.

## (1) Finding J — I hold, but Codex's flicker fix is valid and I was wrong to
lean on that objection.

Counting on the full category before filtering does solve the flicker. I raised
it, Codex answered it, and I should say so plainly rather than repeat it.

What remains is not performance and not flicker. It is that mixed emphasis puts
two visual languages on one 14,000-row list: some qualifiers grey, some at full
strength, with no cue to the reader about why. On a list this long that reads as
inconsistency, not as information. And "ambiguous" is not a stable concept —
we four measured collisions at 1,110 / 6,223 / 534 / 1,446 depending on
case-folding, alias handling, and whether the count is per-category or global.
Shipping a visual rule whose trigger four careful readers could not agree on is
how you get a UI nobody can explain.

**The cheaper treatment that gets most of the benefit:** the real complaint is
that the qualifier is hard to read at `.footnote` + `.secondary`. If 23
Les Misérables rows are hard to tell apart, raise the qualifier's contrast for
EVERY row — one token, no new state, no list-wide scan, no second language. That
is one line and it is reversible after a look on device.

I would ship the parser rules now, look at Les Misérables on the phone, and only
then decide between "leave it", "raise contrast globally", and Codex's entry
model. Deciding it now, before anyone has seen it, is the part I object to.

## Factual check on another plan

Grok's correction on finding I is important and I want it carried into the doc:
**do not blanket-strip Unicode format characters.** This catalog uses U+200C ZWNJ
inside real Persian and Telugu names (`تی‌ام`, `شب‌های`) and U+200D inside emoji
sequences. Codex's Round 1 wording ("handle I conservatively — especially not
globally deleting ZWNJ") agrees. Gemini's Round 1 says to strip
`\u{200C}`/`\u{2060}` at ingestion, which would corrupt those names. Gemini
should withdraw that specific item.

## The combined plan I would ship

One commit, parser only.

Loop order, each rule once-only:
1. RPF — drop the required leading space (C)
2. `& Related Fandoms` / `and Related Fandoms` (A) — terminal, case-insensitive,
   last occurrence, leading-space guard so `Eason-Related Fandoms` is untouched
3. All Media Types, English + the two observed Chinese forms (D)
4. Trailing parenthetical, all four open/close width combinations (E)
5. Spaced dash tail (existing, unchanged)
6. Dash-attached `Fandom` (B) — after the spaced rule so `" - "` still wins

Not in this change: J, F–I, placement refactor, square brackets, fullwidth pipe,
trailing years, RPS, any exception list.

Before commit: full-catalog diff of old vs new output, not just counts — every
name whose split changes, eyeballed by category. Record coverage, empty titles
(must stay 0), and titles still ending in a separator in the commit body.

CONSENSUS: yes
