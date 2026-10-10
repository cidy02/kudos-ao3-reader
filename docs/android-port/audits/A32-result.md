# A32 — Review of Claude's answers to A30

2026-10-10. Static review, complete for brief items 1–13. Android source references below are at `c4dc77b33f1ab0f4eb025b8ad234a9eab55cf3f1`, on `android/agent-codex-a32`; the requested commits `fe873221`, `c4e093db`, `ae05671e` and `e00575d6` were also read. iOS references are at `e1bbb8c52bce9a64d2a95f825978d706c0d0c808` in `/Users/cidy02/kudos-ios-polish`, read as committed code. A30 was read with `git show android/redesign-parity:docs/android-port/audits/A30-result.md`.

No builds, test runs, mutation testing, simulator inspection, sign-in, AO3 contact, branch changes, commits or pushes. “Fails without the fix” below means an assertion and its inputs distinguish the old code by source inspection; it does not claim I ran that experiment. Counterexamples involving returned trees and suspended operations are source-derived, not observations of live AO3. Only this report was written; TASKS and source files were left alone.

| Brief item | Verdict | Result |
|---|---|---|
| 1 / A30-1 | **not fixed** completely | Reply/Edit supersession is fixed; target and viewer changes still escape the count. |
| 2 / A30-5 | **fixed** | Explicit All selection replaces the pending operation; retry ownership is sound. |
| 3 / A30-6, A30-7 | **fixed** | Root-first byline and same-ID placeholder replacement are correct. |
| 4 / A30-10 | **not fixed** completely | `ae05671e` fixes the reported shared top-level root and keeps page-only replies; nested overlap still defeats the guarantee. |
| 5 / A30-11 | **not fixed** completely | Username is not session identity; the reader effect remains unfenced. |
| 6 / A30-12 | **fixed** | Count labels speak required; stacked Title labels drop the glyph. |
| 7 / A30-9 | **fixed** for the reported complete-list poisoning | Browse rejects the epoch entry; Search suggestions still consume it. |
| 8 / Android tests | **not fixed** completely | Strengthened tests are useful, but root precedence and several broader claims are not distinguished. |
| 9 / A30-3 | **fixed** | Replace's omitted preexisting marks no longer compete; their notes remain stored. |
| 10 / A30-4, both platforms | **fixed** | Same-ID revival replaces only a tombstone-suppressed local copy and parks displaced text. |
| 11 / A30-2 | **fixed but broke something** | Cross-launch owner collision is closed; new unnamed drafts become inaccessible after exit. |
| 12 / A30-8 | **fixed but broke something** | First-load cancel is fixed; returning to Browse leaves an abandoned request snapshot available to restore. |
| 13 / iOS tests | **not fixed** completely as a coverage claim | Two annotation tests and the changed draft test distinguish their fixes; the live-mark test deliberately passes old code. |

The two statements made before interruption: **confirmed**, the Android model keeps its chapter list by username rather than session (`CommentsViewModel.kt:320,324,327,330,334`); **confirmed**, the iOS Merge exception is correct for A30-4 (`KudosBackup.swift:3851–3879`). Details follow.

## 9 — A30-3: Replace exclusion is correct

`kudos-ao3-reader/Services/KudosBackup.swift:3939–3948`:

```swift
var removed = removeDeletedElsewhere()
if mode == .replaceLibrary {
    let inSnapshot = Set(contents.manifest.annotations.map(\.id))
    removed.formUnion(existing.map(\.id).filter { !inSnapshot.contains($0) })
}
dedupeSamePassageAnnotations(context: context, preexistingIDs: preexistingIDs, excluding: removed)
```

**Fixed.** The added set is exactly the preexisting IDs absent from the manifest. Replace's later omission pass uses the same manifest-ID test at `KudosBackup.swift:3436–3442`: `for annotation in allAnnotations where !snapshotAnnotationIDs.contains(annotation.id)`. Already hidden members need no new hiding and were already excluded by dedupe's live predicate (`:4030–4031`). The omission pass also sees freshly parked siblings, but those are born hidden (`:4002–4004`); that does not create a live omitted competitor outside the new exclusion. Incoming records have snapshot IDs. An empty annotation snapshot returns early (`:3836–3838`), with no dedupe, and the outer omission pass still hides the local marks.

The A30 input now leaves snapshot R live: L has the same passage, clock 300, and an ID absent from the snapshot; R has clock 100. L cannot win against R. L remains a row with its original note and is later soft-hidden, without minting a dedupe tombstone for R.

