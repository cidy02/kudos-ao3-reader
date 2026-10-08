# A17 result: Android writes, repeating reads, local clears, session

Read-only. No source file was edited. Nothing was built, committed, pushed, or checked out. Nothing was sent to archiveofourown.org, and neither app was run. Android paths are relative to this worktree. iOS paths are relative to `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`.

A4's six findings were not re-filed. The triage at the bottom of `audits/A4-result.md` still holds: A4-1 is fixed on Android (`contentServed`), A4-2 has no Android series form, A4-3's `#error li` parse is in `AO3WriteFormParser.writeErrorMessage`, A4-4's assignment-page walk is not what Android's challenge settings do, and the remaining A4-5 / A4-6 gaps match current iOS (see "Checked and not filed"). A14's three Android examples are still true and are A17-5, A17-6, and A17-7. The History toolbar's Clear History action is a recorded leave-out (`DECISIONS.md:419-421`, `briefs/3w-result.md`); it is not filed. The per-row Delete chip is reachable and is filed.

| id | severity | path:line | statement |
|---|---|---|---|
| A17-1 | P1 | `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/comments/AO3CommentRepository.kt:140` | A comment, reply, or edit whose HTTP status is 200–399 and whose body has no parsed error is reported posted, and the composer then deletes the typed text. Delete does not even read the error flash. Inbox bulk uses the same success test. |
| A17-2 | P2 | `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/preferences/AO3PreferencesRepository.kt:68` | Preferences save treats any HTTP 200–399 as saved. The screen says "Saved successfully." and clears the dirty flag. |
| A17-3 | P1 | `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writes/AO3AuthenticatedClient.kt:80` | `postAuthenticated` copies the Cookie, then waits in the request coordinator with no session check, so a comments POST still waiting is sent after sign-out. A 401 from that path clears whoever is signed in when the response arrives. |
| A17-4 | P1 | `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/comments/CommentCache.kt:18` | Comment threads, including the form's authenticity token and delete/edit paths, are stored on disk with no account or session key and returned as a normal success when the next viewer's public fetch fails. |
| A17-5 | P2 | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountWorksListScreen.kt:816` | "Delete from History" only adds the work id to an in-memory set. AO3 is never told, and the row comes back on the next visit. |
| A17-6 | P1 | `android/app/src/main/java/io/github/cidy02/kudos/settings/PrivacyDataScreen.kt:188` | "Clear N Work(s)" soft-deletes every finished work, including saved and downloaded ones the dialog says it will leave alone. |
| A17-7 | P2 | `android/app/src/main/java/io/github/cidy02/kudos/settings/PrivacyDataScreen.kt:148` | "Clear reading positions" has an empty click, and the stored count above it is the literal `"0"`. |

## A17-1. Comment-shaped writes treat a flashless 200 as posted, and the composer drops the text

`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/comments/AO3CommentRepository.kt:139-154`

```kotlin
val error = formParser.writeErrorMessage(response.value.body)
if (response.value.statusCode in 200..399 && error == null) {
    // Persist choice on success.
    ...
    AO3Result.Success(
        AO3WriteOutcome(
            AO3WriteActionKind.Comment,
            if (replyParentId != null) "Reply posted." else "Comment posted."
        )
    )
}
```

Edit is the same test and then `"Comment updated."` (`AO3CommentRepository.kt:189-191`). Delete does not read the body at all (`AO3CommentRepository.kt:208-213`):

```kotlin
is AO3Result.Success -> {
    if (response.value.statusCode in 200..399) AO3Result.Success(Unit)
    else AO3Result.Failure(AO3Error.Http(response.value.statusCode))
}
```

Inbox bulk is the comment test again (`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/inbox/AO3InboxRepository.kt:86-88`): status 200–399 and `writeErrorMessage == null` becomes `action.successMessage`. The parser already knows a success flash (`AO3WriteFormParser.kt:120-121`, `.flash.comment_notice, .flash.notice`) and an error flash (`AO3WriteFormParser.kt:129-133`, including `.flash.comment_error`). None of these four call `writeSuccessMessage`.

On that Success the comments screen wipes the draft (`android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsViewModel.kt:379-394`):

```kotlin
is AO3Result.Success -> {
    lastSubmittedContentHash = contentHash
    _draft.value = ""
    _replyTarget.value = null
    _editTarget.value = null
    _composerParent.value = null
    _composerPresented.value = false
    _message.value = result.value.message
    draftStore?.clearDraft(...)
    load()
}
```

Delete sets `"Comment deleted."` and reloads (`CommentsViewModel.kt:343-345`). Inbox clears the selection, shows `actionNotice`, and reloads (`AccountInboxViewModel.kt:288-298`).

Checked against iOS `Services/AO3Client.swift:1074-1095`. A recognized error is rejected; a 200–399 is success only when `writeSuccessMessage` finds `.flash.comment_notice` or `.flash.notice`; any other 2xx/3xx is `unconfirmed`. `Services/AO3WriteActions.swift:423-436` turns `unconfirmed` into `AO3WriteError.unconfirmed`, not the success string. Post, delete, and edit all go through that (`Services/AO3CommentActions.swift:46-50`, `:71-75`, `:101-105`). The delete comment there says otwarchive reports a failed delete as `flash[:comment_error]` on a redirected 200. Inbox uses the same verdict (`Services/AO3InboxActions.swift:34-43`). The composer clears the draft only after that call returns success (`Features/Comments/CommentsModel.swift:1074-1079`); an ambiguous post is verified and the text stays (`CommentsModel.swift:1082-1087`).

Failing case, post. Type a comment and tap Post. AO3 returns HTTP 200 whose body is a maintenance or interstitial page: no `#error li`, no `.flash.error` / `.flash.comment_error` / `.flash.caution`, and no `.flash.notice` / `.flash.comment_notice`. Android sets the message to "Comment posted.", closes the composer, and deletes the stored draft. The comment was not posted. It should stay in the composer as unconfirmed. A later check is a read, never a second POST.

