# Audit A26 result

Read-only. No source edit, build, emulator, commit, or request to archiveofourown.org.
iOS reference is `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader`. A24 is not re-filed.
Line numbers are the files as they are on `android/agent-grok-a1` at this read.
`LocalDate.withMonth` / `withYear` were checked on JDK 21 before being left out: both clamp an invalid day (`2026-01-31` with month 2 is `2026-02-28`; `2024-02-29` with year 2025 is `2025-02-28`). `withDayOfMonth` throws `DateTimeException`, and the day list is already limited to `lengthOfMonth()`, so the date sheet does not crash.

| id | severity | where | statement |
|---|---|---|---|
| A26-1 | P1 | `AO3WriteRepository.kt:262`, `WritingChapterFormState.kt:159` | After a chapter preview, save, or delete has been sent, a session change is worded as not saved, and a new preview's draft id is thrown away, so the next Preview creates another chapter. |
| A26-2 | P2 | `AO3WriteRepository.kt:124`, `WritingSeriesState.kt:117` | A series reorder or remove whose POST already returned still throws from the manage-page read-back, and the screen says the order was not saved or nothing was removed. |
| A26-3 | P2 | `AO3CollectionFormState.kt:122`, `AO3TagSetState.kt:56` | Several write screens drop the unconfirmed result when the session has moved and leave the action spinning, so the writer is never told to check AO3. |
| A26-4 | P2 | `AppNavHost.kt:537`, `CommentsScreen.kt:142` | Inbox "Chapter Comments" opens the chapter's first page and never the inbox comment, including when that comment is on a later page. |

## A26-1 A sent chapter preview is described as unsaved, then the next Preview creates another chapter

`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writes/AO3WriteRepository.kt:259-263`

```kotlin
val response = withContext(NonCancellable) {
    client.postAuthenticatedInSession(action, fields, writeHeaders(token, referer), expectedGeneration)
}
movedOnAfterWrite(expectedGeneration)?.let { return it }
return response
```

`movedOnAfterWrite` (`AO3WriteRepository.kt:575-577`) returns `Failure(Validation(UNCONFIRMED))` when the generation changed. That return happens before `previewChapter` can read the body:

`AO3WriteRepository.kt:200-202`

```kotlin
val preview = withContext(Dispatchers.Default) { AO3ChapterFormParser().preview(page.body, page.url) }
movedOnAfterWrite(expectedGeneration) ?: AO3Result.Success(preview)
```

The second check runs only when `postWriting` already returned the body. Either way, a generation change discards the preview, including the new chapter id.

`android/app/src/main/java/io/github/cidy02/kudos/writing/WritingChapterFormState.kt:145-160`

```kotlin
when (val result = writes.previewChapter(form, generation)) {
    is AO3Result.Failure -> throw ChapterFailure(result.error)
    is AO3Result.Success -> {
        currentCoroutineContext().ensureActive()
        if (!ownsSession()) return
        val adopted = form.adopting(result.value)
        mutable.value = old.copy(form = adopted, preview = result.value,
            savedRevision = old.savedRevision + if (form.chapterID == null) 1 else 0)
    }
}
} catch (cancelled: CancellationException) {
    if (active && generation != auth.generation.value) mutable.value = old.copy(saveError = WORK_FORM_SESSION_CHANGED)
    else { if (active) mutable.value = old; throw cancelled }
} catch (error: Exception) {
    if (active) mutable.value = old.copy(saveError = if (generation != auth.generation.value) WORK_FORM_SESSION_CHANGED else chapterFailure(error))
}
```

`ChapterFailure` is an `Exception` (`WritingChapterFormState.kt:217`), so the repository's unconfirmed failure lands in the second catch. The generation has changed, which is why `movedOnAfterWrite` fired, so the message becomes `WORK_FORM_SESSION_CHANGED`: "Your AO3 session changed. Reopen this form before saving." (`WritingWorkFormState.kt:344`). `adopting` does not run. `old` still has `chapterID == null` and the create action.

Save and delete do the same replacement (`WritingChapterFormState.kt:127-131` and `:178-183`). Delete's sentence is "Your AO3 session changed, so nothing was deleted." (`:225`). The work form prefers that sentence over a result it already has (`WritingWorkFormState.kt:81-84`):