Skipping the old fill/park operation does **not** destroy L's note: the omitted row is retained, not hard-deleted. With an empty snapshot note, L's text no longer fills R; with two different notes, no extra sibling is needed because L itself survives hidden. This is consistent with Replace's snapshot choice. There is still no annotation recovery UI, as `parkDisplacedNote` documents at `:3964–3967`; do not describe retained bytes as a tap-to-restore feature. No smaller source fix is needed for A30-3. Add an assertion that the omitted row's note remains stored to make the preservation proof executable.

## 10 — A30-4: Merge exception is correct on iOS and Android

`kudos-ao3-reader/Services/KudosBackup.swift:3868–3879`:

```swift
if mode == .merge {
    guard case .suppressStaleData = tombstones.annotationResolution(
        id: local.id, incomingModifiedAt: local.lastModifiedAt
    ) else { continue }
}
if mode != .replaceLibrary {
    guard SyncMerge.shouldApplyIncoming(
        localModifiedAt: local.lastModifiedAt,
        incomingModifiedAt: incomingModifiedAt
    ) else { continue }
}
```

**Fixed.** Incoming suppression is checked first (`:3849–3857`). The admitted same-ID record can override Merge's add-only rule only when the local version itself resolves to suppression. For local=300, deletion=400, incoming=500, the local takes 500 before the sweep reevaluates it; it then survives. This updates the existing object rather than deleting it and using a stale `byID` reference.

`kudos-ao3-reader/Services/PersistenceSync.swift:618–624` gives the complete resolution rule:

```swift
guard let tombstoneDeletedAt else { return .noTombstone }
guard let incomingModifiedAt else { return .preserveAmbiguous }
return incomingModifiedAt > tombstoneDeletedAt ? .reviveNewerData : .suppressStaleData
```

| Incoming resolution | Same-ID Merge outcome |
|---|---|
| `reviveNewerData` | If local ≤ deletion, incoming > deletion also means incoming > local, so both guards pass. If local > deletion, Merge continues without overwriting it. |
| `preserveAmbiguous` | Unreachable for annotations on this path: `archived.lastModifiedAt ?? archived.createdAt` is a nonoptional Date (`KudosBackup.swift:3849`). There is no timestamp-less admitted annotation here. |
| `noTombstone` | The same ID and index also give local `noTombstone`; the exception does not fire. Local remains untouched even when incoming is newer. |
| `suppressStaleData` | Skipped before the exception. Equal-to-deletion is suppression, not revival. |

An ordinary live local mark nobody tombstoned is never overwritten by this exception. A local mark edited after deletion is likewise protected. If the admitted archived row itself carries deletion flags, those flags are copied (`:3905–3906`); this fix does not silently turn a newer deleted row into a live mark.

The displaced nonempty, different local note is still parked before assignment (`KudosBackup.swift:3892–3899`): `parkDisplacedNote(local.note, from: local, work: work, in: context)`. Its fresh UUID is not covered by the old ID's tombstone, and it is born hidden. Thus the sweep does not remove that text as the old mark.

Android `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt:2182–2197` implements the same exception:

```kotlin
} else if (mode == BackupImportMode.MERGE &&
    tombstoneIndex.annotationResolution(id, existing.effectiveLastModifiedAt) != TombstoneResolution.SUPPRESS_STALE
) {
    // Keep local note / locator / color.
} else if (mode == BackupImportMode.REPLACE_LIBRARY ||
    SyncMerge.shouldApplyIncoming(existing.effectiveLastModifiedAt, incomingModified)
) {
    if (id in preexistingIds && existing.note.isNotEmpty() && existing.note != restored.note) {
        parkDisplacedNote(existing, workId, byId, now)
    }
    byId[id] = restored.copy(createdAt = minInstant(existing.createdAt, restored.createdAt))
}
```

Incoming suppression is at `:2169–2174`, the post-update sweep at `:2202–2206`, parking at `:2237–2244`, and the same strictly-newer resolution rule at `:2540–2549`. Same rule on both platforms for the audited revival/add-only decision. This does not assert identical timestamp sanitization across the entire import pipeline. No source fix needed for A30-4; both new revival tests should additionally assert preservation of the old note on a hidden row.

## 11 — A30-2: owner isolation fixed, cross-launch draft retrieval regressed

`kudos-ao3-reader/Services/CommentSubmission.swift:353–355`:

```swift
private static let launch = UUID().uuidString
static func unnamedSession(_ generation: Int) -> String {
    "\(unnamedSessionPrefix)\(launch):\(generation)"
}
```

**Fixed but broke something.** The static token is made once per process, not once per call. Two calls with generation 3 within one launch agree; a later process has a different token. Production no longer constructs integer-only identities. The only literal `unknown-session:3` readers found are assertions in `KudosTests/CommentSubmissionTests.swift:571,582`; the generic store can still read an explicitly supplied identity, but no production path automatically supplies that legacy owner. `CommentDraftStore.move` matches the entire owner plus `|` (`CommentSubmission.swift:384–386`), so a new owner cannot match the old integer namespace or another launch's token.

