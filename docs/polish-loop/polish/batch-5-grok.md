# Batch 5 — Browse and Search polish audit (Grok)

Repo: `integrate/cloud-redesign`. Read-only. Spec: `docs/design/Final_Redesign_Spec.dc.html` (extracted with `Scripts/redesign-spec-outline.py`; px = pt). Checklist A–G from `.claude-overnight/polish/PLAN.md`. Line numbers from this worktree. No build, no simulator, no AO3 traffic — anything that needs a running screen is called out as unverified.

Where `docs/REDESIGN_DECISIONS.md` already supersedes an artboard, that is recorded under the screen’s checked list, not filed as a defect to revert.

Artboard → code map:

| Artboard | Screen | Primary files |
|---|---|---|
| 1g | Browse categories | `MediaBrowserView.swift` (`categoryPanel`, `jumpBackInSection`, `FandomChipCluster`) |
| 1al | Category, A–Z families | `FandomListView.swift`, `FandomFamilyRows.swift` |
| 1am | Category, most works | Same list, `sort == .familyTotal` |
| 1an | Category filter sheet | `FandomListFilterSheet.swift`, `FandomFamily.swift` (`FandomLibraryIndex`) |
| 1k | Search results | `SearchView.swift`, `SearchResultsHero.swift` (`.subjectPage`), `AO3WorkRow.swift` (`.searchLedger`) |
| 1ao | Filters, medium detent | `AO3FilterPanel.swift` (`.search`) |
| 1ap | Filters, warnings and categories | `cyclingFacetRow`, `AO3Models.swift` warning/category titles |
| 1aq | Filters, status, dates, language | `AO3FilterPanel.swift` status + date sections, `FilterLanguagePicker.swift` |
| 1ar | Language list | `FilterLanguagePicker.swift` |
| 1as | Tags, title, creator | `tagSection`, `TagSelectField.swift`, `typedSections` |
| 1at | Ranges and Save Search… | `FilterRangeSlider.swift`, `Save Search…` button |
| 1au | Refine | `AO3FilterPanel.Mode.refine` |
| 1av | Characters, popular | `TagPickerView` |
| 1aw | Characters, typing | `TagPickerView`, `FilterTagChip` |
| 1ax | Save search | `SaveSearchSheet.swift`, `SearchView.presentSaveDialog` |

Browse’s works page (the tap from 1g / 1al) is `FandomWorksView` in `NativeBrowseView.swift`. It is not its own artboard; 1k is the results language those taps are supposed to land in.

---

## Findings

### batch-5-1 — P1 — 1ax — `SaveSearchSheet.swift:159`

**Artboard:** the sheet exists so the reader sees the search before committing. Chips, in order: included tags in green (`border-radius:99px`, `background:rgba(102,199,115,.14)`, `#66C773`), excluded tags and excluded warnings in red with a minus (`−Eren Yeager/Levi`, `−Graphic Depictions Of Violence`), then the facets **Teen And Up+**, **M/M**, **Gen**, **Complete**, **Words 5,000–80,000**, **Kudos ≥ 500**, **English**, and **Sort: Kudos** last. Footer: **“Only settings you changed are listed. Sort is always shown.”** Caption: “Sort is last and always present, because there is always an order in effect.”

**Code:** the comment at line 105 says the list is “included terms plainly, excluded terms prefixed with a minus … then the faceted choices.” `summary` appends the query, title, creators, the eight tag fields, and the rating, then `return items` at line 159. Warnings, categories, completion, word/kudos/hits/comments/bookmarks ranges, language, and sort are never appended. The footer sentence is not in the view. A reader can save a search whose warnings, word range, language, and sort are invisible on the only screen that claims to print them. The name seeding is right (`SearchView.swift:790` uses `searchSubject`, else **Saved Search**).

**Smallest fix:** Keep building `summary` from the filter values. After the tags, append each non-default warning, category, completion, range, and language, then append `Sort: \(filters.sort.title)` unconditionally. Add the footer under the chips.

---

### batch-5-2 — P1 — 1an — `FandomListView.swift:62`

**Artboard:** switch **I have downloads from**, detail **23 tags**. `REDESIGN_DECISIONS.md` **1an.2**: it means **on disk now** — “What the reader can open offline.”

**Code:** `libraryIndex` unions a work’s fandom names into `downloads` when `work.isSaved`. `SavedWork.isSaved` (`Models.swift:204`) is the keep-forever flag. `SavedWork.hasEPUB` (`Models.swift:222`) is the file on disk. A kept work whose EPUB was freed still matches. A file that is on disk and not marked keep does not. `listingToken` (`FandomListView.swift:73`) also counts `isSaved`, so freeing a file does not refresh the list.

**Smallest fix:** Index `hasEPUB`, and count `hasEPUB` in `listingToken`.

---

### batch-5-3 — P2 — 1g — `MediaBrowserView.swift:404` and `:711`

**Artboard:** each category stat line ends **12 downloaded** / **21 downloaded** / **3 downloaded**, beside a download glyph, in the same wrap as **9,412 fandoms** and **~2.1M works** (`gap:4px 14px`, `400 11px`).

