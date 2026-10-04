# Brief 3ab result — Home section lists

## Scope

`HomeSectionListScreen` now uses the pushed subject-page chrome and the Library's work-list
building blocks. The route and arguments are unchanged:
`Routes.homeSection(id, selecting, selection)`. A selection passed from Home still seeds both
selection mode and the selected work IDs.

No Home dashboard, Room schema, backup format, navigation route, or AO3 networking code changed.

## User-visible strings

Work titles, author names, fandoms, summaries, tags, ratings, warnings, categories, chapter and
word counts, collection/tag names, queue names, and filter values are data-driven. They remain
verbatim data and are not repeated below.

### Before

The screen itself showed:

- the section title: `Reading Now`, `Recently Updated`, `Favorites`, or `Recently Opened`;
- the subtitle `<N> works` (always plural);
- toolbar/accessibility labels `Select`, `Filter this section`, `Expand all`, and `Collapse all`;
- the active-filter badge `!`;
- selection actions `Select All` and `Deselect All`;
- empty state `Nothing here yet` plus the section's existing explanatory copy:
  - `You aren't reading anything yet. Open a work from your Library or find one in Browse.`
  - `None of the works in your Library has a new chapter yet.`
  - `No favorites yet. Mark works as favorites to see them here.`
  - `Nothing opened recently. Start reading to see your history here.`
- filtered-empty state `No matching works`,
  `No works in this section match the current filters.`, and `Clear Filters`.

The old plain cover cards could additionally show `Finished`, `Reading <N>%`, `Not downloaded`,
`Favorite`, `Tap to reveal`, and the accessibility sentence
`Hidden mature work. Activate to reveal.` Their menu showed `Read`, `Comments`, `Select`,
`Download`, `Remove Download`, `Kept Offline by <name>`, `Save for Later`,
`Remove from Saved for Later`, `Favorite`, `Unfavorite`, `Add to Queue`,
`Mark as Finished`, `Mark unfinished`, `Add to Collection`, `Work Details`, and `Remove`.

The reused filter panel showed `Filter and Sort`, `Sort by`, `Default`, `Date Added`,
`Date Downloaded`, `Last Read`, `Title`, `Author`, `Word Count`, `Kudos`, `Status`, `Favorites`,
`Finished`, `Unfinished`, `Download`, `Downloaded`, `Not Downloaded`, `Completion`, `Complete`,
`InProgress`, `My Tags`, `Collections`, `Clear`, `Close`, and `Apply` as applicable.

The reused bulk bar showed `Favorite`, `Download`, `Add to Queue`, `Add to Collection`,
`Mark Finished`, `More actions`, `Unfavorite`, `Remove Download`, `Mark Unfinished`,
`Remove from Saved for Later`, `Remove from Library`, and `Cancel`. Its dialogs could show
`Remove 1 work?` / `Remove <N> works?`, `Selected works move to Recently Deleted for 90 days.`,
`Remove`, `Add Selection to Queue`, `Loading...`, `No custom queues yet.`, `Close`,
`Add Selection to Collection`, `New or existing collection`, `Existing collections:`, `Add`,
and `Cancel`.

### After

The page chrome and header now show:

- accessibility label `Back` on the shared pushed back button;
- kicker `Home`;
- the same four section titles;
- subtitle `<N> work · <order>` or `<N> works · <order>`, using
  `most recently read first` for Reading Now, Favorites, and Recently Opened, and
  `newest check first` for Recently Updated;
- when narrowing produces no rows:
  `<N> work · none match the current filters` or
  `<N> works · none match the current filters`;
- row-group headings `In progress`, `New chapters`, `Favorites`, and `Recently opened`;
- top toolbar accessibility labels `Filter` / `Filter, <N> active` and `More`.

The `More` menu, in iOS order and only under iOS's conditions, shows:

1. `Show mature` or `Hide mature` when Hide mature content is enabled;
2. `Select` when the privacy-visible section has works;
3. `Layout`, leading to `Detailed`, `Ledger`, and `Compact`, when the section has works;
4. `Expand All Cards` or `Collapse All Cards` only in Detailed mode.

Reading Now adds `All <N>` and `WIP <N>`. Recently Updated adds `All <N>`, `Unread <N>`, and
`Offline <N>`. Active filter chips use the existing values and the exact state labels
`Favorites`, `Finished`, `Unfinished`, `Downloaded`, `Not Downloaded`, `Complete`, and
`In Progress` where applicable.