Failing case, delete. Tap Delete Comment on your own comment. AO3 redirects to a 200 that contains `flash[:comment_error]`. Android sets "Comment deleted." and reloads. iOS `commentWriteResult` rejects. The comment is still on AO3.

Failing case, inbox. Select rows, run a bulk action, and get a 200 with neither a success flash nor an error flash. Android shows the action's success message and reloads. iOS surfaces unconfirmed.

Policy. `docs/AO3_NETWORKING_POLICY.md` does not name this flash test. The break is the iOS verdict above. Line 43 forbids retrying a write; Android's retry policy already returns false for any non-GET (`AO3RetryPolicy.kt:19`), so this finding is the false success, not a retry.

Smallest fix. Classify these four with the same three-way verdict as `commentWriteVerdict`: error message, then success flash, otherwise unconfirmed. Clear the draft and close the composer only on success. On unconfirmed, keep the text and say it was not confirmed. Delete must read `writeErrorMessage` before it can succeed.

## A17-2. Preferences save treats any 200–399 as saved

`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/preferences/AO3PreferencesRepository.kt:66-73`

```kotlin
is AO3Result.Failure -> response
is AO3Result.Success -> {
    if (response.value.statusCode in 200..399) {
        AO3Result.Success(Unit)
    } else {
        AO3Result.Failure(AO3Error.Http(response.value.statusCode))
    }
}
```

The screen then marks the form clean (`android/app/src/main/java/io/github/cidy02/kudos/account/AO3PreferencesScreen.kt:129-136`):

```kotlin
is AO3Result.Success -> {
    status = "Saved successfully."
    hasEdits = false
    val reloadResult = repository.load(username)
    if (reloadResult is AO3Result.Success) {
        snapshot = reloadResult.value
    }
}
```

That reload replaces `snapshot` only. It does not copy the reloaded toggles, selects, or text fields back into the maps the screen is editing.

Checked against iOS `Services/AO3PreferencesActions.swift:47-64`: `writeErrorMessage` first, then a `.flash.notice`, then the substring "successfully updated", then a 3xx, and otherwise a rejection. The comment there says a bare 200 can be a login page or a soft failure. A bare 200 is not success.