**Code:** the label is `"\(saved) downloaded"` with `WorkActionLabels.downloadedSymbol`, shown when `savedCount > 0`. `computeStats` increments `savedCount` for every non-deleted library work whose fandoms intersect the category (`:711`). It does not read `hasEPUB` or `isSaved`. The word is the same word as 1an.2, and the number is library membership.

**Smallest fix:** Count works with `hasEPUB` (and say **downloaded** only for those).

---

### batch-5-4 — P2 — 1g — `MediaBrowserView.swift:321` / `AppRouter.swift:211`

**Artboard:** under the last panel, a dashed row (`margin:20px 16px 0`, `padding:12px 14px`, `border-radius:12px`, `500 13.5px`, `rgba(235,235,245,.78)`): **Open AO3 Website**, with a trailing chevron.

**Code:** the iOS footnote is **“Browse fandoms from AO3. Tap a category to see its fandoms.”** `NativeBrowseView.swift:5` and `BrowseView.swift:6` still describe a Browse toolbar entry named **Open AO3 Website**. `AppRouter.openWebsite()` (comment: “Browse toolbar entry”) sets `isPresentingWebBrowser` and has no production caller — the only call is `KudosTests/AppRouterTests.swift:90`.

**Smallest fix:** Add the dashed row and call `router.openWebsite()`. Update the two file headers so they describe the row that exists.

---

### batch-5-5 — P2 — 1g — `MediaBrowserView.swift:247` and `:650`

**Artboard:** Jump Back In titles are bare names: **Naruto**, **Doctor Who**, **Star Wars** (`600 14px`). Cluster chips use the same bare titles (**Frozen**, **Les Misérables**). PLAN D asks for bare names where the board shows them.

**Code:** the card prints `entry.fandom`, which `jumpBackInFandoms` sets from `work.fandomsDisplay`, which `recomputeStats` copies from `work.workFandoms` (`:599`). That is the raw library tag, so a work tagged **Naruto (Anime & Manga)** titles the card with the qualifier. Cluster chips use `family.parsedTitle` (`:738`). The two Browse surfaces spell the same fandom two ways.

**Smallest fix:** Pass `FandomDisplayName.bareTitle` (or the family’s parsed title) into the card. Keep the raw tag as the search key, the way the cluster already does (`onSelectFandom($0.names, $0.title)`).

---

### batch-5-6 — P2 — 1al / 1am — `FandomListView.swift:232` / `FandomFamilyRows.swift:4`

**Artboard caption:** “A fandom with one tag uses the same block, without the tint or the tag marker.” Assassination Classroom is that block: gold star, title `500 15px`, aliases, then an indented child **Anime & Manga** / **2,140** / chevron (`margin-left:21px`, `padding-left:14px`, `border-left:1.5px solid rgba(180,155,234,.2)`). Multi-tag families add the wash and **All N tags**.

**Code:** `family.memberCount == 1` renders `FandomListRow` and never `FandomFamilyBlock`. The file header says so: “Single-tag families keep `FandomListRow` and never reach this view — no tint, no ‘All N tags’ marker.” The row puts the qualifier under the title as a footnote (`.footnote`) and the count on the trailing edge. There is no child row and no chevron on the qualifier.

**Smallest fix:** Send single-tag families through `FandomFamilyBlock` with the wash and the **All N tags** line omitted. One row component, two decorations.

---

### batch-5-7 — P2 — 1al / 1am — `FandomListRow` (`FandomListView.swift:698`) and `FandomFamilyBlock` (`FandomFamilyRows.swift:40`)

**Artboard:** a filled star `#F2C879` on Assassination Classroom and a dim star `rgba(235,235,245,.3)` on Attack on Titan. Attack on Titan also carries a green download badge **3** (`500 11.5px` mono, `#8FE0C4`) beside the title. `#F2C879` is `Color.subjectFavoriteGold` (`SubjectScreen.swift:284`).

**Code:** `libraryIndex` already computes both sets (`FandomListView.swift:56–67`) and the filter sheet reads them. Neither row draws a star or a download count. The data is one view away and the marks are not.

**Smallest fix:** On the family header (and the single-tag row, once it is that header), draw `star.fill` in `subjectFavoriteGold` when any member is favourited, the dim star otherwise, and the green on-disk count from `hasEPUB` (batch-5-2) when it is non-zero.

---

### batch-5-8 — P2 — 1al — `FandomListView.swift:187`

**Artboard:** letter headers (**A** `700 13px` accent, count, hairline) plus a vertical index **A B C … Z #** pinned on the trailing edge. Caption for 1am: “Letter groups and the A–Z index drop out” when the sort is most works.

**Code:** A–Z draws `FandomLetterHeader` inside `Section` headers. Most-works correctly skips them (`sort == .alphabetical`). There is no `sectionIndex` / index titles anywhere in `FandomListView.swift` or `FandomFamilyRows.swift`. A category of thousands of families has letters and no way to jump to one.

**Smallest fix:** Add a vertical index bound to `FandomFamily.letterSections`, shown only while `sort == .alphabetical`.

---

### batch-5-9 — P2 — 1al — `FandomFamilyRows.swift:206`

