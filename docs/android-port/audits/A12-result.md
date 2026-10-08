# A12 result: iOS reader, library, backup

Read-only audit of `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` and `/Users/cidy02/kudos-ios-polish/KudosTests/`. No source was edited, and no tests were run. Paths below are relative to `/Users/cidy02/kudos-ios-polish/`.

`legacyReaderProgress` is the macOS card percent and is display-only (`DATA_AND_PERSISTENCE_INVARIANTS.md`). The resume fields are `readiumLocator` (iOS) and `lastSpineIndex` + `lastScrollFraction` (macOS). Collection membership already removes a local member a trusted tombstone covers (`KudosBackup.swift:2706-2735`). That path is not a finding.

## Findings

| id | severity | file:line | statement |
|---|---|---|---|
| A12-1 | P1 | `kudos-ao3-reader/Models/Models.swift:664` | An iPhone read never writes the spine pair the Mac opens from, a Mac read never updates the locator the iPhone opens from, and a newer iPhone snapshot copies spine 0 over a real Mac chapter. |
| A12-2 | P1 | `kudos-ao3-reader/Features/ReaderReadium/ReadiumReaderView.swift:846` | Deleting a highlight, note, or in-book bookmark in the reader stores an unsigned tombstone, and restore never deletes a copy the other device already has. |
| A12-3 | P1 | `kudos-ao3-reader/Services/KudosBackup.swift:2953` | A queue removal or a saved AO3 link deleted on one device stays on the other. Restore only refuses to insert the incoming row. |
| A12-4 | P2 | `kudos-ao3-reader/Features/Library/LibraryView.swift:76` | Library bulk actions use every selected id, while a fandom chip or the privacy toggle during select hides rows that stay selected. |
| A12-5 | P2 | `kudos-ao3-reader/Features/Library/Collections.swift:543` | Select All in a collection selects every membership, including works the active filter has hidden. |
| A12-6 | P2 | `kudos-ao3-reader/Features/ReaderReadium/ReaderNoteEditor.swift:41` | Changing a highlight's colour writes it immediately. Cancel does not put the old colour back. |
| A12-7 | P3 | `KudosTests/ReadingAnnotationBackupTests.swift:109` | The annotation-resurrection test and the card-percent test stay green if the reader keeps an unsigned tombstone and if Mac still opens at spine 0. |

## A12-1 — iPhone and Mac do not resume each other's position

iOS opens `ReadiumReaderView`. macOS opens `ReaderView`. The split is compile-time:

```24:29:kudos-ao3-reader/Features/ReaderReadium/ReadiumReaderView.swift
    @ViewBuilder private var reader: some View {
        #if os(iOS)
        ReadiumReaderView(work: work)
        #else
        ReaderView(work: work)
        #endif
```

The iPhone write stores the locator and `progressModifiedAt` only:

```664:674:kudos-ao3-reader/Models/Models.swift
    func applyDebouncedReadiumLocator(_ locator: String, at date: Date = Date()) {
        let before = readiumProgress
        readiumLocator = locator
        progressModifiedAt = date
        // Only a new position retires the macOS reader's percent. The first write
        // after open is string-gated, so the restored spot re-reported as a new
        // string lands here too; a glance is not a read.
        if let before, let after = readiumProgress,
           abs(after - before) < ReadiumProgressPersistence.minProgressionDelta { return }
        legacyReaderProgress = nil
    }
```

Nothing in the iOS reader assigns `SavedWork.lastSpineIndex`. The only writers are the Mac reader (`ReaderView.swift:535`), backup merge (`PersistenceSync.swift:654`), a progress reset, and demo data.

The Mac reader resumes from the spine index and never reads `readiumLocator`:

```500:503:kudos-ao3-reader/Features/Reader/ReaderView.swift
            currentIndex = min(max(work.lastSpineIndex, 0), parsed.spineURLs.count - 1)
            // Seed the persisted intra-chapter position so reopening restores
            // the exact saved spot in the saved chapter.
            progressBridge.seed(spine: currentIndex, fraction: work.lastScrollFraction)
```

A Mac persist updates the spine pair, the card percent, and `progressModifiedAt`. It leaves `readiumLocator` as it was:

