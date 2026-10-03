package io.github.cidy02.kudos.backup

import io.github.cidy02.kudos.core.model.SavedWork
import java.time.Instant
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

class DownloadedAtBackupTest {
    private val id = "11111111-1111-1111-1111-111111111111"
    private val added = Instant.parse("2023-11-14T22:13:20Z")
    private val downloaded = Instant.parse("2023-11-14T22:17:20Z")

    @Test
    fun workRoundTripsWithDownloadedAtInIosDateFormat() {
        val encoded = BackupJson.encodeToString(work(downloaded).toBackupWork())
        assertFalse(encoded.contains("\"downloadedAt\": null"))
        val decoded = BackupJson.decodeFromString<BackupWork>(encoded)

        assertEquals("2023-11-14T22:17:20.000Z", decoded.downloadedAt)
        assertEquals(downloaded, decoded.toSavedWork(hasEpub = false).downloadedAt)
    }

    @Test
    fun workRoundTripsWithoutDownloadedAtAndOmitsTheKey() {
        val encoded = BackupJson.encodeToString(work(null).toBackupWork())
        val decoded = BackupJson.decodeFromString<BackupWork>(encoded)

        assertFalse(encoded.contains("\"downloadedAt\""))
        assertNull(decoded.downloadedAt)
        assertNull(decoded.toSavedWork(hasEpub = false).downloadedAt)
    }

    @Test
    fun mergeNeverClearsLocalDateAndUsesPresentIncomingDateByRecency() {
        val localDate = Instant.parse("2023-11-14T22:15:20Z")
        val existing = work(localDate).copy(lastModifiedAt = added.plusSeconds(60))
        val absent = work(null).toBackupWork().copy(
            lastModifiedAt = BackupValidator.formatInstant(added.plusSeconds(120))
        )
        val afterAbsent = BackupMergeService.mergeWork(
            existing,
            absent.toSavedWork(hasEpub = false),
            absent,
            added.plusSeconds(120)
        )
        assertEquals(localDate, afterAbsent.downloadedAt)

        val present = work(downloaded).toBackupWork().copy(
            lastModifiedAt = BackupValidator.formatInstant(added.plusSeconds(180))
        )
        val afterPresent = BackupMergeService.mergeWork(
            afterAbsent,
            present.toSavedWork(hasEpub = false),
            present,
            added.plusSeconds(180)
        )
        assertEquals(downloaded, afterPresent.downloadedAt)

        val localWithoutDate = existing.copy(downloadedAt = null, lastModifiedAt = added.plusSeconds(300))
        val olderPresent = BackupMergeService.mergeWork(
            localWithoutDate,
            present.toSavedWork(hasEpub = false),
            present,
            added.plusSeconds(180)
        )
        assertEquals(downloaded, olderPresent.downloadedAt)
    }

    private fun work(downloadedAt: Instant?) = SavedWork(
        id = id,
        title = "Work",
        author = "Writer",
        dateAdded = added,
        downloadedAt = downloadedAt,
        hasEpub = false,
        lastModifiedAt = added
    )
}
