# Batch 8 — Writing polish audit (Grok)

Repo: `integrate/cloud-redesign`. Read-only. Spec: `docs/design/Final_Redesign_Spec.dc.html` (caption plus inline styles, px = pt). Checklist A–G from `.claude-overnight/polish/PLAN.md`. Line numbers from this worktree. No build, no simulator, no AO3 traffic — nothing here was seen on a device. Where `docs/REDESIGN_DECISIONS.md`, `docs/REDESIGN_PLAN.md`, or an in-code owner comment already supersedes an artboard, that is under the screen’s checked list, not filed as a defect to revert.

Artboard → code map:

| Artboard | Screen | Primary files |
|---|---|---|
| 1u | Own Works | `AuthorProfileView.swift`, `AuthorProfileContentSections.swift`, `WorksScopeAndSort.swift`, `AO3WorkRow.swift`, `AuthorDashboardSections.swift` |
| 1v | Works sort and filter | `AO3FilterPanel.swift` (`worksSortSections`), `AO3WorksSort.swift`, `WorksScopeAndSort.swift` |
| 1w | Series | `AuthorProfileContentSections.swift` (`AO3AuthorSeriesSection`), `AuthorProfileComponents.swift` (`AO3SeriesRow`) |
| 1x | Drafts | `WritingDraftsView.swift` |
| 1bn | Select + Edit Multiple | `AuthorProfileView.swift`, `OwnWorksBulkBar.swift`, `EditMultipleWorksView.swift` |
| 1bo / 1bs | Work edit + draft editor | `WorkEditView.swift`, `WritingChaptersView.swift`, `WritingPreviewView.swift` |
| 1bp | Edit Tags | `EditTagsView.swift`, `WritingFormFields.swift` |
| 1bq | Add Chapter | `AddChapterView.swift` |
| 1br | Series edit + reorder + remove | `SeriesEditView.swift` |
| 1bt | Account hub scopes | `AccountView.swift`, `AccountShortcuts.swift` |
| 1bu | Tag picker | `WritingTagsEditor.swift`, `AO3TagAutocomplete.swift` |
| 1bv | Chapter text editor | `WritingTextEditor.swift`, `WritingNativeTextView.swift` |
| 1bw | Collections, gifts, series | `WorkAssociationPickers.swift` |

Shared chrome: `SubjectHeaderBlock`, `SectionRuleHeader`, `SubjectChip`, `SubjectStatStrip` (value 13pt semibold, label 9pt uppercased tracking 0.63, inside `.subjectPanel()` — `SubjectSurface.swift:790`), `cardRow`, `FilterButton`, `SearchPaginationBar`.

---

## Findings

### batch-8-1 — P2 — 1u — `AO3WorkRow.swift:208` / `:340` / `AuthorDashboardSections.swift:190` / `WorkStatLabel.swift:1043`

**Artboard caption:** “Rows carry the corrected WorkStatusIconGrid signals over the 1c hairline treatment, with each work’s own stats as a signal strip … the chapter count sits against the word count in the metadata line.”

**Frame:** tag pills are on the collapsed card (**Slow Burn**, **Hurt/Comfort**, **Canon Divergence**). The meta line is **English · 14/24 chapters · 84,200 words** with **Updated 3d ago** (and **Posted 2 Mar 2026** on the complete work) at the trailing end. **Series**, **Gift**, and **Complete** sit beside the fandom kicker. There is no author byline.

**Code:** own works use `AO3WorkRow` presentation `.searchLedger` (`AuthorDashboardSections.swift:185`) plus `AO3AuthorPerformanceStrip` (`:179`, `:283`). The strip is the caption’s signal strip: `SubjectStatStrip` cells labelled Kudos, Comments, Hits, Bookmarks (`AuthorDashboardSections.swift:218`). Keep it. The rest of the card is the search ledger. Title is `.title3.weight(.semibold)` (`AO3WorkRow.swift:235`). The byline is drawn (`:239`). Freeform tags render only inside `expanded` (`:273`). `ledgerMetadata` (`:340`) is language, then words, then the raw chapter string (`14/24`, with no “chapters”), and it drops the four counts when the strip is showing. The date on that same line is `WorkStat.displayDate` (`:312`, `WorkStatLabel.swift:1043`), which prints `MM/dd/yyyy` and does not say **Updated** or **Posted**. The accessibility label does prefix “Updated”. `giftLine` is `"Gift for " + recipients` (`AO3Models.swift:48`) and `AO3AuthorWorkCard` draws it as a `WorkStateBadge` under the card (`AuthorDashboardSections.swift:190`). The comment at `AO3WorkRow.swift:224` still says no gift flag is parsed. Completion stays inside `WorkStatusIconGrid` (`:249`), which is what the caption asks for.

**Smallest fix:** On the own-works ledger, use the 1c hairline: fandom kicker, rule, title, no byline. Put the chapter count against the word count (`14/24 chapters · N words`). Prefix the relative date (**Updated** / **Posted**). Draw the frame’s tag pills on the collapsed card. Move the gift mark up beside the kicker as **Gift**. Leave `AO3AuthorPerformanceStrip` and the icon grid.

---

### batch-8-2 — P2 — 1u / 1x / 1w — `AuthorProfileView.swift:293` / `:750` / `WritingDraftsView.swift:52`

