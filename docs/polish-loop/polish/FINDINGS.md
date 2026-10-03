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

## Codex task 10 — B8 challenge / collection-maintainer audit (verified 2026-09-30 ~15:00)
34 rows. Claude checked each against code + artboard.
- FIXED T-326 (87e9eb81): #5 prompt section label follows filter; #6 prompt pills 34/14/12.5 + 44pt tap;
  #7 PromptTagsEditor List minimum; #13 redundant "Owner" subtitle dropped (no added-date data); #16 "Optional";
  #17 Assignments + Defaults rows disclose (Minimum words: no data, left out); #24 Save tags 44pt;
  #25 compact header count; #30 Collection items failed load → Try Again card.
  Found while verifying: L3-B8-1 (P2) 1by/1ch values were 11pt mono, spec 15pt system → fixed.
  L3-FORM-2 (P2, app-wide) SubjectFormRow split label/value 50/50, truncating values beside short labels
  ("8 matched, 4 unmat…") → label keeps natural width, value takes the rest. Regression shots: Settings, Edit
  collection, Preferences, Challenge Settings.
- QUEUED Codex task 11: #4, #9 (radius/title only), #10 (1cd supersedes 1bx), #11 (grouping only), #23, #28, #29.
- REJECTED: #1 spec copy "any chosen tag" would misdescribe AO3's any_relationship (code is truthful).
  #15 date labels follow AO3's own fields (code comments cite otwarchive). #22 "moderator" kicker is a
  documented choice: the collection owner is not necessarily the tag set's owner and the model has no owner field.
  #26 28pt rail pills are the app-wide rail convention (10 call sites); a 44pt layout-free target would overlap
  neighbours 8pt apart.
- OWNER DECISION (#7, #8 below): #2, #3, #8, #12, #18, #32 (AO3 has no endpoint/data); #14, #20, #27, #31 (top
  check-circle confirm vs bottom Save bar); #19, #21, #33, #34 (form structure).
