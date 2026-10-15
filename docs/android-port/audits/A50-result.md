# A50 — second reviews of Android changes since 2026-10-10

Reviewed all seven items, in the requested order. No time cutoff. Android evidence is from **`108835015606300374e5f518f995af0da7eade99`**, read with `git show` in `/Users/cidy02/kudos-android-lane`; its checkout had already advanced, so checkout files were not used for Kotlin conclusions. Paths and line numbers below refer to that commit. The named briefs and the Living Prompt's §10 items 3, 3a and 3b were read. iOS comparisons use `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`.

This is static review, including callers, repositories, shared dispatch and relevant existing tests. No build, test execution, emulator run, sign-in or AO3 contact. The only external verification was reading the pinned OkHttp dependency's source on GitHub for F1. No source, task board, branch, commit or remote was changed. The pre-existing untracked A49 report was left alone.

## 1. 3ci — author Subscribe / Unsubscribe (`a5c14a94`)

**What looked right.** The screen's `submitSubscription` sets `subscriptionBusy = true` before launching and rejects a second invocation while busy (`android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:262–270`). The button is disabled while busy (`author/AuthorProfileComponents.kt:124–137`, same Kotlin source root). Subscribe is immediate; Unsubscribe first shows the account-wide warning and Cancel (`AuthorProfileScreen.kt:541–553`). These match iOS `Features/Authors/AuthorProfileView.swift:154–165`.

The repository preserves the served subscription fields, replacing only the token, and fences the preparing session (`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writes/AO3WriteRepository.kt:1081–1093`). The shared dispatch checks that session again after pacing (`network/ao3/writes/AO3AuthenticatedClient.kt:47–62`). A failure shows an error without optimistically flipping the button (`AuthorProfileScreen.kt:278–288`); an ambiguous response warns the reader to check AO3 before trying again (`AO3WriteRepository.kt:1238–1239`). That failure behavior looked right.

### F1 — P1: one repository call can still send a write twice inside OkHttp

**Evidence:** `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3Client.kt:86–93`:

```kotlin
return OkHttpClient.Builder()
    .installDemoNetworkBlock()
    .callTimeout(config.callTimeoutSeconds, TimeUnit.SECONDS)
    .followRedirects(false)
    .followSslRedirects(false)
    .addInterceptor(AO3RedirectCookieRelayInterceptor())
    .build()
```

The body is repeatable (`AO3Client.kt:264`):

```kotlin
builder.post((formBody ?: "").toRequestBody(mediaType)).build()
```

Pacing and the session check surround the whole call, not each internal attempt (`AO3Client.kt:171–173`):

```kotlin
val result = coordinator.coordinate {
    beforeSend()
    performOnce(method, url, headers, formBody)
}
```

**Reader consequence:** a POST receiving a 408 without a positive Retry-After can be sent again without another tap. The app-level `if (method != AO3HttpMethod.GET) return false` (`AO3RetryPolicy.kt:19`) never gets to prevent that internal replay. It also bypasses the next pacing slot and session check. This affects Subscribe, Unsubscribe, Clear History, challenge saves and comments through the same production client. It is an inherited transport defect, not a new retry loop in 3ci.

