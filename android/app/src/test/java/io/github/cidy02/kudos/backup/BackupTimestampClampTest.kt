package io.github.cidy02.kudos.backup

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Duration
import java.time.Instant
import java.time.temporal.ChronoUnit

class BackupTimestampClampTest {

    @Test
    fun testParseInstant_RejectsFutureDate() {
        val now = Instant.now()
        val futureDate = now.plus(Duration.ofDays(10))
        val futureStr = BackupValidator.formatInstant(futureDate)

        val error = assertThrows(BackupError.InvalidDate::class.java) {
            BackupValidator.parseInstant(futureStr, "dateAdded", now = now)
        }
        assertEquals("dateAdded", error.field)
        assertEquals(futureStr, error.value)
    }

    @Test
    fun testParseInstant_KeepsPastDate() {
        val now = Instant.now()
        val pastDate = now.minus(Duration.ofDays(10))
        val pastStr = BackupValidator.formatInstant(pastDate)

        val parsed = BackupValidator.parseInstant(pastStr, "dateAdded", now = now)

        assertEquals(pastDate.truncatedTo(ChronoUnit.SECONDS), parsed.truncatedTo(ChronoUnit.SECONDS))
    }

    @Test
    fun testParseInstant_ClampsToExportedAt() {
        val now = Instant.now()
        val exportedAt = now.minus(Duration.ofDays(7))
        val forgedJustNow = BackupValidator.formatInstant(now)

        val parsed = BackupValidator.parseInstant(
            forgedJustNow,
            "work.lastModifiedAt",
            exportedAt = exportedAt,
            now = now
        )

        assertEquals(
            "forged just-now timestamp must clamp to the snapshot exportedAt",
            exportedAt,
            parsed
        )
    }

    @Test
    fun testParseInstant_KeepsDateBeforeExportedAt() {
        val now = Instant.now()
        val exportedAt = now.minus(Duration.ofDays(1))
        val older = now.minus(Duration.ofDays(30))

        val parsed = BackupValidator.parseInstant(
            BackupValidator.formatInstant(older),
            "work.lastModifiedAt",
            exportedAt = exportedAt,
            now = now
        )

        assertEquals(older.truncatedTo(ChronoUnit.SECONDS), parsed.truncatedTo(ChronoUnit.SECONDS))
    }

    @Test
    fun testIngestPaths_RejectFutureTimestamps() {
        val now = Instant.now()
        val farFuture = now.plus(Duration.ofDays(100))
        val futureStr = BackupValidator.formatInstant(farFuture)

        val workError = assertThrows(BackupError.InvalidDate::class.java) {
            BackupWork(
                id = "11111111-1111-1111-1111-111111111111",
                title = "Test",
                author = "Author",
                sourceURL = "https://archiveofourown.org/works/1",
                dateAdded = futureStr,
                lastModifiedAt = futureStr,
                hasEPUB = true
            ).toSavedWork(hasEpub = true)
        }
        assertTrue(
            "Work ingest must reject a > now+24h clock",
            workError.field.contains("dateAdded") || workError.field.contains("lastModifiedAt")
        )

        val collectionError = assertThrows(BackupError.InvalidDate::class.java) {
            BackupCollection(
                id = "22222222-2222-2222-2222-222222222222",
                name = "Test",
                dateAdded = futureStr,
                lastModifiedAt = futureStr
            ).toWorkCollection()
        }
        assertTrue(
            "Collection ingest must reject a > now+24h clock",
            collectionError.field.contains("dateAdded") ||
                collectionError.field.contains("lastModifiedAt")
        )

        val queueError = assertThrows(BackupError.InvalidDate::class.java) {
            BackupReadingQueue(
                id = "33333333-3333-3333-3333-333333333333",
                name = "Test",
                kindRaw = "custom",
                sortOrder = 0,
                dateCreated = futureStr,
                dateUpdated = futureStr
            ).toReadingQueue()
        }
        assertTrue(
            "Queue ingest must reject a > now+24h clock",
            queueError.field.contains("dateCreated") || queueError.field.contains("dateUpdated")
        )
    }

