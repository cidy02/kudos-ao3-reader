# Pass 2 — cross-screen consistency (Grok)

Read-only sweep of `integrate/cloud-redesign`. Compared screens with each other and with PLAN.md B–G. Artboard fidelity is out of scope. Nothing here was built, and archiveofourown.org was not contacted.

Not re-filed (owner already rejected or parked them): Filter stays the chip label (2-8); no section hairline / offline tick (2-18); the queue’s In Line switch stays (3-8); the bulk bar keeps More and the words “Remove from Queue” (3-11); selection-mode number size (3-12); 28pt pill rails (3-28); text Cancel/Create is the sheet convention (3-31 — used below as the rule); new-queue copy (3-32); tag-manager row menu (3-33); organizer wash (3-35); filter “Direction” (4-7); one header size (6-4); “Mark as Finished” (6-7); short swipe labels (6-13 — used below as the rule); the progress ring says Finished (2-6). The bottom queue switcher stays an owner question (3-34) and is not opened again. 2-9 was explicitly deferred to this pass and is pass2-38.

Severity: P1 wrong or broken, P2 visible inconsistency, P3 polish.

---

## 1. The “…” menu

**Majority.** `WorkListMoreMenu` (`WorkCardListControls.swift:110`) draws a plain `ellipsis`, tints it `Color.primary`, and the pages that follow the rule fill it in this order: Show/Hide mature (only while Hide Mature is on) · Select · Reorder · display mode · Expand/Collapse (only when the current layout can expand) · page items · destructive last. Reorder, when the list is ordered, is disabled under a filter with the reason in the label (“Clear Filters to Reorder”).

**Matches that order and the neutral tint**

| Screen | Contents | Where |
|---|---|---|
| Library section (History, Favorites works, Reading Now, …) | Mature · Select · Layout · Expand when Detailed | `LibrarySectionListView.swift:215` |
| Queue, when it has works | Mature · Select · Reorder · Layout · Expand when Detailed · Queue Details · Rename · Delete Queue | `ReadingQueueBrowser.swift:756` |
| Queue, empty | Queue Details · Rename · Delete Queue | `ReadingQueueBrowser.swift:790` |
| Queues organizer | Select · Reorder. Done is the word “Done” | `ReadingQueueOrganizer.swift:397` and `:387` |
| Local collection | Mature · Select · Reorder · Expand · Rename · Details · Delete Collection | `Collections.swift:391` |
| Search results | Mature · Select · Expand | `SearchView.swift:187` |
| Fandom works, tag works | Mature · Select · Expand | `NativeBrowseView.swift:397` and `:527` |
| Home dashboard | Mature · Select | `HomeView.swift:269` |
| Work detail toolbar | Plain ellipsis, `.tint(Color.primary)`, destructive last inside the shared menu | `WorkDetailView.swift:407` |

**Same component, different contents or order**

| Screen | What it does instead |
|---|---|
| Library dashboard | Mature · **Reading Insights** · Select · a shelves/ledger picker. A page item sits in front of Select. | `LibraryView.swift:577` |
| Home section list | Mature · Select · Layout. No Expand, even though Detailed is one of the layouts and the library section expands. | `HomeSectionListView.swift:181` |
| Account works (bookmarks, history, subscriptions, marked for later) | Mature · Layout (omitted for marked-for-later and subscriptions) · Expand · Mark All as Seen · Clear History. No Select. | `AO3AccountWorksList.swift:299` |
| Account hub | Mature · Layout · Expand. Select is a separate toolbar icon, and only for the inbox. | `AccountInboxViews.swift:86` and `:115` |
| AO3 collection page | Mature only. The works are expandable rows and there is no Expand. | `AO3CollectionDetailView.swift:120` |
| Home and Library dashboards, while selecting | Mature is pulled out of the menu into its own toolbar button. Pushed lists hide it with the menu. | `HomeView.swift:247`, `LibraryView.swift:535` |

**Custom menu, not `WorkListMoreMenu` (no neutral tint, page items first, mature last)**

| Screen | Order |
|---|---|
| Author profile | Open on AO3 · Share · web links · Select Works · Layout · Expand · Mature · About | `AuthorProfileView.swift:786` |
| Series | Edit series · Open on AO3 · Share · Expand · Mature | `AO3SeriesDetailView.swift:74` |
| Pronunciations | Circled `ellipsis.circle`. Add, Paste, and Copy live inside it. | `ReaderPronunciationSettingsView.swift:164` |

The bulk bar’s circled More is the control 3-11 kept. It is not listed again.

### pass2-1 — P2 — Author profile and Series menus

`AuthorProfileView.swift:786`, `AO3SeriesDetailView.swift:74`

**Convention.** `WorkListMoreMenu` is neutral, and mature is the first item whenever Hide Mature is on.

**Current.** Both are hand-built `Menu`s with no `.tint(Color.primary)`, so they inherit the app accent. Page items come first. Mature is last. Series has no Select and no layout picker.

**Smallest fix.** Build both with `WorkListMoreMenu` and put Mature, then Select (author works), then the layout picker, then Expand, then Open / Share / Edit / About.

### pass2-2 — P2 — Library dashboard puts a page item before Select

`LibraryView.swift:577`

**Convention.** Select comes before page items. Reading Insights is a page item.

**Current.** The menu is Mature · Reading Insights · Select · Layout.

**Smallest fix.** Move the Reading Insights link to after the layout picker.

### pass2-3 — P2 — Home’s work list can change layout and cannot expand

`HomeSectionListView.swift:181` versus `LibrarySectionListView.swift:228`

**Convention.** Expand/Collapse follows the layout picker on every list whose Detailed rows expand. The library section already does this, and only when the mode is Detailed.

