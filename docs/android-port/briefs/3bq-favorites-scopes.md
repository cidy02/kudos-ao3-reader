# Brief 3bq: Favorites has scopes: Works, Authors, Fandoms, Tags (1ak, 1bc, 1bd)

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room schema. Your sandbox
can't run Gradle or Xcode. Claude builds, tests and commits afterwards, so make what you write
compile by reading the real symbols you use, and say which claims need a test run.

**Android only.** iOS is the reference: read it at `/Users/cidy02/kudos-ios-polish/`, change
nothing there. **When this brief and iOS's code disagree, iOS's code wins**; say so in the
result. Decide questions about demo fixtures, test data, file placement and naming yourself and
list them under "Decided without asking". Do not stop for a question: decide it the more
sparing way (fewer reads, nothing sent that iOS does not send), write it under "Open
questions", and keep going to the end. Write `docs/android-port/briefs/3bq-result.md` as you go.

**Standing rules from the owner and from earlier landings** (each cost a fix; follow them):
- A read AO3 will refuse is not made, and a "best-effort" read remembers that it was
  attempted, not only that it succeeded (owner, 2026-10-07).
- A screen reads what it draws from its collected state (`val state by x.collectAsState()`
  then `state.names`), never from a function that reads a flow's `.value`: the second does
  not redraw when the value changes (3bh).
- A screen that takes another's place inside one route gets the shell's top row back by
  itself; give it `ProvidePushedShellChrome` and nothing else.
- In tests: do not assert `hasVisualOverflow` on a short label (assert `!didOverflowHeight`
  and that the last line is not ellipsized); when several values share a panel, count the
  matches or match by the row; an API marked experimental needs its `@OptIn`; Compose tests
  need a tall window for lazy lists, patient waits and `@GraphicsMode(NATIVE)`.
- A brief's file name must not contain the word "prompt" (`.gitignore`).
- A list of rows is lazy, drawn with the form's own parts (`writingSuggestionPanel`, the
  form's failure and loading rows); no stock Material `Button`, progress ring colours or
  unstyled `Text` (3bm).
- A row with a long label shows a short value as its `trailing` content, not as `value`
  (3bm: the shared row gives a long label the width and the value one letter a line).

Read first: `briefs/3u-result.md` and its fixes' results **with their landing notes** (the
Library's section lists on Android and Favorites' quick filters), `briefs/3o-result.md`
(Reading Insights: where Android already computes facts from the reading log),
`briefs/3l-result.md` (author pages) and `docs/AO3_NETWORKING_POLICY.md`.

## What is missing

Audit A8 (a string check) found that Android's Favorites lists works only. iOS's has a scope
strip, Works · Authors · Fandoms · Tags (artboards **1ak**, **1bc**, **1bd**): the last three
are aggregate rows built from the reading log, one row type for all three
(`Features/Library/FavoriteAffinityRow.swift`), fed by `ReadingAffinities` and drawn from
`Features/Library/LibrarySectionListView.swift` (`FavoriteScope`, `favoriteScopeStrip`,
`showsFavoriteScopes`). The Authors scope alone has a "Newest work" block with an UNREAD tag.

## Build

**Count the reads first.** Start the result with every request iOS makes for the Authors
scope's "Newest work" (follow `newestWork` and `authorsReady` to their source): which
address, for how many authors, when (on opening the scope, on scrolling, on refresh), what is
cached and for how long, and which rule of the networking policy allows it. If iOS reads AO3
once per favourite author without a cap the policy names, Android does **not**: build the
Authors scope without the "Newest work" block, list it under "Open questions" with the
numbers, and go on. The Fandoms and Tags scopes read nothing from AO3 on iOS; confirm that.

Then set out what iOS has, from the code: the strip (titles, order, default, where the choice
is stored); for each scope where its rows come from (`ReadingAffinities`: every input, the
ranking, the minimums, what "favourite" means for an author, a fandom and a tag), the row
(the tile and its shape per scope, the name, the log line's wording per scope, the library
line and "N unread works" / "No unread works", the star), what a tap opens, the accessibility
label and hint, the empty state of each scope, and how the quick filters (All, Rereads,
Offline, WIP) and the toolbar behave when the scope is not Works.

Then build it on Android.

- The aggregation as **pure functions over what Android already stores**, with iOS's tests
  ported by name. If iOS uses a fact Android does not record, say which and leave that line
  out rather than invent it.
- One row composable for the three scopes, as iOS has one type.
- The chosen scope is device-local in `SettingsRepository`, default as iOS.
- A tap opens what iOS opens (the author page; the Library filtered to that fandom or tag:
  find the existing route and use it).
- No schema change, no backup key, no new HTTP code.

## How it must be drawn

Layout, order and words are iOS's (1ak, 1bc, 1bd). Tokens only; the section's palette as
today. Light, Dark, Sepia and OLED; every new text with a line height; nothing clipped at
`isAccessibilityFontScale()`; lists lazy.

## Demo and tests

- The demo library must fill each scope with at least three rows, one of them with no unread
  works: extend the demo seed if needed (say what you added) without changing what other
  screens' tests count.
- Tests: the ported aggregation tests; each scope's rows and wording from a seeded library;
  the empty states; the strip only on Favorites; the quick filters' behaviour off the Works
  scope as iOS; the stored scope not in the backup; **the number of AO3 requests each scope
  makes on opening, asserted** (a client that records).
