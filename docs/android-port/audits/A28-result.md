| Id | Severity | File and line | Finding |
|---|---|---|---|
| A28-1 | P1 | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsViewModel.kt:219` | A late top-level draft restore can populate a reply and subsequently be saved or posted as that reply. |
| A28-2 | P2 | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsViewModel.kt:189` | Chapter Comments detaches the original thread job from cancellation; it can overwrite a later scope/page load. |
| A28-3 | P2 | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsViewModel.kt:192` | Chapter Comments discards a failed required thread read, and retry loses the original Inbox intent. |
| A28-4 | P2 | `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/chapters/AO3ChapterIndexRepository.kt:27` | Chapter Comments requires an anonymous chapter-index read even for a signed-in restricted work; index failure silently leaves the isolated thread under All comments. |
| A28-5 | P3 | `android/app/src/test/java/io/github/cidy02/kudos/writing/WritingChapterFormScreenTest.kt:135` | Several tests leave named rules unexercised; two assertions are true independently of the behavior they purport to check. |

Static audit at `5c01ce2b8b95fbe830fec7ca60aa75ca3352d1bf`, branch `android/agent-gemini-a28`. No build, test execution, emulator, AO3 request, authentication, branch switch, commit, or push. The brief already had an uncommitted modification when this audit began; it was not changed. Only this result file was created.

Path convention below: `K/` means `android/app/src/main/java/io/github/cidy02/kudos/`; `T/` means `android/app/src/test/java/io/github/cidy02/kudos/`; `S/` means `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`. All line references are to the checked-out files, unless explicitly identified as a historical commit. A24/A26 findings and their triage were read first. The findings below do not re-file their already documented cases.

## A28-1 — A page load restores the new-comment draft into a reply

Exact code, `K/comments/CommentsViewModel.kt:210–220`:

```kotlin
_state.value = CommentsUiState.Loaded(thread)
val draftContent = draftStore?.getDraft(
    workId = target.workId,
    chapterId = (target as? AO3CommentTarget.Chapter)?.chapterId,
    parentId = null,
    username = currentUsername()
)
if (draftContent != null && _draft.value.isEmpty() && _editTarget.value == null) {
    _draft.value = draftContent
}
```

`K/network/ao3/comments/CommentDraftStore.kt:24–26` suspends in `dataStore.data.map { it[key] }.first()`. The page is already Loaded before that suspension. `startReply`, `K/comments/CommentsViewModel.kt:371–385`, sets the reply target, clears the field, presents the composer, and asynchronously asks for that reply's draft. A nonexistent reply draft leaves the field empty. The page-load guard checks edit state but not reply state, composer context, or the target that is current when the answer arrives.

iOS: `S/Features/Comments/CommentsModel.swift:970–988` resolves the displayed parent, constructs the exact work/chapter/parent context, and synchronously assigns `composerText = drafts.draft(for: context, identity: authContext.identity)` when opening that composer. Fetching a page does not asynchronously populate an unrelated composer.

Concrete failing inputs: store top-level draft `T` for work W; store no reply draft for comment C. Hold the initial page load's draft-store emission after line 210. Tap Reply on C; its composer is empty. Release the top-level draft lookup. Android puts `T` in the Reply-to-C field. Typing or closing now saves it under C's parent key (`saveDraft`, lines 349–358); Submit uses `_replyTarget` and sends it as a reply to C (`submitComment`, lines 439–460). The top-level text must stay in its original slot and must not become a reply.

Smallest fix: remove page-load restoration from `present`; restore drafts only when opening the corresponding composer, with a captured identity/context and a continuation check that the same composer is still current. If retaining page-load restoration, at minimum require no reply, no edit, no open composer, and the same target/identity/request at assignment. Merely adding an edit guard, as the current comment describes, does not fix this race.

This confirms the A24/A26 unconfirmed draft lead; it is not an already filed finding. Claude's A26 `present` refactor retains this wrong guard, and the new thread-joining path can wait on this very draft lookup.

## A28-2 — Superseding Chapter Comments does not cancel its original thread

Exact code, `K/comments/CommentsViewModel.kt:189–193`:

```kotlin
val threadRead = loadJob
loadJob = viewModelScope.launch {
    threadRead?.join()
    val thread = (_state.value as? CommentsUiState.Loaded)?.thread?.comments
        ?.firstOrNull { findCommentRecursive(listOf(it), commentId) != null }
```

The original job was separately launched into `viewModelScope` at lines 154–158. Joining that sibling does not make it a child of the replacement job. `load` cancels only the newly assigned `loadJob` at line 153. The original job's `ensureActive()` at line 157 still succeeds and calls `present` without checking whether it remains the selected request.

iOS: `S/Features/Comments/CommentsView.swift:220–254` cancels the context load when scope/chapter changes; `S/Features/Comments/CommentsModel.swift:395–451` performs the focused-thread/chapter-page sequence inside the same initial operation, rather than turning the first fetch into an untracked sibling.

Concrete taps and order: open Inbox → Chapter Comments; hold the standalone thread response; allow the index to resolve. `openOnChapter` sets By Chapter and `showChapterIncluding` starts the joiner. Tap the chapter pill, then All comments (`K/comments/CommentsScreen.kt:294–296,473–483`); let the new work-page load complete. Release the original standalone thread. The canceled joiner does not resume, but the uncanceled original thread job publishes the isolated Inbox thread over the work page. The label remains All comments. Expected: the superseded initial fetch cannot replace the reader's chosen page.

Smallest fix: retain ownership of both jobs and cancel both on supersession, plus guard publication with a request epoch/current target. Prefer a single initial operation that fetches its thread result directly and then fetches the chapter page. Do not communicate the required result through mutable screen state.

Claude's landing is wrong here: it fixes the successful, untouched opening but breaks the existing “one load at a time” invariant its own `load` comment names. The direct `showChapterIncluding` test does not exercise supersession.

## A28-3 — Required thread failure becomes successful unrelated content; retry drops the intent

Exact code, `K/comments/CommentsViewModel.kt:191–201`:

```kotlin
threadRead?.join()
val thread = (_state.value as? CommentsUiState.Loaded)?.thread?.comments
    ?.firstOrNull { findCommentRecursive(listOf(it), commentId) != null }
_focusedCommentId.value = null
_state.value = CommentsUiState.Loading
val result = repository.loadThread(target, 1, null)
ensureActive()
present(target, result, first = thread?.takeIf {
    result is AO3Result.Success && findCommentRecursive(result.value.comments, commentId) == null
})
```

A failed standalone thread produces Error/AuthRequired in `present` at lines 224–229. The joiner reads that as `thread == null`, clears the requested focus, and replaces the failure with the chapter fetch. Separately, the error button is `onAction = { viewModel.load() }`, `K/comments/CommentsScreen.kt:548`; it does not restore the original comment/chapter intent.

iOS: `S/Features/Comments/CommentsModel.swift:407–424` requires a successful requested thread and a resolvable root before reading the chapter. Lines 485–488 surface the failure. `retryInitialLoad`, lines 492–500, retries the original pending Inbox comment rather than turning it into an ordinary page fetch.

Concrete input: the requested standalone thread fails after the repository's applicable fallback also fails; `/navigate` succeeds; chapter page one succeeds but the requested comment is on page two. Android displays chapter page one as Loaded with no requested thread and no retained failure/retry intent. Expected: failure to fulfill the Inbox request, with a retry of that request. Another concrete input: thread succeeds but the chapter-page read fails; Try Again subsequently reads only the chapter page and cannot reinsert the off-page Inbox thread.

Smallest fix: carry the standalone `AO3Result` in the initial operation, stop on failure/missing requested comment, and retain initial intent until the whole operation succeeds. Route Try Again through that operation while initial intent is pending.

Claude's A26 landing is wrong on these failure paths. This differs from A26-4's original omission of the comment id: the id is now passed, but required failure evidence is discarded.

## A28-4 — Restricted-work chapter routing depends on an anonymous index

Exact code:

- `K/app/KudosAppContainer.kt:109–110`: `val ao3Client: OkHttpAO3Client by lazy { OkHttpAO3Client() }`.
- `K/app/KudosAppContainer.kt:280–282`: the shared `AO3ChapterIndexRepository(ao3Client)` receives that client.
- `K/network/ao3/chapters/AO3ChapterIndexRepository.kt:26–27`: `return when (val response = client.get(url))`; no authenticated headers are supplied.
- Lines 44–46: `val chapters = (chapters(workId) as? AO3Result.Success)?.value ?: return null` and `return chapters.firstOrNull { it.position == position }`.
- `K/comments/CommentsScreen.kt:144`: `chapterIndexRepository?.chapterForPosition(workId, position)?.let { viewModel.openOnChapter(it, focusedCommentId) }`.

iOS: `S/Features/Comments/CommentsModel.swift:429–435,553–563` obtains the chapter directly from the returned standalone thread when possible. If an index is needed, lines 901–909 construct the authenticated request and fence/cache it by the opening authentication context. `docs/AO3_NETWORKING_POLICY.md:28` also explicitly requires comments/index continuations and caches to be scoped to authentication and session generation.

Concrete input: a signed-in reader receives an Inbox comment on chapter 3 of a registered-users-only multichapter work. The authenticated standalone comments read succeeds. Android's anonymous `/works/W/navigate` cannot access that work: an error becomes null, or a login page parses as an empty index and likewise becomes null. The effect does nothing. The isolated thread is left on All comments, rather than entering chapter 3 and reading its first page. Expected: resolve the chapter for the authorized viewer (or from the thread), then open that chapter, with an explicit failure if required resolution fails.

Smallest fix: use a generation-bound authenticated index reader for this signed-in destination and surface required resolution failure. Deriving the chapter id from the already returned thread can also remove the mandatory dependency, matching iOS. The recorded decision allowing three reads does not authorize an anonymous read that the viewer cannot use.

The repository additionally caches by work id for the process lifetime (`lines 21,24,33`), contrary to the per-model, auth/generation-scoped comments-index policy. This cache currently contains anonymously visible data; I am not claiming it exposes authenticated private titles. It can nevertheless retain an old position→id mapping after chapters are reordered and reused by a new opening. Address the cache ownership with the authenticated-reader fix; simply attaching cookies to this shared cache would introduce a private-data leak.

Claude's landing did not create the public index repository, but its new opening still relies on it unconditionally. The A26 fix therefore does not close restricted-work/index-failure paths.

## A28-5 — Tests with tautological assertions or unexercised named claims

These are partial test defects, not a claim that the entire listed test suites prove nothing. Other assertions in the same tests often remain useful.

### `AO3ChapterFormTest.untouchedModeledFieldsMatchBrowserExceptSubmitLabelAndReplayIsExact`

`T/network/ao3/writing/AO3ChapterFormTest.kt:36,40`:

```kotlin
val modeled = encoded.filter { it.first in names }
assertTrue(encoded.filterNot { it.first in names }.none { it.first in modeled.map { pair -> pair.first } })
```

Every name in `modeled` is in `names`; every name in the outer filtered collection is outside `names`. The predicate is true for every possible `encoded`, including one with duplicate modeled controls. It cannot independently prove that fields are emitted once. The independent browser equalities at lines 37–39 are meaningful and should stay.

Reference: `S/Services/AO3WorkActions.swift:550–560` transmits the constructed parameter sequence verbatim, and Android's actual single-emission rule is `K/network/ao3/writing/AO3ChapterForm.kt:117–120`. Smallest fix: remove the tautology, or replace it with independent expected multiplicities for modeled token/method/submit fields and explicit duplicate-control fixtures. Do not assert uniqueness for intentionally repeated array controls.

### `WritingChapterFormScreenTest.directPostSwitchSendsOnlyOnePostAndPostedChapterOffersOnlyUpdate`

`T/writing/WritingChapterFormScreenTest.kt:135–140`: `show()` followed by toggling Post without preview, tapping Post chapter now, and checking the single submit field. `show(kind: String = "new")` is at line 43. The test never opens a posted chapter.

Reference: `S/Features/Writing/AddChapterView.swift:307–308,314,326–346` updates a posted chapter and omits Save as draft. Concrete counterexample: change Android's posted-chapter screen to offer Post and Save as draft; this test still passes. Smallest fix: add a posted fixture case checking the Update label, absence of Post/Save-as-draft controls, and its `update_button` payload. The current test does verify the direct-post switch for a new chapter.

### `WritingChapterFormScreenTest.sectionsPositionAndDateEditCollectedStateAndNoCreatorRowIsInvented`

`T/writing/WritingChapterFormScreenTest.kt:77–86` edits title, position and total, then toggles last chapter. It never enables custom publication date, chooses a date, or checks year/month/day.

Reference: `S/Features/Writing/AddChapterView.swift:244–275` wires the date binding to all three form fields and clears them on disabling custom date. Concrete counterexample: disconnect Android's date picker from the model; the named test still passes. Smallest fix: actually set and clear a date and assert the collected fields. Other form-state tests of date setters do not exercise this screen wiring.

### `WritingChapterDeleteTest.secondTapWhileConfirmReadOrPostIsHeldSendsNothingAndChangedSessionCannotDelete`

`T/writing/WritingChapterDeleteTest.kt:62–67`:

```kotlin
setup.client.beforeResponse = { release.await() }
val deletion = async { model.deleteChapter(confirmed = true) }; runCurrent()
model.deleteChapter(confirmed = true)
assertEquals(2, setup.client.gets.size); assertEquals(0, setup.client.posts)
setup.auth.logout(); release.complete(Unit); deletion.await()
```

Only the confirmation GET is held; the session changes before any POST. No held-POST double tap is exercised. Reference: `S/Features/Writing/AddChapterView.swift:324,345` disables actions while saving/posting, and `S/Services/AO3WorkActions.swift:580–593` sends deletion once. Concrete counterexample: release Android's deletion busy guard immediately after the confirmation GET, permitting two deletion POSTs while the first POST is held; this test still passes. Smallest fix: a second case holding `beforePostResponse`, tapping Delete again, and asserting exactly one recorded POST before and after release.

### `WritingChapterFormScreenTest.allThemesAtAccessibilitySizeKeepLabelsAndFailureWordsUnclipped`

`T/writing/WritingChapterFormScreenTest.kt:325–337` obtains text layouts only for ordinary labels in the four-theme loop. Lines 340–343 then create an unconfirmed failure and only wait for its text to exist; they do not measure its layout, and only the final OLED theme is active.

Reference: `S/Services/AO3WorkActions.swift:571–575` produces the unconfirmed failure, and `S/Features/Writing/AddChapterView.swift:398–400` retains the failure wording for presentation. Concrete counterexample: ellipsize or height-clip the failure paragraph in every theme; the current existence check still passes. Smallest fix: produce the failure inside each theme iteration and apply the same nonempty-layout, overflow and ellipsis assertions to that paragraph. This is a coverage defect, not evidence that the current UI clips it.

### `DemoAuthorWorksSortTest.scopesPseudsLaterPagesAndOtherRoutesRemainLocalAndMissingAssetIsTerminal`

`T/network/ao3/DemoAuthorWorksSortTest.kt:58`:

```kotlin
assertEquals(2, AO3AuthorParser().parseWorksPage(html, 2).currentPage)
```

`K/network/ao3/author/AO3AuthorParser.kt:152` delegates to the search parser; `K/network/ao3/search/AO3SearchParser.kt:28,37` copies the supplied `page` into `currentPage`. This assertion does not establish that the demo selected page two. The expected sorted ids at lines 59–60 also do not identify a page-two fixture independently.

Reference: `S/Services/AO3Client+Authors.swift:5–8` likewise passes its caller's page to parsing; it is not evidence of network route selection. Concrete counterexample: make the demo ignore the page argument and serve its page-one body with the same sorted ids; the asserted `currentPage` is still 2. Smallest fix: distinguish the page fixtures with an independent marker or page-specific ids and assert the returned body's page-two evidence. Keep the useful sort, route isolation and missing-asset assertions.

### Coverage boundary

`WritingSeriesTest.cancelledBestEffortManageAttemptIsRememberedOnExplicitRetry` (`T/writing/WritingSeriesTest.kt:269–279`) meaningfully checks that the required form survives optional-read cancellation and no retry GET occurs. It does not exercise `manageAttempted`: the second `load` exits at `K/writing/WritingSeriesState.kt:37` because the form already exists. Removing the attempt flag alone would still pass. I do not count that as a separate broken observable rule: the retained-form guard also enforces no reread in this case.

Rules not pinned by the requested tests: instant cancellation of the caller job immediately after a returned POST, while the state object remains active, for series verdict/read-back and collection save/delete; and the automatic series-result scroll. `WritingSeriesScreenTest` scrolls to find the result itself, which cannot prove the production effect brought it into view. The held-POST and date-screen omissions above are also unpinned by their named tests. This is source review, not mutation-test execution.

## Item 0 — Work actions and the hand merge of `5c01ce2b`

I reviewed the main-source diff and the current callers against WorkEditView, WritingPreviewView, AO3WorkActions and AO3WritingModels. I found no additional confirmed defect in the Post/Preview/Delete merge itself. That conclusion includes Claude's landing changes; it is not an endorsement of the faulty Comments landing described above.

**New Preview → Save → later Post:** one draft, not two, provided AO3's preview names its created work. `K/network/ao3/writing/AO3WorkActions.kt:13–19` adopts the returned work id, `/works/id` action, patch method and draft kind, matching `S/Models/AO3WritingModels.swift:1034–1045`. Preview already creates that draft; Save updates it and closes the form. Reopening that draft and Post updates the same id. Preview → Post directly also updates it. Existing-work preview only refreshes the token. A new-work preview that lacks an id cannot be adopted; `require` at line 17 preserves the old form and yields UNCONFIRMED rather than authorizing an identity-free save.

**Missing fields:** `K/writing/WritingWorkFormScreen.kt:191–197` gives the missing-fields confirmation; `K/network/ao3/writes/AO3WriteRepository.kt:179–185` independently refuses to send when the list is nonempty. This matches `S/Features/Writing/WorkEditView.swift:213–221` and `S/Services/AO3WorkActions.swift:128–140`. Direct Post is one POST with `post_button`; it does not save a new draft first. Preview's confirmation can still reach the repository, but the repository guard prevents a missing-fields POST.

**Delete:** preparing confirmation reads confirm_delete once; Cancel sends nothing. Confirm rereads that confirmation for a fresh token, then sends only token and delete method (`K/network/ao3/writes/AO3WriteRepository.kt:196–225`). Refusal retains the typed form and clears implications; a 2xx without a notice remains UNCONFIRMED, not “nothing deleted.” Success closes the form. Neither deletion nor its verdict deletes local Library/import data. iOS's two unused work-statistics GETs are intentionally omitted by the 3bx landing decision, so that difference is not a finding.

**Follow-up reads:** work Save/Post/confirmed Delete set `saved`; the navigation callback pops the form and bumps Drafts' revision only when that is the preceding destination (`K/app/AppNavHost.kt:641–660`). `WritingDraftsScreen`'s loader is keyed by that revision and current authentication, so it reloads the current drafts page. There is no success-verification poll. Preview, canceled confirmation, failed/unconfirmed action and Preview Edit do not request a list refresh. After chapter mutation, the owning work's publication refresh is guarded by its original session; it does not refresh an old form with a replacement account's HTML.

**Second taps:** work `perform` sets saving before its first suspension and checks `saving` and `saved` (`K/writing/WritingWorkFormState.kt:106–111`). Chapter state similarly checks busy/finished/chapterSaved; preview controls share the action's busy state. A successful work action cannot be dispatched again from that state. Retrying an explicitly unconfirmed write remains an explicit user action, not an automatic retry.

**Preview return matrix**, `K/network/ao3/writes/AO3WriteRepository.kt:254–277`:

| Returned answer | Opening generation unchanged | Generation moved on |
|---|---|---|
| Typed AuthenticationRequired | AuthenticationRequired | AuthenticationRequired |
| Other typed failure | Original failure | UNCONFIRMED |
| Scoped AO3 validation error in HTML | That validation refusal | That same refusal |
| Parsed preview with a work id | Preview success | Preview success, retained/adopted |
| Parsed preview without a work id | Parser success; new-work adoption rejects it | UNCONFIRMED |
| Login HTML in 200…399 that reaches the parser | AuthenticationRequired | AuthenticationRequired |
| Non-preview HTML / parse failure / status outside 200…399 | Preview unavailable | UNCONFIRMED |

Error detection precedes status/preview parsing. `refused` and `adoptable` deliberately bypass the post-return generation replacement; they do not bypass the original generation fence on the next action. The NonCancellable wrapper includes preview parsing, not merely transport. `movedOnAfterWrite(generation, answer)` retains the login-page verdict because the response itself can expire the session. Those Claude landing changes are correct under the recorded continuation decision. Work/chapter state no longer immediately checks caller cancellation after receiving these verdicts; its `active` test prevents publishing to retired state.

The merge preserves shared chapter preview behavior, original-session send guards, parent-owned chapter operations, total-only retry and publication-refresh behavior. It changes more than work controls: chapter preview presentation is shared, and chapter post-return handling/busy cleanup is altered. I checked those current paths as part of the merge rather than assuming the earlier implementation was correct.

## Item 1 — Remaining A26 fix verdicts

**Writing continuation:** `postWriting` fences before dispatch and passes the answer to `movedOnAfterWrite`; `judgedByCaller` permits preview HTML to reach the matrix above. Work/chapter states display returned evidence while active, but later actions still check the captured generation. Adopting a returned preview after session expiry does not permit the old form to send on the new session. A chapter save followed by a total update rechecks the original generation before that preparation read/write; a confirmed chapter can therefore remain recorded with a partial-total failure. Chapter saved revisions are notifications, not authorization to write again. This closes the A26 post-return-generation cases on the traced normal/session-change paths.

**Series read-back:** `K/network/ao3/writes/AO3WriteRepository.kt:119–132` converts a thrown session-fence cancellation to null only when the caller job is still active. A truly canceled job fails `ensureActive` in the catch and still propagates cancellation. The final generation check converts a read performed across a session change into UNCONFIRMED; state also requires `current()` before applying success. Thus it does not install another account's rows. The follow-up GET is not explicitly fenced against the original generation before it starts: there is a check immediately before it and a final check after it, while `getAuthenticated` snapshots its own generation. A transition during scheduling/header acquisition remains a read-dispatch window, not permission to apply the result. See Unconfirmed for that window and caller cancellation.

**Series state:** returned unconfirmed failures no longer get “nothing saved/removed” prefixes. Success is applied only to the original current session. `close()` marks inactive and cancels load/write jobs (`K/writing/WritingSeriesState.kt:33–34`). The post-verdict `ensureActive` at line 115 and cancellation wording still need the separate instant-cancellation test below; session-change cancellation with an active caller is covered by the A26 fix test.

**Collection:** `sentUnderAnEarlierSession` clears saving and shows UNCONFIRMED when a returned answer belongs to a now-ended session. Typed values remain retained. Same-account reauthentication before a new explicit Save is intentionally supported by `saveGeneration` and fresh preparation; another username is refused. This closes the filed A26 stuck-busy case. It does not establish that every CancellationException means no write occurred: `confirmSave` still checks caller cancellation after the repository result, and save parsing is cancellable. See Unconfirmed.

**Comments opening:** on an uncached normal root-comment opening there are three logical reads: standalone thread, `/navigate` index, chapter first page. The first two begin independently; `showChapterIncluding` waits for the thread job before the third. A cached index makes it two actual GETs. Chapter refresh/page selection subsequently reads the selected chapter without reasking for the Inbox thread. A26's recorded three-read decision permits this difference from iOS's usual two reads, which derive the chapter directly from the standalone comment. A reply notification uses the served reply subtree; iOS additionally fetches the resolved root. That difference was already triaged and is not re-filed. Failure/supersession/index paths are A28-2 through A28-4.

**Leave/return and model identity:** `CommentsScreen`'s work-id key is scoped to the NavBackStackEntry's ViewModelStore, not the whole application. `K/app/AppNavHost.kt:1224–1234` uses ordinary `composable` and does not override that store owner. A second comments destination for the same work, including one above an existing comments destination, receives a different model. Returning to the retained older entry resumes its own model. The one-time `openedOnChapter` guard prevents its original effect from undoing a scope choice on ordinary reentry. Dismissed: the work-id key alone does not cause a newly navigated ordinary comments page to reuse an Inbox-thread model. This does not cure the in-entry orphan-job race.

**Token/method body:** `K/network/ao3/writing/AO3ChapterForm.kt:90–120` emits the modeled token once, emits method only if nonempty, and excludes every replayed served control whose name is modeled. `AO3ChapterFormParser.kt:37` gets `_method` from the served form, not an invented default. Consequently the A26 change does not duplicate either token or modeled method and does not add a method to an ordinary new POST with no override. Adoption deliberately changes a new draft into patch on its returned existing id, matching iOS. Array-valued creator fields retain their repeated values.

**Series result scroll:** the effect at `K/writing/WritingSeriesScreen.kt:82–84` requests `animateScrollToItem(layoutInfo.totalItemsCount)`. That is one past the last measured index, and can use the layout preceding insertion of the result. I did not establish a crash or failed visible scroll from reading the application alone; see Unconfirmed. The new tests locate the message by scrolling themselves, so they do not verify this fix.

## Item 2 — Test review boundary

Read the bodies of all requested classes: AO3ChapterFormTest, WritingChapterReadTest, WritingChapterFormStateTest, WritingChapterSaveTest, WritingChapterDeleteTest, WritingChapterRefreshTest, WritingChapterFormScreenTest, AO3ChapterDispatchTest, DemoWritingChaptersTest, AccountShortcutsScreenTest, AuthorWorksSortTest, AuthorProfileSortScreenTest, DemoAuthorWorksSortTest, WritingSeriesTest and WritingSeriesScreenTest. Read AO3CollectionFormTest's requested session cases and surrounding relevant cases, and CommentsViewModelDraftTest's Chapter Comments case and relevant draft tests. Also inspected the work-action tests/helpers relevant to the merge.

The chapter parser/browser parity, literal modeled fields, dispatch transport, total-only retry, chapter/publication refresh, generation-loss outcomes, local demo isolation, author sorting/query encoding, shortcut state observation and series-order payload tests have meaningful assertions. Transport tests deriving bytes with the production encoder prove transport preserves those bytes; independent literal/browser encoder tests supply the encoder evidence. They do not by themselves prove parity with Swift. `CommentsViewModelDraftTest.chapterCommentsFromTheInboxPutTheInboxThreadFirstAndReadItOnce` checks a direct model sequence and insertion; it does not compose the index effect, exercise failures, change scope while requests are held, or test late draft restoration. Its successful-case assertions are useful but insufficient for the landing.

No passing-test or visual-correctness claim is made here. The brief prohibited executing them.

## Unconfirmed

**Instant caller cancellation after a sent POST.** This is distinct from the fixed “session generation moved while caller stays active” cases. Source establishes remaining cancellation points:

- Collection save: POST is NonCancellable (`K/network/ao3/writes/AO3WriteRepository.kt:587–589`), but parsing enters cancellable `withContext(Dispatchers.Default)` at line 593. A canceled caller can fail to receive the actual notice; `K/account/AO3CollectionFormState.kt:137–138` calls it “Not saved … session changed” if state is still active. Delete has a synchronous repository verdict but the state checks cancellation at lines 148–156.
- Series metadata save: the repository can return a verdict synchronously after its POST, then `K/writing/WritingSeriesState.kt:115–118` can overwrite the result with session-changed wording on caller cancellation. Reorder/removal have a cancellable verification GET; their catch rethrows a genuinely canceled caller, and active state's catch can say the order was not saved/nothing removed.
- Work Save/Post/Delete and work/chapter Preview no longer have that immediate post-return fence; the latter also parses under NonCancellable. A chapter with a pending total update still has a subsequent cancellable preparation/update operation and correctly needs a partial-result distinction.

I did not find a production navigation path that cancels these callers while leaving those state objects active long enough to display the wrong sentence. Full screen disposal closes the collection/series models; inactive state then suppresses display. Therefore the bad active-caller verdict is a concrete library/state edge requiring a controlled coroutine test, not asserted here as a reproduced user-facing finding. Confirm by canceling the *caller Job* from a held POST completion while keeping the model active and the generation unchanged, then assert the sent-write verdict and busy state. Logging out in `beforePostResponse` is not that test.

Chapter Back was traced: `K/writing/WritingWorkFormScreen.kt:87,138–141,164–168` creates and passes the work screen's scope to the chapter/list. `K/writing/WritingChapterFormScreen.kt:34–45` runs writes on that owner scope and retires an unmounted busy chapter only after completion. Back from the child does not cancel the write; whole owning-work removal cancels the owner. A confirmed mutation can still notify the mounted owning work and refresh publication after child Back. This dismisses the proposed child-scope cancellation bug for the real nested route; it does not prove every standalone caller survives disposal.

**Read-back viewer window.** Series has no original-generation argument on its verification GET. A transition after the post-generation check but before authenticated headers are acquired could make the read belong to a replacement viewer; the final generation check suppresses its result. Confirm the network case with a header-acquisition/dispatch barrier and two sessions. The current tests change generation during the GET instead. No AO3 traffic was used to investigate.

**Delayed index intent and account context.** The chapter-index effect is keyed to initial position/work, not the reader's current selection, and the comments model has no captured opening auth generation. A late index or draft continuation needs a current-intent/account fence. A28-1/A28-2 give concrete confirmed races; I did not establish a separate reachable account-switch UI sequence or an independently reproducible pre-index scope-choice sequence, so I do not multiply them into findings. An integration test holding index parsing across a new scope choice/account transition would settle these paths.

**Series scroll.** Need a Compose test that starts at the top of a long form, triggers the verdict, and asserts its visibility without `performScrollToNode`. Also inspect the resolved Compose implementation for out-of-range `animateScrollToItem` behavior. A numeric one-past-last argument alone is insufficient evidence of a crash; clamping may make the current call work.

**Broad error selector.** The lead's class name is inaccurate: these functions are in `AO3WriteFormParser`, not AO3WorkFormParser. `workWriteError`, `K/network/ao3/writes/AO3WriteFormParser.kt:9–20`, already scopes to `#main`, skips preview/workskin/userstuff, and matches `S/Services/AO3Client+Works.swift:658–669`. Dismissed for the work-action path. The shared `writeErrorMessage` at lines 159–164 is broader and is used by series and other writes; however, I found no supplied real AO3 success/refusal page proving an outside-main match changes their verdict. A fabricated `.flash.error` outside main is not the requested real-page evidence. A saved actual response with that structure, checked against the Swift caller's selector, would confirm it. No AO3 contact was made.

## What I did not read

I did not audit the whole Android/iOS repositories, every historical audit, all collection tests, all account/reader/import/persistence paths, or all third-party coroutine/Compose implementations. I read the task-relevant source and reference excerpts rather than every line of the large navigation/container/model files. Long general documentation outputs were partly truncated; the relevant policy, decisions, prior audit/triage and brief/result portions were inspected separately. I did not inspect live AO3 HTML, run code or tests, verify emulator layout, or independently validate the landing's reported test count. Those limits particularly apply to the explicitly Unconfirmed items above.

---

## Triage (Claude, 2026-10-09)

Written by Codex's second slot (Grok ran out of balance twelve minutes into this audit). Five
findings; the four in the comments screen are fixed, three of them faults in Claude's own
Chapter Comments of the same morning. Gate after the fixes: 2,393 tests.

- **A28-1 real, fixed.** A page load restores the work's draft only into a field nobody has
  opened (no reply, no edit, no composer on screen, the same target still current). Each
  composer already reads its own draft when it opens. Test
  `aPageLoadNeverPutsTheWorksDraftIntoAnOpenReply`.
- **A28-2 and A28-3 real, fixed.** The Inbox's Chapter Comments is now one operation owned by
  the view model's one load: the thread, then the chapter's first page. Anything the reader
  chooses meanwhile cancels all of it; a thread that cannot be read is shown as a failure and
  the chapter's page is not read; Try Again repeats the request that failed (for every failed
  load, not only this one: it used to read the work's first page). Tests
  `aPageChosenWhileChapterCommentsLoadIsNotOverwrittenByThem`,
  `chapterCommentsWhoseThreadFailsSayItFailedAndTryAgainRepeatsTheWholeRequest`.
- **A28-4 real, fixed for Chapter Comments.** The chapter is the one the comment's own page
  names (iOS reads it there first), so the chapter index is not read at all: two reads where
  the first version made three. Where the page names no chapter the thread is shown by
  itself; iOS falls back to the index by position. **Still as it was:** the reader's comments
  button resolves its chapter through the index, which is read without the session and is
  kept for the life of the process; a signed-in-only work refuses it and the screen stays on
  All comments.
- **A28-5 real, not changed (P3).** Six tests whose named claim one assertion does not
  exercise, listed in the audit. The series form's scroll to its result has no test that
  would fail without it (it was seen on the emulator).
- **The merge of 3bx (`5c01ce2b`): no fault found**, Claude's landing changes included (the
  preview matrix, the login page as a refusal, the delete without the unused reads).