**Current.** Home’s section menu has the picker and no `ExpandAllMenuItem`.

**Smallest fix.** Copy the library section’s `if displayMode == .detailed` block into this menu.

### pass2-4 — P2 — Select is not in the same place on every works list

`AO3AccountWorksList.swift:299`, `AccountInboxViews.swift:115`, `AuthorProfileView.swift:780`, `AO3CollectionDetailView.swift:120`

**Convention.** Select lives in “…”. Search, Browse, library sections, queues, and local collections all do that.

**Current.** Account works (bookmarks, history, subscriptions, marked for later) have no Select at all, even though Search selects the same kind of remote row. The inbox and an author’s own works put Select on a toolbar button beside the menu. An AO3 collection’s works have neither Select nor Expand.

**Smallest fix.** Add the same Select item Search uses to the account-works menu and the AO3 collection menu, and move the inbox and own-works Select buttons into their menus. Keep Expand on the collection page, since its rows already expand one at a time.

### pass2-5 — P3 — Mature leaves the menu only on the two dashboards

`HomeView.swift:247`, `LibraryView.swift:535`

**Convention.** Show/Hide mature stays in “…”.

**Current.** While the Home or Library dashboard is selecting, the toggle becomes its own toolbar button (and turns accent when revealed). A pushed library or home section drops the menu and offers no toggle until selection ends.

**Smallest fix.** Leave the toggle inside the menu on the dashboards too, or hoist the same single button on every selecting works list. One of those, on all of them.

---

## 2. Add

**Majority.** A list of the user’s own things grows from a neutral toolbar “+” (`ToolbarIconButton`, `systemImage: "plus"`). An empty state may repeat that action. The control is not also a permanent row on a non-empty list.

**Toolbar `ToolbarIconButton` “+”**

| List | Label | Where |
|---|---|---|
| Local collection’s works | Add Works | `Collections.swift:382` |
| Queues organizer | New Queue | `ReadingQueueOrganizer.swift:393` |
| Your own author profile, Works and the dashboard | New Work | `AuthorProfileView.swift:749` |

**Other homes**

| List | Where add lives |
|---|---|
| Queue page | Accent-filled `.buttonStyle(.glassProminent)` plus, not `ToolbarIconButton` | `ReadingQueueBrowser.swift:819` |
| Queues organizer, again | A dashed “New queue” row under the list, on top of the toolbar + | `ReadingQueueOrganizer.swift:465` |
| Queue page, iPad/Mac sidebar | A “New Queue” row under the sidebar, on top of the toolbar + | `ReadingQueueBrowser.swift:392` |
| Library collections carousel and See All | In-page `NewCollectionCard` only. The grid has no toolbar. | `LibraryView.swift:407`, `LibraryEntityGridView.swift:42` |
| AO3 collections | Toolbar plus, but a `NavigationLink` + `Label`, not `ToolbarIconButton` | `AO3CollectionsList.swift:82` |
| Your series | “New series on AO3” only in the empty state. A non-empty series list has no add. The profile “+” is New Work and hides off the Works tab. | `AuthorProfileContentSections.swift:495`, `AuthorProfileView.swift:757` |
| Pronunciations | “Add Pronunciation” is an item inside the circled menu | `ReaderPronunciationSettingsView.swift:149` |
| Writing tags, gifts, series, co-creators | In-form plus rows. Correct for a form field, not a list page. | `WritingTagsEditor.swift:241`, `WorkAssociationPickers.swift:162` |

Empty-state “Add Works” on an empty local collection (`Collections.swift:288`) matches the rule: the toolbar + is still there, and the empty state repeats it.

### pass2-6 — P2 — The queue’s add button is a different control from every other add

`ReadingQueueBrowser.swift:819`

**Convention.** `ToolbarIconButton` “+”, neutral glass, as on the organizer, a collection, and your own works.

**Current.** The queue page builds its own button, `.glassProminent`, tinted with the queue accent.

**Smallest fix.** Use `ToolbarIconButton(title: "Add Works", systemImage: "plus")` here too.

### pass2-7 — P2 — Queues offer add twice; collections and series do not offer it in the toolbar

`ReadingQueueOrganizer.swift:465`, `ReadingQueueBrowser.swift:392`, `LibraryView.swift:407`, `LibraryEntityGridView.swift:42`, `AuthorProfileContentSections.swift:495`, `AO3CollectionsList.swift:82`

**Convention.** One toolbar “+”. An in-page row is only the empty state.

**Current.** The organizer and the iPad queue sidebar keep a permanent “New queue” row beside the toolbar button. Local collections are the opposite: the only add is the dashed card, including on See All, which has no toolbar. Your series can be created only while the list is empty. AO3 collections do put plus in the toolbar, but as a navigation-link label rather than `ToolbarIconButton`.

**Smallest fix.** Drop the always-visible queue rows (leave an empty-state action). Put `ToolbarIconButton` “+” on the collections grid, on your series list, and on the AO3 collections toolbar.

---

## 3. Delete / remove

**Majority for a saved work.** Trailing swipe, full swipe off where the swipe itself would destroy a file. Label “Delete”, `role: .destructive` (system red, no extra tint). Confirmation is `deleteConfirmation` / `destructiveConfirmation`: “Delete this work?”, confirm “Delete”, and the work goes to Recently Deleted. That path is the context menu (`WorkCardActions.swift:427` and `:582`) and the library section (`LibrarySectionListView.swift:942`).