**Checklist B:** Add is a “+” glass toolbar button. The “…” order, when a menu is present, is Show/Hide mature, then Select, then Reorder, then the display-mode picker, then Expand/Collapse all, then page items, then a destructive item last.

**Artboard:** 1u’s caption puts “the sort funnel” in the glass chrome. The 1u frame’s trailing glass buttons are Select (checklist), the funnel, and a plus. There is no ellipsis on that frame. 1x’s **New work** is the way a draft is started. 1w’s empty state is the series action.

**Code:** **New work** is a `SubjectChip` under the hero (`AuthorProfileView.swift:294`), shown when `showsDashboard || selectedTab == .works`. The toolbar is `ActionToolbar` of **Select Works** plus `profileMenu` (`:751`). The menu (`:782`) leads with **Open on AO3** and **Share Profile**, then web actions, then the display-mode picker and **Expand All** (hidden in compact), then `MatureRevealToggle` only when Hide Mature is on. Select is omitted from the menu while the toolbar button is showing (`:797`). The funnel is `FilterButton` in the scope row (`WorksScopeAndSort.swift:96`), accessibility **Sort and filter**. Drafts put **New work** in a `SubjectFormRow` (`WritingDraftsView.swift:52`) and call `hidesNavigationBarChrome()` (`:119`). The series list has no toolbar plus.

**Smallest fix:** A glass toolbar plus on Own Works, Drafts, and Series, pushing the destination that chip and row already push (`WritingWorkDestination` for a work; the series empty action for a series). Put the funnel in that same chrome, with the badge it already computes. Rebuild `profileMenu` in the checklist order, and keep it only for the items that have no other home. Mature stays first whenever Hide Mature is on.

---

### batch-8-3 — P2 — 1bn — `AuthorProfileContentSections.swift:412`

**Artboard:** select mode is hairline rows. Fandom, then the title, then one line: **12 chapters · 84,120 words · 3,812 kudos**. The header is **Your works** and **3 / 12**. The bar is **Edit 3**, **Collections**, **Visibility**, **Delete**. The title bar is **3 selected** and **Select All**.

**Code:** `selectableWorkRow` builds `AO3WorkRow` with the default presentation `.standard` (`AO3WorkRow.swift:22`) and does not pass `.searchLedger`. The header, the `n / n` count (`selectionCountText`, `:350`), the title `"\(count) selected"` (`AuthorProfileView.swift:767`), Select All (`:735`), and the bar labels (`OwnWorksBulkBar.swift:14`) match. The row does not.

**Smallest fix:** In select mode, draw the hairline: fandom, title, `N chapters · N words · N kudos`, and the selection bubble the row already has. Leave the bar and the header.

---

### batch-8-4 — P2 — 1w — `AuthorProfileContentSections.swift:520` / `AuthorProfileComponents.swift:181`

**Artboard caption:** “Each row carries the spine stack, the series state, and how many of its works are posted.”

**Frame:** a 38×38 spine, the fandom kicker, **Complete** / **Restricted**, the title, the summary, the running order of member titles, then **4 works · 138,000 words · 62 bookmarks** and **Updated 3d ago**. Swipes are **Edit** nearer the card and **Reorder** at the edge.

**Code:** `@AppStorage("authorProfile.displayMode")` defaults to `.detailed` (`AuthorProfileView.swift:14`). The series section passes `.ledger` only when the mode is `.ledger` (`AuthorProfileContentSections.swift:522`). The default is `standardBody` (`AuthorProfileComponents.swift:282`): headline title, byline, fandoms as a caption joined with commas, summary, then a flow of stat chips. `ledgerBody` (`:181`) has the spine, the coloured kicker, the **Complete** / **Restricted** badges, the 22×2.5 rule, the 19pt title, the 13.5 summary, and the **N works · N words · N bookmarks** line. Swipes match the frame (`:541`: Reorder at the edge, Edit nearer, `allowsFullSwipe: false`).

**Smallest fix:** Default this list to `ledgerBody`. The display-mode picker can still offer the other layouts. Posted-of-total and the inline running order stay out (see checked): the blurb has neither a posted count nor member titles.

---

### batch-8-5 — P2 — 1bp — `EditTagsView.swift:213` / `WritingFormFields.swift:81`

**Artboard:** the four sets, in order, are **Fandoms**, **Relationships**, **Characters**, **Additional tags**. Each is its own headed group, the count sits with the heading, the chips are under it, and **Add** is the last chip. The same order is on 1bo’s Tags group and on 1bn’s **Tags to add** / **Tags to remove**.

**Code:** `tagsRows` is Fandoms, Characters, Relationships, Additional tags (`EditTagsView.swift:214`). `inlineChips` (`WritingFormFields.swift:81`) puts a 15pt label and a trailing **None** / count inside one Tags card, then a `FlowLayout` of chips with an xmark and a dashed **Add**. The add and the remove-on-chip match the caption (“chips with an add affordance”). The order and the four headings do not. 1bo’s tag rows and 1bn’s `tagRows` use Relationships then Characters.

**Smallest fix:** Swap Characters and Relationships so this page matches 1bo and 1bn. Give each set a `SectionRuleHeader` with the count, and keep the chips and the **Add** chip underneath.

---

### batch-8-6 — P2 — 1bo / 1u / 1bn — `WorkEditView.swift:217` / `AuthorProfileView.swift:85` / `OwnWorksBulkBar.swift:33`

