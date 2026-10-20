# A67 result

Reviewed the current tree on `android/agent-grok-a67` (`ed560f2d`, which sits on lane `28bcd3c5`). Read-only. Items 1–5 are all covered. Every finding below is a writer or a screen path still in this tree.

## Priority

1. **F1, sure.** The launch search-index rebuild writes detached full works back and can put a page, a favourite, a Finished mark, or a tag-refresh stamp back where the reader left them. `WorkSearchIndex.kt:143`, `WorkRepository.kt:254`, started from `KudosApplication.kt:81`.
2. **F7, likely.** A folder sync that already passed the Auto Sync check keeps importing after Replace pauses sync, and can merge the removed works back. `SyncRepository.kt:133`, `SyncRepository.kt:595`, `BackupScreen.kt:156`.
3. **F8, likely.** Replace’s only undo copy is written into app-private storage the Import picker cannot open. Saved links, saved searches, reading history, stars, and fandom visits then have no way back. `BackupScreen.kt:143`, `BackupScreen.kt:387`.
4. **F2, likely.** Deleting a local EPUB writes the work from before the file delete, so a page or a tag written during the delete is lost. `WorkRepository.kt:385`. The held-copy sweep can do the same with the list it loaded at the start (`WorkRepository.kt:366`).
5. **F3, likely.** Re-importing an EPUB the library already has writes that earlier row back after the file write. `WorkImporter.kt:300`.
6. **F4, possible.** Adding a work to a queue rewrites the whole row after a file check. `ReadingQueueRepository.kt:719`, called from `addWork` at `ReadingQueueRepository.kt:121`.
7. **F5, possible.** Preserving a queued work writes the pre-check row back after the EPUB exists check. `WorkImporter.kt:133`.
8. **F6, possible.** Opening the reader writes the work from before the font list is read. `ReaderRepository.kt:82`.
9. **F9, possible.** A multi-item Inbox delete confirms the items the dialog captured, then sends whatever the selection is at that later moment. A load that finishes in between sends nothing. `AccountInboxPane.kt:160`, `AccountInboxViewModel.kt:289`.

## Findings

### F1, sure. Launch search rebuild writes the old work

`WorkDao.upsert` and `upsertAll` are `@Upsert` of the whole `WorkEntity` (`WorkDao.kt:16`). A row written from a snapshot replaces every column, including progress, favourite, Finished, tags, and `lastTagRefreshAttemptAt`.

The rebuild loads the stale list once, copies each of those works, and saves the copies after tag queries and `delay`s:

```kotlin
// android/app/src/main/java/io/github/cidy02/kudos/works/WorkSearchIndex.kt:138
val stale = loadStale(CURRENT_VERSION)
...
for (work in stale) {
    val tags = userTagsFor(work.id)
    pending.add(reindex(work, tags))
    ...
    if (sinceSave >= SAVE_INTERVAL) {
        save(pending.toList())
        ...
    }
    ...
    if (elapsedMs > SLICE_BUDGET_MS) {
        delay(SLICE_BREATHER_MS)
        ...
    }
}
```

`reindex` only changes `searchText` and `searchIndexVersion` on that copy (`WorkSearchIndex.kt:86`). The save writes the copy in full:

```kotlin
// android/app/src/main/java/io/github/cidy02/kudos/works/WorkRepository.kt:254
save = { batch ->
    workDao.upsertAll(batch.map { it.toEntity() })
}
```

It runs at every process start, outside the persistence gate, after the launch sweeps:

```kotlin
// android/app/src/main/java/io/github/cidy02/kudos/KudosApplication.kt:80
// Paced rebuild of stale library searchText (schema bump / pre-index / restore).
runCatching { container.workRepository.rebuildSearchIndexIfNeeded() }
```

A work near the end of a large stale set is not written until hundreds of tag queries and 2 ms breaths later (`SLICE_BUDGET_MS` is 5, `SAVE_INTERVAL` is 250). The reader’s progress saver waits 1500 ms and then writes. If that write lands before this rebuild reaches the work, the next `upsertAll` puts the launch snapshot back: the page, the favourite, or the Finished mark from before the edit. The same snapshot can clear `lastTagRefreshAttemptAt` and the tags a Library backfill just stored, so the next time the Library is open that work is read from AO3 again inside 24 hours. That second read belongs to this write, not to the backfill.