```196:202:kudos-ao3-reader/Features/Reader/ReaderProgressBridge.swift
    func persist(_ fraction: Double, to work: SavedWork, resourceLengths: [Int?], at now: Date = Date()) {
        work.lastScrollFraction = fraction
        if hasMoved, let currentSpine, let percent = WorkReadingPosition.publicationProgress(
            spineIndex: currentSpine, chapterFraction: fraction, resourceLengths: resourceLengths) {
            work.legacyReaderProgress = percent
        }
        work.markProgressModified(now)
```

The iPhone open uses the locator whenever it decodes. The spine is consulted only when the locator is missing, and only when the index is greater than 0:

```1403:1406:kudos-ao3-reader/Features/ReaderReadium/ReadiumReaderView.swift
        let initialLocator = Locator(persistenceString: work.readiumLocator)
        // No Readium progress yet but a legacy position exists → resume at that chapter.
        let fallbackSpineIndex = initialLocator == nil && work.lastSpineIndex > 0
            ? work.lastSpineIndex : nil
```

That fallback lands at the start of the spine item. The fraction is dropped:

```500:502:kudos-ao3-reader/Features/ReaderReadium/ReadiumBook.swift
    /// `fallbackSpineIndex` migrates legacy progress: when there's no saved Readium
    /// `Locator`, resume at the start of that reading-order item (the work's last
    /// chapter from the old WKWebView reader). Intra-chapter offset isn't recovered.
```

```522:524:kudos-ao3-reader/Features/ReaderReadium/ReadiumBook.swift
            if initial == nil, let index = fallbackSpineIndex,
               publication.readingOrder.indices.contains(index) {
                initial = await publication.locate(publication.readingOrder[index])
```

Export always carries both the untouched spine pair and the locator (`KudosBackup.swift:998-999` and `1019-1024`). On reconcile, a newer snapshot overwrites the local spine pair whenever it wins. An absent locator is left alone. A present spine of 0 is written:

```654:664:kudos-ao3-reader/Services/PersistenceSync.swift
        work.lastSpineIndex = incoming.lastSpineIndex
        work.lastScrollFraction = incoming.lastScrollFraction
        // Absent is not a reset. A snapshot that never carried a locator must
        // not wipe the precise position this device already has — that is how a
        // backup round-tripped through macOS cost every work its exact page.
        let localProgression = work.readiumProgress ?? work.legacyReaderProgress
        if let locator = incoming.readiumLocator {
            work.readiumLocator = locator
        }
```

Folder sync calls this restore in the default mode, `.reconcile` (`KudosBackup.swift:2108`, `FolderSyncService.swift:249` and `357`).

**Failing case 1.** Read a work on the iPhone until it is well into a later chapter. `readiumLocator` and `progressModifiedAt` update. `lastSpineIndex` stays 0 and `lastScrollFraction` stays 0. Open the same work on the Mac. `currentIndex` becomes 0. The book opens on the first spine item. The card can still show the iPhone percent, because `publicationProgress` reads the locator (`Models.swift:550-551`). The Mac reader should open the chapter and in-chapter fraction the iPhone stored.

**Failing case 2.** Read on the iPhone, then read further on the Mac, to chapter index 4 with a non-zero fraction. Mac persist sets `lastSpineIndex`, `lastScrollFraction`, `legacyReaderProgress`, and a newer `progressModifiedAt`, and leaves the old `readiumLocator` in place. Open on the iPhone. The old locator decodes, so `fallbackSpineIndex` is nil. The book opens at the old iPhone page. The card shows the Mac percent (`legacyReaderProgress ?? readiumProgress`). The iPhone should open where the Mac stopped.

**Failing case 3.** Same library, synced. The iPhone read is newer, so its snapshot wins. The snapshot's `lastSpineIndex` is still 0. `applyProgress` writes that 0 onto the Mac work. The next Mac open starts at the first spine item. The chapter the reader had reached on the Mac is gone. A snapshot whose spine was never written should not replace a spine the Mac actually saved.

