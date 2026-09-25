# Brief — account-hub-reading (wave 3, cloud)

Source: `account-hub-reading.json` with `critic-wave3.json`'s corrections
applied. Facts: `otwarchive-facts-wave3.json` Q12, Q18, Q19, Q21. Base
`c4ce1e2`. Paths are under `kudos-ao3-reader/` unless they start with
`KudosTests/` or `docs/`.

Seven items: five bugs, then two small gaps.

**Keep out of:** `Services/AO3Client.swift` (and so the bookmark, readings and
subscriptions parsers, which live there), `AO3RequestCoordinator.swift`,
`RequestCoalescer` (T-255), and `project.pbxproj`.

---

## Bugs

### A1 — Opening Bookmarks replaces AO3's exact count with a smaller one (1m.3)

- **Files:** `Services/AO3AccountListCountsCache.swift:14-56`,
  `Features/Bookmarks/AO3AccountWorksList.swift:892-954`.
- **Wrong today:** the dashboard nav seeds Bookmarks with AO3's own count,
  which covers every bookmark: works, series, external, and private for the
  owner (Q18). A one-page Bookmarks list then records
  `AO3AccountListCount(itemsOnPage: 7, totalPages: 1)` from the work rows
  alone, because series, external and deleted bookmarks do not parse as works.
  "Two exact counts are both totals, so the newer one wins", and the hub tile
  drops from 10 to 7.
- **Change:** add `init(itemsOnPage:totalPages:mayOmitRows: Bool)`. With
  `mayOmitRows == true`, a single page gives `lowerBound = itemsOnPage`, never
  `exact`; the multi-page arithmetic is unchanged. `load()` passes
  `mayOmitRows: kind == .bookmarks` (via the existing `record(_:kind:...)`
  overload). A lower bound never replaces an exact count
  (`isAtLeastAsStrong`), so AO3's figure survives. Without a seeded figure, the
  tile reads "7+", which is true.
- **Test** (`KudosTests/AO3AccountListCountsTests.swift`):
  `AO3AccountListCount(itemsOnPage: 7, totalPages: 1, mayOmitRows: true)` has
  `exact == nil` and `lowerBound == 7`. Recording it after an exact 10 leaves
  10. The existing `aNewerExactCountReplacesAnOlderOne` still passes.
- **Residual, after T-255:** History, Marked for Later and Subscriptions also
  drop rows AO3 still counts (deleted works). Fixing those needs the parsers in
  `AO3Client.swift` to report their raw row counts.

### A2 — Marked for Later's header drops its page context (1o.2)

- **Files:** `Features/Bookmarks/AO3MarkedForLaterWorksBrowser.swift:147-154`,
  `:258-269`.
- **Wrong today:** page 1 of 9 reads "20 works · synced 2 min ago". Every other
  account list appends "page X of Y".
- **Change:** `subtitle(workCount:syncedAt:now:currentPage: Int = 1,
  totalPages: Int = 1)` appends " · page X of Y" when `totalPages > 1`. The
  header passes both. The defaults keep existing callers and tests valid.
- **Test** (`KudosTests/AO3MarkedForLaterScreenTests.swift`): with 9 pages the
  line ends "page 1 of 9"; with one page it has no page clause.
  `syncLineIsCountThenRelativeStamp` is unchanged.

### A3 — Marked for Later's footer promises an unmark that does not exist (1o.3)

- **Files:** `Features/Bookmarks/AO3MarkedForLaterWorksBrowser.swift:177-183`;
  **must update** `KudosTests/AO3MarkedForLaterScreenTests.swift:167-178`.
- **Wrong today:** "unmarking here unmarks there". The screen has no unmark
  control, and the app has no unmark write. AO3's is
  `PATCH /works/:id/mark_as_read` (Q19).
- **Change:** "Marked for Later lives on AO3. Pagination follows the ledger:
  X of Y pages." If the owner approves 1o.4 (below), put the clause back in the
  same commit as the action.
- **Test:** update `footerUsesTheRealPageNumbers` to the new strings, and assert
  that the footer contains no "unmark".

### A4 — The Inbox tally mixes site totals with a page-only count (1l.1)