It is a no-op when every row is already at `searchIndexVersion` 2. It runs for a schema bump, a library that was never indexed, and a library just restored. iOS mutates `searchText` on the live record and saves that record. The mechanism here is sure whenever any row is stale and the reader edits it before its batch is saved.

### F7, likely. A sync that already started keeps importing after Pause

Auto Sync is `sync.isEnabled`. A later lifecycle run and the worker both go through `runAutoSync`, which returns without syncing while the flag is off:

```kotlin
// android/app/src/main/java/io/github/cidy02/kudos/backup/SyncRepository.kt:133
suspend fun runAutoSync(): SyncResult? {
    if (!isSyncEnabled() || getSyncFolderUri() == null) return null
    return runSync()
}
```

`runSync` (`SyncRepository.kt:138`) does not read the flag again. Replace’s Pause only stores the flag. It does not call `setAutoSync`, so it does not cancel the worker, and it does not stop a run that already passed the check:

```kotlin
// android/app/src/main/java/io/github/cidy02/kudos/backup/BackupScreen.kt:156
if (pauseSync && pending.syncEnabled) {
    settingsRepository.updateSyncIsEnabled(false)
}
```

That run merges the folder before it exports. Each batch takes the persistence gate inside `importPackage`:

```kotlin
// android/app/src/main/java/io/github/cidy02/kudos/backup/SyncRepository.kt:595
backupRepository.importPackage(
    KudosBackupPackage(manifest, epubFiles, fontFiles),
    normalizeQueuePreservation = next >= manifest.works.size
)
```

Replace’s `importV2ZipBytes` takes the same gate (`BackupRepository.kt:101`). A sync that is already inside `runSyncLocked` waits, then merges the folder after Replace commits. The folder still holds the works Replace just removed. The screen tells the reader those works come back if sync stays on (`BackupScreen.kt:417`). Pause is what is supposed to stop that. A run that started earlier still does it. Works removed by Replace are in Recently Deleted and can return through that merge.

Anything that starts later stays paused: `FolderSyncWorker.doWork` treats a null `runAutoSync` as success and does not retry (`FolderSyncWorker.kt:16`), and `KudosApplication.maybeRunFolderSync` uses the same function (`KudosApplication.kt:150`). Sync Now and choosing a folder (`connect` forces the flag on, `SyncRepository.kt:82`) are the reader.

### F8, likely. The undo copy is where Import cannot see it

Replace refuses to run until an undo copy has been written, and a failed write leaves the library alone (`BackupScreen.kt:177`). That part holds. The copy itself is written here:

```kotlin
// android/app/src/main/java/io/github/cidy02/kudos/backup/BackupScreen.kt:143
val docs = context.getExternalFilesDir(Environment.DIRECTORY_DOCUMENTS)
    ?: File(context.filesDir, "Documents").also { it.mkdirs() }
docs.mkdirs()
val file = File(docs, repository.suggestedSafetyBackupFileName())
val safetyBytes = repository.exportV2ZipBytes()
withContext(Dispatchers.IO) {
    Files.write(
        file.toPath(), safetyBytes,
        StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE
    )
}
```

`getExternalFilesDir(DIRECTORY_DOCUMENTS)` is `Android/data/<package>/files/Documents`. The fallback is the app’s private `filesDir`. The system document picker, which Import Backup uses, cannot browse either on current Android. The name is `Kudos-before-replace-$stamp.kudosbackup` (`BackupRepository.kt:293`). The screen then says the way back is to import that file and choose Replace:

```kotlin
// android/app/src/main/java/io/github/cidy02/kudos/backup/BackupScreen.kt:387
footnote = "Replace only changes this device. Removed works go to Recently Deleted and " +
    "can return through Merge; saved links, saved searches, reading history, stars, " +
    "and fandom visits are deleted completely and remembered as deleted, so Merge " +
    "will not bring them back. To restore everything, import the saved copy and " +
    "choose Replace."
```

