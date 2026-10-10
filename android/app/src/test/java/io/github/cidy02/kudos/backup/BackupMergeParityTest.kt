package io.github.cidy02.kudos.backup

import com.google.crypto.tink.subtle.Ed25519Sign
import io.github.cidy02.kudos.core.model.Bookmark
import io.github.cidy02.kudos.core.model.ReadingAnnotation
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.ReadingQueueKind
import io.github.cidy02.kudos.core.model.ReadingQueueMembership
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.SyncTombstone
import io.github.cidy02.kudos.core.model.SyncTombstoneRecordType
import io.github.cidy02.kudos.core.model.WorkCollection
import java.time.Instant
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Small snapshots for Brief 3bs. No Room, files, demo fixtures or network. */
class BackupMergeParityTest {
    @Before
    fun signingKey() {
        val key = Ed25519Sign.KeyPair.newKeyPair()
        TombstoneSigning.initializeWithRawKeyPair(key.privateKey, key.publicKey)
    }

    @After
    fun resetSigningKey() = TombstoneSigning.resetForTests()

    @Test
    fun dateAddedAndDateCreatedKeepTheEarlierCopyRegardlessOfWinner() {
        for (mode in BackupImportMode.entries) {
            for (localWins in listOf(false, true)) {
                for (localEarlier in listOf(false, true)) {
                    val localDate = at(if (localEarlier) 10 else 20)
                    val archiveDate = at(if (localEarlier) 20 else 10)
                    val localClock = at(if (localWins) 300 else 100)
                    val archiveClock = at(if (localWins) 100 else 300)
                    val local = BackupLibrarySnapshot(
                        works = listOf(work().copy(dateAdded = localDate, lastModifiedAt = localClock)),
                        collections = listOf(collection().copy(dateAdded = localDate, lastModifiedAt = localClock)),
                        readingQueues = listOf(queue().copy(dateCreated = localDate, dateUpdated = localClock))
                    )
                    val remote = BackupLibrarySnapshot(
                        works = listOf(work().copy(dateAdded = archiveDate, lastModifiedAt = archiveClock)),
                        collections = listOf(collection().copy(dateAdded = archiveDate, lastModifiedAt = archiveClock)),
                        readingQueues = listOf(queue().copy(dateCreated = archiveDate, dateUpdated = archiveClock))
                    )
                    val result = merge(local, remote, mode)
                    // iOS skips an ACTIVE File Merge work entirely; its date stays local.
                    assertEquals(if (mode == BackupImportMode.MERGE) localDate else at(10), result.works.single().dateAdded)
                    assertEquals(at(10), result.collections.single().dateAdded)
                    assertEquals(at(10), result.readingQueues.single().dateCreated)
                }
            }
        }
    }

    @Test
    fun fileMergeOfDeletedWorkAlsoKeepsEarlierDateAddedWithEitherClockWinner() {
        for (localClock in listOf(at(100), at(300))) {
            val local = work().copy(dateAdded = at(20), lastModifiedAt = localClock, isDeleted = true)
            val result = merge(BackupLibrarySnapshot(works = listOf(local)),
                BackupLibrarySnapshot(works = listOf(work().copy(dateAdded = at(10), lastModifiedAt = at(200)))),
                BackupImportMode.MERGE)
            assertEquals(at(10), result.works.single().dateAdded)
            assertFalse(result.works.single().isDeleted)
        }
    }

    @Test
    fun replaceLibraryTakesArchiveQueueAndMembershipRegardlessOfLocalClock() {
        for (localClock in listOf(at(100), at(300))) {
            val local = BackupLibrarySnapshot(
                works = listOf(work()),
                readingQueues = listOf(queue().copy(name = "Local", dateUpdated = localClock, lastMembershipChangedAt = localClock, notes = "local")),
                readingQueueMemberships = listOf(member().copy(lastModifiedAt = localClock, sortOrderInQueue = 8, note = "local"))
            )
            val remote = BackupLibrarySnapshot(
                works = listOf(work()),
                readingQueues = listOf(queue().copy(name = "Archive", dateUpdated = at(200), lastMembershipChangedAt = at(200), notes = "archive")),
                readingQueueMemberships = listOf(member().copy(lastModifiedAt = at(200), sortOrderInQueue = 2, note = "archive"))
            )
            val result = merge(local, remote, BackupImportMode.REPLACE_LIBRARY)
            assertEquals("Archive", result.readingQueues.single().name)
            assertEquals("archive", result.readingQueues.single().notes)
            // Swift takes archive contents, but keeps the maximum of existing edit clocks.
            assertEquals(maxOf(localClock, at(200)), result.readingQueues.single().dateUpdated)
            assertEquals(maxOf(localClock, at(200)), result.readingQueues.single().lastMembershipChangedAt)
            assertEquals(2, result.readingQueueMemberships.single().sortOrderInQueue)
            assertEquals("archive", result.readingQueueMemberships.single().note)
            val reconciled = merge(local, remote)
            assertEquals(if (localClock > at(200)) "Local" else "Archive", reconciled.readingQueues.single().name)
            assertEquals(if (localClock > at(200)) 8 else 2, reconciled.readingQueueMemberships.single().sortOrderInQueue)
        }
    }

