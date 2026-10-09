# Audit A22 result

Read-only. Lines are the current source in this worktree (`android/agent-grok-a1`). iOS paths are under `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`. A5, A17, and A18, and the decisions in `briefs/3b*-result.md`, were not re-filed. Recorded on purpose and left out: Edit tags pins the work form when that screen opens (`3bt-result.md` around the session-pin sentence); tag saves use `writeErrorMessage`, a fresh edit-tags GET, and replay of unmodeled controls (`3bt-result.md`); challenge sign-up keeps typed fields and says "open the work" (`3bl-result.md`); Search drops unapplied filters only while results are on screen (`A20-result.md` triage for A20-3).

| id | severity | file:line | statement |
| --- | --- | --- | --- |
| A22-1 | P1 | `comments/CommentsViewModel.kt:136` | An unconfirmed reply or edit reloads the page by clearing its target, so the text is saved as a new comment and can be posted as one. |
| A22-2 | P2 | `network/ao3/comments/AO3CommentRepository.kt:34` | A focused comment thread is stored as that work's page cache, so the offline page is the notification thread. |
| A22-3 | P2 | `comments/CommentsViewModel.kt:128` | Opening a comment from the inbox starts the work's page 1 as well, and whichever answer arrives last is what the screen shows. |
| A22-4 | P2 | `home/HomeViewModel.kt:201` | Verify Session during the first subscriptions load drops the answer and Home says there are no subscriptions. |
| A22-5 | P3 | `network/ao3/comments/CommentCache.kt:58` | A cached reply still carries its edit path, delete path, and Reply action. The test that names this rule never builds a reply. |

## A22-1 An unconfirmed reply becomes a new comment, and replaces the draft

`android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsViewModel.kt:133-138`

```kotlin
fun load(page: Int = 1, focusedId: Long? = null, forceRefresh: Boolean = false) {
    val target = _currentTarget.value ?: return
    _focusedCommentId.value = focusedId
    _replyTarget.value = null
    _editTarget.value = null
    _composerParent.value = null
```

`CommentsViewModel.kt:281-296` and `:353-356` and `:416-424`

```kotlin
fun saveDraft() {
    // iOS `saveDraft`: an edit never uses the draft store. ...
    if (_editTarget.value != null) return
    val target = _currentTarget.value ?: return
    val reply = _replyTarget.value
    val content = _draft.value
    viewModelScope.launch {
        draftStore?.saveDraft(
            ...
            parentId = reply?.commentId,
            username = currentUsername()
        )
    }
}

private fun reloadPageOnScreen() {
    val page = (_state.value as? CommentsUiState.Loaded)?.thread?.currentPage ?: 1
    load(page, _focusedCommentId.value)
}

// inside submitComment's Failure branch:
if (unconfirmed || (result.error is AO3Error.Network && !result.error.isOffline())) {
    lastSubmittedContentHash = contentHash
    _message.value = "Couldn't confirm this posted — reloading to check."
    if (reply != null || edit != null) reloadPageOnScreen() else load()
}
```

`load` does not clear `_draft` or `_composerPresented`. The reload runs while the sheet is still open. `saveDraft`'s edit guard and the reply's parent id both read the targets `load` already cleared.

iOS, `Features/Comments/CommentsModel.swift:1054-1059`, `:1092-1105`, and `:1179-1198`:

```swift
func saveDraft() {
    guard let composerContext, composerEditTarget == nil else { return }
    drafts.save(composerText, for: composerContext, identity: authContext.identity)
}

if editTarget == nil, Self.isAmbiguousSubmitError(error) {
    submissionGuard.markAmbiguous(...)
    await runVerification(...)
} else {
    // An ambiguous edit ... does not reload.
    submissionGuard.fail(Self.message(for: error))
}

// finishIfSucceeded, only after phase == .succeeded:
closeComposer()
composerText = ""
if staysOnPage {
    await loadPage(pageOnScreen, ...)
}
```

iOS keeps the composer context, including the parent comment, until a confirmed success, and it reloads only after that close. An ambiguous edit is a failure message. It does not reload.

