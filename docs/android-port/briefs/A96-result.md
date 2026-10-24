# A96 — series and author Bookmarks parity

Status: implementation and six regression tests written; static diff review complete.
Claude's build/test and fresh device screenshot verification remain pending.
Worktree: `kudos-agent-codex`, branch `android/agent-codex-a96` (base `67f02ddf`).
The supplied brief is preserved. No TASKS edits, commits, pushes, branch changes,
Gradle runs, sign-in, or AO3 requests are authorized for this task.

## Item evidence and verdicts

iOS paths below are relative to `~/kudos-ios-polish/kudos-ao3-reader/` (read only).

1. **Real difference.** `Features/Authors/AO3SeriesDetailView.swift:56` uses
   `AO3SeriesRow` in its default standard presentation
   (`Features/Authors/AuthorProfileComponents.swift:250`). The standard row's
   figures use `WorkStatLabel` with stack, text-size, bookmark, lock,
   completion/in-progress and calendar symbols (`:414-449`), independent of
   demo identities. Changed `author/AuthorProfileComponents.kt:394-402` to reuse
   Android `WorkStatLabel` and `WorkStatIcons` plus existing Material symbols.
   The FlowRow still wraps between complete figures; zero and absent values keep
   their existing distinctions. Existing figure text and date values stay intact.
2. **Real difference.** The standard series row calls `AO3AuthorBylineView`
   (`Features/Authors/AuthorProfileComponents.swift:394-398`); linked names use
   `.tint` (`UIComponents/AO3AuthorNavigation.swift:194-196`), unlinked names
   `.secondary` (`:219-223`). The row does not override tint with its fandom
   palette. The ledger presentation uses the same byline (`:347-350`). Changed
   the shared Android creator helper (`author/AuthorProfileComponents.kt:409-423`)
   to use `tokens.scopePalette.accent` for a routed creator and retain secondary
   ink otherwise. Both its standard and ledger callers use that helper; the
   fandom palette continues to color the ledger's fandom/series mark.
3. **Mixed: real missing prefix; identity-based color is already correct.**
   Series works choose local `SensitiveWorkRow` or remote `AO3WorkRow`
   (`Features/Authors/AO3SeriesDetailView.swift:196-213`). Both call the shared
   byline (`Features/Library/WorkRow.swift:220-224`,
   `Features/Search/AO3WorkRow.swift:115-120`). Its `includesBy` defaults true
   (`UIComponents/AO3AuthorNavigation.swift:94`), the prefix is secondary
   (`:144-146`), linked names are tinted (`:196`), and unlinked names are
   secondary (`:219-223`). Demo local works have no seeded author identities
   (`App/DemoLibrary.swift:25`, `:126`); Android seeds them (`app/DemoLibrary.kt:387`).
   Real AO3 work blurbs parse their author-link hrefs into identities
   (`Services/AO3Client.swift:1962-1968`); registered and orphaned identities have
   routes (`Models/AO3AuthorModels.swift:197-199`). Thus real linked names remain
   accent; anonymous/unlinked names remain grey. The grey-demo observation is
   not a rule to grey every real author. Changed the existing detailed-row
   byline call (`ui/components/SensitiveWorkRow.kt:308-310`) to `includesBy = true`.
   No change to the identity resolver, colors, or navigation in
   `works/detail/WorkDetailIdentity.kt`. This shared call also correctly gives
   other detailed remote cards the iOS standard-row prefix; local cards already
   had it. Selection's existing ledger row already has its own combined prefix
   (`ui/components/SensitiveWorkRow.kt:592-597`) and needs no change.
4. **Real difference.** The standard series row uses a `books.vertical` fandom
   label (`Features/Authors/AuthorProfileComponents.swift:400-405`) with
   secondary ink and up to two lines. Changed
   `author/AuthorProfileComponents.kt:384-390`: decorative, font-scaled Material
   library-books icon beside secondary fandom text constrained to two lines.
   Empty fandom lists still show neither icon nor text.
