# Batch 2 — Library polish audit (Grok)

Repo: `integrate/cloud-redesign`. Read-only. Spec: `docs/design/Final_Redesign_Spec.dc.html`. Checklist A–G from `.claude-overnight/polish/PLAN.md`. Line numbers from this worktree.

Artboard → code map:

| Artboard | Screen | Primary files |
|---|---|---|
| 1c | Library dashboard, shelves | `LibraryView.swift`, `WorkCarouselSection.swift`, `HomeCards.swift` (`WorkCoverCard`) |
| 1d | Library dashboard, ledger | `LibraryView.swift`, `CollectionLedgerRow.swift`, `WorkRow.swift` |
| 1ah | Reading History, by time | `LibrarySectionListView.swift`, `LibraryHistoryGrouping.swift`, `ReadingHistoryFactsStrip.swift` |
| 1ai | Reading History, by state | same + `MoveBackToInProgressButton` |
| 1aj | Favorites, Works | `LibrarySectionListView.swift`, `FavoriteQuickFilter.swift` |
| 1ak | Favorites, Authors | `FavoriteAffinityRow.swift`, `FavoriteAuthorFilterRail.swift`, `ReadingAffinities.swift` |
| 1bc | Favorites, Fandoms | `FavoriteAffinityRow.swift` (scope `.fandoms`) |
| 1bd | Favorites, Tags | `FavoriteAffinityRow.swift` (scope `.tags`) |
| 1bi | Reading Insights | `ReadingInsightsView.swift` |
| 1bj | Recently Deleted | `RecentlyDeletedView.swift` |
| 1ay | Reading Now, zero results | `LibraryFilterEmptyState.swift`, `LibrarySectionListView.swift` |
| 1az | Series, empty | `AuthorProfileContentSections.swift`, `AuthorProfileView.swift`, `AccountView.swift` |

---

## Findings

### batch-2-1 — P1 — 1bc — `FavoriteAffinityRow.swift:42` / `ReadingAffinities.swift`

**Artboard:** “Favorites — Fandoms.” Each row’s second half is a labelled block: uppercase **Since your last visit**, then **23 new works** / **6 new works** / **Nothing new**, with a mix line (“4 by authors you favorite · 2 over 50k words”) or “Last new work 26 Aug 2026”. Caption: “New-since-last-visit needs a per-fandom watermark stored locally and the fandom page’s newest works parsed.” The rail is **All · With new work · Most read · Sort**.

**Code:** `FavoriteAffinityRow` draws identity + log line + a one-line unread count. There is no “Since your last visit” block. `FandomReadWatermark` is stored and backed up (`ReadingLogService` ~line 452) but never read from this row or from `ReadingAffinities`. Fandoms also never get `FavoriteAuthorFilterRail`; there is no “With new work” chip on 1bc. Two-letter tiles in the mock (**GO**, **JJ**, **SW**, `font:700 16px`) become `String(row.name.prefix(1))` at line 231 (a single **G**).

**Smallest fix:** Add a fandom “since last visit” block that reads `FandomReadWatermark` + the fandom’s newest-works parse (the model is already there). Show two-letter initials. Put **With new work** on the same pill rail as Authors, gated on that fetch.

---

### batch-2-2 — P2 — 1ah / 1ai / 1aj — `LibrarySectionListView.swift:872` / `WorkCardActions.swift:252`

**Artboard 1ah:** “Swipe a row for **Queue** and **Remove** — Remove clears it from history, which is the only destructive thing this page can do.” Visible swipe labels: **Queue**, **Remove**. 1ai: “Swipe carries the same Queue and Remove as 1ah.” 1aj: swipe labels **Queue**, **Unstar**.

**Code:** Leading swipe calls `WorkLifecycle.setSaved` and labels it with `WorkActionLabels.saved` — **Download** / **Remove Download**, not Saved for Later / Queue (`WorkActionLabels.savedForLater` is a different pair at line 232). Trailing on History is **Remove from History** (right). Trailing on Favorites Works is **Unstar** (right). There is no Queue/Saved-for-Later swipe on these three screens.

**Smallest fix:** Leading swipe on 1ah/1ai/1aj should be `WorkActionLabels.savedForLater` (copy **Queue** / **Save for Later** to match the mock), and keep Download on the context menu if it still belongs there.

---

### batch-2-3 — P2 — 1ah — `LibrarySectionListView.swift:225` / artboard caption

