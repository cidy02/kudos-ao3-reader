# Brief 3fg — A55 write and request faults

Implemented in the assigned worktree on `android/agent-codex-3fg`, starting at
`23b93e2a0113a52f6d466e2ba28d609edd16b203`. Changes are uncommitted for Claude.
No branch switch, commit, push, sign-in, AO3 contact, Gradle invocation, Room schema
change, backup-format change, `TASKS.md` edit, helper script, stub file, or `.orig`
file. The iOS worktree was read only. A55 #1 and #3's parser fixes are untouched.

## Confirmation against the dispatch code

All seven requested findings were real; none was dismissed as a false positive.

| A55 | Dispatch evidence | Result |
|---|---|---|
| #4 | All three Marked for Later row callbacks only added the work ID to `unmarkedIds`, despite the page's remote-removal promise. | Fenced work-page GET, one POST to `/works/<id>/mark_as_read` with `_method=patch`; remove only after AO3 evidence, otherwise show the failure and keep the row. |
| #2 | `lastSubmittedContentHash` belonged to one model, lacked account/context, and was assigned after the answer. `_submitting` was set inside the launched coroutine. | Synchronous admission and a shared account/work/parent/normalized-body store; lost answers require verification across reopening. |
| #8 | Drafts had no launch-specific unnamed-session identity or move operation; success cleared one chapter slot only. | Launch/session identities, collision-preserving handoff to the verified account, and successful work/parent variant cleanup scoped to that account. |
| #5 | `scheduleIsEditable` disabled editors, but `parameters()` still replayed the schedule controls without a timezone. | Omit timezone and every schedule date control when no timezone is supplied. |
| #6 | The codec retained unknown language JSON for export, but the live URL builder read only the known enum's `code`. | The live request uses the retained ID, and the UI shows that ID rather than Any. |
| #7 | `discardFilterEdits()` returned unless the state was `Results`; initial `Loading` retained unapplied edits. | Restore the requested snapshot for a non-idle search, preserving the typed query; idle Browse keeps its edits. |
| #10 | Resolver allowed only apex/www and silently upgraded cleartext AO3 input. | Accept HTTPS AO3 subdomains; reject HTTP AO3 even with `allowExternalHost`; retain intentional off-site HTTP links with that flag. |

Compared with the named assertions in the iOS worktree's
`AO3WriteDispatchFenceTests`, `CommentSubmissionTests`, `AO3ChallengeFormTests`,
`SearchFiltersTests`, `SearchPanelRulesTests`, and `AO3URLResolverTests`, and their
corresponding implementation. No changes to iOS.

## Production changes, file by file

Paths below `android/app/src/main/java/io/github/cidy02/kudos/`:

| File | Change |
|---|---|
| `account/AccountWorksListScreen.kt` | Every Unmark layout calls the screen's write state. The row remains until success; failure appears in a dialog. Session replacement resets local confirmed removals. |
| `account/SubscriptionUnsubscribeState.kt` | Reuse its existing single-flight, session-bound, cancellation-aware write handling for Unmark, passing the state's opening generation to the repository. |
| `network/ao3/writes/AO3WriteRepository.kt` | Add `unmarkForLater(workId, expectedGeneration)`. Check the tap's generation before GET, reuse fresh-token `indexWrite` and `postOnce`, and construct the POST path without the work GET's adult-consent query. No retry or subsequent list GET. |
| `network/ao3/comments/CommentSubmissionStore.kt` (new) | Full-body normalized keys preserve case and ignore chapter presentation scope. Shared in-memory sending/ambiguous/success records survive screen recreation, preserve original submission time and hidden-comment evidence, isolate different keys/accounts, and clear on logout. Unresolved retention is one hour; the duplicate window is five minutes from confirmed success. |
| `network/ao3/comments/CommentVerification.kt` (new) | Three-state evidence matcher: canonical account, exact top-level/direct-reply placement, normalized text, and no contradictory old timestamp. Missing parent, hidden/anonymous/transformed evidence and cutoffs remain unknown. Reuse the existing timestamp parser. |
| `network/ao3/comments/AO3CommentRepository.kt` | Capture the submitting form's hidden-comment notice before POST. Add fenced, authenticated verification without public fallback, cache, or POST: exact parent thread for replies; first and, if needed, last work-comments page for top-level posts. Authentication failure remains a typed failure. |
| `comments/CommentsViewModel.kt` | Admit synchronously before launch; replace the body hash with the shared key. Ambiguity verifies, never reposts automatically. Reopening an unresolved draft verifies; unknown keeps it blocked; clean absence permits a later explicit tap. Check Again retains the original body/context through composer edits. Preserve account/generation guards on continuations. Serialize draft saves before handoff/cleanup; successful posts clear only their account/work/parent chapter variants; edits clear no comment drafts. Delete shares admission so it cannot release another send's busy state. |
| `comments/CommentsScreen.kt` | Add Check Again to the existing message dialog when a submission remains unresolved. |
| `network/ao3/comments/CommentDraftStore.kt` | Add launch-specific unnamed-session identities, atomic identity moves that keep both different drafts on collision (moved text first), and account/work/parent-scoped variant cleanup. Existing draft key layout remains intact. |
| `auth/AO3AuthRepository.kt` | Move unnamed drafts when session verification supplies a name, including drafts left by closed screens; clear the signed-out account's shared submission records on session removal. |
| `app/KudosAppContainer.kt` | Give auth the existing draft store so verification can perform that handoff without an open Comments model. |
| `network/ao3/account/AO3ChallengeSettingsForm.kt` | Treat a blank timezone as unavailable and omit timezone/date controls from the save when unavailable; unrelated controls keep their existing replay behavior. |
| `network/ao3/search/AO3SearchFilters.kt` | Derive the live language ID/title from the existing preserved JSON for an unknown language. An explicit language selection removes the preserved old value. No new persisted field. |
| `network/ao3/search/AO3SearchUrlBuilder.kt` | Emit `work_search[language_id]` from that effective ID. |
| `search/SearchFilterSheet.kt` | Use the effective language title and explicit-selection operation. |
| `search/FilterLanguagePicker.kt` | Display the unknown ID; avoid marking Any as selected for a preserved unknown language. |
| `search/SearchFilterHelpers.kt` | Include an unknown language's raw ID in the active summary. |
| `search/SearchViewModel.kt` | Discard unapplied filter edits during the first requested load and error state as well as loaded results; leave idle edits alone. |
| `network/ao3/AO3URLResolver.kt` | Match AO3 subdomains by the dot boundary; reject cleartext AO3 resolution instead of upgrading it. Leave canonical work URL generation unchanged. |

`docs/AO3_NETWORKING_POLICY.md` now documents Android's Unmark request/evidence
path and comment admission, verification, and draft handoff behavior.

## Tests added or updated — assertions, not execution results

**No tests were run in this sandbox.** These describe what each new/changed test
asserts. Claude must compile and run them and the existing regression suites.
Paths below `android/app/src/test/java/io/github/cidy02/kudos/`:

### `network/ao3/writes/AO3UnmarkForLaterTest.kt` (new)

- `unmarkForLaterPatchesMarkAsReadOnce`: iOS's GET then one `mark_as_read` POST, exact patch/token fields, work-page referer, and confirmed message.
- `anUnmarkWithoutAO3sNoticeIsNotASuccessAndErrorsAndDropsAreNeverRetried`: maintenance HTML, AO3 refusal, lost answer, and 429 remain failures after one POST.
- `oldTapSendsNothingAndSessionChangeDuringCSRFReadPostsNothing`: a stale tap sends neither GET nor POST; a session change during GET permits no POST.

### `network/ao3/writes/AO3UnsubscribeDispatchTest.kt`

- New `unmarkSessionChangeInsideSharedPacingWaitPreventsPostDispatch`: terminal OkHttp interceptor and a controlled pacing delay prove Unmark reaches the shared last-moment session fence; sign-out during the wait leaves only the GET recorded. The interceptor never calls the network.

### `account/SubscriptionUnsubscribeStateTest.kt`

