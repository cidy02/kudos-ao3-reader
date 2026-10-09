# Audit A27 result

Read-only. iOS is `/Users/cidy02/kudos-ios-polish` on `claude/polish-loop` at `d18a313e` ("T-366: a deletion made on another device removes the copy here"). Lines below are that tree. Nothing there was modified. Android is cited only where T-366 says it copied a rule that already landed (`android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt`, `docs/android-port/briefs/3bs-result.md` item 7).

Folder sync calls `restore` in `.reconcile` (`KudosBackup.swift:2104-2108`). File import is `.merge`. A snapshot is `.replaceLibrary`. A tombstone is adopted only when `TombstoneSigning.shouldAdopt` accepts it: non-empty signature, signature verifies, signer already trusted (`TombstoneSigning.swift:126-132`). Unsigned and untrusted records are not indexed. `SyncTombstone.lastModifiedAt` is the signed `createdAt` (`Models.swift:104`). `SyncMerge.tombstoneResolution` suppresses when the incoming clock is missing-or-not-strictly-newer than that instant; a strictly newer clock revives (`PersistenceSync.swift:618-625`). Equal clocks suppress.

`applyTombstonesToExisting` returns immediately in Replace (`KudosBackup.swift:3582-3588`). The comment there says the incoming loop already has the same guard. Bookmarks, saved searches, reading sessions, favorites, and fandom watermarks do. Queue memberships and annotations do not. A collection or custom queue that is not already in the store does not either (A27-4). Works do (`:2417`).

| id | severity | file:line | statement |
| --- | --- | --- | --- |
| A27-1 | P1 | `kudos-ao3-reader/Services/KudosBackup.swift:3163` | A saved link removed on the other device stays here when the two devices never shared that link's id. The address check runs only while the archive still lists the link. |
| A27-2 | P1 | `kudos-ao3-reader/Services/KudosBackup.swift:3047` | A queue removal does not settle when the membership ids differ. Saved for Later always remaps onto this device's queue, and an existing row keeps its local id. |
| A27-3 | P1 | `kudos-ao3-reader/Services/KudosBackup.swift:3911` | Dedupe runs before the new annotation sweep and can destroy both copies of one passage, including the copy the other device still had. |
| A27-4 | P2 | `kudos-ao3-reader/Services/KudosBackup.swift:3836` | Replace still refuses an annotation, a queue membership, a collection, or a custom queue that a local tombstone covers, so a snapshot that contains it does not bring it back. |
| A27-5 | P1 | `kudos-ao3-reader/Services/KudosBackup.swift:2722` | A collection-membership tombstone is the XOR of this device's work UUID. The same fic downloaded separately on each device never matches, so the removal does not settle. |
| A27-6 | P2 | `kudos-ao3-reader/Services/KudosBackup.swift:2713` | One `lastMembershipChangedAt` covers the whole collection, so any later membership edit keeps every work a tombstone had already removed. |
| A27-7 | P1 | `kudos-ao3-reader/Services/KudosBackup.swift:3683` | Unstarring a favorite, or clearing a fandom watermark, does not settle when the two devices created that row before any sync. The sweep looks up the id only. |
| A27-8 | P2 | `kudos-ao3-reader/Services/AO3AuthService.swift:981` | Launch restore names an "AO3 Account" session and does not move its comment drafts. A later Verify Session skips them because the username is no longer empty. |
| A27-9 | P2 | `kudos-ao3-reader/Features/Bookmarks/AO3AccountWorksList.swift:1299` | An older account-list load that ends in `authenticationRequired` ignores `loadToken` and clears the page a newer load already showed. |
| A27-10 | P2 | `kudos-ao3-reader/Features/Search/SearchView.swift:263` | Search drops unapplied filters only while `phase == .loaded`. Dismissing the panel during a load or a failure keeps the edits, and the next page sends them. |
| A27-11 | P2 | `kudos-ao3-reader/Features/Account/AccountShortcuts.swift:91` | Removing every shortcut stores `""`. The decoder treats that as "never chosen" and puts the six defaults back. The footer's empty grid cannot happen. |

## A27-1 A saved link with a different id survives the other device's deletion

`kudos-ao3-reader/Services/KudosBackup.swift:3131-3168`

```swift
var suppressedBookmarkIDsByURL: [String: UUID] = [:]
for archived in contents.manifest.bookmarks {
    if mode != .replaceLibrary {
        switch tombstones.bookmarkResolution(
            id: archived.id,
            incomingModifiedAt: archived.dateAdded
        ) {
        case .suppressStaleData:
            suppressedBookmarkIDsByURL[archived.urlString] = archived.id
            continue
        case .reviveNewerData, .preserveAmbiguous, .noTombstone:
            break
        }
    }
    // ... match by urlString, keep the local id ...
}
applyTombstonesToExisting(existingBookmarks, in: context, mode: mode) { bookmark in
    if case .suppressStaleData = tombstones.bookmarkResolution(
        id: bookmark.id, incomingModifiedAt: bookmark.dateAdded
    ) { return .suppressStaleData }
    guard let archivedID = suppressedBookmarkIDsByURL[bookmark.urlString] else { return .noTombstone }
    return tombstones.bookmarkResolution(id: archivedID, incomingModifiedAt: bookmark.dateAdded)
}
```

Checked against the deletion record, which stores the bookmark id and no URL (`PersistenceSync.swift:452-462`), and against Android's copy of the same shape (`BackupMergeService.kt:1001-1040`): the URL is removed only when the snapshot still contains that link and its id is suppressed; the second pass matches `link.id` only. T-366's comment at `KudosBackup.swift:3157-3162` says a different local id is tested against the address. That map is filled only inside the loop over bookmarks the archive still contains. A real delete omits the row and sends the tombstone. `briefs/3bs-result.md` item 7 described the second pass iOS was then missing. The pass is there for a shared id. The address case it also described still needs the link to be inside the archive.

