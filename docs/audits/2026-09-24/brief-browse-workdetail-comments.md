# Brief — browse-workdetail-comments (wave 3, cloud)

Source: `browse-workdetail-comments.json` with `critic-wave3.json`'s
corrections applied. Facts: `otwarchive-facts-wave3.json` Q13–Q15, Q20, Q23.
Base `c4ce1e2`. Paths are under `kudos-ao3-reader/` unless they start with
`KudosTests/` or `docs/`.

Eight items: two bugs, then six small gaps. **1f's thread rendering is not in
this batch.** T-247 rebuilt `CommentThreadRow` on the Mac branch (unpushed at
the time of writing), so anything touching it waits for that branch.

**Keep out of:** `Services/AO3Client.swift`, `AO3RequestCoordinator.swift`,
`RequestCoalescer` (T-255); `Features/Comments/CommentThreadRow.swift`
(T-247, and T-254 #7); `Models/Models.swift`; and `project.pbxproj`.

---

## Bugs

### B1 — "Jump Back In" is not what you read most recently (1g.6)

- **Files:** `Features/Search/MediaBrowserView.swift:239-254`
  (`jumpBackInEntries`), `:546-551` (`LibraryWorkSnapshot`), `:557-566`
  (`statsToken`), `:614-641` (`computeStats`).
- **Wrong today:** the doc says "the fandoms you were most recently reading",
  but the ranking is not by reading:
  - `readWorks` is sorted by `dateAdded`, not by last read.
  - The three slots fill in category order. If Anime & Manga has three read
    fandoms, a TV fandom read last night never appears.
  - `statsToken` changes only when the library's size or newest `dateAdded`
    does, so reading a work never refreshes the section.
- **Change:**
  - Add `lastReadDate: Date?` to `LibraryWorkSnapshot`, filled from
    `work.lastReadDate`.
  - Pull the ranking into a pure
    `static func jumpBackInFandoms(works: [LibraryWorkSnapshot],
    categoryFor: (String) -> String?, limit: Int) -> [(fandom: String,
    categoryID: String)]`. It walks read works newest-read first
    (`lastReadDate ?? dateAdded`), takes the first `limit` distinct fandoms
    that map to a category, and keeps the display spelling.
  - Build `jumpBackInEntries` from that function, not from the per-category
    lists.
  - Add the newest `lastReadDate` to `statsToken`.
- **Test:** two read works, the one added earlier but read later in category
  B, and the other added later but read earlier in category A: B's fandom comes
  first. A fandom seen twice appears once.

### B2 — The comment budget counts graphemes; AO3 counts code points (1ba.2)

- **Files:** `Features/Comments/CommentsView.swift:1169-1173`.
- **Wrong today:** `10_000 - model.composerText.count`. AO3 validates the raw
  text with Rails `validates_length_of`, which uses Ruby `String#length`: code
  points (Q15). A comment that shows "5 left" but contains a few multi-scalar
  emoji is rejected.
- **Change:** move the arithmetic into
  `static func remainingCharacters(for text: String) -> Int`, returning
  `characterLimit - text.unicodeScalars.count`. `canPost` keeps reading it.
- **Test:** "a" + "👨‍👩‍👧" (five scalars) leaves `10_000 - 6`; ten thousand
  ASCII letters leave 0.

## Small gaps (no owner decision)

### B3 — Jump Back In cards usually show no work count (1g.7)

- **Files:** `Features/Search/MediaBrowserView.swift:248`.
- **Change:** look the fandom up in the category's full cached list
  (`catalog.fandoms(for: category)`), case-insensitively, instead of only among
  the twelve cluster chips. Fold it into B1's pure function by passing a
  `workCountFor` closure.
- **Test:** with B1's test, a fandom outside the top twelve still gets its
  count.

### B4 — A doc comment misstates how AO3 picks featured fandoms (1g.2)

- **Files:** `Features/Search/MediaBrowserView.swift:525-530`.
- **Fact:** Q23. `/media` lists each category's five most-used canonical
  fandoms, ranked by count, not hand-curated.
- **Change:** the comment should say the cluster applies AO3's own rule (most
  used first) at twelve instead of five. The behaviour is unchanged.
- **Test:** none.

### B5 — The fandom list has no header or tally (1al.3)