**Artboard:** **A–Z** is a selected pill (`padding:7px 14px`, `border-radius:99px`, fill `#B49BEA`, `600 13px`). **Most works** is an unselected pill (`500 13px`). **Group variants** is a pill too (`border-radius:99px`, tinted fill `rgba(180,155,234,.18)`, stroke, check glyph, `500 13px`), not a rounded rect. `SubjectChip`’s own comment (`SubjectSurface.swift:902`) says a pill offers a toggle and a rounded rect states a fact.

**Code:** the two sorts are `.pill(isSelected:)`, which is the right shape, at `.regular` 13 rather than semibold 13 when selected (`SubjectChip` line 943: only `.tinted` is `.medium`; every other style is `.regular`). **Group variants** is `.tinted` while on and `.neutral` while off, with `square.stack`. Both of those styles are radius-8 rects. The control that the decision says to build (`REDESIGN_DECISIONS` **1al**) is the one chip on the rail in the wrong grammar.

**Smallest fix:** `SubjectChip(text: "Group variants", style: .pill(isSelected: groupsVariants), systemImage: "checkmark")` when on, and no icon when off. Give a selected pill `.semibold`.

---

### batch-5-10 — P2 — 1al / 1am — `FandomFamilyRows.swift:59`

**Artboard 1al (A–Z):** a multi-tag header shows **All 4 tags** (`500 11px` mono, accent) and does not print the summed total. **1am (most works):** the same header prints **~17,300** and **All 4 tags**. The tilde is the sum-of-tags warning in the 1am caption.

**Code:** every multi-tag header, in both sorts, draws `countLabel` (the summed or cached total, with `~` while `showsApproximateCount`) and **All \(memberCount) tags**. A–Z therefore shows a figure the board keeps for the sort where that figure is the ranking key.

**Smallest fix:** Draw the summed figure only when `sort == .familyTotal`. Keep **All N tags** on every multi-tag header. Keep the tilde until `applyingExactCount` replaces it (`FandomListView.swift:92`).

---

### batch-5-11 — P2 — 1k — `SearchView.swift:164` / `SearchResultsHero.swift:121`

**Artboard:** one row of 34px glass: back, a query pill whose text is **Good Omens (TV)** (`400 14.5px`), an accent filter circle with badge **3** (`700 9.5px` on `#D9B26A`), overflow. The sort dropdown beside the subject reads **Newest updates first** (`500 13.5px`). The dashed chip at the end of the rail is the word **Filter** (`border-radius:8px`); the count lives on the toolbar badge. Each active chip is a tinted rect with a trailing × (`opacity:.75`).

**Code:** results use the system toolbar: a back chevron, `GlassFieldBar` placeholder **“Search your library and AO3”** (`SearchView.swift:563`), `FilterButton` (the Mail-style funnel, badge via `SearchFilterBadge.count`), and `WorkListMoreMenu`. The comment at `:315` says this is deliberate because Search is a tab root and keeps its navigation title, where 1k gives the bar up to floating chrome. The sort menu label is `Sort.title`, so Date Updated reads **Date Updated** (`AO3Models.swift:1149`), not **Newest updates first**. `SubjectFilterRail` (`SubjectScreen.swift:267`) writes **Filter \(count)** on the dashed chip while the toolbar badge already shows that count. The chips in the rail are `SubjectChip` `.tinted` with no `trailingImage` and they are not buttons (`SearchResultsHero.swift:98`), so the × `SubjectChip` documents at line 928 is never passed and a chip cannot be cleared.

The `…` menu, when results are non-empty, is Mature (only while Hide Mature is on), Select, Expand all. Reorder, a display-mode picker, and page items do not exist for an AO3 result list. That part matches PLAN B’s “when present”.

**Smallest fix:** Keep the tab-root toolbar if that exception stays, and write it into `REDESIGN_DECISIONS` so it stops being an undocumented drift. Either way: label Date Updated + descending **Newest updates first**; leave the dashed chip as **Filter** when the badge already carries the count; pass `trailingImage: "xmark"` and remove that one filter on tap.

---

### batch-5-12 — P2 — 1k — `AO3WorkRow.swift:208`

**Artboard:** the locked ledger row. Kicker **Good Omens (TV)** (`700 10px`, uppercase, tracking `.11em`) with the expand chevron inline (`20×20`). Title `600 19px`. Byline `400 13.5px`. Summary `400 14px`. Expanded groups **FANDOMS**, **RELATIONSHIPS**, **CHARACTERS**, **ADDITIONAL TAGS** (`600 10px`, tracking `.1em`). Relationship chips are the subject tint (`background:#D9B26A3D`, `500 13px`, `#F4E4C6`); every other group is a neutral rect. The fandom chips include the kicker’s own tag, qualifier and all. Meta is `400 11.5px`: **English · 84,210 words · 11/11 · 212 comments · 3,204 kudos · 486 bookmarks · 61,904 hits**, date trailing. `WorkLedgerRow`’s header (`SubjectScreen.swift:303`) lists 1k as one of its artboards.