- New `unmarkKeepsTheRowUntilAO3ConfirmsAndPublishesFailureWithoutRemovingIt`: hold the POST, reject another tap, retain the row while pending and on unconfirmed failure, publish the failure, and remove only on a notice. One GET and one POST, no follow-up list read.

### `network/ao3/comments/CommentSubmissionTest.kt` (new)

- `keysNormalizeWhitespacePreserveCaseAndIgnoreChapterScope`: whitespace equivalence, case distinction, and reply dedup across work/chapter surfaces.
- `secondBeginWhileInFlightAndRecentSuccessAreRejected`: synchronous key admission and the five-minute success window, including a slow original answer.
- `ambiguousPopAndReopenUnknownRecheckAndChapterSwitchStayBlocked`: a recreated screen's lookup sees the unresolved key, and hidden evidence survives unknown rechecks.
- `verifiedAbsenceAndDefinitiveFailureReleaseOnlyTheirOwnKey`: clean absence releases that key only; found resolves the original body, independently of edited text.
- `distinctAccountsBodiesAndParentsDoNotEraseUnresolvedEntriesAndLogoutClearsOnlyItsAccount`: multiple independent unresolved keys and account isolation.
- `logoutInvalidatesTheLoggedOutAccountsUnresolvedState`: real auth-repository logout clears that account's process-shared record.
- `repeatedAmbiguityKeepsOriginalTimeAndExpiresAfterOneHour`: verification keeps the original attempt timestamp and respects retention.
- `verificationRequiresTheExactLevelAndCanonicalAccountAndBody`: direct reply versus top level, missing parent, other accounts, unknown canonical identity, and guest identity.
- `hiddenTransformedCutoffAndOldEvidenceStayUnknown`: conservative handling of moderation notices, HTML bodies, anonymous creators, cutoffs, and contradictory old dates.

### `network/ao3/comments/CommentVerificationReadsTest.kt` (new)

- `topLevelChecksOnlyFirstAndLastWorkPagesEvenFromAChapter`: exact work-page plan, with no intermediate-page crawl.
- `replyChecksItsExactParentAndNeverGuessesAWorkPage`: the parent thread's matching direct reply proves success with one GET.
- `failedMalformedAndStaleSessionReadsStayUnknownWithoutPublicFallback`: network/markup failures remain unknown; auth failure remains typed; session fences prevent stale evidence. Fake public and POST methods throw if reached.

### `network/ao3/comments/AO3CommentRepositoryTest.kt`

- New `hiddenCommentNoticeIsCapturedBeforeSendingEvenFromChapterScope`: capture the actual work form's notice before the only POST, including a chapter-scoped composer; unconfirmed response stays a failure.

### `comments/CommentsViewModelContextTest.kt`

- New `secondTapWhileInFlightDoesNothingAndSuccessClearsOnlyItsChapterVariants`: two taps before a scheduler turn and another while POST is held still make one POST. Success clears that account's work and chapter variants, preserving another account and another parent.
- New `lostAnswerSurvivesReopeningAndUnknownCheckNeverPostsAgain`: lost answer, close/recreate/reopen, unknown recheck, and composer edit retain the original unresolved key; clean absence releases it without POST; a subsequent explicit tap alone sends again.
- New `definitiveRefusalsAndOfflineFailuresKeepTheDraftAndPermitOnlyAnExplicitRetry`: offline-before-send, rate limit, and rejection preserve the draft, do not trigger ambiguity reads, and require another tap for a second attempt.
- New `anUnnamedSessionsDraftsMoveToItsVerifiedNameWithoutReplacingExistingDrafts`: stable launch/session identity, different session identity, a queued save before verification, collision merge, other-account isolation, and no adoption of an earlier launch's legacy unnamed drafts.
- New `verifyingAnUnnamedSessionMovesDraftsEvenWhenTheCommentsScreenHasClosed`: auth verification itself moves the draft without a Comments screen.
- The model helper now injects one submission store per test, shared between that test's recreated models. Existing account/context/edit tests remain in place.

### `account/AO3ChallengeSettingsEditTest.kt`