Selection mode shows `Select Works` with no selected visible work, otherwise `<N> Selected`, and
`Select All` / `Deselect All`. The reused bulk-bar strings listed above are unchanged.

The unfiltered empty state now shows only iOS's `Nothing here yet`. A Recently Updated quick pill
with no results shows `No unread works` or `No offline works` and `Show All`.

The filter-collision state now uses iOS's count-sensitive strings:

- `Nothing matches.`
- `Nothing matches this filter.`
- `Nothing matches both filters.`
- `Nothing matches all three filters.`
- `Nothing matches all four filters.`
- `Nothing matches all five filters.`
- `Nothing matches all <N> filters.`
- `Your 1 work in <section> is hidden by this filter.`
- `All <N> of your works in <section> are hidden by these filters.`
- `Clear all filters`
- `Edit`

Recently Updated compact cards use iOS's `+<N> CH`. Detailed cards retain their existing
metadata/state strings. Ledger rows use `Anonymous`, `Reading`, and `Finished` when those values
apply. Every layout now uses the same Library menu: `Read`, `Comments`, `Select`, `Download`,
`Remove Download`, `Kept Offline by <name>`, `Favorite`, `Unfavorite`, `Save for Later`,
`Remove from Saved for Later`, `Add to Queue`, `Mark as Finished`, `Mark as Still Reading`,
`Add to Collection`, `Work Details`, and `Delete` as applicable. Detailed and Ledger swipe labels
are `Download`, `Remove Download`, `Favorite`, `Unfavorite`, and `Delete` as applicable. Thus the
destructive menu string is now `Delete` rather than the old cover menu's `Remove`. A single delete
can show `Delete this work?`,
`Kudos will move this work to Recently Deleted. You can restore it for the next 90 days.`,
`Delete`, and `Cancel`. The filter-panel and bulk-bar strings listed under Before are otherwise
unchanged.

## Callbacks and behavior

### Before

- `onOpenWork` opened an undownloaded work or Work Details.
- `onOpenReader` opened a work with an EPUB.
- `onOpenComments` opened comments from the long-press menu.
- Pull to refresh called `WorkMetadataRefresh.refresh` once for each visible work.
- Filter, clear, apply, and dismiss updated the screen-local `LibraryFilterState`.
- Select, Select All/Deselect All, row selection, and the bulk bar updated the screen-local
  selection; route-provided initial selection was retained.
- The bulk bar called `WorkRepository`, `ReadingQueueRepository`, and `DownloadQueue` for bulk
  changes.
- Tapping a blurred card called `PrivacyGate.reveal`.
- The card menu's single-item Select, favorite, finished, download, remove, Saved for Later,
  Add to Queue, and Add to Collection callbacks were wired to no-ops.

### After

- `onOpenWork`, `onOpenReader`, `onOpenComments`, pull-to-refresh, the filter panel, initial route
  selection, and the bulk bar are retained.
- The system/back-chrome callback exits selection mode before navigating back.
- `Select` in the menu, a card/row tap during selection, and Select All/Deselect All now all use
  the same visible-ID selection set in Detailed, Ledger, and Compact modes.
- The display callback persists Detailed/Ledger/Compact independently for each Home section.
- Reading Now's All/WIP and Recently Updated's All/Unread/Offline callbacks narrow the same
  privacy-filtered section source.
- `Show mature` / `Hide mature` calls `PrivacyGate.toggleRevealAll`; an obscured work tap still
  calls `PrivacyGate.reveal` for that work only.
- Single-item favorite/unfavorite calls `WorkRepository.toggleFavorite`.
- Single-item finished/still-reading calls `WorkRepository.toggleFinished`.
- Download/Remove Download calls `WorkRepository.setSaved`; a missing EPUB is queued through
  `DownloadQueue.enqueueLocal`.
- Save for Later/removal calls `ReadingQueueRepository.addToSavedForLater` or
  `removeFromSavedForLater`.
- A queue-only row's Remove swipe calls
  `ReadingQueueRepository.removeFromAllQueuesAndDeleteIfQueueOnly` rather than soft-deleting it.
- Delete stages the shared confirmation and then calls `WorkRepository.softDelete`.
- Add to Queue and Add to Collection remain no-ops, as before; see Omissions.

## Reused from the Library lists

- `LibraryPrivacy.visibility` is the only privacy decision.
- `LibrarySubjectLedgerRow` is the Detailed card, including `SensitiveWorkRow`, its privacy blur,
  swipe container, and long-press menu. Its new optional `expandAll` argument defaults to false,
  so existing Library callers are unchanged.