- T-327 (integrate ada6e2fc): Codex task 11 landed (#4, #9, #10, #11, #23, #28, #29) after review. Claude additions:
  - L3-B8-2 (P1, FIXED): "Recently decided" (Moderation) and "Prompts" (Prompt Meme settings) were dead —
    `SubjectFormRow(label:value:…) { EmptyView() }` binds the trailing closure to `action:`, making the row a
    no-op Button over its navigation link. Found by AXe tap. Warning comment on the init.
  - L3-TH-3 (P1 a11y, FIXED): 9 filled confirm buttons (challenge screens, Tag set, fandom filter "Show N tags")
    used `accentOnFill` (for the 24%-alpha fill) on a SOLID accent — near-white on light cyan in Dark.
    New `Palette.labelOnAccent` (WCAG crossover, as T-323).
  - L3-B8-3 (P2, FIXED): 1s approval as a cramped 180pt 3-way segmented control → 1s status chip + Menu, 44pt tap.
  - L3-B8-4 (P3, FIXED): assignment due line mono → 11.5pt system tabular (1cb).
  - Tag-set editor sub-screen given the SubjectHeaderBlock chrome (Codex used a bare navigationTitle).
  - Kicker variety across challenge screens (collection title vs "AO3 Account") matches each artboard → not a finding.
- L3-FORM-3 (P2, FIXED 6cda4ea9): regression from T-326 — SubjectFormRow with no value (EmptyView trailing) hugged its
  label (Tag set link panel shrank). Zero-minimum Spacer; re-shot Challenge Settings, Edit collection, Settings.
- L3-B8-5 (P3, OPEN, unverifiable offline): Tag set counts parse from h3/h4 headings; the edit-page fixture has none,
  so counts read 0 while the fields hold tags. Check against a real AO3 tag-set edit page before trusting the counts.
- Tag set (1ch) + "Add tags" editor screenshotted via Challenge Settings → tag set (profile route) — match.

## Codex task 12 — queue sheets, comments, fandom list, save search, AO3 History, author, series (verified ~16:20)
27 rows.
- FIXED T-328 (integrate eab554df): #20 (P1) author Works layout picker did nothing — Works, Series and Dashboard
  cards now follow Ledger/Detailed; picker drops Compact on these List pages; default Ledger (#21). #15 Save Search
  detents + grabber. #18 "Delete from history". #26 one "See all" per Dashboard section.
- QUEUED Codex task 13: #3, #4, #5, #6, #7, #9, #12, #13, #16, #22, #24, #25 + verify unknown-stat zeros on the
  Detailed card (seen on Dashboard, Detailed mode).
- LATER (task 14 candidates): #10 fandom A–Z index, #11 fandom row star/download indicators (spec'd, need plumbing).
- REJECTED: #2, #14, #19, #23 — 28pt rail/tag hit targets are a documented choice (MinimumHitTarget.swift:
  "a smaller floor … for a control deliberately boxed tightly against other small controls"). #8 comments CTA
  label is dark on the light accent in Dark (contrast fine; matches spec's #16192e on #A3B2EC).
  #27 1az is the empty own-Series state, not series detail (INVENTORY mapping corrected).
- OWNER DECISION: #1 add-to-queue/collection sheet chrome (→ OD #2 group); #17 History layout (→ OD #10).
- Seen while verifying (P3, open): Detailed card's rating/warning pill row is centred, not leading.
- T-329 (integrate 375fdd49): Codex task 13 landed after review (#4, #5, #6 partly, #7, #9, #12, #13, #16, #22, #24, #25,
  Detailed-card unknown stats). Review reverted/kept: #3 Post capsule rejected (a `.confirmationAction` Button is
  already the system's filled capsule; a hand-drawn one nests inside it); thread screen kept `hidesFloatingTabBar`
  (Codex dropped it); tray kept semantic sizes for Dynamic Type (T-273; Codex hard-coded 10.5/9.5/8.5pt); empty
  Series card de-nested (subjectPanel inside cardRow). Codex hit its usage limit at 20:32Z mid-verification.
- L3-B4-5 (P3, UNVERIFIED — code already sets .accessibilityHidden on unfitted chips; AXe may list hidden elements): Browse category cards expose ~8 invisible overflow fandom chips to VoiceOver, all at one
  29×14 frame (describe-ui on `browse`). Hide chips that aren't drawn.
- L3-B4-6 (P3, OPEN): fandom family block draws an inner lighter panel inside its card (box in a box).
- L3-FORM-1 CLOSED (4ebb9acf): AddChapterView, EditMultipleWorksView.
- Claude batch (17:00, AXe): Account signed-out ✓ (prominent label black on salmon). New collection sheet: text
  Cancel/Create ✓, rows ✓. L3-B1-9 (P3, OPEN): `SubjectHueSwatchRow.fallbackHue` is dead since it was added
  (ac669892) — its doc promises a ring for "colour comes from the name", nothing draws it, so with no swatch chosen
  the New collection row shows five unselected circles and no explanation (New queue has a footnote for this).
  Options: add New queue's footnote to New collection; or ring the swatch nearest the name's hue. Login (1n) NOT
  opened: its web view may reach AO3 outside DemoNetworkBlock — code-review only.

## agy task 14 (Claude Opus 4.6 via agy, read-only) — reader chrome, writing, library sheets, utilities (verified ~17:15)
24 rows.
- FIXED T-330 (integrate ce771dff): #1 Availability Done → trailing; #3 Read Aloud Form themed; #4–7 Color.accentColor → theme
  tint; #8 PrivacyDataView List minimum; #13 note editor detents + grabber. Found by Claude: "Zero KB" → "0 bytes" (shared
  formatter, 3 call sites), keeping "KB" casing (format style would write "kB").
- LATER (need screens reached first / screenshots): #2 Availability Form + .cardRow mix (visual check); #9–11 List minimum on
  Drafts, Preview, 4 association pickers; #12 1bv editor toolbar glass bar; #24 1ac promise panel green gradient;
  #23 BugReportView legacy Form.
- REJECTED: #22 editor line height (1.35 × serif's ~1.2 natural = spec's 1.62; the code comment says so). #16 red destructive
  rows are the app convention. #17–21 fixed sizes: the app's spec'd chrome uses fixed sizes app-wide (AX handled per screen
  in T-311); #15 badge font (shared SubjectStateBadge, P3). #14 checkmark vs "Done" → OD #2/#8 group.
