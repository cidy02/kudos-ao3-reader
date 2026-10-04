# Brief 3w result: account-list toolbar

## Changes

Worked only in `/Users/cidy02/kudos-agent-gemini`, on the existing
`android/agent-gemini-3w` branch. No commits, pushes, branch switches, sign-in,
AO3 contact, Gradle execution, schema/backup edits, or `TASKS.md` edits.

`AccountWorksListScreen.kt` now places the existing `FilterButton` before the
overflow menu. It opens `SearchFilterSheet` in a new opt-in refine mode:
facets narrow the loaded page immediately, preserve AO3's ordering, and never
run a search. Done dismisses the panel; Reset and the filter button's existing
long-press clear action reset the facets. Search-only Sort by, Crossovers and
Updated controls, the search-specific tag footer, and the bottom Close/Save
row are absent in refine mode. Existing search/browse callers retain their
default sheet behaviour.

The new `search/AO3SummaryFilter.kt` ports iOS's local summary matching for
Android's existing facets: include/exclude tags, rating and its Exact/Rating+/
Rating- rules, Include Not Rated, warning/category selections, completion,
language and word bounds. Includes are ANDed; exclusions match across tag
groups; Underage's alternate spelling is recognised; missing word counts stay
visible. Android's subscription metadata lacks an `isComplete` field, so
completion can also be read from its posted/total chapter text. No filter or
setting model was extended.

Subscriptions' scope, watermarks and confirmed row suppression are shared with
the toolbar, so the new Mark All as Seen action updates the same counts the
Updated pill, groups and badges read. It calls the existing
`SubscriptionWatermarks.markAllSeen` for the refined loaded page, using only
rows with a numeric posted chapter count. Other pages and Marked for Later's
separate watermark namespace are preserved. Unknown chapter counts are not
baselined as zero. First known counts baseline without producing a badge;
existing watermarks retain their badge until explicitly marked seen.

As iOS's toolbar backing does, the screen fills in the loaded subscriptions
page after it is drawn, using the existing `AO3SparseWorkEnricher.enrich`.
The walk is sequential, page-bounded, and owned by `LaunchedEffect` keyed to
the list kind, loaded works and observable auth state. Changing those keys or
leaving the screen cancels further handoffs. An already handed-off lookup is
owned by the enricher's existing application scope; the cancellation check
prevents its result from being applied to the departed effect. These are the
existing anonymous metadata requests through `AO3WorkMetadataRepository` and
`OkHttpAO3Client` pacing/coordinator, sharing cached and in-flight lookups with
the rows. There is no new endpoint, authenticated crawl, background sweep or
polling. `AO3SparseWorkEnricher.kt` changed only its outdated row-only comment.
No requests were exercised during this work.

Refine judges a subscription against its enriched summary, retaining an
index-only row until enough metadata exists to judge it. The panel shows the
iOS live match line and separately counts rows not checked yet. Refinement is
independent of the lists' existing All/Updated/Downloaded, bookmark and history
pills. Their strings and row-action callbacks remain in place.

Claude's completed mature-content implementation was retained: the shared
`PrivacyGate`, `visibleEntries`, `PairedWorkRow`, `LibraryPrivacy.visibility`,
and `AccountListPrivacyTest` were not rewritten.

## Each iOS toolbar item

“Loaded works” below means signed in, successfully loaded with a nonempty
unrefined page, and, for Subscriptions, the Works scope. An active filter that
matches nothing does not strand the filter button. If neither mature privacy
nor loaded works needs the toolbar, the entire cluster is absent.