    @Test
    fun replaceLibraryKeepsReadingSessionsAndFavouritesLastWriteWins() {
        for (localClock in listOf(at(100), at(300))) {
            val session = io.github.cidy02.kudos.data.local.entity.ReadingSessionEntity(id = ANN, workID = WORK,
                startedAt = at(10), endedAt = at(20), durationSeconds = 10.0, lastModifiedAt = localClock)
            val favourite = io.github.cidy02.kudos.data.local.entity.ReadingFavoriteEntity(id = LINK, kindRaw = "tag",
                targetKey = "Comfort", displayName = "Local", createdAt = at(10), lastModifiedAt = localClock)
            val local = BackupLibrarySnapshot(readingSessions = listOf(session), readingFavorites = listOf(favourite))
            val remote = local.copy(readingSessions = listOf(session.copy(durationSeconds = 20.0, lastModifiedAt = at(200))),
                readingFavorites = listOf(favourite.copy(displayName = "Archive", lastModifiedAt = at(200))))
            val result = merge(local, remote, BackupImportMode.REPLACE_LIBRARY)
            assertEquals(if (localClock > at(200)) 10.0 else 20.0, result.readingSessions.single().durationSeconds, 0.0)
            assertEquals(if (localClock > at(200)) "Local" else "Archive", result.readingFavorites.single().displayName)
        }
    }

    @Test
    fun replaceLibraryStillPinsSystemQueueNameAndKind() {
        val local = queue().copy(kindRaw = ReadingQueueKind.SAVED_FOR_LATER, name = "Saved for Later", dateUpdated = at(300))
        val remote = local.copy(id = OTHER, name = "Renamed", notes = "snapshot", dateUpdated = at(100))
        val result = merge(BackupLibrarySnapshot(readingQueues = listOf(local)),
            BackupLibrarySnapshot(readingQueues = listOf(remote)), BackupImportMode.REPLACE_LIBRARY)
        val q = result.readingQueues.single()
        assertEquals(QUEUE, q.id)
        assertEquals(ReadingQueueKind.SAVED_FOR_LATER_NAME, q.name)
        assertEquals(ReadingQueueKind.SAVED_FOR_LATER, q.kindRaw)
        assertEquals("snapshot", q.notes)
    }

    @Test
    fun fileMergeReturnsCollectionAndQueueAndClearsAllDeletionFields() {
        for (localClock in listOf(at(100), at(300))) {
            val local = BackupLibrarySnapshot(
                collections = listOf(collection().copy(lastModifiedAt = localClock, isDeleted = true,
                    deletedAt = at(50), permanentDeletionScheduledAt = at(500))),
                readingQueues = listOf(queue().copy(dateUpdated = localClock, isDeleted = true,
                    deletedAt = at(50), permanentDeletionScheduledAt = at(500)))
            )
            val result = merge(local, BackupLibrarySnapshot(collections = listOf(collection()), readingQueues = listOf(queue())), BackupImportMode.MERGE)
            val c = result.collections.single()
            assertFalse(c.isDeleted)
            assertNull(c.deletedAt)
            assertNull(c.permanentDeletionScheduledAt)
            val q = result.readingQueues.single()
            assertFalse(q.isDeleted)
            assertNull(q.deletedAt)
            assertNull(q.permanentDeletionScheduledAt)
            assertEquals(localClock, q.dateUpdated)
        }
    }