Unconfirmed, not changed: a caller cancelled in the instant a POST returns while its state
object stays active (collection save, series save) could word a sent write as "not saved";
the audit found no navigation path that does it.

## After the fix, on the emulator (Claude, 2026-10-09, afternoon)

**The rewritten Chapter Comments crashed the app** once the demo could show it
(`IllegalArgumentException: Key "post-comment_1002" was already used`): the thread put first
shared a reply with the chapter's page, and the list keys its rows by comment id. The thread
put first now leaves out any comment the page already shows
(`theThreadPutFirstNeverRepeatsACommentTheChapterPageShows`). The demo's single-comment page
now carries the comment that was asked for, as AO3's does, so the feature can be seen: header
"Chapter 3", scope "Chapter 3", the inbox thread first, two reads.

**A28-4, the part left open, is closed too** (the same afternoon): the chapter index is read
in the reader's session and cached per session (`AO3ChapterIndexRepositoryTest`).

**A28-5, three of its six closed** (the same evening): a second tap while the chapter delete
POST is out (`secondTapWhileTheDeletePostIsHeldSendsExactlyOneDelete`); a posted chapter's
actions and its `update_button` (`aPostedChapterOffersOnlySaveChapterChangesAndSendsUpdate`);
the tautology in `AO3ChapterFormTest` replaced by real multiplicities. Still open: the date
picker's wiring on the chapter screen, the failure paragraph's layout in each theme, the demo
author works' page two.
