package io.github.cidy02.kudos.backup

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.Duration
import java.time.temporal.ChronoUnit

class BackupTimestampClampTest {

    @Test
    fun testParseInstant_ClampsFutureDate() {
        val now = Instant.now()
        val futureDate = now.plus(Duration.ofDays(10))
        val futureStr = BackupValidator.formatInstant(futureDate)

        val parsed = BackupValidator.parseInstant(futureStr, "dateAdded")

        // Should be clamped to now + 24h
        val maxAllowed = now.plus(24, ChronoUnit.HOURS)
        assertEquals(maxAllowed.truncatedTo(ChronoUnit.SECONDS), parsed.truncatedTo(ChronoUnit.SECONDS))
    }

    @Test
    fun testParseInstant_KeepsPastDate() {
        val now = Instant.now()
        val pastDate = now.minus(Duration.ofDays(10))
        val pastStr = BackupValidator.formatInstant(pastDate)

        val parsed = BackupValidator.parseInstant(pastStr, "dateAdded")

        assertEquals(pastDate.truncatedTo(ChronoUnit.SECONDS), parsed.truncatedTo(ChronoUnit.SECONDS))
    }

    @Test
    fun testIngestPaths_ClampFutureTimestamps() {
        val now = Instant.now()
        val farFuture = now.plus(Duration.ofDays(100))
        val futureStr = BackupValidator.formatInstant(farFuture)
        val maxAllowed = now.plus(24, ChronoUnit.HOURS).plusSeconds(5)

        // Work path
        val work = BackupWork(
            id = "11111111-1111-1111-1111-111111111111",
            title = "Test",
            author = "Author",
            sourceURL = "https://archiveofourown.org/works/1",
            dateAdded = futureStr, // Out of bounds
            lastModifiedAt = futureStr, // Out of bounds
            hasEPUB = true
        ).toSavedWork(hasEpub = true)
        
        assertTrue("Work dateAdded should be clamped", !work.dateAdded.isAfter(maxAllowed))
        assertTrue("Work lastModifiedAt should be clamped", !work.lastModifiedAt!!.isAfter(maxAllowed))

        // Collection path
        val collection = BackupCollection(
            id = "22222222-2222-2222-2222-222222222222",
            name = "Test",
            dateAdded = futureStr, // Out of bounds
            lastModifiedAt = futureStr // Out of bounds
        ).toWorkCollection()

        assertTrue("Collection dateAdded should be clamped", !collection.dateAdded.isAfter(maxAllowed))
        assertTrue("Collection lastModifiedAt should be clamped", !collection.lastModifiedAt!!.isAfter(maxAllowed))

        // Queue path
        val queue = BackupReadingQueue(
            id = "33333333-3333-3333-3333-333333333333",
            name = "Test",
            kindRaw = "custom",
            sortOrder = 0,
            dateCreated = futureStr, // Out of bounds
            dateUpdated = futureStr // Out of bounds
        ).toReadingQueue()

        assertTrue("Queue dateCreated should be clamped", !queue.dateCreated.isAfter(maxAllowed))
        assertTrue("Queue dateUpdated should be clamped", !queue.dateUpdated.isAfter(maxAllowed))
    }

    @Test
    fun testMerge_ClampFutureTimestampsOnWorksAndCollections() {
        val now = Instant.now()
        val farFuture = now.plus(Duration.ofDays(100))
        val futureStr = BackupValidator.formatInstant(farFuture)
        val nowStr = BackupValidator.formatInstant(now)
        val maxAllowed = now.plus(24, ChronoUnit.HOURS).plusSeconds(5)

        val result = BackupMergeService.merge(
            current = BackupLibrarySnapshot(),
            backup = KudosBackupPackage(
                manifest = KudosBackupManifest(
                    version = BackupVersion.CURRENT,
                    exportedAt = nowStr,
                    works = listOf(
                        BackupWork(
                            id = "11111111-1111-1111-1111-111111111111",
                            title = "Test",
                            author = "Author",
                            sourceURL = "https://archiveofourown.org/works/1",
                            dateAdded = futureStr,
                            lastModifiedAt = futureStr,
                            hasEPUB = true
                        )
                    ),
                    collections = listOf(
                        BackupCollection(
                            id = "22222222-2222-2222-2222-222222222222",
                            name = "Test",
                            dateAdded = futureStr,
                            lastModifiedAt = futureStr
                        )
                    )
                )
            )
        )

        val work = result.snapshot.works.single()
        val collection = result.snapshot.collections.single()
        assertTrue("Merged work dateAdded should be clamped", !work.dateAdded.isAfter(maxAllowed))
        assertTrue("Merged work lastModifiedAt should be clamped", !work.lastModifiedAt!!.isAfter(maxAllowed))
        assertTrue("Merged collection dateAdded should be clamped", !collection.dateAdded.isAfter(maxAllowed))
        assertTrue(
            "Merged collection lastModifiedAt should be clamped",
            !collection.lastModifiedAt!!.isAfter(maxAllowed)
        )
    }
}