All three within-launch handovers remain compatible:

- Verify Session: `kudos-ao3-reader/Services/AO3AuthService.swift:664–676` checks the expected generation/session, moves from `unnamedSession(expectedGeneration)` at `:673`, **then** increments generation.
- Restore: the generation/session guards and `finishAccepting` are at `AO3AuthService.swift:969–983`; the move at `:991` uses `unnamedSession(restoringGeneration)`. It uses this launch's same static token.
- Mounted Comments model: `kudos-ao3-reader/Features/Comments/CommentsModel.swift:245–248` checks `hasPrefix(unnamedSessionPrefix)`, and moves from the **captured full identity**, when the generation delta is 0 or 1. Adding a token does not defeat that prefix or change the generation arithmetic. New identities originate from the same helper at `CommentsModel.swift:30`.

No within-launch handover break caused by the token was found. However, Restore's comment claiming a draft from “the next launch” follows at `AO3AuthService.swift:985–987` is now false. Reproduction: launch A restores an unnamed session offline, reader types T, app exits before the account is named; launch B restores the same credentials and names Alice. B moves only B's token namespace. T remains in UserDefaults under A's token, with no production lookup or recovery surface. This also affects drafts written by the **new** implementation, not only ambiguous legacy integer keys. The contract above the store still promises drafts survive “an app exit” (`CommentSubmission.swift:359–360`).

Failing closed is the right safety choice compared with assigning unproven text to another account. Calling it a complete persistent-draft fix is wrong: the retrieval regression is deliberate and real. Smallest complete fix: store an opaque draft-owner token alongside the persisted session, retain it on restoration of those credentials, rotate it on replacement/sign-out, and use it for all three handovers. Keep ambiguous legacy integer owners unassigned; explicit recovery would be needed to reclaim those safely. Do not recover them by moving every unnamed prefix. Update the misleading Restore/store comments if the launch-only trade is retained.

## 12 — A30-8: Apply survives, abandoned first-request filters can return

`kudos-ao3-reader/Features/Search/SearchView.swift:271–273`:

```swift
guard !showing, var restored = loadedFilters ?? requestedFilters else { return }
restored.query = filters.query
if filters != restored { filters = restored }
```

**Fixed but broke something.** First-load cancellation now has a snapshot: `load` records `requestedFilters = current` synchronously at `:884–885`, before creating its Task. Apply calls `runSearch` (`:664`), which synchronously clears `loadedFilters` and calls `load(page: 1)` (`:744–756`). By the time SwiftUI delivers the close change, the fallback is Apply's new filters; closure does not undo a searchable Apply. A later search overwrites `requestedFilters`, and old answers cannot overwrite `loadedFilters` because of `token == loadToken` (`:896,901`). Back to a captured history level also sets `loadedFilters = previous.filters` (`:693`), which takes precedence over the fallback.

The new hole is an abandoned request, not a superseding successful search. `SearchView.swift:708–718` does this on Back:

```swift
loadToken += 1
filterHistory.removeAll()
filters = AO3SearchFilters()
results = []
// ...
phase = .idle
```

It clears neither snapshot. Concrete input: in a fresh Search view, Apply filters A with fandom Doctor Who; hold the first answer, so `loadedFilters == nil`. Tap Back to Browse. The token invalidates A but `requestedFilters == A` remains. Open the still-available filters panel in Browse, edit it, then close without Apply. The handler restores A's fandom/completion/sort, retaining only the newly typed query. The next Search AO3 action sends abandoned A filters; A's late response itself is correctly discarded. Before this change the fallback was nil and this first-request Back case could not restore A.

Smallest fix: clear both `loadedFilters` and `requestedFilters` when discarding the search in `returnToBrowse`; apply the same snapshot-reset rule to other transitions that deliberately reset filters/results to idle (`clearQuery`, `clearAllFilters`, panel Reset at `:613–633,666–674`). An active newer request already replaces the snapshot correctly. Add a state/view regression for Apply → pending → Back → panel close; no test for this new handler was added in `e1bbb8c5`.

## 13 — iOS tests: three distinguish old behavior, one is a guardrail

All paths below are in `/Users/cidy02/kudos-ios-polish` at `e1bbb8c5`.

