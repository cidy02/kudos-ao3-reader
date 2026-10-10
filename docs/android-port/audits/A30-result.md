| ID | Severity | File and line | Finding |
|---|---|---|---|
| A30-1 | P1 | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsViewModel.kt:375` (84778078) | A pending new-comment draft lookup can overwrite a reply composer and send that text as a reply. |
| A30-2 | P1 | `kudos-ao3-reader/Services/AO3AuthService.swift:990` (iOS) | Restore moves persistent drafts by a process-local generation number, which can belong to a different account on another launch. |
| A30-3 | P1 | `kudos-ao3-reader/Services/KudosBackup.swift:3824` (iOS) | Replace dedupes against local annotations absent from the snapshot, deletes the snapshot's mark, then hides the local winner. |
| A30-4 | P1 | `kudos-ao3-reader/Services/KudosBackup.swift:3863` (iOS) | Merge skips a newer same-ID revival, then hard-deletes the older local row using the tombstone. |
| A30-5 | P2 | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsViewModel.kt:311` (84778078) | Choosing All comments during Chapter Comments can do nothing; the pending result changes the scope back to By Chapter. |
| A30-6 | P2 | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsViewModel.kt:243` (84778078) | The chapter pill uses the stale Inbox position instead of the position in the served comment byline. |
| A30-7 | P2 | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsViewModel.kt:223` (84778078) | A focused reply's chapter overrides the root's chapter, contrary to iOS's root-first resolution. |
| A30-8 | P2 | `kudos-ao3-reader/Features/Search/SearchView.swift:265` (iOS) | Unapplied filter edits still survive dismissal during the first search because there is no loadedFilters snapshot yet. |
| A30-9 | P2 | `android/app/src/main/java/io/github/cidy02/kudos/app/DemoLibrary.kt:304` | Privacy demo seeding poisons the normal TV Shows catalog with one fixture fandom for seven days. |
| A30-10 | P2 | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsViewModel.kt:266` | The duplicate-key fix does not remove a shared root; the demo rewrite can also create repeated IDs inside one returned tree. |
| A30-11 | P2 | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsViewModel.kt:297` | A loaded comments picker bypasses the new session-scoped repository and retains an anonymous index after sign-in/restore. |
| A30-12 | P2 | `android/app/src/main/java/io/github/cidy02/kudos/ui/subject/SubjectForm.kt:159` | Any trailing content is treated as a speaking field, so the Fandoms count row loses its required announcement. |

## Scope and evidence

Static source audit; no build, test execution, simulator, sign-in, or AO3 contact. Android items 1–4 were first read at `21a85056`; the worktree subsequently advanced to `3f34360f` on `android/agent-gemini-a30`. Where a quote is explicitly marked `84778078`, its line numbers identify the original audited comments implementation, before the later insertion into `present`. iOS was initially read at `/Users/cidy02/kudos-ios-polish`, HEAD `53c552ce029849e65a3327247032f2fd96e18bd9`, the requested item-4 commit. During the audit that checkout advanced to `cef4edd3b253c527aee1bf26c4aeb1b1af95655e`. The intervening diff leaves the quoted finding code and relevant reference behavior unchanged; the cited AccountComponents lines also precede its later layout changes. All `kudos-ao3-reader/...` references refer to that read-only iOS worktree. The four intervening iOS commits were checked for changes affecting this report, not independently audited. Findings are source-derived counterexamples, not claims of observed runtime reproduction.

Items 1–9 are reviewed below, including the added production diffs at `3f34360f`. Only this report is written. Earlier A28/A27 findings and acknowledged decisions are not new findings here. Item 7 supplies a concrete restore/picker path for the previously unconfirmed auth-context concern; repository-only cache tests do not cover that path.

## A30-1 — The other asynchronous draft lookup still replaces the wrong composer

`android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsViewModel.kt:375` at `84778078`:

```kotlin
viewModelScope.launch {
    _draft.value = if (target == null) "" else draftStore?.getDraft(
        workId = target.workId,
        chapterId = (target as? AO3CommentTarget.Chapter)?.chapterId,
        parentId = null,
        username = currentUsername()
    ).orEmpty()
    _composerPresented.value = true
}
```

There is no continuation guard. `startReply` sets `_replyTarget`, clears `_draft`, and presents the reply immediately (`:419–437`). `submitComment` captures the current draft and reply and sends `repository.submitComment(target, content, reply?.commentId)` (`:490–511`). The new guard in `present` does not protect this separate job.

**iOS reference:** `kudos-ao3-reader/Features/Comments/CommentsModel.swift:970–988` resolves the displayed parent, sets `composerContext`, and synchronously loads the draft for that context and identity before returning:

```swift
composerContext = context
composerText = drafts.draft(for: context, identity: authContext.identity)
```

**Failing case:** on a loaded work with top-level draft T, tap Write a comment; hold its datastore lookup before the sheet appears. Tap Reply on comment C while the loaded list remains available, and type R. Release the first lookup. It assigns T unconditionally; the reply target remains C. Saving now overwrites C's reply draft, and Submit sends T to C. Expected: the earlier new-comment operation cannot touch the later reply or its typing. `CommentsScreen.kt:654–669` leaves the loaded screen active until the asynchronous new-comment lookup presents the sheet.

**Smallest fix:** give composer opens/closes/context changes one generation (or cancelable job). Capture target, parent/edit context and authentication identity, then verify that exact generation and context before applying a lookup. Apply the fence to all draft lookups. This is a different job from the already-reported A28-1 `present` race.

## A30-2 — An integer generation is not a persistent draft owner

`kudos-ao3-reader/Services/AO3AuthService.swift:989–992`:

```swift
if saved.username.isEmpty, !restoredName.isEmpty {
    CommentDraftStore().move(
        from: CommentDraftIdentity.unnamedSession(restoringGeneration), to: restoredName
    )
}
```

The identity in `Services/CommentSubmission.swift:345–347` is:

```swift
static func unnamedSession(_ generation: Int) -> String { "\(unnamedSessionPrefix)\(generation)" }
```

`sessionGeneration` starts at zero on every service instance (`AO3AuthService.swift:311`); startup advances it (`:459`). Drafts persist in UserDefaults as `identity|w...-c...-p...` (`CommentSubmission.swift:361–362`). `move` transfers **every** matching prefix and removes the originals (`:372–387`), concatenating a different destination draft. Logout preserves ordinary comment drafts (`AO3AuthService.swift:588–629`); it only clears unresolved-submission guards there.

**Reference being checked:** iOS's own `Features/Comments/CommentsModel.swift:30` uses that unnamed identity while logged in without a name. Restore's guards at `AO3AuthService.swift:969–983` correctly fence a concurrent session change within the running process. They cannot identify which earlier process wrote a persisted integer-keyed draft. The new code is therefore unsafe despite those guards.

**Failing inputs:** UserDefaults contains Alice's text under `unknown-session:1|w123-c0-p0` from an earlier unnamed/offline session. In a later process, a hintless saved/WebKit session belongs to Bob; startup generation is again 1. Validation names Bob. The new restore move assigns Alice's text to Bob's ordinary composer, or concatenates it with Bob's text. Opening that context and submitting can post Alice's text under Bob. Expected: only drafts provably belonging to Bob's restored credential identity move. Conversely, a draft filed under generation 2 on a previous launch is never found by a generation-1 restore, even if the account is unchanged. Claude's hand-over fixes only matching integer values, not durable ownership.

**Smallest safe fix:** persist an opaque session/draft namespace with the saved credential identity and preserve it across restore; migrate only that namespace after naming it. Legacy integer-only namespaces cannot safely be assigned to an account automatically; preserve them for explicit recovery instead of guessing ownership. Do not solve this by moving all unnamed prefixes.

## A30-3 — Replace still loses the snapshot's mark during dedupe