**Majority for taking a work out of a container.** Trailing swipe, `destructiveConfirmation`, title “Remove this work?”, confirm “Remove”, message names the container and says the work stays in the library. Local collection (`Collections.swift:305` and `:501`) and the queue page (`ReadingQueueBrowser.swift:251` and `:358`) both confirm. The collection swipe says “Remove”. The queue swipe says “Remove from Queue” (wording is pattern 10).

**Recently Deleted is the right sink** for soft-deleting a work, a local collection (`Collections.swift:491`), and a queue (`ReadingQueueOrganizer.swift:713`, `ReadingQueueBrowser.swift:350`). Removing a membership, hiding a history row, and deleting on AO3 correctly do not land there.

**Same job, different safety or no swipe**

| Screen | Swipe | Confirms? | Notes |
|---|---|---|---|
| Library section, ordinary work | Trailing Delete | Yes, via `confirmBeforeDelete` | Full swipe is left on (`:909` does not set `allowsFullSwipe: false`); the alert still gates it |
| Library section, History | “Remove from History” | No | `LibrarySectionListView.swift:926`. Full swipe commits |
| Library section, queue-only work | “Remove from Queue”, which calls `removeFromAllQueues` | No | `:936` |
| AO3 history rows | “Delete from History” | Yes | `AO3HistoryWorksBrowser.swift:139`, ask at `AO3AccountWorksList.swift:386` |
| Home section rows | Leading Download + Favorite only | Delete is context menu and the bulk bar, not a swipe | `HomeSectionListView.swift:251` |
| Favorites works | Trailing “Unstar”, no Delete | No ask, by design of that page | `:910` |
| Queue organizer rows | Rename (blue) then Delete | Yes | `ReadingQueueOrganizer.swift:501` |
| Library collection cards | None | Delete only after you open the collection | `Collections.swift:439` |
| AO3 collection cards | Edit only, gray | No delete swipe | `AO3CollectionsList.swift:275` |
| Inbox | Mark Read / Mark Unread, accent | Delete is in the row menu and does confirm | `AccountInboxViews.swift:680` and `:171` |
| Your own works | Delete (explicit `.tint(.red)`, no destructive role) then Chapter / Tags / Edit. Full swipe off | Yes, “Delete on AO3” | `AuthorProfileContentSections.swift:378`, ask at `AuthorProfileView.swift:89` |
| Subscriptions | Unsubscribe | Yes | `AO3SubscriptionsWorksBrowser.swift:363`, `AO3NamedSubscriptionsList.swift:203` |
| Recently Deleted | Delete then Restore. Menu says “Delete Permanently”; swipe says “Delete” | Yes | `RecentlyDeletedView.swift:562` |
| Comments | Copy / Edit / Delete, full swipe off | Yes | Not re-litigating the short “Edit” label (6-13) |

### pass2-8 — P2 — Home’s copy of a library row cannot be swiped away

`HomeSectionListView.swift:251`

**Convention.** A list of the user’s works has a trailing delete swipe plus the bulk bar. The library section is that list.

**Current.** The comment refuses the swipe because this screen has no `confirmBeforeDelete` alert. The row’s context menu already confirms on its own (`WorkCardActions.swift:452`), and Select mode on this same screen already uses `WorkBulkActionBar`.

**Smallest fix.** Add the library section’s trailing Delete swipe. It already routes through `pendingDelete` and Recently Deleted.

### pass2-9 — P2 — “Take this off the list” confirms on one screen and commits on the next

`LibrarySectionListView.swift:926` and `:936`, versus `ReadingQueueBrowser.swift:358` and `AO3AccountWorksList.swift:386`

**Convention.** Scoped removal asks with `destructiveConfirmation` before it changes membership. A full swipe on the library section is enabled, so the first trailing button runs immediately.

**Current.** “Remove from History” calls `WorkLifecycle.removeFromHistory` with no ask. The same history, read from AO3, asks with “Delete from History?”. “Remove from Queue” on a queue-only library row calls `removeFromAllQueues` with no ask. The same gesture on the queue page sets `pendingRemoval` and asks.

**Smallest fix.** Point both library-section buttons at `pendingRemoval` and the existing scoped confirmation. Set `allowsFullSwipe: false` on that trailing edge so the ask cannot be skipped.

### pass2-10 — P2 — A collection cannot be deleted from the list that shows it

`LibraryView.swift:414` (collection cards have no swipe), `AO3CollectionsList.swift:275`

**Convention.** The queue organizer’s custom queues swipe to Delete, which confirms and soft-deletes into Recently Deleted (`ReadingQueueOrganizer.swift:501`).

**Current.** A local collection card has no swipe. Delete exists only inside the open collection’s menu. An AO3 collection card swipes to Edit and has no delete.

**Smallest fix.** Trailing Delete on a local collection card, reusing the collection menu’s confirmation and `PreservedWorkService.softDelete`. On AO3 collections, a trailing Delete that presents the same confirm-then-delete the collection form already performs, owner-only.

### pass2-11 — P2 — Inbox delete is menu-only

`AccountInboxViews.swift:680`

**Convention.** The destructive action of a row is the trailing swipe, and it confirms. This row already confirms (“Remove this notification from your AO3 Inbox?”).

**Current.** The swipe is Mark Read / Mark Unread. Delete is only in the overflow.

**Smallest fix.** Add a trailing “Delete” swipe that sets the same `confirmDelete` flag. Keep full swipe off.

### pass2-12 — P3 — One delete swipe paints its own red

`AuthorProfileContentSections.swift:380`

**Convention.** `Button(role: .destructive)` and no extra `.tint`, which is how library, queue, collection, history, and Recently Deleted swipes go red.

**Current.** The own-work Delete button has no role and `.tint(.red)`.

**Smallest fix.** Give it `role: .destructive` and drop the tint.

---

## 4. Reorder