**Code:** Search uses `presentation: .searchLedger`, which is a second layout, not `WorkLedgerRow`. The kicker is `FandomDisplayName.bareTitle` (`:386`), so **Good Omens (TV)** becomes **Good Omens**. PLAN D’s bare-name rule applies where the board shows a bare name; this board keeps the disambiguator, on the kicker and again on the chip. Expanded fandoms are `nonemptyFandoms.dropFirst()` (`:274`), so the primary tag is missing from the group the board repeats it in. `chipGroup` (`:457`) labels are `.caption2.semibold` tertiary, not uppercase tracked 10px, and every chip is `TagChip` with `tinted` left false (`TagChip.swift:47` fills those with `quaternarySystemFill`). The ledger path also adds an **Archive Warnings** group the board does not draw; the standard card’s comment at `:162` already removed that group. Title is `.title3.semibold` (~20pt). Byline is `.subheadline` (~15pt). Meta is `.caption2` (11pt) and otherwise matches the board’s units and exact figures (`ledgerCount` uses `.formatted()`).

The expand control is a 20pt glyph with `minimumHitTarget(30)` (`:424`). The comment says 44pt reached the fandom button 5pt away. That exception is real; it is listed under checked, not here.

**Smallest fix:** On `.searchLedger`, kicker and fandom chips use the raw display segment (qualifier kept). Stop dropping the first fandom. Uppercase the group labels at 10pt with `.1em` tracking. Pass a tint into `TagChip` only for `.relationship`. Drop the warnings group. Set the title to 19pt semibold and the byline to 13.5pt.

---

### batch-5-13 — P2 — 1k (Browse and tag destinations) — `NativeBrowseView.swift:169` and `:470`

**Artboard 1k** is “search results in the same language as every other pushed, subject-scoped screen”: wash, 32pt hero, stat strip, chip rail, ledger rows. Tapping a fandom on 1g or 1al is that push.

**Code:** `FandomWorksView` and `TagWorksView` both call `SearchResultsHero` without `presentation`, so it stays `.card` (`SearchResultsHero.swift:44`): a tappable card, not the subject page. Rows are `SelectableAO3WorkRow` with the default `.standard` presentation. The row comment (`AO3WorkRow.swift:20`) says Search opted into the redesign “without changing the shared row in Browse.” `FilterButton` on both toolbars omits `badgeCount` (`NativeBrowseView.swift:393` and `:524`), so the count 1k puts on the filter never appears. Pagination is the shared bar, which is right, and it is not given the subject palette (Search’s call at `SearchView.swift:553` does pass `resultsPalette`).

**Smallest fix:** Pass `presentation: .subjectPage` and a sort binding, draw rows as `.searchLedger`, pass `badgeCount`, and pass the subject palette into `SearchPaginationBar`. The deferral comment can come out in the same change.

---

### batch-5-14 — P2 — 1g — `MediaBrowserView.swift:272`

**Checklist G.** iPhone and iPad share the `#if os(iOS)` panels. macOS does not.

**Code:** `categoryListMac` is a `DisclosureGroup` list, header **Browse by fandom**, of `category.fandoms` (the featured subset), each row the raw `fandom.name`. No Jump Back In, no hue panels, no chip cluster, no **Open AO3 Website**, and no navigation into `FandomListView`, so 1al / 1am / 1an are unreachable on macOS. The comment at `:344` describes this as an intentional compact row. Pull to refresh is wired. The footnote is **“Popular fandoms from AO3. Tap one to search its works.”**

**Smallest fix:** On macOS, push `FandomListView` from the category the way iOS does, even if the category row stays compact. A Mac reader otherwise cannot open the family list this batch redesigned.

---

### batch-5-15 — P2 — 1ao / 1ap — `AO3FilterPanel.swift:184`

**Artboard:** Reset is a 34px glass circle whose glyph is `#D9B26A` (the same gold as Apply’s fill `#D9B26A`, dark glyph `#26200f`). Title **Filters** `600 17px`. Apply is the magnifier on this board; 1au’s confirm is the check. Reset stays visible and dims when there is nothing to reset (the build note on the control).

**Code:** Reset is `Button(role: .destructive)` with `arrow.counterclockwise`, disabled when `!canReset`. The destructive role tints that gold arrow red. Apply is `.borderedProminent` with no subject tint, so it takes the app accent rather than the fandom gold the board fills it with. Placement (reset leading, apply trailing), the magnifier vs checkmark split (`:195`), and disabled-not-hidden are right.

**Smallest fix:** Drop `.destructive` on Reset (clearing filters is not a delete) and tint both circles with the subject accent: Reset glass with a gold glyph, Apply filled gold.

---

### batch-5-16 — P2 — 1aq / 1as — `AO3FilterPanel.swift:343` and `:403`

**Artboard 1aq:** a group labelled **Date updated**, then a separate group labelled **Language**. Date footer, in full: **“The picker and the two bounds all filter on the date AO3 revised the work, and AO3 requires all of them at once. “Past month” with a 2024 range returns nothing.”**

**Artboard 1as:** under Title and Creator, **“Searched as AO3’s own fields. The search box above also matches summaries and tags, so a creator looked up through it comes back noisier.”**

