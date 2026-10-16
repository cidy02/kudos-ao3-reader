# Brief 3fm: A59's remaining rows (Marked for Later, Subscriptions, Dashboard, comments polish)

Rules (binding): work only in this worktree (`~/kudos-agent-codex`, branch
`android/agent-codex-3fm`, at the lane's HEAD named in the dispatch); don't commit, push, or
switch branches; never sign in and never contact archiveofourown.org; no stub files; no helper
scripts or `.orig` files left behind; **don't edit `TASKS.md`**. No Room schema or
backup-format change (stop and say so if one seems needed). Your sandbox can't run Gradle:
Claude builds, tests and commits, so make what you write compile (`SavedWork` needs an
`author`; give test works a fixed millisecond `dateAdded`, since Room keeps milliseconds).
**Write your result file early and keep it current**, so a usage limit cannot leave it empty:
`docs/android-port/briefs/3fm-result.md`. Binding: `docs/AO3_NETWORKING_POLICY.md`.

Your A59 (`docs/android-port/audits/A59-result.md`; read Claude's triage at its top). Claude has
fixed the six priority items and the History note. These **missing** rows remain. For each:
confirm it against the code at HEAD first, then fix it as iOS does
(`/Users/cidy02/kudos-ios-polish/`, read-only) with a test porting the iOS assertion, or say
why it isn't real. In this order; stop where you run out of time and say where.

1. `AO3MarkedForLaterScreenTests`: `allSplitsUpdatedAheadOfEverythingElse`, `allDropsAnEmptyRun`,
   `narrowedPillsAreOneList`, `anEmptiedPageReloadsOneThatHasRows`, `downloadLineRequiresARealSize`,
   `downloadLineUsesTheSharedFileSizeLabel`.
2. `AO3SubscriptionsScreenTests`: `chapterRangeIsTheGapAfterTheWatermark`,
   `rangeFollowsTheWatermarkAndThePostedSideOfTheChaptersString`,
   `enrichmentIsWhatMakesAnIndexRowUpdated`, `rangeAgreesWithTheNewChapterCount`.
   (Watermarks now skip unknown counts: `SubscriptionWatermarks.parsePostedCount` is `Int?`.)
3. `AO3AccountListCountsTests.dashboardNavSeedsCountsWithoutOpeningAnyList`: seed counts from the
   dashboard nav the profile header already parses (no new request). Counts are now keyed by
   `AO3AccountListCountsCache.scope(username, generation)`.
4. `AO3DashboardTests`: `missingGroupsAreEmptyButMalformedGroupDoesNotEraseItsSiblings`,
   `dashboardNeverLoadsTheFullListsOrAboutAndScopeSwitchReloadsOnlyDashboard`.
5. `AO3AuthorProfileTests.parsesSeriesAndBookmarkMetadata`;
   `AO3TagAutocompleteTests.canonicalAndCountAreParsedWhenPresent`.
6. `AccountMoreOnAO3Tests`: `siteWideURLNormalizesLeadingSlash`, `userScopedURLBuilding`.
7. `CommentPolishTests`: `theTrayIsFourColumnsUntilAccessibilitySizes`,
   `aSignedOutStripDoesNotReserveTheReplyBand`.
8. `AO3MarkupTests.bothSurfacesSelectTheSameSpanForTheSameInput` (the comment tray now goes
   through `WritingMarkup.insertion` for all but Heading and an empty-URL Link).

Leave to Claude: `AO3AccountWorksSessionReloadTests.aClearedAccountKeepsNoRowsOrUnsubscribePath`,
`AO3InboxAccountTransitionTests.queuedATapCannotSubmitTheEquivalentBRow`,
`CommentsInitialIntentTests.composeIntentIsInertWhenSignedOut`,
`AO3SubscriptionsScreenTests.enrichmentFromAnOldGenerationIsNotRecorded`.
