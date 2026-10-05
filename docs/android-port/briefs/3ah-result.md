| Surface / empty case | Android before | iOS unfiltered | iOS filtered | Android after |
|---|---|---|---|---|
| Library dashboard: Reading Now | Section message, even when a filter hides the section | “You aren't reading anything yet. Open a work from your Library or find one in Browse.” | Same message | Same |
| Library dashboard: Saved for Later | Section message, even when a filter hides the section | “You haven't saved any works for later. Add a work to Saved for Later to see it here.” | **Same message, including the reported misleading case** | Same, following iOS |
| Library dashboard: Finished | “Works you mark as finished will appear here.” | Same | Same | Same |
| Library dashboard: Downloaded | “Download a work to read it without an internet connection.” | Same | Same | Same |
| Library dashboard: Reading History | “Works you open appear here with your reading progress.” | “Works you open appear here with your reading time, reread count, and any new chapters.” | Same as unfiltered | iOS message |
| Library dashboard: Favorites | “To add a favorite, use a work's menu or tap the star on its page.” | “To add a favorite, swipe a work in your Library or tap the star on its page.” | Same as unfiltered | iOS message |
| Library dashboard: Collections | “Use + above to create a collection for works you want to group together.” | Same | Same; work filters do not remove collections | Same |
| Entire Library dashboard has zero works, including a filter hiding every work | The individual empty sections above; no whole-Library empty card | The individual empty sections above | The individual empty sections above; **no whole-Library collision card** | Same structure |
| Library pushed Reading Now / Saved for Later / Finished / Downloaded / Reading History / Favorites: genuinely no section works after privacy | “Nothing here yet” + that section's message | Section title + section's message, with section icon | Same genuine-absence state, independent of filters | Section title + iOS message and corresponding Android icon in a subject panel |
| Those six pushed Library sections: section has works, panel filters hide all | “Nothing here yet” + section's message; hero incorrectly counted already-filtered works (usually 0) | Not applicable | Collision card C below; hidden count uses the section before filters | C; correct pre-filter hero count |
| Pushed Library Favorites: quick Rereads / Offline / WIP pill hides all, panel defaults | “Nothing here yet” + Favorites message | No empty body card; the header/controls remain | No collision card unless LibraryFilters is active (sort also counts as active in Swift) | Same lack of body card; active panel/sort uses C |
| Pushed Library Collections enum destination | “Nothing here yet” + “You have no collections yet. Use + above to create one.” | “Collections” + “You have no collections yet. Create one from your Library to group works together.” (placeholder) | Same placeholder | iOS title/message; the actual dashboard Collections chevron opens its separate Collections screen |
| Home Reading Now / Recently Updated / Favorites / Recently Opened: genuinely no section works after privacy (all layouts) | “Nothing here yet”, no description or actions | “Nothing here yet”, books icon, no description/actions | Same; genuine absence wins over filters/pills | Same strings, subject panel |
| Home section has works but panel filters hide all: Detailed / Ledger | Partial collision card: title + hidden sentence + Clear/Edit; no drops or collision explanation | Not applicable | C | Full C |
| Home Recently Updated: Unread or Offline pill hides all, but panel-filtered works remain: Detailed / Ledger | With panel filters: partial collision card; without: “No unread works” or “No offline works”, “Show All” | Pill empty state: “No unread works” / “No offline works”, “Show All” | **Pill empty state wins over the collision card** when filteredItems is nonempty | iOS branch order; Show All changes only the pill |
| Home section empty after filters/pill: Compact, panel filters or non-default sort active | Partial collision card if narrowing filters active; otherwise pill empty state | Not applicable | C whenever visibleItems is empty and LibraryFilters is active; counts ignore the update pill | C, including sort-active case |
| Home Recently Updated: only Unread/Offline pill hides all: Compact, panel defaults | “No unread works” / “No offline works”, “Show All” | Empty grid body; no pill empty-state card | Same with panel defaults | Empty grid body, following iOS |
| Library bulk “Add Selection to Queue” dialog, no custom queues | “No custom queues yet.”, “Close” | New queue input + Queues section/footer, no “No custom queues yet.” sentence (`ReadingQueues.swift:449–490`) | Library filters do not affect this dialog | Unchanged Android dialog; not a work-filter empty state |
| Library loading/error and Home initial-null snapshot | Library loading/error cards; Home temporarily follows its genuine-empty branch | Library initially shows dashboard skeletons; iOS queries do not use Android's repository-error branch | Unrelated to filter collisions | Loading/error behavior unchanged; Home's empty string unchanged |