**Majority, and the PLAN rule.** Reorder is an item in “…”. Choosing it enters a mode, the toolbar says “Done”, and the handles exist only in that mode. They are absent under a filter, with the reason in the menu label. No screen should say “drag to reorder”.

| List | How reorder works |
|---|---|
| Queues organizer | Menu → mode, system move handles, toolbar **Done** (`ReadingQueueOrganizer.swift:385`) |
| Queue page | Menu → mode, but Done is a checkmark image (`ReadingQueueBrowser.swift:733`). Custom `ReorderHandleView` is also live while selecting (`ReadingQueuePageParts.swift:67`) |
| Local collection | Menu item opens `CollectionReorderSheet`, a second screen (`Collections.swift:404`, sheet at `:468`) |
| Series | A gray “Reorder” swipe pushes `SeriesReorderDestination` (`AuthorProfileContentSections.swift:542`). The series page menu has no Reorder item |
| Series reorder screen and collection reorder sheet | Dedicated screens titled “Reorder” / “Reorder works”, with `.onMove`. Fine as the destination; the entry point is what differs |
| Writing tags | Chips are always draggable. The subtitle says “drag to reorder” (`WritingTagsEditor.swift:150`) and VoiceOver is hinted “Drag to reorder.” (`:200`) |
| Shortcut editor | The sheet is the editor: `.environment(\.editMode, .constant(.active))` and Done dismisses (`AccountShortcuts.swift:155`). Handles belong here because the screen exists to edit. Not a browsing list |

`SectionRuleHeader` still documents a “Drag to reorder” note (`SubjectSurface.swift:548`). Nothing passes that note today.

### pass2-13 — P2 — Ordered lists of the user’s things enter reorder three different ways

`ReadingQueueOrganizer.swift:387`, `ReadingQueueBrowser.swift:731`, `ReadingQueuePageParts.swift:67`, `Collections.swift:404`

**Convention.** One mode, ended by the word Done. Handles only in that mode. The organizer is the one that matches.

**Current.** The queue page ends the mode with a checkmark and shows handles during selection as well. A collection’s menu opens a sheet instead of the mode.

**Smallest fix.** On the queue page, replace the checkmark with `Button("Done")` and make `isDragLive` true only while reordering. On a collection, set the same `isReordering` flag the organizer uses and call the collection’s existing move function from `.onMove`, instead of presenting `CollectionReorderSheet`.

### pass2-14 — P2 — Series reorder is a swipe, not a menu mode

`AuthorProfileContentSections.swift:542`, `AO3SeriesDetailView.swift:74`

**Convention.** Reorder is in “…”.

**Current.** The series list swipes to Reorder. The series page’s own menu can Edit, Share, Expand, and reveal mature, and cannot reorder.

**Smallest fix.** Add “Reorder” to the series menu (after Select / layout, before the page items) and keep the swipe as a shortcut to that same screen, since posting a new order to AO3 needs the save step `SeriesReorderView` already has.

### pass2-15 — P2 — “Drag to reorder” is still on screen

`WritingTagsEditor.swift:150` and `:200`

**Convention.** PLAN B: no “Drag to reorder” hints, and no always-on handles. Reorder is a mode.

**Current.** The tag editor’s subtitle counts “N chosen · drag to reorder · …”, the chips are always draggable, and the accessibility hint repeats the phrase.

**Smallest fix.** Drop both strings. If the chips must stay draggable because this form is the editor, the Move Earlier / Move Later actions already there are the affordance, and the subtitle should not mention dragging.

---

## 5. Section headers and page headers

**Majority.** A subject page names itself with `SubjectHeaderBlock` (kicker, 32pt title, tally) and scrolls that away under the bar. A group inside the page is `SectionRuleHeader` (small caps, optional count, optional see-all). Writing forms use `SectionRuleHeader` too (`WorkEditView.swift:67`, `SeriesEditView.swift:79`). Filter sheets and creation sheets use an inline `navigationTitle` plus text Cancel / verb, which is the sheet convention.

**`SectionRuleHeader` + `SubjectHeaderBlock` already:** library sections, home shelves, queue page, queues organizer, local and AO3 collection pages, account works, comments, work detail, challenges, account hub, recently deleted, insights.

**Something else on a subject page**

| Screen | Header |
|---|---|
| Series page | `navigationTitle("Series")` and `Section("Works")` | `AO3SeriesDetailView.swift:61` and `:66` |
| Author Works tab | `Section` header is a plain `Text("Works")` / `Text("Your works")` | `AuthorProfileContentSections.swift:334` |
| Author Series tab | `Section("Series")` | `AuthorProfileContentSections.swift:465` |
| Tag works | `navigationTitle(request.title)` and no subject block | `NativeBrowseView.swift:496` |
| Collections See All, queues See All | `navigationTitle` only | `LibraryEntityGridView.swift:54` |
| Shortcut editor | `Section { … } header: { Text("On the grid") }` | `AccountShortcuts.swift:127` |

Search is a field in the principal slot plus `SearchResultsHero`, which is the results summary rather than a second page title. macOS keeps `navigationTitle` on account works because the wash does not clear the window title (`AO3AccountWorksList.swift:277`). Both are fine.

### pass2-16 — P2 — Series and the author tabs use a different header than every other subject page

`AO3SeriesDetailView.swift:61`, `AuthorProfileContentSections.swift:343` and `:465`

**Convention.** `SubjectHeaderBlock` for the page, `SectionRuleHeader` for Works / Series.

**Current.** Series is a bar title plus a stock section header. The author tabs, which sit under a profile header, still label their lists with `Text("Works")` and `Section("Series")` instead of the rule header used on the account, library, and queue lists of the same works.