**Checklist B:** a destructive action uses the shared `destructiveConfirmation`.

**Artboard 1bo:** the alert is **Delete “The Weight of Water”?** The message is **All 12 chapters, 3,812 kudos and 214 comments are removed from AO3, and the work leaves the collection it belongs to. Bookmarks other people made will break. This cannot be undone.** The button is **Delete on AO3**.

**Code:** a posted work’s dialog title is **Delete Work?** (`WorkEditView.swift:218`), with no quoted title. A draft’s title is **Delete this draft?** and its button is **Delete draft**, which match 1bs. The posted button is **Delete work on AO3**. The message is `deleteImplications.cautionText` when the prefetch succeeded (`:227`). That string is AO3’s own caution paragraph (`AO3Client+Works.swift`, `parseDeleteImplications`); the parsed chapter, kudos, comment, bookmark, and word counts are not composed into the artboard’s sentence. If the load fails, the user gets the save-error alert and no delete dialog. The own-works swipe (`AuthorProfileView.swift:85`) does name the work — **Delete “Title”?** — and its message says the delete removes “chapters, kudos, comments and bookmarks.” The bulk alert uses that same sentence, pluralised, and names every title (`OwnWorksBulkBar.swift:27`). None of the three calls `destructiveConfirmation`.

**Smallest fix:** One confirmation helper. Title it **Delete “Title”?** (or **Delete N works?**). For a posted work, compose the counted sentence from the fields already parsed, including the bookmark line the artboard uses (**Bookmarks other people made will break**). Keep AO3’s caution as the fallback when the parse has no counts. Point the swipe, the bulk bar, and the edit form at that helper.

---

### batch-8-7 — P2 — 1bs / 1bo — `WorkEditView.swift:411` / `WritingTextEditor.swift:503`

**Artboard 1bq**, the same row the work form uses for prose: an empty chapter reads **Empty — opens the editor with plain text, AO3’s HTML tags, or a paste from elsewhere.**

**Code:** `WritingTextEditorRow.detail` returns `"Empty — \(emptyHint)"` only when `emptyHint` is set and the text is empty (`WritingTextEditor.swift:507`). Otherwise an empty field is the one-line value **Empty**, and a filled field that does not preview is **Set** (`:491`). Add Chapter passes `emptyHint` on **Chapter text** only (`AddChapterView.swift:221`). Work Edit’s **Beginning notes**, **End notes**, and **Work text** pass neither `emptyHint` nor `previewsText` (`WorkEditView.swift:415`). **Summary** does preview (`previewsText: true`, `:412`), so a filled summary shows stripped text. The draft post group also inserts **Preview on AO3** (`:705`). That screen is a decision to build (`REDESIGN_DECISIONS.md:62`); the empty-row copy is the defect.

**Smallest fix:** Pass the 1bq empty hint (or a one-line cousin) on Work text, Beginning notes, and End notes, on both the work form and the chapter form. Leave Summary’s preview.

---

### batch-8-8 — P2 — 1bw — `WorkAssociationPickers.swift:73` / `:374`

**Artboard caption:** “The series picker separates placing this work from reordering the series, since the first writes one work and the second writes all of them.”

**Frame:** under **Position in Water**, **Place this work** reads **2nd of 3**, and **Reorder the series** reads **3 works**. The footnote is “changing it here writes one work and leaves the others alone.” **Also on this work** always shows **Inspired by** **1 work** and **Translations** **None**.

**Code:** the position section (`:374`) has **Reorder the series** and the footnote that order saves on the reorder screen. There is no **Place this work** row. `detailText` (`:478`) already produces **3 works · this work is 2nd** as the series row’s subtitle when the form carried the numbers; that line does not edit the position. `AO3SeriesMembership` stores `position` and `workCount`. **Also on this work** is drawn only when `parentWorkCount > 0`, and the only row is **Inspired by** (`:73`). **Translations** is not on this screen. The toggle **This work is a translation** lives on `WorkParentWorkPickerView.translationPanel` (`:689`), reached from the work form’s Inspired by row. Work Edit passes a parent count of 0 or 1, so a work with no parent hides the section.

**Smallest fix:** Add **Place this work** with the ordinal the membership already has, posting that one work’s position, and keep **Reorder the series** as the all-works write. On Collections and gifts, always show **Also on this work**: **Inspired by** with its count or **None**, and **Translations** reading **None** or the translation state, opening the picker that already owns the toggle.

---

### batch-8-9 — P2 — 1bu — `WritingTagsEditor.swift:232`

**Artboard:** **Recently used** and **From your other works** are rows. Each name has a green **Canonical** badge. The caption of that second screen calls them local conveniences, which the code’s comment agrees with (`:230`).

**Code:** `convenienceChips` is a `FlowLayout` of dashed `SubjectChip`s with a plus (`:232`). They add on tap. They do not show **Canonical**, and they have no count. Chosen chips above them are draggable `SubjectChip`s with an xmark (`:183`), which matches “the chips are draggable.”

**Smallest fix:** Draw those two groups as the suggestion row already used underneath (name, **Canonical** badge), still adding locally and still fetching nothing. Leave the chosen chips as chips.

---

### batch-8-10 — P2 — 1br — `SeriesEditView.swift:204` / `AO3Client+Authors.swift:185`

**Artboard:** the row is **Delete series on AO3**, in the same destructive slot as 1bo’s **Delete work on AO3**.