- **Files:** `Features/Search/FandomListView.swift:134-146`.
- **Spec:** 1al: kicker "Browse", title the category, tally "9,412 tags in
  8,106 fandoms · A–Z"; 1an filtered: "1,204 of 9,412 tags · most works".
- **Change:** a first `Section` holding
  `SubjectHeaderBlock(kicker: "Browse", title: category.name, subtitle: tally,
  palette: palette)` above the sort rail. The tally comes from a pure
  `FandomListTally.text(totalTags:families:shownTags:isFiltered:sort:)` over
  numbers the view already holds (`fandoms.count`, `families.count`, and
  `FandomFamilyFilters.tagCount(in: filtered)`).
- **Test:** `text(9412, 8106, shown: 9412, isFiltered: false, sort:
  .alphabetical) == "9,412 tags in 8,106 fandoms · A–Z"`; filtered →
  "1,204 of 9,412 tags · most works". Numbers go through `.formatted()`, so pin
  a fixed locale in the test or build the expectations with `.formatted()`
  too.

### B6 — The Kudos chip is drawn neutral; the board fills it (1a.1b)

- **Files:** `Features/WorkDetail/WorkDetailAO3Actions.swift:43-60`, `:91-108`.
- **Spec:** 1a: "Kudos filled, since it is the one the app is named after".
  The board draws it in the tinted chip style (accent 22 % fill, accent 40 %
  hairline), while Subscribe, Bookmark and Mark for Later are neutral.
- **Change:** give `chip(...)` a `style` parameter (default: today's
  `isDone ? .tinted : .neutral`) and pass `.tinted` for Kudos. The doc comment
  at :55-60 should say the fill is emphasis, not a state. No state is claimed,
  as before.
- **Test:** none (visual). Screenshot at the Mac.

### B7 — Work Detail prefers the stored figure over the fresher remote one (1a.5)

- **Files:** `Features/WorkDetail/WorkDetailView.swift:522-540`.
- **Change:** a pure `WorkDetailFigures.preferred(local: Int?, remote: Int?)
  -> Int?`. It returns `remote` when present; otherwise `local` if it is > 0;
  otherwise nil. Use it for kudos, comments, bookmarks and hits. The remote
  summary is the fetch the screen just made; the stored value is the last
  refresh.
- **Test:** (local 412, remote 500) → 500; (412, nil) → 412; (0, nil) → nil;
  (0, 0) → 0. A printed zero from AO3 survives.

### B8 — The empty Series card lacks its title and the Safari line (1az.2)

- **Files:** `Features/Authors/AuthorProfileContentSections.swift:465-480`,
  `Features/Account/AccountExternalNavCard.swift`.
- **Spec:** 1az: "No series yet" above "You have not made a series."; under
  the button, "Opens archiveofourown.org in Safari. Posting is not something
  the app does."
- **Change:** add the title line. Add an optional `footnote: String?` to
  `AccountExternalNavCard` (default nil, so other callers are unchanged) and
  pass the line here. "Browse" is the app's word for its in-app browser (see
  1aa's "Opens on AO3 in Browse"), so use that rather than "Safari" if the card
  opens in-app.
- **Test:** none (copy).

---

## Needs the owner

- **1f.5 — Comment thread depth.** At `c4ce1e2` the thread shows a root plus
  two replies, then Continue thread. T-247 built inline threading to depth 5
  (`CommentThreadGeometry.maxInlineDepth`). AO3's own rule (Q13) is to cut off
  at depth 5 only when more than one reply remains, and its "N more comments"
  count is the whole subtree.
- **1an.2 — what "I have downloads from" means.** Today it means kept
  permanently (`isSaved`). The Library's Downloaded shelf means on disk
  (`hasEPUB`). critic-wave3 marked this UNSURE: pick one meaning for both.
- **1f.4 — streaming older comments.** Already decided: keep paging.

## Later

- **1al.4 — "Group variants" switch** (M). This renders the raw tag list with
  the same sorts.
- **1a.4 — Work Detail's Activity "Progress"** is fixed by home-library H5:
  switch `WorkDetailSections.swift:471` to the same helper, in the same commit
  as H5.
- **Comment signed-out action row gap.** Handoff's owner list, unchanged.