A Mac read that never had an iPhone locator does reach the right chapter on the iPhone, but only when `lastSpineIndex > 0`, and only at the start of that chapter (`ReadiumBook.swift:500-502`). A Mac read still inside the first spine item (`lastSpineIndex == 0`, fraction 0.4) does not qualify for the fallback at all.

**Smallest fix.** In `openBook`'s debounced write and the publication-end flush (`ReadiumReaderView.swift:1358-1386`), where `book` can resolve the locator, set `lastSpineIndex` from `spineIndex(for:)` (`ReadiumReaderView.swift:748`) and `lastScrollFraction` from `locations.progression` in the same save as `applyDebouncedReadiumLocator`. On the Mac, when `legacyReaderProgress == nil` and `readiumLocator` is non-empty, resume from that locator's href and progression instead of from `lastSpineIndex`. On the iPhone, when `legacyReaderProgress != nil`, do not pass the stored locator as `initialLocator`; resume from `lastSpineIndex` (including 0) and apply `lastScrollFraction` as `locations.progression` on the located item. In `applyProgress`, skip the spine-pair assignment when the incoming spine and fraction are both still 0, the incoming locator is non-empty, and the local spine or fraction is already ahead. A later iOS build that really returns to the start will have written the spine, and a newer timestamp then applies. Do not resume from `legacyReaderProgress`. It stays the card percent.

## A12-2 — a highlight deleted on one device stays on the other

In-reader delete inserts a `SyncTombstone` and leaves `signature` and `signerPublicKey` empty (`Models.swift:82-85`, defaulted in the initializer at `87-108`):

```846:853:kudos-ao3-reader/Features/ReaderReadium/ReadiumReaderView.swift
        modelContext.insert(SyncTombstone(
            recordID: annotation.id,
            recordType: .readingAnnotation,
            sourceURL: work.sourceURL,
            ao3WorkID: ao3WorkID
        ))
        modelContext.delete(annotation)
        try? modelContext.save()
```

The bookmark button does the same thing (`ReadiumReaderView.swift:720-726`). The note editor's Delete Highlight calls `deleteAnnotation` (`ReaderNoteEditor.swift:52-54`). The row is then gone, so the next export does not carry it and does not carry `isPendingDeletion`.

Peers drop that tombstone. Empty signature is not adopted:

```128:131:kudos-ao3-reader/Services/TombstoneSigning.swift
    static func shouldAdopt(_ archived: KudosBackupTombstone, defaults: UserDefaults = .standard) -> Bool {
        guard !archived.signature.isEmpty, !archived.signerPublicKey.isEmpty else { return false }
        guard verify(archived) else { return false }
        return TombstoneTrustStore.isTrusted(archived.signerPublicKey, defaults: defaults)
```

The drop is a `continue` (`KudosBackup.swift:2279-2293`). `resignLocalUnsignedIfNeeded` (`TombstoneSigning.swift:134-148`) signs empty rows once and then sets `migrationCompleteKey`, so a tombstone inserted after that pass stays unsigned.

The signed helper already exists and is what permanent work deletion uses (`WorkLifecycle.swift:189-191`):

```437:449:kudos-ao3-reader/Services/PersistenceSync.swift
    static func recordDeletion(
        of annotation: ReadingAnnotation, in context: ModelContext, reason: String = "workDeleted"
    ) {
        insertSigned(
            SyncTombstone(
                recordID: annotation.id,
                recordType: .readingAnnotation,
                createdAt: TombstoneSigning.now(),
                deletedOnDeviceID: PersistenceDevice.currentID(),
                deletionReason: reason
            ),
            in: context
        )
    }
```

`insertSigned` calls `TombstoneSigning.sign` (`PersistenceSync.swift:540-543`).

Signing alone does not remove a copy already on the other device. `restoreAnnotations` returns immediately when the archive lists no annotations, which is the case after the only mark was deleted:

```3785:3785:kudos-ao3-reader/Services/KudosBackup.swift
        guard !contents.manifest.annotations.isEmpty else { return }
```

```3798:3802:kudos-ao3-reader/Services/KudosBackup.swift
            switch tombstones.annotationResolution(id: archived.id, incomingModifiedAt: incomingModifiedAt) {
            case .suppressStaleData:
                // Deleted here on purpose — an older archive must not revive it.
                suppressed += 1
                continue
```