Failing case. Change a preference AO3 rejects. The response is HTTP 200, the body is the form again with `#error li` or `.flash.error`, and there is no success flash. Android sets "Saved successfully." and `hasEdits = false`, so the Save button disables. iOS shows AO3's error and does not claim the save. The toggled values should stay dirty, and the status should be AO3's reason.

Policy. None. This is the false success.

Smallest fix. Use the iOS order: error message, success flash, 3xx, otherwise unconfirmed. Set `hasEdits = false` only after a confirmed save. Leave the toggles and text fields as the reader left them when the save is rejected or unconfirmed.

## A17-3. `postAuthenticated` can send the previous account's Cookie, and its 401 clears the next session

`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writes/AO3AuthenticatedClient.kt:80-101`

```kotlin
override suspend fun postAuthenticated(...): AO3Result<AO3HttpResponse> {
    val authHeaders = when (val result = authRepository.authenticatedHeaders(url)) {
        is AO3Result.Failure -> return result
        is AO3Result.Success -> result.value
    }
    return postClient.postForm(
        url = url,
        formFields = formFields,
        headers = headers + authHeaders
    ).expireSessionIfNeeded()
}

private suspend fun AO3Result<AO3HttpResponse>.expireSessionIfNeeded(): AO3Result<AO3HttpResponse> {
    if (this is AO3Result.Failure && error == AO3Error.AuthenticationRequired) {
        authRepository.sessionDidExpire()
    }
    return this
}
```

`authenticatedHeaders` copies `Cookie` from the current session (`AO3AuthRepository.kt:269-273`). `postForm` calls `executeWithRetry` with the default `beforeSend` of `{}` (`AO3Client.kt:133-149`, `:162-167`). The coordinator takes a slot, waits out the spacing gap, and only then runs that callback (`AO3RequestCoordinator.kt:18-33`). The spacing gap is 600ms (`AO3NetworkConfig.kt:6`), applied after the previous request start (`AO3RequestCoordinator.kt:33`). Collection and sign-up writes do not use this path: `postAuthenticatedInSession` on the default client checks the generation, then passes `requireSession` as `beforeSend` into `postFormChecked`, so the check runs inside `coordinate` after the wait (`AO3AuthenticatedClient.kt:43-58`, `AO3Client.kt:152-159`).

`getAuthenticated` checks the generation after its own response (`AO3AuthenticatedClient.kt:65-73`). A logout during the comment form GET therefore aborts before `postAuthenticated` copies a Cookie. The hole is the wait after that copy.

`sessionDidExpire`'s generation argument defaults to null, and a null argument does not skip the clear (`AO3AuthRepository.kt:278-283`):

```kotlin
suspend fun sessionDidExpire(expectedGeneration: Int? = null) {
    sessionMutex.withLock {
        if (expectedGeneration != null && expectedGeneration != sessionGeneration) return
        clearSessionLocked()
```

`logout` advances the generation and clears the local cookie jar. It does not cancel other ViewModels and it does not POST to AO3 (`AO3AuthRepository.kt:287-329`).

The comments job survives a tab switch. Comments is its own destination, pushed from the reader (`app/AppNavHost.kt:948-951`, `:968-998`). The shell switches tabs with `saveState = true` (`app/MainScaffold.kt:603-610`). In the navigation-runtime jar resolved for navigation-compose 2.9.5 (`android/gradle/libs.versions.toml:21`), `NavControllerImpl.pop` stores that flag on the entry, and `markTransitionComplete` calls `NavControllerViewModel.clear(entry.id)` only when the flag is not set and the entry is no longer in the back queue. `NavControllerViewModel.clear` clears that entry's `ViewModelStore`. A saved tab back stack therefore does not clear the comments ViewModel, and `submitComment`'s `viewModelScope` job keeps running. `submitComment` applies Success with no generation check (`CommentsViewModel.kt:379-394`).

The same unfenced `postAuthenticated` is used by kudos, both subscribe branches, mark for later, and bookmark (`AO3WriteRepository.kt:471`, `:539`, `:546`, `:620`, `:683`), inbox bulk (`AO3InboxRepository.kt:75`), preferences (`AO3PreferencesRepository.kt:57`), and comment submit, edit, and delete (`AO3CommentRepository.kt:129`, `:186`, `:208`). Preferences is launched from `rememberCoroutineScope` (`AO3PreferencesScreen.kt:86`, `:119`), which is cancelled when that composable leaves composition, so it is not the tab-switch example.

