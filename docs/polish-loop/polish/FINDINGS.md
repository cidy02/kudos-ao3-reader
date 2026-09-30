# Findings log (LOOP-v3)

| ID | Sev | Screen | Source | Finding | Status | Commit / reason |
|---|---|---|---|---|---|---|
| L3-1 | P2 | Work detail → My copy (1a) | owner | Sheet was the old Library list instead of 1a's sheet | fixed | T-296 |
| L3-2 | P3 | Library shelves (1c) | Claude | Hard-edged band where the shelf scroll view clips card shadows | fixed | T-297 |
| L3-3 | P3 | Work detail facts card (1a) | Claude | Local "Added" row on the page duplicates My copy Activity; not on 1a's card | fixed | T-298 |
| L3-4 | P3 | Reading Now section (1ad) | Claude | Opens in Detailed while 1ad draws ledger rows | rejected | Owner decision 2026-07-19 (TASKS Key Decisions): keep per-section AppStorage defaults; 1ad shows the list mode, not the default |
| L3-B2-1 | P1 | Queue select | Grok | Select All / counts / bulk actions used the whole queue while a filter was shown | fixed | T-299 |
| L3-B2-2 | P1 | Queue select | Grok | Drag with mature works hidden moved the wrong row / revealed hidden works | fixed | T-299 |
| L3-B2-3 | P2 | Queue page | Grok | Inline list/grid picker in In line header (1h build note moved it to …) | fixed | T-299 |
| L3-B2-4 | P2 | Queue select (grid) | Grok | Select in grid had no numbered rows | fixed | T-299 |
| L3-B2-5 | P2 | Queue page (grid) | Grok | Up next row could not be removed | fixed | T-299 |
| L3-B2-6 | P2 | Queue select + app-wide | Grok | Selection checks/outlines in fixed red (Color.accentColor) | fixed | T-299 (swept 9 files) |
| L3-B2-7 | P2 | Queue details | Grok | Order/copy differ from 1h.3/1h.4 | deferred → Codex | |
| L3-B2-8 | P2 | Tag manager | Grok | Row menu (Show only, Copy to queue) per 1bh missing | deferred → Codex | |
| L3-B2-9 | P2 | + Tag / Edit tag sheets | Grok | No detent/grabber | fixed | T-299 (Done-only kept: live-apply sheet) |
| L3-B2-10 | P2 | + Tag chip | Grok | ~16pt tap target | fixed (+ Tag) | T-299; adjacent chips unsure, left |
| L3-B2-11 | P2 | Organizer | Grok | Rename swipe blue | rejected | semantic colour, like blue Download |
| L3-B2-12 | P2 | Queue page | Grok | Failed pull-to-refresh is silent | deferred → Codex | app-wide pattern (sections too) |
| L3-B2-13 | P3 | New queue | Grok | Copy differs from 1j | fixed (2 of 4) | T-299; colour footnote kept (honest when unset), "one word" kept |
| L3-B2-14 | P3 | Card grids | Grok | 16/16 gaps vs 1h 12/14 | fixed app-wide | T-299 |
| L3-B2-15 | P3 | Organizer strip | Grok | 5pt strip, hidden from VoiceOver | deferred | |
| L3-B2-16 | P3 | Queue select bar | Grok | "Remove from Queue" vs "Remove" | rejected | owner 3-11 |
| L3-B5-8 | P3 | Bookmarks | Grok | "are recs" / "are with notes" empty copy | fixed | T-300 |
| L3-B5-9 | P2 | Bookmarks (all AO3 lists) | Grok | Adult remote rows not gated by Hide Mature | owner decision #4 | app-wide scope question |
| L3-B5-10 | P2 | AO3 History | Grok | Opens compact; swipe says "Delete" | rejected | owner SHORT-R5 (compact default) + 6-13 (short swipe labels) |
| L3-B5-13 | P3 | Named subscriptions | Grok | ProgressView loading | rejected | same as pass2-22: names, not works |
| L3-B5-16 | P2 | Inbox filter sheet | Grok | No detent/grabber; tap-to-apply | fixed (chrome) | T-300; tap-to-apply kept (each row is one choice) |
| L3-B5-17 | P2 | AO3 Dashboard | Grok | Fandom chips without counts | fixed | T-300 |
| L3-B5-1,2,3,4,5,6,7,11,12,14,15,18,19,20 | P2/P3 | Account hub, Bookmarks card, History subtitle, Subscriptions layout, Inbox chrome/strip, Dashboard cards | Grok | spec-layout rebuilds | queued → Codex | batch-L3-5-grok.md |
| L3-B4-1 | P2 | Browse (1g), offline | Claude | A failed load replaces the whole page, hiding the local Jump Back In section; message was raw NSURLError text | message fixed (T-300); layout open | |
| L3-B9-1 | P1 | Local collection page | Claude | Pre-redesign screen: bar title, no wash, white cards, red + | fixed | T-302 |
| L3-B9-2 | P2 | Collection cards (1c) | Claude | 1c draws a neutral panel with a 2×2 grid of mini work covers (each work's hue, title, author); app draws a fanned stack; New collection card lacks 1c's 34px round +; 15px/12px captions | queued → Codex | |
| L3-B9-3 | P3 | Collections See All | Claude | Bar title only (pass2-17) | fixed | T-308 |
| L3-B10-1 | P3 | Settings pages | Claude | Form rows regular weight and taller than 1m/Settings artboard (15pt medium, 11pt padding) | fixed (hub) | 0c183944; rest → L3-FORM-1 |
| L3-B11-1 | P3 | Reader | Claude | With no publisher CSS, headings render in Readium serif while body follows the chosen font | open | verify with a real AO3 EPUB |
| L3-AX-1 | P1 | App-wide (AX5) | Claude | Shared chips/strips/tags/pills/facts use fixed sizes; headers scale — lopsided at accessibility sizes | fixed | T-311 |
| L3-AX-2 | P1 | Library shelf card (AX5) | Claude | Cover card clips its icon grid at AX sizes | fixed (T-311) | residual P3: Gen ☉ glyph overflows its tile at AX sizes |
| L3-AX-3 | P2 | Works ledger (AX5) | Claude | Title/byline truncate to "Two Voices at…"/"by Av…Sec…" | fixed | T-311 + L3-AX-4 (96fcdc3c) |
| L3-TH-1 | P1 | Dark/OLED | Claude | Selected tab and system-tinted controls in #990000 on near-black | fixed | T-307 |
| L3-B1-1 | P3 | Recently Updated (1ae) | Claude | Tally "newest check first" vs spec "newest update first" | rejected | list sorts by lastUpdateCheck; the spec wording would claim an order it does not have |
| L3-B1-2 | P2 | Home section lists (1ad/1ae) | Claude | No quick-filter pills (spec All / Unread / Offline); Library sections have them | queued → Codex task 7 | |

## L3-B7-1 (P2, fixed T-309) — Account/author Series list drew one white full-width panel
`AO3AuthorSeriesSection` hung `.navigationDestination` (Edit/Reorder, T-289) on its `Section`; the
Section folded into a single plain row — no cards, default insets, grey below. Destinations moved
onto the header, inside `.listRowInsets`, since destinations outside it also pushed the header in 16pt.
Screen-verify on the same pattern elsewhere (a non-row modifier on a `Section`):
WritingTagsEditor.swift:138 `.task` (B7 Edit Tags), ReaderSpeechSettingsSection.swift:247/:321
`.confirmationDialog` (B11), PairingSheet.swift:133 `.onAppear` (B10). WorksScopeAndSort:87 renders fine.
Dead code: AccountView.swift:789 `profileSeriesSections` has no caller.

## Codex T-310 (collection cards 1c) — accepted with fix
Hard-coded dark-only rgba on the New collection tile → glass tokens. Open P3: 2-line titles in the
2×2 mosaic break mid-word at 164pt ("Unanswere/d").

## Codex task 6 (Dynamic Type sweep, L3-AX-1/2/3) — accepted with fixes (T-311)
Rejected: capping WorkLedgerRow titles at 3 lines at AX sizes (reverses the "never truncate
enlarged text" rule). Added: the progress ring facing the icon tray scales with it
(`WorkStatusTrayMatched`); the resume card's ring (≤72) and play button (≤56) are capped.
Open L3-AX-4 (P2): Reading Now detailed card truncates title and byline to one line at AX XXXL.
Open P3: work-detail stat strip labels truncate ("WARNIN…") at AX sizes.
Harness: `-UIPreferredContentSizeCategoryName` launch arg does not take effect; use
`xcrun simctl ui <sim> content_size accessibility-extra-extra-extra-large` (reset to `large`).
Gate: `-only-testing` takes the struct name, not the file name. The signal is the Swift Testing "✔ Test run with N tests" line; the XCTest "Executed 0 tests" line is always 0.

## T-314 Home Recently Updated pills (1ae) — fixed
`HomeUpdatePill` All · Unread (`hasUpdate`) · Offline (`hasReadableEPUB`), counted over the Filter
panel's result; an empty pill shows "No offline works" + Show All. Open P3 (L3-B1-7): 1ad's Reading Now
rail is All · Offline · WIP; Home and Library Reading Now show All · WIP only.

## B5 account follow-ups (19:05)
- T-315 hub header/rows, T-316 dashboard compact cards, T-317 list chrome on empty/failed + 1p group names — fixed.
- L3-B5-20 (P2): sparse AO3 rows (Subscriptions, Marked for Later before enrichment) print "0 words · 0 comments ·
  0 kudos · 0 bookmarks · 0 hits" for stats AO3's list page never gave — reads as real zeros. Unknown ≠ 0.
- L3-B5-21 (P3): Marked for Later's group header sits ~4pt under the pill rail; Subscriptions has ~40pt.
- Row 12 layout (single rail, cover grid) → OWNER-DECISIONS #5.
- T-318 (P1, fixed): Inbox opened from the hub never loaded (model activated only via the Activity tab).
  Also Replied on the byline, row padding inside the card, pagination pill floats.
- Grok B5 row 14 (inbox toolbar as four glass circles) — deferred P3: the app's other pushed lists use the
  same system-grouped glass capsule for filter+select; changing only Inbox would be the inconsistency.
- Grok B5 row 15 remainder (visible "Mark read" beside Reply) — deferred P3; the swipe and "…" carry it.

## B9 audit (19:27)
- L3-B9-1 (P2, fixed T-319): Reading Insights' period segmented control crammed in the header → "…" menu (1bi).
- L3-B9-2 (P3): Recently Deleted's Select is a text pill; other lists use the checklist icon.
- L3-B9-3 (P3): Most-read fandoms lists "Doctor Who" and "Doctor Who (2005)" as two rows — AO3 fandom variants not merged.
- L3-B10-1 (fixed 0c183944): Settings hub rows ~52 → ~42pt (List min row height), header gaps restored explicitly.
- L3-FORM-1 (P2, in progress — fixed: SettingsHub, WorkEdit, EditTags, WritingChapters; B6/B8 screens folded
  into Codex task 5; left: SeriesEdit, AddChapter, EditMultipleWorks): the same List min-row-height inflation on every `panelSegment` form without
  `.environment(\.defaultMinListRowHeight, 0)`: CollectionModeration, CollectionMaintainers, ChallengeSignUps,
  ChallengeSettings(+Edit), NewCollectionSheet, AO3CollectionDetail, EditMultipleWorks,
  SeriesEdit, EditTags, WorkEdit, WritingChapters, AddChapter. Not fixed globally in `cardList()`: headers
  on the hub relied on the minimum for their gaps, so each screen needs a before/after screenshot.
  Do per screen as routes/fixtures exist (B6/B7/B8).
- L3-B4-1 (P2, fixed T-321 c13a0be9): Browse Jump Back In showed "Doctor Who" twice (2005 + classic tags both bare).
  `FandomDisplayName.bareTitle(_:among:)` keeps the qualifier on collision; card row equal height.
- L3-B4-2 (P3): Browse's failed-load icon is wifi.slash even when the message is "couldn't be found".
- L3-B9-3 → no change: Insights prints full tag names, so the two Doctor Who rows are already distinguishable.
- Harness: /media, /media/<x>/fandoms, /tags/<x>/works, /works/search now served (ao3_media*, ao3_author_works).
- L3-B4-3 (P2, fixed T-322): Search results hero 26pt right of the cards (double insets); stray dot after the
  subtitle when the sort control wrapped (same dot seen on Insights before T-319).
- L3-B4-4 (P3): results stat strip shows "0 FILTERS" and "1 PAGE" beside the pager's own "Page 1 / 3" — check 1k's cells.
- L3-B7-2 (RETRACTED 20:44 — fixture gap: the works come from /series/<id>/manage, which the harness does not serve; not an app bug. Add a manage fixture later.) Series Edit opened from the series list's Edit swipe gets no works (only the series page
  passes them): subtitle "3 works" but "Reorder works 0", "rewrites the position of the 0 works", "leaves the 0
  works posted". Load the works in SeriesEditDestination, or fall back to series.workCount in the copy.
- Task 5: agy Opus (quota out after ~20 min) wrote 10 fixtures + min-row-height on 11 B6/B8 screens (unverified,
  held uncommitted in the lane) — no header padding, no failure-page fix, no routes/tests. Claude routed fixtures.
- L3-TH-2 (P1 a11y, fixed T-323): prominent buttons on Dark/OLED put white text on the lifted accent (~2.8:1);
  threshold 0.45 → WCAG crossover 0.179, `prominentLabel()` on the nine prominent buttons, chip + banner too.
- L3-B1-8 (P2, FIXED T-324 491e46c6 — Codex: sheet presentation + AO3 shell): Library filter panel vs AO3 filter panel (1an). Group labels now match.
  Open: Library's has no "Filters" title bar / Reset + Done circles (keeps a bottom Reset row) and opens at
  full height. A NavigationStack inside its `.inspector` merged the bar into the host screen instead of the
  sheet — moving it to `filterPanelPresentation` (the AO3 panel's sheet) is the fix; 5 call sites.
- T-325 (aab3aa25): L3-B4-2 fixed (failure symbol per error kind); mosaic mid-word break fixed; L3-AX-2 residual fixed
  (root cause: AppleSymbols glyphs used `.custom(_:size:)`, which scales with Dynamic Type on top of an
  already-scaled size → `fixedSize:`).
- L3-B1-7 → REJECTED: Reading Now only lists works with the EPUB on disk (`isInProgress` requires hasEPUB), so
  an Offline pill always equals All. Kept the existing note in LibraryFilters.swift. Candidate owner note only.
