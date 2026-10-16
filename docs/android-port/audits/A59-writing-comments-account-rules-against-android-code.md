# A59: iOS's Writing, Comments and AO3-account-screen rules: does Android's code keep them?

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/A59-result.md`. **Leave no other file behind.** Do not edit `TASKS.md`.

The method of your A52 to A58. Android: `~/kudos-android-lane` at `a0bddb6d` (read-only). iOS:
`/Users/cidy02/kudos-ios-polish/` (read-only; `kudos-ao3-reader/`, `KudosTests/`). Binding:
`docs/AO3_NETWORKING_POLICY.md`. **Write the priority list first and keep it current**, so a
usage limit cannot leave it empty.

Read every `@Test` in these iOS files: `WritingCheckpointTests`, `WritingPreviewChaptersTests`,
`WritingScreensPresentationTests`, `WritingSeriesCollectionsTests`, `WritingTagPickerTests`,
`WritingTextEditorTests`, `DraftExpiryTests`, `CommentMarkupTests`, `CommentPolishTests`,
`CommentsAccountTransitionTests`, `CommentsInitialIntentTests`, `CommentThreadReviewFixTests`,
`AO3MarkupTests`, `AO3TagAutocompleteTests`, `TagAutocompleteTests`, `TagWorksRequestTests`,
`AO3AuthorProfileTests`, `AO3DashboardTests`, `AO3AccountListCountsTests`,
`AO3AccountWorksSessionReloadTests`, `AO3BookmarksWorksBrowserTests`,
`AO3CollectionItemsScopeTests`, `AO3CollectionItemStagingTests`,
`AO3CollectionSessionReloadTests`, `AO3CollectionsFilterTests`, `AO3HistoryScreenTests`,
`AO3InboxAccountTransitionTests`, `AO3InboxPaginationFailureTests`,
`AO3MarkedForLaterScreenTests`, `AO3SubscriptionsRefineTests`, `AO3SubscriptionsScreenTests`,
`SubscriptionWatermarkTests`, `AccountHubRowsTests`, `AccountMoreOnAO3Tests`,
`CollectionModerationCopyTests`, `PromptMemeFixtureTests`, `OmittedFieldKeepsPreferenceTests`,
`UserFacingErrorTests`.

For each test: quote its assertion (`file:line`), say in one line what it guarantees a reader,
then **kept** (quote the Kotlin, `path:line`; Android's own test if any), **missing** (quote
the code that breaks it; say what a reader sees wrongly or loses), **not applicable**, or
**unsure**. Without quotes on both sides it is **unsure**.

Weigh most: a writer's text lost (a draft, a chapter, a checkpoint), a preview or a post that
sends what the writer didn't write, a comment going out marked up wrongly or under the wrong
account, a list or count that is another account's after switching, a staged change sent to the
wrong item, a preference AO3 had that a save quietly drops.

## Report

The priority list first (**the missing ones worth fixing first**, one line each, most harmful
first), then a table per test file. Say plainly where Android is right.