Checked against iOS `Services/AO3Client.swift:888-903`. `submitWrite` checks the preparing session, calls `pace()`, checks again, and only then calls `URLSession`. A mismatch throws `CancellationError`. History applies a successful delete only when `writeResultStillOwnsScreen` still matches (`Features/Bookmarks/AO3AccountWorksList.swift:1051-1056`).

Failing case, the POST. Open comments, tap Post. The form GET just ran, so the POST waits in the coordinator for a free slot and then for the rest of the 600ms gap, with the old Cookie already in its header map. Switch to the Account tab and log out, or sign in as someone else. The comments ViewModel is still alive. The POST leaves with the Cookie copied before the wait. AO3 receives a comment from the account that was just left. When the comments screen is restored it shows "Comment posted." and clears the draft. It should throw `CancellationException` inside the coordinator, before OkHttp, and it should not apply the result after the generation has moved.

Failing case, the 401. A `postAuthenticated` call is already in flight with account A's Cookie. AO3 redirects it to login. `mapWriteResponse` turns that into `AuthenticationRequired` (`AO3Client.kt:281-285`). Before that result is applied, account B signs in. `expireSessionIfNeeded` calls `sessionDidExpire()` with no generation, and `clearSessionLocked` signs B out. The fenced path passes the generation into `sessionDidExpire` (`AO3AuthenticatedClient.kt:59-61`) and does not do this.

Policy. `docs/AO3_NETWORKING_POLICY.md:18` (the Writes row) and line 44. A queued write must not continue after its session generation is observed stale. The check is before and after the pace wait, immediately before the request is sent. It is not a per-screen guard, and it does not cancel a request that has already started.

Smallest fix. Send these posts through `postAuthenticatedInSession` (the check already inside `coordinate`). Pass that same generation to `sessionDidExpire`. Callers drop the result when the generation they captured no longer matches, as the collection writes and iOS `writeResultStillOwnsScreen` do.

## A17-4. Comment threads are cached on disk with no account, and the next viewer can be handed them

`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/comments/CommentCache.kt:14-40`

```kotlin
class CommentCache(private val context: Context) {
    private val cacheDir: File get() = File(context.cacheDir, "comment_threads")

    private fun fileFor(target: AO3CommentTarget, page: Int): File {
        val name = when (target) {
            is AO3CommentTarget.Work -> "work_${target.workId}_p${page}.json"
            is AO3CommentTarget.Chapter -> "work_${target.workId}_ch${target.chapterId}_p${page}.json"
        }
        return File(cacheDir, name)
    }
    ...
    suspend fun save(thread: AO3CommentThread, page: Int) = withContext(Dispatchers.IO) {
        ...
        file.writeText(json.encodeToString(thread))
    }
}
```

The file name is work, chapter, and page. There is no username and no session generation. One process-wide cache is installed at `app/KudosAppContainer.kt:176`. A search of `android/app/src/main/java` found no caller of `CommentCache.clear`. `logout` clears the cookie jar and does not touch this directory (`AO3AuthRepository.kt:319-329`).

Every successful parse is written, including an authenticated page (`AO3CommentRepository.kt:39-62`). If the authenticated GET fails, the repository tries a public GET, and if that also fails it returns `cache.load` as `AO3Result.Success`. A public GET that lands on the login page is `AuthenticationRequired` (`AO3Client.kt:317-321`, `mapResponse`), so that path is the cache return, not an error. The serialized thread includes `editPath` and `deletePath` (`AO3CommentModels.kt:218-219`) and `AO3CommentForm.authenticityToken` (`AO3CommentModels.kt:256-258`). The row menu shows "Delete Comment" whenever `deletePath != null` (`comments/CommentThreadComponents.kt:828-838`). It does not check the current user.