Failing case. Work 123 has a stored new-comment draft "hello". Reply to comment 55 with "thanks". AO3 returns HTTP 200 with no notice, so `commentWriteFailure` yields `UNCONFIRMED`. `reloadPageOnScreen` calls `load`, which sets `_replyTarget` and `_editTarget` to null. The sheet stays up and still shows "thanks". Dismiss it. `closeComposer` calls `saveDraft` with `parentId` null, and "thanks" replaces "hello". Open New comment: the field is "thanks". Change it to "thanks!" and tap Post. `submitComment` sees no reply and no edit, so it POSTs a new comment on the work. The same sequence with Edit writes the edited body into the new-comment slot, because the edit guard no longer sees an edit target, and a changed Post creates a comment instead of updating one. The reply should stay a reply until the sheet closes, the stored draft "hello" should stay stored, and a second tap should still address comment 55 or the edit.

Smallest fix. Split "fetch this page again" from "reset the composer". `reloadPageOnScreen` should not clear `_replyTarget`, `_editTarget`, or `_composerParent` while `_composerPresented` is true. An unconfirmed edit should show the failure and leave the edit target in place, as iOS does.

## A22-2 The focused thread is cached as the work's comment page

`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/comments/AO3CommentRepository.kt:33-38` and `:64-67`

```kotlin
val safePage = page.coerceAtLeast(1)
val pageUrl = if (focusedCommentId != null) {
    AO3CommentUrls.commentThreadUrl(focusedCommentId)
} else {
    target.pageUrl(safePage)
}
...
if (thread is AO3Result.Success) {
    cache?.save(thread.value, safePage, viewer)
}
```

`cache.save` keys the file by `thread.target`, the page number, and the viewer (`CommentCache.kt:24-29` and `:40-46`). The focused request's URL is `/comments/{id}`. The file name is still `work_{id}_p{page}`.

iOS fetches that standalone page in `loadFocusedThread` (`Features/Comments/CommentsModel.swift:395-409`) and does not pass it to `CommentsPageCache.store`. `store` runs from `fetchPage` (`:820-850`), whose URL is `commentsPageURL` for that work, chapter, and page. The standalone thread stays in memory on that screen. iOS's comment cache is in-memory and dies with the screen (`:1212-1224`).

Failing case. Open an inbox notification for comment 55 on work 123. The screen asks for `https://archiveofourown.org/comments/55` and, on success, writes that thread over the viewer's page-1 file for work 123. Later, offline, open work 123's comments with no focused id. `loadThread` misses the network and returns that file (`AO3CommentRepository.kt:53-54`). The list is comment 55's thread. Page 1 of the work's comments should still be the cached page, or there should be no page cached from this navigation.

Smallest fix. Call `cache.save` only when `focusedCommentId` is null. A focused thread needs its own key if it is kept at all.

## A22-3 Inbox focus races the work's first comment page

`android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsViewModel.kt:127-129` and `:133-141`

```kotlin
init {
    load(1)
}

fun load(...) {
    ...
    viewModelScope.launch {
        _state.value = CommentsUiState.Loading
        val result = repository.loadThread(target, page, focusedId)
```

`load` does not keep the `Job` and does not cancel the previous one. The screen then starts a second load (`comments/CommentsScreen.kt:130-134`):

```kotlin
LaunchedEffect(focusedCommentId) {
    if (focusedCommentId != null) {
        viewModel.load(focusedId = focusedCommentId)
    }
}
```

The view model is created with `viewModel(...)` before that effect (`CommentsScreen.kt:121-124`), so `init` has already launched page 1. Both requests run. Each writes `_state` when it returns. There is no generation check.

iOS, with a pending comment id, uses `loadFocusedThread` as the initial load (`Features/Comments/CommentsModel.swift:395-409`). It does not also request the work's page 1 unless the screen is in the chapter-focus branch (`:443-445`), and that branch stores the real chapter page.

Failing case. Tap an inbox row for comment 55 on work 123. The work's comment page 1 and `/comments/55` are both in flight. If page 1 returns last, the screen shows page 1 and the notification comment is absent whenever it lives on a later page. If the focused thread returns last, the screen is right and A22-2 has already replaced the page-1 cache. One of those two answers should be requested, and a late page-1 response should not replace the thread the reader opened.

Smallest fix. Pass the focused id into the view model and have `init` load that, or cancel the previous `load` job at the start of `load` and ignore a result whose request id is older.

## A22-4 Verify Session abandons the first subscriptions load

`android/app/src/main/java/io/github/cidy02/kudos/home/HomeViewModel.kt:187-220`