Works can still be restored from Recently Deleted. Saved links, saved searches, reading history, stars, and fandom visits cannot, and Merge will not bring them back. iOS writes this copy into the user Documents directory the import sheet lists, with a staged write and more than one attempt. Here there is one `CREATE_NEW` attempt. A name collision in the same second throws, `safetyName` stays null, and Replace is refused. That refusal is safe. The file the reader cannot open is the loss.

### F2, likely. `deleteLocalEpub` writes the pre-delete work

```kotlin
// android/app/src/main/java/io/github/cidy02/kudos/works/WorkRepository.kt:385
suspend fun deleteLocalEpub(workId: String): SavedWork? {
    val work = getWork(workId) ?: return null
    fileStore.deleteWorkEpub(workId)
    return upsert(work.copy(hasEpub = false, remoteEpubPending = false, freedAt = null, lastModifiedAt = clock()))
}
```

`deleteWorkEpub` is `withContext(Dispatchers.IO)` (`WorkFileStore.kt:48`). The upsert is the row from before that yield, with three fields changed. A tag backfill or a progress save that commits during the delete is replaced by the old row. Callers are Free up space (`freeFinishedCopies`, `WorkRepository.kt:379`), the launch held-copy sweep (`sweepHeldCopies`, `WorkRepository.kt:371`), Recently Deleted’s Remove Copy, and Work Detail.

The sweep also upserts rows from the list it loaded at the start, after earlier iterations have suspended:

```kotlin
// android/app/src/main/java/io/github/cidy02/kudos/works/WorkRepository.kt:366
for (entity in workDao.getHeldCopies()) {
    val work = decorate(entity.toDomain())
    if (!qualifiesForHold(work)) {
        upsert(work.copy(freedAt = null, lastModifiedAt = now))
    } else if ...
}
```

`decorate` adds kept-offline fields. The other columns stay the loop-start snapshot. That window is the DAO calls between works, so this part is possible. The file-delete path is the likely one. iOS clears the file flag on the live record.

### F3, likely. An EPUB re-import writes the match from before the file write

```kotlin
// android/app/src/main/java/io/github/cidy02/kudos/works/WorkImporter.kt:300
if (existing != null) {
    if (!existing.hasEpub || !fileStore.workEpubExists(existing.id)) {
        when (val write = fileStore.writeWorkEpub(existing.id, finalBytes)) {
            ...
        }
    }
    val restored = if (existing.isDeleted) {
        workRepository.restoreFromRecentlyDeleted(existing.id) ?: existing
    } else {
        existing
    }
    work = epubMetadata.applyTo(restored.copy(...), fillOnly = true).withImportedAo3Ids()
    return WorkImportResult.Success(workRepository.upsert(work))
}
```

`findImportedEpub` and `workEpubExists` are suspends, and `writeWorkEpub` is a file write (`withContext(Dispatchers.IO)`). For a work that is not in Recently Deleted, `restored` is the `existing` captured before that write. `applyTo(..., fillOnly = true)` fills empty metadata and the upsert writes the whole row. A favourite, a place, or a Finished mark saved while a large file is writing goes back to the earlier row. A brand-new import has no existing row to clobber. Web EPUB import ends in this function (`WorkImporter.kt:214`).

### F4, possible. Queue normalize writes a row held across a file stat

```kotlin
// android/app/src/main/java/io/github/cidy02/kudos/library/ReadingQueueRepository.kt:719
private suspend fun normalizeWork(workId: String, now: Instant, markModified: Boolean = false) {
    val work = workDao.getById(workId) ?: return
    ...
    val hasFile = epubOnDisk?.invoke(workId) ?: work.hasEpub
    ...
    val normalized = work.copy(...)
    if (normalized != work) workDao.upsert(normalized)
}
```

`epubOnDisk` is `workFileStore.workEpubExists` (`KudosAppContainer.kt:272`), which is `withContext(Dispatchers.IO)`. `addWork` calls this outside a transaction (`ReadingQueueRepository.kt:103` and `:121`). A commit that lands during the stat is overwritten if any queue field changed. Launch `normalizeAllQueuedWorks` and `removeMembership` run inside `withTransaction`, so other DAO writes wait out that whole function. The open window is `addWork`.