`kudos-ao3-reader/Services/KudosBackup.swift:3823–3824`:

```swift
func removeDeletedElsewhere() -> Set<UUID> {
    guard mode != .replaceLibrary else { return [] }
```

The new order is sweep then dedupe (`:3930–3931`), but Replace's sweep excludes nothing. Dedupe ranks all live local and incoming rows by modification time (`:4013–4026`); an incoming loser is tombstoned and hard-deleted (`:4048–4055`). Only later does Replace hide records missing from the snapshot (`:3436–3442`):

```swift
for annotation in allAnnotations where !snapshotAnnotationIDs.contains(annotation.id) {
    guard !annotation.isPendingDeletion else { continue }
    annotation.isPendingDeletion = true
    annotation.deletedAt = now
}
```

**iOS reference/contract:** the same file describes Replace as a snapshot and deliberately rolls back newer local values (`:3864–3866`). The omission pass is its implementation of that contract. This is not A27-4's unresolved question about bringing back an incoming ID covered by its own tombstone: the snapshot mark here has no tombstone when restore starts.

**Failing inputs:** work W survives Replace. Local mark L and incoming mark R have distinct IDs, the same kind and exact locator. L is modified at 300; R is modified at 100. The snapshot contains only R, with a trusted tombstone for L at 400 (or even with no tombstones). Replace inserts R, skips the sweep, lets L win, deletes/tombstones R, then soft-deletes L because L is absent from the snapshot. There is no live mark. Nonempty R note text may be parked on a hidden salvage row, but its live mark is gone and the generated tombstone can remove R on another device. Expected: Replace retains snapshot mark R; a local mark outside the snapshot cannot defeat it.

**Smallest fix:** exclude local annotation IDs absent from the Replace snapshot before same-passage dedupe, preserving those rows under the existing omission/recovery policy. Do not mint a dedupe tombstone for a snapshot row because of a local row that Replace is about to hide. Add a Replace variant to the new test; `KudosTests/TombstoneSweepsExistingRecordsTests.swift:297` currently invokes only `.merge`.

## A30-4 — Merge's same-ID skip defeats a newer revival before the sweep

`kudos-ao3-reader/Services/KudosBackup.swift:3851–3863` accepts `.reviveNewerData` and then skips an existing ID in Merge:

```swift
case .reviveNewerData, .preserveAmbiguous, .noTombstone:
    break
// ...
if let local = byID[archived.id] {
    if mode == .merge { continue }
```

The later sweep evaluates the **unchanged local** clock (`:3827–3831`) and hard-deletes it when stale.

**iOS reference/contract:** `KudosBackup.swift:3800–3803` explicitly says deletion wins over an *older* archive; `:3818–3820` says a copy edited after deletion survives. Merge's add-only rule legitimately avoids overwriting an ordinary existing live annotation, but this combination never installs the accepted newer revival after deleting the stale local version.

**Failing inputs:** local annotation A modified 300; trusted tombstone A at 400; archive includes live A modified 500 with note N, on a restored work. Incoming resolution allows 500 to revive A. Merge skips it because A is in `byID`, then the sweep deletes local A at 300. Neither version survives locally. Reconcile updates A to 500 first and preserves it; Replace updates A to 500 and does not sweep it. Expected: the live 500 version survives the deletion at 400 in Merge too, without unnecessarily overwriting unrelated existing annotations.

**Smallest fix:** treat a stale local row suppressed by a tombstone as absent for the add-only incoming-ID decision, while preserving displaced note text as required by the existing recovery policy. If sweeping before the incoming loop, rebuild `byID` from surviving models; never leave deleted objects in that lookup. Add a same-ID revival test, separate from the distinct-ID passage collision test.

## A30-5 — The cancellation fix is bypassed by same-scope/same-target no-ops

At `84778078`, `CommentsViewModel.kt:310–315` and `:571–574`:

```kotlin
if (_scope.value == next) return
// ...
if (next == CommentScope.All) {
    setTarget(AO3CommentTarget.Work(target.workId))
}
// setTarget:
if (_currentTarget.value == target) return
```

Inbox Chapter Comments starts with Work/All (`:80–82`, `:143–145`); it does not set ByChapter until the second read succeeds (`:234–243`). The picker remains reachable during Loading and All's tap calls `setScope(All)` (`CommentsScreen.kt:297–299`, `:461–485`).

**iOS comparison:** `Features/Comments/CommentsModel.swift:436–445` assigns `.byChapter` and the selected chapter **before** awaiting the chapter page. Android remains All throughout that await. iOS's `CommentsView.swift:220–223` also has an initial-context guard; I am not claiming its initial-load cancellation is universally correct. Android's explicit recorded promise that a reader's scope/page choice cancels the pending operation is itself violated here.

**Failing taps:** open Inbox → Chapter Comments; hold the chapter-page read. Open the chapter picker and choose All comments. Android returns from `setScope` without canceling `loadJob` or clearing `pendingChapterComments`. Release the read: it installs the chapter target and ByChapter scope despite that selection. Expected: the user's explicit All choice replaces the pending operation. One job owner alone does not close every supersession path.

**Smallest fix:** when Chapter Comments is pending, treat an explicit scope/target selection as a new operation even if it equals the currently published value. Cancel the pending job and perform the selected load. Keep idempotent same-target shortcuts for truly settled state.

## A30-6 — Correct chapter ID, wrong visible position

At `84778078`, `CommentsViewModel.kt:241–243`:

```kotlin
_selectedChapter.value = _chapters.value.firstOrNull { it.chapterId == chapterId }
    ?: AO3ChapterRef(chapterId, position, "")
```

`position` is the Inbox route hint, not the served byline. The parser already retains `chapterLabel` (`network/ao3/comments/AO3CommentParser.kt:181–185`, `:206–207`). A later index only changes `selectedChapter` when it is null (`CommentsViewModel.kt:293–300`), so it cannot repair this placeholder. The pill displays its position (`CommentsScreen.kt:463–464`).

**iOS reference:** `Features/Comments/CommentsModel.swift:553–563` derives the position from the served comment's `chapterLabel`:

```swift
let position = comment.chapterLabel?
    .split(whereSeparator: { !$0.isNumber })
    .compactMap { Int($0) }
    .first ?? 1
```

**Failing inputs:** Inbox hint position 3; the thread byline identifies chapter ID 77 as Chapter 5; no index is loaded. Android fetches the right chapter ID but calls it Chapter 3. iOS calls it Chapter 5. Later the index returns ID 77, position 5, title “Renumbered”: Android keeps its nonnull position-3 placeholder. Expected: the actual byline supplies the initial position; an authoritative later index can reconcile the same ID.

**Smallest fix:** derive the placeholder position from the resolved comment's byline as iOS does. Replace a matching placeholder with the later index entry without switching chapter IDs. A later index title alone is not a separate finding: iOS also initially creates an empty-title chapter reference; source reading did not establish that every later title change updates its selection either.

## A30-7 — Reply-first chapter selection changes the requested chapter

At `84778078`, `CommentsViewModel.kt:223`:

```kotlin
val chapterId = root?.let { findCommentRecursive(listOf(it), commentId)?.chapterId ?: it.chapterId }
```

**iOS reference:** `Features/Comments/CommentsModel.swift:411–429` resolves/fetches the owning root; `:553–563` takes the first chapter-bearing comment in the flattened root page. Where the root has a chapter, that root wins.

**Failing inputs:** returned tree has root A with chapter 77 and focused reply B with chapter 88. Android finds B first for chapter resolution, requests chapter 88, and may prepend A there. iOS resolves the root page and requests chapter 77. Expected: the enclosing root's chapter wins when present, with a descendant fallback only when the root supplies none. This is independent of A28's already-triaged absence of an additional parent-thread fetch.

