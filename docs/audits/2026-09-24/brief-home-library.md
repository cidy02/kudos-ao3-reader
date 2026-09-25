# Brief — home-library (wave 3, cloud)

Source: `home-library.json` with `critic-wave3.json`'s corrections already
applied. Facts: `otwarchive-facts-wave3.json`. Base `c4ce1e2`. Paths are under
`kudos-ao3-reader/` unless they start with `KudosTests/` or `docs/`.

Nine items: five bugs, then four small gaps. None needs an owner decision.
Everything else the audit found is listed at the end, as owner calls or later
work.

**Keep out of:** `Services/AO3Client.swift`, `AO3RequestCoordinator.swift`,
`RequestCoalescer` (T-255); `Models/Models.swift` and every persistence
service; `project.pbxproj`; `ReadingQueueCard` (T-252 owns the queue boards).

---

## Bugs

### H1 — The Library section cache ignores six filter fields (1c.7, 1d)

- **Files:** `Features/Library/LibraryView.swift:254-280` (`sectionsRevision`),
  `Features/Library/LibraryFilters.swift`.
- **Wrong today:** `rebuildSectionCache` runs only from
  `.task(id: sectionsRevision)` (`LibraryView.swift:178-183`). The revision
  string leaves out `characters`, `relationships`, `additionalTags`,
  `excludeTags`, `warnings` and `categories`, and it counts `userTags` rather
  than naming them. With any filter already on, change one of those and every
  dashboard carousel keeps the previous filter's works and counts.
- **Change:** add `LibraryFilters.revisionKey: String`, which joins every
  stored field in a fixed order and sorts each set (for example
  `userTags.sorted()` and `characters.sorted()` joined with a separator none of
  them can contain, and the enum raw values). In `sectionsRevision`, replace the
  filter slice (fandoms through `hasActiveFilters`) with `filters.revisionKey`.
- **Test** (`KudosTests/LibraryFiltersTests.swift`): two `LibraryFilters` that
  differ only in `characters`, only in one `warnings` member, or only in the
  *names* of a single `userTags` entry must give different `revisionKey`s.
  Equal filters give equal keys.

### H2 — Home's Subscriptions header prints page 1's count as a total (1b.7)