**Artboard 1ah:** “No card view here — the tile format cannot carry this much metadata legibly.”

**Code:** History’s `…` menu always includes `DisplayModeMenuPicker`, which offers **Detailed / Ledger / Compact**. Compact is the two-up cover grid (`compactGrid` at line 756). A reader can put History into the layout the spec forbids.

**Smallest fix:** For `.history` (and probably `.favorites`, which 1aj also draws only as ledger), pass a picker that omits `.compact`, or disable Compact with a reason.

---

### batch-2-4 — P2 — 1ah / 1ai / 1aj / Reading Now / Finished / Downloaded — `LibrarySectionListView.swift:214`

**Convention (PLAN B, and `WorkListMoreMenu`’s own comment):** `…` order when present: Show/Hide mature · Select · Reorder (off under filters with a reason) · display mode · Expand/Collapse all · page items · destructive last. Home/Browse/Collections/Author profile all ship `ExpandAllMenuItem` (`HomeSectionListView` does not; Collections and `AuthorProfileView.swift:808` do).

**Code:** Library section lists: Mature → Select → `DisplayModeMenuPicker`. No Expand/Collapse. No Reorder (fair for History) and no disabled row explaining why. Expand/Collapse only matters in Detailed, but Detailed is on the picker, so choosing it leaves the control every other work list uses missing.

**Smallest fix:** After the layout picker, add `ExpandAllMenuItem` when `displayMode != .compact` (ledger does not expand — hide it there). Omit Reorder on History/Favorites with a disabled “Reorder isn’t available while filters are on / this list is recency-sorted” if you want PLAN B literally.

---

### batch-2-5 — P2 — 1c — `LibraryView.swift:9` / Saved for Later carousel

**Artboard 1c caption:** “Sections in source order: Reading Now, **Saved for Later (local + the AO3 “Marked for Later” card**, plus a Mature work held behind “Tap to reveal”)…”. The mock draws an **AO3** provenance kicker on *The Empty Hearth* inside Saved for Later.

**Code:** File header: “AO3 Marked for Later remains in Account and never becomes local queue membership.” The carousel is local queue members only (`LibrarySectionKind.savedForLater`). No AO3 card in this shelf.

**Smallest fix:** Either add the remote Marked-for-Later teaser card the mock shows (signed-in, provenance badge, tap → Account 1t), or treat the artboard caption as superseded and drop the AO3 card from the spec. As shipped, 1c is missing a named row.

---

### batch-2-6 — P2 — 1c — `LibraryView.swift:505` / `HomeCards.swift:131`

**Artboard 1c cover cards:** Reading Now centre is **2% / READING**, **42% / READING**; Saved for Later is **4/4 / SAVED**, **7/7 / SAVED**; Finished is **100% / DONE**. State is 8px uppercase under the figure.

**Code:** `footer` is publication percent only for Reading Now, the string **Finished** for Finished, and `nil` for Saved for Later / History / Downloaded. `progress` is only set for Reading Now. `WorkCoverCard.progressRing` labels the ring **Reading** or **Finished** (`HomeCards.swift:134`), never **SAVED** or **DONE**. Saved-for-Later cards therefore fall through `resolvedProgress` to whatever `readingProgress` happens to be, not the mock’s chapter fraction + SAVED.

**Smallest fix:** Per-section ring: Reading Now keeps percent + READING; Finished passes `progress: 1` and state **DONE**; Saved for Later passes chapter fraction (or complete) and state **SAVED**. Don’t send the Finished footer through `updateBadge` if the ring is the spec.

---

### batch-2-7 — P2 — 1ai — `LibraryHistoryGrouping.swift:79`

**Artboard 1ai:** three sections, uppercase kickers **IN PROGRESS · 2**, **ABANDONED · 1**, **FINISHED · 2**. Caption: Abandoned is its own section, rows grey, one-tap **Move back to In progress**.

**Code:** State grouping emits five buckets: **In progress**, **Abandoned**, **Read, not finished**, **Finished**, **Not started**. Grey + undo exist and match (`ledgerKickerMuted`, `MoveBackToInProgressButton.swift:14` copy is exact). Extra buckets are visible on the same screen as the mock’s three.

**Smallest fix:** When grouping is `.state`, only emit In progress / Abandoned / Finished (fold freed-history into Finished or a single “Read” bucket if you must keep them). Hide empty ones already happens.