    @Test
    fun testMerge_RejectsFutureTimestampsOnWorksAndCollections() {
        val now = Instant.now()
        val farFuture = now.plus(Duration.ofDays(100))
        val futureStr = BackupValidator.formatInstant(farFuture)
        val nowStr = BackupValidator.formatInstant(now)

        val error = assertThrows(BackupError.InvalidDate::class.java) {
            BackupMergeService.merge(
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
        }
        assertTrue(
            "Merge must reject a > now+24h archive clock, was field=${error.field}",
            error.field.contains("dateAdded") ||
                error.field.contains("lastModifiedAt") ||
                error.field.contains("exportedAt")
        )
    }

    @Test
    fun testMerge_ClampsLastModifiedAtToExportedAt() {
        val now = Instant.now().truncatedTo(ChronoUnit.MILLIS)
        val exportedAt = now.minus(Duration.ofDays(7))
        val forgedJustNow = BackupValidator.formatInstant(now)
        val exportedStr = BackupValidator.formatInstant(exportedAt)
        val workId = "11111111-1111-1111-1111-111111111111"

        val first = BackupMergeService.merge(
            current = BackupLibrarySnapshot(),
            backup = KudosBackupPackage(
                manifest = KudosBackupManifest(
                    version = BackupVersion.CURRENT,
                    exportedAt = exportedStr,
                    works = listOf(
                        BackupWork(
                            id = workId,
                            title = "Hostile just-now",
                            author = "Author",
                            sourceURL = "https://archiveofourown.org/works/1",
                            dateAdded = forgedJustNow,
                            lastModifiedAt = forgedJustNow,
                            hasEPUB = true
                        )
                    )
                )
            ),
            now = now
        )

        val afterHostile = first.snapshot.works.single()
        assertEquals(
            "Merged work lastModifiedAt must clamp to exportedAt",
            exportedAt,
            afterHostile.lastModifiedAt
        )
        assertEquals(
            "Merged work dateAdded must clamp to exportedAt",
            exportedAt,
            afterHostile.dateAdded
        )

        val genuineModified = now.minus(Duration.ofDays(3))
        val genuine = BackupMergeService.merge(
            current = first.snapshot,
            backup = KudosBackupPackage(
                manifest = KudosBackupManifest(
                    version = BackupVersion.CURRENT,
                    exportedAt = BackupValidator.formatInstant(now),
                    works = listOf(
                        BackupWork(
                            id = workId,
                            title = "Genuine later backup",
                            author = "Author",
                            sourceURL = "https://archiveofourown.org/works/1",
                            dateAdded = exportedStr,
                            lastModifiedAt = BackupValidator.formatInstant(genuineModified),
                            hasEPUB = true
                        )
                    )
                )
            ),
            now = now
        )

        val afterGenuine = genuine.snapshot.works.single()
        assertEquals("Genuine later backup", afterGenuine.title)
        assertEquals(
            "Genuine lastModifiedAt (between exportedAt and now) must win LWW",
            genuineModified,
            afterGenuine.lastModifiedAt
        )
    }

    @Test
    fun testMerge_RejectsFutureExportedAt() {
        val now = Instant.now()
        val futureExported = BackupValidator.formatInstant(now.plus(Duration.ofDays(10)))

        val error = assertThrows(BackupError.InvalidDate::class.java) {
            BackupMergeService.merge(
                current = BackupLibrarySnapshot(),
                backup = KudosBackupPackage(
                    manifest = KudosBackupManifest(
                        version = BackupVersion.CURRENT,
                        exportedAt = futureExported
                    )
                ),
                now = now
            )
        }
        assertEquals("exportedAt", error.field)
    }
}