```kotlin
private suspend fun loadSubscriptions(auth: AO3AuthState) {
    if (!auth.isSignedIn) {
        subscriptions.value = emptyList()
        ...
        return
    }
    subscriptionsLoading.value = true
    val generation = authRepository.generation.value
    try {
        val result = accountListRepository.load(AccountListType.Subscriptions, page = 1)
        if (authRepository.generation.value != generation) return
        when (result) { ... }
    } finally {
        subscriptionsLoading.value = false
    }
}
```

The collector is `authRepository.state.collect { loadSubscriptions(auth) }` (`HomeViewModel.kt:124-126`). Verify Session bumps the generation and then assigns `SignedIn` again (`auth/AO3AuthRepository.kt:200-203` and `:305-306`). `SignedIn` is a data class of the username (`auth/AO3AuthState.kt:7`). The same username does not emit a new `StateFlow` value, so the collector does not start another load. The `return` skips assigning the list. `finally` clears the loading flag. An empty list with `subscriptionsLoadFailed` still false is the empty copy (`home/HomeFacts.kt:347-351`, drawn at `home/HomeScreen.kt:534` and `:564-566`).

iOS, `Features/Home/HomeView.swift:577-586`:

```swift
let generation = auth.sessionGeneration
let loaded = try await auth.accountSubscriptions()
guard !Task.isCancelled, auth.isLoggedIn, auth.sessionGeneration == generation else {
    isLoadingSubscriptions = false
    if !Task.isCancelled, auth.isLoggedIn { await loadSubscriptions() }
    return
}
```

A generation move while still signed in asks again. That is the A20-6 repair. Android's check stops the late write (A19-5) and does not ask again.

Failing case. Signed in as the same account, open Home, and let the subscriptions request stay in flight with an empty shelf (the skeleton). On Account, tap Verify Session and let it succeed. The in-flight call returns, the generation no longer matches, and Home sets loading to false without a list and without `subscriptionsLoadFailed`. The shelf says "You have no work or series subscriptions yet." A pull to refresh is what fills it. The shelf should show the list from a new request, or the failure sentence.

Smallest fix. On a generation mismatch, if `authRepository.state.value` is still signed in, call `loadSubscriptions` again with that state. Keep the early return that refuses to assign the stale page.

## A22-5 Cached replies still have edit, delete, and reply

`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/comments/CommentCache.kt:54-59`

```kotlin
/** What is safe to keep: the words, and nothing that posts, edits, deletes or replies. */
internal fun readOnly(thread: AO3CommentThread): AO3CommentThread = thread.copy(
    form = null,
    comments = thread.comments.map { it.copy(editPath = null, deletePath = null, canReply = false) }
)
```

`AO3Comment.replies` is the nested list (`network/ao3/comments/AO3CommentModels.kt:228`). `copy` on the parent leaves that list as it was, including each reply's `editPath`, `deletePath`, and `canReply`. The action row shows Reply, Edit, and Delete from those fields (`comments/CommentThreadComponents.kt:700` and `:777-828`). The offline path returns this object (`AO3CommentRepository.kt:53-54`).

The viewer key does separate accounts (`CommentCache.kt:61-65`). This does not hand the file to the next account. It leaves the action URLs in the signed-in viewer's file, which is the property the comment says the copy does not have. iOS does not write comment action URLs to disk (`Features/Comments/CommentsModel.swift:1222-1224`).

`android/app/src/test/java/io/github/cidy02/kudos/network/ao3/comments/CommentCacheTest.kt:11-27` builds one top-level comment and no `replies`. `aCachedThreadCarriesNothingThatCanAct` stays green if every reply keeps `/comments/10/edit` and `/comments/10`.

Failing case. A thread whose top-level comment has a reply with `editPath` `/comments/10/edit`, `deletePath` `/comments/10`, and `canReply` true. After `readOnly`, the parent has none of those, and the reply still has all three. Offline, More on that reply offers Edit Comment and Delete Comment. The file should contain neither path, and the reply should not offer Reply.

Smallest fix. Map `readOnly` recursively over `replies`. Add a reply with those three fields to `aCachedThreadCarriesNothingThatCanAct` and assert they are cleared.

## Fixes whose named case is closed