Opening Inbox widens the write. `AccountInboxViewModel.startWorkContextEnrichment` calls `loadThread` once per distinct work id on the visible page (`AccountInboxViewModel.kt:372-385`). That is the policy's page-1 hydration. The extra harm is that each of those calls saves into the same unscoped files. `AndroidManifest.xml:11` sets `android:allowBackup="false"`, so this is a same-device, next-account leak, not an Auto Backup leak.

Checked against the comments rule. iOS keeps comment pages in memory only, per `CommentsModel`, keyed by authentication scope and session generation, because owner-only draft chapter titles and action forms are private (`docs/AO3_NETWORKING_POLICY.md:28`).

Failing case. Account A opens comments on a restricted work. The authenticated GET succeeds, and the thread, A's delete and edit paths, and the form's authenticity token are written under `cacheDir/comment_threads/`. A logs out. The next person, or a signed-out A, opens that work's comments. The public GET redirects to login and is `AuthenticationRequired`, so `loadThread` returns A's cached thread as a normal success. The screen can show Delete on A's comments, and the token is in the JSON file. It should not persist comment HTML. Any memory cache should be keyed by account and session generation and dropped in `clearSessionLocked`. A failure for a different session must not return the previous thread.

Policy. `docs/AO3_NETWORKING_POLICY.md:28`.

Smallest fix. Stop writing comment threads to disk. If a memory cache remains, key it by username and `sessionGeneration`, and clear it from `clearSessionLocked`. Do not return a cached authenticated thread after an authenticated or public failure for a different session.

## A17-5. "Delete from History" hides the row and does not tell AO3

`android/app/src/main/java/io/github/cidy02/kudos/account/AccountWorksListScreen.kt:803-816`

```kotlin
DestructiveConfirmation(
    show = pendingDelete != null,
    title = "Delete from History?",
    text = if (pendingDelete?.remote?.title.isNullOrBlank()) {
        "This removes the work from your AO3 reading history. The work stays on AO3."
    } else {
        "“${pendingDelete?.remote?.title}” will be removed from your AO3 reading history. The work stays on AO3."
    },
    confirmText = "Delete from History",
    confirmBeforeDelete = true,
    onConfirm = {
        val pending = pendingDelete ?: return@DestructiveConfirmation
        pendingDelete = null
        deletedIds = deletedIds + pending.remote.id
    },
```

The Delete chip sets `pendingDelete` (`AccountWorksListScreen.kt:920-925`). `deletedIds` is `remember { mutableStateOf(setOf()) }` (`AccountWorksListScreen.kt:784`). Leaving the composition drops it. `readingsByWorkId` is built on the line above (`AccountWorksListScreen.kt:779-780`) and the confirm handler never reads it. No POST runs.

A second dialog, "Clear your entire history?", would hide only the ids currently in `works` (`AccountWorksListScreen.kt:821-830`). Nothing in this file sets `confirmClearHistory` to true, so that dialog does not open. The toolbar action that would open it was left out on purpose: Android has no call for AO3's clear-history form (`DECISIONS.md:419-421`, `briefs/3w-result.md`). That absence is not a finding. Wiring the dead dialog as it stands would repeat this lie for the whole page.

Checked against iOS `Features/Bookmarks/AO3AccountWorksList.swift:389-402` (the same title, confirm label, and message) and `:1037-1058`. iOS POSTs `deleteReading` and removes the row only after success, and only when `writeResultStillOwnsScreen` still matches. The swipe does not post; the confirm does.

Failing case. Open History, tap Delete on a work, confirm "Delete from History". The row disappears. Leave the screen and come back. The row is there. AO3's history is unchanged. The row should disappear only after AO3 accepts the readings destroy, and only for the session that tapped.

Policy. None. The control claims a write it does not make.

Smallest fix. POST the readings destroy iOS posts, with a fresh token from the history page, through `postAuthenticatedInSession`, and remove the row only on a confirmed success for that generation. Leave the unreachable clear-history dialog unwired until that same write exists for the whole history.

## A17-6. "Clear N Work(s)" soft-deletes saved and downloaded works the dialog says it leaves alone

`android/app/src/main/java/io/github/cidy02/kudos/settings/PrivacyDataScreen.kt:180-189`