- **Files:** `Features/Account/AccountInboxScreen.swift:110-125`.
- **Wrong today:** in "1,204 comments · 12 unread · 3 awaiting your reply", the
  first two come from AO3's heading, which covers the whole inbox (Q21). The
  third counts only the loaded page. The line does not say so.
- **Change:** move the line into a pure
  `AO3InboxTally.headerLine(total:unread:awaitingOnPage:totalPages:)` (next to
  `awaitingReplyCount` in `Models/AO3InboxModels.swift`). The clause reads
  "3 awaiting your reply on this page" whenever `totalPages > 1`.
- **Test:** `headerLine(total: 1204, unread: 12, awaitingOnPage: 3,
  totalPages: 60)` ends "on this page"; with `totalPages: 1` there is no suffix.

### A5 — Subscriptions' Refine narrows rows that have no data yet (1p.6)

- **Files:** `Features/Bookmarks/AO3AccountWorksList.swift:218-221`
  (`visibleWorks`), `:313-325` (`refineSource: works` at :322).
- **Wrong today:** Refine applies facets to the index rows. Those carry no
  fandoms, rating, completion or language (`AO3WorkSummary.subscription`). A
  rating, fandom, completion or language facet fails every row not yet
  enriched: "No works on this page match the current filters", and the panel
  says "0 of 25 match".
- **Change:** a pure `AO3SubscriptionsRefine.visible(works:enriched:filters:)`
  resolves each row to `enriched[id] ?? row` and keeps a row when it is still
  index-only (no rating and no fandoms: nothing is known yet) or when it
  matches. `visibleWorks` uses it for `.subscriptions`. `refineSource` gets the
  same resolved array, so the panel's count agrees.
- **Test:** filters(rating: .teen) over [index-only row, enriched Teen,
  enriched Explicit] keeps the first two.

## Small gaps (no owner decision)

### A6 — Two docs still describe the four-segment hub (1m.4)

- **Files:** `Features/Account/AccountView.swift:4-10` (type doc),
  `docs/ARCHITECTURE_MAP.md:22`.
- **Change:** describe the flattened hub: Shortcuts, then Reading / Writing /
  Activity groups, then Account. Say that
  `libraryStyleCompactRoot` is unreachable while `showsWorkListControls` is
  false for every scope (`AccountView.swift:498-516`). Deleting that branch is
  a separate commit, if anyone wants it gone.
- **Test:** none (docs). AGENT_ONBOARDING DoD 3 requires the doc fix.

### A7 — The signed-out preview lists fewer rows than the hub (1n.2)

- **Files:** `Features/Account/AccountView.swift:954-1030`, `:1109-1160`.
- **Wrong today:** the preview's doc says it "cannot drift from the thing it
  previews", but its rows are string literals. It lacks Subscriptions, Drafts
  and History.
- **Change:** static row orders, one per scope
  (`[AccountReadingTab.later, .bookmarks, .collections, .subscriptions]`,
  `[AccountWritingTab.works, .series, .drafts]`,
  `[AccountActivityTab.history, .inbox]`), used by both the signed-in groups
  and `previewGroup` (titles and symbols from the tab enums; `previewSymbol`
  goes away).
- **Test:** the preview's reading titles equal
  `readingRowOrder.map(\.rawValue)` and include "Subscriptions"; the same for
  writing (Drafts) and activity (History).

---

## Needs the owner

- **1o.4 — Unmark on Marked for Later** (M, AO3 write): `PATCH
  /works/:id/mark_as_read` (Q19), with CSRF from the work page as `markForLater`
  does, behind a confirm. Restores A3's promised clause.

## Later

- **1l.2 — Inbox pill rail** (M). Q21 changes the plan: Unread (`read=false`),
  Awaiting reply (`replied_to=false`) and Replied (`replied_to=true`) are AO3's
  own server filters. Each pill is one filtered GET, exact across pages. The
  build note's "inferred" is unnecessary.
- **1p.4 — Works / Series / Authors scopes** (M): type= on the same index, with
  a row shape of name plus byline.
- **A1's residual** for History, Marked for Later and Subscriptions: after
  T-255.