---

### batch-2-8 — P2 — 1aj / 1ak / 1bc / 1bd / 1ay — `SubjectScreen.swift:267`

**Artboards:** dashed trailing chip copy is **Sort** on 1aj, 1ak, 1bc, 1bd, 1ay (`font:400 13px`, dashed pill). 1ah is the exception: it says **Filter**.

**Code:** `SubjectFilterRail` always draws **Filter** or **Filter N**. Favorites Works also has a comment that the artboard’s Sort chip was not rebuilt (`LibrarySectionListView.swift:445`).

**Smallest fix:** On Favorites + Reading Now, label the dashed chip **Sort** (it still opens the panel that owns sort). Leave History as **Filter**.

---

### batch-2-9 — P2 — 1ak / 1bc / 1bd — `LibrarySectionListView.swift:411` / `ReadingAffinities.swift:52`

**Artboard 1ak rail (one row of pills):** **All · With new work · Most read · Sort**. 1bc same. 1bd: **All · Unread works · Most read · Sort**. Header tally on every Favorites artboard: **34 works · 9 authors · 12 fandoms · 6 tags**.

**Code:** Authors get `FavoriteAuthorFilterRail` (All / With new work) and a *second* `SubjectSegmentedControl` of `ReadingAffinities.Order` (**Recent / Most read / Most time**). Fandoms/Tags get that Order control plus, for Tags, All / Unread works. **Most read** is not a pill on the filter rail; **Recent** and **Most time** are extra. Affinity header (`affinityHeader`, line 612) is only **N authors** / **N fandoms** / **N tags**. Works header is **N works · newest first**. The four-way tally never appears.

**Smallest fix:** One pill rail per scope as drawn (All / With new work / Most read on Authors and Fandoms; All / Unread works / Most read on Tags). Put the four-way tally on `SubjectHeaderBlock.subtitle` for every Favorites scope.

---

### batch-2-10 — P2 — 1ah / 1aj — `LibrarySectionListView.swift:846` / `ReadingHistoryFactsStrip.swift:60`

**Artboard 1ah:** “What this page adds sits on a **hairline underneath** — hours spent, reread count, and whether the work changed since you read it.” Mock facts are inline, tinted: `3h 20m`, gold **Read ×2**, accent **2 new chapters**. 1aj: “the reread count on the footer”, same hairline treatment; no changed-since.

**Code:** Facts are monospaced 11pt chips in a `FlowLayout` under the row, with **no hairline**. Duration uses `ReadingInsights.durationLabel` → **3 h 20 min**, not **3h 20m**. Style split history/favorites is correct (changed-since only on History). Zero facts correctly omit the strip.

**Smallest fix:** Draw `SubjectRowSeparator` above the strip. Format History/Favorites durations as `3h 20m` / `31h 12m` (the 1ak log line uses the same helper).

---

### batch-2-11 — P2 — 1bi — `ReadingInsightsView.swift:35` / `:420` / `:458` / `:396`

**Artboard 1bi:** three cards only (hours + 7-week bars, where the hours went, pace). Section kicker **This month** with trailing **7 wks**. Period control is not “This year”. Footer on the pace card: **“Sessions shorter than a minute are not counted…”** Caption: “The footer states the measurement rule.” Header subtitle: **18.4 hours in August · measured on this device**.

**Code:** Header tally matches the measured-on-device line. Hours / fandom / pace cards match structure, bar labelling, current-week accent, “Everything else”, figures (31 min, words/hour, % finished, streak). Then two extra cards: **Your library** (explicitly “Artboard 1bi draws three cards and stops”) and **Most-read fandoms**. Period picker is **This month / This year**, and the section count is `weeklySeconds.count` (a bare **7**), not **7 wks**. Pace footnote is **“Sessions shorter than 15 seconds…”** (`minimumPersistableDuration = 15`).

**Smallest fix:** Drop or fold the two extra cards under a disclosure if the owner still wants the old stats. Replace This year with a **7 wks** note on the hours section. Keep the 15-second truth in the footnote (honest) but the mock’s “a minute” is what the card currently fails.

---

### batch-2-12 — P2 — 1ay — `LibraryFilters.swift:7` / `LibraryFilterEmptyState.swift:135`