- New `missingTimeZoneMakesScheduleReadOnlyAndOmitsItFromSave`: port iOS's literal missing-timezone form; editor is read only, save has no timezone/date fields, unrelated text survives.
- Updated `absentDisabledUnreadableZoneAndUnreadableDateCannotBeChangedAndPastRevealsFollowSwiftCode`: replace its former expectation that a blank-timezone save replays dates with the omission assertion. Other cases remain.

### `search/SearchFiltersCodecTest.kt`

- New `languageDecodesEveryShapeAndUnknownIdStillReachesAO3`: legacy string, intermediate `{id,title}`, and current `{id}` shapes all retain a future ID in the actual query, UI title/summary, and export after an unrelated edit. Known French still decodes; explicitly selecting Any removes the old ID.

### `search/SearchPanelRulesTest.kt` (new)

- `aClosedPanelPutsBackTheRequestedSearchAndNothingInBrowse`: a held initial request and its error restore the requested filters while retaining typed query text; after Back, idle Browse retains the live edits.

### `network/ao3/AO3URLResolverTest.kt`

- Replace the old upgrade assertion with `cleartextHTTPAbsoluteAO3URLIsRejected`: apex and download HTTP URLs fail, including with external-host permission.
- New `subdomainHostIsAllowedByDefaultAndLookalikesAreRejected`: HTTPS download subdomain, protocol-relative AO3 URL/query/fragment preservation, deceptive suffix rejection, and deliberately allowed external HTTP.
- Existing relative-link, external-link, unsupported-scheme, and host tests remain.

## URL trust caller inventory

At dispatch and after these changes, **no production caller uses
`AO3URLResolver.resolve` or `isTrustedAo3Host`**. Only their direct resolver tests
exercise the changed decisions. `isTrustedAo3Host` remains a host-only check.

Every production consumer of `AO3URLResolver` uses its unchanged
`canonicalWorkUrl`: `network/ao3/chapters/AO3ChapterIndexRepository.kt`,
`app/DemoLibrary.kt`, `works/CanonicalWorkMerge.kt`, `works/DownloadQueue.kt`,
`works/WorkDetailScreen.kt`, `works/WorkTags.kt`, `works/WorkIdentityIndex.kt`, and
`library/KeepOffline.kt`. Their generated URLs and behavior are unchanged.

Existing in-app/browser routing still uses `AO3BrowseUrls` / `AO3WebUrlPolicy`;
existing write URL construction still uses `AO3WriteUrls`. None was migrated to
the resolver. Thus the new HTTP refusal cannot break a currently routed in-app
link. This is a static caller/control-flow check, not rendered navigation QA.

## Verification and remaining checks

- `git diff --check` passes. Branch and HEAD remain the assigned lane and dispatch SHA.
- Reviewed the request paths, session fences, evidence-before-removal branches, callback callers, and changed expectations against iOS. Reviewed the diff for scope and sensitive/generated files.
- No Gradle build, JVM/Robolectric test execution, lint suite, emulator/device run, screenshot review, independent adversarial review, or live AO3 verification was performed. Compilation and test results remain for Claude; do not treat the test descriptions above as passes.
- All added request tests use terminal fakes/interceptors. No sign-in or AO3 access was needed or attempted.
- The shared unresolved store intentionally has process lifetime, as on iOS; it does not survive an app restart. An unnamed draft from a launch that never learns its account stays on disk without being assigned to a later launch's account, also matching iOS's privacy choice.
- Manual UI checks still needed in an authorized local fixture/demo setup: Unmark busy/failure/confirmed states across layouts, unresolved-comment Check Again, and unknown-language label/selection. No claim of visual correctness.

## Deferred A55 items

#9's WebView frame/demo behavior is untouched. The lower-priority badge,
long-press, tapped-tag passthrough, and filtered-tag adult-consent items are also
untouched. The badge is a plausible cheap follow-up confined to summary/count
logic, but changing its counting contract is outside this brief; it should get
the iOS badge assertion when taken up. Challenge checkbox duplicate pairs remain
unchanged: their effective checked/disabled behavior was not a demonstrated bug.

Next step: Claude builds and runs the Android regression suites, reviews the
changes (including the UI states), and commits on this lane under the owner's
workflow. No port to the read-only iOS tree is needed.
