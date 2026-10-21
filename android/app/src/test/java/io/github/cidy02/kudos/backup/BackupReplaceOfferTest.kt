package io.github.cidy02.kudos.backup

import io.github.cidy02.kudos.core.model.Bookmark
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.ReadingQueueKind
import io.github.cidy02.kudos.core.model.SavedSearch
import io.github.cidy02.kudos.core.model.WorkCollection
import java.time.Instant
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * iOS offers Replace whenever it would remove something Merge cannot
 * (`hasAnythingReplaceWouldRemove`), not only when the device has works.
 */
class BackupReplaceOfferTest {
    private val added = Instant.parse("2026-10-20T12:00:00Z")

    @Test
    fun noWorksButABookmarkOffersReplaceAndTheAlwaysThereQueueDoesNot() {
        val bookmarkOnly = BackupMergeService.preview(
            current = BackupLibrarySnapshot(
                bookmarks = listOf(Bookmark(title = "A link", urlString = "https://example.com/a", dateAdded = added))
            ),
            backup = emptyPackage()
        )
        assertTrue(bookmarkOnly.hasReplaceableRecords)
        assertTrue(bookmarkOnly.isLibraryEmpty)

        val searchOnly = BackupMergeService.preview(
            current = BackupLibrarySnapshot(
                savedSearches = listOf(SavedSearch(name = "Slow burn", dateAdded = added))
            ),
            backup = emptyPackage()
        )
        assertTrue(searchOnly.hasReplaceableRecords)

        val liveCollection = BackupMergeService.preview(
            current = BackupLibrarySnapshot(
                collections = listOf(WorkCollection(name = "Favorites", isDeleted = false))
            ),
            backup = emptyPackage()
        )
        assertTrue(liveCollection.hasReplaceableRecords)

        val deletedCollectionOnly = BackupMergeService.preview(
            current = BackupLibrarySnapshot(
                collections = listOf(WorkCollection(name = "Gone", isDeleted = true))
            ),
            backup = emptyPackage()
        )
        assertFalse(deletedCollectionOnly.hasReplaceableRecords)

        val customQueue = BackupMergeService.preview(
            current = BackupLibrarySnapshot(
                readingQueues = listOf(ReadingQueue(name = "Weekend", kindRaw = ReadingQueueKind.CUSTOM))
            ),
            backup = emptyPackage()
        )
        assertTrue(customQueue.hasReplaceableRecords)

        val savedForLaterOnly = BackupMergeService.preview(
            current = BackupLibrarySnapshot(
                readingQueues = listOf(
                    ReadingQueue(name = "Saved for Later", kindRaw = ReadingQueueKind.SAVED_FOR_LATER)
                )
            ),
            backup = emptyPackage()
        )
        assertFalse(savedForLaterOnly.hasReplaceableRecords)

        assertFalse(
            BackupMergeService.preview(BackupLibrarySnapshot(), emptyPackage()).hasReplaceableRecords
        )
    }

    @Test
    fun farFewerWorksUsesIosLargeRemovalThreshold() {
        // The old rule warned whenever the file held under half the works.
        val underHalf = BackupImportPreview(
            localWorkCount = 10, fileWorkCount = 4, willAdd = 0, willRemove = 6, inBoth = 4
        )
        assertFalse(underHalf.isMuchSmallerThanLibrary)

        val nineteen = BackupImportPreview(
            localWorkCount = 100, fileWorkCount = 10, willAdd = 0, willRemove = 19, inBoth = 10
        )
        assertFalse(nineteen.isMuchSmallerThanLibrary)

        // 20 removed, and at least ten times the additions. The file is not under half
        // the library, which is the case the old rule missed.
        val large = BackupImportPreview(
            localWorkCount = 40, fileWorkCount = 30, willAdd = 2, willRemove = 20, inBoth = 28
        )
        assertTrue(large.isMuchSmallerThanLibrary)

        val notTenfold = BackupImportPreview(
            localWorkCount = 40, fileWorkCount = 30, willAdd = 3, willRemove = 20, inBoth = 27
        )
        assertFalse(notTenfold.isMuchSmallerThanLibrary)
    }

    private fun emptyPackage() = KudosBackupPackage(
        manifest = KudosBackupManifest(version = BackupVersion.CURRENT, exportedAt = "2026-10-20T00:00:00Z")
    )
}
