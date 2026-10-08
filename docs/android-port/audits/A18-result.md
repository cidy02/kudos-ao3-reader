# Audit A18 result

Read-only. Lines are the current source in this worktree. iOS paths are under `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`. `audits/A17-result.md` is not in the tree; AO3 writes, repeated reads, local Clear/Delete/Reset, and the session after sign-out were treated as A17's scope and were not re-filed. A1, A3, and A5 findings were not re-filed. Wording rows in `audits/A14-result.md` were not re-filed. Nothing below is recorded in `docs/android-port/DECISIONS.md`.

| id | severity | file:line | statement |
| --- | --- | --- | --- |
| A18-1 | P1 | `comments/CommentsViewModel.kt:273` | Dismissing or typing an edit replaces the unsent new-comment draft with that comment's body. |
| A18-2 | P1 | `app/AppNavHost.kt:981` | A signed-in reader's comment drafts are stored and loaded under `guest`, so another account sees them and can erase them. |
| A18-3 | P2 | `app/AppNavHost.kt:972` | Opening a comment from the inbox drops the comment id, so the screen loads page 1 of the work. |
| A18-4 | P2 | `search/SearchScreen.kt:852` | With Blur on, "In Your Library" shows a mature saved work's title and summary in the clear. |
| A18-5 | P2 | `ui/components/SensitiveWorkRow.kt:151` | A row that is already blurred still exposes its title to accessibility and a fandom tap leaves the row for Search. |
| A18-6 | P2 | `network/ao3/DemoNetwork.kt:289` | While the demo is active, OkHttp still performs real requests to hosts other than AO3, including the launch-time GitHub update check. |

## A18-1 Edit overwrites the new-comment draft

`android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsViewModel.kt:265-286`

```kotlin
fun closeComposer() {
    saveDraft()
    _composerPresented.value = false
    _replyTarget.value = null
    _editTarget.value = null
    _composerParent.value = null
}

fun saveDraft() {
    val target = _currentTarget.value ?: return
    val reply = _replyTarget.value
    val content = _draft.value
    viewModelScope.launch {
        draftStore?.saveDraft(
            content = content,
            workId = target.workId,
            chapterId = (target as? AO3CommentTarget.Chapter)?.chapterId,
            parentId = reply?.commentId,
            username = currentUsername
        )
    }
}
```

`CommentsViewModel.kt:288-291` and `:323-329`

```kotlin
fun updateDraft(content: String) {
    _draft.value = content
    saveDraft()
}

fun startEdit(comment: AO3Comment) {
    _editTarget.value = comment
    _replyTarget.value = null
    _composerParent.value = null
    _draft.value = comment.body
    ...
}
```

The sheet's dismiss is that function (`comments/CommentsScreen.kt:316`, `onDismiss = viewModel::closeComposer`). Each keystroke calls `updateDraft` (`comments/CommentComposerSheet.kt:226` via `CommentsScreen.kt:311`). `startEdit` clears the reply target, so `parentId` is null: the new-comment slot. `closeComposer` does not clear `_draft`, and the new-comment branch of `openComposer` (`CommentsViewModel.kt:244-258`) does not replace `_draft` before the sheet is shown.

iOS, `Features/Comments/CommentsModel.swift:1044-1049`:

```swift
func saveDraft() {
    // Edits don't use the draft store — a stale edit draft could silently
    // overwrite a newer comment revision.
    guard let composerContext, composerEditTarget == nil else { return }
    // A's draft must never appear when B opens the same work/comment target.
    drafts.save(composerText, for: composerContext, identity: authContext.identity)
}
```

iOS's Cancel and the sheet binding both call `saveDraft()` (`Features/Comments/CommentsView.swift:880` and `:1299`). The guard is what makes that safe. `closeComposer()` (`CommentsModel.swift:1038-1042`) only clears presentation state. `startEditing` (`:1014-1021`) fills the field from `comment.bodyText` and does not write the draft store.