Verified against pinned **OkHttp 5.4.0** (`android/gradle/libs.versions.toml:22`): its [builder defaults](https://github.com/square/okhttp/blob/parent-5.4.0/okhttp/src/commonJvmAndroid/kotlin/okhttp3/OkHttpClient.kt#L554) enable recovery; its [retry interceptor](https://github.com/square/okhttp/blob/parent-5.4.0/okhttp/src/commonJvmAndroid/kotlin/okhttp3/internal/http/RetryAndFollowUpInterceptor.kt#L214-L248) handles 408 and 503/Retry-After: 0 internally. **Confidence: high for the replay path; no claim that AO3 was observed returning either response.** Fix the production write transport so the body cannot be replayed and automatic write recovery is disabled; retain paced, explicit GET recovery. Cover this with the real client against a local server, rather than a fake that counts repository calls.

### F2 — P2: the old subscription action is enabled before the new header arrives

**Evidence:** `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:275–285`:

```kotlin
} finally {
    subscriptionBusy = false
}
...
is AO3Result.Success -> {
    profileMessage = result.value.message
    ...
    loadHeader(bypassCache = true)
}
```

`loadHeader` starts a separate job and leaves the existing header present until its answer (`AuthorProfileScreen.kt:167–184`). The visible button depends only on the old form and `!subscriptionBusy` (`android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileComponents.kt:124–137`):

```kotlin
onClick = { onSubscription(form) },
enabled = !subscriptionBusy,
...
Text(if (form.isSubscribed) "Unsubscribe" else "Subscribe", fontSize = 13.sp)
```

**Reader consequence:** after “Subscribed.”, dismissing the dialog while the header GET is delayed exposes an enabled **Subscribe** again. Tapping it resubmits the old creation form. After unsubscribe it similarly offers the obsolete deletion form. The second tap *during the first POST* is guarded correctly; this gap begins after the POST and before header replacement. iOS keeps `isPerformingSubscription` set while awaiting `reloadHeaderTracked` (`Services/AO3AuthorProfileService.swift:419–434`). **Confidence: high.** Keep the action unavailable through header reconciliation and require fresh form evidence before enabling it again.

## 2. 3co step 7 — Clear History (`c2442cd6`)

**What looked right.** The menu opens a native destructive confirmation; only its confirm callback calls the writer (`android/app/src/main/java/io/github/cidy02/kudos/account/AccountWorksListScreen.kt:227–239,323–334`). `SubscriptionUnsubscribeState.confirmWrite` sets its busy key before suspension and invokes `onSuccess` only for a success in the same session (`account/SubscriptionUnsubscribeState.kt:39–53`). Failures leave the rows and show the error. **Nothing in this path clears local library works, reading sessions or even the displayed history before AO3 says yes.**

`clearReadingHistory` requests the signed-in account's `/readings/confirm_clear` token, then posts only that token to `/readings/clear` (`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writes/AO3WriteRepository.kt:1183–1192`). This matches iOS `Services/AO3WriteActions.swift:280–299`. No application retry or unsolicited write was found, subject to F1's underlying transport replay.

### F3 — P2: success hides one captured page object instead of clearing the history state

**Evidence:** `android/app/src/main/java/io/github/cidy02/kudos/account/AccountWorksListScreen.kt:167,233–236,419`:

```kotlin
var clearedPage by remember { mutableStateOf<Any?>(null) }
...
val page = loaded?.page
clearScope.launch { unsubscribeState.confirmClearHistory { clearedPage = page } }
...
if ((current.canonicalWorks.isEmpty() && current.page.works.isEmpty()) || clearedPage === current.page) {
```

History pagination remains available during the write (`AccountWorksListScreen.kt:1010–1012`):

```kotlin
if (totalPages > 1) {
    item {
        KudosPaginationBar(currentPage = currentPage, totalPages = totalPages, onPageChange = onLoadPage)
```

**Reader consequence:** confirm Clear on page 1, then request page 2 while the token read/POST is pending. If page 2 loads before the clear completes, success marks page 1's object; page 2 remains visible, containing history AO3 just cleared. The ViewModel still holds its works, reading entries and page count. The composition-only marker can also disappear when that composition is recreated while its ViewModel survives. iOS actually empties its arrays and resets pagination (`Features/Bookmarks/AO3AccountWorksList.swift:1054–1059`). **Confidence: high for the page-change race; composition restoration was not exercised.** On confirmed success, clear the session-owned ViewModel state and retire pending history loads, without another AO3 read.

## 3. Favorites Authors, “With new work”, and byline accounts (`78beddc1`, `1b25f24d`, `2ddab9c7`)

**Reads for one look.** `FavoriteAffinityList` starts the round when the Authors list is composed, including when **All** is selected; it does not wait for a “With new work” tap. Its input is every resolvable author row, not only rows drawn in the viewport (`android/app/src/main/java/io/github/cidy02/kudos/library/FavoriteAffinityRow.kt:273–287`). `AuthorNewestWorkStore.prefetch` deduplicates usernames and walks them sequentially (`library/AuthorNewestWorkStore.kt:69–77`). The container requests each account's first Works page sorted by Date Posted, without a dashboard read (`app/KudosAppContainer.kt:165–175`).

Thus, with **N distinct uncached usernames**, a healthy cold opening makes **N logical page reads**, one after another. A fresh 30-minute answer costs zero; a fresh underlying five-minute HTML cache can also avoid a network request. Normal systemic failure stops the walk; GET retries and redirect hops can make the physical request count larger. Signed-in reads use `getAuthenticated`, otherwise public GET (`network/ao3/author/AO3AuthorRepository.kt:81–88`). Reading account links while parsing already-fetched blurbs/work pages adds **zero** requests (`network/ao3/search/AO3SearchParser.kt:71–72,115–116`; `network/ao3/work/AO3WorkMetadataParser.kt:35–41`).

**Policy judgment:** this is a bulk, per-author walk in the ordinary sense, but the binding policy explicitly grants the **foreground, cancellable Favorites Authors newest-work exception**. I do not count that authorized foreground walk itself as a violation. The scope/loop checks, session-qualified cache, normal failure stop and unavailable filter until completion looked right. The following cases do not satisfy those limits.

### F4 — P1: backgrounding the app does not stop the Authors walk

**Evidence:** `android/app/src/main/java/io/github/cidy02/kudos/library/FavoriteAffinityRow.kt:285–288`:

```kotlin
LaunchedEffect(store, session, round) {
    complete = null
    if (store != null) complete = store.prefetch(usernames)
}
```

The only per-author gate is coroutine cancellation/cache status (`android/app/src/main/java/io/github/cidy02/kudos/library/AuthorNewestWorkStore.kt:72–75`):

```kotlin
for (username in distinct) {
    currentCoroutineContext().ensureActive()
    if (cached(username, scope) != null) continue
    if (!fetchAndStore(username, scope)) return false
}
```

The app's background callback does not cancel these reads (`android/app/src/main/java/io/github/cidy02/kudos/KudosApplication.kt:114–119`):

```kotlin
override fun onActivityStopped(activity: Activity) {
    startedActivityCount = (startedActivityCount - 1).coerceAtLeast(0)
    if (startedActivityCount == 0) {
        maybeRunFolderSync()
    }
}
```

**Reader consequence:** open Authors with many uncached accounts, then press Home or lock the phone. The retained composition's `LaunchedEffect` is not cancelled merely because its Activity stops. The loop can start subsequent authenticated author reads while the app is in the background. Navigating away/disposal does cancel the caller; that is a different event. This violates the explicit foreground-only exception and the prohibition on background logged-in scraping. **Confidence: high from lifecycle ownership; not device-tested.** Tie the round to the visible, started/resumed screen lifecycle and stop handing off authors when it stops.

### F5 — P1: a pseud-shaped word becomes somebody else's account

**Evidence:** `android/app/src/main/java/io/github/cidy02/kudos/library/ReadingAffinities.kt:140–145`:

```kotlin
if (work.authorIdentitiesJSON.isNotBlank() || ',' in work.author ||
    WorkTags.canonicalAO3WorkURL(work.sourceUrl) == null) return null
return AO3AuthorRoute.fromByline(work.author).username.takeIf {
    accountName.matches(it) && !it.equals("Anonymous", true) && !it.equals("orphan_account", true)
}
```

`fromByline` accepts an unadorned word as the account (`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/author/AO3AuthorModels.kt:41–44`):

```kotlin
val text = byline.trim()
val match = pseudByline.find(text) ?: return AO3AuthorRoute(text)
return AO3AuthorRoute(match.groupValues[2], match.groupValues[1])
```

The blurb author is link **text**, not the account path (`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/search/AO3SearchParser.kt:71–72`):

```kotlin
val authorLinks = element.select("h4.heading a[rel=author]")
val authors = authorLinks.normalizedTexts()
```

**Reader consequence:** an older saved AO3 work can have `author = "BlueBird"` and no recorded identities, from a pseud link belonging to `/users/ActualWriter/pseuds/BlueBird`. If a different account is named BlueBird, the fallback requests **that person's** works, displays their newest work under the saved writer's row, and opens the wrong profile. A valid AO3 source URL proves the work's origin, not its creator's username. The current link-derived JSON recording looked right; guessing missing identity from old words does not. **Confidence: high for this input; no personal library was inspected.** Leave the identity unresolved until an already-authorized page supplies its link. Do not repair it by probing possible accounts.

### F6 — P2: stale fallback is promoted to a successful newest-work check

**Evidence:** `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3PageCache.kt:90–94`:

```kotlin
val copy = value(key, stale = true) ?: return failure
val cached = parsed(copy, true)
if (cached is AO3Result.Failure) remove(key)
return cached
```

That result carries `isStale = true` (`AO3PageCache.kt:86`), but `android/app/src/main/java/io/github/cidy02/kudos/library/AuthorNewestWorkStore.kt:52–53` discards it:

```kotlin
return when (result) {
    is AO3Result.Success -> true.also { store(result.value.works.firstOrNull(), username, scope) }
```

**Reader consequence:** after the 30-minute newest cache expires, an outage can make `loadWorks` fall back to older HTML (up to the shared cache's 24-hour limit). The store stamps that as a fresh answer, continues requesting later authors despite the unresolved network response, and can enable “With new work” using stale answers. A cached empty page or an already-read old work can hide a newer post while the UI presents the check as complete. This breaks the documented stop-on-unresolved rule. **Confidence: high.** Preserve stale status, stop the round, and keep the filter unavailable; an old row may be displayed explicitly as an old copy.

## 4. 3ch — writer's own totals (`824dd439`)

**Looked right; no finding.** The ownership guard is genuinely in the repository, not merely the screen. `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/author/AO3AuthorRepository.kt:74–78`:

```kotlin
val own = route.pseud == null &&
    authenticatedClient?.username()?.equals(route.username.trim(), ignoreCase = true) == true
val url = AO3AuthorUrls.userStatsUrl(route.username)?.takeIf { own } ?: return null
return cached(url, AO3PageCache.Kind.Stats, bypassCache, parser::parseUserStats)
```

A call for another username, a pseud, or a signed-out client returns without fetching. The screen waits for the header and Works list, uses `statsAsked` once per route/session opening, and explicitly rechecks on refresh and confirmed own-work writes (`android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:340–356,589–598`). This is one logical `/users/<name>/stats` read, with shared cache/GET retry behavior, not a stats crawl. Failure does not delete data. The existing `OwnStatsTest` exercises the repository boundary; it was read, not run.

## 5. 3df — comments open newest (`1c6bd366`)

**What looked right.** `read(null, ...)` obtains page 1's count and requests the last page only when the count exceeds one (`android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsViewModel.kt:298–308`). A real one-page result takes one logical read. Work/chapter targets are part of the per-screen memory key (`:151–160`), and chapter page URLs include the chapter id (`network/ao3/comments/AO3CommentModels.kt:40–54`). Switching order goes to that order's start; a focused thread remains that thread (`CommentsViewModel.kt:833–839`).

After a newly posted top-level comment, `reloadStart` clears the memory pages before discovering the newest end again (`CommentsViewModel.kt:722–724,802`); it therefore handles a new comment creating an additional page. Replies/edits reload the page on screen rather than unconditionally jumping to page 1 (`:712–715,802`). The explicit Inbox Chapter Comments route intentionally keeps its focused thread; it is not an ordinary newest-page opening. Those choices looked right.

### F7 — P2: an unrecognized 200 page is still reported as “No Comments Yet”

**Evidence:** `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/comments/AO3CommentParser.kt:104–108`:

```kotlin
val root = document.selectFirst(
    "#comments_placeholder ol.thread, #main > ol.thread, main > ol.thread, ol.thread"
) ?: return emptyList()
return parseThread(root, depth = 0, parentId = null)
```

The parser constructs a thread even without that landmark (`AO3CommentParser.kt:31–39`); the repository wraps it as success (`network/ao3/comments/AO3CommentRepository.kt:241–245`). The screen then says (`android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsScreen.kt:597–601`):

```kotlin
if (thread.comments.isEmpty()) {
    item {
        ContentUnavailableView(
            title = "No Comments Yet",
            description = "You can be the first to comment on this work.",
```

**Reader consequence:** a 200 interstitial or changed page that is neither recognized login nor recognized overload, and contains no comments landmark, becomes an empty page 1/1. The new newest-page discovery accepts it and never finds the real last page. The broad `ol.thread` fallback can also accept an unrelated thread. This is an inherited parser defect directly under 3df, contrary to the policy's authoritative-landmark rule. **Confidence: high for the parser result; no live markup failure was reproduced.** Distinguish a recognized empty comments container from a missing/unrecognized container and report the latter as a read error.

## 6. 3cf — challenge settings form and radio refusal (`7ea341fd`)

**What looked right.** Save is not an HTTP patch containing only changed keys: it submits the challenge's complete successful controls with the reader's edits applied, as a browser does. Untouched whitespace, hidden checkbox twins, repeated names, disabled controls, the selected submitter and fresh token are handled by `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/account/AO3ChallengeSettingsForm.kt:35–74` and `network/ao3/writing/AO3WorkForm.kt:83–89`. Radio edits are now explicitly refused (`AO3ChallengeSettingsForm.kt:42`): `if (control.type == "radio") return this`. No screen row edits a radio. That guard looked right.

The state sets `saving` before suspension, validates, and asks before an anonymous/unrevealed true-to-false transition (`android/app/src/main/java/io/github/cidy02/kudos/account/AO3ChallengeSettingsEditState.kt:70–92`). One Save makes **one challenge POST**, then **one collection POST only if a collection switch changed and the first write succeeded** (`:98–119`). This follows iOS `Features/Challenges/ChallengeSettingsEditView.swift:774–845`. Two distinct endpoints are not duplicate submission. No automatic application retry was found; F1 still applies underneath.

### F8 — P1: saving a collection switch can undo a Basics edit the reader just saved

**Evidence:** Basics opens the separate collection form (`android/app/src/main/java/io/github/cidy02/kudos/account/AO3ChallengeSettingsEditScreen.kt:159–160`):

```kotlin
SubjectFormRow(label, value = value, valueMaxLines = Int.MAX_VALUE, showsDisclosure = true, onClick = onOpenCollection)
```

The settings ViewModel retains its original data, even on another successful load (`android/app/src/main/java/io/github/cidy02/kudos/account/AO3ChallengeSettingsEditState.kt:50`):

```kotlin
is AO3Result.Success -> state.value.copy(data = state.value.data ?: result.value)
```

Its second write uses that captured collection (`AO3ChallengeSettingsEditState.kt:103,108–109`):

```kotlin
val collection = data.collection
...
if (changed && collection != null && ownsSession()) {
    when (val saved = writes.saveChallengeSettings(collection, generation, collectionSwitches = true)) {
```

The fresh GET refreshes the token only; the POST uses the old controls (`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writes/AO3WriteRepository.kt:503–509`):

```kotlin
val token = parser.parseAuthenticityToken(html, metaOnly = true)
...
val posted = checked.copy(token = token)
...
client.postAuthenticatedInSession(posted.actionUrl, posted.parameters(), writeHeaders(token, referer), expectedGeneration)
```

**Reader consequence:** open challenge settings, follow Name/Tagline/Introduction/FAQ to Basics, change and save one there, then return and save a moderation switch. The second POST resends the earlier title/description/profile controls as well as the switch, overwriting the Basics change with old values. The collection form's change notification only invalidates the collections list (`android/app/src/main/java/io/github/cidy02/kudos/app/AppNavHost.kt:692–699,1356–1364`), not this retained edit model. **Confidence: high from the retained model and payload; not exercised against AO3.** Reconcile collection controls after the child edit, or apply only the four switch edits to a freshly parsed collection form when preparing the second write. Preserve unsaved challenge edits while doing so.

## 7. 3cg — one captured comments context

**The target capture itself looked right.** `Composer` holds target, viewer, reply id and edit comment (`android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsViewModel.kt:173–175`). `submitComment` takes `sent.target`, `sent.edit` and `sent.replyTo`, then calls the repository with those values (`:748–772`). A later screen target does not replace them. A draft lookup checks both composer identity and viewer before opening (`:603–616,668–678`); an edit uses no new-comment draft slot (`:635–637`); success closes only its own composer (`:793–800`). `setTarget` cancels an unopened composer but preserves an already open one (`:854–860`). No route-change retargeting of a captured reply/edit was found. The screen also keys its ViewModel by work id (`comments/CommentsScreen.kt:124–128`).

Three surrounding failures remain; they are not evidence that the captured target itself is wrong.

### F9 — P1: text typed during a send is discarded when the older text succeeds

**Evidence:** the composer editor remains editable during submission (`android/app/src/main/java/io/github/cidy02/kudos/comments/CommentComposerSheet.kt:245–257`):

```kotlin
BasicTextField(
    value = textFieldValue,
    onValueChange = send,
```

That call has no `enabled = !submitting` or `readOnly = submitting`. Submission captures the text once (`android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsViewModel.kt:751–753`):

```kotlin
val sent = composer ?: return
val target = sent.target
val content = _draft.value
```

On success it clears the draft slot and, for the same composer, clears the current field without checking whether its content changed (`CommentsViewModel.kt:783–795`):

```kotlin
if (edit == null) draftStore?.clearDraft(
    workId = target.workId,
    chapterId = (target as? AO3CommentTarget.Chapter)?.chapterId,
    parentId = replyTo,
    username = sent.viewer.username
)
...
if (composer === sent) {
    composer = null
    _draft.value = ""
```

**Reader consequence:** send “Thank you”, then keep typing while AO3 is slow. Only “Thank you” was sent; the added text is erased from both editor and saved draft when that request succeeds. A newer composer using the **same draft slot** has a related disk-loss window: identity protects its visible field, but the old request still deletes its newer stored draft. **Confidence: high.** Freeze editing/dismissal for the send, or clear only the exact submitted draft version and preserve later text.

### F10 — P1: the captured viewer is not enforced across comment form preparation and POST

**Evidence:** preparation suspends to parse after the form GET (`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/comments/AO3CommentRepository.kt:106–112`):

```kotlin
val page = when (val result = authenticatedClient.getAuthenticated(csrfSourceUrl)) {
    is AO3Result.Failure -> return result
    is AO3Result.Success -> result.value
}
val form = withContext(Dispatchers.Default) {
    parser.parseCommentForm(page.body, page.url, target)
}
```

It later calls `authenticatedClient.postAuthenticated(...)` without the preparing generation (`AO3CommentRepository.kt:145–151`). That client captures whichever session exists **at the POST call** (`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writes/AO3AuthenticatedClient.kt:95–97`):

```kotlin
val generation = sessionGeneration()
return try {
    postAuthenticatedInSession(url, formFields, headers, generation)
```

The model checks its captured reader only after the repository returns (`android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsViewModel.kt:769–777`). `syncViewer` retires the composer, not the submitted coroutine (`:234–255`).

**Reader consequence:** change accounts or relogin after the form GET returns but while parsing/preference lookup is suspended. The prepared comment/reply can be dispatched with the next session's cookie and the previous session's token/pseud, although that next session did not approve it. AO3 may reject the mismatched token; the forbidden dispatch still occurs. This is narrower than the already-correct check for a session change while waiting in the POST queue. **Confidence: high for dispatch; acceptance as another account is not asserted.** Carry the opening generation into the repository, recheck after preparation, and use `postAuthenticatedInSession` with that same generation. iOS explicitly rechecks between form GET and request construction (`Services/AO3CommentActions.swift:83–98`).

### F11 — P1: edits POST to the form-read address instead of the update address

**Evidence:** the parser retains the Edit link verbatim (`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/comments/AO3CommentParser.kt:279–281`):

```kotlin
val href = link.attr("href").takeIf { it.isNotBlank() } ?: continue
when {
    label == "edit" -> editPath = href
```

The repository resolves that path (`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/comments/AO3CommentRepository.kt:184`) and uses it for both GET and POST (`:186,192–197`):

```kotlin
val page = when (val result = authenticatedClient.getAuthenticated(url)) {
...
val fields = listOf(
    "_method" to "put",
    "authenticity_token" to token,
    "comment[comment_content]" to text
)
return when (val response = authenticatedClient.postAuthenticated(url, fields, mapOf("X-CSRF-Token" to token, "Referer" to url))) {
```

**Reader consequence:** an Edit link `/comments/9/edit` causes an update attempt at **`PUT /comments/9/edit`**, rather than `/comments/9`. The edit fails instead of updating the reader's comment; capturing the right comment does not fix the endpoint. The existing repository test supplies `/comments/9/edit` but only checks a fake maintenance verdict (`android/app/src/test/java/io/github/cidy02/kudos/network/ao3/comments/AO3CommentRepositoryTest.kt:109`). iOS reads `commentEditURL` and writes `commentThreadURL` separately (`Services/AO3CommentActions.swift:88–98`). **Confidence: high from the request construction and iOS route contract; no live write attempted.** Use the captured comment id's update endpoint, or the validated edit form's own action, keeping `/edit` as the token source/referer only.

## Fix first

- **F1:** prevent transport-level POST replay and require pacing/session checks for every dispatched request.
- **F8:** stop a collection-switch save from overwriting a Basics change already saved.
- **F9:** preserve text/drafts changed while an earlier comment send is pending.
- **F10–F11:** fence comment preparation to its opening session and send edits to the update endpoint.
- **F4–F5:** stop Authors reads in the background and stop guessing accounts from pseud words.
- **F6, F3, F2, F7:** preserve stale/failure truth, clear actual history state, reconcile subscription buttons, and reject unrecognized comments pages.