**Artboard 1ay:** three named filters on the rail, all selected: **Unread**, **Downloaded**, **50k+ words**, plus idle **Updated this week**, dashed **Sort**. Card title **Nothing matches all three filters.** Body: **Every work in Reading Now is hidden. Downloaded and 50k+ words have no works in common here.**

**Code:** Collision card title/counts/drop-one/Clear/Edit match type (18/13.5/8.5/14) and the drop-one pattern. `LibraryFilters` has no Unread, Downloaded, or “updated this week” facet — only completion, word bounds (`Words ≥ 50000`, not **50k+ words**), tags, rating, etc. So the mock’s colliding pair cannot appear as labelled. Detail copy is **“All N works in Reading Now are hidden.”** not **“Every work in Reading Now is hidden.”** Funnel badge is wired (`badgeCount:` at `LibrarySectionListView.swift:212`).

**Smallest fix:** Add Unread / Downloaded (and optionally Updated this week) as Library filter members if 1ay is the spec, and label the word-count chip **50k+ words** when the bound is 50_000. Align the hidden-count sentence with the mock, or keep the counted sentence if you prefer exactness (PLAN D).

---

### batch-2-13 — P2 — 1az — `AuthorProfileContentSections.swift:476` vs `:559`

**Artboard 1az:** full subject page, kicker **AO3 Account**, 32pt **Series**, subtitle **No series yet**. Card title **You have not made a series.** (18 semibold). Body about grouping works. Primary **New series on AO3**. Footnote **“Opens archiveofourown.org in Safari. Posting is not something the app does.”** Glass **+** in the toolbar.

**Code, live path** (`showsNewSeriesOnAO3`, used from `AccountView.swift:817` and own-profile): 14pt semibold title, same body, then `AccountExternalNavCard` with footnote **“Opens archiveofourown.org in Browse. Series are made there, not in the app.”** `pathSuffix: "series/new"` builds **`/users/<username>/series/new`**. The spec-faithful `AO3SeriesEmptyCard` (18pt, Safari, site-wide `https://archiveofourown.org/series/new`) is **unreferenced**. Subtitle **No series yet** is set (`AuthorProfileView.swift:325`). No toolbar +.

**Smallest fix:** Use `AO3SeriesEmptyCard` (or its URL + 18pt layout) on the own-series empty branch. Add a glass + that opens the same destination. Do not use the user-scoped `series/new` path unless it is a real AO3 route (the unused card already picked `/series/new`).

---

### batch-2-14 — P2 — 1c — `LibraryView.swift:307` / `:320`

**Artboard 1c:** section stack Reading Now → Saved for Later → Finished → Collections → Downloaded → Reading History → Favorites → Recently Deleted. Gap between blocks **18px**. 1d gap **16px**.

**Code:** Real dashboard has all seven plus Recently Deleted. First-paint `TabDashboardShell` titles omit History and Favorites (`LibraryView.swift:308-310`). `VStack(spacing: 24)` for both layouts.

**Smallest fix:** Add “Reading History”, “Favorites” to the skeleton. Use spacing 18 for shelves (1c) and 16 for ledger (1d).

---

### batch-2-15 — P3 — 1c — `Collections.swift:102` / Recently Deleted row `LibraryView.swift:341`

**Artboard 1c:** New collection card title **New collection** (sentence case), subtitle **Tap to create**. Recently Deleted: trash + **Recently Deleted** `font:600 14px` + count `400 13px` `rgba(235,235,245,.5)` + chevron, fill `rgba(235,235,245,.08)`, not a material tile.

**Code:** Shelves card title **New Collection** (title case). Ledger row title is already **New collection** (`CollectionLedgerRow.swift:229`). Dashboard Recently Deleted is `.subheadline.weight(.semibold)` on `.regularMaterial` radius 12.

**Smallest fix:** “New collection” on the shelves card. Draw the deleted row as a 16pt subject row (600/14 + 400/13 + chevron), not material.

---

### batch-2-16 — P3 — 1ak / 1bd — `FavoriteAffinityRow.swift:82` / `:147` / `:205`

**Artboard 1ak:** author name `600 16px`, no star on the identity line, newest-work meta **posted 2 Sep 2026**. 1bd empty unread line: **Everything tagged this way is finished**.

**Code:** Name is **15** semibold. Every Authors/Fandoms/Tags row draws `star.fill` (comment: “being on this page *is* the favourite”). Newest-work date is labelled **updated** (parser stores `dateUpdated`). Unread-empty line is **Everything tagged this way has been opened**.