    @Test
    fun fileMergeOnlyClearsDeletionFieldsOnContainersItActuallyReturns() {
        val c = collection().copy(deletedAt = at(50), permanentDeletionScheduledAt = at(500))
        val q = queue().copy(deletedAt = at(50), permanentDeletionScheduledAt = at(500))
        val result = merge(BackupLibrarySnapshot(collections = listOf(c), readingQueues = listOf(q)),
            BackupLibrarySnapshot(collections = listOf(collection()), readingQueues = listOf(queue())), BackupImportMode.MERGE)
        assertEquals(c.deletedAt, result.collections.single().deletedAt)
        assertEquals(c.permanentDeletionScheduledAt, result.collections.single().permanentDeletionScheduledAt)
        assertEquals(q.deletedAt, result.readingQueues.single().deletedAt)
        assertEquals(q.permanentDeletionScheduledAt, result.readingQueues.single().permanentDeletionScheduledAt)
    }

    @Test
    fun fileMergeRetractsSavedWorkTombstonesByUuidAo3IdAndCanonicalAddress() {
        val unrelated = tombstone(OTHER, SyncTombstoneRecordType.SAVED_WORK)
        val wrongKind = tombstone(WORK, SyncTombstoneRecordType.READING_ANNOTATION)
        val tombstones = listOf(
            tombstone(WORK, SyncTombstoneRecordType.SAVED_WORK),
            tombstone(OTHER, SyncTombstoneRecordType.SAVED_WORK).copy(ao3WorkID = 42),
            tombstone(OTHER, SyncTombstoneRecordType.SAVED_WORK).copy(sourceURL = "https://archiveofourown.org/works/42/chapters/1?view_full_work=true"),
            unrelated, wrongKind
        )
        for (localClock in listOf(at(100), at(300))) {
            val result = merge(BackupLibrarySnapshot(works = listOf(work().copy(isDeleted = true, lastModifiedAt = localClock)), tombstones = tombstones),
                BackupLibrarySnapshot(works = listOf(work())), BackupImportMode.MERGE)
            assertEquals(setOf(unrelated.id, wrongKind.id), result.tombstones.map { it.id }.toSet())
            // The next export must allow a peer with no row to acquire the work.
            assertEquals(WORK, merge(BackupLibrarySnapshot(), result).works.single().id)
        }
    }

    @Test
    fun aWinningSameIdAnnotationParksTheDisplacedNoteWithItsOriginalAnchorAndDates() {
        for (mode in listOf(BackupImportMode.RECONCILE, BackupImportMode.REPLACE_LIBRARY)) {
            for (localClock in listOf(at(100), at(200), at(300))) {
                val old = annotation().copy(note = "old", lastModifiedAt = localClock, colorRaw = "pink",
                    selectedText = "selection", progression = 0.4, spineIndex = 2, chapterTitle = "Two")
                val incoming = old.copy(note = "new", locatorString = "new locator", colorRaw = "blue", lastModifiedAt = at(200))
                val local = BackupLibrarySnapshot(works = listOf(work()), annotations = listOf(old))
                val remote = BackupLibrarySnapshot(works = listOf(work()), annotations = listOf(incoming))
                val result = merge(local, remote, mode)
                val archiveWins = mode == BackupImportMode.REPLACE_LIBRARY || localClock <= at(200)
                assertEquals(if (archiveWins) "new" else "old", result.annotations.single { it.id == ANN }.note)
                if (archiveWins) {
                    val parked = result.annotations.single { it.id != ANN }
                    assertEquals(old.copy(id = parked.id, workID = WORK, isPendingDeletion = true,
                        deletedAt = NOW, lastModifiedAt = NOW), parked)
                    assertNotEquals(ANN, parked.id)
                    assertEquals(parked, merge(result, result, mode).annotations.single { it.id == parked.id })
                } else assertEquals(1, result.annotations.size)
            }
        }
    }

    @Test
    fun noteEditedBetweenCaptureAndApplyIsAlsoParkedWhenArchiveStillWins() {
        val old = annotation().copy(note = "captured", lastModifiedAt = at(100))
        val local = BackupLibrarySnapshot(works = listOf(work()), annotations = listOf(old))
        val remote = old.copy(note = "archive", lastModifiedAt = at(200))
        val plan = BackupMergeService.merge(local, KudosBackupPackage(KudosBackupManifest(
            version = BackupVersion.CURRENT, exportedAt = NOW.toString(), works = listOf(work().toBackupWork()),
            annotations = listOf(remote.toBackupAnnotation())
        )), now = NOW)
        val fresh = local.copy(annotations = listOf(old.copy(note = "typed during import", lastModifiedAt = at(150))))
        val result = BackupMergeService.refreshForApply(plan, fresh).snapshot
        assertEquals("archive", result.annotations.single { it.id == ANN }.note)
        assertEquals(setOf("captured", "typed during import", "archive"), result.annotations.map { it.note }.toSet())
        assertTrue(result.annotations.filter { it.id != ANN }.all { it.isPendingDeletion })
    }