**Smallest fix:** resolve the chapter reference from the root-first tree using the iOS traversal order; use that same comment for its ID and label. Do not pick the focused reply's byline ahead of a chapter-bearing root.

## A30-8 — Removing the phase check still leaves the first-load hole

`kudos-ao3-reader/Features/Search/SearchView.swift:265–267`:

```swift
guard !showing, var restored = loadedFilters else { return }
restored.query = filters.query
if filters != restored { filters = restored }
```

`runSearch` clears `loadedFilters` before starting the request (`:738–750`). `load` captures `current = filters` at `:878` but publishes `loadedFilters = current` only on success (`:894`). The filter control remains available while loading (`:222–228`).

**iOS contract being checked:** the comment at `:260–264` promises unapplied panel edits are dropped regardless of phase. The old A27-10 loaded/paging/failed case is fixed when a successful snapshot exists; the following first-request case is distinct.

**Failing taps:** start the first search with filters A; hold its response. Open filters, change Completion to B, and dismiss without Apply. `loadedFilters` is nil, so the revert does nothing. Let A succeed. The rows represent A while the controls retain B. Next Page sees `filters != loadedFilters` (`:864–865`) and starts page 1 of B, silently applying dismissed edits. Expected: dismissal restores the request's applied filters even before the first response arrives.

**Smallest fix:** retain a separate applied/request filter snapshot before the first await (or snapshot on panel opening) and restore it on cancel. Keep Apply explicit so closing via Apply cannot undo its snapshot. The new handler does not ordinarily undo Apply: `runSearch` synchronously clears `loadedFilters` before SwiftUI delivers the close change.

## A30-9 — A fake complete catalog escapes the demo

`android/app/src/main/java/io/github/cidy02/kudos/app/DemoLibrary.kt:302–305`:

```kotlin
val cache = FandomCatalogCache(cacheRoot)
if (!Files.exists(cacheRoot.resolve("fandom-catalog.json"))) {
    cache.save(mapOf("TV Shows" to FandomCatalogCache.Entry(
        listOf(AO3Fandom("Doctor Who", 42)), clock().toEpochMilli())))
}
```

The roots passed at `:264` are the ordinary application files/cache directories. The normal container uses that same catalog cache (`app/KudosAppContainer.kt:282–283`). On a non-demo launch `MainActivity.kt:30–31` disables the demo flag but removes no seeded data. `network/ao3/browse/AO3BrowseRepository.kt:50–55` trusts the fresh entry and returns it without a read; `FandomCatalogCache.kt:74–78` makes it fresh for seven days. This bypasses that repository's explicit no-poison rule (`AO3BrowseRepository.kt:47–49`).

**iOS reference:** `App/DemoLibrary.swift:14–19` seeds persistent sample library data, but this Privacy addition has no equivalent write of a fake complete catalog. `Features/Search/FandomCatalog.swift:199–208` stores a successfully fetched complete fandom list; `:218–225` restores cached entries as catalog data.

**Failing taps:** clean debug install with no catalog cache → launch the Privacy demo → quit → launch without demo extras → open TV Shows within seven days. The real Browse screen returns only Doctor Who, count 42, as its complete list. Expected: demo measurements must not replace normal catalog contents with fixture data. The brief records additive demo assets; that does not make a synthetic one-item list valid live Browse metadata.

**Smallest fix:** seed the fixture catalog only in a demo-specific cache namespace, and make demo measurements use that namespace. Alternatively, leave this normal catalog unseeded and supply the demo figure without a live authoritative cache entry. Do not erase genuine caches on every normal launch.

## A30-10 — Descendant pruning does not guarantee unique drawn keys

Current `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsViewModel.kt:255–266`:

```kotlin
private fun AO3Comment.without(ids: Set<String>): AO3Comment =
    copy(replies = replies.filter { it.id !in ids }.map { it.without(ids) })
// ...
val thread = if (first == null) sorted else sorted.copy(
    comments = listOf(first.without(onPage)) + sorted.comments)
```

The helper never tests `first.id`. The decision to supply `first` tests whether the page contains the **focused comment ID**, not whether it contains the owning root (`:246–248`). Drawn keys are `post-${comment.id}` (`comments/CommentThreadGeometry.kt:121`) and the LazyColumn uses them directly (`CommentsScreen.kt:590–592`). `repliesByRoot` also uses root numeric IDs as map keys (`:333–335`), so duplicate roots share/overwrite that lookup in addition to colliding in the list.

**iOS reference:** `kudos-ao3-reader/Features/Comments/CommentsModel.swift:581–592` checks `focusedRootID` before inserting a root:

```swift
guard !chapterPage.comments.contains(where: { $0.contains(commentID: focusedRootID) }),
      let root = focusedPage.comments.first(where: { $0.contains(commentID: focusedRootID) })
else { return chapterPage }
```

**Failing inputs:** standalone tree root A contains focused reply B. The chapter page contains A but not B (a truncated/different reply subtree). Android passes A as `first` because B is absent. Pruning removes only overlapping descendants; it still prepends A ahead of the page's A. Both produce `post-comment_A`, including when folded to root-only rows. Expected: one drawn root per ID, with any needed focused subtree merged into that root, not another copy.

There is a second concrete new input in the demo. `network/ao3/DemoNetwork.kt:295–296` does:

```kotlin
bytes.decodeToString().replace("comment_1001", "comment_${path.substringAfterLast('/')}")
```

`android/app/src/debug/assets/fixtures/ao3_comments_page.html:31` is root `comment_1001`; `:73` is its existing reply `comment_1002`. Asking `/comments/1002` rewrites the root to `comment_1002` but leaves that reply unchanged. A normal focused-thread `load` presents both without any `first` pruning. The recursive parser preserves the tree (`AO3CommentParser.kt:124–155`), and the root plus inline reply have the same post key. The transform also leaves numeric action/Parent Thread URLs such as `/comments/1001` unchanged (`fixture:55`, `:104–105`): it is not a coherent standalone-thread fixture for the requested comment. Expected: a valid requested subtree with unique IDs and consistent links. This is local fixture corruption, not evidence that live AO3 returns such a tree.

**Smallest fix:** resolve overlap at the root and descendant levels when combining the two trees, retaining one node per comment ID and the necessary focused subtree. Make the demo select/build a coherent standalone subtree instead of replacing one ID string throughout an unrelated page. Verify **drawn row keys**, not only descendant IDs in the particular happy-path fixture. The new test `theThreadPutFirstNeverRepeatsACommentTheChapterPageShows` deliberately assigns a new root ID and therefore never exercises a shared root or `/comments/1002`'s transformed collision.

## A30-11 — The picker keeps its own unscoped index

Current `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsViewModel.kt:295–301`:

```kotlin
if (chapterIndexRepository == null || _chapters.value.isNotEmpty()) return
viewModelScope.launch {
    when (val res = chapterIndexRepository.chapters(target.workId)) {
        is AO3Result.Success -> {
            _chapters.value = res.value
```

There is no captured auth identity/generation, nor a reset on identity change. `CommentsScreen.kt:121–124` keys the ViewModel only by work ID. `app/AppNavHost.kt:1066–1070` observes authentication and passes the new username, but this updates only the lambda used for drafts/composer identity; it does not recreate or clear the ViewModel's chapters. The reader effect (`CommentsScreen.kt:141–147`) likewise has no auth key.

**iOS reference:** `Features/Comments/CommentsModel.swift:232–255` compares AuthContext and clears `chapters` on change. Its index continuation checks `isCurrent(expected, auth)` after the load (`:904–909`), and its cache includes authentication scope as well as generation (`:1260–1279`).