- `AO3AuthenticatedClient.postAuthenticated` captures the generation and `postAuthenticatedInSession` checks it before headers, after headers, and again at `postFormChecked` (`AO3AuthenticatedClient.kt:82-101` and `:45-64`). A fence failure while the caller is still active becomes `AuthenticationRequired`, and a 401 expires only that generation. In `android/app/src/main/java`, `postFormChecked` is called only from that client, and the only request builder that uses `.post` is `AO3Client`. This closes A17-3 for AO3 form posts.
- `commentWriteFailure` returns AO3's error text, then the fallback for a non-2xx/3xx, then null only when `writeSuccessMessage` finds a notice, otherwise `UNCONFIRMED` (`AO3WriteFormParser.kt:140-143`). Comment submit, edit, and delete, and the inbox write, call it. A bare 200 no longer counts as posted. This closes A17-1.
- `AO3PreferencesRepository.save` checks `writeErrorMessage` first, then a notice, a 3xx, or the "successfully updated" sentence (`AO3PreferencesRepository.kt:74-82`). A bare 200 is `UNCONFIRMED`. Same order as `Services/AO3PreferencesActions.swift:55`. This closes A17-2.
- Comment drafts call `currentUsername()` at each read and write (`CommentsViewModel.kt:59-63`). The screen passes a lambda over the latest name (`CommentsScreen.kt:120-123`). This closes A18-2. `CommentDraftStore`'s key format was not re-opened.
- `saveDraft` returns immediately when an edit target is set (`CommentsViewModel.kt:283-284`). That closes A18-1 for a live edit. A22-1 is the reload clearing that target first.
- `SensitiveWorkRow` puts `hiddenMatureWorkSemantics` after the click (`SensitiveWorkRow.kt:175-180`). A fandom or tag tap on a blurred or selecting row calls the card action (`:160-161`). `HomeLocalWorkFrame` reveals on click and opens the menu on a long-press only when the work is not obscured (`home/HomeWorkMenu.kt:92-102`). iOS keeps a separate expand control on a blurred row (`Features/Privacy/MatureContent.swift:169-180`); Android's expand control also expands and does not reveal. A18-5 and A19-6 stay closed for the cases those comments name.
- `discardFilterEdits` resets filters to `lastFilters` only in `Results` (`search/SearchViewModel.kt:136-139`). That is the A20-3 repair as its triage recorded it. Search's library matches treat Hide as hidden and Blur as a blurred row (`search/SearchScreen.kt` passes `LibraryPrivacyVisibility.Hidden` into the hidden set). iOS `SearchView.computeLocalMatches` also filters with `isHidden` only.
- Availability rows that are not `Visible` say "Hidden mature work" and reveal (`settings/AvailabilitySweepScreen.kt:193-206`). iOS does the same for hidden and blurred (`Features/Account/AvailabilitySweepView.swift:70-84`). The section count still includes them, which A19-9 already accepted.
- `ReaderProgressSaver.flushPending` holds `writing` across `save` (`reader/ReaderProgressSaver.kt:47-52`). A flush that arrives during the database write waits and then writes a newer `pending`. That closes the A5-1 window the comment names.
- `LibrarySelection.visible` intersects the selection with the ids on screen (`library/LibrarySelection.kt:22-23`). That closes A5-5's "Delete counts works you cannot see." iOS still keeps the hidden ids selected; A5's triage already recorded that difference.
- History grouping rules (yesterday cut, state order, fandom family, tally wording) match `Features/Library/LibraryHistoryGrouping.swift`. Favorites' source keeps `LibraryPrivacyVisibility.Visible` only (`library/ReadingAffinities.kt:85`), which `3bq-result.md` calls privacy-visible. A History fandom header is the fandom of every work in `sectionItems` (`library/LibraryScreen.kt:1312-1316`, `library/LibraryHistoryGrouping.kt:118-131`), and those items include blurred rows. iOS groups `visibleItems`, and `passesPrivacy` is `!isHidden` (`Features/Library/LibrarySectionListView.swift:100-101` and `:646-654`; `PrivacyGate.isHidden` is Hide mode only, `MatureContent.swift:62-65`). A blurred work's fandom can title a section on both platforms. Hide mode drops the work before grouping. Not filed.

## Unconfirmed