The function ends at the dedupe (`3873`) with no `applyTombstonesToExisting`. The comment on the update path says the incoming skip never sets the deletion flag, and that cross-device delete was expected to ride `isPendingDeletion` on a row that is still in the archive (`3826-3829`). The reader hard-deletes, so that flag never travels.

Reading sessions already do the other half. The comment states the hole:

```3529:3534:kudos-ao3-reader/Services/KudosBackup.swift
        // A record deleted on another device arrives as a tombstone with no record
        // behind it, so the loop above never sees it and the local copy survives.
        // Deletions have to be applied against what is already here.
        applyTombstonesToExisting(existing, in: context, mode: mode) {
            tombstones.readingSessionResolution(id: $0.id, incomingModifiedAt: $0.lastModifiedAt)
        }
```

Saved searches describe the same failure in the project's own words (`3086-3094`): the incoming loop only declines to add the row back, the copy already here stays, and the next export publishes it again. `applyTombstonesToExisting` (`3558-3568`) skips `.replaceLibrary` on purpose. Folder sync uses `.reconcile`, so the sweep would run there.

The invariants require an in-book annotation delete to be a hard delete plus a signed `.readingAnnotation` tombstone, so an older archive cannot resurrect it.

**Failing case.** Both devices have the same highlight (same id, synced earlier). On device B, tap the highlight and choose Delete Highlight. B saves an unsigned tombstone and deletes the row. Folder sync runs. Device A drops the tombstone at `shouldAdopt` and never walks its existing highlight, because the archive's annotation list no longer contains that id (and is empty if it was the only one). A still shows the highlight and exports it next time. B's local tombstone is indexed before the adopt filter (`KudosBackup.swift:2263-2276`), so B keeps suppressing that id and the highlight does not return to B. Edit the note on A. `lastModifiedAt` is now newer than B's `deletedAt`, `tombstoneResolution` returns `.reviveNewerData` (`PersistenceSync.swift:622-625`), and the highlight comes back on B too. After the delete, neither device should show it, and a later edit on A should not recreate it on B.

**Smallest fix.** Both reader sites should call `SyncTombstones.recordDeletion(of:in:)` and then `context.delete`, matching `WorkLifecycle.hardDelete`. `restoreAnnotations` should drop the empty-list return, or still run the sweep when the list is empty, and call `applyTombstonesToExisting` on the rows fetched before the loop, with `annotationResolution(id:incomingModifiedAt:)` and `$0.lastModifiedAt`. Leave the `.replaceLibrary` exclusion inside the helper.

## A12-3 — a removed queue membership or saved link survives on the other device

Queue removal signs a tombstone (`ReadingQueueService.swift:727-733` calls `recordDeletion(of: ReadingQueueMembership)`, `PersistenceSync.swift:424-434`). Saved-link deletion does the same (`PersistenceSync.swift:452-462`). Restore then only looks at rows the archive still contains.

Queue memberships:

```2953:2968:kudos-ao3-reader/Services/KudosBackup.swift
        for archived in contents.manifest.readingQueueMemberships {
            guard let work = restoredWorksByArchivedID[archived.workID] else { continue }
            switch tombstones.membershipResolution(
                id: archived.id,
                incomingModifiedAt: archived.lastModifiedAt ?? archived.queuedAt
            ) {
            case .suppressStaleData:
                suppressedQueueMemberships += 1
                continue
            case .preserveAmbiguous:
                ambiguousQueueConflicts += 1
            case .reviveNewerData, .noTombstone:
                break
            }
```

There is no sweep after this loop. The next call is `restoreAnnotations` (`3044`). `queuedAt` on the archive struct is a non-optional `Date` (`1518`), so `lastModifiedAt ?? queuedAt` is never nil and the `.preserveAmbiguous` arm does not insert a dateless membership.

Saved AO3 links:

```3122:3130:kudos-ao3-reader/Services/KudosBackup.swift
        for archived in contents.manifest.bookmarks {
            if mode != .replaceLibrary {
                switch tombstones.bookmarkResolution(
                    id: archived.id,
                    incomingModifiedAt: archived.dateAdded
                ) {
                case .suppressStaleData:
                    continue
```

