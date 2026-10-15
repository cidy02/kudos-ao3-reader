# A51 — review of the 2026-10-15 fixes

What this change does: these fixes prevent several accidental writes, merge edits into fresher forms, narrow cache invalidation, and preserve useful screen state. The central fixes mostly look right, but the write transport still has an automatic POST replay path and several state edges remain.

Reviewed **all seven requested items, in order; no time cutoff**. Android quotations and line numbers refer to **`8723abbefa3b0ca4738b3afd90a0180d8f0a5503`**, read with `git show` in `/Users/cidy02/kudos-android-lane`. Its checkout is on `android/redesign-parity` at `78a1c46f`; the intervening commit only adds the A51 brief. iOS was read in `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader`, HEAD **`4156d988bbbdb8a3bbc487b6ec004c22ce38df8a`** (T-408).

Static review only: changed code, callers, relevant tests, briefs, A49/A50/A37 reports and the binding networking policy. No builds, test execution, emulator work, sign-in, AO3 contact, branch changes, commits or pushes. Dependency/server-route verification used public source on GitHub, not archiveofourown.org. No visual correctness claim. Existing worktree edits were left untouched; this report is the only file written.

In Android references below, **`K/` means `android/app/src/main/java/io/github/cidy02/kudos/`**. Swift paths are relative to the iOS directory above. Findings distinguish a new regression from an incomplete fix or an inherited fault exposed by the requested caller check.

## 1. 3ei F1 — OkHttp recovery and GET retries