```kotlin
DestructiveConfirmation(
    show = showClearHistoryConfirm,
    title = "Clear Reading History?",
    text = "Moves your local reading-history records to Recently Deleted for 90 days. The works themselves can also be re-downloaded from AO3 anytime. Your saved and downloaded works aren't affected.",
    confirmText = "Clear ${finishedWorks.size} Work${if (finishedWorks.size == 1) "" else "s"}",
    ...
    onConfirm = {
        showClearHistoryConfirm = false
        scope.launch { workRepository?.softDeleteAllFinished() }
    },
```

The count and the delete set are every active finished work. `observeFinishedWorks` is `observeLibraryWorks().filter { it.isFinished }` (`WorkRepository.kt:124-126`). `softDeleteAllFinished` loads `workDao.getAll()` and soft-deletes each `isFinished` row (`WorkRepository.kt:128-141`). `getAll` is `WHERE isDeleted = 0` (`data/local/dao/WorkDao.kt:32-33`). There is no `!hasEpub` and no `!isProtected`. `isProtected` is `isSaved || isFavorite || isKeptOffline || !hasAo3WorkId || ao3Unavailable` (`core/model/SavedWork.kt:118-119`). `softDelete` sets `isDeleted`, keeps the EPUB, and moves the work to Recently Deleted for 90 days (`WorkRepository.kt:339-355`), so it leaves the library.

Checked against iOS `Features/Account/PrivacyDataView.swift:52-65` and `:120-134`. `freedHistory` is `!hasEPUB && !isProtected`. The comment at `:56-63` says the old filter, which did not check `isProtected`, soft-deleted saved works that had no EPUB, and that this was the bug the dialog's promise forbids. Android is that bug, and it also takes finished works that have an EPUB.

Free up space is a different button and is not this finding. It uses `qualifiesForHold` (`WorkRepository.kt:995-996`: finished, not protected, not deleted, has an EPUB), which matches iOS `Services/LocalDataClearing.swift:29-31`.

Failing case. A work is marked finished, saved, and downloaded (`hasEpub`, `isSaved`). Privacy, Clear reading history, confirm "Clear N Works". That work is soft-deleted into Recently Deleted and disappears from the library. The dialog said saved and downloaded works are not affected. The button should soft-delete only finished works with no file and `!isProtected`, and the count on the button should be that same set.

Policy. None. This is local data the words said would stay.

Smallest fix. Filter both the count and `softDeleteAllFinished` to `isFinished && !hasEpub && !isProtected && !isDeleted`. Keep the confirm.

## A17-7. "Clear reading positions" does nothing

`android/app/src/main/java/io/github/cidy02/kudos/settings/PrivacyDataScreen.kt:128` and `:148`

```kotlin
SubjectFormRow("Reading positions", value = "0")
```

```kotlin
SubjectFormRow("Clear reading positions", showsDisclosure = true, onClick = {})
```

`showsDisclosure = true` draws it as a tappable row. The click is an empty lambda. No dialog is shown. The number above the row is the literal `"0"`, not a count of stored positions.

Checked against iOS `Features/Account/PrivacyDataView.swift:150-161` and `Services/LocalDataClearing.swift:56-85`. iOS confirms, then clears `readiumLocator`, `lastSpineIndex`, `lastScrollFraction`, and `legacyReaderProgress` on works that have one of those set. It keeps the works and `lastReadDate` (Continue Reading order).

Failing case. Tap "Clear reading positions". Nothing happens. Positions stay, and there is no confirmation. It should confirm with iOS's message and then clear those position fields, not the works and not Continue Reading order.

Policy. None. The row claims an action it does not perform.

Smallest fix. Count works that have a locator or a non-zero spine index or scroll fraction, confirm, then clear those fields.

## Checked and not filed