- `LibrarySubjectWorkCard` is the Compact cover card, including the privacy blur, selection
  chrome, tap routing, and long-press menu. Its new optional `footerOverride` defaults to null,
  so existing Library callers are unchanged.
- `LibraryWorkMenu`, `leadingSwipeActions`, and `trailingSwipeActions` are shared directly rather
  than copied.
- Ledger mode uses the existing `WorkLedgerRow`, `defaultWorkSignals`, and the same Library menu
  and swipe factories.
- The page uses `ProvidePushedShellChrome`, `FilterButton`, `SubjectHeaderBlock`,
  `SectionRuleHeader`, `SubjectChip`, `subjectScreenWash`, `LibraryFilterPanel`, and
  `WorkBulkActionBar`.

## Mature works in every Home section

| Section | Blur mode | Hide mode |
|---|---|---|
| Continue Reading / Reading Now | The work remains in section order. Detailed and Ledger rows and Compact cards blur it; tapping reveals it, while tapping in selection mode selects without revealing. `Show mature` reveals all. | The work is omitted before section/filter counts and rendering. `Show mature` authenticates if required, then restores it in section order for the session. |
| Recently Updated | Same blur/reveal behavior; its All/Unread/Offline counts and `+<N> CH` card appear only after the privacy decision. | Omitted from the section and every quick-pill count until `Show mature` reveals all for the session. |
| Favorites | Same blur/reveal behavior; being favorited never bypasses privacy. | Omitted from the section until `Show mature` reveals all for the session. |
| Recently Opened | Same blur/reveal behavior; prior reading history never bypasses privacy. | Omitted from the section until `Show mature` reveals all for the session. |

In both modes, `Hide mature` clears the session-wide reveal through the existing `PrivacyGate`.
Per-work reveals remain session-only. No privacy state is persisted by this screen.

## iOS details not reproduced

- The referenced iOS `HomeSectionKind` currently defines only Reading Now and Recently Updated.
  Android already routes Favorites and Recently Opened here, so those two use their existing
  Android membership/order rules and the same iOS visual system rather than being removed.
- iOS's filter-collision card can calculate a minimal colliding filter set and offer
  `Drop one filter`, `Without <filter>`, and `<N> work(s)` suggestions. Android's shared
  `LibraryFilterState` has no equivalent collision/drop analysis. The count-sensitive iOS title,
  explanation, Clear-all, and Edit actions are present; the speculative per-filter drops were not
  duplicated in this screen.
- iOS's bulk Actions menu includes `Tag`. Android's shared `WorkBulkActionBar` does not yet expose
  bulk tagging. This screen reuses that bar instead of creating a Home-only fork.
- The existing single-item Library menu requires caller-owned queue/collection sheets for
  `Add to Queue` and `Add to Collection`. `HomeSectionListScreen` has no such callbacks in its
  route contract, so those two inherited menu entries remain no-ops rather than adding a second
  sheet implementation here.
- iOS checks whether an EPUB is actually readable for Offline. Android's current shared model
  exposes `hasEpub` at this layer, so the Offline pill uses that established Android signal.

## Verification left to Claude

Per the brief, Gradle was not run in this sandbox. `git diff --check` passes. Claude still needs to
compile/test and visually inspect all three layouts, selection entered both locally and through
`Routes.homeSection(id, selecting, selection)`, Blur and Hide in all four sections, filter-empty
states, compact-card spacing, and the floating chrome/tab-bar transition.

## Review changes (Claude, before landing)

- **The filter panel's Sort now works.** It was passed a fixed sort and an empty callback, on the
  old screen too. iOS keeps a section's own order until a sort is picked
  (`HomeSectionListView`), so the list is re-sorted with the Library's `sortDisplayItems` only
  when the sort isn't Default, and Clear resets it.
- **Still dead, as before this brief:** Add to Queue and Add to Collection in a row's menu. The
  Library's two dialogs live inside `LibraryScreen` and need extracting before this screen can
  show them. Queued as a follow-up.

Checked on the emulator: all four sections in Dark, Reading Now in Light and at font scale 2.0,
Favorites in Sepia; the More menu's four items; Detailed, Ledger and Compact layouts (the choice
is remembered per section); selection mode with the bulk bar; a Mature work blurred in every
layout; the Title sort reordering Recently Opened.