```kotlin
mutable.value = when {
    generation != auth.generation.value -> retained().copy(saveError = WORK_FORM_SESSION_CHANGED)
    result is AO3Result.Success -> retained().copy(saved = true, saveError = null)
    result is AO3Result.Failure -> retained().copy(saveError = workFormFailure(result.error))
```

`postAuthenticatedInSession` throws `CancellationException` only from `requireSession` (`AO3AuthenticatedClient.kt:51-53`), and that function is `beforeSend`, which runs before `performOnce` (`AO3Client.kt:172-173`). A throw there means the POST did not go out. The hole is the check after the response.

iOS judges the preview body it received and adopts the draft before anything else is sent. `Services/AO3WorkActions.swift:494-502` and `:607-614` return that body. `Models/AO3WritingModels.swift:1016-1027`:

```swift
func adopting(_ preview: AO3PreviewHTML) throws -> AO3ChapterForm {
    var form = self
    if let token = preview.csrfToken { form.csrfToken = token }
    guard chapterID == nil else { return form }
    guard let chapterID = preview.chapterID, preview.workID == workID else {
        throw AO3WorkWriteError.unconfirmed
    }
    form.chapterID = chapterID
    form.actionURL = AO3Client.chapterURL(workID: workID, chapterID: chapterID)
    form.httpMethodOverride = "patch"
    form.isDraft = true
    return form
}
```

`Features/Writing/AddChapterView.swift:423-430` assigns that form before showing the preview. The recorded decision (`docs/android-port/DECISIONS.md:1127-1131`) is that a sent write is reported as "AO3 replied but didn't confirm the change went through", and that iOS judges the answer it has. The session sentence is the one the decision forbids after the POST.

Failing case. On a posted work, Add chapter, title "Two", chapter text "hello", tap the row that calls `openPreview` ("Post chapter now" when "Post without preview" is off, `WritingChapterFormScreen.kt:162-163`). The preview POST is sent. While it is in flight, after `beforeSend` and before the body is judged, Verify Session (or any other generation bump) lands. Android shows "Your AO3 session changed. Reopen this form before saving." The draft AO3 just created is not adopted. Tap Preview again: the form still POSTs to `/works/{id}/chapters`, and AO3 creates a second chapter. iOS shows the preview of the first draft, and Post from that preview updates it. The same session bump during Save of a new chapter, or during Delete, shows the reopen sentence or "nothing was deleted" instead of the unconfirmed sentence. The work form's Save does the same, and a new work's captured create action is unchanged, so Save is offered again against that action.

Smallest fix. Have `postWriting` return the response it already received. In `previewChapter`, parse that body; when `preview()` succeeds, return it so `adopting` runs. Use the unconfirmed failure only when the body does not confirm. In the chapter save, preview, and delete catches, and in `WritingWorkFormState.save`, show that result's message after the POST. Keep the session sentence for the `ownsSession()` check that runs before the POST.

## A26-2 The series read-back still throws after the reorder or remove POST

`AO3WriteRepository.kt:109-126`

```kotlin
val response = withContext(NonCancellable) {
    client.postAuthenticatedInSession(action, fields, writeHeaders(token, url), expectedGeneration)
}
movedOnAfterWrite(expectedGeneration)?.let { return it }
when (response) {
    is AO3Result.Failure -> return response
    is AO3Result.Success -> parser.writeErrorMessage(response.value.body)?.let {
        return AO3Result.Failure(AO3Error.Validation(it))
    }
}
val fresh = try {
    when (val result = client.getAuthenticated(url)) {
        is AO3Result.Failure -> null
        is AO3Result.Success -> try { seriesParser.parseManage(result.value.body, url) } catch (_: Exception) { null }
    }
} catch (cancelled: CancellationException) { throw cancelled }
catch (_: Exception) { null }
movedOnAfterWrite(expectedGeneration)?.let { return it }
```

`getAuthenticated` throws after the manage GET returns when the generation changed during that GET (`AO3AuthenticatedClient.kt:74-75`). The rethrow happens before the second `movedOnAfterWrite`. The first one already passed, so the POST to `/series/{id}/update_positions` or `/serial_works/{id}` has returned.

`WritingSeriesState.kt:116-118` and `:136-137` still turn that throw into the old sentences:

```kotlin
} catch (_: CancellationException) {
    if (active) mutable.value = state.value.copy(error = if (order) "Your AO3 session changed, so the order was not saved."
        else WORK_FORM_SESSION_CHANGED)
```

```kotlin
} catch (_: CancellationException) {
    if (active) mutable.value = state.value.copy(error = "Your AO3 session changed, so nothing was removed.")
```

A `Failure` from `movedOnAfterWrite` would have gone through `workFormFailure` (`WritingSeriesState.kt:109` and `:133-134`) and shown the unconfirmed sentence. This path never gets there. A24-1's post-POST `requireCollectionSession` is gone; this catch is the hole that fix left. Series metadata Save does not use this read-back and does show the failure message.

iOS returns nil from the read-back on a session mismatch and the caller throws unconfirmed, not `CancellationError`. `Services/AO3WorkActions.swift:348-361`:

```swift
guard let rows = await readBackManagePage(manageURL, expectedGeneration: expectedGeneration, using: client),
      !rows.contains(where: { $0.serialWorkID == serialWorkID })
else { throw AO3WorkWriteError.unconfirmed }

private func readBackManagePage(
    _ url: URL, expectedGeneration: Int, using client: AO3Client
) async -> [AO3SeriesWorkRow]? {
    guard let html = try? await workFormHTML(at: url, using: client),
          sessionGeneration == expectedGeneration
    else { return nil }
```

The reorder branch is the same shape (`AO3WorkActions.swift:296-302`).

Failing case. Reorder two works and tap Save. The positions POST finishes and AO3 has the new order. Verify Session lands during the manage-page GET. Android shows "Your AO3 session changed, so the order was not saved." Remove shows "Your AO3 session changed, so nothing was removed." The writer can send a second order, or delete the series believing the work is still in it. iOS shows "AO3 replied but didn't confirm the change went through. Check on AO3 before trying again."

Smallest fix. On `CancellationException` from that read-back, set `fresh` to null and fall through to the unconfirmed return. Do not rethrow.

## A26-3 Other write screens drop the unconfirmed result and stay busy

`movedOnAfterWrite` returns a `Failure`. These callers return before they copy that failure onto the screen, because `ownsSession()` is now false, and nothing else clears the in-flight flag.

`AO3CollectionFormState.kt:118-122` (delete is the same at `:148-150`):

```kotlin
mutable.value = before.copy(saving = true, notice = null, form = form.copy(generalErrors = emptyList()))
try {
    val result = writes.saveCollection(form.copy(generalErrors = emptyList()), generation)
    currentCoroutineContext().ensureActive()
    if (!owns(generation)) return
```

`AO3TagSetState.kt:52-56` (`finally` clears the job, not `saving`):

```kotlin
mutable.value = state.value.copy(saving = true, saveError = null, saveNotice = null)
try {
    val result = writes.saveTagSetFields(data, fields, generation)
    currentCoroutineContext().ensureActive()
    if (!ownsSession()) return
```

The same return, with the busy flag left set, is in:

- `AO3TagSetState.kt:72-74` (`nominationInFlight`)
- `AO3PromptMemeState.kt:64-65` (`promptInFlight`; the `finally` at `:71-72` clears it only while `ownsSession()`)
- `AO3ChallengeSignUpState.kt:81-83` (`saving`)
- `AO3CollectionMaintainersState.kt:81-83` (`inviting`) and `:118-120` (`leaving`); both catches are empty
- `AO3CollectionModerationState.kt:164-165` (`inFlight`, and `busy` stays true while it is set, `:74`)
- `AO3CollectionItemsState.kt:109-110` (phase stays `Submitting`, which is `busy`, `:29`)

iOS reports the unconfirmed error and leaves the control usable. The decision at `DECISIONS.md:1129-1130` says every write in `AO3WriteRepository` is reported with that sentence after the POST.

Failing case. Edit a collection title and tap Save. The POST returns. Verify Session completes before `owns` is checked. The repository has `Failure(UNCONFIRMED)`. The screen returns at line 122. `saving` stays true, `canSave` stays false (`AO3CollectionFormState.kt:32-34`), and the unconfirmed sentence is never shown. The same shape leaves tag-set Save, a prompt claim, a sign-up Save, an invite, Leave, a moderation decision, and a collection-item submit spinning. The writer is not told the change may have landed, and they cannot try again from that screen.