    @Test
    fun parkedNoteUsesIosKindAndColourFallbacksForUnknownStoredRawValues() {
        val old = annotation().copy(kindRaw = "note", colorRaw = "unknown", note = "old", lastModifiedAt = at(100))
        val remote = old.copy(kindRaw = "highlight", colorRaw = "blue", note = "new", lastModifiedAt = at(200))
        val result = merge(BackupLibrarySnapshot(works = listOf(work()), annotations = listOf(old)),
            BackupLibrarySnapshot(works = listOf(work()), annotations = listOf(remote)))
        val parked = result.annotations.single { it.id != ANN }
        assertEquals("bookmark", parked.kindRaw)
        assertEquals("yellow", parked.colorRaw)
        assertEquals("old", parked.note)
    }

    @Test
    fun identicalEmptyAndFileMergeNotesDoNotCreateSalvageRows() {
        for (oldNote in listOf("", "same")) {
            val local = annotation().copy(note = oldNote, lastModifiedAt = at(100))
            val remote = local.copy(note = "same", lastModifiedAt = at(200))
            assertEquals(1, merge(BackupLibrarySnapshot(works = listOf(work()), annotations = listOf(local)),
                BackupLibrarySnapshot(works = listOf(work()), annotations = listOf(remote))).annotations.size)
        }
        val result = merge(BackupLibrarySnapshot(works = listOf(work()), annotations = listOf(annotation().copy(note = "old"))),
            BackupLibrarySnapshot(works = listOf(work()), annotations = listOf(annotation().copy(note = "new", lastModifiedAt = at(300)))), BackupImportMode.MERGE)
        assertEquals("old", result.annotations.single().note)
    }

    @Test
    fun ao3UnavailableIsMonotonicAndAssetIdentifierOnlyFillsAnEmptyLocalValue() {
        for (mode in listOf(BackupImportMode.RECONCILE, BackupImportMode.REPLACE_LIBRARY)) {
            for (localClock in listOf(at(100), at(300))) {
                for (localUnavailable in listOf(false, true)) {
                    for (localAsset in listOf("", " ", "local.epub")) {
                        val local = work().copy(lastModifiedAt = localClock, ao3Unavailable = localUnavailable, assetIdentifier = localAsset)
                        val remote = work().copy(lastModifiedAt = at(200), ao3Unavailable = !localUnavailable, assetIdentifier = "archive.epub")
                        val result = merge(BackupLibrarySnapshot(works = listOf(local)), BackupLibrarySnapshot(works = listOf(remote)), mode).works.single()
                        assertTrue(result.ao3Unavailable)
                        assertEquals(localAsset.ifEmpty { "archive.epub" }, result.assetIdentifier)
                    }
                }
            }
        }
    }

    @Test
    fun sameWorkKindAndExactLocatorCollapseToNewestAndSalvageBothNotes() {
        for (localClock in listOf(at(100), at(300))) {
            val old = annotation().copy(note = "local", lastModifiedAt = localClock)
            val remote = old.copy(id = OTHER, note = "archive", lastModifiedAt = at(200))
            val result = merge(BackupLibrarySnapshot(works = listOf(work()), annotations = listOf(old)),
                BackupLibrarySnapshot(works = listOf(work()), annotations = listOf(remote)))
            val winnerId = if (localClock > at(200)) ANN else OTHER
            val loserId = if (winnerId == ANN) OTHER else ANN
            assertEquals(winnerId, result.annotations.single { !it.isPendingDeletion }.id)
            assertEquals(setOf("local", "archive"), result.annotations.map { it.note }.toSet())
            assertTrue(result.tombstones.any { it.recordID == loserId && it.deletionReason == "samePassageDeduped" && TombstoneSigning.verify(it) })
            if (loserId == ANN) assertTrue(result.annotations.single { it.id == ANN }.isPendingDeletion)
            else assertTrue(result.annotations.none { it.id == OTHER })
        }
    }