Failing case. There is a stored new-comment draft "thanks for the chapter" on work 123. Tap Edit on your comment "I loved this". Change nothing and dismiss the sheet. `saveDraft` writes "I loved this" to `draft:123:0:0:…` (`CommentDraftStore.kt:20-21`, parent id 0). Tap New comment. The field shows "I loved this". "thanks for the chapter" is gone. The same replacement happens on the first edit keystroke, before dismiss. The field should keep "thanks for the chapter", and the edit should stay out of the draft store.

Smallest fix. Return at the start of `saveDraft` when `_editTarget.value != null`. When opening a new comment, set `_draft` from that target's stored draft (or to empty) before `_composerPresented` becomes true.

## A18-2 Signed-in drafts are stored as guest

`android/app/src/main/java/io/github/cidy02/kudos/app/AppNavHost.kt:981-987`

```kotlin
val commentsAuthState by container.authRepository.state.collectAsState(
    initial = AO3AuthState.Restoring
)
CommentsScreen(
    ...
    currentUsername = commentsAuthState.usernameOrNull,
```

`auth/AO3AuthRepository.kt:19` is `val state: StateFlow<AO3AuthState>`. `auth/AO3AuthState.kt:12-13` returns a username only for `SignedIn`. The call uses the `Flow.collectAsState(initial)` overload. Android's Compose runtime documents that overload as taking the caller-supplied initial value; the `StateFlow.collectAsState()` overload is the one that uses `StateFlow.value` as the initial value (Compose runtime `collectAsState`, docs current as of 2026-10-07). `produceState` shows `initial` for the composition that starts the collector. The first composition of this destination therefore passes `null` even when the repository is already `SignedIn`.

`comments/CommentsScreen.kt:119-122`

```kotlin
val viewModel: CommentsViewModel = viewModel(
    key = target?.workId?.toString(),
    factory = CommentsViewModel.factory(repository, target, draftStore, currentUsername)
)
```

The key is the work id. `ViewModelProvider` calls the factory only when that key has no stored model, so the later `SignedIn` frame does not rebuild it. `CommentsViewModel` keeps `currentUsername` as a constructor value (`CommentsViewModel.kt:58`) and passes it to every `getDraft` / `saveDraft` (`:146`, `:256`, `:283`, `:308`). The store key is `draft:{work}:{chapter}:{parent}:{username ?: "guest"}` (`network/ao3/comments/CommentDraftStore.kt:20-21`).

iOS keys the same text by account. `Features/Comments/CommentsModel.swift:19-30` uses the known username, or a per-session id when a session exists but the name is not known yet, and the empty identity only when logged out. `Services/CommentSubmission.swift:354-355` is `"\(identity)|w…-c…-p…"`. `startComposer` assigns `drafts.draft(for:identity:)` before the sheet is usable (`CommentsModel.swift:978`). The model comment at `:1048` says account A's draft must never appear for account B.

Failing case. Sign in as Alice. On work 123, open New comment, type "see you at the con", and dismiss. The stored key is `draft:123:0:0:guest`. Sign out, sign in as Bob, open work 123, tap New comment. Bob's field shows "see you at the con". If Bob clears the field and dismisses, `saveDraft` deletes that key (`CommentDraftStore.kt:32-33`) and Alice's text is gone. Bob should see an empty composer, and Alice's draft should still be under Alice's name.

Smallest fix. Read the username from `authRepository.state.value` at each save and load (a `StateFlow`, not a constructor snapshot). Use `state.collectAsState()` with no `initial` at the destination so the first frame is the current value. Keep the `viewModel` key from depending on a username captured once.

The new-comment path also applies a stored draft after the sheet is already up: `openComposer` sets `_composerPresented` true and then assigns `_draft` whenever `getDraft` returns non-null (`CommentsViewModel.kt:248-258`). `load` does the same on success (`:142-148`). The reply path refuses that assignment unless the field is still empty and the reply id still matches (`:310`). `CommentComposerSheet.kt:74-77` copies the new text into the field. A keystroke typed before the DataStore read returns is replaced. iOS assigns the draft synchronously in `startComposer` before the sheet is usable. The same "do not assign over text the reader already typed" guard the reply path has belongs on these two assignments.

## A18-3 Inbox open drops the focused comment id

`android/app/src/main/java/io/github/cidy02/kudos/app/Routes.kt:94-112`