- POST retry. `AO3RetryPolicy.shouldRetry` returns false when the method is not GET (`AO3RetryPolicy.kt:19`). Writes are not retried.
- Kudos treats HTTP 200 as success on purpose. iOS `commentWriteResult` is deliberately not used for kudos (`AO3WriteActions.swift:418-420`). Android matches that (`AO3WriteRepository.kt` kudos handling).
- Subscribe and bookmark still accept a flashless 200. That is the remaining A4-6 P3 on both apps after the triage. Mark for later and work-page unsubscribe already require evidence. Not re-filed.
- Collection save still accepts a "successfully created" / "successfully updated" substring before the parsed-error check (`AO3WriteRepository.kt:292-304`). `writeErrorMessage` runs first and now includes `#error li`, which is the A4-3 fix. The leftover substring is the remaining A4-5 P3 and matches current iOS. Not re-filed.
- Series `seriesWorks` walks pages with no numeric cap. The policy's batch exception allows that for an explicit series download or series preservation (`docs/AO3_NETWORKING_POLICY.md:47`). Callers are the download queue and reading-queue preservation. Not filed.
- Challenge settings reads at most the first and last sign-up page and does not read assignment pages. That is the correction of A4-4, not a new crawl.
- Collections filter crawl is capped at 25 and is user-initiated (`DECISIONS.md:414-418`). Subscriptions enrichment is the anonymous page walk the policy allows (`docs/AO3_NETWORKING_POLICY.md:27`, `DECISIONS.md:406-413`).
- Availability sweep and the tag-refresh worker stay inside the caps and cooldowns the policy names. Not filed.
- The work-form repository documents that it does not write, and the work-form screen is not on a production navigation path. A missing Save there is not a lying control.
- History toolbar Clear History, as an absent AO3 call, is the leave-out cited above. The reachable per-row Delete is A17-5.

## Unconfirmed

- Double-tap Post. `CommentsViewModel.submitComment` (`CommentsViewModel.kt:355-370`) does not return when a submit is already running. It sets `_submitting` inside the coroutine, and the Post button's enabled state is a composition parameter. A second call can only land before the next recomposition. Inbox `startAction` does check `isPerformingBulkAction` before it launches (`AccountInboxViewModel.kt:265-275`), so this suspicion is the comment button only. A search of the local lifecycle-viewmodel 2.10 jars did not prove that `viewModelScope` uses `Dispatchers.Main.immediate` (no `ViewModelKt` class in the runtime jar, and no bytecode string tying `viewModelScope` to `immediate`). Confirm by invoking `submitComment()` twice before the first suspend, or by reading the dispatcher field in that artifact, before filing it.
- A4's unconfirmed sign-up and collection hidden fields were not re-checked against otwarchive. Confirm `AO3ChallengeSignUpForm.parameters` before filing a dropped `tag_set_attributes[id]`.
- `AO3SparseWorkEnricher`'s memo is process-lifetime and is not keyed by session generation. The subscriptions screen starts the walk only while signed in. Confirm whether a metadata card cached for account A can paint on account B's subscriptions page before filing it.
- Author subscribe opening the web, noted by A14 at `AuthorProfileScreen.kt:239`, was not re-read. Re-read that handler and `DECISIONS.md` before filing it as a control that claims an in-app write.

## What was not read

- The writing editor's save body past `AO3WorkFormRepository`'s "no writes" note, chapter-editor POSTs, and `WritingBufferPreview`.
- Author-profile block, mute, and subscribe POSTs, past A14's note. Not re-read this pass.
- Library, queue, and collection delete confirmations against iOS, other than privacy, history, and free-up space. Not compared in full: `QueueStorageScreen`, `CollectionDetailScreen`, library bulk delete, reset settings, and Reset Read Aloud.
- Empty `onRemove` lambdas on `AccountScreen`. Not opened.
- Bookmark composer's close path. Its flashless-200 success matches the A4-6 P3 left on iOS, and the screen was not re-walked.
- `HomeViewModel`'s launch metadata refresh of a handful of works, past the call site in `KudosApplication`.
- Bug-report payload construction past the screen strings. No Cookie header was found in the log calls that were searched. Session-file encryption was not read past the comment in `AO3SessionStore`.
- Tests. Live AO3. otwarchive source this pass (A4 already cited it). `viewModelScope`'s dispatcher implementation in the local lifecycle 2.10 jar, as noted under Unconfirmed.
- `DECISIONS.md` was searched for history, reading positions, and comment cache, and the Clear History leave-out was read in full. The rest of that file was not re-read line by line.