C means the full iOS `LibraryFilterCollisionCard`: count-dependent title, hidden-count sentence, collision explanation when two or more narrowing filters are active, positive-count “Without …” drop rows, “Clear all filters”, and “Edit”. Exact strings are listed below.

Reference read: `/Users/cidy02/kudos-ios-polish`, HEAD `d0b85f4f`. Android starting HEAD: `60296bc8`, branch `android/agent-gemini-3ah`. Only this Android worktree was edited. No commit, push, branch switch, TASKS edit, sign-in, AO3 request, Room schema change, or backup-format change was made.

**The brief and iOS disagree about dashboard emptiness. iOS wins.** Both dashboard layouts still use `SectionEmptyState(kind.emptyMessage)` after filtering (`Features/Library/LibraryView.swift:358–375`, `499–517`). There is no call to `LibraryFilterCollisionCard` in that file. Consequently the reported dashboard Saved for Later sentence remains. The collision card is ported where iOS actually uses it: pushed Library and Home section lists. iOS also wins for Home's different Detailed/Ledger and Compact quick-pill branches, and Library Favorites' quick-pill-only empty body. These are observable limitations of the reference, not missing Android implementation work.

The table covers reachable screen branches, including the dialog's “no queues” message for completeness. The old private `LibraryCarousel` (still containing `EmptyStateCard("Nothing here yet", ...)`) and `ReadingQueuesShelf` have no callers in `LibraryScreen.kt`; their strings cannot currently appear on this screen. Separate Collections/Queue screens and Favorite Authors/Tags affinity lists are not implemented by the two requested Android screens and are outside this change.

## User-visible strings before → after

### Genuine absence / dashboard copy

| String or location | Before | After |
|---|---|---|
| Pushed Library genuine-empty title (each section) | “Nothing here yet” | “Reading Now”, “Saved for Later”, “Finished”, “Collections”, “Downloaded”, “Reading History”, or “Favorites” |
| Reading Now message | “You aren't reading anything yet. Open a work from your Library or find one in Browse.” | Unchanged |
| Saved for Later message | “You haven't saved any works for later. Add a work to Saved for Later to see it here.” | Unchanged on genuine-empty lists **and all empty dashboard shelves** |
| Finished message | “Works you mark as finished will appear here.” | Unchanged |
| Downloaded message | “Download a work to read it without an internet connection.” | Unchanged |
| Collections enum placeholder message | “You have no collections yet. Use + above to create one.” | “You have no collections yet. Create one from your Library to group works together.” |
| Reading History message (dashboard/list) | “Works you open appear here with your reading progress.” | “Works you open appear here with your reading time, reread count, and any new chapters.” |
| Favorites message (dashboard/list) | “To add a favorite, use a work's menu or tap the star on its page.” | “To add a favorite, swipe a work in your Library or tap the star on its page.” |
| Dashboard Collections | “Use + above to create a collection for works you want to group together.” | Unchanged |
| Home genuine-empty title | “Nothing here yet” | Unchanged |
| Home quick-pill titles / action | “No unread works”, “No offline works”, “Show All” | Unchanged strings in Detailed/Ledger; removed from Compact when panel defaults, as in iOS |
| Favorites quick-pill-only empty title/message | “Nothing here yet” + old Favorites message | No empty-state body text, as in iOS |
| Library queue dialog empty text/action | “No custom queues yet.” / “Close” | Unchanged |

Source for section titles/messages: iOS `Features/Library/LibrarySectionKind.swift:24–37,66–82`; genuine-empty pushed state: `LibrarySectionListView.swift:265–277`; Home genuine-empty: `HomeSectionListView.swift:128–129`. Dashboard Collections uses its separate text at `LibraryView.swift:437–440,553–556`.

### Collision strings (verbatim iOS templates)

Home previously had the following titles and hidden sentences, but lacked the collision suffix and drop controls. Pushed Library previously used “Nothing here yet” and the section's ordinary message instead of all these strings. Neither surface previously displayed drop labels/counts.

| Active narrowing labels | After title (already present in the old Home card) |
|---|---|
| 0 | “Nothing matches.” |
| 1 | “Nothing matches this filter.” |
| 2 | “Nothing matches both filters.” |
| 3 | “Nothing matches all three filters.” |
| 4 | “Nothing matches all four filters.” |
| 5 | “Nothing matches all five filters.” |
| 6+ | “Nothing matches all {N} filters.” |

