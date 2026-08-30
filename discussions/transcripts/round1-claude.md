CLAUDE — ROUND 1 PLAN

## 1. Findings A–E

Take A, B, C, E. Skip D for now. Order inside the existing once-only loop matters
because the forms nest; the rule is "outermost first".

**A. `& Related Fandoms` (80 unique).** New once-only flag, placed FIRST in the
loop — before RPF — because it sits outside everything else
(`Bridgerton (TV) & Related Fandoms`, `Percy Jackson … & Related Fandoms - All
Media Types`). Shape: case-insensitive match on `(&|and) Related Fandoms` anchored
to the end, taking the LAST occurrence so `Spirou & Fantasio & Related Fandoms`
keeps its series ampersand. Guard: nonempty stem after the trim, which also
rejects `Eason-Related Fandoms` (no space before `Related`) and
`Chinese Related Fandoms` (no `&`/`and`).

**B. `-Fandom` glued (178).** Do NOT generalise to "unspaced dash + anything" —
Grok showed `「云熠」对家总裁有点怪-办公室篇` is a chapter subtitle. Restrict to the
literal: case-insensitive terminal `-Fandom`, optional spaces, nonempty stem.
Folds into the existing dash rule as an alternate spelling rather than a new flag.

**C. Glued `RPF` (49).** Relax the existing RPF rule from `" RPF"` to terminal
`RPF` with a nonempty-stem guard, still case-insensitive. `hetamyuRPF` →
`hetamyu`. Risk is a real word ending in those three letters; none in the index.
Keep it in the same once-only flag as spaced RPF.

**E. Mixed-width brackets (16–23).** Cheapest correct fix: don't pair open with
close. Accept a terminal `)` OR `）`, then search back for the LAST `(` or `（`,
whichever is nearer the end. Add the negative guard Grok found: refuse when the
character before the opener makes it a smiley (`:)`, `:(`), and refuse
`Sunn O)))` — both fall out of requiring the opener to exist and the stem to be
nonempty and not end in `:`.

**D. Localized "All Media Types" (8–21).** Skip. It is a translated-phrase map
that will rot as AO3 adds languages, for ~15 rows. Revisit only if a CJK-reading
user asks.

## 2. Sibling collision (J) — the design question

**Do nothing in the parser. This is a rendering decision and the right answer is
to leave it alone.**

The temptation is to detect collisions at render time and keep the qualifier at
full strength when a stem is ambiguous. I would not, for three reasons:

- It needs the whole category list in scope to know a stem is ambiguous. That is
  a per-list computation over up to 14,158 rows feeding a per-row style — exactly
  the class of work that caused the scroll-lag problem this file already carries
  scars from.
- It makes the row's appearance depend on what else is in the list, so the same
  fandom renders differently in Browse vs search results. That is worse than a
  consistent quiet qualifier.
- The qualifier is still legible. It is smaller and grey, not hidden. A reader
  scanning 23 Les Misérables rows still sees `(1933)` / `(2012)` / `(Dallas 2014)`
  — they are simply not shouting.

If it turns out to matter in practice, the cheap fix is not collision detection:
it is raising the qualifier's contrast globally (`.secondary` is already fairly
light) — one token change, no new state, no list-wide scan.

## 3. Data quality (F–I)

**Out of scope for this change, but F and G are real bugs worth filing.**

F (`Navigation and Actions`, 21 rows) and G (raw HTML, 2 rows) mean the
fandom-index scraper is capturing page chrome. That belongs in `AO3Client`'s
fandom parsing, not in a display helper — fixing it here would be papering over
a scrape bug at the last possible moment, and the bad rows would still be in the
cache, in search, and in the works query.

H (HTML entities, 9 rows) is the one arguable inclusion: `&lt; - Fandom` should
display as `< - Fandom`. But unescaping belongs at ingestion for the same reason,
and doing it in `split` would mean the displayed title no longer matches the
identity string.

I (invisible controls, 14 rows) — leave. Blanket stripping breaks legitimate bidi
and ZWJ sequences. The only genuinely broken row is the visually-blank one, which
is one row.

Recommendation: one follow-up task against the scraper for F/G/H together.

## 4. Where the parsing lives

**Leave it in the view, but hoist the call.** `split` is pure and cheap — a few
`range(of:)` scans over a short string — and it only runs for realised rows, so
it is not the scroll-lag cause. The measured suspects there were variable row
heights and the per-row shadow, neither of which this touches.

What I would change: `FandomListRow` currently calls `split` inside a computed
property that the body reads, so it runs on every body evaluation of a visible
row rather than once per row. Compute it once in the row's initialiser and store
it. That is a two-line change with no behavioural risk.

I would NOT precompute the whole 14k list at load time. That trades a real
startup cost for a saving on ~10 visible rows.

## 5. Testing and definition of done

- Extend `FandomDisplayNameTests` with the real strings from section 5.1 for
  each rule taken, plus the negative guards: `Spirou & Fantasio & Related
  Fandoms`, `Eason-Related Fandoms`, `Sunn O)))`, `MYSTERIOUS MURDER DIY :)`,
  `f(x) (Band)`, `Ellie and Abbie (and Ellie's Dead Aunt) (2020)`.
- Re-run the full-catalog validation offline before committing and record the
  numbers: qualifier coverage, empty titles (must stay 0), titles still ending in
  a separator, titles still containing a suffix word.
- Done = tests green, lint clean on touched files, full-catalog numbers recorded
  in the commit body, and a visual check on the simulator that the fandom list
  still reads correctly.

## 6. What I would NOT do

- **No manual exception list.** Codex verified no general rule exists for the
  dash residual and put it at ~1 name in 2,000. A list nobody can enumerate is
  worse than a known cosmetic imperfection.
- **No square-bracket rule.** `Civil War [2016]` argues for, `[ミラージュ]`
  furigana argues against, and the counts are tiny.
- **No fullwidth `｜` alias split.** 330 rows, but `[雨成｜R]易感` wraps in it.
- **No trailing-year rule.** `Blade Runner 2049`.
- **No RPS rule.** Catches `LiamCarps`.
- **No change to the en/em dash separators.** Measured net-positive already.

Confidence: high on A/B/C/E and on the scope-outs; high on leaving J alone,
though that is the one I would most want a second opinion on, because it is a
judgement about reading behaviour rather than a measurement.

Would want measured before committing: whether relaxing RPF to unspaced (C)
changes any row other than the 49 intended — a full-catalog diff of old vs new
output, not just a count.