**Smallest fix:** 16pt names; drop the decorative star on aggregate rows (the Works scope already stars the title); keep “updated” if the date is an update, or show the posted date if the store has one; 1bd empty line can stay honest or match the mock.

---

### batch-2-17 — P3 — 1bj — `RecentlyDeletedView.swift:309` / `:637`

**Artboard 1bj:** subtitle **6 items · removed from the app after 30 days**. Countdown **3d** `700 13px` `#FF9F0A`, **LEFT** `400 9px` uppercase. Select is a visible glass pill (not inside `…`). Swipe Restore then Delete. **Delete All Permanently** outlined red capsule.

**Code:** Window is read from `PreservedWorkService.recoveryWindow` (90 days) and the subtitle tells the truth — correct, but not the mock’s 30. Countdown is **15** semibold, **left** 10pt not uppercase. Amber `< 7` days matches “amber under a week”. Select is a visible toolbar button (matches 1bj, not PLAN B). Swipe order, reassurance copy, kickers (Downloaded work / Reading queue / Local collection), Expiring soon / Later, Delete All Permanently, per-item alert — match.

**Smallest fix:** 13pt bold countdown, uppercase **left**. Leave 90 in the subtitle unless the recovery window itself should become 30.

---

### batch-2-18 — P3 — 1c / 1ah — `SectionRuleHeader` hairline / offline tick

**Artboard 1c/1ah:** section headers run a hairline to the chevron. 1ah/1aj caption: “offline tick in the metadata line”.

**Code:** `SectionRuleHeader` spacer is explicitly undrawn (“Owner call: too many hairlines”). `WorkLedgerRow` comment: offline tick removed with owner approval. Still visible against the mocks.

**Smallest fix:** None unless the owner wants the hairline/tick back; recording the drift.

---

### batch-2-19 — P3 — 1ai — `MoveBackToInProgressButton.swift:16`

**Artboard:** full-width outlined control on the Abandoned card, label **Move back to In progress**.

**Code:** Copy and intent match. Padding 12×7 + 12.5pt type is well under a 44pt target (`LibrarySectionListView` does not apply `minimumHitTarget` here).

**Smallest fix:** `.minimumHitTarget()` on the button.

---

## Per-screen coverage

### 1c Library, shelves

Checked, matches:

- Section order Reading Now → Saved for Later → Finished → Collections → Downloaded → Reading History → Favorites → Recently Deleted (`LibraryView.swift:321-330`)
- Collapse caret + see-all chevron (`WorkCarouselSection` / `SectionRuleHeader`)
- Reset chip when any filter is on; quieter than fandom pills (`LibraryView.swift:469-477`)
- Fandom chips are pills; selected uses accent fill (`SubjectChip.pill`)
- Filters stay in the toolbar; `…` holds Mature, Reading Insights, Select, Shelves/Ledger (`LibraryView.swift:561-596`) — same order as the 1c caption
- New collection leading card in Collections; “Tap to create”
- Favorites empty copy exact: “Swipe a work in your Library, or tap the star on its page, to favorite it.”
- Tap to reveal on blurred mature cards (`MatureContent.swift:281`)
- Pull to refresh (`refreshable`)
- Recently Deleted hidden when count is 0 (mock shows it with 11 items)
- iOS large title “Library”; 32pt in the mock is `inlineLarge`
- No always-on drag handles
- Delete lives in section lists / select mode, not on the dashboard carousels

Gaps: batch-2-5, 2-6, 2-14, 2-15. Skeleton omits History/Favorites. Dashboard `FilterButton` has no numeric badge (1c mock also has none). No `+` in the Library toolbar — add is the New collection card, matching 1c.

Not verified in a simulator: actual Liquid Glass chrome, iPad/macOS overlap, Dynamic Type clipping.

### 1d Library, ledger

Checked, matches:

- Same seven sections, same chips/Reset/collapse/see-all
- Ledger rows: fandom kicker, title, author · words · chapters, 2×2 signal tray (`WorkLedgerRow`)
- Collections ledger: 128×114 2×2 miniatures, 61×54 cells, 6pt gap, title 15 semibold, “N works”, chevron (`CollectionLedgerRow.swift`)
- New collection ledger: dashed stroke, 128×114 plus well, “New collection” / “Tap to create”
- Mature “Tap to reveal”; Favorites empty; Recently Deleted row
- Layout is one page-wide `WorkSectionLayout`, not per section