```3143:3144:kudos-ao3-reader/Services/KudosBackup.swift
            bookmark.title = archived.title
            bookmark.dateAdded = archived.dateAdded
```

The following block (`3146-3153`) deletes local links only in `.replaceLibrary`, and only when the URL is absent from the snapshot. Reconcile never deletes a link that is already here. An existing link is also matched by URL and keeps its own id (`3135-3136`). A tombstone for the other device's id does not name that row.

Collection membership is the pattern to copy, not another hole: when a snapshot exists and the mode is not Replace, local members a tombstone covers are removed (`2706-2735`).

**Failing case.** The same work is in a queue on both devices, one membership id, from an earlier sync. Remove it from the queue on device B. B writes a signed `.readingQueueMembership` tombstone and deletes the row. Sync. Device A adopts the tombstone (`shouldAdopt` passes) and then never looks at the membership it already has, because B's archive no longer lists that id. The work stays in the queue on A. A's next export publishes the membership. B suppresses that id, so B's queue stays empty. The two queues disagree from then on. Removing it on B should remove it on A.

The same steps with a saved AO3 link (same id) leave the link on A. A second case: each device saved the same URL before any sync, so the ids differ. Restore matches by URL and does not adopt the archived id (`3135-3144`). A's tombstone does not cover B's id. B keeps the link and A later reinserts it. The sweep by id fixes the shared-id case. The URL case also has to delete the local row whose URL is the one just suppressed, or the restore has to give an existing link the archived id before tombstones are applied.

**Smallest fix.** After the membership loop, call `applyTombstonesToExisting` with `membershipResolution` and the local `lastModifiedAt`, as sessions do at `3532`. After the bookmark loop, and before the Replace omission pass, call it with `bookmarkResolution` and `dateAdded`. On `.suppressStaleData` for a bookmark, also delete the local row in `bookmarksByURL` for that URL. Do not add a second sweep for collection membership.

## A12-4 — Library select mode acts on works the chips have hidden

The bulk bar receives every selected work, with no filter and no privacy check:

```76:78:kudos-ao3-reader/Features/Library/LibraryView.swift
    private var selectedWorks: [SavedWork] {
        works.filter { selection.contains($0.id) }
    }
```

The title counts that same set (`136`, via `selection.count`). The dashboard carousels do not. They draw `cachedWorks`, which is `filters.apply` plus `passesPrivacy` (`284-291`). Entering select on the dashboard leaves the carousels up (`127-130`; `enterSelectMode` sets `showingSelectionList = false` at `796-801`). The fandom chips stay on that dashboard and write the filter:

```447:452:kudos-ao3-reader/Features/Library/LibraryView.swift
    private var shelvesDashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                fandomFilterBar
                localCarousel(.readingNow)
```

```588:594:kudos-ao3-reader/Features/Library/LibraryView.swift
                        filterChip("All", selected: filters.fandoms.isEmpty) {
                            filters.fandoms = []
                        }
                        ForEach(fandoms, id: \.self) { fandom in
                            filterChip(fandom, selected: filters.fandoms.contains(fandom)) {
                                filters.fandoms = filters.fandoms.contains(fandom) ? [] : [fandom]
```

`sectionsRevision` includes `filters.revisionKey`, `hideMature`, and the reveal gate (`262-279`), so the carousels rebuild. `selection` is not pruned. The privacy toggle is in the select toolbar whenever mature works are hidden (`653-656`) and changes that same gate. Select All itself is limited to `selectableWorks` (`792-794`). The bug is a selection made before the chip or the toggle.

Delete confirms, then soft-deletes `selectedWorks` (`WorkBulkActionBar.swift:128-144`). Favorite, finish, queue, and tag use the same array with no extra filter (`147-179`).

The queue browser states the rule this screen breaks:

```154:159:kudos-ao3-reader/Features/Library/ReadingQueueBrowser.swift
    /// Selection acts on what is on screen: Select hides the filter rail, so a
    /// filtered-out or hidden work must never be removed, moved, tagged or
    /// downloaded unseen (L3 B2 #1).
    private var selectedWorks: [SavedWork] {
        displayedWorks.filter { selection.contains($0.id) }
    }
```