`KudosTests/TombstoneSweepsExistingRecordsTests.swift:161` (`aTrustedTombstoneRemovesASavedLinkButNotOneSavedAgainLater`) uses one id and an empty bookmark list. It stays green if the address rule is absent. `replaceLibraryDoesNotSweepExistingSavedLinks` covers the Replace bypass, which does hold for bookmarks.

**Failing case.** Both devices save `https://archiveofourown.org/works/1` before any sync. The local ids differ. Date Added on both is older than the deletion. On device B, delete the link. B writes a signed `.bookmark` tombstone for B's id and exports no bookmark. Folder sync. Device A adopts the tombstone. `suppressedBookmarkIDsByURL` stays empty. The sweep asks `bookmarkResolution` for A's id, misses, and leaves the row. A's next export publishes A's id. B has no tombstone for that id and inserts it. The link returns on B. A should drop its link when Date Added is not strictly newer than B's tombstone, and A's next export should carry a deletion that covers that address.

**Smallest fix.** Put the canonical URL on the bookmark tombstone (`sourceURL` is inside the signed payload, so only new tombstones) and, in the sweep, suppress a local bookmark whose URL matches, using that row's `dateAdded`. Keep the Replace early-return in `applyTombstonesToExisting`.

## A27-2 A queue membership with a different id survives the other device's removal

`kudos-ao3-reader/Services/KudosBackup.swift:2997-3050`

```swift
if let existing = work.queueMemberships.first(where: { $0.queue?.id == queue.id }) {
    // ... maybe copy sort order and note ...
    work.isQueuedForLater = true
    continue
}
let membership = ReadingQueueMembership(
    id: archived.id,
    queue: queue,
    work: work,
    // ...
)
// ...
let membershipsAfterRestore = (try? context.fetch(FetchDescriptor<ReadingQueueMembership>())) ?? []
applyTombstonesToExisting(membershipsAfterRestore, in: context, mode: mode) {
    tombstones.membershipResolution(id: $0.id, incomingModifiedAt: $0.lastModifiedAt)
}
```

Saved for Later never follows a queue tombstone. It is forced onto this device's singleton (`KudosBackup.swift:2780-2785`). An existing membership is found by local queue id plus work object and keeps its UUID. The new sweep then looks up that UUID only. `ReadingQueueMembership` sets `lastModifiedAt = queuedAt` at init, so the sweep's clock is real for a row nobody has edited. A queue hard-delete tombstones each membership id and then deletes the queue (`PreservedWorkService.swift:157-166`); it does not give the surviving device a key it can match.

`aTrustedTombstoneRemovesAQueueMembershipButNotOneChangedLater` (`TombstoneSweepsExistingRecordsTests.swift:223`) uses one shared id. It stays green when the ids differ.

**Failing case.** Both devices add the same downloaded work to Saved for Later before any sync. Membership UUIDs differ. On B, remove it from the queue. B tombstones B's membership id. Sync. A's sweep misses A's id. The work stays in Saved for Later and A's next export publishes A's membership. B inserts that id, because B's tombstone names the other one, and the work is back in B's queue. The same loop happens for a custom queue both devices already share, when each device adds the work while offline. Removing it on B should remove it on A when A's `lastModifiedAt` is not strictly newer, and A's export should not republish a membership B has removed.