**Failing inputs/taps:** hold startup session-store loading/validation; open Comments on a public work while authentication is still Restoring and no held username exists. Open its chapter picker; the anonymous index contains only chapter 1. Finish restoration as the work's owner, whose authenticated index includes additional chapter titles. The same screen gets the new username, but its nonempty `_chapters` still has the anonymous list. Reopen the picker: the early return prevents even consulting the newly scoped repository. Expected: clear/reload the index in the new auth context. A public-index read completing after restore can also populate this stale list because the continuation has no viewer fence. No sign-in or network was performed to audit this counterexample.

**Smallest fix:** scope the consumer's chapter state and in-flight index/reader effect to the auth context, not only the repository map. Clear old chapters/selection and cancel or reject old continuations when that context changes. Reopening a settled picker should then use the repository's correct per-session cache. Do not retain a guest index just because it is nonempty. The new two repository tests exercise direct sequential cache calls; neither mounts this retaining consumer during restore.

## A30-12 — A trailing count does not speak the required label

`android/app/src/main/java/io/github/cidy02/kudos/ui/subject/SubjectForm.kt:107–110`, `:159`:

```kotlin
byControl -> semantics { contentDescription = label.removeSuffix(REQUIRED_MARK) }
// ...
modifier = (if (hasValue) Modifier else Modifier.weight(1f)).spokenAs(label, byControl = trailing != null),
```

`trailing != null` means arbitrary composable content, not necessarily an accessible field. The existing `writing/WritingEditTagsScreen.kt:147–149` passes:

```kotlin
SubjectFormRow(tagKind.title + if (tagKind == WritingTagKind.Fandom) " ∗" else "", trailing = {
    Text(workFormCount(values), color = tokens.secondaryInk, fontSize = 13.sp, lineHeight = 18.sp)
})
```

**iOS reference:** `Features/Writing/EditTagsView.swift:218` marks Fandoms required. Its inline count row in `Features/Writing/WritingFormFields.swift:84–94` explicitly speaks `"\(title), required"` on the label, even though a count follows it. `UIComponents/SubjectForm.swift:249–252` also uses explicit `isRequired`, independent of trailing content.

**Failing taps:** open Writing → Edit Tags, focus the Fandoms label with a screen reader. The changed helper gives it contentDescription “Fandoms”; its trailing “None”/count has no required description, and the Add control is just “Add Fandoms” (`WritingEditTagsScreen.kt:163`). Nothing in that row announces required. Expected: “Fandoms, required,” as on iOS. This is a production caller affected by the shared-component change, not a hypothetical suffix collision.

**Smallest fix:** default required labels to speaking required even with custom trailing content. Use an explicit label-spoken-by-field option only for actual `SubjectTextFieldRow` callers, where the field itself supplies that announcement. Apply the intended label semantics in its stacked path as well: `SettingsChrome.kt:173` currently draws plain `Text(label)` while `:156` gives the field the required description, leaving the visible-label semantic text with the glyph at large/multiline size. Keep the rendered strings unchanged.

## 1. 84778078 — A28 fix closure and state paths

| Prior case | Verdict on the revised code |
|---|---|
| A28-1, `present` puts a top-level draft into a reply opened during its suspended lookup | Closed for that specific continuation: reply/edit/presentation/current-target guards reject it. Not a universal composer fix: A30-1 is the unguarded `openComposer` lookup. |
| A28-2, detached thread job writes after another page/scope load | Closed when the new action actually calls `load`: one `loadJob`, cancellation and `ensureActive` after both reads. Not every choice reaches it: A30-5. |
| A28-3, failed required thread discarded and retry drops Inbox intent | Transport/typed failures at either read now surface and retain the pair for retry. A successful parse without the required root still takes `present(work, thread)` and clears intent (`:224–228`): the missing-required-comment case already described in A28 remains open; not re-filed. |
| A28-4, Chapter Comments needs an anonymous index for a restricted work | Closed for this opening: derives ID from the thread, two reads, no index. Thread-only fallback with no chapter is an explicit new decision, not a finding. The separate reader/picker index path was acknowledged; the later ef718dad is reviewed under item 7. |

`retry` (`CommentsViewModel.kt:152–155` at 84778078) repeats `lastPage` plus focused ID for an ordinary failed page/thread. `load` records both and clears pending intent (`:160–175`). A failed first Chapter Comments read retains `(commentId, position)` and retries the operation; a failed second read retries **both reads**, not only the chapter page. That is the recorded whole-operation retry, not an extra automatic retry. Authentication-required results show a login action rather than Try Again; other typed failures show Try Again.

On successful Chapter Comments the target becomes Chapter, focus becomes null and the pending pair is cleared; page selection then reads that chapter. `lastPage` remains 1 on this initial-only operation; explicit page loads set it. `setTarget`, `setScope`, `selectChapter` clear pending and reset page/focus **only if their equality shortcuts reach `load`**. `openOnChapter` sets selected chapter/scope once, then delegates to `setTarget`; re-entry does not undo a later choice. Sorting only changes loaded order. A direct refresh/default `load()` selects page 1 and drops focused/pending intent; no independent pull-to-refresh handler was found in this screen. Explicit pager calls load the requested page and clear focus.

`reloadPageOnScreen` (`:468–470`) uses the loaded page or 1, then calls ordinary `load`, which cancels pending Chapter Comments and clears its pair. A reply success clears its captured draft and calls that reload (`:523–529`); an unconfirmed/non-offline reply also reloads while preserving composer context (`:536–541`, `:165–171`). If these methods run while Chapter Comments is Loading, they replace it with the current Work/focused-thread read, not its pending chapter operation. I did **not** establish a production tap sequence that posts a reply during this initial pending operation: the Write control and comment rows require Loaded state. This conditional path is not presented as another confirmed UI finding.

## 2. f0940037 — The fifteen rows and the extra networking change

### Fifteen row checks

Read the production change, brief/result/landing note, the quoted iOS implementation and `Brief3caScreenTest.kt`. No visual verification is claimed.

| Row | iOS reference (`kudos-ao3-reader/`) | Source verdict |
|---|---|---|
| 6 | `Features/Browse/NativeBrowseView.swift:656`, fandom sibling `:280` | Filtered tag empty copy/clear differs correctly from truly empty; Date Updated baseline is ignored by the extra-filter badge. Clear explicitly loads page 1 once. Existing fandom behavior retained. |
| 10 | `Features/Account/AO3DashboardView.swift:18` | Signed-out Dashboard copy and no action; no profile composition/read for absent username. |
| 12 | `Features/Account/AO3PreferencesView.swift:486` | Authentication-required save preserves edits, shows the quoted expiry message, and does not reload the successful-save path. Expiry belongs to the authenticated client. |
| 13 | `Features/Account/AccountComponents.swift:34` | Restoring gets the skeleton, not the signed-out header. |
| 14 | `Features/Account/AccountComponents.swift:40` | One combined accessibility label, “Restoring AO3 session”; no login action on the skeleton. |
| 18 | `Features/Account/AccountView.swift:727` | Own embedded profile NotFound gets Profile unavailable below its account header, without retry. |
| 19 | `Features/Account/AccountView.swift:727` | Exact own-profile description; no anonymous probe/action. |
| 24 | `Features/Authors/AuthorProfileContentSections.swift:77`, `Services/AO3AuthorProfileService.swift:365` | Failed later page retains the successful page's rows and explicitly retries the failed requested page. Android's replacing pager rather than iOS accumulation is recorded, not re-filed. |
| 32 | `Features/Authors/AuthorProfileView.swift:699` | Header 404 gets Author unavailable, Open on AO3, no Try Again and no selected-tab read. |
| 33 | Same `:699` | Missing pseud copy and pseud dashboard URL, not the base user's URL. |
| 34 | Same `:710`, `:728` | Non-404 header failure preserves author/pseud identity and Try Again; Dashboard uses its account header. A successful retried header alone activates selected content. |
| 36 | `Features/Bookmarks/AO3NamedSubscriptionsList.swift:169`, `:235` | Named signed-out subscriptions use ordinary list failure/description/Try Again. The retry is local while signed out. |
| 37 | `Features/Comments/CommentMarkup.swift:126`, `:476` | Six heading levels; fallback h3; re-leveling retains the enclosing heading's whole body and adjusts selection. |
| 38 | Same `:476` | Six spoken “Heading N” labels and matching insertion levels. |
| 47 | `Features/Bookmarks/AO3AccountWorksList.swift:711` | Nonempty raw page filtered to zero gets the exact local-filter empty state; Clear changes filters without a read. Privacy hiding alone is not this state. |