| iOS item, in order | Android result | Conditions / missing backing |
|---|---|---|
| Filter button and Refine panel | Added on all four lists | Loaded works only. Uses existing filter model/button/sheet, with local matching and a live count. Subscriptions' Series/Authors scopes have no filter. |
| Mature reveal toggle | Already present; retained | Only while `settings.privacy.hideMatureContent` is on, including loading/empty/signed-out states and Series/Authors. Eye icon and shared session reveal state. |
| Display mode picker | Omitted | `SettingsRepository` and `KudosSettings` have no account-wide equivalent of iOS's `account.displayMode`. Other screens' private layout enums/preferences are not this setting. It would need an account display preference plus the corresponding Compact/Ledger/Detailed rendering in these browsers. Marked for Later and Subscriptions must never offer it. No preference was invented. |
| Expand All | Retained, with corrected list/loading/scope gates | Available for loaded Bookmarks/History (also the existing generic account lists). Absent on Marked for Later/Subscriptions, as in the actual iOS toolbar. Android currently draws detailed cards and has no compact account layout to check. Future display-mode support must also hide it in Compact. |
| Mark All as Seen | Added | Subscriptions only, in Works scope, with loaded works and at least one refined-page row having new chapters. iOS's `tracksNewChapters` is Subscriptions only: Marked for Later keeps its separate visit clock and does not offer this action. Local watermark write; no AO3 write. |
| Clear History and its destructive confirmation | Omitted | Android's `AccountListRepository` has no AO3 clear-reading-history call, and no equivalent was found in the auth/network repositories. `WorkRepository.softDeleteAllFinished` concerns the local library and cannot substitute. The existing History browser contains an unreachable confirmation that only suppresses loaded rows; wiring that would falsely claim the entire AO3 history was cleared. It remains untouched, including its strings. A real implementation needs the AO3 confirmation-form read and single-shot, CSRF/session-fenced submission, then a success/error path for this screen. |

The Refine panel reuses Android's existing controls rather than porting all
of the newer iOS panel. In particular Android's `AO3SearchFilters` has no
`chapterCount` / single-chapter facet, so no Chapters picker was invented.
Tag entry remains the existing include/exclude fields with local suggestions
from paired works on the loaded page; no AO3 autocomplete repository is
passed. Word bounds remain the existing text fields rather than iOS sliders.

## User-visible strings

New literals (iOS verbatim):

- `Mark All as Seen` — overflow action.
- `Refine` — sheet title in refine mode; existing search-mode `Filters` stays.
- `Done` — checkmark accessibility label in refine mode; existing search-mode
  `Apply filters` stays.
- `{matching} of the {total} {work|works} on this page {matches|match}` — live
  count. `work` is singular when total is 1; `matches` when matching is 1.
- ` · {pending} not checked yet` — appended when unknown subscription rows are
  retained under active facets.

Newly reused on these account lists, without editing their existing literals:
`Filter`, `Clear All Filters`, and `Reset filters`, plus the existing sheet's
facet headings, enum choices, tag include/exclude fields and word-bound labels.
Their literals remain in `ui/subject/SubjectComponents.kt`,
`search/SearchFilterSheet.kt`, `search/TagSuggestField.kt` and
`network/ao3/search/AO3SearchFilters.kt`.

No existing screen string was changed or removed. In particular, the brief's
explicit string-preservation rule keeps `Expand All` / `Collapse All`; current
iOS's helper says `Expand All Cards` / `Collapse All Cards`. `Show mature` /
`Hide mature` and their eye icons were already landed by Claude. The two dead
`Hide Mature Content` / `Show Mature Content` labels were already gone.

## Signatures

- `AccountWorksListScreen`, `AccountListViewModel`, its factory, and the one
  `AppNavHost.kt` call: unchanged.
- `SearchFilterSheet`: appended `refine: Boolean = false` and
  `refineMatchText: String? = null`. All three existing search/browse callers
  use named arguments and require no changes.
- Private `SubscriptionsBrowser`: added
  `watermarks: Map<Long, SubscriptionWatermark>`, `scope: String`,
  `onScopeChange: (String) -> Unit`, and
  `onUnsubscribeWork: (CanonicalWork) -> Unit`. Its single call is updated.
  Scope taps still change scope, and the confirmed Unsubscribe still performs
  its existing local row suppression; this brief does not introduce a remote
  unsubscribe write. Suppression is reset with the loaded page/auth state.