**Smallest fix.** On series, replace the bar title with `SubjectHeaderBlock` (kicker from the bare fandom, title the series name) and `SectionRuleHeader(title: "Works", count:)`. On the author tabs, replace the two section headers with `SectionRuleHeader`.

### pass2-17 — P3 — Tag works and the See All grids are bar titles

`NativeBrowseView.swift:496`, `LibraryEntityGridView.swift:54`

**Convention.** A pushed list of works or of the user’s collections names itself with `SubjectHeaderBlock`, the way a library section and a collection page do.

**Current.** Both use `navigationTitle` and nothing else. Fandom works already builds a `SearchResultsHero`, so the tag page is the odd one of that pair.

**Smallest fix.** Give tag works the same hero the fandom page uses. Give See All a one-line `SubjectHeaderBlock` (title “Collections” or “Queues”, count in the subtitle) and an empty bar title.

---

## 6. Counts on chips, cards, and stat strips

**Majority where the pass-1 compact rule landed.** `Int.compactCount` (`CompactCount.swift:6`, which is `.formatted(.number.notation(.compactName))`): queue pills and the organizer stat strip (`ReadingQueueOrganizer.swift:198` and `:456`), queue row counts (`:551`), work-detail kudos / comments / bookmarks / hits (`WorkDetailFactsSections.swift:148`), the library’s Recently Deleted count (`LibraryView.swift:355`), and the “50k+ words” chip (`LibraryFilters.swift:407`). Accessibility strings and pagination stay exact, which is what PLAN D asks for. Search’s hero and page counts stay exact because they are AO3 totals (`SearchResultsHero.swift:150`). The fandom directory’s right-hand column stays exact on purpose: it is sized for a six-digit figure (`FandomListView.swift:771`).

**Full integers in the same job**

| Surface | Formatter | Where |
|---|---|---|
| Every `SectionRuleHeader` count | `"\(count)"` | `SubjectSurface.swift:571` |
| Every `SubjectFieldLabel` count | `count.formatted()` (1,200, not 1.2K) | `SubjectSurface.swift:679` |
| Author “how this work did” strip | `.formatted()` for Kudos, Comments, Hits, Bookmarks | `AuthorDashboardSections.swift:220` |
| Comments signal strip | `.formatted()` | `CommentsView.swift:511` |
| Author fandom chips | `(workCount.formatted())` glued to the tag | `AuthorProfileContentSections.swift:183` |
| Insights pace cells | `.formatted()` for works opened, while words-read on the same screen is compact | `ReadingInsightsView.swift:498` versus `:500` |

### pass2-18 — P2 — The same four stats are compact on the work and exact on the author and the comments

`WorkDetailFactsSections.swift:148`, `AuthorDashboardSections.swift:220`, `CommentsView.swift:511`

**Convention.** A stat strip of kudos, comments, bookmarks, and hits uses `compactCount`. The work page already does, and keeps `.formatted()` for the accessibility value.

**Current.** The author performance strip and the comments strip print grouped full numbers for the same kind of figure.

**Smallest fix.** Pass `compactCount` as the cell value in both strips. Leave the spoken string exact, as the work page does.

### pass2-19 — P2 — The shared section header and field label never compact

`SubjectSurface.swift:571` and `:679`

**Convention.** A count drawn next to a label on a chip, card, or section uses `compactCount`. `countText` (“3 / 12”, “2,140 words”) stays exact.

**Current.** `SectionRuleHeader.count` interpolates the integer. `SubjectFieldLabel.count` uses `.formatted()`. A comments section and a tag section can show 12,000 beside a work page that shows 12K for the same work.

**Smallest fix.** Print `count.compactCount` in both views. Do not change `countText`.

### pass2-20 — P2 — Author fandom chips and the insights pace row use a third formatter

`AuthorProfileContentSections.swift:183`, `ReadingInsightsView.swift:498`

**Convention.** Chip counts and the small figures on a stat card use `compactCount`. Queue chips and the insights “words read” cell already do.

**Current.** Each author fandom chip appends ` (1,234)`. The pace card mixes `.formatted()` work counts with a compact word count.

**Smallest fix.** `fandom.workCount?.compactCount` inside the chip, and `compactCount` for the pace cells.

---

## 7. Fandom names

**Majority.** Kickers, cover cards, and the work-detail identity use `FandomDisplayName.bareTitle`: `WorkRow.swift:136`, `AO3WorkRow.swift:386`, `HomeCards.swift:97` and `:250`, `HomeResumeHero.swift:148`, `WorkDetailIdentityBlock.swift:41`, `MediaBrowserView.swift:279`. Library filter chips match on the bare family (`LibraryFilters.swift:282`).

The expanded metadata line on a work card still joins the raw tags (`WorkRow.swift:229`). That is the canonical list, under a kicker that is already bare, so it is the one place the disambiguator still earns its keep. Not filed.

**Raw tag, on a kicker, card, chip, or section title**

| Surface | Where |
|---|---|
| Queue cover, the next-up kicker | `ReadingQueues.swift:84` |
| Series row kicker | `AuthorProfileComponents.swift:199` via `primaryFandom` at `:263` |
| History grouped by fandom | Section titles are the raw first tag, so “Doctor Who” and “Doctor Who (2005)” become two groups | `LibraryHistoryGrouping.swift:98` |
| Favorites, newest-work line | `FavoriteAffinityRow.swift:207` |
| Draft card kicker | `WritingDraftsView.swift:255` |
| Author fandom filter chips | `fandom.name` | `AuthorProfileContentSections.swift:185` |
| Prompt-meme card kicker | `PromptMemeView.swift:245` |
| Challenge offer summary | `ChallengeSignUpView.swift:413` |