Smallest fix. When the session no longer matches after the call returns, clear the in-flight flag and set the error to `AO3CollectionFields.UNCONFIRMED`. Do not apply a `Success` payload onto the new session. Keep the pre-POST `ownsSession()` return so a change before the POST still sends nothing.

## A26-4 Chapter Comments never opens the inbox comment

`android/app/src/main/java/io/github/cidy02/kudos/app/AppNavHost.kt:536-538`

```kotlin
onOpenChapterComments = { workId, position ->
    navController.navigate(Routes.comments(workId, chapterPosition = position))
},
```

`Routes.comments` can carry a focused comment id (`Routes.kt:116-119`). This call does not pass one. The row's own open does: `AccountInboxPane.kt:317` calls `onOpenWorkComments(workId, item.id)`. The menu item is shown from `AccountInboxPane.kt:319-320` and `:994-1000`, and its label "Chapter Comments" matches iOS.

The comments route starts on the work, not the chapter (`AppNavHost.kt:1041`, `target = AO3CommentTarget.Work`). `CommentsViewModel` init loads that page (`CommentsViewModel.kt:134-136`). The chapter switch is a later effect, and it gives up when a focused id is present (`CommentsScreen.kt:139-146`):

```kotlin
LaunchedEffect(initialChapterPosition, target?.workId) {
    val workId = target?.workId ?: return@LaunchedEffect
    val position = initialChapterPosition ?: return@LaunchedEffect
    if (focusedCommentId != null) return@LaunchedEffect
    val chapterId = chapterIndexRepository?.chapterIdForPosition(workId, position)
    if (chapterId != null) {
        viewModel.setTarget(AO3CommentTarget.Chapter(workId = workId, chapterId = chapterId))
    }
}
```

`setTarget` loads page 1 of whatever target it was given (`CommentsViewModel.kt:472-476`). Passing only the comment id would hit the early return and stay on the focused thread. Passing only the position, which is what ships, loads chapter page 1 and never asks for the inbox comment.

iOS passes both, and the chapter focus still means the chapter's comments. `Features/Account/AccountView.swift:1022-1023` sets focus `.chapter`. The destination is `AccountView.swift:215-226`:

```swift
CommentsView(
    workID: destination.workID,
    context: destination.workContext,
    initialChapterPosition: destination.focus == .chapter
        ? destination.chapterPosition : nil,
    initialCommentID: destination.commentID,
    initialFocusesChapter: destination.focus == .chapter,
```

`Features/Comments/CommentsModel.swift:326-329` takes the comment id first and calls `loadFocusedThread`. When the focus is the chapter, that loads the chapter's first page and inserts the requested root if it is not already there (`CommentsModel.swift:428-451`):

```swift
if pendingInitialFocusesChapter {
    // ...
    scope = .byChapter
    selectedChapter = chapter
    // The Chapter control promises the chapter's comments, not a
    // mislabeled isolated-thread screen. Fetch its real first page,
    // then include the explicitly requested root if it lives on a
    // later AO3 page so focus remains deterministic without crawling.
    guard let chapterPage = await fetchPage(1, auth: auth, forceRefresh: false, expected: expected) else { return }
    presentedPage = Self.chapterPage(chapterPage, including: focusedPage, focusedRootID: rootID)
}
```

Failing case. An inbox comment is on chapter 3, and that chapter's comments put it on page 2. Tap Chapter Comments. Android requests the work's first comment page (`CommentsViewModel` init), then `/works/{id}/navigate`, then chapter 3's first comment page. The inbox comment is not on that page and is not added. iOS opens chapter 3's comments and includes that thread. A comment that does happen to be on page 1 is still not focused, because its id was never passed.

Smallest fix. Navigate with `Routes.comments(workId, focusedCommentId = item.id, chapterPosition = position)`. When both are set, do what `loadFocusedThread` does: chapter scope, that chapter's first page, and the focused root included when it is not on the page. Do not take the early return at `CommentsScreen.kt:142` for that pair, and do not start the work-wide page load that the chapter effect then cancels.

## Fixes that close the case they name

