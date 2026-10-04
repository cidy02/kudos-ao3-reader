package io.github.cidy02.kudos.backup

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.publicationProgress
import io.github.cidy02.kudos.core.model.readiumProgress
import java.time.Instant
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The macOS reader's whole-book percent (`legacyReaderProgress`) across a merge: iOS
 * `PersistenceSyncTests`, the tests of the same names. It travels with the reading progress
 * and its clock, and a snapshot that has no such key is not a clear.
 */
class MacReadingPositionMergeTest {
    @Test
    fun newerMacPercentSurvivesBackupAndBeatsTheLocator() {
        val merged = restore(
            archived(mac = JsonPrimitive(0.37), locatorTotal = 0.2, at = 200),
            over = local(mac = null, locatorTotal = 0.8, at = 100)
        )

        assertEquals(0.37, merged.legacyReaderProgress!!, 0.0)
        assertEquals(0.37, merged.publicationProgress!!, 0.0)
    }

    @Test
    fun olderMacPercentLeavesNewerLocalProgress() {
        val merged = restore(
            archived(mac = JsonPrimitive(0.37), locatorTotal = null, at = 100),
            over = local(mac = 0.6, locatorTotal = null, at = 200)
        )

        assertEquals(0.6, merged.legacyReaderProgress!!, 0.0)
    }

    @Test
    fun olderProgressDoesNotBringItsMacPercentEvenWhenItsMetadataIsNewer() {
        // The other device edited the work later, and read it earlier. Its percent is part of
        // what it read, not of what it edited.
        val merged = restore(
            archived(mac = JsonPrimitive(0.37), locatorTotal = null, at = 100, metadataAt = 300),
            over = local(mac = 0.6, locatorTotal = null, at = 200)
        )

        assertEquals(0.6, merged.legacyReaderProgress!!, 0.0)
    }

    @Test
    fun newerSnapshotWithoutMacPercentClearsIt() {
        // iOS read last: its snapshot carries an explicit null, and that null must win.
        val merged = restore(
            archived(mac = JsonNull, locatorTotal = 0.8, at = 200),
            over = local(mac = 0.37, locatorTotal = 0.2, at = 100)
        )

        assertNull(merged.legacyReaderProgress)
        assertEquals(0.8, merged.publicationProgress!!, 0.0)
    }

    @Test
    fun keylessSnapshotAtTheSameTimeKeepsTheMacPercent() {
        // An older build wrote the work without the key, progress untouched.
        val merged = restore(
            archived(mac = null, locatorTotal = 0.2, at = 100),
            over = local(mac = 0.42, locatorTotal = 0.2, at = 100)
        )

        assertEquals(0.42, merged.legacyReaderProgress!!, 0.0)
    }

    @Test
    fun newerKeylessSnapshotClearsTheMacPercentWhenTheLocatorMoves() {
        val local = local(mac = 0.42, locatorTotal = 0.2, at = 100)

        val moved = restore(archived(mac = null, locatorTotal = 0.8, at = 200), over = local)
        assertEquals(0.8, moved.readiumProgress!!, 0.0)
        assertNull(moved.legacyReaderProgress)
        assertEquals(0.8, moved.publicationProgress!!, 0.0)

        val held = restore(archived(mac = null, locatorTotal = 0.2, at = 200), over = local)
        assertEquals(0.42, held.legacyReaderProgress!!, 0.0)

        // Less than the reader's own delta is not a move.
        val noise = restore(archived(mac = null, locatorTotal = 0.2005, at = 200), over = local)
        assertEquals(0.42, noise.legacyReaderProgress!!, 0.0)
    }

    private fun restore(archived: BackupWork, over: SavedWork): SavedWork = BackupMergeService.merge(
        current = BackupLibrarySnapshot(works = listOf(over)),
        backup = KudosBackupPackage(
            manifest = KudosBackupManifest(
                version = BackupVersion.CURRENT,
                exportedAt = "2026-03-01T00:00:00Z",
                exportedBy = BackupExportedBy(
                    platform = "ios",
                    appVersion = "test",
                    schemaVersion = BackupVersion.CURRENT
                ),
                works = listOf(archived),
                settings = BackupSettingsPayload()
            ),
            epubFilesByWorkId = emptyMap(),
            fontFilesByFileName = emptyMap()
        )
    ).snapshot.works.single()

    private fun local(mac: Double?, locatorTotal: Double?, at: Long) = SavedWork(
        id = WORK,
        title = "Mac Read",
        author = "Writer",
        sourceUrl = "https://archiveofourown.org/works/444",
        dateAdded = BASE,
        lastSpineIndex = 3,
        readiumLocator = locatorTotal?.let(::locator),
        legacyReaderProgress = mac,
        progressModifiedAt = BASE.plusSeconds(at),
        lastModifiedAt = BASE.plusSeconds(at)
    )

    /** [mac] null is a manifest with no such key; [JsonNull] is the key with an explicit null. */
    private fun archived(mac: JsonElement?, locatorTotal: Double?, at: Long, metadataAt: Long = at) = BackupWork(
        id = WORK,
        title = "Mac Read",
        author = "Writer",
        summary = "",
        sourceURL = "https://archiveofourown.org/works/444",
        dateAdded = BASE.toString(),
        isFavorite = false,
        isSaved = true,
        isFinished = false,
        hasEPUB = false,
        isComplete = true,
        lastSpineIndex = 3,
        lastScrollFraction = 0.0,
        readiumLocator = locatorTotal?.let(::locator),
        legacyReaderProgress = mac,
        progressModifiedAt = BASE.plusSeconds(at).toString(),
        lastModifiedAt = BASE.plusSeconds(metadataAt).toString()
    )

    private fun locator(total: Double) =
        """{"href":"ch.xhtml","type":"application/xhtml+xml","locations":{"totalProgression":$total}}"""

    private companion object {
        const val WORK = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        val BASE: Instant = Instant.parse("2026-01-01T00:00:00Z")
    }
}