**Code:** the comment (`SeriesEditView.swift:21`) says delete is an open-on-AO3 link and that the delete belongs on AO3’s confirm page. The row does not pass `isDestructive`, so it is not red. The action is `openURL(series.url)` (`:206`). `series.url` is the public series page: the blurb’s `h4.heading a[href*='/series/']` (`AO3Client+Authors.swift:186`). Tapping the row opens the series the reader is already editing. 1bo’s **Delete work on AO3** is red and deletes after a confirm (`WorkEditView.swift:518`).

**Smallest fix:** Open AO3’s series delete page, if that URL is known, and mark the row `isDestructive`. If the only honest destination is the public series page, relabel the row so it does not read as the same control as the work delete. Do not add a native series delete; the comment is right that the app has no series-delete call.

---

### batch-8-11 — P2 — 1bt — `AccountView.swift:1114` / `:1134`

**Artboard:** the Writing device lists **Works**, **Series**, **Drafts** (**Deleted by AO3 after 30 days**), and **Performance** / **Dashboard** with the subtitle **Kudos, comments, hits and bookmarks per work**. The Activity device’s Inbox subtitle is **3 awaiting a reply**. The build note says every row is a screen that already exists.

**Code:** `writingRowOrder` is works, series, drafts (`AccountView.swift:134`). The drafts subtitle is exactly **Deleted by AO3 after 30 days** (`:1118`). There is no Dashboard row in the group. Dashboard exists as `AccountShortcut.dashboard` (`AccountShortcuts.swift:10`, title **Dashboard**) and as `Route.dashboard` (`AccountView.swift:59`, `AO3DashboardView` at `:460`). A shortcut the reader removes is then gone from the hub. Inbox’s subtitle is `"\(unread) unread"` when `inboxModel.unreadCount` is non-nil (`:1137`). Batch 7’s inbox hero already distinguishes comments, unread, and awaiting a reply.

**Smallest fix:** Add **Dashboard** to the Writing group, subtitle **Kudos, comments, hits and bookmarks per work**, opening `Route.dashboard`. Point the Inbox row’s subtitle at the same “awaiting a reply” count the inbox hero already formats, and keep the unread count beside it when both exist. Leave the pills and the inner headings flattened (see checked).

---

### batch-8-12 — P3 — 1u — `AuthorProfileContentSections.swift:343` / `AuthorProfileView.swift:269` / `AO3WorkRow.swift:239`

**Artboard:** the page title is **Works**. The scope pills are the only second **Works**. Rows have no byline.

**Code:** the section header still says **Works** under a page titled Works (`AuthorProfileContentSections.swift:343`). `AO3AuthorFandomFilterSection` is inserted above the list on every profile (`AuthorProfileView.swift:269`) while the sort sheet already has Fandoms. The search-ledger byline is on every own-works row (`AO3WorkRow.swift:239`).

**Smallest fix:** Drop the redundant **Works** header on this page. Keep the fandom rail only when a fandom is selected, as a removable chip. The byline goes away with the hairline in batch-8-1.

---

### batch-8-13 — P3 — 1w — `AuthorProfileContentSections.swift:480`

**Artboard caption:** “the empty state as one card with the AO3 action.” 1az, the locked empty of this screen, says the same: one card.

**Code:** a text card, **You have not made a series.** at 18pt semibold plus a 13.5pt explanation (`:481`), then a second card, `AccountExternalNavCard` **New series on AO3** (`:495`). The footnote says **Opens archiveofourown.org in Browse**, which is the true destination (the same correction as batch 7’s external rows). The comment at `:492` already rejects 1az’s “Safari”.

**Smallest fix:** One card: the sentence, then **New series on AO3**. Keep the Browse footnote.

---

### batch-8-14 — P3 — 1x — `WritingDraftsView.swift:60` / `:136`

**Checklist E:** loading is a skeleton shaped like the content.

**Artboard notice:** **Please note: unposted drafts are deleted after 29 days. The chip on each draft is time left, not time since.**

**Code:** the first load is `ProgressView("Loading drafts…")` (`:60`). Failure is a footnote plus **Retry** (`:67`). The notice (`:138`) is the 30-day sentence plus the recovery-copies sentence, in an orange rounded rect. The chip itself says **N days left** (`DraftExpiry.chipText`). The “time left, not time since” sentence is not in the notice. The 30-day figure is the documented correction of the frame’s 29 (see checked).

**Smallest fix:** A skeleton of two draft cards while `isLoading` and the list is empty. Add one clause to the notice: the chip is time left. Keep 30 days.

---

### batch-8-15 — P3 — 1bv — `WritingTextEditor.swift:97` / `:253`

**Artboard:** the bar is the short set (italic, bold, paragraph, break, rule, link, quote). The footnote under it matches the code’s footnote (`:106`).

**Code:** the iOS bar (`:253`) groups every `AO3MarkupTag.writing` case under **Text** and **Blocks & links**. The test count is 17. Each button is the tag in caption monospaced over the lowercased name. An extra line above the bar reads **Local recovery · Save on the work form** (`:97`). macOS uses a **Format** menu with the same tags. The serif body, the word count on the rule, paste-as-plain, and the preview toggle match OD1 (see checked).

**Smallest fix:** Lead the bar with the seven tags the frame draws, and put the rest behind one more button. Drop the **Local recovery** line, or move it into the overflow where recovery already lives.