- L3-B10-2 (P2, FIXED — see STATUS): Settings › Privacy sub-page is a system grouped Form with a "Privacy" section
  header repeating the page title — not the subject form grammar the hub got in L3-B10-1. Other Settings sub-pages likely same.
  L3-B10-2 resolution: sub-pages stay native Forms (documented choice in SettingsPageForm); the 10 headers that repeated the page title were removed.
- T-331 (integrate 1962033b): agy task 15 landed — agy #9–11 (List minimum on Drafts/Preview/4 pickers), L3-B1-9 fixed
  (dead fallbackHue removed; New collection footnote). Prompt Meme now offline (`ao3_challenge_requests`; note: `.gitignore`
  line 45 `*_prompt*` silently ignores any fixture with "_prompt" in its name).
- L3-B1-10 (P3, OPEN): Add Works sheet title truncates ("Add to Comfort…") — the Mature eye toggle shares the trailing
  toolbar group with Add. Options: move the eye into a "…" menu (menu order rule: Mature first) or shorten the title.
- FIRST PASS COMPLETE (17:45): all 68 INVENTORY rows audited at least once (Claude and/or Codex/agy/Grok).
- L3-TH-4 (P1 a11y, FIXED ffdcc764 + test 9d8a2c00): Teen rating yellow on its own tint over light cards ~1.3:1 in
  Light/Sepia (every work card, chip, Work Detail). Light appearances get a dark mustard; found on the second-pass theme
  sheets. Process slip: the colour commit landed before its test update (gate piped through grep) — fixed forward.
- Withdrawn: "Detailed card pill row centred" — documented choice in WorkStatLabel ("Centred. Justification stretched…").
- L3-AX-5 (P1 a11y, FIXED 1e20fff9): every SubjectFormRow/SubjectFormValue form was a fixed 15pt — no Dynamic Type across
  Settings, AO3 Preferences, challenge/collection forms. Now scaled; value rows stack at AX sizes; control labels wrap.
  Also fixed: AO3 Preferences navigation-link pickers drew their label twice ("Your site skin | Your site skin Reversi")
  at every size — `.labelsHidden()` doesn't apply to that style (pushed option list now has no title — acceptable).
- AX5 second pass (16 routes) — FIXED by Claude in baec039b (agy hit quota before editing; Codex brief withdrawn):
  L3-AX-6 Account gear overlaps kicker; L3-AX-7 "Subscriptio/ns" shortcut; L3-AX-8 single-word header titles split
  ("AO3_Reade/r"); L3-AX-9 Inbox "Chapt/er 3" chip; L3-AX-10 Queue row chips overlap, title fixed; L3-AX-11 Recently
  Deleted card mixed scaling; L3-AX-12 Home hero "Chap/ter 2". Also P3: .control text-field rows squeeze their value at AX5.
- L3-AX-6…12 FIXED (baec039b): one-word titles/usernames shrink instead of splitting; Account kicker clears the gear;
  Inbox chip never wraps; Home hero ring stacks at AX sizes; Queues/Recently Deleted rows scale consistently. Default size
  pixel-checked unchanged (Home, Account, Inbox, Queues). 113 tests / 7 suites.
- T-333 (owner, 2026-09-30): Browse → category → fandom/tag results were still the pre-redesign page (card hero, standard
  rows) while the Search tab's were 1k — never redesigned, not a regression. Now share the 1k page. integrate 8067e790.
- Gemini task 17: D ×3 fixed 317b0b96; A ×6 false positives (closures are real actions); E list → Codex task 16.
- Second pass, challenge screens: Light ✓ (7 screens). AX5: card/row text fixed while headers scale → Codex task 16.
  "Your sign-up" offline failure = missing fixture for a not-yet-signed-up user (not an app bug).