### F5, possible. Preserve writes the row from before the exists check

```kotlin
// android/app/src/main/java/io/github/cidy02/kudos/works/WorkImporter.kt:133
val attempt = workRepository.upsert(work.copy(lastPreservationAttemptAt = workRepository.currentInstant()))
if (attempt.hasEpub && fileStore.workEpubExists(attempt.id)) {
    return WorkImportResult.Success(workRepository.upsert(attempt.copy(
        epubPreservationStatusRaw = "preserved", preservedAt = attempt.preservedAt ?: workRepository.currentInstant()
    )))
}
```

Callers re-read the work immediately before this, so the input is fresh. The second upsert is `attempt` from before `workEpubExists`. The failure and cancel paths re-read (`WorkImporter.kt:149` and `:156`). The success-when-the-file-is-already-there path is the one that can put an older page back. The window is one file stat.

### F6, possible. Opening the reader writes the work from before the font list

```kotlin
// android/app/src/main/java/io/github/cidy02/kudos/reader/ReaderRepository.kt:52
val settings = settingsProvider()
var openedWork = workRepository.releaseHeldCopy(workId) ?: work
if (settings.app.keepsWorksYouRead && !openedWork.isSaved) {
    openedWork = workRepository.setSaved(workId, true) ?: openedWork
}
val customFonts = customFontsProvider?.invoke()
    ?: customFontRepository?.listImported()
    ?: emptyList()
...
val stamped = workRepository.upsert(openedWork.copy(
    lastReadDate = now,
    progressModifiedAt = now,
    lastModifiedAt = now,
    hiddenFromHistoryAt = null
))
```

`releaseHeldCopy` and `setSaved` re-read. `listImported` is a DAO read (`CustomFontRepository.kt:28`) and the font path check can stat files. The upsert is the work from before that. One query, during open.

### F9, possible. Inbox bulk delete sends the selection it finds later

A single notification is deleted from the item the dialog captured. A selection is not:

```kotlin
// android/app/src/main/java/io/github/cidy02/kudos/account/AccountInboxPane.kt:157
onConfirm = {
    val pending = pendingDelete ?: return@DestructiveConfirmation
    pendingDelete = null
    if (pending.items.size == 1) {
        viewModel.startItemAction(AO3InboxBulkAction.Delete, pending.items.first(), pending.openedIn)
    } else {
        viewModel.startBulkAction(AO3InboxBulkAction.Delete, pending.openedIn)
    }
}
```

```kotlin
// android/app/src/main/java/io/github/cidy02/kudos/account/AccountInboxViewModel.kt:289
fun startBulkAction(action: AO3InboxBulkAction, openedIn: AO3PageCache.Scope? = null) {
    startAction(action, mutableState.value.selectedItems, openedIn)
}
```

A load that finishes while the dialog is up clears the selection (`AccountInboxViewModel.kt:163`). `startAction` then returns on an empty list (`AccountInboxViewModel.kt:299`) and sends nothing. The reader confirmed a delete of the items named in the dialog. The dialog’s scrim keeps them from changing the selection by hand, so this needs a load already in flight. One item is unaffected.

## What looked right

### Item 1. The 2026-10-16 re-read, and the writers that are not this bug

`bab161fd` and `28bcd3c5` do re-read after the long suspend and skip a deleted row. That holds in `WorkUpdateChecker.kt:37`, `WorkAvailabilitySweep.kt:81`, `WorkRepository.refreshMetadata` and `backfillTagsFromAO3` (`WorkRepository.kt:771`, the cancel path puts the old stamp back from a fresh read at `:786`), `WorkMetadataRefresh.kt:36`, Work Detail kudos (`WorkDetailScreen.kt:1142`), and `ReaderRepository.markKudosGiven`. `WorkImporter.saveMetadataOnly` and `download` look the existing row up after the canonical fetch. `persistDownloadedEpub` and the 404 paths re-read before writing file or unavailable flags.