| Test and evidence | Would fail with its fix removed? | What it actually proves / smallest improvement |
|---|---|---|
| `KudosTests/TombstoneSweepsExistingRecordsTests.swift:334`, `replaceKeepsTheSnapshotsMarkAgainstANewerLocalOneOnTheSamePassage` | **Yes**, without Replace's exclusion. | Distinct IDs, same locator, local clock 300, incoming 100; `liveNotes == ["in the snapshot"]` at `:352` becomes no live mark in old code. Does not assert retained local note or absence of a new tombstone for incoming. Add those assertions. |
| Same file `:358`, `mergeTakesAMarkBroughtBackAfterItsDeletionWhenTheCopyHereIsTheDeletedOne` | **Yes**, without the Merge exception. | Same ID, local 300, trusted/signed deletion 400, incoming 500; `:380` expects the revived live note. Old Merge skips then sweeps. Does not assert parked old text; add that assertion. |
| Same file `:384`, `mergeStillLeavesALiveMarkHereAlone` | **No**: it passes the parent implementation as well. | No tombstone, same ID, newer incoming; `:403` expects "mine". This is a necessary guardrail against an overbroad exception, not a baseline-failing test for the original fault. Claude's “each new test fails with its fix taken out” claim is wrong for this test. Keep the test; correct the claim. |
| `KudosTests/CommentSubmissionTests.swift:552`, `anUnnamedSessionsDraftsMoveToTheAccountThatIsThenNamed` | **Yes**, restoring the old integer-only helper. | `unnamedSession(3)` would equal the deliberately seeded legacy owner; `move` would move the unrelated work-43 draft too, failing `:581–582`. It also checks same-launch equality, different generations and concatenated destination drafts. It does **not** exercise either auth service handover, the model handover, or two actual launches. A permanent fixed token would pass it too. Add a controllable owner-token/launch seam when implementing durable ownership; test separate owners and same-session restoration, rather than claiming this is a restart test. |

## 1 — A30-1: the count fences composer changes, not all context changes

`android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsViewModel.kt:421,434–436` now captures an opening count and checks it before assigning the work draft:

```kotlin
val opening = ++composerGeneration
// ... getDraft ...
if (composerGeneration != opening) return@launch
_draft.value = stored
_composerPresented.value = true
```

Reply and Edit advance the same count (`:477,508`), as do close/cancel and verified success (`:444,501,518,577`). Reply's lookup tests that count at `:492–493`. `present` checks the count, current target, no reply/edit and no presented sheet (`:291–305`). Thus the exact A30 Write → Reply/Edit interleaving is fixed, and no replacement of a later Reply/Edit draft was found through that old path.

**Not fixed completely:** `setTarget` changes `_currentTarget` and calls `load`, without advancing the count (`:632–635`). Neither a username change nor a session-generation change is observed by the model. `openComposer` and `startReply` do not compare their captured target/viewer when their independent jobs finish (`:420–436,476–495`). The model still says the count covers “every change of what it is for” (`:125`); that claim is false.

Concrete taps: loaded work W, stored work draft T; tap Write a comment and suspend its datastore read before the sheet appears. The list and chapter pill are still available (`android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsScreen.kt:310,477–485,654–669`). Choose chapter C from the picker. That changes the target and starts a page load, but not the opening count. Release the work lookup: T opens in the now-chapter composer. `saveDraft` takes the **current** target (`CommentsViewModel.kt:455–464`), so typing/dismissing can save T into C's draft slot; `submitComment` also passes the new target at `:551,571`. The eventual POST endpoint additionally depends on the returned form action (`network/ao3/comments/AO3CommentRepository.kt:121–124`), so this review does not assert that every such POST necessarily lands on C. The wrong displayed/stored draft is already established. This does not require interacting through an already-presented modal sheet.

A target can also move while a sheet is open: the independent reader effect resolves `chapterForPosition` and calls `openOnChapter` (`CommentsScreen.kt:141–147`), whose `setTarget` has no composer fence. For a programmatic target/scope change with a sheet already open, `load` deliberately retains its reply/edit context (`CommentsViewModel.kt:175–179`) while save/submit use the new target. Scope taps behind a modal sheet were not presumed reachable; the pending-open and reader-effect paths are enough.

Viewer counterexample: draft read starts under Alice, auth becomes Bob before it returns, no composer open/close occurs. The result has the same count and is accepted. `CommentsScreen.kt:120–124` updates only the username lambda, and keys the model by work; there is no auth epoch check. A same-name credential change likewise cannot be represented by this count.

Ordinary `load` on the same target with an open reply/edit and a failed submit should **not** advance the count merely for reloading: it preserves that composer by design. Failure at `CommentsViewModel.kt:592–605` does not change its context, including an unconfirmed-post reload. No unnecessary count bump was found there. A legitimate close discards a pending lookup, and reopening reads that slot afresh.