---

### batch-8-16 — P3 — 1br — `SeriesEditView.swift:301` / `:370`

**Checklist B:** no “Drag to reorder” hint. The artboard’s reorder row is a 15pt index and a 15pt title.

**Code:** the header subtitle is **"{title} · drag to change the reading order"** (`:301`). iOS forces `editMode` active (`:353`), which is right for a screen whose only job is reordering, so the handles stay. The index is 13pt semibold monospaced (`:371`) and the title is 14.5pt medium (`:376`). **Save** sends the whole order once (`:359`).

**Smallest fix:** Drop “drag to change the reading order” from the subtitle; the numbers and the handles already say it. Set the index and the title to 15pt.

---

## Checked, matches

### 1u — Own Works

- Header kicker **AO3 Account**, title **Works**, subtitle **N works · N words · N kudos** when `/users/:id/stats` has landed (`AuthorProfileView.swift:326`). The count is dropped under In collections and Gifts (`:311`). Series zero reads **No series yet** (`:325`). Words and kudos are not invented before the fetch.
- Scope pills **Works** / **In collections** / **Gifts** (`WorksScopeAndSort.swift:12`), only on your own profile. The **New work** chip and the scope chips use `minimumHitTarget()`.
- Fandom kicker uses `FandomDisplayName.bareTitle` (`AO3WorkRow.swift:386`).
- Swipes, `allowsFullSwipe: false`, edge inward: **Delete**, **Chapter** (only when `isComplete != true`, `:371`), **Tags**, **Edit** (`:383`). That is the frame footnote: Edit, Edit Tags, Add Chapter on a work in progress, Delete. The host confirms delete before the write (`AuthorProfileView.swift:85`). The copy is batch-8-6; the confirm exists.
- The performance strip follows the caption’s “signal strip.” Replacing it with the frame’s inline “1,204 kudos” sentence would fight the caption. The row around it is batch-8-1.
- **Complete** lives in `WorkStatusIconGrid`, which is where the caption puts it.
- Loading is `AO3AuthorLoadingRows`. Empty works: **No works** / **AO3 has no visible works for this author scope.** Failed: an inline error plus the profile **Try Again**. Pull to refresh (`:275`). The list hides the floating tab bar.
- Select is its own toolbar button on own works when the list is non-empty (`:772`). Select All covers loaded works only (`:732`).

### 1v — Sort and filter

- Decision: one sheet, the same shape as Search (`REDESIGN_DECISIONS.md:58`). Facets apply live; sort commits on the checkmark. That live behaviour is the shared panel, not a defect.
- Caption: sort is one radio group, direction is a segmented pair, completion is chips. The code does those three. Nine columns, and the caption string **9 fields**, match `AO3WorksSort`.
- The action bar is icon-only: Reset is `arrow.counterclockwise`, accessibility **Reset filters**, and it clears facets; the confirm is a checkmark, accessibility **Apply** (`AO3FilterPanel.swift:170`). The caption says Cancel and Apply. The Reset behaviour is the panel’s own comment. Not reverted.
- The funnel’s badge counts an active sort plus an active refine. Its placement is batch-8-2.

### 1w — Series

- Hero tally uses `seriesTallyParts` (`AuthorProfileComponents.swift:544`): exact works and words from the loaded blurbs, or “N works, N words in the M loaded series” when the list is partial. It does not invent a zero.
- Swipes match (batch-8-4). Creators only (`series.isCreator`).
- **Posted-of-total** is the caption’s third fact and the build note says it is not parsed. `AO3SeriesSummary` (`AO3AuthorModels.swift:458`) has `workCount` and no posted count. Not invented.
- The inline running order is on the frame. `AO3SeriesSummary` has no works array, so the index cannot draw member titles (`docs/REDESIGN_PLAN.md` records the same limit). Not invented. The reorder screen is where the order is edited.
- Other authors see **No series**. Loading is `AO3AuthorLoadingRows`. The empty state’s Browse footnote is the true destination (batch-8-13 is the two cards).
- Ledger stats line, when that presentation is on, is **N works · N words · N bookmarks** at 11.5pt (`AuthorProfileComponents.swift:233`). The date keeps AO3’s own string (`dateUpdated` is stored as printed, `:470`).

### 1x — Drafts

- Header: kicker **AO3 Account**, title **Drafts**, subtitle from `draftsTally`: **N drafts**, plus **· N expiring this week**, and a page clause when paged. The expiring count is drafts on this page whose deletion date parsed.
- **1x.3** Post and Delete swipes: decision is no, stay in the editor (`REDESIGN_DECISIONS.md:61`). The card has no such swipe. Tap opens `WritingWorkDestination`. Deleting asks on the editor. Checked, not a revert.
- Expiry chip: **N days left** (`DraftExpiry.chipText`). Colours (`WritingDraftsView.swift:240`): three days or fewer red, within the week orange, otherwise mint. The frame’s 6 days is orange and 22 is mint. The last day is not **0 days left**.
- Created line is **Created** plus a locale date (`:296`). Word count only. The chapter count is omitted on purpose (`:219`): AO3’s draft blurb always prints 1 before the slash, which would lie about a multi-chapter draft.
- The 30-day notice replaces the frame’s 29. The comment (`:129`) cites otwarchive keeping a 29-day draft and purging a 31-day one. Keep 30. The missing “time left” clause and the spinner are batch-8-14.
- Empty: **Works you save as drafts appear here.** with **New work** above it. Error has **Retry**. Pagination is `SearchPaginationBar` when `totalPages > 1`. Pull to refresh, and the chip clock updates when the scene becomes active and when the day changes.
- The card’s title is 19pt semibold, the summary is 13.5pt limited to 3 lines, and an empty title reads **Untitled**. No kudos and no hits, which is the caption.
- Signed-out behaviour of this screen was not read. Not claimed.