`LibrarySectionListView.selectedWorks` is `visibleItems` (`145-147`) and its Select All writes those ids (`167-168`).

**Failing case.** On the Library dashboard, enter Select and tap five works from more than one fandom. The title reads "5 Selected". Tap one fandom chip. Four of the five leave the carousels. The title still reads "5 Selected". Tap Delete and confirm. `bulkDelete` soft-deletes all five, including the four no longer on screen. The same five are removed if, with mature hiding on, the reader reveals nothing and then taps the privacy control so previously visible adult works drop out of the carousels while their ids stay in `selection`. Confirming delete should affect only the works still on screen.

**Smallest fix.** Make `selectedWorks` filter through `selectableWorks` (already privacy- and filter-aware, `759-761`), and intersect `selection` with those ids when `filters` or the reveal gate changes. Point the title at that visible count. `toggleSelectAll` can stay as it is.

## A12-5 — Collection Select All includes works the filter hid

The list and its count use `visibleWorks` (`310`, `339`). The empty overlay says the filter matched nothing (`354-361`). Selection does not:

```534:545:kudos-ao3-reader/Features/Library/Collections.swift
    private var selectedWorks: [SavedWork] {
        works.filter { selection.contains($0.id) }
    }

    private var allSelected: Bool {
        let ids = Set(works.map(\.id))
        return !ids.isEmpty && ids.isSubset(of: selection)
    }

    private func toggleSelectAll() {
        selection = allSelected ? [] : Set(works.map(\.id))
    }
```

`works` is every non-deleted member (`147-149`). `visibleWorks` applies `filters` (`153-155`). The filter button is hidden once select mode starts (`402-411`), so a filter set beforehand still applies. `bulkRemove` (`560-563`) calls `remove` on `selectedWorks`, which writes a membership tombstone and detaches the work (`524-529`). The confirm dialog counts `selectedWorks` (`ScopedRemovalBulkActionBar.swift:130-142`).

**Failing case.** A collection has 10 works. Filter it down to 2. The header count is 2. Tap Select, then Select All. `selection` becomes all 10 ids. The list still shows 2 rows. The dialog says "Remove 10 works?". Confirm. All 10 lose the membership, including 8 the reader could not see. Select All should select the 2 visible works, and Remove should detach those 2.

**Smallest fix.** Base `selectedWorks`, `allSelected`, and `toggleSelectAll` on `visibleWorks`, as `LibrarySectionListView` does.

## A12-6 — Cancel leaves a highlight's new colour in place

The note draft is local until Done (`35`, `70-74`, seeded at `82-84`). The colour is written on the model as soon as the swatch is tapped, and `onCommit` runs:

```40:46:kudos-ao3-reader/Features/ReaderReadium/ReaderNoteEditor.swift
                    Section("Colour") {
                        ReadingAnnotationColorPicker(selected: annotation.color) { option in
                            annotation.color = option
                            annotation.markModified()
                            ReadingAnnotationColor.lastUsed = option
                            onCommit()
                        }
```

Cancel only dismisses:

```66:67:kudos-ao3-reader/Features/ReaderReadium/ReaderNoteEditor.swift
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
```

`onCommit` from this editor saves and redraws. `markModified` updates `lastModifiedAt`, so the next folder sync publishes the colour.

**Failing case.** Open a yellow highlight's note, tap blue, then tap Cancel. The note text is unchanged, which is what Cancel does for the draft. The highlight is blue on the page and stays blue after the editor closes. Cancel should restore yellow and leave `lastModifiedAt` as it was. Done should be what stores a colour change, or Cancel should write the colour captured in `onAppear` back onto the annotation and call `onCommit` again.

**Smallest fix.** Remember `annotation.color` in `onAppear`. On Cancel, if it differs, assign it back, call `markModified` only when a note change is also being kept (it is not, on Cancel), and call `onCommit` so the page repaints the original swatch.

## A12-7 — two tests stay green while A12-1 and A12-2 are broken