There is a separate way a count bump can discard the *new* composer: a successful old submit unconditionally increments and clears at `:575–582`, even if the sheet was swipe-dismissed and a different composer opened while the POST was out. Modal dismissal still invokes `onDismiss` during submitting (`android/app/src/main/java/io/github/cidy02/kudos/comments/CommentComposerSheet.kt:101–104`); only the Cancel button is disabled (`:119–121`). The clearing predates this fix, so it is not a new regression from the count. It remains an unfenced submit completion.

Smallest complete fix: capture the composer target, owner/session and generation at open/submit; save and submit using that captured context, and invalidate/reopen explicitly on target or auth-context change. Guard every lookup with that context, not count alone. On submit completion, clear only the composer generation that submitted, while clearing the successful draft in its captured owner slot. Do not bump the count for a same-context reload or an ordinary failed submit.

## 2 — A30-5: explicit selection has one load owner

**Fixed.** `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsViewModel.kt:360` and `:633` make their no-op conditional on `pendingChapterComments == null`:

```kotlin
if (_scope.value == next && pendingChapterComments == null) return
// ...
if (_currentTarget.value == target && pendingChapterComments == null) return
```

Choosing All now invokes `setTarget` once, then `load` clears pending synchronously at `:171` and cancels the previous `loadJob` at `:182`. The old Chapter Comments operation checks `ensureActive()` after both reads (`:227,244`). Two physical requests may already have started when the choice cancels one, but there are not two live publication owners or two new loads from the one scope tap. Repeated same-target taps after pending was cleared return normally.

The paired request survives thread/chapter failures (`:237,245–247`), and `retry()` repeats it (`:159–162`). Explicit target selection intentionally clears it: subsequent Retry belongs to the selected ordinary page, not the Inbox request the user abandoned. `setScope(ByChapter)` with no selected chapter cannot create a target and leaves the pair alone; the actual picker uses All or `selectChapter(chapter)`, not that unresolvable call (`CommentsScreen.kt:297–303`). No new retry-loss bug found. No source fix needed; make the cancellation test hold the second read explicitly (item 8).

## 3 — A30-6/A30-7: chapter resolution and placeholder replacement

**Fixed.** `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsViewModel.kt:271–272`:

```kotlin
private fun firstNamingChapter(comment: AO3Comment): AO3Comment? =
    if (comment.chapterId != null) comment else comment.replies.firstNotNullOfOrNull(::firstNamingChapter)
```

The root wins when it names a chapter. Otherwise depth-first traversal finds the first named descendant, rather than privileging the focused reply. That same comment provides the label number at `:254–255`: `Regex("\\d+").find(it)?.value?.toIntOrNull() ?: position`. Inbox position 8 and root byline Chapter 3 now select chapter 77 with number 3. Overflow/unparseable/absent number falls back to the Inbox hint; no unrelated chapter-ID digits are taken from a URL because the regex reads the byline text.

`CommentsViewModel.kt:337–338` replaces only an index record matching the **currently selected chapterId**:

```kotlin
res.value.firstOrNull { it.chapterId == chosen.chapterId }?.let { _selectedChapter.value = it }
```

It does not call `selectChapter` or `setTarget`. A delayed index cannot reverse a newer selection: `chosen` is read after the suspension, and matching is by that chosen ID. If absent in the index, the placeholder remains. Changing its title/position does not change the target or start a comment load. The initial-null fallback also only fills selection (`:340–347`). No source fix needed here; tests do not yet distinguish conflicting root/reply chapter IDs or assert the delayed same-ID repair (item 8).

## 4 — A30-10: reported root overlap fixed, universal uniqueness is not

`android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsViewModel.kt:258–267` now selects the missing requested comment itself when the page has the thread's top-level root:

```kotlin
onPage == null || findCommentRecursive(onPage, commentId) != null -> null
onPage.any { it.id == root.id } -> findCommentRecursive(listOf(root), commentId)
else -> root
```

**Not fixed completely.** Withdraw the concern that the *current* implementation replaces the page root and loses its page-only replies: that was true of `fe873221`, and `ae05671e` corrects it. For thread A(B), page A(X), requested B: presentation is B followed by the page's intact A(X). It contains A, B, X once each. The strengthened test now asserts X (`comment_9`) remains. The page's fields, replies and cutoff information on A are retained. Data held only in the thread on some other sibling is not merged into A; this is the documented choice to put the requested comment first by itself, not evidence of dropping a page reply.

The membership check is only top-level. `present` at `:287–288` still prepends `first.without(onPageIDs)`, and `without` at `:277–278` still tests only **children**, never the first node:

```kotlin
copy(replies = replies.filter { it.id !in ids }.map { it.without(ids) })
```

Two returned-tree counterexamples distinguish the remaining gap:

1. Standalone tree root B with requested child C; chapter page root A containing B without C. `onPage.any(root.id)` is false, so first=B. `without` keeps B itself although B is already under A. With shallow replies, rendered keys contain `post-comment_B` twice. The recursive parser accepts these tree shapes (`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/comments/AO3CommentParser.kt:118–155`); there is no repository normalization. `CommentThreadGeometry.kt:121` builds `"post-${comment.id}"`, and `CommentsScreen.kt:590–592` uses it directly. Folding may temporarily hide the nested occurrence; expansion reveals it.
2. Standalone R → B → C, requested C; chapter page contains B but neither R nor C. The else branch prepends R; filtering B deletes **its entire subtree**, including the requested C. The page stays whole but the Inbox comment disappears from the result. This is a pruning problem, not a duplicate already present in AO3's response.

Smallest fix for those combined-tree cases: choose the requested missing subtree whenever the surrounding thread overlaps the page, checking the complete recursive ID set rather than only top-level roots; alternatively merge/lift missing descendants without dropping their missing children. The first node itself must be proven absent before prepending. Assert actual `CommentConversationBuilder.rows(...).map { it.id }`, as well as presence of the requested comment, on the two shapes above. No live AO3 reproduction is claimed.

The demo's original `/comments/1002` collision **is fixed** by `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/DemoNetwork.kt:319`: `if ("id=\"$asked\"" in page) bytes else ...`. An existing requested ID now leaves the fixture untouched, so root 1001 is not renamed onto reply 1002. It still returns the whole multi-root fixture rather than selecting the requested thread, but IDs within that supplied fixture stay unique.

**Unchanged:** absent-ID demo rewriting still leaves numeric action/parent URLs inconsistent (`DemoNetwork.kt:319`; `android/app/src/debug/assets/fixtures/ao3_comments_page.html:54–55`), so “coherent single-comment page” is too broad; select/build the requested subtree and rewrite its matching addresses together.

## 5 — A30-11: username is not a viewer session

`android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsViewModel.kt:320–334`:

```kotlin
private var chaptersViewer: String? = null
val viewer = currentUsername()
if (chapterIndexRepository == null || (_chapters.value.isNotEmpty() && chaptersViewer == viewer)) return
// ...
if (currentUsername() != viewer) return@launch
_chapters.value = res.value
chaptersViewer = viewer
```

**Not fixed completely.** The ordinary guest-null → named-Alice case now reloads when the picker is tapped, and a null-read completion after the name changes is discarded. That is the narrower case its test proves. The old guest list remains visible while the new read runs, and on failure; no auth-change reset was added.

Confirm the interrupted statement: these lines store a **username**, not a session ID/generation. After a list is read as Alice, signing out and back in as Alice without reopening the picker while signed out leaves `chaptersViewer == "Alice"`; the next call returns early and never consults the repository's new generation. A suspended parse/cache return from Alice session 1 can also publish into Alice session 2 because the completion guard compares only the same name. Same account name does not prove the same credential generation or permissions.