```kotlin
private const val ARG_COMMENT_FOCUSED_ID = "focusedCommentId"
...
const val Comments =
    "comments/{$ARG_COMMENT_WORK_ID}?focused={$ARG_COMMENT_FOCUSED_ID}" +
        "&chapter={$ARG_COMMENT_CHAPTER_POSITION}&compose={compose}"

fun comments(...): String {
    val query = buildList {
        focusedCommentId?.let { add("focused=$it") }
        ...
    }
}
```

The URL query name is `focused`. The placeholder name is `focusedCommentId`.

`app/AppNavHost.kt:968-978`

```kotlin
sharedComposable(
    Routes.Comments,
    arguments = listOf(
        Routes.navArgOf("commentWorkId"),
        navArgument("focused") { type = NavType.StringType; nullable = true },
        navArgument("chapterPosition") { type = NavType.StringType; nullable = true },
        navArgument("compose") { type = NavType.BoolType; defaultValue = false }
    )
) { backStackEntry ->
    ...
    val focusedId = Routes.routeArg(backStackEntry, "focused")?.toLongOrNull()
```

`Routes.routeArg` is `entry.arguments?.getString(name)` (`Routes.kt:206-207`).

Checked in `androidx.navigation:navigation-common:2.9.5` (the version in `android/gradle/libs.versions.toml`), class `androidx.navigation.NavDeepLink`. `parseQuery` puts each query parameter in a map keyed by the parameter name (`focused`) and records the name inside the braces (`focusedCommentId`) with `ParamQuery.addArgumentName`. `getMatchingQueryArguments` reads `Uri.getQueryParameters` with that map key. `parseInputParams` walks `ParamQuery.getArguments()` and calls `parseArgument(bundle, braceName, value, arguments[braceName])`. `parseArgument` writes the bundle under that brace name (`NavType.parseAndPut`, or `putString` when no `NavArgument` is registered for it). `NavArgumentKt.missingRequiredArguments` only treats a registered argument as required when it is not nullable and has no default, so `navArgument("focused") { nullable = true }` lets the graph build and never receives the id. The id is stored under `focusedCommentId`. `getString("focused")` is null.

`chapterPosition` is registered and read under the brace name, so the reader's chapter argument is unaffected. `compose` matches on both sides.

`account/AccountInboxPane.kt:314-315` navigates with the inbox comment id:

```kotlin
onOpen = {
    item.workId?.let { onOpenWorkComments(it, item.id) }
},
```

`AppNavHost.kt:509-510` and `:521-522` call `Routes.comments(workId, focusedId)`. `comments/CommentsScreen.kt:129-132` calls `viewModel.load(focusedId = …)` only when the long is non-null. The ViewModel's `init` has already called `load(1)` with no id (`CommentsViewModel.kt:122-123`). `AO3CommentRepository.kt:34-37` would request `AO3CommentUrls.commentThreadUrl(focusedCommentId)` (`/comments/{id}`) when the id is present, and the work page otherwise.

iOS passes the id through. `Features/Account/AccountView.swift:1036-1043` pushes `AccountInboxThreadDestination(…, commentID: item.id, …)`, and `:215-221` opens `CommentsView(…, initialCommentID: destination.commentID, …)`. The standalone thread URL is `https://archiveofourown.org/comments/{commentID}` (`Services/AO3Client+Comments.swift:47-48`), which is what Android's repository uses when it actually receives the id.

Failing case. An inbox row whose comment is not on page 1 of the work. Tap the row. The comments screen requests the work's first page and shows those comments. It should request `https://archiveofourown.org/comments/{that id}` and show that comment's thread. Navigating with no `focused` query still matches, so this is the wrong thread, not a crash.

`app/src/test/java/io/github/cidy02/kudos/app/RoutesNavigationTest.kt:63-68` registers `navArgument("focusedCommentId")`, which is the name production does not use. `messageCreatorOpensNativeCommentsWithComposerRequested` (`:137-142`) navigates `Routes.comments(123, composes = true)` and never supplies or reads a focused id. That test stays green if production continues to read `"focused"`.

Smallest fix. Register and read `focusedCommentId`. Leave the URL query name as `focused`.