### pass2-21 — P2 — Eight surfaces still show the raw fandom tag

The lines in the table above.

**Convention.** A kicker, card, chip, or fandom section title uses `FandomDisplayName.bareTitle`. History’s own work rows already do. Grouping by the raw string also splits one family into two sections.

**Current.** Each of those eight prints `fandoms.first` or `workFandoms.first` unchanged.

**Smallest fix.** Run the string through `FandomDisplayName.bareTitle` at each of those eight call sites. In `LibraryHistoryGrouping.fandom`, group by the bare title so the section header and the bucket are the same key. Keep the raw tag on the work for hue and for filtering.

---

## 8. Empty, loading, and error

**Majority for a works list.** First load is a skeleton shaped like the row (`AO3WorkRowSkeletonList` on search and tag works; `AO3AuthorLoadingRows` is four `AO3WorkRowSkeleton`s, `AuthorProfileContentSections.swift:13`). Empty and failed are `ContentUnavailableView`. A failed load has Try Again. An over-filtered list has Clear Filters (`NativeBrowseView.swift:561`, search’s collision card). A genuinely empty library section has no action because the section cannot create a work (`LibrarySectionListView.swift:272`). An empty collection does, and the action is Add Works (`Collections.swift:282`).

**Differs**

| Screen | State | What it does |
|---|---|---|
| User / series subscriptions | First load | Centered `ProgressView` | `AO3NamedSubscriptionsList.swift:179` |
| Same screen | Failed | `ContentUnavailableView` + Try Again | `:169` |
| Same screen | Empty | `ContentUnavailableView`, no action | `:156` |
| Author tabs, series page | Empty and failed | `AO3ProfileMessageRow` inside the list, not `ContentUnavailableView` | `AuthorProfileContentSections.swift:33`, `AO3SeriesDetailView.swift:126` |
| Add-works sheet | Nothing eligible, or mature-only | `ContentUnavailableView`, the mature one with a reveal action | `AddLibraryWorksSheet.swift:64` |
| Add-works sheet | Query miss | A secondary `Text("No works match …")` | `:86` |

### pass2-22 — P2 — Subscriptions spin; every neighbouring list skeletons

`AO3NamedSubscriptionsList.swift:179`

**Convention.** The first load of an account list is a row skeleton. This screen’s own error state is already `ContentUnavailableView`.

**Current.** The loading branch is `ProgressView` centered in a row.

**Smallest fix.** Replace that branch with `AO3WorkRowSkeletonList` (or `AO3AuthorLoadingRows` if the row is a name rather than a work). Leave the empty copy as a `ContentUnavailableView`; there is no create action on this list.

### pass2-23 — P3 — Author and series empties are a custom row

`AuthorProfileContentSections.swift:33`, `AO3SeriesDetailView.swift:126`

**Convention.** `ContentUnavailableView` with a title, a symbol, a sentence, and Try Again when the load failed. Library, search, queues, and the add sheet do this.

**Current.** Both use `AO3ProfileMessageRow`. The retry is there. The shape is not the one on the other lists.

**Smallest fix.** Present the same title, message, and Try Again through `ContentUnavailableView`.

### pass2-24 — P3 — One empty state inside Add Works is a plain sentence

`AddLibraryWorksSheet.swift:86`

**Convention.** The other two empties in this sheet are `ContentUnavailableView`.

**Current.** A query that matches nothing is `Text("No works match “…”")`.

**Smallest fix.** Use `ContentUnavailableView` with “No matching works” and a Clear Search button that empties `query`.

---

## 9. Sheets

**Majority, and the convention 3-31 fixed.** Text Cancel on the leading side, a text verb on the trailing side (Create, Done, Save, Add), an inline `navigationTitle`, a visible drag indicator, and a detent of `.large` or `[.medium, .large]`. Filter panels get that chrome from `FilterPanelPresentation.swift:42`. Creation sheets that match: `NewReadingQueueSheet.swift:123` (Cancel / Create, large, grabber) and the pronunciation editor (`ReaderPronunciationSettingsView.swift:403`, Cancel / Save). `AddLibraryWorksSheet.swift:102` is Cancel / a count verb, with a grabber (`:115`) and the system large detent.

**Differs**

| Sheet | Chrome |
|---|---|
| New collection | Cancel / Create and an inline title, but no detent and no grabber. Its sibling new-queue sheet has both. | `NewCollectionSheet.swift:60` |
| New queue | `.tint(palette.accent)` on the whole sheet, so Cancel and Create take the queue colour. New collection does not tint. | `NewReadingQueueSheet.swift:134` |
| Collection items | Commit is a checkmark icon (“Submit staged changes”). Dismiss of the staged set is the word Discard. | `AO3CollectionItemsView.swift:184` |
| Pronunciation editor | `.presentationDetents([.medium])` and no drag indicator | `ReaderPronunciationSettingsView.swift:418` |
| Queue reorder | Ended with a checkmark, not “Done” | Filed as pass2-13 |

### pass2-25 — P2 — New collection and new queue do not share chrome

`NewCollectionSheet.swift:60`, `NewReadingQueueSheet.swift:134`

**Convention.** Text Cancel / Create, inline title, `.large`, grabber visible, buttons in the neutral bar colour. New queue has the detent and the grabber. New collection has the neutral buttons.

**Current.** New collection is missing the detent and the grabber. New queue tints the entire sheet, including Cancel and Create, with the queue accent.

**Smallest fix.** Add `.presentationDetents([.large])` and `.presentationDragIndicator(.visible)` to `NewCollectionSheet`. Remove the `.tint(palette.accent)` on `NewReadingQueueSheet` (the swatches already carry the colour).