- **Files:** `Features/Home/HomeView.swift:485-492`.
- **Wrong today:** AO3 pages subscriptions `ITEMS_PER_PAGE` at a time (25 in
  otwarchive's config; Q12). Home loads page 1 and prints `merged.count`, so a
  reader with 45 subscriptions sees "SUBSCRIPTIONS 25". `WorkCarouselSection`'s
  own doc (`UIComponents/WorkCarouselSection.swift:44-46`) forbids exactly this.
- **Change:** `accountSubscriptions` already records the page in
  `AO3AccountListCountsCache` (`Services/AO3AuthService.swift:795-799`). Add a
  pure `enum HomeSubscriptionsCount { static func itemCount(shown: Int,
  recorded: AO3AccountListCount?) -> Int? }` that returns `shown` only when
  `recorded?.exact != nil`, and pass its result as `itemCount`. Read the count
  with `AO3AccountListCountsCache.shared.count(for: .subscriptions,
  authenticationScope: AO3AuthorProfileFetcher.sessionScopedCacheScope(for: auth))`.
- **Test:** `itemCount(shown: 12, recorded: .init(itemsOnPage: 12, totalPages: 1)) == 12`;
  `itemCount(shown: 25, recorded: .init(itemsOnPage: 25, totalPages: 2)) == nil`;
  `itemCount(shown: 3, recorded: nil) == nil`.

### H3 — A failed Subscriptions load reads as "not subscribed" (1b.8)

- **Files:** `Features/Home/HomeView.swift:501-530`.
- **Wrong today:** when the first fetch throws, `subscriptions` stays `[]` and
  the section says "You're not subscribed to anything yet".
- **Change:** `@State private var subscriptionsLoadFailed = false`. Set it
  `true` in the `catch` only when `subscriptions.isEmpty`, and `false` on
  success or sign-out. Move the empty-state copy into a pure
  `HomeSubscriptionsCopy.emptyMessage(isLoggedIn:loadFailed:)`. The failure copy
  is "Couldn't load your subscriptions. Pull down to try again."
- **Test:** `emptyMessage(isLoggedIn: true, loadFailed: true)` must not contain
  "not subscribed"; the other two cases keep today's strings.

### H4 — The Recently Updated empty state names the wrong source (1b.9)

- **Files:** `Features/Home/HomeSections.swift:40-42`.
- **Wrong today:** "No recent updates from your subscriptions yet." The section
  is built from saved, unfinished library works (`WorkUpdateChecker`,
  `Services/WorkUpdateChecker.swift:17-47`). No subscription is involved.
- **Change:** "No new chapters yet on the works in progress in your library."
- **Test:** `HomeSectionKind.recentlyUpdated.emptyMessage` does not contain
  "subscri" (case-insensitive).

### H5 — Reading Now cards print "Ch N" from a spine index (1b.12; same root as 1a.4)

- **Files:** `Utilities/WorkReadingPosition.swift` (new function), with call
  sites at `Features/Home/HomeView.swift:575-576`,
  `Features/Library/LibraryView.swift:515` and
  `Features/WorkDetail/WorkDetailSections.swift:471`.
- **Wrong today:** `SavedWork.readingProgressLabel` returns
  `"Ch \(lastSpineIndex + 1)"`. The legacy macOS reader writes
  `lastSpineIndex`, and sync copies it to iOS. The legacy reader itself labels
  chapters by walking past Preface and Summary, "instead of a raw spine
  position" (`Features/Reader/ReaderView.swift:263-297`). The model has no
  story-chapter index, so its label is off by the front matter.
- **Change:** add `WorkReadingPosition.cardProgressLabel(readiumProgress:
  Double?) -> String?` that returns the Readium percent ("42%") or `nil`, and
  use it at the three call sites (`work.readiumProgress`). Leave
  `SavedWork.readingProgressLabel` in `Models.swift` untouched: it is out of
  bounds for this batch and still has its one "42%" test. Leave
  `readingProgress` alone too: `KudosTests/SavedWorkProgressTests.swift:49-54`
  pins its spine-as-chapter fraction, and changing that is a separate decision.
- **Test:** `cardProgressLabel(readiumProgress: nil) == nil`;
  `cardProgressLabel(readiumProgress: 0.42) == "42%"`.

## Small gaps (no owner decision)

### H6 — The Reading Now tally omits its order (1ad.2)

- **Files:** `Features/Library/LibrarySectionKind.swift`,
  `Features/Library/LibrarySectionListView.swift:290-297`.
- **Spec:** 1ad: "4 works · most recently read first".
- **Change:** add `LibrarySectionKind.orderDescription`, where each phrase
  describes the sort in `works(from:visible:)`:
  - readingNow, history: "most recently read first"
  - savedForLater: "most recently read or added first"
  - finished: "most recently read first"
  - downloaded, favorites: "newest first"
  - collections: ""

  Append `" · " + orderDescription` in `headerTallyLine` only when
  `!filters.hasActiveFilters` (a filter's own sort replaces the section's).
- **Test:** every non-empty phrase is present, and `.collections` is empty.

### H7 — Reading Now's rows are headed "READING NOW", not "IN PROGRESS" (1ad.4)

- **Files:** `Features/Library/LibrarySectionKind.swift`,
  `Features/Library/LibrarySectionListView.swift:688-693`.
- **Spec:** 1ad heads the rows "IN PROGRESS". `HomeSectionKind.groupTitle`
  already says so.
- **Change:** add `LibrarySectionKind.groupTitle` (readingNow: "In progress";
  every other kind: `title`) and use it for the single non-history bucket.
- **Test:** `LibrarySectionKind.readingNow.groupTitle == "In progress"` and
  `.downloaded.groupTitle == .downloaded.title`.

### H8 — Select mode never shows the count in the title bar (1af.1)

- **Files:** `Features/Home/HomeSectionListView.swift:141-155`,
  `Features/Library/LibrarySectionListView.swift:173-187`, and
  `Features/Library/LibraryView.swift:130-132` (which already does this inline).
- **Spec:** 1af: "Select mode takes the title bar for a count".
- **Change:** `enum WorkSelectionTitle { static func text(selectedCount: Int)
  -> String }` returns "Select Works", "1 Selected" or "\(n) Selected". Add a
  `.principal` `ToolbarItem { Text(WorkSelectionTitle.text(...)) }` inside both
  lists' `if isSelecting` branch, and make LibraryView use the same function.
- **Test:** 0 → "Select Works", 1 → "1 Selected", 12 → "12 Selected".

### H9 — Remote cards carry no AO3 provenance badge (1b.11)

- **Files:** `Features/Home/HomeCards.swift:157-213` (`AO3WorkCoverCard`).
- **Spec:** the small "AO3" badge measured in `docs/REDESIGN_PLAN.md:2663-2671`
  (radius 5, black 40 %, `700 8px`, `.08em`, white 80 %).
- **Change:** a top-trailing overlay `Text("AO3")` at those metrics, with
  `.accessibilityHidden(true)`, since the card's label already says it is an AO3
  work. Draw it on the remote card only: a local card is the library's.
- **Test:** none (visual). This needs a screenshot at the Mac, in all four themes.

---

## Needs the owner

- **1ad.5 — Default Reading Now to ledger rows?** The board draws ledger rows,
  but the ledger row drops the summary. That is a density reduction under
  AGENTS.md's UI rule (critic-wave3 changed this item from GAP to OWNER).
- **1ad.1 — Reading Now on Home's stack.** Already decided ("Phase A
  contract", `docs/REDESIGN_PLAN.md:1504-1514`). Listed so nobody re-opens it.
- **1c.2 / 1d.3 — the AO3 Marked for Later card in Saved for Later.** Already
  decided (kept local). If it ever returns, H9's badge comes first.

## Later (not in this batch)

- **1ad.3 — WIP pill with counts** (S/M). "Offline" is vacuous, because Reading
  Now already requires the EPUB (`Models/Models.swift:540-544`). All and WIP
  carry information. This is a new filter dimension, and it has to interact
  with the collision card.
- **1ay.3 — name the colliding pair** (M). It needs a single-member
  `LibraryFilters` builder that mirrors `droppingEachActiveFilter`.
- **1b.5 — queue card face "next up"** (S). Blocked until T-252's queue work
  lands, because both touch `ReadingQueueCard`.
- **1b.4** copy: "New queue / Plan what to read next" (trivial). Do it with
  1b.5.