    @Test
    fun samePassageWithEmptyWinnerFillsTheNoteAndStampsTheContentEdit() {
        val old = annotation().copy(note = "keep", lastModifiedAt = at(100))
        val remote = old.copy(id = OTHER, note = "", lastModifiedAt = at(200))
        val result = merge(BackupLibrarySnapshot(works = listOf(work()), annotations = listOf(old)),
            BackupLibrarySnapshot(works = listOf(work()), annotations = listOf(remote)))
        val winner = result.annotations.single { !it.isPendingDeletion }
        assertEquals(OTHER, winner.id)
        assertEquals("keep", winner.note)
        assertEquals(NOW, winner.lastModifiedAt)
    }

    /** Android only: rows with no locator (its oldest builds) are never "the same passage". */
    @Test
    fun annotationsWithNoLocatorAreNeverCollapsed() {
        val a = annotation().copy(locatorString = "", note = "first")
        val b = a.copy(id = OTHER, note = "second")
        val result = merge(BackupLibrarySnapshot(works = listOf(work()), annotations = listOf(a)),
            BackupLibrarySnapshot(works = listOf(work()), annotations = listOf(b)))
        assertEquals(setOf(ANN, OTHER), result.annotations.filter { !it.isPendingDeletion }.map { it.id }.toSet())
        assertEquals(2, result.annotations.size) // nothing parked, nothing hidden
    }

    @Test
    fun samePassageDedupIsExactAndUsesUuidToBreakEqualClockTies() {
        val a = annotation()
        val b = a.copy(id = OTHER)
        val result = merge(BackupLibrarySnapshot(works = listOf(work()), annotations = listOf(a)),
            BackupLibrarySnapshot(works = listOf(work()), annotations = listOf(b)))
        assertEquals(minOf(ANN, OTHER), result.annotations.single { !it.isPendingDeletion }.id)
        val different = listOf(b.copy(locatorString = "different"), b.copy(kindRaw = "note"), b.copy(workID = OTHER))
        for (other in different) {
            val r = merge(BackupLibrarySnapshot(works = listOf(work(), work().copy(id = OTHER, sourceUrl = "", ao3WorkID = null)), annotations = listOf(a)),
                BackupLibrarySnapshot(works = listOf(work(), work().copy(id = OTHER, sourceUrl = "", ao3WorkID = null)), annotations = listOf(other)))
            assertEquals(2, r.annotations.count { !it.isPendingDeletion })
        }
    }

    @Test
    fun pendingDeletionRowsAndAnnotationsWithoutAResolvedWorkDoNotCompeteInDedup() {
        val live = annotation()
        val hidden = live.copy(id = OTHER, isPendingDeletion = true, deletedAt = at(300), note = "hidden")
        val result = merge(BackupLibrarySnapshot(works = listOf(work()), annotations = listOf(live, hidden)),
            BackupLibrarySnapshot(works = listOf(work()), annotations = listOf(live)))
        assertEquals(2, result.annotations.size)
        assertEquals("hidden", result.annotations.single { it.id == OTHER }.note)
        val orphans = listOf(live, live.copy(id = OTHER))
        val skipped = merge(BackupLibrarySnapshot(annotations = orphans), BackupLibrarySnapshot(annotations = listOf(live)))
        assertEquals(orphans, skipped.annotations)
    }

    @Test
    fun trustedRemoteTombstonesRemoveExistingAnnotationsMembershipsAndSavedLinksUsingRowClocks() {
        for (mode in listOf(BackupImportMode.MERGE, BackupImportMode.RECONCILE)) {
            for (rowClock in listOf(at(100), at(200), at(300))) {
                for (kind in listOf("highlight", "note", "bookmark")) {
                    val local = BackupLibrarySnapshot(works = listOf(work()), readingQueues = listOf(queue()),
                        annotations = listOf(annotation().copy(kindRaw = kind, lastModifiedAt = rowClock)),
                        readingQueueMemberships = listOf(member().copy(lastModifiedAt = rowClock)),
                        bookmarks = listOf(link().copy(dateAdded = rowClock)))
                    val deletions = listOf(tombstone(ANN, SyncTombstoneRecordType.READING_ANNOTATION),
                        tombstone(MEMBER, SyncTombstoneRecordType.READING_QUEUE_MEMBERSHIP), tombstone(LINK, SyncTombstoneRecordType.BOOKMARK))
                        .map { TombstoneSigning.sign(it) }
                    val result = merge(local, BackupLibrarySnapshot(tombstones = deletions), mode)
                    val expected = if (rowClock > at(200)) 1 else 0
                    assertEquals(expected, result.annotations.size)
                    assertEquals(expected, result.readingQueueMemberships.size)
                    assertEquals(expected, result.bookmarks.size)
                }
            }
        }
    }