### 1bn — Select and Edit Multiple

- Bar labels **Edit N**, **Collections**, **Visibility**, **Delete** (`OwnWorksBulkBar.swift:14`). Delete asks, names the count and every title, and is never pre-selected. That is the decision (`REDESIGN_DECISIONS.md:59`). The sentence those alerts use is batch-8-6.
- Edit Multiple title **Edit 1 work** / **Edit N works**. Subtitle is the titles joined by commas. The intro says the field stays untouched on every selected work (`EditMultipleWorksView.swift:62`). **Change on all** (`:86`) generalises the frame’s **Change on all three**. Not a defect.
- Tag groups, both add and remove: Fandoms, Relationships, Characters, Additional tags. Rating and Language are **Leave as is**.
- Warnings and categories are tri-state menus, not switches. The comment (`:275`) says AO3’s `edit_multiple` offers keep / on / off, and a switch cannot represent “leave as is.” Checked.
- **Gift recipients** is on the page, disabled, value **Per work** (`:266`). AO3’s edit_multiple form has no gift field. Checked.
- **Remove me as a co-creator** (`:324`) replaces the frame’s **Remove co-creators**. The field is `remove_me`, self only. Checked. **Add co-creators** placeholder is **Pseud**.
- Collections: Add is a name field. Remove is disabled at **None** when AO3 sent no current collections.
- Comments are three **Leave as is** / **On** / **Off** rows. Save and Cancel are in the toolbar. Focus scrolls to Collections and gifts, or Comments and visibility.
- The select-mode row is batch-8-3. The header **Your works** and **n / n** match.

### 1bo / 1bs — Work edit and the draft editor

- Titles: **New work**, **Draft**, **Edit work** (`WorkEditView.swift:746`). Draft subtitle appends **never posted**; a posted work appends **N chapter(s)** (`:393`). The posted date and “saved 2 minutes ago” are absent because the form has neither. `WritingTextRecovery.savedAt` belongs to the editor’s recovery sheet. Checked.
- Groups, in order: **Required** / **Required before posting**, Tags, Association, Text, **Publication** / **When posted**, then the delete or post group. Required rows: Title, Rating, Archive warnings, Fandoms, Language, with required marks on title, warnings, and fandoms. Tag row order here is Categories, Relationships, Characters, Additional tags.
- The tags footnote is **Tags can also be edited separately from the work text.** It does not point at 1bq. The spec caption that names 1bq for this page is the wrong artboard.
- Association: Series value is the names, **Adding …**, or **None** (`seriesValue`, `:687`). It is deliberately not **Water, 2 of 3**; the work form posts no position (the place for that is batch-8-8). Collections and gifts share one push. Co-creators reads **N**, **N + 1 invited**, or **None**. Inspired by reads **1** or **None**, on drafts too.
- Posted text rows add **Chapters**, **Add chapter**, **Edit tags**, then **Work skin** with the blank option renamed **Default**. Drafts and new works get **Work text** instead. Those two extra rows are how 1bq and 1bp are reached.
- Publication: posted works get **N of** plus an editable total, and **Work is complete** writes the total or clears it (`:631`). Then the backdate, the date picker only while backdate is on, registered-only, comment moderation, and who can comment. Drafts skip the chapter-total rows (`:470`). The chapters-posted footnote shows only when the work is posted.
- Post alert: **Post this work?** Button **Post work**, or **Fill in what is missing** when `missingRequiredFields()` is non-empty, and that button does not post. The message names the missing fields (**a title**, **an archive warning**, …) and says posting notifies subscribers and cannot be undone. The subscriber count is omitted on purpose (`:754`).
- Toolbar Save posts an update for a posted work and saves a draft otherwise. The error alert is **AO3 could not save the change**.
- Draft post group: **Post work**, **Preview on AO3** (a built screen, `REDESIGN_DECISIONS.md:62`), **Delete draft** when the work has an id. The empty-row copy is batch-8-7. The delete title for a draft matches 1bs.

### 1bp — Edit Tags

- Header: kicker **AO3 Account**, title **Edit tags**, subtitle **"{title} · changes here do not touch the text"** (`EditTagsView.swift:137`).
- Rating is every option as a check row (`ratingSlots`, `:146`). The caption asks for exclusive rows, which this is. A second tap on the selected rating stays selected.
- Warnings are multi-select. The footnote (`:71`) says AO3 needs at least one, and the first is how a creator declines to warn. The frame’s “exactly one of these six” is replaced in the comment (`:67`) because AO3 checks presence. Checked, not a revert.
- Categories are switches. Their order is whatever `form.categoryOptions` AO3 sent. Not claimed against the frame’s F/F-first list.
- Fandoms is required. Chips have an xmark, **Add** is a dashed chip, and both targets use `minimumHitTarget()` with **Remove {tag}** / **Add {set}** (`WritingFormFields.swift:106`). The order and the headings are batch-8-5.
- Save is the toolbar button (`EditTagsView.swift:127`).