### pass2-26 — P2 — Collection items commits with an icon

`AO3CollectionItemsView.swift:184`

**Convention.** The trailing button of a sheet or an editing bar is a word: Create, Done, Save.

**Current.** Submit is `Label("Submit staged changes", systemImage: "checkmark")`. Discard, next to it, is text.

**Smallest fix.** `Button("Submit")`, disabled when nothing is staged. Keep the accessibility label that includes the count.

### pass2-27 — P3 — The pronunciation editor has no grabber

`ReaderPronunciationSettingsView.swift:418`

**Convention.** A medium sheet shows the drag indicator. The filter panel and the comments composer do.

**Current.** Detent is `.medium` only, and nothing sets `presentationDragIndicator`.

**Smallest fix.** Add `.presentationDragIndicator(.visible)`.

---

## 10. Swipe labels and colours

**Majority for the four actions PLAN names.**

| Action | Label | Colour | Where it is shared |
|---|---|---|---|
| Download | “Download” / “Remove Download” / “Kept Offline by …” | `.blue` | `WorkDownloadButton.swift:22`, `WorkDownload.swift:43`. Remote rows use the same blue for the unsaved case (`WorkCardActions.swift:564`) |
| Save for Later | “Save for Later” / “Remove from Saved for Later” | `.indigo` | `SaveForLaterButton.swift:48`, remote leading swipe `WorkCardActions.swift:574` |
| Favorite | “Favorite” / “Unfavorite” | `.yellow` | Library section leading (`LibrarySectionListView.swift:906`), Home section (`HomeSectionListView.swift:262`), context menu via `WorkActionLabels.favorite` (`WorkCardActions.swift:243`) |
| Delete | “Delete” | destructive role, no extra tint | Library section, queue organizer, Recently Deleted, context menu |

Short labels are the rule (6-13). The bulk bar’s “Remove from Queue” stays long (3-11). Collection membership already uses the short swipe “Remove” (`Collections.swift:314`).

**The same action, a different word or colour**

| Action | Outlier |
|---|---|
| Favorite, on the Favorites page | Trailing “Unstar”, tint `.subjectFavoriteGold` | `LibrarySectionListView.swift:919` |
| Favorite, on a remote row | Not on the swipe. The context menu has it. Local rows swipe it. | `WorkCardActions.swift:577` |
| Remove from a container | Queue page and the library’s queue-only row say “Remove from Queue” (`ReadingQueueBrowser.swift:256`, `LibrarySectionListView.swift:939`). History says “Remove from History” (`:929`) or “Delete from History” (`AO3HistoryWorksBrowser.swift:143`). The collection says “Remove”. |
| Add to Queue | Orange, and only on the remote row’s trailing edge (`WorkCardActions.swift:597`). Local rows keep it in the context menu. |

Download’s blue is consistent. Do not shorten “Save for Later”: that is the feature’s name, and the long “Remove from Saved for Later” is what keeps it distinct from Delete on the other edge.

### pass2-28 — P2 — Unstarring is a different word and a different gold

`LibrarySectionListView.swift:919`, `WorkActionLabels` at `WorkCardActions.swift:243`

**Convention.** The action is “Unfavorite”, tint `.yellow`, which is what the leading swipe on every other library row and on Home already says.

**Current.** Favorites’ trailing swipe says “Unstar” in `.subjectFavoriteGold`.

**Smallest fix.** Use `WorkActionLabels.favorite(isFavorite: true)` and `.tint(.yellow)` on that button.

### pass2-29 — P2 — Remote rows omit the favorite swipe that local rows have

`WorkCardActions.swift:577`

**Convention.** Favorite is a leading swipe, yellow, on the local row.

**Current.** A remote row’s leading edge is Download and Save for Later. Favorite is only in the context menu. Trailing is Delete plus an orange “Add to Queue”, an action the local swipe does not show.

**Smallest fix.** Add the same Favorite button (yellow, `WorkActionLabels.favorite`) to the remote leading edge, after Save for Later. Leave “Add to Queue” in the context menu so the trailing edge stays Delete, matching the local row.

### pass2-30 — P2 — Container swipes do not share a label

`Collections.swift:314`, `ReadingQueueBrowser.swift:256`, `LibrarySectionListView.swift:929` and `:939`, `AO3HistoryWorksBrowser.swift:143`

**Convention.** The swipe is the short word. The confirmation and the menu carry the scope (“Remove from Queue”, “Delete from History”). The collection swipe is already “Remove”, and its confirmation already says which collection.

**Current.** The queue swipe and the library’s queue-only swipe say “Remove from Queue”. Local history says “Remove from History”. AO3 history says “Delete from History”.

**Smallest fix.** Swipe label “Remove” on the queue and on both history lists. Keep the existing confirmation titles, which already name the container.

---

## 11. Confirmation copy

**Majority.** A question title, a destructive confirm button whose label is the verb, Cancel, and a message that says what goes away and what is left. Local works: “Delete this work?” / “Delete” / Recently Deleted (`WorkCardActions.swift:454`). Membership: “Remove this work?” / “Remove” / the work stays in the library (`Collections.swift:501`, `ReadingQueueBrowser.swift:358`). One named container: “Delete “Name”?” / “Delete” (`ReadingQueueOrganizer.swift:717`, `OwnWorksBulkBar.swift:27`). Comments: “Delete this comment?” / “Delete” (`CommentsView.swift:291`).

**The words drift**