The tests use terminal local clients and assert actual words, actions, draft mutations and read counts; they are not generally tautological. One claim is overstated: `row12ExpiredPreferenceSaveKeepsEditsShowsIosMessageAndExpiresOnlyItsSession` (`Brief3caScreenTest.kt:197–219`) never replaces the session while the POST is held. Removing the production generation fence would still pass its “only its session” portion. Its edits/message/no-reload assertions remain useful. A held old-session refusal after a new login is needed to establish that part; this is a coverage limitation, not evidence of a production regression. The old A28-5 tests are not re-filed.

### Every production repository caller

| Caller | Method/path | Failure surface now |
|---|---|---|
| `author/AuthorProfileScreen.kt:116` (also Dashboard wrapper) | `loadDashboard` → changed `getHtml` | 404 Author unavailable/Open on AO3; otherwise identity + Couldn't load author/Try Again. Expiry can trigger auth-generation reactivation as described below. |
| Same `:144` | `loadWorks` | Typed tab error; later-page failure retains old rows/Try Loading More. **This method already had the one-session/no-fallback path before f0940037.** |
| Same `:153`, `:162`, `:171` | `loadSeries`, `loadBookmarks`, `loadAbout` → changed `getHtml` | Initial tab failure or preserved later-page content with explicit retry, according to the existing tab/page state. |
| `account/AccountViewModel.kt:138` | Own header `loadDashboard` | First 404 marks Profile unavailable; other failures leave available account identity without a new generic error card. Generation changes discard old results. |
| Same file `:49` | `AccountSeriesViewModel.load` → `loadSeries` | Maps AuthRequired/Failed/Loaded, but no production instantiation of this view model outside its own file was found. Do not invent a visible Series screen for it. |
| `search/SearchViewModel.kt:360` / `SearchScreen` | `search` → changed `fetch` | Search failed + typed message/Try Again; stale rows may remain on a paging error (`SearchScreen.kt:265–266`). |
| `browse/TagWorksScreen.kt:109` | `search` → changed `fetch` | Error message + Retry (`:345–351`), no successful works list. |
| `network/ao3/browse/AO3BrowseRepository.kt:96` → `browse/FandomWorksScreen.kt` | `searchTagWorks` | Unchanged direct anonymous `client.get` (`AO3SearchRepository.kt:47`), not the changed `fetch`. Couldn't load works + explicit retry. |

`loadFandomWorks` has no external production caller in the searched main source. Containers and composable parameters pass repositories; they do not add independent reads.

### Failure-by-failure: before, now, iOS

Before, author `getHtml` and search `fetch` retried **every returned authenticated failure** via the public client. A parse failure after a successful response never triggered that fallback. Now they choose one branch using `username() != null` (`AO3AuthorRepository.kt:67–71`, `AO3SearchRepository.kt:19–21`). The following applies to each changed caller above; its specific card is in the caller table.

| First authenticated read | Before f0940037 | Now | iOS |
|---|---|---|---|
| Session expired/login refusal | Client expires captured session, then repository asks anonymously; public success could become public content. Account/Author generation fences can discard the outgoing result. | No repository anonymous fallback. Search/Tag receive AuthenticationRequired (“AO3 requires login.”); own Account becomes signed out; Author generation reactivation can start a **new** public context. | Auth-required is not hidden by stale authenticated author HTML (`AO3AuthorProfileService.swift:63–66`). Author expiry changes its auth scope and may reactivate publicly; Search reports the request failure. No same-operation anonymous retry. |
| 403 | If public succeeds, public content; otherwise the public failure is shown, masking the first failure. | Refused header/tab/search/tag error, “AO3 denied access.” | Single chosen request; author may serve stale HTML from the **same** auth scope for non-auth failures (`AO3AuthorProfileService.swift:67–71`), otherwise failure UI. |
| 404 | Public success could recover; otherwise normal not-found failure. | Header unavailable card; own profile unavailable; tab/search/tag typed not-found failure. | Header unavailable or applicable list/search failure, with the same-scope stale author-cache exception. |
| 5xx | Public success could recover a transient or cookie-specific server failure. | Server/busy error and explicit retry; old rows retained where the caller supports them. | Single request, possible same-scope stale author result; otherwise retryable failure. |
| Offline | A second public attempt was still made. With continued outage it failed too. | One chosen logical read and offline failure; no anonymous retry. | Same-scope stale author data can keep an author page usable offline; otherwise offline/network failure. |
| Viewer cannot see the page | A typed refusal could be bypassed by a public success; a 200 response failing parse did not fall back. | Preserve refusal/parse failure; do not anonymously probe for more. | Preserve chosen-viewer result; no refusal bypass. |

**Yes, some screens now fail for reasons other than session expiry where they used to work:** e.g. authenticated 503, public 200 on a header/Series/Bookmarks/About/search/tag request. That is the deliberately recorded removal of all returned-failure fallback, not an unapproved regression. A genuine 200 parse failure, author Works, and fandom `searchTagWorks` did not have this behavior change. iOS's stale author cache is not an anonymous retry; Android's lack of that same cache predates this commit.

**Signed out:** with the actual default authenticated client, one anonymous repository read remains. Previously the authenticated attempt failed locally at `authenticatedHeaders` before touching transport, then the public fallback read once; now the null-username branch directly reads once. This is one logical read, not a guarantee of exactly one wire attempt: the common transport can perform its separately allowed retry behavior. No successful-header selected-tab read should be confused with a retry of the header.

**Restoring:** `username() != null` is not a test of published SignedIn state. `AO3AuthRepository.kt:118–121` installs `currentSession` while state remains Restoring during validation; `:281` returns that session's username. Calls during that interval authenticate, whereas earlier calls before disk load are anonymous. iOS checks `auth.isLoggedIn` for author reads (`AO3AuthorProfileService.swift:48`); its request helper is also gated by `isLoggedIn` (`AO3AuthService.swift:715`). Thus timing can change the viewer chosen during restore. This preexisting distinction is not a new fallback-removal finding. If parity requires waiting for restored authentication, use the auth state/identity generation, not a nullable display name, and do not solve it by reinstating a refusal fallback.

## 3. 51b4eada — Privacy selections, measurement, notices and demo persistence