**Code:** Updated, After, Before, and the Language link share one `Section` with no header, so neither **Date updated** nor **Language** is labelled. The date footer (`:365`) is **“Updated and the After / Before dates all apply to the same date, and a work has to pass every one.”** Same meaning, and the sentence that teaches the failure (“Past month” plus a 2024 range) is gone. Title and Creator (`:403`) have the fields and no footer. The explanation exists only as a comment inside `typedSections`.

**Smallest fix:** Two sections, `groupLabel("Date updated")` and `groupLabel("Language")`. Put 1aq’s date sentence in the footer. Put 1as’s sentence under Title & creator.

---

### batch-5-17 — P2 — 1av / 1aw — `TagSelectField.swift:69` and `:352`

**Artboard 1av:** a pushed page. Back control is a gold chevron plus the word **Filters** (`400 15px`, `#D9B26A`). Title **Characters**. Search pill placeholder **Search Characters**. Section **Popular in Attack on Titan**. Footer: **“Shown because Attack on Titan is the only fandom set. Start typing to search every character tag on AO3.”**

**Artboard 1aw:** **Selected** chips, then **Results**, keeping AO3’s duplicate spellings as separate rows (**Eren Yeager**, **Eren Yeager (Anime)**, **Eren Yeager | Eren Jaeger**). Footer: **“AO3’s own spellings, including the ones that are the same character twice. Tap once to include, twice to exclude, a third time to clear.”**

**Code:** `TagSelectField` presents `TagPickerView` as a `.sheet` (`.large`, drag indicator) whose trailing control is a checkmark labelled **Done**. Nothing in the chrome reads **Filters**. `loadPopular` (`:336`) asks only `fandomContext.first`, and the section title names only that first fandom, with no footnote. Two included fandoms still produce **Popular in &lt;the first one&gt;**. `runSearch`’s `catch` sets `results = []` (`:353`), and the empty branch (`:187`) draws **No tags found for “\(query)”.** A failed autocomplete is indistinguishable from a real miss, and there is no retry. The parent tag-section footer has the tap-cycle sentence and not the spellings sentence.

The include/exclude grammar on the rows, the green selected capsules, the 300ms debounce, and the skeleton bars are right (checked below).

**Smallest fix:** Push the picker (back button **Filters**) instead of a sheet. Footer the popular list with the “only fandom set” sentence, and name every fandom that was actually queried — or query the one fandom and say so. On `catch`, show the error and **Try Again**, and leave `results` alone. Add the spellings sentence under Results.

---

### batch-5-18 — P2 — 1al / 1an — `FandomListView.swift:157`

**Checklist E.** An empty filter needs an empty state with an action.