### 1bq — Add Chapter

- Title **Add chapter**, or **Edit chapter** when `chapterID != nil`.
- **Chapter number** when `includePosition`, otherwise **Expected chapter total**. The value is **N of** plus an editable total. **Position** / **After chapter** is gated on `form.includePosition`. `chapter[position]` is omitted from the body when that flag is false (`AO3WritingModels.swift:666`). Where the flag is assigned was not re-read; the row is gated on it.
- **Chapter text** passes the empty hint and the rule title **Chapter N** (`AddChapterView.swift:220`). Summary, notes, and end notes on this form do not pass the hint (batch-8-7).
- Switches: **Set a different publication date**, **Post without preview** (default false), **This is the last chapter**. The last-chapter footnote matches the artboard: the switch writes the work’s total.
- **Post chapter now** in the success colour, or **Save chapter changes** when editing a posted chapter. **Save as draft** for a new or draft chapter. With preview on, the green button opens the preview instead of posting. The subscriber footnote matches. A partial failure says **Retry updating the work total** and **The chapter was saved. Only the work total will be retried.** The error alert is **AO3 could not save the chapter**.

### 1br — Series edit, reorder, remove

- Header and the Complete footnote match. `reorderFootnote` (`:219`) says a work’s place is stored on the work, so reordering rewrites the position of the works in one request. The caption’s “three requests” is the sentence this comment corrected, because AO3 renumbers from one list. Checked.
- **Remove works** pushes `SeriesRemoveWorksView`. The confirm names the work: **Remove “Title” from Series?**, button **Remove from series**, message **The work stays posted on AO3.** The last work cannot be removed; the footnote says AO3 deletes the series with the last. That is the decision (`REDESIGN_DECISIONS.md:60`). The row’s value is the work count, not a pending-removal count.
- Reorder: title **Reorder**, label **Reading order**, numbers stay visible, **Save** sends the whole order once and is disabled under two rows. A draft chip shows when `row.isDraft`. VoiceOver reads the index, the title, Draft, and the metadata (`:390`). Metadata is absent when the screen was opened from the 1w swipe, because the manage page does not print words or the date (`:17`). The handles are on because this screen is the reorder mode. The subtitle’s drag hint and the type size are batch-8-16.
- **Creators** is a byline field, placeholder **Add a co-creator byline** (`:152`).
- The delete label matches. Where it opens is batch-8-10.

### 1bs

- Covered with 1bo. **Draft**, **Required before posting**, **When posted**, **Post this work?**, **Fill in what is missing**, **Delete this draft?**, **Delete draft**.

### 1bt — Hub scopes

- The caption asks for scope pills and for inner headings (Saved / Following, Posted / Unposted, Read on AO3 / Received). `tabSections` (`AccountView.swift:560`) and the comments at `:1090`, `:1110`, and `:1125` flatten those on purpose. `docs/REDESIGN_PLAN.md` records the same decision. Not restored.
- Row order matches the frames once the inner headings are ignored. Reading: Marked for Later, Bookmarks, Collections, Subscriptions. Writing: Works, Series, Drafts. Activity: History, Inbox (`:133`).
- History’s subtitle is exactly **AO3’s own history, not the local reading log** (`:1131`).
- Subscriptions does not say **7 with new chapters**. The comment (`:1094`) says that count needs the loaded works, and the cache holds sizes only. Checked.
- Comments and Kudos are on the Activity device. No native hub destination for either was found, so they are not filed as missing screens. **Gifts given and received** is an `AccountExternalNavCard` on More on AO3 (`AccountMoreOnAO3View.swift:280`), and **Gifts** is a 1u works scope.
- Row chrome (`:1228`): SF Symbol 15pt in the accent, title 15pt regular, subtitle 11.5pt secondary, count 13pt medium monospaced, chevron, vertical padding 11. The frame’s title weight is medium. Measured as one step, and left here rather than as its own finding. A subtitle-less row’s 44pt height was not measured.
- Identity, the pseud, and **Posting as** are 1m (batch 7). The works screen’s **Scope** / **All Pseuds** control is a different menu.

### 1bu — Tag picker

- Header kicker **Edit tags**, title is the field name. Empty subtitle: **AO3 offers its canonical tags as you type**. With chips: **N chosen · drag to reorder · …** (`WritingTagsEditor.swift:147`). The frame’s second screen drops the offer sentence once tags are chosen. The drag clause is the same idea; the hint itself is the same class as batch-8-16 and was not filed twice.
- Placeholder **Add a tag**. Chosen chips drag, drop, and expose Move Earlier / Move Later. The xmark is **Remove {tag}** at `minimumHitTarget()`. No always-on drag handle.
- Suggestions: the name at 15pt, **Canonical** in green with a check, or **Posts as typed** in orange (`:365`). The frame says **Not canonical — posts as typed**. The shorter badge is the comment at `:297`, because the list is capped. Checked.
- The work-count column is drawn only when `tag.workCount` is non-nil. The comment says autocomplete returns canonical tags and no counts, so the column is absent rather than a column of em dashes. The frame’s **41,208** is not invented. Checked.
- The footnote (`:377`) says the counts are absent and that a non-canonical tag still posts.
- The closed-list branch (warnings, categories, and the bulk “remove from collections” picker) uses the kicker **Choose** and **None chosen** / **N chosen**.
- A checkmark on this screen’s own toolbar was not found. Chips write the binding live, and the parent form’s Save is the commit. Not filed as a missing button.
- The convenience rows are batch-8-9.