`prepareForReading` resets `isFinished`, the spine index, and the scroll fraction after a fresh EPUB (`WorkImporter.kt:203`). iOS `WorkReaderPreparation.restoreReadableEPUB` does the same on the live record. That wipe is the shared behaviour.

These are not the bug: a get, a copy, and an upsert with no file, network, `delay`, or `withContext` between them (`setFavorite`, `setFinished`, `softDelete`); `WorkRepository.upsert` reading tags in the same breath as the write (`WorkRepository.kt:234`); backup apply, which captures rows again inside `withTransaction` before it writes.

### Item 2. Library tag backfill

Looked right.

The daily tag worker and the launch read of up to five works are gone. Launch cancels any previously scheduled `WorkTagsRefreshWorker` and `AvailabilitySweepWorker` (`KudosApplication.kt:162` and `:155`). The availability sweep remains a screen the reader opens.

The backfill starts only on the main Library, and leaving that composition cancels it:

```kotlin
// android/app/src/main/java/io/github/cidy02/kudos/library/LibraryScreen.kt:202
if (section == null) {
    LaunchedEffect(Unit) {
        val readsAO3 = ... DemoNetwork.awaitLaunchDecision(); !DemoNetwork.isActive
        workRepository.backfillFilterMetadata(readsAO3)
    }
}
```

A section page passes a section, so it does not start the walk. `backfillTagsFromAO3` checks `needsAO3Refresh` (`SavedWork.kt:136`: no read when `ao3Unavailable`, and no read when `lastTagRefreshAttemptAt` is under 24 hours), stamps the attempt before the request, and on cancel restores the old stamp and rethrows. One request already on the wire can finish after the reader leaves. The walk does not continue to the next work. A cancel is not an attempt, so the next open can read that work. That matches the 24-hour rule. An empty tag page keeps the tags the work has. A 404 sets `ao3Unavailable` and keeps the rest. Queue-only and deleted works are skipped. The demo sets `readsAO3` false, and `MainActivity` decides demo or not before `setContent`.

The read goes through `WorkTagsRepository(ao3Client)` (`KudosAppContainer.kt:235`). That client’s `get` is the shared coordinator: one at a time is not required, and request starts are at least 600 ms apart (`AO3RequestCoordinator.kt:25`, `AO3NetworkConfig.kt:6`). Local EPUB tag fill is not an AO3 read and still runs in the demo.

### Item 3. What stays paused, and Disconnect

A sync that has not started stays paused. The worker, resume, and launch all use `runAutoSync`. Disconnect clears the folder, the flag, the last error, the manifest digest, and `lastSyncAt` (`SyncRepository.kt:95`), and cancels the worker. Sync Now is the reader. `connect` turns Auto Sync on because the reader just chose a folder. Refusing Replace when the undo copy cannot be written, with no “I understand the risks” bypass, matches the 2026-10-16 decision and is the safer side.

### Item 4. Web import, pages, tags, Submit

Looked right.

An EPUB is fetched only when the URL is https on an AO3 host, the encoded path starts with `/downloads/`, and the last segment ends in `.epub`:

```kotlin
// android/app/src/main/java/io/github/cidy02/kudos/network/ao3/work/AO3EpubDownloader.kt:27
fun isEpubDownload(url: String): Boolean {
    val parsed = url.toHttpUrlOrNull() ?: return false
    return AO3BrowseUrls.isAo3Url(url) && parsed.encodedPath.startsWith("/downloads/") &&
        parsed.pathSegments.lastOrNull()?.endsWith(".epub", ignoreCase = true) == true
}
```

`isAo3Url` requires scheme `https` and host `archiveofourown.org` or a subdomain (`AO3BrowseUrls.kt:31`). `downloadUrl` returns before `getBytes` otherwise. The WebView uses that check for the address field, a main-frame navigation, the download listener, and the URL the screen was opened with (`AO3WebViewFallbackScreen.kt:76`, `:168`, `:255`, `:302`). The address field turns a scheme-looking string into a navigation decision: `javascript:` and `intent:` are Block, other http(s) hosts are handed to an external browser, and only an AO3 https URL loads in the WebView (`AO3WebUrlPolicy.kt:25`). A plain query becomes an AO3 works search. The import coroutine is the composition scope, so leaving the screen cancels it. The downloader in production is `AO3EpubDownloader(ao3Client)` (`KudosAppContainer.kt:239`), the shared pacer. One import is one download the reader asked for. `importWebEpub` does not fetch the work page first.