An unnamed held session also cannot be identified by this string. If the callback reports null it is indistinguishable from guest; `AO3ChapterIndexRepository.kt:32` even chooses anonymous access from `username() != null`. If represented by blank `""` (the session model's username is a String, `android/app/src/main/java/io/github/cidy02/kudos/auth/AO3Session.kt:114–117`), two unnamed sessions share that name, so the model's cache still collides. The production screen reads published `SignedIn.username` (`AO3AuthState.kt:12–13`; `AppNavHost.kt:1114–1118`), whereas the repository reads the held session username (`auth/AO3AuthRepository.kt:119,282`), which can exist during Restoring. They are not the same identity source.

**Unchanged:** the reader effect still keys only on position/work and applies `chapterForPosition` without an auth-context check (`android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsScreen.kt:141–147`), so a guest index completing after sign-in can still call `openOnChapter`.

Smallest complete fix: pass one captured published auth context with generation/session identity to the mounted model and reader effect; clear retained chapters/selection on context change, reload for the new context, and fence publication after index parsing and cache return. Key the reader effect by that context and preserve the user's subsequent explicit chapter choice. Keep named-session reads authenticated and do not cure failures with anonymous retries. The repository's existing `(workId, generation)` map is useful, but cannot fix a model that skips calling it.

## 6 — A30-12: every current caller whose spoken label changes

**Fixed.** `android/app/src/main/java/io/github/cidy02/kudos/ui/subject/SubjectForm.kt:127,162` defaults `labelSpokenByControl = false` and passes that explicit flag to `spokenAs`. The non-field count no longer suppresses “required.” `android/app/src/main/java/io/github/cidy02/kudos/settings/SettingsChrome.kt:174–177` explicitly marks the field's accompanying label as spoken by its control in both stacked and inline paths; the field itself still has `spokenFormLabel(label)` at `:157`.

Production suffix/caller search found these changed announcements, and no other current marked callers:

| Caller | Before → after |
|---|---|
| `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingEditTagsScreen.kt:147–148`, Fandoms count row | Label description “Fandoms” → “Fandoms, required.” The count Text has no required announcement of its own. |
| `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingWorkFormScreen.kt:238`, Title via `SubjectTextFieldRow` when multiline/stacked/accessibility-scale layout applies | Visible label's raw “Title ∗” → label description “Title.” The input still says “Title, required.” This caller is single-line normally; large font scale selects stacked layout (`SettingsChrome.kt:129`). |

Inline Title already said “Title” alongside its speaking field and stays so. Work form Archive warnings and Fandoms (`WritingWorkFormScreen.kt:242,245`) use values without trailing controls and already said required; unchanged. Unmarked labels return the same modifier (`SubjectForm.kt:108`), so optional text fields, counts, switches and dynamic labels without the suffix do not change. No current caller passes `labelSpokenByControl=true` on a stacked value row, so that separate branch's default at `:145` creates no current regression. Visible labels and action callbacks are untouched. No source fix needed; add semantic assertions for Edit tags' count and large-text Title label, which the field-only assertions do not establish.

## 7 — A30-9: stale seed is not a Browse fallback

**Fixed for the reported full-category result.** `android/app/src/main/java/io/github/cidy02/kudos/app/DemoLibrary.kt:306` seeds `FandomCatalogCache.Entry(listOf(AO3Fandom("Doctor Who", 42)), 0L)`. `network/ao3/browse/AO3BrowseRepository.kt:54–55` serves only `!FandomCatalogCache.isStale(entry, now)`, and `:61–69` returns the GET/parse result; it does not use the stale entry on network, refusal or parse failure. With the present clock, epoch zero is far beyond seven days (`FandomCatalogCache.kt:74–78`). No stale-cache fallback was found in that Browse path.

The Privacy figure intentionally still counts the file's bytes: `android/app/src/main/java/io/github/cidy02/kudos/settings/LocalDataFootprint.kt:78` uses `fileSize(cacheRoot.resolve("fandom-catalog.json"))`, and `PrivacyDataScreen.kt:131–134` displays `footprint?.cacheBytes`. Stale bytes occupy storage, so including them is correct; it does not assert the entries are live.

There is another consumer: `android/app/src/main/java/io/github/cidy02/kudos/search/SearchScreen.kt:182–184` loads **all** entries into local AO3 fandom suggestions without checking age:

```kotlin
val loaded = fandomCatalogCache?.load().orEmpty()
viewModel.setCatalogFandoms(loaded.values.flatMap { it.fandoms })
```

Thus after a demo seed and a non-demo launch, typing Doctor Who can still show its fake count 42 in cached suggestions (`SearchScreen.kt:911–915` renders `fandom.workCount?.compactCount()`). Old legitimate catalog entries can reasonably remain useful suggestions, but an epoch date alone does not label this fake entry as demo-only. This residual is not a new full-category regression caused by the date change. Smallest complete isolation fix remains a demo-only cache namespace (and matching demo measurement), rather than expiring all useful cached suggestions. Add a normal Search consumer assertion if claiming no demo metadata escapes.

**Unchanged:** installs already seeded with a fresh timestamp are not repaired because `DemoLibrary.kt:303` still skips an existing file.

## 8 — Android tests: fault sensitivity and gaps

### `c4e093db`

| Test | Verdict against the fault named |
|---|---|
| `android/app/src/test/java/io/github/cidy02/kudos/writing/WritingChapterDeleteTest.kt:76`, `secondTapWhileTheDeletePostIsHeldSendsExactlyOneDelete` | **Fixed.** `beforePostResponse` holds the POST at `:80`; `:84` asserts busy, and `:86–89` attempts Delete/Save/Preview and checks no extra reads/POSTs. Releasing busy after the confirm read would fail the busy assertion and/or permit more operations. This now exercises the POST interval rather than just GET. |
| `android/app/src/test/java/io/github/cidy02/kudos/writing/WritingChapterFormScreenTest.kt:139`, `aPostedChapterOffersOnlySaveChapterChangesAndSendsUpdate` | **Fixed** for the actual posted-form actions. Opens `"posted"`, reaches Save, rejects Post/draft/direct-post controls, taps Save and checks only `update_button` at `:147`. Wrong dispatch fails. Compose's negative assertions only inspect nodes currently composed; they are not an exhaustive proof that no incorrectly inserted action exists elsewhere offscreen. If broadening that claim, scroll through the entire action area. |
| `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/writing/AO3ChapterFormTest.kt:26`, `untouchedModeledFieldsMatchBrowserExceptSubmitLabelAndReplayIsExact` | **Fixed.** Counts at `:42–46` can fail for duplicate/missing token, submit, title or body, or duplicate method. Earlier independent browser/replay comparisons at `:37–39` also reject wrong values and replayed extras. `_method <= 1` alone permits absence, but the edited-form browser comparison rejects absence when required. Unlike the removed disjoint-set assertion, these are not tautologies. |

### `fe873221`, with `ae05671e`'s test update

All following comment tests are in `android/app/src/test/java/io/github/cidy02/kudos/comments/CommentsViewModelDraftTest.kt`.

| Test / line | Verdict and limit |
|---|---|
| `aNewCommentsLateDraftNeverLandsInTheReplyOrEditOpenedAfterIt` `:470` | **Fixed**, distinguishes the old unguarded work lookup. The StandardTestDispatcher queues that job; Reply/Edit advance generation before it runs. Without the guard, `:484`/`:493` sees the work text instead of reply/edit text. The final untouched open at `:499–500` verifies lookup still works. It does not hold a lookup already suspended, change target/viewer, or test submit completion. Smallest strengthening: explicit delayed draft seam and target/auth changes from item 1. |
| `allCommentsChosenWhileChapterCommentsLoadIsNotReplacedByTheChapter` `:345` | **Fixed** for same-scope/same-target early returns: assertions at `:359–363` require an ordinary work load and no chapter URL. It stops the **first** thread read during background parsing, not the chapter-page read. The fake GET returns immediately (`:543`); there is no explicit barrier, so `runCurrent(); assertEquals(1, urls.size)` also depends on worker timing. Hold both relevant reads deliberately; add pending-second-read and failed-selection→Retry cases. |
| `chapterCommentsFromTheInboxPutTheInboxThreadFirstAndReadItOnce` `:264` (changed hint at `:272`) | **Fixed** for stale Inbox numbering. Hint 8 versus byline 3 makes `:283` fail with the old placeholder. Covers requested root already on/off page. Does not supply a conflicting named reply or load the index later. |
| `aRootTheChapterPageHoldsWithoutTheReplyIsDrawnOnceAndTheBylineNamesTheChapter` `:320` | **Fixed** for top-level overlap and numbering, **not fixed** as proof of A30-7. Current `:335–338` catches duplicate root keys and the old replacement's lost page-only `comment_9`. But only the root is given chapter metadata (`:323`); focused reply has none, so the old `focused.chapterId ?: root.chapterId` returns 77 too. It cannot fail for reply-over-root precedence. Add root=77/reply=88, and assert request 77; also assert the delayed index repairs number/title without a new GET. |
| `aChapterListReadAsAGuestIsReadAgainOnceTheReaderIsSignedIn` `:368` | **Fixed** for the original nonempty-list early return: null→Alice produces size 1→2 at `:393–396`, which old code cannot. **Not fixed** as session-isolation coverage: fake generation is always 1 (`:374`), calls are sequential, and it invokes the model directly. Cannot detect same-name session changes, stale publication, retained rows on failure, unnamed sessions or the reader effect. Add generation changes and held parse/index completions. |

No tests for `demoCommentThreadPage`, epoch seeding, changed Fandoms-count semantics or stacked-label semantics were added by `fe873221`; the listed comment tests do not exercise those paths. Its `AccountShortcutsScreenTest.kt:69` change adds a wait for `Remove Inbox`, preserving the existing removal assertions; it addresses readiness timing, not an A30 correctness regression.

The later Android revival test, `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupMergeParityTest.kt:361`, **does distinguish** old Merge: local 100, signed deletion 200 (`:449` helper), incoming 300, assertion `:367`. Old Merge skips then sweeps. Its Reconcile iteration and no-tombstone “mine” assertion also pass old code and are guardrails. It checks live notes, not the parked displaced note; add that assertion.

## Remaining verification

All requested numbered items were source-reviewed. The report does not certify runtime rendering, real AO3 folding/permissions, test scheduling stability, or test/build success. Prior A30 findings outside this brief were not repeated or re-audited. The fixes still needing changes are composer target/session ownership, complete tree-overlap handling, mounted chapter-session ownership, durable unnamed-draft retrieval, and Search snapshot invalidation on abandonment. The demo catalog's broader isolation and the named test gaps remain explicitly limited above.