    /**
     * Audit A30-4, as iOS T-376. The mark was deleted on the other device and then brought back there,
     * newer than the deletion. Merge skipped it because this device still had the old copy, then swept
     * the old copy as deleted: neither was left.
     */
    @Test
    fun aMarkBroughtBackAfterItsDeletionSurvivesWhenTheCopyHereIsTheDeletedOne() {
        fun library(note: String, clock: Instant, deleted: Boolean = false) = BackupLibrarySnapshot(works = listOf(work()),
            annotations = listOf(annotation().copy(note = note, lastModifiedAt = clock)),
            tombstones = if (deleted) listOf(TombstoneSigning.sign(tombstone(ANN, SyncTombstoneRecordType.READING_ANNOTATION))) else emptyList())
        for (mode in listOf(BackupImportMode.MERGE, BackupImportMode.RECONCILE)) {
            val result = merge(library("before the deletion", at(100)), library("brought back", at(300), deleted = true), mode)
            assertEquals(listOf("brought back"), result.annotations.filter { !it.isPendingDeletion }.map { it.note })
        }
        // Merge still never overwrites a live mark nobody deleted.
        val kept = merge(library("mine", at(100)), library("theirs, newer", at(300)), BackupImportMode.MERGE)
        assertEquals(listOf("mine"), kept.annotations.map { it.note })
    }

    @Test
    fun tombstoneSecondPassUsesCreatedAndQueuedFallbacksAndNeverSnapshotExportTime() {
        val local = BackupLibrarySnapshot(works = listOf(work()), readingQueues = listOf(queue()),
            annotations = listOf(annotation().copy(createdAt = at(100), lastModifiedAt = null)),
            readingQueueMemberships = listOf(member().copy(queuedAt = at(100), lastModifiedAt = null)),
            tombstones = listOf(tombstone(ANN, SyncTombstoneRecordType.READING_ANNOTATION), tombstone(MEMBER, SyncTombstoneRecordType.READING_QUEUE_MEMBERSHIP)))
        val result = merge(local, BackupLibrarySnapshot())
        assertTrue(result.annotations.isEmpty())
        assertTrue(result.readingQueueMemberships.isEmpty())
    }

    @Test
    fun suppressedIncomingLinkRemovesSameAddressLocalIdButKeepsANewerLocalAdd() {
        for (localClock in listOf(at(100), at(200), at(300))) {
            val localLink = link().copy(dateAdded = localClock)
            val archivedLink = link().copy(id = OTHER, dateAdded = at(100))
            val remote = BackupLibrarySnapshot(bookmarks = listOf(archivedLink),
                tombstones = listOf(TombstoneSigning.sign(tombstone(OTHER, SyncTombstoneRecordType.BOOKMARK))))
            val result = merge(BackupLibrarySnapshot(bookmarks = listOf(localLink)), remote)
            if (localClock > at(200)) assertEquals(localLink, result.bookmarks.single())
            else assertTrue(result.bookmarks.isEmpty())
        }
    }

    @Test
    fun unknownAndUnsignedIncomingTombstonesDoNotRemoveExistingRows() {
        val local = BackupLibrarySnapshot(works = listOf(work()), annotations = listOf(annotation()), readingQueues = listOf(queue()),
            readingQueueMemberships = listOf(member()), bookmarks = listOf(link()))
        val key = Ed25519Sign.KeyPair.newKeyPair()
        val unsigned = listOf(tombstone(ANN, SyncTombstoneRecordType.READING_ANNOTATION), tombstone(MEMBER, SyncTombstoneRecordType.READING_QUEUE_MEMBERSHIP), tombstone(LINK, SyncTombstoneRecordType.BOOKMARK))
        for (signed in listOf(false, true)) {
            // Switch signer after preparing the foreign rows so the merge does not trust it as its own.
            if (signed) TombstoneSigning.initializeWithRawKeyPair(key.privateKey, key.publicKey)
            val remote = BackupLibrarySnapshot(tombstones = if (signed) unsigned.map { TombstoneSigning.sign(it) } else unsigned)
            signingKey()
            val result = merge(local, remote)
            assertEquals(local.annotations, result.annotations)
            assertEquals(local.readingQueueMemberships, result.readingQueueMemberships)
            assertEquals(local.bookmarks, result.bookmarks)
        }
    }