**The named GET cases look right.** Disabling recovery does remove OkHttp's transparent retry of a failed pooled connection and a refused HTTP/2 stream. Both surface as `IOException`; HTTP/2's `StreamResetException` specifically extends it ([OkHttp 5.4.0 source](https://github.com/square/okhttp/blob/parent-5.4.0/okhttp/src/commonJvmAndroid/kotlin/okhttp3/internal/http2/StreamResetException.kt#L18-L22)).

`K/network/ao3/AO3Client.kt:207–210`:

```kotlin
} catch (error: CancellationException) {
    throw error
} catch (error: IOException) {
    AO3Result.Failure(AO3Error.networkFromTransport(error))
```

`networkFromTransport` always returns `AO3Error.Network` (`K/network/ao3/AO3Error.kt:39–49`); `AO3RetryPolicy.shouldRetry` accepts Network only for GET and within `maxRetries` (`K/network/ao3/AO3RetryPolicy.kt:19–25`). Each attempt re-enters `coordinator.coordinate`, rather than retrying inside the previous slot (`AO3Client.kt:173–185`). The coordinator spaces starts by 600 ms and caps concurrency at three (`AO3RequestCoordinator.kt:18–34`, `AO3NetworkConfig.kt:4–8`). Binary GETs have the same IO mapping and paced loop (`AO3Client.kt:219–248`). Thus a stale socket after sleep or a `REFUSED_STREAM` gets at most two explicit, paced retries. **Confidence: high from source; neither transport fault was executed.**

Other recovery previously supplied: retryable connection/route failures, eligible 408 responses, and protocol follow-ups. A GET 408 now becomes `AO3Error.Http(408)` and is not retried (`AO3Client.kt:341–347`, `AO3RetryPolicy.kt:30`); this agrees with this project's explicit “other 4xx never retried” rule. Do not restore POST recovery to recover that behavior.

### F1 — P1, incomplete A50 F1 fix: a 503 can still replay a POST

`K/network/ao3/AO3Client.kt:92,175–177,268`:

```kotlin
.retryOnConnectionFailure(false)
...
val result = coordinator.coordinate {
    beforeSend()
    performOnce(method, url, headers, formBody)
}
...
builder.post((formBody ?: "").toRequestBody(mediaType)).build()
```

The body remains repeatable. In pinned OkHttp **5.4.0**, the 503 follow-up does **not** consult `retryOnConnectionFailure`: when `Retry-After` is zero, it returns the original request for another attempt. Its separate HTTP/2 coalesced-connection 421 follow-up also survives this flag. See [RetryAndFollowUpInterceptor.kt:238–265](https://github.com/square/okhttp/blob/parent-5.4.0/okhttp/src/commonJvmAndroid/kotlin/okhttp3/internal/http/RetryAndFollowUpInterceptor.kt#L238-L265).

**Reader consequence:** a comment, subscription or other POST answered with `503` and `Retry-After: 0` is sent again without another tap, pacing slot or session check. The app's GET-only retry policy never sees the first response. Whether the first write reached AO3's application is unknown; the second send alone violates the single-shot policy. This was already part of A50 F1; the 408-only regression test (`android/app/src/test/java/io/github/cidy02/kudos/network/ao3/AO3NetworkingCoreTest.kt:249–258`) does not close it.

**Fix:** make POST bodies non-replayable to OkHttp, in addition to disabling connection recovery; retain explicit GET retries. Verify real-client request counts for 503/zero Retry-After as well as 408. **Confidence: high for the dependency path; no claim AO3 was observed returning these responses.**

That same 503 branch can internally repeat a GET outside the coordinator too. The two named IO failures are covered by explicit paced retries; it is not yet true that every physical GET retry is paced.

**Other clients:** no second native write-sending OkHttp client was found. GitHub release lookup builds a bodyless request (`K/network/github/GitHubReleaseClient.kt:33–38`); the update and TTS download clients do likewise (`K/update/AppUpdateInstaller.kt:62`, `K/reader/speech/TTSDownloadWorker.kt:83`). Coil's separate client is installed only as an image fetcher (`K/KudosApplication.kt:135–143`). The native authenticated writer uses the same AO3 instance for GET and POST (`K/app/KudosAppContainer.kt:146–150`). WebView/browser form submission is separate from these native OkHttp callers.

## 2. 3eo F4 — per-removal cache records

**Looked right; no new finding in the removal journal.** A read records the revision before fetching. A matching removal after that snapshot cancels the read even if no entry existed when it was removed. Parsing suspensions do not open a stale-insertion window: successful insertion checks again while holding the same cache monitor.

`K/network/ao3/AO3PageCache.kt:127–129,162–165`:

```kotlin
val version = revision()
fun requireCurrent() {
    if (scope(auth) != viewerScope || removedSince(key, version)) throw CancellationException()
}
...
loaded is AO3Result.Success -> synchronized(this) {
    requireCurrent()
    insert(key, result.value)
    loaded
}
```

If the read wins the monitor first, the subsequent write removes its inserted entry. If the write wins first, insertion is refused. This preserves the useful part of the old global revision guard without cancelling unrelated reads.

The window boundary is correct (`AO3PageCache.kt:32–39`):

```kotlin
removals.addLast(Removal(++revision, matches))
while (removals.size > 64) forgottenThrough = removals.removeFirst().at
...
forgottenThrough > version || removals.any { it.at > version && it.matches(key) }
```

At equality, the forgotten removal already preceded the read's snapshot, so `>` is correct. A read older than an omitted removal is conservatively cancelled, regardless of key. The deque remains bounded at 64. `removed` is private and every caller holds `@Synchronized`; journal reads, revision snapshots and entry operations use the same monitor. Parsing stays outside it. `evict` only drops an unparseable/refused copy and deliberately creates no write barrier (`:62–64`); it no longer strands unrelated pages. **Confidence: high from the locking and boundary trace.** Existing tests check unrelated removals and matching invalidation; no multithreaded execution was performed.

**Known A37 F3 remains, as the briefs say.** This is distinct from installing an old read after its own removal: a *new* post-write read snapshots the new revision but can join an older transport request. `K/network/ao3/AO3RequestCoalescer.kt:42` still says `inFlight[key] ?: CompletableDeferred<V>().also { created ->`; `AO3Client.kt:111–116` keys that sharing by GET URL and headers, not cache revision. The journal cannot distinguish the answer it receives. This acknowledged issue can also return an old subscription header after its invalidation. It is not counted again as a new A51 finding.

## 3. 3ei F8 — collection switches on the fresh form

**Looked right.** `K/network/ao3/writes/AO3WriteRepository.kt:517–525`:

```kotlin
val base = if (!collectionSwitches) checked else (try {
    AO3ChallengeSettingsFormParser().parse(html, form.slug, form.kind, true)
} catch (_: Exception) { null })?.copy(changes = checked.changes.filterKeys { it in COLLECTION_SWITCHES })
    ?: return AO3Result.Failure(AO3Error.Parse("Couldn't read AO3's collection form."))
val posted = base.copy(token = token)
...
client.postAuthenticatedInSession(posted.actionUrl, posted.parameters(), writeHeaders(token, referer), expectedGeneration)
```

Only the four allowed switch edits are transplanted; the old title, tagline, introduction and untouched switches are not. The fresh parser requires the expected collection action and POST method (`K/network/ao3/account/AO3ChallengeSettingsForm.kt:132–140`). Session checks surround the form read and dispatch.

**What is actually sent:** a full browser-style submission, not just four keys. Consequently a field newly served at save time, which this screen never displayed, can be sent **unchanged with AO3's current value**. That is needed to preserve the rest of the form and is not an invented user edit. `parameters()` iterates the fresh served controls, changes only the last non-hidden twin of an edited name, preserves hidden/repeated/unknown values and replaces the token (`AO3ChallengeSettingsForm.kt:57–72`). Disabled controls and unchecked checkboxes/radios contribute no successful values (`K/network/ao3/writing/AO3WorkForm.kt:83–89`). A switch absent from the fresh form is not appended from the change map. No new dropped required field or stale Basics overwrite was found. **Confidence: high; the Basics-save regression test was read, not run.**

## 4. 3em / T-408 — one form per work, Android and iOS

**Both changes looked right.** Android now calls `editWorkTags(id, expectedGeneration) { fresh -> changes.applying(fresh) }` (`K/network/ao3/writes/AO3WriteRepository.kt:175`). The helper still does the authenticated read, checks cancellation/session after it, parses, and verifies both form kind and work id (`:233–249`). It then sends the merged fresh form:

```kotlin
return submitWork(merge(fresh), expectedGeneration, referer, tagsOnly = true)
```

`AO3WriteRepository.kt:250`. The merge copies tag changes into that form, leaving its token, action, method, language and served controls intact (`K/network/ao3/writing/AO3BulkEdit.kt:44–57`). `submitWork` uses `form.actionUrl` and the same form's CSRF token (`AO3WriteRepository.kt:253–264`); the encoder still carries unknown successful controls and filters absent Edit Tags fields (`K/network/ao3/writing/AO3WorkFormEncoder.kt:5–18,90–97`). The single-work editor still replaces the desired tag set on a fresh form (`AO3WriteRepository.kt:222–226`). Nothing the removed *extra* read supplied is now missing.

iOS `Services/AO3WorkActions.swift:422–429`:

```swift
try requireWorkSession()
var form = try await loadEditTagsForm(workID: workID)
form.tags = changes.applying(to: form.tags)
return try await submitWorkForm(
    form.actionURL,
    form.parameters(submit: .update),
    referer: AO3Client.workEditTagsURL(workID: workID)
)
```

`loadEditTagsForm` still performs the authenticated read and parser (`:22–25`). The parsed DTO retains action, override, CSRF, tags, language and choices (`Services/AO3Client+Works.swift:302–316`); its parameter encoder emits token, override, tags, language and submitter (`Models/AO3WritingModels.swift:652–664`). The old `editTags` path performed the same load again and assigned the merged tag set (`AO3WorkActions.swift:148–156`); no unique check disappeared with that second load. Sequential coordinator admission and the shared write verdict remain. **Confidence: high for this diff; no live writes or builds.** Previously recorded bulk-form and partial-run limitations are outside this fix and were not claimed solved.

## 5. 3ei F10/F11 — comment sessions and routes

**The session fix and edit route look right.** Submit/reply capture generation at `K/network/ao3/comments/AO3CommentRepository.kt:111`, edit at `:190`, delete at `:222`, all before their preparation GET. All four use `postInSession`; its catch distinguishes a session fence from real coroutine cancellation (`:271–280`). Production dispatch rechecks before acquiring headers and through `postFormChecked` after pacing (`K/network/ao3/writes/AO3AuthenticatedClient.kt:53–62`). This closes the stated form-read-to-POST account switch.

Edit strips the query, trailing slash and `/edit` before the `_method=put` POST (`AO3CommentRepository.kt:197–205`). Its real caller passes the parsed `editPath` (`K/comments/CommentsViewModel.kt:769–772`), so both plain and query-bearing `/comments/<id>/edit` links reach `/comments/<id>`. Replies retain the parent's `/comments/<id>/comments` route (`AO3CommentRepository.kt:130–131`, `AO3CommentModels.kt:80–87`), independent of whether the parent is on a work or chapter. These parts pass, subject to F1 underneath.

The requested caller check also exposes two **inherited routing faults**, not introduced by 3ei:

### F2 — P2: Delete still posts to the confirmation link

`K/network/ao3/comments/AO3CommentParser.kt:290–294`:

```kotlin
val href = link.attr("href").takeIf { it.isNotBlank() } ?: continue
when {
    label == "edit" -> editPath = href
    label == "delete" || label.contains("delete") -> deletePath = href
```

`K/comments/CommentsViewModel.kt:728,733` passes that path unchanged to `repository.deleteComment(path)`. `K/network/ao3/comments/AO3CommentRepository.kt:229–230` then does:

```kotlin
val fields = listOf("_method" to "delete", "authenticity_token" to token)
return when (val response = postInSession(session, url, fields, mapOf("X-CSRF-Token" to token, "Referer" to url))) {
```

AO3's Delete link is the GET confirmation action `/comments/delete_comment?id=<id>`, not the destroy endpoint: [comments helper:302–309](https://github.com/otwcode/otwarchive/blob/master/app/helpers/comments_helper.rb#L302-L309), [routes:551–570](https://github.com/otwcode/otwarchive/blob/master/config/routes.rb#L551-L570). Sending `_method=delete` to that path does not destroy the requested comment.

**Reader consequence:** Delete reads its confirmation page successfully, then fails to remove the comment. The tests use `/comments/9` directly (`android/app/src/test/java/io/github/cidy02/kudos/network/ao3/comments/AO3CommentRepositoryTest.kt:134–141`), skipping the real parser-to-writer path. **Fix:** read the confirmation URL, then send its actual destroy form/action (or a strictly validated canonical comment-id endpoint), retaining the captured session. **Confidence: high from caller plus upstream route source; not live-tested.**

### F3 — P1: a new chapter comment can be posted as a work-level comment

`K/network/ao3/comments/AO3CommentRepository.kt:105–109,130–134`:

```kotlin
val csrfSourceUrl = if (replyParentId != null) {
    AO3CommentUrls.commentThreadUrl(replyParentId, isReply = true)
} else {
    AO3WriteUrls.workUrl(target.workId)
}
...
val submitUrl = if (replyParentId != null) {
    AO3CommentUrls.commentReplyEndpoint(replyParentId)
} else {
    form?.actionUrl?.takeIf { it.isNotBlank() } ?: target.defaultSubmitUrl()
}
```

`K/network/ao3/comments/AO3CommentParser.kt:440–445` takes that fetched form's action verbatim. AO3's work view renders its comment form for **the work**, not the requested chapter ([works/show.html.erb:75–76](https://github.com/otwcode/otwarchive/blob/master/app/views/works/show.html.erb#L75-L76); [commentable form:122–124](https://github.com/otwcode/otwarchive/blob/master/app/views/comments/_commentable.html.erb#L122-L124)). Thus a `Chapter(123, 456)` target with a normal `/works/123/comments` form posts there; its correct chapter fallback (`AO3CommentModels.kt:57–58`) is never reached. No separate chapter id is in the submitted fields (`AO3CommentRepository.kt:146–150`).

**Reader consequence:** a reader composing under a chapter can get “Posted.” while the comment is attached through the work endpoint rather than the chapter they chose. Replies and edits are id-based and are not affected by this specific mistake. **Fix:** prepare the chapter's own form for chapter submissions and validate its destination, or preserve the explicit chapter target when selecting the POST endpoint. Add a repository test that submits a Chapter target, not just a test of its URL helper. **Confidence: high for the wrong outgoing destination; exact AO3 display placement was not observed.**

## 6. 3ej — Authors lifecycle, byline accounts, stale answers

**The loop itself now behaves as intended.** `K/library/FavoriteAffinityRow.kt:290–292` runs `store.prefetch(usernames)` under `repeatOnLifecycle(STARTED)`. Leaving the composition or dropping below STARTED cancels the sequential caller. Already kept, fresh answers are skipped on return (`K/library/AuthorNewestWorkStore.kt:72–80`). A failure or stale success returns false at the first unresolved author (`:49–60,78`); it does not repeatedly launch the round while the lifecycle remains STARTED. One unavailable author deliberately keeps the filter unavailable; that is the policy's stop rule, not an infinite loop. Returning to STARTED or reopening retries the unresolved suffix.

**The narrowed identity rule looks right.** `K/library/ReadingAffinities.kt:146–148` requires a closing parenthesis and a parsed pseud; `K/network/ao3/author/AO3AuthorModels.kt:33` anchors the grammar to `^(.+) \(([A-Za-z0-9_]+)\)$`. Bare names no longer become account requests; recorded link-derived identities still win. The stale-page change also looks right: `AuthorNewestWorkStore.kt:55–56` returns false without storing a stale result. **Confidence: high for these local changes.** The following edges prevent calling the whole path finished.

### F4 — P2, residual foreground-policy gap: cancelling the round does not cancel its detached GET

`K/network/ao3/AO3RequestCoalescer.kt:31–32,44–46,57`:

```kotlin
class AO3RequestCoalescer<K : Any, V : Any>(
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
)
...
scope.launch {
    try {
        created.complete(operation())
...
return deferred.await()
```

The lifecycle cancels `await()`, but the independent operation owns the coordinator wait and GET retry loop (`K/network/ao3/AO3Client.kt:111–116,173–185`). There is no subscriber count or last-waiter cancellation.

**Reader consequence:** open Authors, then leave/lock while its current author GET is waiting for pacing or retry backoff. That GET can still **start**, or start another retry, after the screen stopped. The next author is no longer handed off, which is a real improvement; this is a bounded remaining request, not the old unrestricted background walk. Authenticated requests in this path still fall outside the policy's foreground/cancellable exception. **Fix:** cancel a shared read when its last interested caller leaves, without cancelling another active consumer. **Confidence: high from coroutine ownership; background traffic was not measured.**

### F5 — P2, new resume edge: refreshed answers do not invalidate the displayed newest works

`K/library/FavoriteAffinityRow.kt:286,290–298`:

```kotlin
var complete by remember { mutableStateOf<Boolean?>(null) }
...
LaunchedEffect(store, session, round, lifecycle) {
    complete = null
    if (store != null) lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) { complete = store.prefetch(usernames) }
}
...
val newestWorks = remember(store, session, round, complete) {
    usernames.mapNotNull { name -> store?.cached(name)?.work?.let { name to it } }.toMap()
}
```

**Reader consequence:** finish a round (`complete == true`), background for more than the 30-minute answer TTL, and return. The lifecycle block refreshes the store, then assigns `true` again. Its `remember` keys have not changed, so rows retain the previous newest-work map and open the old work (`:334–337`), even if another recomposition occurs. The filter, which directly consults `store.cached` at `:307`, can meanwhile use the new answer. A partial retry returning false after a previous false has the same missing update signal.

**Fix:** publish a changed answer snapshot/revision for each completed round, or reset `complete` inside each lifecycle invocation so refreshed data invalidates the memo. **Confidence: high from the retained-composition path; not exercised on a device.**

### F6 — P2, exposed by the narrower identity rule: unknown authors can still produce “No new work”

`K/library/FavoriteAffinityRow.kt:282,295`:

```kotlin
val usernames = allRows.mapNotNull { it.username }
...
val ready = store != null && complete == true && usernames.all { store.cached(it) != null }
```

The filter drops unresolved rows (`K/library/AuthorNewestWorkStore.kt:101–103`):

```kotlin
val work = row.username?.let(newestWork)?.work
work != null && work.id !in readWorkIds
```

The empty screen then says `"No new work"` and `"None of these $noun has posted something you have not already read."` (`K/library/FavoriteAffinityRow.kt:352–355`).

**Reader consequence:** with only older bare-byline authors, the username list is empty, so prefetch and `all` succeed without any request. “With new work” becomes selectable, hides every unknown row and makes a categorical claim about authors never checked. Mixed known/unknown rows can produce the same false empty message. The new identity admission is correct; this remaining presentation contradicts the brief's “no ‘No new work’ claim.” **Fix:** distinguish unchecked accounts from checked authors with no new work; do not use that empty assertion for an unresolved population. **Confidence: high for the empty-list case.**

## 7. 3ek / 3ep / 3eq / 3eu — screen state and affordances

### Subscribe: looked right for the stated reload gap

`K/author/AuthorProfileScreen.kt:272` rejects `subscriptionBusy || headerLoading`; the hero receives the same combined busy value at `:712`. Success calls `loadHeader(bypassCache = true)` (`:293`), which sets loading before launching and clears it in `finally` (`:171–194`). A failed header load sets `header = null` rather than restoring an enabled old form (`:188`). No suspend separates clearing write-busy from setting header-loading on the success continuation. This closes A50 F2's ordinary delayed-reload gap. The acknowledged A37 F3 transport sharing race remains separate. **Confidence: high; no UI execution.**

### Clear History: page-change race fixed, retained data not cleared

The new marker hides every loaded page after confirmed success, including a page opened during the write. It does not issue an unsolicited reread or clear local library data. That part looks right.

#### F7 — P2, incomplete A50 F3 fix: cleared rows return when the composition is recreated

`K/account/AccountWorksListScreen.kt:169,237,420`:

```kotlin
var historyCleared by remember { mutableStateOf(false) }
...
clearScope.launch { unsubscribeState.confirmClearHistory { historyCleared = true } }
...
if ((current.canonicalWorks.isEmpty() && current.page.works.isEmpty()) || historyCleared) {
```

The retained ViewModel still holds the old loaded page. Its only opening check is (`K/account/AccountViewModel.kt:240–241`):

```kotlin
fun ensureSessionLoaded() {
    if (requestedGeneration != repository.authRepository.generation.value) load(1)
```

**Reader consequence:** clear successfully, then recreate the composition while its navigation ViewModel survives. The plain `remember` resets, the same-session opening check fetches nothing, and the old history rows/pagination reappear. An Activity recreation for a locale change is one route: locale/layout-direction changes are not among the Activity's handled changes (`android/app/src/main/AndroidManifest.xml:30`). Ordinary rotation is handled there and is not the reproduction being claimed. Conversely, while the original composition survives, the marker has no session key and can hide a replacement session's newly loaded history.

**Fix:** clear the session-owned ViewModel's history page and retire pending loads on confirmed success; a composition-only mask cannot establish cleared data. **Confidence: high for retained-ViewModel/remount behavior; no recreation experiment.** The remount weakness existed with the old marker too; this fix closes the page-identity race but does not finish the original state repair.

### Assignments: direct refusals and due-date retry improved; one skipped list remains writable

The new `usable` helper correctly excludes a list that has its own error. `dueRefused` distinguishes Forbidden/AuthenticationRequired from a transport failure (`K/account/AO3ChallengeAssignmentsState.kt:103`), and full Refresh resets the due-date attempt unless refused (`:118`). For a known-closed owner, `readDue()` is reached after list loading (`:167`); it clears old due values before asking (`:99–100`). A timed-out read can therefore recover on the next explicit Refresh without inventing a Late badge. **These parts looked right.**

#### F8 — P2, incomplete A37 F8 fix: Open's old rows survive a failed Complete refresh

`K/account/AO3ChallengeAssignmentsState.kt:53–56`:

```kotlin
private fun usable(list: SignUpAssignmentList) = if (list in errors) emptyList() else rows(list)
fun candidates(kind: AssignmentWrite) = if (kind == AssignmentWrite.Default)
    (usable(SignUpAssignmentList.Complete) + usable(SignUpAssignmentList.Open)).filter { !it.fulfilled && !it.defaulted }
else usable(SignUpAssignmentList.Defaults)
```

But `:148` skips Open when Complete failed:

```kotlin
if (more == null && list == SignUpAssignmentList.Open && state.value.errors[SignUpAssignmentList.Complete] != null) continue
```

A non-refusal failure records only Complete's error (`:159–163`):

```kotlin
val stopped = if (refused && more == null) lists.dropWhile { it != list } else listOf(list)
```

**Reader consequence:** load successfully, then Refresh with Complete timing out or returning 5xx. Open is not read in this round, keeps its old page, and has no error. Its stale unfulfilled assignments remain in “Report a default,” despite the Matched section reporting failure. `select` admits them through `candidates` (`:90–92`), and the footer still offers the action from retained `reportable` rows (`K/account/AO3ChallengeAssignmentsScreen.kt:218,222`).

**Fix:** mark Open unusable when the grouped Complete/Open read is skipped, or track which lists succeeded in this refresh rather than equating “no error” with “freshly usable.” **Confidence: high from the successful-load-then-failure sequence.** A cold-load refusal test does not exercise retained Open rows.

### Series: preservation works, with a repeated-request loading edge

One next-page failure now preserves the shown page and offers the failed page's Retry action (`K/app/SeriesWorksScreen.kt:98–107,228–234`); success replaces it and resets error/loading metadata. The ordinary requested behavior looks right.

#### F9 — P2, new regression: a second pending page request can leave a permanent loading label

`K/app/SeriesWorksScreen.kt:98–105`:

```kotlin
val shown = state as? SeriesWorksState.Loaded
state = shown?.copy(loadingPage = page, pageError = null) ?: SeriesWorksState.Loading
...
is AO3Result.Failure -> shown?.copy(pageError = result.error.displayMessage() to page)
    ?: SeriesWorksState.Error(result.error.displayMessage(), page)
```

Pagination remains active; its call omits an `enabled` override (`:271–275`):

```kotlin
KudosPaginationBar(
    currentPage = current.page.currentPage,
    totalPages = current.page.totalPages,
    onPageChange = { load(it) }
)
```

**Reader consequence:** tap Next twice while page 2 is pending. The second invocation captures a `shown` whose `loadingPage` is already 2. If that request fails, its failure copy retains 2, so `Loading page 2…` (`:227`) stays beside “Couldn't load page 2” after all requests have ended. Subsequent failures keep carrying that marker. The generation fence rejects the first continuation correctly; it does not clear the second one's inherited loading state.

**Fix:** explicitly clear `loadingPage` in the failure state, and/or disable duplicate pagination while loading. **Confidence: high from the two-invocation state trace; not emulator-tested.**

### Author fandom filter and totals: looked right

The selected fandom resets with route/session (`K/author/AuthorProfileScreen.kt:129–130`). `loadTab` snapshots it only for plain Works, includes it in the continuation fence and passes it with sort/page/cache settings to `loadFandomWorks` (`:198–224`). That repository uses the same scoped page cache (`K/network/ao3/author/AO3AuthorRepository.kt:47–55`). Pagination and sort continue through `loadTab`; switching to Gifts/In collections ignores the retained fandom, and returning to Works uses the chosen fandom again. A fandom chip exits selection and starts page one (`AuthorProfileScreen.kt:874–885`).

The totals line explicitly requires `selectedFandom == null`, plain Works, account rather than pseud, and unfiltered completion (`:675–679`), so whole-account words/kudos are not represented as fandom totals. The facet uses the existing header data and reads only on selection; no new crawl was added. **No new fault found; confidence high from source.** No screenshot comparison was performed.

### Queue chevron: looked right

`K/library/QueueOrganizerScreen.kt:464–466`:

```kotlin
if (!selecting && !reordering) {
    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
        tint = tokens.tertiaryInk, modifier = Modifier.size(20.dp))
}
```

That condition matches the branch that actually supplies `QueueCardPress(onClick = onOpen)` (`:471–480`). Selection has its checkbox and reordering its grip. Auto-mirroring handles direction; the decorative icon adds no duplicate accessibility action. **No behavior fault found; visual density and Light parity were not independently seen.**

## Fix first

- **F1 (P1):** prevent OkHttp's remaining 503/421 POST follow-ups; the single-shot write guarantee is still incomplete.
- **F3 (P1, inherited):** keep a new chapter comment on the chapter the reader selected.
- **F2 (P2, inherited):** send Delete to the destroy action rather than its confirmation link.
- **F8 (P2):** exclude skipped Open assignments after a failed Complete refresh.
- **F4 (P2):** stop an abandoned Authors GET from starting/retrying in the background.
- **F5 (P2):** invalidate displayed newest-work snapshots on every resumed round.
- **F7 (P2):** clear retained History data rather than masking it in the composition.
- **F6 (P2):** replace the false “No new work” assertion when authors remain unknown.
- **F9 (P2):** clear the series loading marker after overlapping page requests fail.