| Ask | Title | Confirm | Voice |
|---|---|---|---|
| Inbox | “Remove this notification from your AO3 Inbox?” | “Delete From Inbox” | Title says Remove, button says Delete | `AccountInboxViews.swift:171` |
| A work of yours | “Delete “title”?” | “Delete on AO3” | `AuthorProfileView.swift:90` |
| The work editor | “Delete this draft?” or “Delete Work?” | “Delete draft” or “Delete work on AO3” | `WorkEditView.swift:218` |
| A comment | “Delete this comment?” | “Delete” | “It can't be undone.” | `CommentsView.swift:295` |
| Your own work, the bulk bar | “Delete “title”?” | “Delete” | “It cannot be undone.” | `OwnWorksBulkBar.swift:35`, `AuthorProfileView.swift:98` |
| Queue or collection | “Delete “name”?” | “Delete” | “for 90 days”, written out four times | `ReadingQueueBrowser.swift:354`, `ReadingQueueSettingsView.swift:266`, `ReadingQueueOrganizer.swift:725`, `Collections.swift:497` |

Recently Deleted itself reads `PreservedWorkService.recoveryWindow` for the subtitle. The four dialogs do not.

### pass2-31 — P2 — The inbox ask cannot decide between Remove and Delete

`AccountInboxViews.swift:171`

**Convention.** The title and the confirm button use one verb. Membership uses Remove. Destroying the row uses Delete.

**Current.** The title says “Remove this notification…”. The button says “Delete From Inbox”. The swipe, if pass2-11 lands, would say Delete.

**Smallest fix.** Title “Delete this notification?”, confirm “Delete”, message unchanged (it already says the comment stays).

### pass2-32 — P2 — Single-item delete titles are not one pattern

`WorkEditView.swift:218`, `WorkCardActions.swift:454`, `CommentsView.swift:291`, `AuthorProfileView.swift:90`

**Convention.** “Delete this work?” when the row has no name worth quoting. “Delete “Name”?” when the name is what the person must check. Confirm is “Delete”, and the message carries “on AO3” or “to Recently Deleted”.

**Current.** The editor asks “Delete Work?” (capital W, no “this”) for a posted work and “Delete this draft?” for a draft. The author page puts the name in the title and “on AO3” on the button. Comments and the library put “this” in the title and keep the button as “Delete”. “Can't” and “cannot” both appear.

**Smallest fix.** Editor: “Delete this draft?” and “Delete this work?”. Author button: “Delete”, with “on AO3” only in the message. Use “cannot” in both messages.

### pass2-33 — P3 — “90 days” is copied into four dialogs

`ReadingQueueBrowser.swift:354`, `ReadingQueueSettingsView.swift:266`, `ReadingQueueOrganizer.swift:725`, `Collections.swift:497`

**Convention.** The recovery window has one source. Recently Deleted already reads it.

**Current.** Each dialog hardcodes “for 90 days”. They agree today. They will not if the window changes.

**Smallest fix.** One `PreservedWorkService` sentence, used by all four, that interpolates `recoveryWindow`.

---

## Favorites controls (deferred here as 2-9)

### pass2-34 — P2 — Favorites is the only library list with a second on-page order control

`LibrarySectionListView.swift:416`

**Convention.** Order lives in Filter. The chip stays labelled Filter (2-8 stands). History, Reading Now, search, and browse do not put a segmented Recent / Most read / Most time control on the page.

**Current.** Authors, fandoms, and tags each add a `SubjectSegmentedControl` of `ReadingAffinities.Order` under the scope switch, and tags add another pill rail (All / Unread works) on top of that. Works uses a different quick-filter rail. The header tally on those scopes is only “N authors / fandoms / tags”, while Works says “N works · newest first”.

**Smallest fix.** Remove the on-page order control and drive that order from the filter panel, the way every other library section does. Keep each scope’s one pill rail (All / With new work, All / Unread works, All / Rereads / Offline / WIP).

---

## The ten changes that would move the app the most

1. **One menu.** Put author and series on `WorkListMoreMenu` (pass2-1), move Reading Insights after Select (pass2-2), add Expand to Home’s section (pass2-3), and put Select back inside the menu on account works, the inbox, own works, and AO3 collections (pass2-4).
2. **One add button.** Neutral `ToolbarIconButton` “+” on the queue page (pass2-6), and that same button as the only add on queues, local collections, AO3 collections, and your series (pass2-7).
3. **One remove gesture.** Trailing delete on Home rows (pass2-8). Confirm history and queue-only removal before a full swipe commits it (pass2-9). Delete a collection from the list that shows it (pass2-10).
4. **One reorder mode.** Word “Done”, handles only while reordering, collections inline like queues (pass2-13). Series reorder in the menu (pass2-14). Delete the “drag to reorder” copy (pass2-15).
5. **One page header.** `SubjectHeaderBlock` and `SectionRuleHeader` on series and the author Works / Series tabs (pass2-16).
6. **One count.** `compactCount` inside `SectionRuleHeader`, `SubjectFieldLabel`, the author stat strip, the comments strip, author fandom chips, and the insights pace cells (pass2-18, pass2-19, pass2-20).
7. **One fandom name.** `FandomDisplayName.bareTitle` on the eight remaining kickers, chips, and history groups, and group history by that bare title (pass2-21).
8. **One empty state.** A skeleton instead of a spinner on subscriptions (pass2-22), and `ContentUnavailableView` for the author, series, and add-works misses (pass2-23, pass2-24).
9. **One sheet.** New collection grows the detent and grabber; new queue loses the accent tint on Cancel/Create (pass2-25). Collection items says Submit (pass2-26).
10. **One swipe vocabulary.** “Unfavorite” in yellow (pass2-28), favorite on remote rows too (pass2-29), swipe label “Remove” wherever the confirmation already names the container (pass2-30), and the inbox dialog uses Delete in both the title and the button (pass2-31).