## A18-4 Search shows blurred library works in the clear

`android/app/src/main/java/io/github/cidy02/kudos/search/SearchScreen.kt:517-519`

```kotlin
// Search does not read a setting of its own; mature reveal lives on Library.
if (settingsRepository == null) Unit
```

`search/SearchLocalMatches.kt:39` keeps every title match, capped at 20. Nothing calls `LibraryPrivacy.visibility`. `SearchScreen.kt:850-860` draws each hit with `SensitiveWorkRow` and does not pass `obscured` (the parameter defaults to false at `ui/components/SensitiveWorkRow.kt:115`).

Default privacy is hide-mature on and mode Obscure (`core/model/SettingsModels.kt:85-86`). `library/LibraryPrivacy.kt:15-31` returns `Obscured` for an adult work in that mode until the session reveal.

iOS local hits go through the row that applies that gate itself. `Features/Search/SearchLocalResultsList.swift:40-50` uses `SensitiveWorkRow`. `Features/Privacy/MatureContent.swift:121-123`:

```swift
private var blurred: Bool {
    hideMature && work.isAdult && mode == .obscure && !gate.isRevealed(work)
}
```

The blurred branch blurs the row and, when not selecting, speaks "Hidden mature work. Activate to reveal." (`MatureContent.swift:191-198`).

This is Blur mode. In Hide mode both platforms still list the matching library work: iOS `SearchView.localWorks` (`SearchView.swift:532-534`) only drops deleted objects, and the blur predicate is obscure-mode only. Remote AO3 results are unblurred on both (Android `SearchScreen.kt:1040`; iOS uses `AO3WorkRow`). `DECISIONS.md` (2026-10-03) says mature privacy covers the reader's own library and not AO3's listings. A library search hit is the reader's own library.

Failing case. Hide mature content is on, mode is Blur, and the session has not revealed the work. Type a query that matches a saved Mature or Explicit work. "In Your Library" shows its title and summary in the clear, and a tap opens it. iOS blurs that row, and a tap reveals it.

Smallest fix. When drawing `matches.works`, pass `obscured` from `LibraryPrivacy.visibility` for that saved work, and wire `onReveal` the way `library/LibraryScreen.kt:984-995` already does.

## A18-5 A blurred SensitiveWorkRow still gives away the work

`android/app/src/main/java/io/github/cidy02/kudos/ui/components/SensitiveWorkRow.kt:151-161` and `:177-181` and `:228-242`

```kotlin
.semantics { contentDescription = "$title, by ${author.ifBlank { "Anonymous" }}" }
.combinedClickable(
    onClick = {
        when {
            selecting -> onSelect?.invoke()
            obscured -> onReveal?.invoke()
            else -> onClick()
        }
    },
    ...
)
...
Column(
    modifier = Modifier
        .fillMaxWidth()
        .run { if (obscured) blur(16.dp) else this }
        ...
) {
    ...
    modifier = Modifier.clickable {
        tagSearch(SearchSubjectField.FANDOM, fandom)
    }
```

The content description is the title and author whether or not `obscured` is true. The fandom `clickable` is a child of the card, so a tap on that line runs `tagSearch` and does not run the card's `onReveal`. `app/MainScaffold.kt:264-270` provides `LocalTagSearch`, which starts a Search for that fandom. The "Tap to reveal" overlay (`SensitiveWorkRow.kt:317-335`) has no click handler. Callers that do pass `obscured = true` include `library/LibraryScreen.kt:992`, `library/QueuePageScreen.kt:339`, `library/CollectionDetailScreen.kt:717`, and `account/AccountWorksListScreen.kt:1493`.

The ledger row already uses the hidden label (`ui/subject/WorkLibraryComponents.kt:158-159` and `:193-194`: `"Hidden mature work. Activate to reveal."` when obscured). iOS's non-selecting blurred branch ignores children and uses that same label (`Features/Privacy/MatureContent.swift:191-198`). iOS's fandom line inside `WorkRow` is `Text`, not a button (`Features/Library/WorkRow.swift:230-238`), and the blurred card is one reveal button. iOS does keep an expand control outside the blur on purpose (`MatureContent.swift:163-169`); the Android expand control matching that is not this finding.