    @Test
    fun repeatedReplaceBypassesAllThreeTombstoneSecondPasses() {
        val content = BackupLibrarySnapshot(works = listOf(work()), annotations = listOf(annotation()), readingQueues = listOf(queue()),
            readingQueueMemberships = listOf(member()), bookmarks = listOf(link()))
        val local = content.copy(tombstones = listOf(tombstone(ANN, SyncTombstoneRecordType.READING_ANNOTATION),
            tombstone(MEMBER, SyncTombstoneRecordType.READING_QUEUE_MEMBERSHIP), tombstone(LINK, SyncTombstoneRecordType.BOOKMARK)))
        val first = merge(local, content, BackupImportMode.REPLACE_LIBRARY)
        val second = merge(first, content, BackupImportMode.REPLACE_LIBRARY)
        assertEquals(1, second.annotations.size)
        assertEquals(1, second.readingQueueMemberships.size)
        assertEquals(LINK, second.bookmarks.single().id)
    }

    private fun merge(local: BackupLibrarySnapshot, remote: BackupLibrarySnapshot,
        mode: BackupImportMode = BackupImportMode.RECONCILE): BackupLibrarySnapshot = BackupMergeService.merge(
        local, KudosBackupPackage(KudosBackupManifest(version = BackupVersion.CURRENT, exportedAt = NOW.toString(),
            works = remote.works.map { it.toBackupWork() }, collections = remote.collections.map { it.toBackupCollection() },
            readingQueues = remote.readingQueues.map { it.toBackupReadingQueue() },
            readingQueueMemberships = remote.readingQueueMemberships.map { it.toBackupReadingQueueMembership() },
            annotations = remote.annotations.map { it.toBackupAnnotation() }, bookmarks = remote.bookmarks.map { it.toBackupBookmark() },
            tombstones = remote.tombstones.map { it.toBackupTombstone() },
            readingSessions = remote.readingSessions.map { it.toBackupReadingSession() },
            readingFavorites = remote.readingFavorites.map { it.toBackupReadingFavorite() })), mode, now = NOW
    ).snapshot

    private fun work() = SavedWork(id = WORK, title = "Work", author = "Writer", dateAdded = at(10),
        sourceUrl = "https://archiveofourown.org/works/42", ao3WorkID = 42, lastModifiedAt = at(200))
    private fun queue() = ReadingQueue(id = QUEUE, name = "Queue", dateCreated = at(10), dateUpdated = at(200))
    private fun collection() = WorkCollection(id = COLLECTION, name = "Collection", dateAdded = at(10), lastModifiedAt = at(200))
    private fun member() = ReadingQueueMembership(id = MEMBER, queueID = QUEUE, workID = WORK, queuedAt = at(10), lastModifiedAt = at(200))
    private fun annotation() = ReadingAnnotation(id = ANN, workID = WORK, kindRaw = "highlight", colorRaw = "yellow",
        locatorString = "exact locator", createdAt = at(10), lastModifiedAt = at(200))
    private fun link() = Bookmark(id = LINK, title = "Link", urlString = "https://archiveofourown.org/works/42", dateAdded = at(100))
    private fun tombstone(id: String, kind: String) = SyncTombstone(recordID = id, recordTypeRaw = kind, createdAt = at(200), lastModifiedAt = at(200))
    private fun at(seconds: Long) = BASE.plusSeconds(seconds)

    private companion object {
        const val WORK = "11111111-1111-4111-8111-111111111111"
        const val QUEUE = "22222222-2222-4222-8222-222222222222"
        const val COLLECTION = "33333333-3333-4333-8333-333333333333"
        const val MEMBER = "44444444-4444-4444-8444-444444444444"
        const val ANN = "55555555-5555-4555-8555-555555555555"
        const val LINK = "66666666-6666-4666-8666-666666666666"
        const val OTHER = "77777777-7777-4777-8777-777777777777"
        val BASE: Instant = Instant.parse("2026-01-01T00:00:00Z")
        val NOW: Instant = BASE.plusSeconds(1000)
    }
}