Load More appends. A later page is added to the rows already shown, duplicates by id dropped, and a failure leaves those rows and offers “Try Loading More” for the page that failed (`AuthorProfileScreen.kt:227` and `:948`). The button is disabled while a load is in flight.

Exact page entry commits on Go. The slider, the nearby tiles, First, and Last only change the draft (`KudosPaginationBar.kt:160` and `:197`). A value outside `1..totalPages`, or one that does not fit in an `Int`, leaves Go disabled. The Inbox uses this bar (`AccountInboxPane.kt:1129`). At a large accessibility font it uses `LargeTextPager`, which is Previous and Next. That is the same large-text pager other lists use.

Dashboard About opens the author route it was given, pseud included: `onOpenAbout(route)` (`AuthorProfileScreen.kt:492`) navigates through `Routes.authorAbout`, which encodes `pseud (username)` (`Routes.kt:220`), and the destination opens `AuthorTab.About` (`AppNavHost.kt:1306`). Settings’ About is the app screen (`AppNavHost.kt:1245`), a different route.

Popular tags: one read when a character, relationship, or freeform picker opens, keyed on fandom, kind, and repository (`FilterTagPicker.kt:95`). Cycling a tag and typing change other state. Typing drives a separate autocomplete effect, debounced 300 ms, and only at two characters (`FilterTagPicker.kt:108`). The repository is `AO3TagAutocompleteRepository(ao3Client)` (`KudosAppContainer.kt:209`). The count-stripping regex is ordinary and is fine on Android (`AO3TagAutocompleteRepository.kt:106`).

Collection Items’ Submit cannot run twice. The button launches `confirmSubmit` only while `canSubmit` (`AO3CollectionItemsScreen.kt:127`). `confirmSubmit` returns when `busy`, and it sets `Phase.Submitting` before any suspend (`AO3CollectionItemsState.kt:107`). On the main dispatcher the second call sees that phase. The write is one fresh form and then one single-shot POST per draft, stopping on the first refusal (`AO3WriteRepository.kt:876`), through `postOnce` (`AO3WriteRepository.kt:1242`). A cancel does not send the POST again.

### Item 5. Bulk download, the menu’s work, Home delete, Inbox delete, the pager

Looked right, aside from F9.

Remote Download walks the selected summaries one at a time, checks cancellation, and stops on a failure other than 404 (`RemoteWorkSelection.kt:280`). It saves listing metadata with `enrichMetadata = false` and then downloads the EPUB if the file is missing (`WorkImporter.kt:189`). It does not read each work page first. The downloader is the shared client. Home’s Bulk Download enqueues into `DownloadQueue`, whose pump processes one item at a time (`DownloadQueue.kt:162`).

Each remote row owns its menu. `RemoteWorkActionFrame` remembers menu state by `summary.id` and the actions close over that row’s summary, or over `local.id` when the row already matches a library work (`WorkRowActions.kt:142` and `:180`). `LibraryWorkMenu` calls those actions with the `work` it was given (`LibraryScreen.kt:1146`). Home, Search, Browse, author works, and account lists go through that frame.

Home bulk Delete sets `deletingSelection` before the targets (`HomeBulkBar.kt:61`). The dialog asks when that flag is set, even if the reader turned confirmations off:

```kotlin
// android/app/src/main/java/io/github/cidy02/kudos/home/HomeWorkMenu.kt:241
confirmBeforeDelete = controller.deletingSelection || confirmBeforeDelete,
```

A single Home row still follows the setting. Inbox delete always passes `confirmBeforeDelete = true` (`AccountInboxPane.kt:156`). Mark Read and Mark Unread do not ask. One notification is sent from the item the dialog held (F9 is the multi-select path only). The Inbox pager is the shared bar, including its exact-page field, on the page the reader is on (`AccountInboxPane.kt:378`).