Failing case. Hide mature content is on, mode is Blur, and a Mature saved work is on the Library list that uses `SensitiveWorkRow`. The pixels are blurred. Accessibility focus on the card is given `"$title, by $author"`. Tap the fandom line. Search opens for that fandom. The card's reveal action does not run. The spoken label should be "Hidden mature work. Activate to reveal.", and a tap on the fandom line should reveal, as a tap on the rest of the card does.

Smallest fix. When `obscured` is true, set the content description to the hidden label with `clearAndSetSemantics`, and do not attach the fandom `clickable` (or the tag-chip clicks) on that row. `WorkLedgerRow`'s label string is the one to copy.

## A18-6 Demo mode still calls the network for non-AO3 hosts

`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/DemoNetwork.kt:286-289`

```kotlin
override fun intercept(chain: Interceptor.Chain): Response {
    if (!isActive()) return chain.proceed(chain.request())
    val url = chain.request().url
    if (!DemoNetworkRoutes.isAo3Host(url.host)) return chain.proceed(chain.request())
```

`installDemoNetworkBlock` adds that interceptor (`DemoNetwork.kt:639-640`). `network/github/GitHubReleaseClient.kt:22-34` builds its client with it and requests `https://api.github.com/repos/cidy02/kudos-ao3-reader/releases`. `KudosApplication.kt:93-97` launches `checkIfDue()` on startup with no demo gate. `AppUpdateRepository.kt:28-32` calls `checkNow(autoDownload = true)`, which downloads a newer APK (`:54-55`). The metadata refresh next to it does wait: `KudosApplication.kt:82-84` calls `DemoNetwork.awaitLaunchDecision()` and returns when `DemoNetwork.isActive` is true.

`Application.onCreate` runs before `MainActivity.onCreate` calls `DemoNetwork.activate` (`MainActivity.kt:23-29`). `awaitLaunchDecision` exists so a startup request cannot beat that call (`DemoNetwork.kt:96-98`). The update check does not use it, so it can also run while `isActive` is still false and the interceptor proceeds every host. After `activate`, line 289 still proceeds for GitHub.

The in-app browser path is not this hole. While the demo is active, `web/AO3WebViewFallbackScreen.kt:149-157` returns a `WebResourceResponse` for every request, AO3 fixture or a local 404. That matches `DECISIONS.md` (2026-10-05) for the browser. The same file's older rule (2026-10-03) is "the demo must never reach AO3". The brief's boundary for this audit is that nothing in demo mode may reach the network. No decision records an exception for GitHub or other non-AO3 OkHttp calls. Coil (`KudosApplication.kt:130-131`), `update/AppUpdateInstaller.kt:36-38`, and `reader/speech/TTSDownloadWorker.kt:72` use the same interceptor.

Failing case. Launch a debug build with the demo extra. The update check is due (no check in the last 24 hours, or the stored timestamp is absent). The app requests `https://api.github.com/repos/cidy02/kudos-ao3-reader/releases`. If a newer APK is listed, it downloads that APK. Both requests should fail locally, the way an AO3 request does while the demo is active, and the update check should wait on `awaitLaunchDecision` and skip when the launch is the demo.

Smallest fix. In `intercept`, when the demo is active and the host is not AO3, return a local error response instead of `chain.proceed`. Gate `checkIfDue` the same way the metadata refresh is gated.

## Unconfirmed