`ReadingAnnotationBackupTests.aDeletedAnnotationIsNotResurrectedByAnOlderArchive` (`KudosTests/ReadingAnnotationBackupTests.swift:109-140`) builds an archive that still contains the annotation, then inserts its own `SyncTombstone` into a second store that has no annotation row, and restores. It expects an empty fetch and `suppressedAnnotations == 1`. That is the incoming-row skip at `KudosBackup.swift:3798-3801`. The tombstone it inserts is unsigned (`128-132`), which is enough locally because local tombstones are indexed before `shouldAdopt`. The test never calls `deleteAnnotation` or `toggleBookmarkAtCurrentPosition`. It stays green if those functions keep writing an empty signature, and if a device that already has the highlight is never passed to `applyTombstonesToExisting`.

`SavedWorkProgressTests.lastReaderToWriteOwnsThePercent` (`KudosTests/SavedWorkProgressTests.swift:146-157`) sets a locator and a Mac percent and asserts `publicationProgress`. It stays green if `applyDebouncedReadiumLocator` never writes `lastSpineIndex`, and if `ReaderView.load` still opens at spine 0 after an iPhone read. `reReportedReadiumSpotKeepsTheMacPercent` (`161-169`) likewise asserts only the card percent.

**Smallest fix.** One test should delete through `SyncTombstones.recordDeletion(of: ReadingAnnotation)`, export, and restore onto a second context that already has that id, and expect the row to be gone and the stored tombstone to have a non-empty signature. One test should run `applyDebouncedReadiumLocator` (or the reader write once it also sets the spine) and expect `lastSpineIndex` and `lastScrollFraction` to match the locator, and expect `applyProgress` not to copy spine 0 over a local spine when the incoming locator is the only position the snapshot actually wrote.

## Known failing tests (not findings)

These two are the known environmental failures named in the brief. They were not re-run. They are not product bugs on the evidence below.

`KudosBackupTests.failedRestoreLeavesNoSwiftDataMutationsVisibleAfterCallerAutosave` (`KudosTests/KudosBackupTests.swift:293-335`) writes a real font file at `{base}.ttf` and creates a directory at `{base}-restored-1.ttf` (`300-301`). Restore builds `takenFileNames` from font rows and from directory entries whose `isDirectory` is not true (`KudosBackup.swift:3214-3228`), so the directory is not reserved. The original name is taken, `uniqueRestoredFileName` returns `{base}-restored-1.ttf` (`3231-3245`), and `data.write(to:options: .atomic)` hits that directory (`3307`). The test expects `NSCocoaErrorDomain` code 512. `FIXES-GROK-BACKUP.md` (around lines 145 and 166-170) and `FIXES-GROK-SIGNING.md` (around 237-242) record this simulator returning code 4, `NSFileNoSuchFileError`, with the message that `{base}-restored-1.ttf` doesn't exist. Those notes say the throw happens before `save`, and that the failure is the code comparison, not the rollback. `TASKS.md` T-336 says the same failure is present on commit `d5dde56d`.

`KudosBackupTests.invalidBackupEPUBLeavesValidLocalEPUBUnchanged` (`KudosTests/KudosBackupTests.swift:892-961`) feeds `Data("not-an-epub")` for a newer, non-preserved work and expects `hasEPUB` still true, the original bytes unchanged, and `skippedInvalidEPUBs == 1`. The restore path that matches that expectation is `KudosBackup.swift:2488-2516`: `mayReplaceEPUB` allows the attempt (`4343-4351`, local status is not `.preserved` and the archive is newer), `replaceEPUB` preflights with `EPUBDocument.inspectPackage`, and a throw increments `skippedInvalidEPUBs` and calls `journal.undoDisplacement`. `TASKS.md` T-336 and T-354 group this test with the font test as environmental and already failing on `d5dde56d`. `FIXES-GROK-BACKUP.md` and `FIXES-GROK-SIGNING.md` do not log which assertion failed. The cause is not established from the code. Nothing in that catch block is filed as a defect.

## Unconfirmed