- Right-to-left paginated end. `ReadiumNavigatorHost` reports `page` as `totalPages - pageIndex` for RTL. If `pageIndex` is already the logical page, a complete work would finish on the first page of the last chapter. `3br-result.md` says paginated mode was not seen on the emulator. Confirm against Readium Kotlin 3.3.0's meaning of `pageIndex`, without a device.
- `ReaderProgressSaver.onProgress` writes `pending` without the mutex. A location callback that lands after `flush` has returned, and after the debounced job was cancelled, is saved only if that new job runs. Confirm by flushing on reader close and then delivering one more progress before the scope cancels.
- `AnnotationRepository.deleteAnnotation` stores `recordID = id.lowercase()` (`reader/AnnotationRepository.kt:51`). Confirm iOS's tombstone record id uses the same case, or a backup from iOS will not suppress the highlight.
- Edit-tags chip remove closes over the composed `values` list (`writing/WritingEditTagsScreen.kt:168-169`). iOS removes from the live collection at tap time (`Features/Writing/WritingTagsEditor.swift:215-216`). Two removes that run before the next composition would leave one tag. Confirm with a test that invokes both click lambdas on one composition.
- Inbox author enrichment calls `loadThread` once per work (`account/AccountInboxViewModel.kt:382`). Each success is now written into that work's page-1 comment cache. Confirm the networking policy allows that fan-out. The policy file was not re-read.
- Edit-tags body token. The demo fixture includes an `authenticity_token` input, so the header and the body match. A page whose only token is the meta tag would drop it from the body if that name is not an enabled successful control. Confirm on a real edit-tags document. No request was made.

## Not read

Not compared line by line to Swift, or not opened: `backup/BackupMergeService.kt` beyond `mergeAnnotations`, `parkDisplacedNote`, and `dedupeSamePassageAnnotations`; `works/detail/WorkDetailForms.kt`; the series-preservation loop in `library/ReadingQueueRepository.kt`; `WorkImporter.preserveQueuedWork` against `ReadingQueueService.swift:476-528` (the Android function was read); `writing/WritingChaptersScreen.kt`; `account/WritingDraftsScreen.kt`; `AO3WorkFormEncoder.kt` and `AO3ChallengeSignUp.kt` were not re-opened after the context cut (an earlier pass found their field order recorded in `3bo`, `3bt`, and `3bl`); `reader/EndOfWorkActions.kt` and `ReaderViewport.kt` were not re-opened (the earlier pass matched the `3br` paginated and scrolled rules); `docs/android-port/DECISIONS.md`; `docs/AO3_NETWORKING_POLICY.md`; `briefs/3bm-result.md` and the series-loop sections of `3bn-result.md` and `3bs-result.md`. No source file was edited. Nothing was built, committed, or requested from AO3.

## Triage (Claude, 2026-10-09)

All five read against the code; all real, all fixed (gate 2,212). Four were in fixes of the
day before that no one had reviewed.

- **A22-1 real, fixed.** A reload no longer clears the composer's reply or edit target
  while the sheet is open, and an edit AO3 did not confirm is a failure message with no
  reload, as on iOS. Test `aReloadWhileTheComposerIsOpenKeepsTheReplyAndItsDraftSlot`. The
  fault was older than A20-5's change (the check after an unconfirmed post always reloaded),
  but that change widened it.
- **A22-2 real, fixed.** Only a work's or chapter's own page is cached or read from the
  cache; one comment's thread is not.
- **A22-3 real, fixed.** A new comments view model loads the Inbox's thread first and only
  (no page 1 as well), and a newer load cancels the older one.
- **A22-4 real, fixed.** Home asks again when the session moved on while it was loading and
  the reader is still signed in (iOS T-370 did the same for iOS's A20-6).
- **A22-5 real, fixed.** The cached copy strips replies at every depth; the test now builds
  two levels of them.

From "Unconfirmed":

- **The Inbox's author lookup wrote each work's first page of comments into the offline
  cache**: comments of works the reader never opened. Fixed: that read no longer uses the
  cache (`useCache = false`). The lookup itself is allowed (`AO3_NETWORKING_POLICY.md`,
  "Inbox metadata").
- Still open, none confirmed: right-to-left paginated end of a work (needs Readium's
  meaning of `pageIndex`); a progress callback after the reader's last flush; the case of a
  tombstone's record id against iOS's; two quick chip removes on Edit tags; Edit tags when
  the page's only token is the meta tag.

Not read by this audit: most of `BackupMergeService.kt`, `WorkDetailForms.kt`, the series
preservation loop, `WritingChaptersScreen.kt`, `WritingDraftsScreen.kt`.