5. **Real difference.** AuthorProfileView delegates Bookmarks to
   `AO3AuthorBookmarksSection` (`Features/Authors/AuthorProfileView.swift:474`).
   The scroll compact heading is mixed-case, secondary semibold subheadline
   (`Features/Authors/AuthorProfileContentSections.swift:634-637`); the list
   heading is `Section("Bookmarks")` (`:666`) in a plain list
   (`UIComponents/AppThemeSurface.swift:230-238`). The supplied Dark screenshot
   also shows mixed case. Changed `author/AuthorProfileScreen.kt:1038-1043` to
   existing Text with the shared gutter, secondary ink, 15sp semibold type and
   zero tracking, plus heading semantics. Other `SectionRuleHeader` callers
   retain their existing style. Updated the existing heading/pagination test
   (`author/AuthorProfileSortScreenTest.kt:109-114`) to find this section heading
   separately from the same-named tab label.

Dates (Q28) and the extra local-library bookmark card (decision 3gx) are out of scope.

## Tests and verification

Android production paths above are relative to
`android/app/src/main/java/io/github/cidy02/kudos/`. All six new tests are in
`android/app/src/test/java/io/github/cidy02/kudos/app/BriefA96ContentTest.kt`, using
the Robolectric native graphics/Compose pattern from `Brief3hcContentTest.kt`.

| Test (line) | What it checks | Expected failure with the fix reverted |
|---|---|---|
| `seriesFiguresHaveIconsIncludingTheDateAndWrapAtLargeText` (111) | All six figure labels are displayed without overflow, with an icon's width before their text; figures wrap at normal and 2× text. | Restoring bare Text removes the figure row's semantics; removing only its icon fails the measured icon/text offset. |
| `inProgressHasAnIconAndMissingSeriesFiguresStayAbsent` (123) | In-progress has an icon; null counts/completion, unrestricted state and blank date emit no invented figures. | The reverted in-progress Text has no figure semantics/icon offset. The absence checks protect the existing nullable-data behavior. |
| `seriesCreatorsUseAppAccentForLinksAndSecondaryInkForGuestsInBothPresentations` (137) | Standard and ledger series creators use the chosen app accent across Light/Sepia/Dark/OLED; guests and "by" stay secondary; tapping a creator retains its parsed pseud route. | Restoring the fandom accent fails the linked-name color assertion (the test chooses a violet app accent and Star Wars fandom). |
| `seriesWorkBylinesIncludeByForLinkedAndUnlinkedNamesIncludingSelection` (158) | Parses registered identities from the existing series fixture; the detailed row includes one secondary "by", tints only linked authors and opens their pseud route; removing identities gives a non-clickable secondary name. Selection retains its existing combined prefix. | Restoring `includesBy = savedCard` removes the detailed remote row's standalone "by", failing its node-count assertion. Greying all names instead fails the registered-author color assertion. |
| `seriesFandomHasAQuietIconAndWrapsWithinTheCard` (185) | Icon precedes secondary fandom text in all four themes; long fandoms use two lines at 2× text; no icon for an empty list. | Restoring the plain fandom Text removes the icon node, failing lookup and geometry assertions. |
| `authorBookmarksUsesAMixedCaseSubheadlineAboveTheCards` (205) | Opens the actual author Bookmarks screen with fixture-only responses; asserts the mixed-case section heading's semantics, secondary ink, 15sp semibold type, zero tracking and placement before the cards in all themes. | Restoring `SectionRuleHeader` emits uppercase BOOKMARKS; mixed-case heading lookup fails and the uppercase-absence assertion also fails. |

These revert failures are derived from the assertions and source review, **not
executed mutation-test results**. Gradle/build/test execution is reserved for
Claude by the brief. The heading client handles only two fixture paths and strips
image URLs; other tests use local values/the existing parser and fixtures. No AO3
requests, sign-in, device installs, or demo routing changes were performed.

Static review: inspected both byline call sites, all series-creator helper
callers, the standard/ledger selection distinction, the existing heading test,
and the supplied iPhone Light series/Dark bookmarks screenshots. `git diff
--check` passes. No fresh Android screenshots were taken, so visual correctness
is not claimed. No commits, pushes, branch switches or TASKS edits were made.

Next: Claude runs `BriefA96ContentTest`, `AuthorProfileSortScreenTest`,
`Brief3gxParityTest`, `Brief3haContentTest` and the lane's full build/test gate,
then re-shoots seriesdetail and authorbookmarks against iPhone in the four themes
and largest text. The dated parity decision is recorded in
`docs/android-port/DECISIONS.md` under A96.
