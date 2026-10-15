# A55: iOS's request-building and write rules: does Android's code keep them?

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/A55-result.md`. **Leave no other file behind.** Do not edit `TASKS.md`.

The method of your A52 and A54 (`docs/android-port/audits/A52-result.md`,
`A54-result.md`), applied to what a quiet mismatch would send wrongly. Android:
`~/kudos-android-lane` at `f4a7a283` (read-only). iOS: `/Users/cidy02/kudos-ios-polish/`
(read-only; `kudos-ao3-reader/`, `KudosTests/`). Binding: `docs/AO3_NETWORKING_POLICY.md`
(a write only on the reader's tap, sent once, never retried; nothing read that the reader did
not ask for).

Read these iOS test files, every `@Test` in them (not only the ones A25 or A16 named):
`SearchURLTests`, `FilteredWorksURLTests`, `FandomWorksURLTests`, `SearchFiltersTests`,
`SearchPanelRulesTests`, `SearchPaginationTests`, `AO3URLResolverTests`,
`AO3WriteActionsTests`, `AO3WriteDispatchFenceTests`, `AO3AuthorActionFencingTests`,
`AO3ChallengeWriteStubTests`, `AO3ChallengeFormTests`, `CollectionItemsWriteVerificationTests`,
`CommentSubmissionTests`, `AO3PostingPseudTests`, `DownloadOnSubscribeTests`,
`BrowserNavigationVerdictTests`.

For each test: quote its assertion (`file:line`), say in one line what it guarantees (which
request, which field, which verdict), then **kept** (quote the Kotlin, `path:line`; where
Android has its own test of it, name it), **missing** (quote the code that breaks it; say what
goes to AO3 wrongly, or what the reader is told wrongly), **not applicable** (no such feature
on Android: say which), or **unsure**. Without quotes on both sides it is **unsure**.

Weigh most: a parameter iOS sends that Android drops or names differently (a search that
quietly returns other works), a write that can go twice, go without a tap, or report success
without AO3's evidence, a token taken from the wrong form, a posting pseud lost.

## Report

A table per test file, then **the missing ones worth fixing first**, one line each, the most
harmful first. Stop where you run out of time and say where. Say plainly where Android is right.