| Action | Android effect | iOS comparison / safety conclusion |
|---|---|---|
| Free up space | `WorkRepository.kt:367–376`, `:1055–1056`: active finished works with EPUB and no protection; deletes only the EPUB, updates flags, retains record/positions and original source. | `Services/LocalDataClearing.swift:29–43`: same finished/file/not-protected/not-deleted selection. Kept/downloaded, favorite, imported/no AO3 ID and known-unavailable works protected. Keep-offline queues/collections protect even when the keeper is deleted. An ordinary finished AO3 reading copy can be removed, by design on both platforms. |
| Clear reading positions | `WorkRepository.kt:157–175`: active works with locator, positive spine/scroll or nonnil legacy progress; resets all four fields, updates progress/record clocks; retains work, EPUB, shelf order/lastReadDate. | `LocalDataClearing.swift:56–85`: same selection and resets. Includes a work currently being read: that is iOS's explicit all-positions behavior too, not an extra Android deletion. |
| Clear reading history | `WorkRepository.kt:144–154`, `:384–395`: active no-EPUB, not-protected, not-queued-for-later works; soft-deletes for 90 days and records work tombstones. No EPUB/source/font/recovery deletion here. | `Features/Account/PrivacyDataView.swift:64–65`: no EPUB/not protected. Android additionally excludes queued-for-later, an explicit decision. It does not take a kept/favorited/imported/unavailable work that iOS keeps. |
| Clear browse cache | `FandomCatalogCache.kt:65–66`: only `cacheDir/fandom-catalog.json`. No library row, reading copy, original, font, recovery text or reader file deletion. | Same purpose as iOS's browse metadata clearing; platform cache scope is explicitly recorded (Android streams EPUB rather than creating iOS's unzip scratch). |
| Remove AO3 session | Confirming logout, `PrivacyDataScreen.kt:190–193` → local `AO3AuthRepository.logout`. Clears durable/in-memory credentials and local cookies, sets removal-pending on failure; no HTTP. | iOS local logout purpose matches; does not delete typed drafts or library files. |

`SavedWork.isProtected` and relation decoration were checked, not inferred from the button text: iOS `Models/Models.swift:473–492` and Android's work/model/keeper queries. The four Android Clear confirmations follow the user preference; iOS always asks. This is explicitly recorded, not a finding. Source reading found no additional last-copy deletion among these new screen actions.

**Measurement:** `settings/LocalDataFootprint.kt:64–82` encloses database reads and all disk traversal in `withContext(Dispatchers.IO)`. A large library is materialized off the main thread; it is not a UI-thread filesystem walk. `:85–111` skips hidden entries, does not recurse through symlink directories, and rejects symlink files with NOFOLLOW_LINKS. Missing directories return zero. A file disappearing before/during size/stat lookup contributes zero via `runCatching`; directory enumeration failures return zero for that subtree. iOS's scanner is detached (`Services/LocalDataFootprint.swift:64–82`) and skips unreadable files (`:99–120`). Reading-copy size uses logical bytes on both platforms and is subtracted with a zero clamp; other files use allocated blocks when available, including valid zero-block sparse files. Recursive totals are not an atomic snapshot on either platform. See Unconfirmed for symlink metadata parity on the separate reading-copy path and for platform formatting.

**Notices:** `PrivacyDataScreen.kt:139–149` observes the auth and notice flows. Expiry and logout publish fixed sentences (`AO3AuthRepository.kt:148`, `:288`, `:298–303`); accepting/validating a session clears the notice (`:311–319`). Cleanup-retry also updates/clears the removal notice. The single-shot restore starts from a new null notice, and old-generation continuations are fenced. No persistent path was established where a completed successful login leaves Logged out/session expired below Signed in. These notices interpolate no username, token, URL or exception text. The explicit Signed in value displays the user's username as intended; it is not leaked by a notice.

**Demo:** new assets are additive in normal app-owned roots: original TXT, copied TTF and font row, a recovery record, catalog JSON and named saved search (`DemoLibrary.kt:269–309`). It only **reads** `/system/fonts`; it writes nothing outside the app's supplied files/cache directories. The assets and rows do persist into a non-demo launch; there is no isolated database or cleanup. Ordinary additive library/demo fixture persistence was already recorded. The authoritative catalog contamination is A30-9: it changes actual non-demo Browse results rather than merely leaving a visibly named sample asset.

## 4. iOS 53c552ce — T-371 closure and remaining edges

The exact A27-3 distinct-ID Merge case is fixed: sweep removes old Local before dedupe, `excluding` prevents it ranking against Remote. Reconcile has the same ordering and same result. The new regression test is meaningful for `.merge` (`TombstoneSweepsExistingRecordsTests.swift:262–301`), but does not exercise Replace or same-ID revival. Replace and same-ID Merge counterexamples are A30-3 and A30-4.

An empty annotation list still invokes the sweep before returning (`KudosBackup.swift:3836–3838`) in Merge/reconcile, even when no work was restored. Replace intentionally does not sweep tombstones; its later omission pass hides all annotations absent from the empty snapshot. A soft-deleted loser is excluded by the live filter (`:4014`) on a later dedupe; the clock stamped on the loser (`:4051–4053`) does not by itself make it live again. The older triaged concern about that clock versus a tombstone is not presented as a new confirmed bug.

The incoming loop completes before the new sweep (`:3847–3930`), so its `byID` is not subsequently used to write a swept row. The new dedupe fetch/filter can nevertheless inspect a swept object's fields before checking exclusion; the actual SwiftData deleted-model lifetime/crash is Unconfirmed below. A hard-deleted incoming dedupe loser is not subsequently mutated by that loser loop.

The new unnamed-draft move uses **this launch's restoring generation**, after valid-session acceptance. It is fenced against a concurrent login/logout in the same process; persistent generation collision/mismatch is A30-2. Merely adding `move` does not establish cross-launch identity.

The filter phase removal fixes dismissal while paging or failed when a loaded snapshot exists, and does not ordinarily undo Apply because `runSearch` clears that snapshot synchronously. The first-loading gap is A30-8.

`Features/Account/AccountShortcuts.swift:94–106`: encode empty as `none`, decode that literal as empty; empty/unknown-only input still uses defaults. This closes A27-11; no new issue found.

`Features/Writing/SeriesEditView.swift:120`, `:129` share verdictID, but `save` is single-flight (`:252`), clears both verdicts (`:254–255`) and assigns only success or error (`:260`, `:262`). The two ID rows are mutually exclusive in the read save path; a duplicate-ID crash is not established. The scroll handler runs on verdict changes (`:136–138`). Actual visibility after SwiftUI layout remains manual; no visual-correctness claim.

`Features/Writing/AddChapterView.swift:454–457` and `SeriesEditView.swift:571–575` catch `AO3WorkWriteError.unconfirmed` before the generic failure prefix. They preserve the uncertainty wording and do not claim the operation did not happen; no new write/retry is introduced by those catch arms.

## 5. f17ed651 — Challenge sign-ups and withdrawal

Read the new list/parser/state/screen, both entrances and route registration, own-form withdrawal change, shared authenticated write/verdict code, demo routing/mutation and relevant tests against `Features/Challenges/ChallengeSignUpsView.swift`, `ChallengeSignUpView.swift`, `Services/AO3ChallengeActions.swift`, the challenge paging service and shared Swift write builder. No additional confirmed finding in this item; the following reductions are explicit decisions, not omissions to re-file.

### Counted reads

Counts below assume successful two-page sign-ups and one-page assignment lists; subtract the last-page read for a single-page sign-ups list. No POST is made by list opening, filtering, refresh, Load more or participant detail.

| Viewer/case | Android reads, in order | iOS comparison |
|---|---|---|
| Owner, known closed gift exchange | 6: gift edit; Complete `assignments?fulfilled=true`; Open `assignments?unfulfilled=true`; Defaults `assignments`; sign-ups page 1; last sign-ups page. | Same six when each assignment list is one page. iOS walks all their pages; Android page-one-only is owner question 16. |
| Owner, known open | 3: gift edit; sign-ups first/last. | iOS still attempts assignments; if the first assignment read is refused, it adds one failed read. Android deliberately avoids it. |
| Owner, failed schedule probe | 3, or 4 when a 404/parse failure triggers gift→meme fallback: attempted edit(s), sign-ups first/last; no assignments. | iOS swallows schedule failure but still tries the assignment join. |
| Owner, prompt meme resolved by fallback | 4: gift probe, meme edit, first/last sign-ups; no assignment probe. | The omitted gift-exchange assignment join is recorded. |
| Moderator | 2: sign-ups first/last, unknown matching, no owner schedule or assignments. | iOS tries the owner schedule, swallows refusal, then tries assignments. If assignments are available and single-page, six reads; if first assignments read refuses, four. Android's reduction is explicit in the brief/result/decision. |
| Neither owner nor moderator | 0, local terminal refusal. | Collection's iOS entrance requires `show.isMaintainer` (`AO3CollectionDetailView.swift:355–359`); it does not present this list to this viewer. |
| Signed out | 0, local login sentence. | Swift authenticated-request construction fails locally, without sending a list request. |