**Smallest fix.** When the incoming loop finds an existing membership for the same queue and work, and the archived id is suppressed on the local clock, delete the local row. For a membership the archive omitted, key the tombstone by something both devices share (queue kind or queue id, plus the work's AO3 id) and have the sweep consult that key. Do not key Saved for Later by the queue UUID.

## A27-3 Dedupe before the annotation sweep deletes both copies

`kudos-ao3-reader/Services/KudosBackup.swift:3816-3823` and `:3911-3912`, with the loser path at `:4028-4036`

```swift
func removeDeletedElsewhere() {
    applyTombstonesToExisting(existing, in: context, mode: mode) {
        tombstones.annotationResolution(id: $0.id, incomingModifiedAt: $0.lastModifiedAt)
    }
}
// ... merge loop ...
dedupeSamePassageAnnotations(context: context, preexistingIDs: preexistingIDs)
removeDeletedElsewhere()
```

```swift
SyncTombstones.recordDeletion(of: loser, in: context, reason: "samePassageDeduped")
if preexistingIDs.contains(loser.id) {
    loser.isPendingDeletion = true
    loser.deletedAt = Date()
    loser.markModified()
} else {
    context.delete(loser)
}
```

`existing` is fetched once, before the merge (`KudosBackup.swift:3809`). The sweep walks those same objects, so a later `lastModifiedAt` write is visible, and a row inserted by this restore is not in the sweep. Dedupe groups by work id, kind, and exact locator, keeps the newest `lastModifiedAt`, tombstones every loser as `samePassageDeduped`, hard-deletes a loser this restore just inserted, and soft-deletes a pre-existing loser while stamping `lastModifiedAt` to now (`:4028-4036`). The sweep's index was built at the start of restore and does not contain that new dedupe tombstone. An empty annotation list still sweeps and returns (`:3821-3823`), so a same-id delete whose work is absent from the archive is removed. `aTrustedTombstoneRemovesAHighlightButNotOneEditedLater` (`TombstoneSweepsExistingRecordsTests.swift:188`) uses `works: []` and one id. It never builds two rows on one locator.

**Failing case.** Device A has highlight Local at locator L, `lastModifiedAt` 300. Device B has highlight Remote at the same locator, modified 100, and a trusted tombstone for Local at 400 (A had previously synced Local, B deleted it, then B made Remote). B's archive still lists Remote. Sync onto A. Dedupe ranks Local newer, hard-deletes Remote, and tombstones Remote as `samePassageDeduped`. The sweep then deletes Local because 300 is not newer than 400. Both marks are gone. A's next export carries the dedupe tombstone for Remote, so B loses Remote too. Running the sweep first would delete Local and leave Remote.

**Smallest fix.** Call `removeDeletedElsewhere()` before `dedupeSamePassageAnnotations`. Do not tombstone or hard-delete a row the sweep is about to remove.

## A27-4 Replace still suppresses an annotation, a membership, a collection, or a queue

`kudos-ao3-reader/Services/KudosBackup.swift:3836-3840`, `:2953-2962`, `:2565-2572`, and `:2795-2804`. The helper that does skip Replace is `:3574-3588`. Works skip resurrection only outside Replace (`:2417`).

```swift
switch tombstones.annotationResolution(id: archived.id, incomingModifiedAt: incomingModifiedAt) {
case .suppressStaleData:
    suppressed += 1
    continue
```

```swift
switch tombstones.membershipResolution(
    id: archived.id,
    incomingModifiedAt: archived.lastModifiedAt ?? archived.queuedAt
) {
case .suppressStaleData:
    suppressedQueueMemberships += 1
    continue
```

```swift
} else {
    switch tombstones.collectionResolution(
        id: archived.id,
        incomingModifiedAt: incomingModifiedAt
    ) {
    case .suppressStaleData:
        suppressedCollections += 1
        continue
```

```swift
switch resolution {
case .suppressStaleData:
    // This queue snapshot is older than a local explicit delete.
    suppressedQueueIDs.insert(archived.id)
    continue
```

```swift
/// **Never in `replaceLibrary`.** That mode deliberately bypasses tombstones —
/// it is "make this device look like the archive" ...
guard mode != .replaceLibrary else { return }
```

Bookmarks wrap the incoming check in `if mode != .replaceLibrary` (`:3133`). So do searches (`:3072`), sessions (`:3504`), favorites (`:3634`), and watermarks (`:3727`). Annotations and memberships do not. A collection or custom queue that is not already in the store hits the same unguarded `suppressStaleData` continue. Saved for Later never consults a queue tombstone (`:2780-2785`). A collection or queue that is still in the store, including Recently Deleted, is updated from the snapshot instead. The second pass cannot put a skipped row back, because `applyTombstonesToExisting` returns before it deletes anything in Replace. The `mode != .replaceLibrary` at `KudosBackup.swift:3851` is only the last-write-wins guard, and it sits after the annotation tombstone `continue`.

**Failing case.** Delete a highlight on this device. The signed tombstone is on file and the row is gone. Replace-restore a backup that still contains that highlight. The incoming switch hits `.suppressStaleData` and skips the insert. The highlight stays gone. A saved link in the same backup, covered by a local tombstone, is restored. A queue membership in that backup is skipped the same way as the highlight. Hard-delete a custom collection after Recently Deleted expires, leave its tombstone, and Replace-restore a backup that still contains that collection. `collectionsByID` has no row, `collectionResolution` returns `.suppressStaleData`, and the collection is not recreated. A custom queue in that backup is skipped the same way, and its memberships are dropped with it (`suppressedQueueIDs`). Replace should restore all four.

**Smallest fix.** Wrap the annotation and membership switches in `if mode != .replaceLibrary`. In the collection and queue `else` branches, treat Replace as revive and insert the snapshot row. Match the work guard at `:2417`.

## A27-5 A collection membership tombstone does not match the other device's work UUID

`kudos-ao3-reader/Services/KudosBackup.swift:2676-2687` and `:2713-2726`, the key at `:4284-4292`, the record at `PersistenceSync.swift:523-536`.

```swift
for workID in archived.workIDs {
    guard let work = restoredWorksByArchivedID[workID] else { continue }
    if tombstones.suppressesCollectionMembership(
        collectionID: collection.id,
        workID: work.id,
        incomingModifiedAt: incomingModifiedAt
    ) {
        continue
    }
```

```swift
let doomed = collection.works.filter { member in
    !archiveAffirmedMemberships.contains(member.id)
        && tombstones.suppressesCollectionMembership(
        collectionID: collection.id,
        workID: member.id,
        incomingModifiedAt: locallyChangedAt
    )
}
```

```swift
let id = SyncTombstone.collectionMembershipID(collectionID: collectionID, workID: workID)
```

`collectionMembershipID` is the XOR of the two UUIDs (`Models.swift:119-129`). `WorkRestoreIndex.existingWork` binds an archived work by AO3 id first and returns the local `SavedWork` (`KudosBackup.swift:4331-4336`, `WorkIdentityIndex.swift:39-42`). The local UUID is kept. A12's note that the sweep exists (`A12-result.md`, the collection-membership paragraph) is about a shared pair of UUIDs. This is the pair that does not match. The sweep is skipped in Replace (`KudosBackup.swift:2706`).

**Failing case.** Both devices download the same fic on their own, so the `SavedWork` UUIDs differ, and they share one collection UUID from an earlier sync. On B, remove the work from the collection. B tombstones XOR(collection, Wb). Sync. A's sweep looks up XOR(collection, Wa) and misses. The work stays in the collection on A. A's next export lists Wa. B resolves Wa to Wb and suppresses the re-add, because B's tombstone matches Wb. The work never leaves A, and it never returns to B. It should leave A, and A's next export should carry a deletion B can match.

**Smallest fix.** Key the tombstone by collection id plus AO3 work id (or the canonical work URL), the way a saved-work tombstone is already indexed by `ao3WorkID` (`KudosBackup.swift:4198-4210`). Look the sweep up with the resolved work's AO3 id.

## A27-6 One collection clock protects every removed member

`kudos-ao3-reader/Services/KudosBackup.swift:2707-2726`

```swift
// `lastMembershipChangedAt` is when this device's reader last
// chose the contents of this collection. A membership chosen
// after the deletion elsewhere is a deliberate re-add and stays.
let locallyChangedAt = collection.lastMembershipChangedAt
    ?? collection.lastModifiedAt
```

`suppressesCollectionMembership` returns false once `tombstone.lastModifiedAt >= incomingModifiedAt` is false (`KudosBackup.swift:4291-4292`). The clock passed in is the collection's, not the member's. `archiveAffirmedMemberships` only protects members the incoming loop already kept. A removed work is absent from the archive, so it is not in that set. Any newer collection clock makes the comparison fail for every previously removed member.

**Failing case.** Devices share a collection and the same work UUIDs. On B, remove work W. The tombstone's clock is T. On A, after that, add a different work V. A's `lastMembershipChangedAt` becomes newer than T. Sync. The sweep evaluates W with V's clock, the comparison fails, and W stays in the collection. W should leave. V should stay.

**Smallest fix.** Give each membership its own clock, and skip only the member whose own add is newer than the tombstone.

## A27-7 A favorite or a fandom watermark with a different id survives

`kudos-ao3-reader/Services/KudosBackup.swift:3645-3685` and `:3738-3772`. The deletion records store the UUID only (`PersistenceSync.swift:493-515`).

```swift
let local = byID[archived.id] ?? byTarget[targetKey]
if let local {
    resolvedLocalIDs.insert(local.id)
    // ... keep local.id ...
}
applyTombstonesToExisting(existing, in: context, mode: mode) {
    tombstones.readingFavoriteResolution(id: $0.id, incomingModifiedAt: $0.lastModifiedAt)
}
```

Watermarks match `byID` or `byName[fandomName]` and sweep by id the same way (`:3738-3772`). Incoming suppression is skipped in Replace. The second pass is skipped in Replace. A `.work` star's target is remapped onto the local work UUID on the way in (`:3701-3709`). The tombstone's `recordID` is still the favorite's UUID, so the remap does not help the sweep.

**Failing case.** Both devices star the same author, or the same fandom, before any sync. The row ids differ. The target string matches. On B, unstar. B tombstones B's id and exports no favorite. Sync. A's sweep misses A's id. The star stays, and A's next export publishes A's id. B inserts it. The star returns on B. The same steps with a fandom watermark, matched by name, leave the watermark on A. Unstarring should clear A when A's `lastModifiedAt` is not strictly newer than B's tombstone.

**Smallest fix.** Carry the target key (kind plus target, or the fandom name) on the tombstone, and have the sweep suppress the local row that matches it, using the local clock. The in-archive path can keep resolving `byTarget` / `byName` the way bookmarks try to resolve by URL.

## A27-8 Launch restore does not hand an unnamed session's drafts to the named account

`kudos-ao3-reader/Services/AO3AuthService.swift:671-676` and `:981-983`. The identity and the screen-open move are `CommentsModel.swift:19-36` and `:245-248`.

```swift
let verifiedName = refreshed.username.trimmingCharacters(in: .whitespacesAndNewlines)
if session.username.isEmpty, !verifiedName.isEmpty {
    CommentDraftStore().move(
        from: CommentDraftIdentity.unnamedSession(expectedGeneration), to: verifiedName
    )
}
sessionGeneration += 1
```

```swift
guard await finishAccepting(
    refreshed, expectedGeneration: restoringGeneration
) else { return }
```

`finishAccepting` sets `status` to the verified username and does not touch drafts (`AO3AuthService.swift:906-929`). Offline restore, when validation cannot reach AO3, signs in as `"AO3 Account"` while `saved.username` is empty (`:998-1000`). `AuthContext.current` treats `"AO3 Account"` as unnamed and files drafts under `unknown-session:<generation>` (`CommentsModel.swift:22-30`). `sessionGeneration` starts at 0 and is not persisted (`AO3AuthService.swift:311`).

Verify Session with an empty `currentSession.username` does move `unknown-session:<that generation>` before it bumps the generation, including when no comments screen is open. That is the case A20-1 named, and that path is closed. The launch path is the sibling. After it, `currentSession.username` is the real name, so the `session.username.isEmpty` check in Verify Session is false and the move never runs.

`CommentDraftStore.move` concatenates on a key collision and matches the prefix plus `"|"` (`CommentSubmission.swift:372-388`). This finding does not depend on that.

**Failing case.** Airplane mode. Launch. The account row says AO3 Account. Open a work's comments, type a reply, and leave the screen. The draft is stored under `unknown-session:0`. Kill the app. Launch on the network. `restore` validates, `finishAccepting` shows the real username, and no draft is moved. Open the reply composer. It is empty. Tap Verify Session. The username is already set, so the move is skipped. The reply should be in the composer under the real username.

**Smallest fix.** When `finishAccepting` turns a placeholder session into a real username, move every `unknown-session:` key onto that username. That is the hand-over A20 asked to live on the path that names the account, not only on Verify Session.

## A27-9 The account list's auth failure ignores the load token

`kudos-ao3-reader/Features/Bookmarks/AO3AccountWorksList.swift:1258-1259` and `:1299-1305`

```swift
guard auth.sessionGeneration == expectedSessionGeneration, token == loadToken else { return }
works = result.works
```

```swift
} catch AO3Error.authenticationRequired {
    guard await auth.sessionDidExpire(expectedGeneration: expectedSessionGeneration) else { return }
    works = []
    readingEntries = [:]
    bookmarkDetails = [:]
    unsubscribePaths = [:]
    phase = .idle
}
```

The success path and the `AO3Error` / generic catches check `token == loadToken` and the session generation (`:1258`, `:1318`, `:1321`). `authenticationRequired` checks the generation inside `sessionDidExpire` and then clears the list with no token check. `CancellationError` and `URLError.cancelled` leave `phase` alone (`:1306-1316`). The success-path race A20-2 named is closed for a load that completes normally.

**Failing case.** Bookmarks is showing page 1. Tap Next. That load's token is 1. Pull to refresh before it returns. The refresh token is 2, it completes, and page 1 is on screen with `phase == .loaded`. Token 1 then throws `authenticationRequired`. `sessionDidExpire` returns true for the same generation. The catch clears `works` and sets `phase = .idle`. The page the reader just loaded is gone. The same sequence applies to History, Subscriptions, and Marked for Later, which share `load`. The stale auth failure should return when `token != loadToken`, the same way the success path does.

**Smallest fix.** After `sessionDidExpire` returns true, return without clearing when `token != loadToken`.

## A27-10 Search keeps unapplied filters unless the phase is already loaded

`kudos-ao3-reader/Features/Search/SearchView.swift:259-266` and `:858-864`

```swift
.onChange(of: router.panel == .searchFilters) { _, showing in
    guard !showing, phase == .loaded, var restored = loadedFilters else { return }
    restored.query = filters.query
    if filters != restored { filters = restored }
}
```

```swift
if page != 1, filters != loadedFilters {
    runSearch()
    return
}
```

Fandom and tag results revert whenever the panel closes, with no phase check (`NativeBrowseView.swift:237-239` and `:592-594`). Search reverts only when `phase == .loaded`, and it copies `filters.query` onto the restored snapshot so the typed text stays. Apply calls `runSearch` (`SearchView.swift:736-748`), which sets the panel to `.none`, `phase` to `.loading`, and `loadedFilters` to nil before the fetch. The `onChange` then sees a phase other than `.loaded` and does not undo Apply. A page load sets `phase = .loading` while the current results stay on screen (`:858-872`) and captures `let current = filters` for the request that is already running (`:876`).

**Failing case.** Search is showing page 1, `phase == .loaded`, filters equal `loadedFilters`. Pull to refresh, or tap Next so a load is in flight and `phase` is `.loading`. Open Filters, change a rating, and dismiss without Apply. The `onChange` returns because the phase is not `.loaded`. The in-flight load finishes with the filters it captured and sets `loadedFilters` back to those. `filters` still has the rating. Tap Next. `page != 1` and `filters != loadedFilters`, so `runSearch()` sends the rating nobody applied. The same dismiss while `phase == .failed` skips the revert, and Try Again on page 1 sends `filters` directly, because the mismatch check is only for `page != 1`. Dismissing without Apply should restore `loadedFilters` and leave the query text, including while a page is loading and after a failure.

**Smallest fix.** On dismiss, revert whenever `loadedFilters` is non-nil, as the fandom and tag pages do, and keep the `filters.query` copy. Do not require `phase == .loaded`.

## A27-11 Choosing no account shortcuts restores the default grid

`kudos-ao3-reader/Features/Account/AccountShortcuts.swift:90-100` and `:128-132`. The grid reads the same key (`AccountView.swift:51`).

```swift
static func decode(_ raw: String) -> [AccountShortcut] {
    guard !raw.isEmpty else { return AccountShortcut.defaults }
    let chosen = raw.split(separator: ",").compactMap { AccountShortcut(rawValue: String($0)) }
    return chosen.isEmpty ? AccountShortcut.defaults : chosen
}

static func encode(_ shortcuts: [AccountShortcut]) -> String {
    shortcuts.map(\.rawValue).joined(separator: ",")
}
```

```swift
footer: {
    if chosen.isEmpty {
        Text("If you choose none, the grid is hidden. You can still find every "
            + "destination in the sections below.")
    }
}
```

The editor's `chosen` is `decode(raw)` (`AccountShortcuts.swift:109`). Removing the last row encodes `[]` as `""` (`:165-173`). The next `decode` hits the empty-string branch and returns the six defaults (dashboard, subscriptions, works, bookmarks, collections, history). `chosen.isEmpty` is therefore never true after a removal, so the footer never appears. Relaunch reads the same `""` from `@AppStorage` and shows the six defaults again.

**Failing case.** Open Account, edit shortcuts, and remove all six. The moment the last one goes, the editor shows the six defaults again. Leave and relaunch. The grid is the six defaults. The footer says the grid is hidden and the destinations remain in the sections below. An explicit empty choice should stay empty across launch. A missing key, the first-launch `""` that was never written by the editor, can keep returning the defaults.

**Smallest fix.** Encode an explicit empty choice as a sentinel (`none` is enough). `decode` maps that sentinel to `[]` and still maps `""` to `AccountShortcut.defaults`.

## Deletion settlement

Unsigned and untrusted incoming tombstones do nothing on every type, in Merge, reconcile, and Replace. They are not indexed. This device's next export does not carry them. A tombstone this device already holds is a separate row and is exported. That is the Phase 2 trust rule in `shouldAdopt`. It is not a finding.

A copy whose clock is strictly newer than the tombstone survives the sweep on every type that sweeps by that id. The survivor is re-exported, and the deleting device revives it (`reviveNewerData`). That hatch is the one the sweep comments describe. A27-3 and A27-6 are the places a later pass or a coarser clock defeats it. Overwriting `bookmark.dateAdded` from an archive that still contains the URL (`KudosBackup.swift:3154-3155`) can rewind a local clock before the sweep. A real deletion omits the URL, so that rewind is not how A27-1 fails.

| type | Merge and reconcile, trusted | Replace, trusted | (d) next export carries the deletion | (e) a newer copy on both devices |
| --- | --- | --- | --- | --- |
| `savedWork` | (a) Incoming suppressed by record id, AO3 work id, or canonical URL when the tombstone is at least as new as `lastModifiedAt ?? dateAdded` (`KudosBackup.swift:2417`, `:4198-4210`). (b) No sweep removes a work the archive simply omitted. Reconcile applies `isDeleted` when the archive is newer (`:4504-4511`). File Merge leaves an active existing work's flags alone (`:2377-2409`). (c) That work clock. | (a) Resurrection is not suppressed (`:2417` is `mode != .replaceLibrary`). (b) A work whose local id is outside the snapshot is soft-deleted with no tombstone (`:3393-3408`). | Only a tombstone that was adopted or already local. Replace's omission soft-delete does not mint one. | A strictly newer archive is not suppressed and is applied. The existing copy is not removed by absence alone. |
| `workCollection` | (a) A collection that is not already in the store is suppressed by `collectionResolution` on `lastModifiedAt ?? dateAdded`, in Replace as well as Merge (A27-4, `:2565-2572`). An existing row, including Recently Deleted, ignores that tombstone and then applies `isDeleted` when `incomingWins` (`:2652-2659`). File Merge withholds `incomingWins` for an existing collection (`:2591-2600`). (b) No absence sweep. (c) `lastModifiedAt`. | (a) A missing collection is still suppressed (A27-4). An existing one is updated because Replace forces `incomingWins` (`:2595`). (b) Omission soft-delete, no tombstone (`:3411-3417`). | Same as works. | A newer collection record revives when a local row exists, and when no local row exists only if the archive clock is strictly newer than the tombstone. Membership of that collection is A27-5 and A27-6. |
| `readingQueue` | (a) Saved for Later is forced to `.noTombstone` and mapped onto the local singleton (`:2780-2785`). A custom queue that is not already in the store is suppressed by `queueResolution`, in Replace as well as Merge (A27-4, `:2795-2804`), and its memberships are recorded in `suppressedQueueIDs`. An existing queue ignores the tombstone. `isDeleted` applies when `incomingWins` (`:2941-2948`); file Merge forces `incomingWins` false for an existing queue (`:2839-2840`). (b) No absence sweep. (c) `effectiveQueueModifiedAt`. | Replace forces `incomingWins` for a queue that is already here (`:2841`). A queue that is not here is still suppressed (A27-4). Omission soft-delete skips Saved for Later and mints no tombstone (`:3420-3428`). | Same as works. A Saved for Later tombstone is ignored on purpose. | A newer custom queue revives when a local row exists. Saved for Later never settles by queue tombstone; its memberships are A27-2. |
| `readingQueueMembership` | (a) Incoming suppressed on `lastModifiedAt ?? queuedAt`, including in Replace (A27-4). (b) Sweep by the local membership id only, on `lastModifiedAt` (`:3047-3050`). A different id does not match (A27-2). A membership whose work is not in `restoredWorksByArchivedID` is skipped, not re-homed. A membership whose queue id is in `suppressedQueueIDs` is not inserted (`:2969-2972`). (c) The membership's own `lastModifiedAt`. | (a) Still suppressed (A27-4). (b) Sweep returns immediately. | Carries the tombstone for the id that was deleted. Does not mint one for the other device's id, so the survivor is republished. | A strictly newer membership of the same id survives and revives on the other device. A different id never enters that comparison. |
| `workCollectionMembership` | (a) Incoming member suppressed when XOR(collection id, local work id) matches and the collection clock is not newer (`:2681-2686`). (b) Sweep uses the same XOR and the collection-wide clock (`:2713-2726`), and only outside Replace. A work downloaded separately does not match (A27-5). A later edit of any member keeps every removed member (A27-6). (c) `lastMembershipChangedAt ?? lastModifiedAt` for every member. | Sweep skipped (`:2706`). Snapshot membership is the archive's work list (`:2738` onward). | Carries the XOR of the UUIDs on the deleting device. The other device's work UUID is a different record, so the deletion is not what that device exports. | A collection clock newer than the tombstone keeps the member on both sides after the next exchange. There is no per-member "edited after deletion" clock. |
| `readingAnnotation` | (a) Incoming suppressed on `lastModifiedAt ?? createdAt`, including in Replace (A27-4). A mark whose work is not in the restore is skipped (`:3833`). (b) Sweep by id on `lastModifiedAt`, including when the archive lists no annotations (`:3816-3823`). Then dedupe can delete the survivor and the other device's row (A27-3). (c) The annotation's `lastModifiedAt`. | (a) Still suppressed. (b) Sweep skipped. Replace also soft-deletes annotations whose ids are absent from the snapshot, with no tombstone (`:3431-3437`). | Carries an adopted annotation tombstone. Dedupe also mints `samePassageDeduped` for the loser, which the other device then adopts. | A strictly newer same id survives the sweep. Dedupe can still drop it when the other row on that locator is the one the tombstone names. |
| `bookmark` | (a) Incoming suppressed on `dateAdded` when the mode is not Replace (`:3133-3140`). (b) Sweep by local id, plus by URL only if this archive still contained the suppressed link (A27-1). (c) `dateAdded`. | (a) Not suppressed. (b) Sweep skipped. Omission of a URL hard-deletes and mints a tombstone (`:3170-3177`). | Carries the tombstone for the deleted id. A surviving different id is exported as a live link. | A `dateAdded` strictly newer than the tombstone survives a same-id sweep and revives on the other device. A different id is not compared unless the archive also still lists the URL. |
| `savedSearch` | (a) Incoming suppressed by id outside Replace (`:3072`). (b) Sweep by id on `dateAdded`. (c) `dateAdded` only. There is no edit clock. | (a) Not suppressed. (b) Sweep skipped. Omission hard-deletes and mints a tombstone. | Carries the tombstone. A shared id settles. | A search added after the deletion has a later `dateAdded` and survives on both devices. Two searches made independently are different rows. That is a shared-id identity, and it settles. |
| `readingSession` | (a) Incoming suppressed by id outside Replace (`:3504-3513`). (b) Sweep by id on `lastModifiedAt` (`:3556-3558`). The work UUID is remapped onto the local work for the row that is kept (`:3520`). (c) `lastModifiedAt`. | (a) Not suppressed. (b) Sweep skipped. An unmatched local id is hard-deleted and tombstoned (`:3560-3564`). | Carries the session tombstone. A shared id settles. | A strictly newer session of that id survives and revives. Sessions for one work on two devices are different rows until an id has synced. That is intended. |
| `readingFavorite` | (a) Incoming suppressed by id outside Replace (`:3634-3643`). Match by id or `kind\|target` keeps the local id. (b) Sweep by id only (A27-7). (c) `lastModifiedAt`. | (a) Not suppressed. (b) Sweep skipped. Omission uses `resolvedLocalIDs`, so a target-matched local id is kept (`:3687-3695`), and other ids are tombstoned and hard-deleted. | Carries the favorite id that was unstarred. The other device's id is exported live. | A strictly newer favorite of the same id survives. A different id for the same target does not. |
| `fandomReadWatermark` | (a) Incoming suppressed by id outside Replace (`:3727-3736`). Match by id or fandom name keeps the local id. (b) Sweep by id only (A27-7). (c) `lastModifiedAt`. | Same Replace shape as favorites (`:3775-3781`). | Carries the watermark id. The other device's row for that fandom is exported live. | A strictly newer watermark of the same id survives. A different id for the same fandom name does not. |

## Checked, not findings

**A20-4.** `WorkDetailView.seriesWorks` drops a work `PrivacyGate.isHidden` (`WorkDetailView.swift:636-642`). A blurred sibling is a button labeled "Hidden mature work" that calls `gate.reveal` (`WorkDetailOverviewSections.swift:156-171`). `isHidden` and `isBlurred` are the two modes (`MatureContent.swift:63-71`). The row still shows the series position number. The title is not shown. The case A20 named is closed.

**A20-5.** `finishIfSucceeded` reloads `currentPageNumber` for a reply or an edit, and reloads the newest or first page for a new top-level comment (`CommentsModel.swift:1179-1198`). Delete still calls `model.load(forceRefresh: true)` (`CommentsView.swift:999-1014`). T-370 and the A20 triage promised the reply and the edit. Delete was not part of that fix.

**A20-6.** On a generation mismatch while still signed in, `loadSubscriptions` clears the loading flag and calls itself (`HomeView.swift:580-586`). `accountSubscriptions` does not bump `sessionGeneration`; it returns an empty list if the generation moved (`AO3AuthService.swift:813-821`). One Verify Session during the first load asks again and then fills the shelf. The named case is closed.

**T-369.** Request URLs in the GET, authenticated GET, and authenticated POST logs are private. The three AO3 work ids A21 already listed are still interpolated with no privacy marker, and a number is public by default: `AO3Client.swift:1326` (`Downloading EPUB for work \(workID)`), `WorkAvailability.swift:61`, and `WorkAvailability.swift:88`. A21's triage said those work ids were hashed. They were not. They are not re-filed here. The inconclusive sibling at `WorkAvailability.swift:68` hashes the id and still marks `error.localizedDescription` public; A21 already asked for that reason to be private. Local UUIDs, counts, and the sign-in, speech, and fandom sentences T-369 left public on purpose were not re-filed. `WorkAvailabilitySweep.swift:90`'s force-unwrap is the open item A21 already recorded.

**Sent writes.** `AO3Client.submitWrite` throws `CancellationError` only before `URLSession`: a missing prepared-session header, or a stamp mismatch before and after `pace()` (`AO3Client.swift:894-917`). After the response, a login redirect throws `AO3Error.authenticationRequired` (`:911-912`), whose sentence is "Your AO3 session expired. Please log in again." (`Models/AO3Models.swift:1248`). That is AO3 refusing the cookie. It is the same for every `submitWrite`.

Once a body is back, these classify a 2xx/3xx page with neither an error flash nor a success flash as "AO3 replied but didn't confirm…": work, chapter, series, and delete forms (`AO3WorkActions.swift:561-575`, `AO3WritingModels.swift:1070-1072`); series reorder and remove, which throw `.unconfirmed` when the read-back does not show the write (`AO3WorkActions.swift:296-302`, `:344-350`); collection create, update, delete, and the member/item verdict (`AO3CollectionActions.swift:461`, `:483-494`); challenge sign-up, settings, and `throwIfChallengeWriteFailed` (`AO3ChallengeActions.swift:64-68`, `:315-325`); comment post, reply, edit, and delete via `commentWriteResult` (`AO3WriteActions.swift:423-433`, `:560-562`). Comment post and reply route `.unconfirmed` into the ambiguous check (`CommentsModel.swift:1092-1097`). Edit and delete surface the sentence through `message(for:)`.

`saveBookmark` still treats any 2xx/3xx with no error flash as "Bookmarked." (`AO3WriteActions.swift:385-388`). `giveKudos` treats any 2xx as "Kudos left." (`:41-43`). The subscribe branch of `toggleSubscribe` treats a 2xx/3xx with no error flash as "Subscribed." (`:126-131`). A20 already left that any-2xx success as the A4 leftover and said not to re-file it. The bookmark composer's `isWorking` is cleared on both paths (`AO3WorkActionsModel.swift:125-140`).

`requireSessionGeneration` throws `CancellationError` (`AO3AuthService.swift:765-768`). The collection form's "Not saved" / "Not deleted" sentences (`AO3CollectionFormView.swift:513-518`, `:585-586`), the chapter delete's "nothing was deleted" (`AddChapterView.swift:451-453`), and the reorder screen's "the order was not saved" (`SeriesEditView.swift:414-415`) are reached from that fence or from `submitWrite`'s pre-send fence. After the POST, those writes throw `.unconfirmed` or a rejection, and the flags are cleared. `ChallengeAssignmentsView.perform` and the moderation accept/decline catches return on `CancellationError` without a sentence (`ChallengeAssignmentsView.swift:667-671`, `CollectionModerationView.swift:855-859` and `:877-880`). The `requireSessionGeneration` after a successful write is what makes that catch able to run once the POST has returned. A generation change also restarts `.task(id: auth.sessionGeneration)`, and `load()` calls `clearLoadedState()`, which clears `itemInFlight` / `participantInFlight` and re-reads the lists (`ChallengeAssignmentsView.swift:122`, `:456-460`; `CollectionModerationView.swift:114`, `:749-753`). The control does not stay busy, and the screen shows the re-read list. No separate finding.

## Unconfirmed

Dedupe soft-deletes a pre-existing loser and calls `markModified()`, which moves `lastModifiedAt` to now (`KudosBackup.swift:4029-4033`). The sweep then sees a clock newer than a tombstone for that same id and leaves the soft-deleted row in place. Whether the next export republishes it as a live highlight was not traced past `markModified`. Confirm by reading the annotation export filter for `isPendingDeletion`.

`CommentsModel.syncAuthenticationContext` can move a draft twice if SwiftUI delivers Verify Session's generation bump and the later username write as two updates (`CommentsModel.swift:245-248` allows a generation delta of 0 or 1). `CommentDraftStore.move` concatenates when both keys hold text. Confirm by reading `CommentsView`'s `onChange` of `authenticationKey` (`CommentsView.swift:203-211`) against a session whose username is still "AO3 Account" when the generation publishes.

`URLError.localizedDescription` marked `.public` (the A21 class E lines T-369 left in place) sometimes includes a URL. Nothing in this pass showed a live string that does. Confirm with one logged `URLError` from `AO3Client`.

A bookmark URL that differs from the tombstone's URL by a trailing slash would miss `suppressedBookmarkIDsByURL` even on the in-archive path. No canonicalizer was read on that dictionary. It does not change A27-1, which fails before the map is consulted.

## What was not read

Not read line by line: the work, collection, and queue field-merge bodies beyond the `incomingWins` and `isDeleted` gates cited above; EPUB byte replacement (`KudosBackup.swift:4340` onward); font and settings restore; the backup exporter except the tombstone fields cited from `PersistenceSync.swift`; `AO3InboxActions`; preference writes (`AO3PreferencesActions.swift`); the comment verification matcher past its generation checks (`AO3CommentActions.swift:245` onward); `CommentSubmissionTests`; series position numbering as an accessibility leak; Android favorite, watermark, annotation, and collection-membership merge. `audits/A26-result.md` is not in this tree. The "didn't confirm" wording was read from the iOS error types. `docs/AO3_NETWORKING_POLICY.md` and `docs/DATA_AND_PERSISTENCE_INVARIANTS.md` were not read end to end. No build was run, and archiveofourown.org was not contacted.

---

## Triage (Claude, 2026-10-09)

Eleven findings, all checked against the code. Fixed on iOS in **T-371**; the rest are one
question for the owner.

- **A27-3 real, fixed.** My own T-366 put the new annotation pass after the same-passage
  dedupe. The pass now runs first and tells the dedupe what it removed. Test
  `aDeletedCopyDoesNotTakeTheOtherDevicesMarkOnTheSamePassageWithIt`. Android has always
  swept first (`BackupMergeService.kt`, the pass at the `REPLACE_LIBRARY` guard before
  `dedupeSamePassageAnnotations`).
- **A27-8 real, fixed.** The launch restore hands an unnamed session's comment drafts to the
  account it has just named, as Verify Session does.
- **A27-10 real, fixed.** Search drops the panel's unapplied edits whatever the phase.
- **A27-11 real, fixed on both apps.** An explicit empty choice of Account shortcuts is
  stored as `none` and stays empty; a value never written is still the defaults. Android had
  copied the fault, with two tests that pinned it.
- **A27-9 not a fault.** `sessionDidExpire` returns true only after it has cleared the stored
  session: the reader is signed out, and the signed-out prompt is the right screen whichever
  load reported it.
- **A27-1, A27-2, A27-5, A27-7 real, not changed: owner question 21.** One fault in four
  places: a deletion record names an id, and a row each device made on its own never shares
  one. It predates T-366 and Android has the same rules. Nothing is lost; a deleted thing
  comes back. The fix is a deletion record that says what was deleted, which changes what is
  signed. T-366's comment on saved links claimed more than the code does and is corrected.
- **A27-6 real, not changed: the same question.** One clock for a whole collection.
- **A27-4 real, not changed: the same question.** Bringing these rows back in Replace would
  only have them removed at the next sync, because the deletion record stays on file (true
  today of a saved link, a search, a session, a star and a watermark that Replace does bring
  back). Replace needs one rule for a deletion made after the backup.

From its notes:

- **Three work ids were still public in the log** (A21's triage said they were hashed; they
  were not): `AO3Client.downloadEPUB`, two lines in `WorkAvailability`. Hashed now.
- Not changed: a comment delete still reloads the first page; `URLError` descriptions stay
  public in the log (A21 class E).
- Unconfirmed, not looked at: a soft-deleted dedupe loser whose clock is now newer than a
  deletion record for it; a draft moved twice if SwiftUI delivers Verify Session's two
  changes separately.

Also in T-371, found from Android the same day: the series form's Save scrolls AO3's answer
into view (it was the list's last row, below the fold); an unconfirmed chapter delete or
series removal is no longer prefixed "was not deleted" / "was not removed".