**Code:** `loadedList` always draws the header and the sort rail, then `ForEach(displayedFamilies)`. There is no branch for `displayedFamilies.isEmpty`. A query or a filter that matches nothing leaves the header, the rail, and a blank list. The only `ContentUnavailableView` in the file is the load failure (**Couldn't load fandoms** / **Try Again**, `:101`).

**Smallest fix:** When the phase is `.loaded` and `displayedFamilies` is empty, show a `ContentUnavailableView` whose action clears the query and `filterOptions`.

---

### batch-5-19 — P2 — 1ax — `SaveSearchSheet.swift:63`

**Artboard:** included tags are green pills, excluded tags are red pills with a minus, facets are neutral pills (`border-radius:99px`, `400 12px`). The section label **What gets saved** is `600 11px`, tracking `.07em`, uppercase, with no count.

**Code:** included chips are `SubjectChip` `.neutral` and excluded chips are `.dashed` (radius-8 rects). The header is `SectionRuleHeader(title: "What gets saved", count: summary.count)`, so a badge appears that the board does not draw. This is the visual half of batch-5-1; fixing the missing rows without changing the chip style still will not match the sheet.

**Smallest fix:** Draw included tags with `includeColor`, excluded tags with `excludeColor` and the minus prefix, and facets as neutral capsules. Use `SubjectFieldLabel` `.formGroup` for the header and pass no count.

---

### batch-5-20 — P3 — 1au — `AO3FilterPanel.swift:162`

**Artboard:** **“14 of the 20 works on this page match”** (`400 12.5px`). The code’s shape matches that sentence, including the optional **“ · N not checked yet”**.

**Code:** `works` is pluralized and the verb is fixed: `"\(matching) of the \(total) \(works) on this page match"`. One work on the page reads **“1 of the 1 work on this page match”**.

**Smallest fix:** `matching == 1 ? "matches" : "match"` — or “matches” only when `matching != 1`. The noun is already correct.

---

### batch-5-21 — P3 — 1g / 1al — `MediaBrowserView.swift:394` / `FandomFamilyRows.swift:24` / `FandomClusterChip` (`SubjectScreen.swift:597`)

**Artboard 1g:** stat wrap is `gap:4px 14px`. Cluster chip names are `rgba(235,235,245,.88)` (`500 12.5px`), counts at 50% , radius 10, padding `7px 11px`, gap 7. A familiar chip has a `2.5×14` accent bar.

**Artboard 1al:** the member rule is `margin-left:21px` plus `padding-left:14px` and a `1.5px` border, so the rule sits 14pt to the left of the qualifier text. Family titles are `500 15px`.

**Code:** stats use `FlowLayout(spacing: 16, rowSpacing: 4)`. Cluster names are `palette.accent` (the comment at `:588` explains a borderless-button tint bug; the fix paints the name in the category accent, and the board paints it near-white). The member list is padded `.leading, 21` and the rule overlay is padded `.leading, 21` again, so the rule lines up with the qualifier instead of sitting 14pt to its left. Family titles are `.body.semibold` (~17pt). Cluster chips and `FilterTagChip` (`TagSelectField.swift:384`) have no `minimumHitTarget`; the drawn size is under 44pt. `minimumHitTarget` grows the hit area without growing the chip.

**Smallest fix:** Stat spacing 14. Cluster name at 88% primary, count at 50%. One leading inset of 21 on the member stack and a 1.5pt rule at that inset, with the text padded 14 beyond it. Family title 15pt medium. Add `minimumHitTarget()` on the cluster button and on `FilterTagChip`.

---

### batch-5-22 — P3 — 1aq — `AO3Models.swift:926`

**Artboard:** the Crossovers value reads **Exclude crossovers**. The Chapters value on that board reads **Multi-chapter**.

**Code:** `Crossover.exclude.title` is **Exclude** (`:926`). Chapters offers **Any** and **Single Chapter Only** only. The comment at `:965` is right that AO3’s form has a single-chapter checkbox and no multi-chapter-only counterpart, so **Multi-chapter** should not be added. **Exclude** versus **Exclude crossovers** is the label that does exist and does not match.

**Smallest fix:** Title `.exclude` **Exclude crossovers**. Leave Chapters as **Single Chapter Only**.

---

## Checked, matches

### 1g — Browse categories

- iOS is one full-width panel per category, `LazyVStack` spacing 18 (`MediaBrowserView.swift:118`). Panel radius is `SubjectMetrics.rowRadius` (16), glyph tile 32pt radius 9, title `400 15px`, heading gap 3 (`SubjectPanel`, `categoryPanel`).
- Jump Back In: kicker 8.5 with an 18×2.5 rule, card radius 14 padding 12 gap 8, title `600 14px`, works line `400 10.5px`, cap 3 (`jumpBackInLimit`). `SectionRuleHeader` is 11pt bold uppercase with a mono count and no chevron, because `onSeeAll` is nil (`SubjectSurface.swift:540`). The board’s header count **4** over three cards is the mock; the code counts the cards it shows. There is no further Jump Back In destination, so the board’s trailing chevron is not filed.
- Cluster: radius 10, padding 7×11, gap 7, familiar bar 2.5×14, two rows, dashed remainder. Compact `1.2K` on chips and stats follows PLAN D; the board’s exact **9,412** and **+24,804 more** are the mock. The remainder’s accessibility label is the exact figure (`:886`). The comment at `:688` still says the remainder is “stated exactly”; the UI is not, and PLAN D is the rule.
- Names on cluster chips are `parsedTitle` (bare). NBSP before `&` in category titles (`wrapSafeName`).
- Skeleton until counts land (`cardsReady`, `loadingStats` shaped like three stats plus a chip). Failure is **Couldn't load fandoms** / **Try Again**. Pull to refresh invalidates the cache first. iPad takes the iOS panels (`#if os(iOS)`).
- Not visually checked: safe area against the tab bar, Dynamic Type wrapping of a 15pt title, Reduce Motion on the shimmer.

### 1al / 1am — category list

- Header kicker **Browse**, title the category, tally **“9,412 tags in 8,106 fandoms · A–Z”** / **“N of M tags · most works”** via `FandomListTally` (`FandomListView.swift:817`). Subtitle size is the shared header’s 15.5, which is 1k’s size; 1al draws 13. Left on the shared component on purpose (checklist C), not filed.
- Sort rail **A–Z** / **Most works**, dashed **Filter** (and **Filter N** once filters are on — this page has no separate badge, so the count has somewhere to live). Search prompt **Search \(category name)**. Bottom search field on iOS.
- Most-works drops letter sections. Group variants defaults on (`@AppStorage` default `true`). Off uses `FandomFamily.ungrouped` and the tally stops claiming a fandom count (`families` nil).
- Multi-tag members: qualifier with parentheses and a leading `- ` stripped (`qualifierDisplay` path in `FandomListView`’s parser), each member’s count `.formatted()` and exact, chevron, hairline between members. **All N tags** is 11pt mono in the accent.
- Tilde on a summed total until `applyingExactCount` (`:92`). Family tap sends `includedFilterNames`, never the parsed title (`:246`).
- Skeleton, **Couldn't load fandoms** / **Try Again**, pull to refresh, subject wash. Zoom source keys match the works page.
- Chrome is an inline navigation title plus `.searchable`, not 1al’s three floating 34px circles. The overflow circle’s menu is not drawn on any board in this batch, so the missing circle is not filed as a missing action.
- Not visually checked: the vertical index’s safe area (the index itself is missing — batch-5-8), keyboard over the bottom search field.

### 1an — filter sheet

- Title **Filter**. Sections **Minimum works**, **Tag kinds**, **Yours**, **Grouping**. Switches: **Hide RPF tags**, **Hide All Media Types umbrellas**, **Hide Related Fandoms groupings**, **Favourited only**, **I have downloads from**, **Only fandoms with more than one tag**. British **Favourited** matches the board.
- Minimum segments **Any / 10+ / 100+ / 1,000+**. Caption **“\(n) tags in this category hold fewer than \(n) works.”** (`:130`).
- Counts are tags for the kind and library switches, families for the grouping switch (`familyCountLabel`). Multi-tag detail while Group variants is off: **“Turn on Group variants to use this”**, and the row is disabled.
- **Show \(n) tags**, 16pt semibold, accent fill, radius 14. **Reset** is disabled when `!options.hasActiveFilters`. Draft is copied on open and committed on Show (`FandomListView.swift:129`).
- The sheet does not disable **Show 0 tags**. The board does not show that state, so it is not filed.

### 1k — Search results (the Search tab)

- `SearchResultsHero` `.subjectPage`: kicker **Search results**, title **“\(total) works”** at 32pt bold, subtitle the subject at 15.5, sort pulled out of the chip rail into a menu beside the subject. Stat strip cells Works / Filters / Pages / Page, figures 13pt semibold, labels 9pt uppercase tracking 0.63 (`SubjectStatStrip`). Page is the highlighted cell. Totals are `.formatted()` (exact), which is what PLAN D asks of a prose total.
- Active chips are tinted rects. Sort is not among them (`nonSortFilterLabels`).
- First load is `AO3WorkRowSkeletonList`. Empty is `ContentUnavailableView.search`. Failure is **Search failed** plus the message plus **Try Again**. Pull to refresh, cancelled on tab change. Subject wash (not `subjectScreenWash`) is the documented tab-root choice.
- Pagination bar receives `resultsPalette`. The page sheet says **Go to page**, **Page number**, **of N**, **Nearby**, **First page**, **Last (N)**, tiles are 44pt, detents `[.height(430), .large]` (`SearchPaginationBar.swift`).
- Ledger meta units and exact counts match the board (batch-5-12 is the type, the kicker, and the chip tint). Date sits at the trailing end of the meta row. Expand is instant, on purpose, because animating a `List` row ghosts the old cell (`AO3WorkRow.swift:404`). That is not a Reduce Motion check; Reduce Motion was not exercised.
- `…` order for what this list can do: Mature when the setting is on, Select, Expand all. No always-on drag handle.
- Not visually checked: keyboard avoidance on the toolbar field, tab-bar overlap (the tab bar is hidden while Search is focused), Dynamic Type clipping of the 32pt total.

### 1ao / 1ap — filter chrome, rating, warnings, categories

- Sheet detents `[.medium, .large]` (`SearchView.swift:209`). Title **Filters**. Group labels go through `SubjectFieldLabel` `.formGroup`: 11pt semibold, tracking, uppercase (`AO3FilterPanel.swift:227`).
- **Sort by**, **Order** as a segment **Ascending / Descending** (hidden for Best Match), **Rating** titles **Any rating / General Audiences / Teen And Up / Mature / Explicit**. **Match** is **Exact / Rating+ / Rating−** and is hidden while rating is Any. **Include Not Rated** stays visible in both modes, including under Any, per `REDESIGN_DECISIONS` **1au.4**.
- Included row: `includeColor` at 10% behind the row, `plus.circle.fill` and **Include**. Excluded row: secondary title, strikethrough in `excludeColor` at 70%, `minus.circle.fill` and **Exclude**, no red row fill. Clear rows have neither label. The words stay, which is what the 1ap note asked for. **Underage Sex** matches the warning title (`AO3Models.swift:826`).
- Reset stays disabled rather than disappearing. Apply is disabled until `filters.isSearchable` in search mode.
- VoiceOver: `combinedAccessibilityRow` so a facet is one stop (`:567`).

### 1aq — status, dates, language

- Crossovers, Updated, and the date bounds are search-only. Completion and Chapters stay in Refine. After / Before toggles seed `Date()` rather than a silent old date (`:529`).
- The status footer is **“Crossover status is not carried on a search result, so it needs AO3 to answer the query.”** The board also says completion is missing from the blurb. The code comment at `:335` is the correction: every blurb carries completion, and Refine narrows by it. Not filed.
- **Multi-chapter** on the board is not an AO3 filter (`AO3Models.swift:965`). The control is **Single Chapter Only**. Not filed. The **Exclude** / **Exclude crossovers** label is batch-5-22.
- Language is a disclosure to `FilterLanguagePicker`. The missing group labels and the shorter date footer are batch-5-16.

### 1ar — language

- Title **Language**. **Any language** first, then `Language.allCases` by native name. Prompt **Search \(N) languages** where N is `allCases.count - 1`. Checkmark on the selection. Match is diacritic-insensitive on the title and the id (`FilterLanguagePicker.swift:64`). Searchable on iOS and macOS.

### 1as — tags, title, creator

- Rows **Fandoms**, **Characters**, **Relationships**, **Additional Tags**, in that order. Fandoms hidden when `showFandomPicker` is false (the Browse fandom page). Summary **Any**, or **N included · M excluded** with the middle dot (`TagSelectField.swift:24`). The board’s **2 included · 1 excluded** is that string.
- Chips under the row are green/red capsules with plus and minus, strikethrough on exclude, and a tap cycles clear → include → exclude. That matches 1as and 1aw’s selected chips.
- Tag-section footer is the board’s sentence, exactly: **“Tap a tag once to include it, twice to exclude it, and a third time to clear it.”**
- Title and Creator are search-only. Creator turns off autocapitalization and autocorrection on iOS. The missing footer is batch-5-16.

### 1at — ranges

- Search shows Word count, Hits, Kudos, Comments, Bookmarks. Refine keeps Word count and hides the other four (`:435`).
- Each range is a slider plus From / To. Placeholder **Any**. Fields are mono 14, radius 8. Thumbs are 22pt and call `minimumHitTarget()` (`FilterRangeSlider.swift:103`).
- Footer, exact: **“Leave a handle where it is for an open bound. AO3 reads one-sided ranges as “more than” and “fewer than”.”** In search it sits on Bookmarks (the last range); in Refine it sits on Word count.
- **Save Search…** with a bookmark icon, at the bottom, disabled until `filters.isSearchable`, only when `onSave` is set. Search passes `presentSaveDialog`. The fandom-works panel does not, so Save Search is a Search action, which is where 1at draws it.

### 1au — Refine

- Title **Refine**. Confirm is the checkmark, accessibility **Done**. Live line is 12.5pt secondary, hidden when the source page is empty, and it does not invent a count in search mode (`:145`).
- Hidden in Refine, matching the caption: Sort, Order, Crossovers, Updated, date bounds, Title, Creator, Hits, Kudos, Comments, Bookmarks. Kept: rating, match, Include Not Rated, warnings, categories, completion, chapters, language, word count, tags.
- The grammar slip on a one-work page is batch-5-20.

### 1av / 1aw — tag picker

- Empty query with no fandom: **“Type above to search AO3 characters.”** and **“Add a fandom and this opens on its most-used characters.”** Fandom-kind keeps the one-line prompt (`TagSelectField.swift:241`). That is the no-fandom state the 1av note asked for.
- Loading is four skeleton bars (widths 220 / 160 / 190 / 130), not a spinner. The “Loading…” / “Searching…” strings are ignored by `loadingRow`, which matches the build note.
- Debounce is 300ms inside `.task(id: query)`. Results are whatever autocomplete returns, so duplicate spellings stay separate rows. Include wash and Include / Exclude labels match `cyclingFacetRow`.
- The sheet-versus-push chrome, the missing footnotes, the first-fandom-only popular list, and the error that looks like an empty result are batch-5-17.

### 1ax — save sheet, besides the summary

- **Cancel**, title **Save Search**, **Save** disabled when the trimmed name is empty. Footnote exact: **“Named from what the search is of. Rename it to anything.”** Name is seeded from the subject (`SearchView.swift:790`). Empty-summary fallback **“This search has no filters yet — only its name will be saved.”** is not on the board; it is the honest line when there is nothing to list, and it is not filed.
- The missing facets are batch-5-1. The chip colours and the counted header are batch-5-19.

### Checklist items verified as shared

- `SubjectHeaderBlock` 32 / 15.5, `SectionRuleHeader` 11 bold uppercase, `SubjectChip` radius 8 for state and a capsule for a pill, `SubjectStatStrip` 13 semibold / 9 uppercase. Search’s results page uses them. Browse’s fandom works page does not (batch-5-13).
- Card rows: radius `CardRadius.listRow`, inner padding 16 (`AppThemeSurface.swift:205`). 1k’s card padding is `16px 18px` and radius 16. Horizontal inset differs by 2pt; not filed on its own.
- Counts over 999 on Browse chips and stat lines use compact notation. Pagination, the 1k hero total, fandom-list member counts, and the Refine sentence stay exact.
- Hide Mature appears in the works `…` menu only while the setting is on (Search, fandom works, tag works).
- No screen in this batch shows a permanent drag handle or a “Drag to reorder” hint. AO3 result lists have no reorder.
- Delete does not apply to these screens: Browse and Search do not hold user-owned rows. Saved searches were not in this batch’s artboards.
- Keyboard avoidance, floating tab-bar overlap, and Reduce Motion were not exercised. Shimmer is on the Browse and tag skeletons; whether it checks Reduce Motion was not read.

---

## Three that matter most

1. **batch-5-1** — Save Search prints the tags and the rating and then stops. The sheet’s only job is to show the search the reader is about to keep, and the footer that says sort is always shown is missing along with the sort.
2. **batch-5-2** and **batch-5-3** — “Downloaded” is defined as on disk now, and neither the filter nor the category stat uses that. One hides the wrong fandoms; the other counts every library work.
3. **batch-5-13**, with **batch-5-6** and **batch-5-7** — Search results grew the 1k subject page, and the fandom a reader actually opens from Browse is still the old card hero and the old row. The list they tapped through still treats a one-tag fandom as a different row, and it never shows the star or the download count the index already computed.