`AO3ChallengeSignUpsState.kt:47–55` remembers attempted and rejects duplicate/in-flight/terminal/stale-session loads. An explicit refresh repeats that viewer's opening sequence; failed optional schedule/assignment/total reads do not erase loaded rows or cause an automatic retry. Complete failure stops before Open/Defaults (four total reads with successful schedule and first/last list); Open failure stops before Defaults (five). A failed last-page count leaves total nil and retains page 1. Load more makes **one** next-sign-ups-page read and dedupes appended rows by ID (`:88–106`); it does not repeat settings, assignments or the total calculation. The last page can be read once for total and again when the user loads it, as iOS (`AO3Client+Challenges.swift:47–52`). Filters use only loaded pages. The documented partial assignment join can call later-page sign-ups Unmatched; broader crawling was expressly deferred, so it is not a new finding.

Participant detail uses the selected already-parsed row: zero reads/writes; its own shell Back restores list context. Rows are lazy. Role admission is captured for its opening generation; the model is closed/cancelled on disposal and checks the generation after reads. The two native entrances carry owner/maintainer admission from their already-loaded collection/settings state. Direct unadmitted debug routes get an HTTP-403-worded local refusal; the result already acknowledges that wording, not a live request.

### Withdraw, field for field

`AO3WriteRepository.kt:349–369` matches Swift `AO3ChallengeActions.swift:74–86` and `AO3WriteActions.swift:404–412`, `:443–455`:

| Part | Actual contract |
|---|---|
| Token preparation | One fresh authenticated GET `/collections/<encoded slug>/signups/<id>/confirm_delete`. Only trimmed nonempty meta `csrf-token`; no replay of the own-form's token or hidden stale token. |
| Dispatch | One POST `/collections/<encoded slug>/signups/<id>`; URL derived by the trusted AO3 collection URL builder, not an arbitrary served action. |
| Ordered body | `_method=delete`, then `authenticity_token=<fresh meta token>`, form encoded. No commit, prompt fields, form carry fields or extra ID. |
| Headers | `X-CSRF-Token` fresh token; Referer exact confirm-delete URL; Cookie captured through the authenticated client; identifiable shared User-Agent; `application/x-www-form-urlencoded; charset=UTF-8`. No AJAX `X-Requested-With` or special Accept. |
| Session boundary | Generation check before token read, after token read and at shared pre-dispatch fence (`AO3AuthenticatedClient.kt:45–60`). NonCancellable POST; after it, nonthrowing `movedOnAfterWrite` rather than `requireCollectionSession`. No write retry. |
| Verdict | AO3 error text first; notice or 3xx success; unexplained 2xx unconfirmed; other status fallback. Matches Swift `AO3CollectionActions.swift:483–494`. Login refusal remains auth refusal; a different post-dispatch session returns unconfirmed. |

Only a parsed existing `signUpID` exposes Withdraw. Opening the form reads only its new/edit page; exposing/opening/canceling confirmation adds no GET/POST. The UI does not invent a closed-schedule visibility gate; after-close defaulting is deliberately a different, unimplemented service. AO3 decides whether this DELETE is allowed.

**Second tap:** `AO3ChallengeSignUpState.kt:104–107` publishes withdrawing before its first suspension, so another concurrent confirm/method call sends nothing while preparing or posting. Success sets withdrawn, blocking subsequent load/save/withdraw calls. Refusal/unconfirmed clears busy in `finally` and retains typed form fields. A *later explicitly confirmed* retry after a nonterminal refusal/unconfirmed result can make another fresh token GET and one POST; neither app has a permanent submission block for that deletion. This is not an automatic POST replay. Terminal auth/403 blocks another attempt on that state.

**After withdrawal:** success sets the exact “Sign-up withdrawn.” notice and callback pops the own-form route plus shows a toast (`AO3ChallengeSignUpScreen.kt:53`, `AppNavHost.kt:799–801`). There is no explicit mutation/invalidation of an already-held parent-list state. The ordinary remounted Android list creates a new `remember` model and repeats its admitted opening reads; the demo's next sign-ups response removes ID 4, yielding five rows/total and Your sign-up resolving ID 5. A retained list state would keep its old rows until refresh. iOS sets the notice/dismisses (`ChallengeSignUpView.swift:683–695`) but its list's `phase == .idle` guard does not itself refresh a retained loaded list on return (`ChallengeSignUpsView.swift:445–447`). Immediate retained-list refresh is not proven on either platform; see Unconfirmed. No automatic follow-up GET is inside the withdraw repository itself.

Read tests for counted admission, optional failures, append/refresh retention, exact wire body/header construction, all verdicts, busy/duplicate guards and session changes. Their assertions exercise those rules; none were run here. The demo's closed-schedule DELETE success is an intentionally synthetic verdict already disclosed in the result, not evidence of live after-close permission.

## 6. 99fe77a9 — Duplicate comment keys and single-comment demo page

The reported overlap of **distinct roots sharing descendants** is fixed by collecting every page ID and pruning shared replies from the prepended tree. The guarantee “any comment the page already shows” is too broad: it never prunes the prepended root itself. The root-overlap and coherent-demo counterexamples are A30-10.

Paging replaces the loaded thread, not appends it. Refresh, reply/edit/delete reload and ordinary focused-thread load call `present` with no `first`; those paths cannot accumulate the previously prepended tree across pages, but do not dedupe a duplicate already present in the new response either. Sorting reorders roots without normalizing IDs, so a duplicate-key state survives a sort; folding can hide a repeated descendant but never fixes repeated roots. Reply expansion/Continue Thread also draws the same source tree. The model's helper only applies to the special chapter merge, not universally to the drawn list. The new test uses a deliberately different standalone root and walks IDs; it does not build the same-root case or assert all actual row keys after those transitions.

The demo helper transforms both native and intercepted comment-address answers, but only rewrites `comment_1001` strings. It leaves the unrelated roots/replies and numeric action addresses from the original fixture; requests matching an existing reply/root ID can create collisions. A normal focused load of that fixture can therefore fail without even invoking the new pruning helper. The unrelated Post work color edits in this commit were read; they change only the theme-based success green in the two action renderers, not dispatch or confirmation.

## 7. ef718dad — Session-scoped chapter index

The production container now supplies DefaultAO3AuthenticatedClient. Repository keys are `(workID, sessionGeneration)` for a held named session and `(workID, null)` for anonymous (`AO3ChapterIndexRepository.kt:31–44`). With the production client's monotonically advancing generation, sequential repository calls do not serve Alice's key to Bob or the anonymous key to a signed-in caller. Relogin also gets a different generation. There is one chosen GET on a cache miss; refusal does not retry anonymously; empty parsed results are not cached. The signed-out direct path makes one anonymous logical read.

That fixes the original anonymous-only restricted-work read, but does **not** establish end-to-end viewer isolation: the consumer stores `_chapters` without a viewer key and bypasses the repository after its first nonempty result (A30-11). Reader initialization is keyed only to chapter position/work and can also accept a late old-viewer index. The client's GET fence is before index parsing (`AO3AuthenticatedClient.kt:74–79`); the repository does not recheck after `withContext(Dispatchers.Default)` or on its cache-hit return. The old-generation parsed entry is stored under its old key, so that alone does not poison Bob's repository key, but the returned old-viewer result can still populate an unfenced mounted consumer. One must distinguish safe map separation from safe publication.

