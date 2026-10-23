# A88 triage: the 72 A82 screens re-reviewed after the fixes (Claude, 2026-10-23)

Each half had two independent reviewers: Gemini 4 Argon on account 2 (`A88a-gemini-result.md`,
`A88b-gemini-result.md`) and Claude-CLI (`A88a-cli-result.md`, `A88b-cli-result.md`). Tiles:
`~/kudos-tools/pairs/tiles-a88/`. Of A82's 35 earlier differences, 31 are gone (16 of 17 in the first
half, 15 of 18 in the second). Gemini tended to rate more screens as matching; Claude-CLI caught finer
detail (row padding, swatch opacity, sheet grounds), and every one it raised that I checked was real.
The Android shots' four reader screens showed Home (a harness fault, fixed by `--activity-single-top`).

## Fixed
- **Android 3gz** (`46a50158`): queue tags' rows, gutter and Add row (it predates 3gx: A82's shot is
  identical); the fandom works chip and count; both works pages' wash; New collection's title at 2.0x;
  swatch opacity per theme; the formatting tray's Done; one card for the chapter picker; the page
  picker's tiles; the pronunciations icon; collection reorder handles.
- **Android 3ha** (gating): a directly opened series' card (bookmarks, Restricted, date) and zero figures,
  neutral; challenge settings' title subtitle with the sign-up count when known (no extra read, owner
  decision 16) and its pinned Save; bulk names in one row; author bookmarks neutral with a header and a
  Load More card; white sheets in Light (preference help, recovery); availability's orphan rule;
  privacy's wash; the chapter-form shot route as iOS's.
- **Android, Claude:** the pushed bar's title gives way to its buttons (the text editor's Done at 2.0x).
- **iOS T-437 … T-440** (Codex's I12, Claude-CLI's I13 … I15): Revoke and Add Works' full titles as
  headings; Add Works' bylines whole at AX5; the collections filter's Reset ground; collection items'
  creator line; the parent URL without a hyphen (I15, gating); the manage-screen shot routes at AX5.

## Decided, not changed
Android's own extra information (rule: no lost information): series remove's words · date line,
privacy's "Imported fonts" row (iOS shows it when fonts exist), Add to Queue's Series section, the
voice-engine notes on the pronunciation pages. Platform layout: Android's search field at the top of the
fandom list and library picker (iOS 26 floats it at the bottom); Add Works' Cancel/Add at the bottom.
Demo data: the iPhone recovery sheet's second paragraph, the series preserve prompt's known count, the
order of two demo collections made in the same instant.

## Capture problems, re-shot
Android (`list11-android.txt` and 3ha's nine, started warm with `android6.sh`): the reader screens and
every column that showed "isn't responding", a spinner, Home or no sheet. iPhone (`list10-ios.txt`, done):
pronunciations, pronunciation edit, and the AX5 manage screens; all opened. A88c re-reviews them.

## A88c: the re-shot screens (41 pairs)
Claude-CLI (`A88c-cli-result.md`): match 22, minor 15, differs 4. Gemini (`A88c-gemini-result.md`): match 33,
minor 6, differs 2. Every A88 difference in this set is gone or decided. Checked in the shots before
briefing:
- **Claude-CLI**: the wash seam on `tagseditor` and `collectionsgifts`. The Light page's wash fades to
  (237,230,235) at y=640 and restarts at (227,201,205) at y=680. It's been there since `531a11a9`; A88 missed it.
- **Gemini**: the iPhone's current-speed pill ("1.0x (default)") is near-white on pale glass in Light
  and Sepia.
- **Claude-CLI**: the iPhone's editor sets a title, but its buttons crowd it out of the bar (Android
  draws it cut).

Sent on:
- **Android 3hb (Codex):** the seam, ⊖, sheet cards, queue tags' Add, the editor's title, Customize
  Theme, page jump and the pager's colours, the reader sheets in Sepia, and Find/Note's opening focus.
- **Android 3hc (Gemini, account 2):** collection reorder's card, the collection form's card, New
  queue's radios, Add Works' bylines, the comments chapter picker, and "Draft". Its seventh item, the
  works pages' card dates in iOS's MM/dd/yyyy, is withdrawn: owner Q28 is open, and until it's answered
  each app keeps its own form (Claude-CLI caught it). Gemini's change for it isn't landed.
- **iOS I16 (Claude-CLI):** the Sample Text value at AX5, the current-speed pill, and the AX5
  pronunciation shot route.

Capture problems left: Android's OLED `revokedevice`, Android's Sepia `formattingtray`, and the
iPhone's AX5 `pronunciations`/`pronunciationedit` (I16). `parentpicker` is re-shot after T-440. 3ha's
nine screens are re-shot after its landing.