Gaps: same AO3 MFL and spacing as 1c. Ring diameter is tray height (~59pt) rather than the caption’s **44px** — documented in `WorkRow.swift:150`. 1d mock also uses 44.

### 1ah Reading History, by time

Checked, matches:

- Local history, not AO3; works you’ve actually read (`LibrarySectionKind.history`)
- Default grouping Time; chips Time / State / Fandom / Flat (`LibraryHistoryGrouping`)
- Tally **N works · most recently read first**
- Ledger default (`defaultDisplayMode = .ledger`)
- TODAY / THIS WEEK… via `SectionRuleHeader` uppercasing “Today”
- Facts: time, Read ×N when finishCount > 1, N new chapters; no “0m · Read ×0”
- Trailing Remove from History (hide marker, not delete)
- Filter dashed chip (this artboard does say Filter)
- Subject header kicker + 32pt title + wash
- Empty copy explains the log
- Pull to refresh; select mode + bulk bar; tab bar hides while selecting

Gaps: batch-2-2 (Queue), 2-3 (Compact), 2-4 (Expand all), 2-10 (hairline + `3h 20m`). Offline tick absent (owner call).

### 1ai Reading History, by state

Checked, matches:

- Same screen, grouping `.state`
- Abandoned derived, not stored; undo writes `keepInProgress`
- Abandoned rows desaturate the kicker (`ledgerKickerMuted`)
- Button copy **Move back to In progress**
- Tally **N works · N in progress · N abandoned** (zeros dropped)
- Same Queue/Remove expectation as 1ah (and the same Download-not-Queue bug)

Gaps: batch-2-7 extra buckets; 2-19 hit target.

### 1aj Favorites, Works

Checked, matches:

- Local stars, no AO3 write
- Segmented Works / Authors / Fandoms / Tags
- Pills All / Rereads / Offline / WIP; All is the default
- Ledger rows; gold star beside the title (`showsFavoriteStar`)
- Footer time + Read ×N; no changed-since
- Trailing Unstar (not Delete)
- Header on Works: work count (not the four-way tally)
- Empty copy same as 1c Favorites

Gaps: batch-2-2 Queue, 2-3 Compact, 2-8 Sort chip, 2-9 four-way tally, 2-10 hairline. Offline tick absent.

### 1ak Favorites, Authors

Checked, matches:

- Rows: initial tile (circle, first letter), name, log line **N works read · duration · last read**
- Newest work block, uppercase label, UNREAD tag
- Chevron to author page when a registered username exists
- All / With new work rail; With new work waits on prefetch (“Checking new work…”)
- Empty states distinguish “nothing read” vs “chip hid every row”
- Compact word counts on newest-work meta (`12k words`)

Gaps: batch-2-9 rail/tally, 2-16 star/size/posted, duration `31 h 12 min` vs `31h 12m`. No swipe on aggregate rows (mock has none).

### 1bc Favorites, Fandoms

Checked, matches:

- Same Favorites chrome / segments
- Log line inserts **N favorited** after works read
- Tile is a rounded square, not a circle
- Unread library line present

Gaps: batch-2-1 (the screen’s second half). No “With new work”. Initials are one letter.

### 1bd Favorites, Tags

Checked, matches:

- `#` tile, circular
- Log line **N works read carry this tag · last read …**
- Block **In your library** / **N unread works** / **No unread works**
- Extras **N downloaded · N in Saved for Later**
- All / Unread works pills
- Empty-by-filter copy for Unread works

Gaps: batch-2-9 Most read as a pill + four-way tally; 2-16 “finished” vs “opened”.

### 1bi Reading Insights

Checked, matches:

- Reached from Library `…` → Reading Insights
- Header kicker Library, 32pt title, “measured on this device”
- Hours hero + signed delta vs previous month
- Seven bars, value on top, current week at full accent, no axis
- Where the hours went, remainder **Everything else**
- Pace grid: median session, words per hour, % finished, longest streak
- `—` when words/hour or finish rate would be a fake 0%
- Empty: no overlay if the library card still has data; full empty only when no sessions and no works
- Pull to refresh; Reduce Motion not specially handled on the bars (not verified visually)

Gaps: batch-2-11 extra cards, This year, 7 vs 7 wks, 15 seconds vs a minute.

### 1bj Recently Deleted

Checked, matches:

- Mixed kinds, grouped Expiring soon / Later (14-day split; 9d still in Expiring soon as in the mock)
- Kicker names the kind; countdown stacked **Nd** / **left**; amber under a week (`#FF9F0A` via `subjectAmber`)
- Reassurance card copy almost verbatim (straight apostrophe vs the mock’s ’)
- Swipe Restore + Delete (Delete outermost); context menu for macOS
- Select visible; bulk Restore / Delete Permanently / Done
- Delete All Permanently outlined red, 14 semibold, own confirmation
- Per-item alert names real download / place / notes
- Hidden from Library when empty; empty `ContentUnavailableView` if you land here empty
- 44pt min height on Delete All Permanently

Gaps: batch-2-17 (30 vs 90, countdown type). No `…` menu (artboard has none). No add.

### 1ay Reading Now, zero results

Checked, matches:

- Header **N works · none match the current filters**
- Collision card: title by filter count, drop-one rows with remaining counts, **Clear all filters** then **Edit**
- Type 18 / 13.5 / 8.5 / 14; radius 18; padding 18
- Filter button badge = active narrowing count
- Edit opens the same inspector

Gaps: batch-2-8 Sort vs Filter, 2-12 missing Unread/Downloaded/50k+ labels. Reading Now also shows All/WIP completion pills (`LibraryCompletionPills`) in front of the summary chips — extra vs the mock’s four named filters.

### 1az Series, empty

Checked, matches:

- Subtitle **No series yet** on own profile when count is 0
- Body explains what a series is and that AO3 creates them
- Action title **New series on AO3**
- Loading / error branches exist on the profile (`AO3AuthorContentMessage`)
- Creating a series is not an in-app write

Gaps: batch-2-13 (live empty is the 14pt Browse card; spec card unused; toolbar + missing; URL path differs). Signed-out: `AccountExternalNavCard` disables when `auth.username == nil`.

---

## Checklist holes (A–G) that are systematic

- **B Actions:** History/Favorites swipes are Download, not Queue. Library section `…` never offers Expand/Collapse. 1bj Select is correctly *not* buried. 1c add is the New collection card, not a toolbar +.
- **C Consistency:** `SubjectHeaderBlock`, `SectionRuleHeader`, `SubjectChip`, `WorkLedgerRow`, `FilterButton`, `WorkListMoreMenu`, `LibraryFilterCollisionCard` are reused. Drift is copy (Filter vs Sort) and missing ExpandAll vs Collections/Browse.
- **D Data display:** Insights hours are one decimal; compactName used on newest-work words and Insights library words. 1ay would print `Words ≥ 50000`. No raw 0% on Insights finish rate (`—`). Fandom chips on 1c keep disambiguation (**Supergirl (TV 2015)**), which is what that artboard draws.
- **E States:** Section empty copy + icon; filter collision is actionable; Insights empty; Recently Deleted empty; Favorites affinity empty-by-filter. 1c skeleton is one section short. 1az live empty is the weaker of two implementations.
- **F A11y:** 34pt glass chrome is below 44pt but `minimumHitTarget()` is used on chips, collapse, see-all, author chevron. Abandoned undo is not. VoiceOver: History facts chips, Insights bars, Recently Deleted countdown, affinity rows combined. Dynamic Type: ledger stacks at accessibility size; Insights grid collapses to one column. Reduce Motion: carousel collapse uses `withAnimationUnlessReduced`; Insights bars do not.
- **G Platform:** iOS tab bar hides in select mode on Library dashboard, section lists, Recently Deleted. Pull to refresh on dashboard, section lists, Insights. Keyboard: filter inspector only. iPad/macOS not built in this audit (read-only, no xcodebuild).

---

## Three that matter most

1. **1bc is half a screen.** The fandom rows never show “Since your last visit” / new-work mix, and there is no “With new work” chip, even though `FandomReadWatermark` already exists. That is the feature 1bc is for.
2. **History and Favorites cannot Queue from a swipe.** 1ah/1ai/1aj specify Queue + Remove/Unstar. The leading action is Download. Remove/Unstar are right; the add-to-queue gesture the mock teaches is missing.
3. **1az’s good empty state is dead code.** Own Series empty uses a 14pt Browse card aimed at `/users/…/series/new`. `AO3SeriesEmptyCard` already has the spec’s 18pt card, Safari footnote, and `/series/new`. Wire that, and add the toolbar +.