`username() != null` still is **not** published SignedIn: `AO3AuthRepository.kt:118` installs the restored session while validation/state is Restoring, and `:281` reports its held username. Before installation the index is anonymous; after installation it authenticates, even before restoration acceptance. Swift `CommentsModel.swift:282–285` uses `auth.isLoggedIn`, and its AuthContext clears/reloads chapters on restoration becoming signed in. A nullable username is not sufficient to match that behavior; choose a captured auth state/identity with a generation, and fence its publication. The new tests cover sequential repository cache changes, not restore timing, same-screen retention or a parser held across an auth transition. No anonymous fallback should be added to cure this.

## 8. dd987fef / 3f34360f — Comment and composer layout

**Source verdict: no confirmed dropped control or changed action in these diffs.** This is a layout-only check, not a claim the new layouts render correctly at every width/font scale.

`CommentThreadComponents.kt:457–523` factors the same name/role and metadata nodes into lambdas. Name/avatar keep their same author callbacks only when a username exists. Role badge keeps the same non-User/non-Guest condition and is still not an action. The chapter surface keeps the same nonblank-label condition and remains nonclickable. Hide/Show keeps `collapse != null` and the same `onToggleCollapse` clickable surface. Neither accessibility nor default branch adds/removes these controls. At scale above 1.3 the name/role row is followed by a FlowRow of date/chapter/collapse (`:524–535`); metadata can wrap rather than sharing the fixed avatar-height row.

At default size, the empty weighted spacer is replaced with a weighted name/role block (`:537–549`), so the name receives the previously wasted free width; metadata remains outside that block in the same order. The row changes fixed height to `heightIn(min = avatarSize)`, allowing taller contents—an expressly recorded decision beyond merely allocating name width. Text sizes, badge conditions, colors, avatar and body/control ordering otherwise remain. Long names still use one line/ellipsis, so “shown whole” is not an unlimited-width guarantee. Single metadata items wider than the available FlowRow width still need rendered inspection; source alone cannot prove every label fits.

`CommentComposerSheet.kt:119–164` preserves Cancel/onDismiss and confirmation/onSubmit, their enabled predicates, and the spinner. Both action labels get one line/no soft wrap; the title gets the remaining weighted width, one line/ellipsis and centered text. No header control is conditionally removed, no callback or tappable parent is broadened, and normal-size title placement still follows the space between the two action widths. Changes do not turn title/metadata into actions. Button fitting on the smallest width at extreme scale remains unverified; the commit itself says the final fix was not seen on the emulator. The earlier composer state race is A30-1, not a layout finding.

## 9. 579c87df — Required-label accessibility

Rendered strings are unchanged: all new operations are semantics modifiers/contentDescription; `Text(text = label)` still draws its original marker. The exact suffix is space plus U+2217 (`" ∗"`), not ASCII `*`; labels without that suffix keep their previous description. Required row values, count text and button actions are not altered.

The shared helper interprets **every** label ending with that suffix as required; it has no explicit required flag. Thus an unrelated dynamically supplied label with that literal ending would also get changed semantics. Search of production marker call sites found Title, Archive warnings, Fandoms and the inline Fandoms count row, not a confirmed optional static label ending that way. Do not invent an existing optional-row regression without such a caller. An explicit required parameter would avoid inference if arbitrary user labels are later passed here.

The actual current regression is A30-12: `trailing != null` suppresses required speech for a trailing count that cannot supply the announcement. The stacked/multiline text-field path also still renders plain label semantics while only its field is relabeled, so the claimed “label says the name alone” rule is not applied there. The revised WorkForm tests inspect the field's new description; they do not establish all required label paths or inline count speech.

## Unconfirmed

- **SwiftData reads after deletion:** `KudosBackup.swift:3831` deletes a model; `:4013–4014` fetches then evaluates `isPendingDeletion` and `deletedAt` before `removed.contains(id)`. If a fetch exposes the pending-deleted row, exclusion does not prevent those reads. Whether that traps or materializes stale values depends on actual context/model invalidation. Confirm with saved file-backed and in-memory contexts, pending deletes, autosave boundaries and same-passage duplicates. Do not describe the exclusion as proof that deleted models are never read. Source reading establishes no later `byID` write after the sweep.
- **Reading-copy symlink metadata:** recursive file measurement explicitly rejects symlinks; the separate `Files.size(workEpubPath)` follows them. iOS uses URL resource values for this separate logical-size path. Confirm its actual symlink result on Foundation and Android before asserting a numerical parity defect. No source file is deleted by measurement.
- **Localized byte labels and rendered layouts:** allocated/logical selection is source-checked; exact Foundation/NumberFormat boundary labels, large-text fit, verdict scroll timing and imported-font validity require device/runtime checks. None were run.
- **Reply/reload while initial Chapter Comments is pending:** the model methods cancel/drop the pair as described in item 1, but the visible loaded-state gates prevented establishing a production tap sequence for this initial case. A fake-only call sequence is not enough to claim users encounter it.
- **Retained list immediately after withdraw:** the callback pops and toasts but does not notify the parent model. Confirm Navigation Compose disposal/remount and rapid transition cases to establish whether every return refreshes the list or an old mounted state can still show the removed row. iOS's own loaded list is not explicitly invalidated either. The demo's next GET definitely omits the withdrawn row; that does not prove an existing list was refreshed.
- **Arbitrary optional label ending in the required glyph:** the generic helper will reinterpret it; no such existing optional production call site was confirmed. Test an actual dynamic-label caller before adding another finding. Inline required count speech is confirmed separately in A30-12.

## What was not read / not verified

All nine requested items received the source audit described above; there is no pending numbered item. No full-repository audit, exhaustive test-suite read, external AO3 behavior check, rendering, builds or test execution was performed. Specified diffs/briefs/results/landing notes, A28/A27 triage, relevant main-source callers and quoted iOS reference paths were read. R5/A14 and R3, plus the earlier 3bl/3ba/3ay results, were not independently re-audited as whole historical reports; the live production/Swift code and current recorded decisions were used for the challenged behavior. The new test suites were read selectively for the specific claims discussed, not as a complete test audit. Existing iOS untracked `Packages` and `Vendor` directories were not modified. Only `docs/android-port/audits/A30-result.md` was created.

## Triage (Claude, 2026-10-09 evening)

| ID | Verdict | What was done |
|---|---|---|
| A30-1 | Real | Fixed: one composer count fences every draft lookup. Test fails without it. |
| A30-5 | Real | Fixed: a scope or target chosen while Chapter Comments is pending is a new load. Test. |
| A30-6 | Real | Fixed: the number comes from the byline; the index replaces the placeholder. Test. |
| A30-7 | Real, though AO3 keeps a thread on one chapter | Fixed with A30-6: root first. |
| A30-9 | Real, debug installs only | Fixed: the demo's entry is dated 1970. An install that already ran the demo is not repaired. |
| A30-10 | Real | Fixed: the page's copy of the root gives way; the demo page is coherent. Test. |
| A30-11 | Real | Fixed in the screen's model (the repository was already per session). Test. |
| A30-12 | Real | Fixed: explicit `labelSpokenByControl`; the stacked label no longer speaks the mark. |
| A30-2, A30-3, A30-4, A30-8 | iOS | See the iOS task rows (T-376 onwards). |

**Later the same evening.** A30-10's fix was changed after Codex's unfinished review A32 (the
comment asked for goes first by itself; the page's root is left whole). The iOS findings
landed as T-376 (`e1bbb8c5`; each new test fails with its fix taken out). A30-4 applied to
Android too and is fixed there (`BackupMergeService.mergeAnnotations`); A30-3 does not apply
to Android. A30-2 was not checked on Android: its drafts are keyed by account name, with no
session count.