### 1bv — Chapter text

- OD1 (`REDESIGN_DECISIONS.md:52`): no WYSIWYG WebView. Native editor, a toolbar that inserts AO3 tags, and a read-only preview. Formatted-by-default is deferred. **Edit tags directly** is omitted on purpose. The build note says the frame is a mockup of the editor. Not reverted.
- The rule title is the chapter name, and Add Chapter passes **Chapter N**. The count is the word count from the last checkpoint, not per keystroke (`WritingTextEditor.swift:78`).
- Body: serif via `fontDescriptor.withDesign(.serif)`, `lineHeightMultiple = 1.35`, which the comment calls 1.62 over the serif’s own line height (`WritingNativeTextView.swift:97`). The buffer stays raw markup.
- Menu: **Paste as plain text**. Chapter actions add **Preview on AO3** and **Delete chapter**. The delete alert is **Delete “name”?**, button **Delete on AO3**, message **This will delete all comments on the chapter as well and cannot be undone.**
- Preview is a toolbar toggle. A failed parse is said and not drawn as an empty chapter (`WritingBufferPreview`). Undo, Redo, and Done are toolbar buttons.
- The footnote matches the artboard (`:106`). The link tag is the one that asks for a URL; the others insert immediately.
- The comment says the bar sits above the keyboard (`:101`). Reduce Motion and Dynamic Type for this editor were not verified.
- The extra recovery line and the 17-tag bar are batch-8-15.

### 1bw — Collections, gifts, series

- Header **Edit work** / **Collections and gifts** / the work title. **Your collections** carries a count the frame’s rule does not. Search is a row labelled **Search**, placeholder **Search all collections by name**, filtering the offered list and debouncing `AO3Client.shared.openCollections`.
- `stateText` (`:216`): **Moderated — a maintainer approves the work**, **Closed to new works**, **Open**, and the unknown sentence **Open to new works · may be moderated or unrevealed**. Unrevealed appends **· Unrevealed until reveal**. Anonymous appends **· Anonymous**. Rows are checkmarks, title 14.5pt medium, state 11.5pt.
- The collections footnote matches the frame’s pending / unrevealed sentence.
- Gifts: section **Gift recipients**, an **Add** row, placeholder **Username or pseud**, a borderless **Add** button, then one row per recipient with a remove button. The footnote says gifts are notified by email on post and cannot be taken back, and that **AO3 checks the name when the work is saved.** The frame says the field validates before save. The code’s sentence matches the save-time check the comment describes. Not filed as a missing pre-save lookup.
- Empty copy: **AO3 offers this work no collections** and **No collection matches “…”**.
- Series subtitle prefers **Saving adds …**, then **Saving creates …**, then `membershipText` (**{title} is part of one series** / **N series**). A current series cannot be unticked (**This work is in it**). The list is single-select because the work form posts one series id.
- **Create a series from this work** is a title field, placeholder **Title**, under **New series**. Creation happens when the work form is saved (`:399`), which is the one request the form can post. Empty series: **You have no series yet**.
- **Place this work** and the Translations row are batch-8-8. The series-row subtitle helper already says **N works · this work is Nth**.

### Accessibility and platform (checked in code, not on a device)

- Scope chips, the **New work** chip, tag remove and **Add**, and the tag picker’s xmark use `minimumHitTarget()`. The default floor is 44. Filter chips elsewhere in the app document a lower floor when 44 would overlap neighbours; that exception was not re-measured on these screens.
- Own-works ledger metadata is one accessibility element, and the date is spoken as “Updated …”. Select-mode rows expose **Selected** / **Not selected**. Series reorder rows read the index, the title, and Draft. Collection rows read the state and selected / not selected.
- Pull to refresh is on the profile, on drafts, and on the account hub. The writing forms hide the floating tab bar via `subjectScreenWash` or `hidesFloatingTabBar`.
- iOS states the page name in `SubjectHeaderBlock` and hides the bar chrome on drafts. macOS sets `navigationTitle` on the pushed editors. iPad and macOS were not run. Keyboard avoidance was read as a comment on the tag bar and was not watched. Dynamic Type and Reduce Motion were not exercised on these screens.

---

## The three that matter

1. **batch-8-1.** Own Works is the list a writer lives in, and the row is still the search ledger: tags hidden until expand, the chapter count after the word count and without the word “chapters,” a date that reads `MM/dd/yyyy`, and **Gift for …** under the card. Select mode (batch-8-3) then swaps in a third layout. The signal strip can stay; the caption asks for it. The toolbar plus and the funnel (batch-8-2) are the same screen’s other miss, and they are the “add” the owner asked every page to have.
2. **batch-8-4.** Series already has the designed row — spine, state badges, 19pt title — and the default display mode never shows it. The list opens on the old stat-chip row.
3. **batch-8-6.** Deleting a posted work says **Delete Work?** and then either AO3’s raw caution or, from the swipe, a sentence that treats other people’s bookmarks as deleted. The artboard counts the chapters, the kudos, and the comments, and says the bookmarks will break. Beside it, **Delete series on AO3** (batch-8-10) opens the public series page and deletes nothing.