- `auth/AO3WebLoginScreen.kt:95-100` returns false from `shouldOverrideUrlLoading` whenever `request.url.host` is an AO3 domain, with no scheme check. `intent://archiveofourown.org/...` has that host. `javascript:` has an empty host and is refused. Whether a WebView that is told not to override an `intent:` URL then starts an activity was not confirmed from Android's WebView contract. `auth/AO3NativeLoginScreen.kt` has no `shouldOverrideUrlLoading`; the page it loads is the fixed login URL, and no off-site redirect from that URL was traced.
- `web/AO3WebViewFallbackScreen.kt:72-76` calls `openExternal` for any initial URL that is not allowed in-app, and `Block` includes `javascript:` and `intent:`. The navigation override at `:160-171` refuses those schemes. Callers found for `Routes.webFallback` pass app-built AO3 URLs. A caller that forwarded a raw href would confirm this.
- `comments/CommentComposerSheet.kt:74-77` keeps the old `TextFieldValue` selection when it copies a shorter `draft` in. A crash from a selection past the new text was not checked against Compose BOM 2026.06.00. The text replacement itself is the assignment in A18-2.
- `home/HomeResumeHero.kt:74-76` and `ui/subject/SubjectWorkCoverCard.kt:136-160` blur the title `Text` and do not call `clearAndSetSemantics`. Whether TalkBack still reads that title was not confirmed. `WorkLedgerRow` sets the hidden label; whether merged descendant text is still spoken was not confirmed.
- `browse/FandomListChrome.kt` calls `family.members.first()` only in branches already limited by `memberCount`. An empty family constructed some other way was not traced. `app/DemoLibrary.kt:581` uses `entries.remove("mimetype")!!` inside the demo EPUB builder; the placeholder map was not read.
- `works/WorkTagsRefreshWorker` was not read. A WorkManager process does not share the in-memory `DemoNetwork.isActive` flag. `KudosApplication` already says a WorkManager-only process is not the demo and continues after the launch wait.

## What was not read

- `works/` file import, rebuild from the original, the availability sweep, the download-date confirmation, and Work Detail's sheets past the download watcher and the series-preservation `preview` check. Those two are guarded (`canUsePreviewForPreservation` before `preview!!`; `getHeldCopies()` requires `freedAt IS NOT NULL` before `freedAt!!`).
- `browse/` paging and the fandom-index cache, past the `memberCount` check above.
- `author/` tab paging and whether a late `loadHeader` / `loadTab` is cancelled. `headerError!!` and `tabError!!` sit in `!= null` branches.
- `comments/` thread geometry, line by line. A search of `CommentThreadGeometry.kt` found no `!!`, `first()`, or `single()`.
- `home/` menus and the rest of the dashboard, past the resume hero, the cover card, and the section-list privacy wiring.
- `settings/` reset beside iOS, `onboarding/`, `support/` past `ShakeDetector` (its `first()` is after `isNotEmpty`), and `update/` past the launch check.
- The shell's top row and tab bar, and release-build reachability of debug extras past `MainActivity.publishDebugRoute`, which stores the extra only when `BuildConfig.DEBUG`.
- `auth/` storage and what remains on screen after sign-out (left to A17).
- `DECISIONS.md` end to end. It was searched for mature content, drafts, the demo, and the WebView. `audits/A14-result.md` was searched so its wording rows were not filed again.
- Tests other than `RoutesNavigationTest` and the note that `CommentsViewModelDraftTest` does not navigate a focused comment id.

## Triage (Claude, 2026-10-08)

All six read against the code; all real, all fixed.

- **A18-1, A18-2 fixed** (`8c8c948b`): an edit stays out of the draft store; a new comment
  opens with its own draft, set before the sheet can be typed in; the signed-in name is read
  at each save and load. Tests in `CommentsViewModelDraftTest`.
- **A18-3 fixed**: the destination registers and reads `Routes.ARG_COMMENT_FOCUSED_ID`, the
  name the route's braces use. No test drives the real graph; the shared constant is the
  guard. Not seen on the emulator yet.
- **A18-4 fixed**: Search's "In Your Library" rows are blurred by the Library's rule, and a
  tap reveals. In **Hide** mode a matching work is still listed in the clear, as on iOS:
  owner question 20.
- **A18-5 fixed**: a blurred row is one button, labelled "Hidden mature work. Activate to
  reveal."; its title, author, fandoms and tags are not in what a screen reader is given,
  and a tap on a fandom or tag reveals (or selects, while selecting) and never opens a
  search. Tests in `SensitiveWorkRowPrivacyTest`.
- **A18-6 fixed in part**: the update check waits for the launch decision and is skipped in
  the demo. Other hosts (cover and avatar images, a voice download) still pass through the
  demo's interceptor: the demo's rule is that it never reaches AO3 (DECISIONS 2026-10-03),
  and the emulators are in airplane mode.
- Unconfirmed items: not looked at yet.