- New internal helpers in `AO3SummaryFilter.kt`:
  `AO3SearchFilters.matchesSummary(AO3WorkSummary): Boolean`,
  `AO3SearchFilters.includesAccountWork(AO3WorkSummary, subscriptions: Boolean): Boolean`,
  `AO3WorkSummary.isSubscriptionIndexOnly(): Boolean`,
  `AO3WorkSummary.hasPostedChapterCount(): Boolean`, and
  `refineMatchText(total: Int, matching: Int, pending: Int): String`.
- No existing repository, privacy helper, model, storage or backup signature
  changed. The added test class is `AO3SummaryFilterTest` (six tests).

## Mature and Explicit works on each list

This table assumes Hide mature content is on and the work has not been
revealed, and describes rows that pass the ordinary refine/pill filters.
Both Mature and Explicit follow the same rule. “Paired” means the AO3 work
matches a work in the reader's library.

| List | Blur: paired | Blur: unpaired | Hide: paired match | Hide: unpaired |
|---|---|---|---|---|
| Marked for Later | Local row is obscured; one tap reveals that work. Pairing and local Downloaded state remain. | Plain remote row, never obscured or privacy-hidden. | Match is unpaired before drawing; plain remote row, no local Downloaded state and no match for the Downloaded pill. | Plain remote row, never privacy-hidden. |
| Bookmarks | Local row is obscured; one tap reveals that work. AO3 bookmark note/tags/date/privacy/recommendation information remains the bookmark's remote information. | Plain remote row with the AO3 bookmark information, never obscured or privacy-hidden. | Match is unpaired; plain remote row with AO3 bookmark information, no local state. | Plain remote row with AO3 bookmark information, never privacy-hidden. |
| History | Local row is obscured; one tap reveals that work. In progress/Finished pills can still read the paired local state. AO3 visit facts remain. | Plain remote row with AO3 visit facts; no local progress state, and never obscured or privacy-hidden. | Match is unpaired; Everything can show the plain remote row and AO3 visit facts. It no longer matches In progress/Finished because those pills require local state. | Plain remote row with AO3 visit facts; no local progress state, and never privacy-hidden. |
| Subscriptions (Works) | Local row is obscured; one tap reveals that work. Remote chapter counts/Updated filtering remain independent of the privacy gate. | Plain remote row, enriched as before, never obscured or privacy-hidden. | Match is unpaired; plain remote row with remote chapter/update information, no local state. | Plain remote row, enriched as before, never privacy-hidden. |

For all four lists, Show mature reveals all through the shared session gate.
In Blur it removes the obscuring; in Hide the library match is paired again.
Hide mature resets the gate's revealed-all and individual reveals. If Hide
mature content is off, the menu toggle is absent and matched local rows are
visible normally. The existing biometric requirement applies to revealing.
Plain remote rows stay outside the mature privacy gate even after enrichment.

## Verification / handoff

Read the iOS lane's `AO3AccountWorksList.swift`, toolbar helpers,
`AO3FilterPanel.swift`, `AO3SummaryFilter.swift`, `AO3SubscriptionsRefine.swift`
and rating/warning helpers; read Android's real filter, settings, account,
privacy, watermark, enrichment and network symbols and all sheet call sites.
`git diff --check` passes. `AccountListPrivacyTest` remains unchanged.

Added six pure JUnit regressions in `search/AO3SummaryFilterTest.kt`: combined
facets and stable ordering; rating ladder and unrated toggle; sparse subscription
retention/rejection after enrichment; subscription completion and missing words;
unknown chapter count eligibility; and singular/plural/pending live-count text.
No tests, Gradle build or UI verification were run in this sandbox.

Claude's next step: run Android assemble and unit tests, including
`AO3SummaryFilterTest`, `AccountListPrivacyTest`, `AO3SparseWorkEnricherTest` and
existing search-filter tests. Verify toolbar conditions, live filter/Reset/Done,
Updated → Mark All as Seen, and each table cell using demo/offline data. Check
the existing Search/Browse sheets still retain their search controls. No live
sign-in or AO3 request is needed for that review. Changes are intentionally
left uncommitted for pickup.