- `createAnnotationFromSelection` stores `spineIndex` as `(book.readingPosition?.chapter ?? 1) - 1` (`ReadiumReaderView.swift:635`) and then uses that index for `chapterTitle` (`644`). Bookmarks use `spineIndex(for:)` href matching (`782`). The comment at `736-747` says `readingPosition.chapter` and the href index disagree when `locations.position` is missing. A navigator text selection usually has a position, so this may only mislabel. Confirm with a selection locator whose position is nil, or whose position-scan chapter is not the href's section: the contents row would name the other chapter. The highlight would still anchor by its locator string.

- No force unwrap, `try!`, or SwiftData use off the model actor was confirmed on the paths read. `FolderSyncService` uses `Task.detached` for file IO (`343`) and calls `restore` on the caller context. A hang from restoring many EPUBs, or from `LibraryView.backfillFilterMetadata` (`744-752`) walking every work, was not pinned to a concrete unbounded case. The invariants accept a full-table query up to the low thousands.

## What was not read

- `ReadiumBook.swift` past `open`, `readingPosition`, and the fallback comment. The position card, scrubber, and page-bar math were not traced.
- `ReaderSpeechController.swift` after the utterance-end / `onAdvance` handoff. The page-follow closure in `ReadiumReaderView` was not re-read in this pass. TTS engines were not read.
- `ReaderSearchView.swift` after about line 280, and `ReaderSearchGrouping.swift`. The search model up to the overlapping-iterator guard was read earlier and looked closed. It is not a finding.
- `ReaderContentsSheet`, the chapter list UI, and `ReaderNoteEditor` callers other than delete and colour.
- `ReadingLogService.swift` and `PreservedWorkService.swift` bodies, except the queue-removal tombstone call.
- `FolderSyncService.swift` past the restore call sites, `makeLocalContents`, and the read-before-write comment. Prune policy was not re-derived.
- `KudosBackup.apply` field by field, settings restore, font restore past the name collision used by the known test, and EPUB journal undo.
- `RecentlyDeletedView`, `ReadingQueueOrganizer`, and `LibraryFilters` matching. `PrivacyGate` was not read. The privacy claim in A12-4 uses `LibraryView.passesPrivacy` and `sectionsRevision` only.
- macOS `ReaderController` beyond `ReaderView.load` / `persist`.
- Annotation backup tests other than `aDeletedAnnotationIsNotResurrectedByAnOlderArchive`. `TombstoneSweepsExistingRecordsTests` was read. It covers saved searches only.
- `KUDOSBACKUP_FORMAT.md` was not re-read in this pass. The invariants doc is the behavior source used here. A version-number disagreement between those two docs was not treated as a reader-facing bug.

## Triage (Claude, 2026-10-08)

Each finding read against the Swift it cites.

- **A12-1 real, half fixed (iOS T-364).** The iPhone reader now writes the chapter and place
  with every position save, so the Mac opens where the iPhone stopped and an iPhone snapshot
  no longer carries zeros over the Mac's chapter. **Open:** after the Mac has read further,
  the iPhone still opens at its own last locator (the Mac never writes one). The fix is in
  the iPhone's open path (prefer the chapter and place when the Mac's percent is set); not
  done because it cannot be seen without a Mac and changes where a book opens. P2.
- **A12-2 real. First half fixed (T-364):** the reader's delete now records a signed
  tombstone. **Second half open, with A12-3:** a deletion does not remove the copy another
  device already has, for annotations, queue memberships and saved links. The same hole is
  on Android (`BackupMergeService.kt` sweeps saved searches, sessions, favourites and
  watermarks only). Android: brief 3bs item 7. iOS: next (T-366), following
  `applyTombstonesToExisting` and `TombstoneSweepsExistingRecordsTests`.
- **A12-4, A12-5, A12-6 real, fixed on iOS (T-364) and on Android**, which had all three
  (the Library dashboard's selection during a filter change, the collection page's, and
  Cancel in the note editor keeping a colour).
- **A12-7** (two tests that would stay green): follows the fixes above; a test for the
  signed reader tombstone and for the spine pair is still owed on iOS.
- **The two long-failing backup tests:** both were wrong tests, not wrong code. Fixed in
  T-363 (an OS-dependent error code; a fixture whose work was stamped newer than the
  archive, so the validator under test never ran).