`movedOnAfterWrite` itself returns the unconfirmed failure and does not throw (`AO3WriteRepository.kt:568-577`). The old post-POST `requireCollectionSession` throws are gone. A26-1 and A26-3 are the screens that still hide that failure. A26-2 is the read-back that still throws. The check before a POST still throws, and `beforeSend` is before the bytes (`AO3Client.kt:172-173`).

`AO3SeriesForm.parameters` always keeps `authenticity_token` and `_method` (`AO3SeriesForm.kt:37-41`), then skips those names in the replay (`:42-44`), so they are not sent twice. That closes the meta-only token drop for the series form.

`WritingSeriesScreen.kt:106` says "1 work". That closes A24-2. `SeriesWorksScreen.kt:167` offers Reorder only when more than one loaded work is present. That closes A24-3.

`BackupMergeService.kt:1448-1452` runs the membership pass only for a collection present in `affirmedMemberships`. A collection the archive does not carry is skipped. That closes the extra sweep named in the comment. The loop itself only removes work ids whose tombstone says `SUPPRESS_STALE`.

The inbox menu label matches iOS (`AccountInboxPane.kt:996`, `AccountInboxViews.swift:439`). The destination is A26-4.

The three hand merges were compared. `AccountShortcuts` and both chapter demo routes are in `Routes.title`, `hasSubjectHeader`, and `tabBarHiddenBases`. The author-profile composable still receives `authorUsername`, and `7845158a` added `authRepository`; `initialPseud` was not a navigation argument. `WritingWorkFormScreen`'s returns still reach Edit tags, the series reorder, the chapter form, the text editor, the tag editor, the association picker, the chapters list, and tag choices. The chapters load effect is composed before the chapter-form `return` (`WritingChaptersScreen.kt:48-59`), so Back without a save does not start another `/navigate` read. A confirmed save increments `attempt`, which does.

Account shortcut decode matches Swift for a missing value, a known list, an empty string, and an all-unknown string: both restore the defaults (`AccountShortcuts.kt:30-32`, `AccountShortcuts.swift:90-95`). Series is absent on Android by the brief. Author works URLs omit Date Updated, the column's natural direction, and completion Any, and they omit `work_search` when the scope does not accept it (`AO3AuthorUrls.kt:70-79`). Apply loads page 1 only when the sort changed (`SearchFilterSheet.kt:116`, `AuthorProfileScreen.kt:298-299`). Dismiss only hides the sheet (`:289`). Reset clears filters, not the sort (`:290`).

## Unconfirmed

- A chapter POST still drops `authenticity_token` and `_method` when those names are not enabled served controls (`AO3ChapterForm.kt:110-112`). The series form was changed so that cannot happen (`AO3SeriesForm.kt:37-41`). The chapter filter is the recorded rule in `briefs/3bu-result.md` (modeled pairs filtered to enabled served names). The new-chapter fixture includes a hidden `authenticity_token`, so the ordinary form sends it. This would be confirmed by a chapter form whose token exists only in the `csrf-token` meta tag: the body would then lack `authenticity_token` while iOS still sends it.
- If the caller's job is cancelled while `withContext(NonCancellable)` is returning, the caller can see `CancellationException` before `movedOnAfterWrite`. I did not confirm that against the kotlinx.coroutines version this app uses, and I did not trace whether Back during a save cancels the scope `WritingWorkFormScreen` passes into the chapter form. Confirm those two before treating a Back-during-save as a discarded sent write.
- `chapterIdForPosition` requires an equal position (`AO3ChapterIndexRepository.kt:46`). iOS clamps into `1...chapterCount` (`CommentsModel.swift:600-604`). An inbox `chapterPosition` past the live index would leave Android on the work's All comments. I did not find an inbox item that produces that position.

## Not read