- Hidden count 1: “Your 1 work in {sectionTitle} is hidden by this filter.”
- Other hidden counts: “All {N} of your works in {sectionTitle} are hidden by these filters.”
- With at least two active narrowing labels and a single filter failing alone, append: “ {label} matches no works here.”
- Otherwise, with at least two active labels, append: “ {joined labels} have no works in common here.”
- Two joined labels use “{A} and {B}”; three or more use “{A}, {B}, and {C}” (Oxford comma).
- “Drop one filter” (drawn uppercase, as iOS's textCase does).
- “Without {filterLabel}”.
- “1 work” / “{N} works”.
- Combined drop accessibility label: “Without {filterLabel}, {work count}”.
- “Clear all filters”.
- “Edit”.

Source: iOS `LibraryFilterEmptyState.swift:49–80,87–115,123–160`. The singular hidden sentence says “this filter” even with several active filters: preserved exactly. “Clear all filters” and “Edit” existed on the partial Home card; both are new on filtered-empty Library lists. Dropping replaces filters with that row's remainingFilters; Clear creates default filters and resets sort to Natural; Edit opens the existing panel. The independent Home update pill / Favorites quick pill is not reset by Clear, matching Swift.

Filter labels use the Swift member order: user tags, fandoms, characters, relationships, additional tags, excluded tags, rating, warnings, categories, completion, language, words (`LibraryFilters.swift:225–253`). Dynamic tag/language labels are their names; exclusions use “−{name}”. Identical labels gain “ (your tag)”, “ (fandom)”, “ (character)”, “ (relationship)”, “ (tag)”, “ (excluded tag)”, “ (rating)”, “ (warning)”, “ (category)”, “ (status)”, “ (language)”, or “ (words)” to disambiguate. Names for Android user tags are looked up from real Tag IDs; IDs never replace available display names.

Enum labels are the existing shared AO3 strings: ratings “General Audiences”, “Teen And Up”, “Mature”, “Explicit”, “Not Rated”; warnings “No Archive Warnings Apply”, “Creator Chose Not To Use Archive Warnings”, “Graphic Depictions Of Violence”, “Major Character Death”, “Rape/Non-Con”, “Underage Sex”; categories “F/F”, “F/M”, “Gen”, “M/M”, “Multi”, “Other”; status “Complete” / “In Progress”. No “Any” label is a member. Warning/category ordering follows enum declaration order, not alphabetical order.

Word labels: “Words {from}–{to}”, “{compact from}+ words” for a parseable lower-only bound (e.g. “50K+ words”), “Words ≥ {from}” otherwise, and “Words ≤ {to}” for upper-only. Both bounds are one member and are cleared together. Swift uses localized compact number formatting (`LibraryFilters.swift:419–422`, `UIComponents/CompactCount.swift:6–7`); Android uses the platform ICU short compact formatter with the current locale and parses a Long, preserving Swift's 64-bit lower-bound handling.

Android's retained old predicates are also removable if present: “Favorites”, “Finished”, “Unfinished”, “Downloaded”, “Not Downloaded”, collection names, and old rating-string selections. Their facet suffixes are “favorite”, “reading state”, “download”, “collection”, and “rating”. They are Android-only state compatibility; the new panel's iOS facets have the Swift ordering above.

### Hero counts

Library filtered-empty hero before: “0 works · none match the current filters” when the source was already filtered. After: “{pre-filter section N} {work/works} · none match the current filters”. Home already used the pre-filter section count; its string remains unchanged. This text is shown only when the base section contains works. Source: iOS `LibrarySectionListView.swift:302–306`, `HomeSectionListView.swift:69–75`.

## Count computation and iOS line references

| Count / decision | Swift source in the iOS lane | Android implementation |
|---|---|---|
| Base section / hidden count | Library `items` = `kind.works(from: works, visible: passesPrivacy)` at `LibrarySectionListView.swift:100–107`; card receives `items.count` and `items` at `321–328`. Home does the same at `HomeSectionListView.swift:51–56,78–85`. Section membership predicates live at `LibrarySectionKind.swift:120–181`. | `LibrarySectionKind.unfilteredItems(state)` rebuilds section membership from `state.collectionMembers`, which `LibraryQuery.buildState` retains before panel filtering and after privacy. Home already computes `sectionItems` before filtering. Card uses works.size, never global totalSaved or already-empty displayed rows. Saved for Later includes queue-only members; other shelves keep their existing exclusion rules. |
| Each drop's remainingCount | `LibraryFilters.swift:166–175`: copy all filters, clear exactly one member, `works.filter(remaining.matches).count`. | `LibraryFilterState.droppingEachActiveFilter`: clear the same member, count `LibraryQuery.filterOnly(works, filters = remaining)`. Every other narrowing predicate remains active. |
| Which drop rows appear | `LibraryFilterEmptyState.swift:17–23,42–85` | Only drops with remainingCount > 0. A zero-count drop is still computed but not offered. No fake estimate or full-facet marginal count. |
| Active count for title | `LibraryFilterEmptyState.swift:25–27,123–132`; summary excludes sort. | Number of individual active narrowing members (drops.size). Every selected tag/warning/category is one; both word bounds together are one; sort is zero. |
| Collision labels | `LibraryFilters.swift:185–201` | Clear every other member to evaluate each alone. Return the first singleton matching nothing; else first pair with no overlap in the supplied works; else every member. The pair order follows the same member order. |
| Existing matcher semantics | `LibraryFilters.swift:277–326` | Reuse `LibraryQuery.filterOnly`/matchesFilters from 3af: AND across/within facets, family fandom matching, categorized-tag fallback, exact flat exclusions, lenient rating, canonical warnings, case-insensitive language, and unknown word counts <= 0 are kept under word bounds. No second matcher was added. |
| Sort | `LibraryFilters.swift:33–38,153–155,213–216` | Can make LibraryFilters active but never narrows works or becomes a drop. New Clear actions reset the separately stored Android sort. |
| Home update pill | `HomeSectionListView.swift:91–98,301–317,421–425,495–500` | Detailed/Ledger shows “Show All” ahead of C if the pill alone empties nonempty filteredItems. Compact uses C if panel/sort active and otherwise has an empty body. C counts all base sectionItems, ignoring the pill, as Swift does. Unread uses hasUpdate; Offline uses the existing hasEpub equivalent. |
| Favorites quick pill | `LibrarySectionListView.swift:112–125,743–749,783–788` | Applied after panel filters. C receives the entire pre-filter Favorites section and does not add the quick pill as a member. With defaults and quick-pill-only emptiness no body card is shown. |

Android-only Library search has no counterpart in Swift LibraryFilters. It is held fixed **before** computing collision counts, so clicking a suggested drop returns the advertised count while search remains active. With an empty search (all iOS-comparable cases), the source is exactly the privacy-visible pre-filter section. Search-only zero results retain a plain empty state. Clear resets filters and sort, retaining the search and separate quick pill, consistent with the existing Android search binding and Swift's filter-only reset. No search predicate or invented search label was inserted into the Swift member set.

The new renderer is `library/LibraryFilterEmptyState.kt`: `subjectPanel(18.dp)`, theme glass fill/stroke, ordinary clickable rounded rows and capsule controls, theme-specific iOS destructive color (`UIComponents/SemanticThemeColors.swift:13–18`), and subject-accent count text. It uses no Material Card, Button, or OutlinedButton. Text may wrap and controls have a minimum 48 dp touch height (Android accessibility accommodation; iOS uses 42 pt footer controls). Genuine-empty and Home quick-pill states use the same subject-panel renderer, with their source strings and corresponding Android book/clock/check/collection/download/history/star or update-pill glyphs (the SF Symbols themselves are Apple-only).

## Tests and verification

Added `android/app/src/test/java/io/github/cidy02/kudos/library/LibraryFilterCollisionTest.kt`, eight tests. The first four retain the exact Swift method names from `KudosTests/LibraryFiltersTests.swift`:

| Test | What it checks | Swift counterpart |
|---|---|---|
| droppingEachActiveFilterCountsWorksRevealedByDroppingOne | Two disjoint predicates each reveal one work; returned remainingFilters actually produces the advertised count and keeps the other predicate | 148–170 |
| collidingFilterLabelsNamesTheDisjointPair | Identifies rating/status rather than the English bystander; an impossible French filter is named alone; zero-reveal bystander row is suppressed | 199–221 |
| sameNamedFiltersOnDifferentFacetsStayDistinct | Tag/language both named English have distinct IDs and facet-labelled text; neither drop reveals a work | 226–238 |
| droppingEachActiveFilterTreatsWordBoundsAsOneMember | Complete vs 50K lower bound collision; two-sided bounds are removed together as one member and counts remain correct | 241–261 |
| tripleCollisionFallsBackToAllMembersWhenEveryPairOverlaps | Three predicates whose pairs overlap but triple does not; all labels returned and each drop reveals one | Additional coverage |
| individualTagMembersAndUnknownWordCountsUseTheExistingMatcher | Only the missing selected user tag reveals a row when dropped; other tags held; unknown word count kept; exclusions drop individually | Additional coverage |
| sectionCountsAreBeforeFiltersButAfterPrivacyAndMembership | Saved for Later has 0 displayed rows but 2 recoverable pre-filter rows; hidden Explicit and unrelated work excluded; queue-only Saved for Later work included; sort/defaults have no members | Additional coverage |
| collisionStringsKeepIosSingularPluralAndJoinedList | All seven title variants, exact hidden singular/plural, singleton explanation, disjoint-pair and Oxford-comma explanations | Additional coverage |

Robolectric sdk 35 supplies the real platform ICU formatter for the word-label test; English locale is set and restored by the suite. Existing matching regressions remain in `LibraryFiltersTest`; section/pill tests remain in `LibrarySectionKindTest` / `LibrarySectionQuickFilterTest`.

**Performed:** read real Kotlin constructors/enums/call sites, filter matcher, section membership, theme surface APIs, test dependencies, and the source Swift above; `git diff --check` passed. **Not performed:** Gradle build, unit-test execution, emulator screenshots, or accessibility interaction. Per the brief, Claude must build/test afterwards. No build success or visual correctness is claimed.

Claude can run from `android/`:

```sh
./gradlew :app:assembleDebug :app:testDebugUnitTest --tests 'io.github.cidy02.kudos.library.LibraryFilterCollisionTest' --tests 'io.github.cidy02.kudos.library.LibraryFiltersTest' --tests 'io.github.cidy02.kudos.library.LibrarySectionKindTest' --tests 'io.github.cidy02.kudos.library.LibrarySectionQuickFilterTest'
```

## Emulator checks still required

Use local imported/seeded works while offline; stay signed out and block AO3 traffic.

1. Library dashboard in Shelves and Ledger: empty individual sections and a wholly empty Library use the ordinary iOS section messages. Explicitly record the misleading Saved for Later sentence remains under a rating filter, because that is what the reference does. Verify changed History/Favorites copy and unchanged Collections copy.
2. Pushed Saved for Later: prepare one Complete Explicit work and one WIP Teen work in the section. Set Teen And Up + Complete: hero says “2 works · none match the current filters”; card says “Nothing matches both filters.” and the two-filter collision sentence; “Without Teen And Up” and “Without Complete” each show “1 work”. Tap each from a freshly restored collision and check its displayed result count.
3. Add English to both fixture works and the filters: title counts three filters, collision explanation still names rating + Complete, and no zero-count English drop row appears. Replace English with Français: explanation names Français alone; if no single drop recovers any row, omit the entire Drop one filter block.
4. Test word range, multiple selected tags, excluded tags, same-named English user tag/language, and a work with unknown word count. Check facet suffixes and that dropping a word member clears both bounds. Hide-mode mature works and works outside the section must not inflate hidden/drop counts; obscure-mode works stay eligible without being revealed by a filter action.
5. Clear all filters resets both filter state and sort to Natural. Edit opens the real 3af panel and closing it keeps the edited state. Privacy mode and repository records remain unchanged. Test one-work hidden copy as well as plural copy.
6. Home Reading Now, Recently Updated, Favorites, Recently Opened: filter collisions use the same card in Detailed, Ledger, and Compact. Truly empty sections show only “Nothing here yet”, even if filters are active.
7. Home Recently Updated Detailed/Ledger: a panel leaves some works but Unread/Offline pill hides all → “No unread works” / “No offline works” + “Show All”. Show All retains panel filters and restores filtered rows. When the panel itself leaves nothing, show C instead.
8. Home Compact: pill-only emptiness with panel defaults has no body card; with an active panel/sort it has C. Confirm counts are the base-section drop counts, not pill-filtered counts; Clear intentionally retains the pill. Record this reference behavior rather than silently correcting it.
9. Favorites quick-pill-only emptiness: default filters leave header/controls and an empty body; activating panel/sort permits C, whose counts ignore the quick pill. Clear retains the quick pill, as in iOS.
10. Light, Dark, Sepia, OLED; narrow phone and tablet; largest font scale; long tag names. Check the subject-card family, multiline title/detail, count alignment, red Clear capsule and outlined Edit, whole-row touch targets, TalkBack labels, and no clipping under chrome. Take screenshots; this session did not see the UI.