- The new test bodies (`AO3ChapterFormTest`, `WritingChapterReadTest`, `WritingChapterFormStateTest`, `WritingChapterSaveTest`, `WritingChapterDeleteTest`, `WritingChapterRefreshTest`, `WritingChapterFormScreenTest`, `AO3ChapterDispatchTest`, `DemoWritingChaptersTest`, `AccountShortcutsScreenTest`, `AuthorWorksSortTest`, `AuthorProfileSortScreenTest`, `DemoAuthorWorksSortTest`, and the `SettingsRepositoryTest` / `WritingSeriesTest` edits). No test was run.
- `Features/Writing/WritingPreviewView.swift` (the adopt and Post path was read in `AddChapterView` and `AO3WorkActions`).
- `Features/Search/AO3FilterPanel.swift` and `Services/AO3AuthorProfileService.swift`, beyond the Android request and Apply behavior cited above.
- `SettingsRepository.updateAccountShortcuts` past the `account.shortcuts` key.
- `BackupMergeService` outside the membership loop at `:1448-1462`.
- `giveKudos` and any write screen that does not call `AO3WriteRepository`.
- Nothing was opened on an emulator, and archiveofourown.org was not contacted.

---

## Triage (Claude, 2026-10-09)

All four were checked against the code. Gate after the fixes: 2,330 tests.

- **A26-1 real, fixed.** A verdict the write repository returned is now shown as it is by the
  chapter form (save, preview, delete) and the work form: both used to replace it with "Your
  AO3 session changed. Reopen this form before saving." whenever the session had moved on,
  the "didn't confirm" verdict included. A preview AO3 did return is adopted even when the
  session has since moved on, so the form keeps the draft AO3 created
  (`aPreviewAnsweredAfterTheSessionMovedOnStillAdoptsTheDraftAo3Created`); nothing more
  leaves that form. A confirmed save or delete now finishes the form in every case (it could
  stay busy). Five tests pinned the old sentence for a POST that had gone out and were
  corrected.
- **A26-2 real, fixed.** The read-back after a series reorder or removal no longer rethrows
  the client's cancellation: it falls through to "didn't confirm"
  (`aSessionThatMovesOnDuringTheReadBackIsUnconfirmedNotUnsaved`). A screen that closed still
  cancels.
- **A26-3 real for one screen, fixed there.** Six of the seven screens named are rebuilt when
  the session changes (their state is remembered on the session's generation), so no control
  is left busy: the new screen reads AO3 again and shows what AO3 has. The collection form is
  not rebuilt (it keeps what was typed for when the same account is back) and did stay busy
  for good: it now ends with "didn't confirm" once the POST has gone out, and with "Not
  saved" or "Not deleted" when the session moved before anything was sent (that sentence was
  unreachable). Two tests asserted the stuck state and were corrected.
- **A26-4 real, fixed.** The Inbox's "Chapter Comments" passes its comment: the screen reads
  that thread once (not the work's first page), then the chapter's first page, and puts the
  thread first when it is not on that page, as iOS
  (`chapterCommentsFromTheInboxPutTheInboxThreadFirstAndReadItOnce`). Found beside it: a
  comments screen opened on a chapter (also from the reader's comments button) was labelled
  "All comments"; it now carries the chapter's name, and the chapter is applied once, so
  coming back to the screen does not undo a scope chosen since. Where the inbox comment is a
  reply, Android puts the thread AO3 serves for that reply; iOS reads the top of the thread
  as well (one more read).

From its notes:

- **A chapter POST dropped its token** from the body when AO3 gave it only in the meta tag
  (unconfirmed in the audit; real: the third form with the fault of A23-1). Fixed; test
  `theTokenGoesInTheBodyEvenWhenOnlyTheMetaTagCarriesIt`.
- **AO3's login page in answer to a writing POST** is now reported as "Your AO3 session
  expired. Please log in again." (AO3's own refusal), not as "didn't confirm": that answer is
  itself what ends the session. Only for the work, chapter and Edit tags writes so far.
- **"Was not deleted" and "was not removed" in front of "didn't confirm"** contradicted it
  (a chapter delete, a series removal). The unconfirmed sentence now stands alone. iOS says
  both sentences in both places: a small iOS task.
- Not changed: an Inbox chapter position past the end of the chapter index stays on the
  thread (iOS clamps to the last chapter); no inbox row was found that produces one.
- Not looked at: a caller cancelled in the instant a POST returns.

Seen on the emulator the same day: Chapter Comments opens headed "Chapter 3" with the scope
"Chapter 3"; a series Save scrolls AO3's answer into view (it was the list's last row, below
the fold, so Save seemed to do nothing; iOS has the same row and no scroll: a small iOS task).
