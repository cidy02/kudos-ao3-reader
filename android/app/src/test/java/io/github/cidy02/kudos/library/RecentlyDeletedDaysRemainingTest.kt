package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.ui.components.WorkOrigin
import io.github.cidy02.kudos.ui.components.WorkRedownloadability
import io.github.cidy02.kudos.ui.components.deleteConfirmationMessage
import io.github.cidy02.kudos.ui.components.shouldConfirmDelete
import io.github.cidy02.kudos.ui.components.workDeletionMessage
import io.github.cidy02.kudos.works.WorkConversionRecord
import java.nio.file.Files
import java.time.Instant
import java.time.temporal.ChronoUnit
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RecentlyDeletedDaysRemainingTest {
    @Test
    fun fullDaysRemainingUsesExactCount() {
        val now = Instant.parse("2026-06-26T12:00:00Z")
        val scheduled = now.plus(90, ChronoUnit.DAYS)

        assertEquals(90L, daysRemainingUntil(scheduled, now))
    }

    @Test
    fun partialDayRoundsUpInsteadOfFlooring() {
        val now = Instant.parse("2026-06-26T12:00:00Z")
        // 89 days + 1 hour left → floor would be 89; ceiling is 90.
        val scheduled = now.plus(89, ChronoUnit.DAYS).plus(1, ChronoUnit.HOURS)

        assertEquals(90L, daysRemainingUntil(scheduled, now))
    }

    @Test
    fun underOneDayStillShowsOneDayLeft() {
        val now = Instant.parse("2026-06-26T12:00:00Z")
        val scheduled = now.plus(3, ChronoUnit.HOURS)

        assertEquals(1L, daysRemainingUntil(scheduled, now))
    }

    @Test
    fun pastOrEqualScheduledIsZero() {
        val now = Instant.parse("2026-06-26T12:00:00Z")

        assertEquals(0L, daysRemainingUntil(now, now))
        assertEquals(0L, daysRemainingUntil(now.minusSeconds(1), now))
    }

    @Test
    fun daysLeftLabelAndRedThresholdAtSevenDays() {
        assertEquals("1 day left", daysLeftLabel(1))
        assertEquals("7 days left", daysLeftLabel(7))
        assertEquals("90 days left", daysLeftLabel(90))

        assertTrue(isUrgent(0))
        assertTrue(isUrgent(1))
        assertTrue(isUrgent(6))
        assertTrue(isUrgent(7))
        assertFalse(isUrgent(8))
        assertFalse(isUrgent(30))
        assertFalse(isUrgent(90))
    }

    @Test
    fun sortsRowsSoonestToGoFirst() {
        val entry30 = sampleEntry(id = "a", daysRemaining = 30)
        val entry2 = sampleEntry(id = "b", daysRemaining = 2)
        val entry7 = sampleEntry(id = "c", daysRemaining = 7)

        assertEquals(
            listOf("b", "c", "a"),
            sortedSoonestFirst(listOf(entry30, entry2, entry7)).map { it.id }
        )

        val state = RecentlyDeletedUiState(
            loading = false,
            deletedEntries = listOf(entry30, entry7),
            heldEntries = listOf(entry2)
        )
        assertEquals(listOf("b", "c", "a"), state.allEntries.map { it.id })
    }

    @Test
    fun reasonTextPerOriginAndImportFormat() {
        val ao3Ok = WorkRedownloadability.of(
            origin = WorkOrigin.ARCHIVE_OF_OUR_OWN,
            ao3Unavailable = false
        )
        assertTrue(ao3Ok.canRedownload)
        assertNull(ao3Ok.rowTitle)
        assertNull(ao3Ok.rowBody)

        val ao3Gone = WorkRedownloadability.of(
            origin = WorkOrigin.ARCHIVE_OF_OUR_OWN,
            ao3Unavailable = true
        )
        assertFalse(ao3Gone.canRedownload)
        assertEquals("No longer on AO3.", ao3Gone.rowTitle)
        assertEquals(
            "The author removed it or made it private, so Kudos can't download it again.",
            ao3Gone.rowBody
        )

        val ffnPdf = WorkRedownloadability.of(
            origin = WorkOrigin.FANFICTION_NET,
            ao3Unavailable = false,
            importFormatDisplayName = "PDF"
        )
        assertFalse(ffnPdf.canRedownload)
        assertEquals("Imported PDF from FanFiction.net.", ffnPdf.rowTitle)
        assertEquals(
            "Kudos can only download from AO3, so this copy is the only one.",
            ffnPdf.rowBody
        )
        assertEquals("a PDF from FanFiction.net", ffnPdf.importSourcePhrase)

        val pdfOnly = WorkRedownloadability.of(
            origin = WorkOrigin.IMPORTED_FILE,
            ao3Unavailable = false,
            importFormatDisplayName = "PDF"
        )
        assertEquals("Imported PDF.", pdfOnly.rowTitle)
        assertEquals("a PDF", pdfOnly.importSourcePhrase)

        val siteOnly = WorkRedownloadability.of(
            origin = WorkOrigin.FANFICTION_NET,
            ao3Unavailable = false,
            importFormatDisplayName = null
        )
        assertEquals("Imported from FanFiction.net.", siteOnly.rowTitle)
        assertEquals("FanFiction.net", siteOnly.importSourcePhrase)

        val plainFile = WorkRedownloadability.of(
            origin = WorkOrigin.IMPORTED_FILE,
            ao3Unavailable = false,
            importFormatDisplayName = null
        )
        assertEquals("Imported file.", plainFile.rowTitle)
        assertEquals("a file", plainFile.importSourcePhrase)

        val unknownSite = WorkRedownloadability.of(
            origin = WorkOrigin.UNKNOWN,
            ao3Unavailable = false,
            importFormatDisplayName = null
        )
        assertEquals("Imported from another site.", unknownSite.rowTitle)
        assertEquals("another site", unknownSite.importSourcePhrase)

        val unknownEpub = WorkRedownloadability.of(
            origin = WorkOrigin.UNKNOWN,
            ao3Unavailable = false,
            importFormatDisplayName = "EPUB"
        )
        assertEquals("Imported EPUB from another site.", unknownEpub.rowTitle)
        assertEquals("an EPUB from another site", unknownEpub.importSourcePhrase)

        val htmlImport = WorkRedownloadability.of(
            origin = WorkOrigin.WATTPAD,
            ao3Unavailable = false,
            importFormatDisplayName = "HTML"
        )
        assertEquals("an HTML from Wattpad", htmlImport.importSourcePhrase)

        val rtfImport = WorkRedownloadability.of(
            origin = WorkOrigin.IMPORTED_FILE,
            ao3Unavailable = false,
            importFormatDisplayName = "RTF"
        )
        assertEquals("an RTF", rtfImport.importSourcePhrase)

        val epubImport = WorkRedownloadability.of(
            origin = WorkOrigin.IMPORTED_FILE,
            ao3Unavailable = false,
            importFormatDisplayName = "EPUB"
        )
        assertEquals("an EPUB", epubImport.importSourcePhrase)
    }

    @Test
    fun escalatedMessagesAndBulkCountsForSoftAndPermanentDelete() {
        val available = SavedWork(
            id = "11111111-1111-4111-8111-111111111111",
            title = "Available Work",
            author = "Writer",
            ao3WorkID = 101,
            sourceUrl = "https://archiveofourown.org/works/101"
        )
        val unavailable = SavedWork(
            id = "22222222-2222-4222-8222-222222222222",
            title = "Gone Work",
            author = "Writer",
            ao3WorkID = 202,
            sourceUrl = "https://archiveofourown.org/works/202",
            ao3Unavailable = true
        )
        val importedFfn = SavedWork(
            id = "33333333-3333-4333-8333-333333333333",
            title = "Rescued Fic",
            author = "Writer",
            sourceUrl = "https://www.fanfiction.net/s/1/1/"
        )

        val softAvailable = workDeletionMessage(listOf(available))
        assertEquals(
            "Kudos will move “Available Work” to Recently Deleted. You can restore it for the next 90 days.",
            softAvailable
        )

        val softUnavailable = workDeletionMessage(listOf(unavailable))
        assertEquals(
            "“Gone Work” is no longer on AO3, so Kudos can't download it again. It stays in Recently Deleted for 90 days, then it's gone for good.",
            softUnavailable
        )

        val permUnavailable = deleteConfirmationMessage(
            title = "Gone Work",
            reason = WorkRedownloadability.NoLongerOnAO3,
            permanently = true
        )
        assertEquals(
            "“Gone Work” is no longer on AO3, so Kudos can't download it again. You can't undo this.",
            permUnavailable
        )

        val ffnPdfReason = WorkRedownloadability.of(
            origin = WorkOrigin.FANFICTION_NET,
            ao3Unavailable = false,
            importFormatDisplayName = "PDF"
        )
        assertEquals(
            "“Imported Story” was imported from a PDF from FanFiction.net. Kudos only downloads from AO3, so this is the only copy. It stays in Recently Deleted for 90 days, then it's gone for good.",
            deleteConfirmationMessage(title = "Imported Story", reason = ffnPdfReason, permanently = false)
        )
        assertEquals(
            "“Imported Story” was imported from a PDF from FanFiction.net. Kudos only downloads from AO3, so this is the only copy.",
            deleteConfirmationMessage(title = "Imported Story", reason = ffnPdfReason, permanently = true)
        )

        val fiveWorks = listOf(
            available,
            available.copy(id = "44444444-4444-4444-8444-444444444444"),
            available.copy(id = "55555555-5555-4555-8555-555555555555"),
            unavailable,
            importedFfn
        )
        val bulkSoft = workDeletionMessage(fiveWorks)
        assertTrue(bulkSoft.contains("2 of these 5 can't be downloaded again."))
        assertTrue(bulkSoft.contains("90 days"))

        val bulkPerm = deleteConfirmationMessage(itemCount = 5, irreplaceableCount = 2, permanently = true)
        assertEquals(
            "Kudos will permanently remove each item and any download, progress, or notes stored with it. You can't undo this. 2 of these 5 can't be downloaded again.",
            bulkPerm
        )

        val bulkPermAllRedownloadable = deleteConfirmationMessage(itemCount = 3, irreplaceableCount = 0, permanently = true)
        assertEquals(
            "Kudos will permanently remove each item and any download, progress, or notes stored with it. The works stay on AO3. You can't undo this.",
            bulkPermAllRedownloadable
        )
    }

    @Test
    fun irreplaceableCountIgnoresCollectionsAndQueues() {
        val entries = listOf(
            sampleEntry(id = "w1", noun = "work", redownloadability = WorkRedownloadability.CanRedownload),
            sampleEntry(id = "w2", noun = "work", redownloadability = WorkRedownloadability.NoLongerOnAO3),
            sampleEntry(
                id = "h1",
                noun = "work",
                isHeldCopy = true,
                redownloadability = WorkRedownloadability.of(WorkOrigin.FANFICTION_NET, false, "PDF")
            ),
            sampleEntry(id = "c1", noun = "collection", redownloadability = WorkRedownloadability.NoLongerOnAO3),
            sampleEntry(id = "q1", noun = "reading queue", redownloadability = WorkRedownloadability.NoLongerOnAO3)
        )
        assertEquals(2, irreplaceableCount(entries))
        assertTrue(bulkPermanentMessage(entries).contains("2 of these 5 can't be downloaded again."))
        assertEquals(
            "1 of these can't be downloaded again once it's gone.",
            reassuranceIrreplaceableLine(1)
        )
        assertEquals(
            "2 of these can't be downloaded again once they're gone.",
            reassuranceIrreplaceableLine(2)
        )
    }

    @Test
    fun workStillOnAo3DeletesWithoutQuestionWhenSettingIsOffWhileIrreplaceableAsks() {
        val onAo3 = SavedWork(
            id = "11111111-1111-4111-8111-111111111111",
            title = "Still On AO3",
            author = "Author",
            ao3WorkID = 42,
            sourceUrl = "https://archiveofourown.org/works/42",
            ao3Unavailable = false
        )
        val goneFromAo3 = onAo3.copy(
            id = "22222222-2222-4222-8222-222222222222",
            ao3Unavailable = true
        )
        val nonAo3Import = SavedWork(
            id = "33333333-3333-4333-8333-333333333333",
            title = "Local Import",
            author = "Author",
            sourceUrl = "https://www.fanfiction.net/s/99/1/"
        )

        assertFalse(shouldConfirmDelete(onAo3, settingOn = false))
        assertTrue(shouldConfirmDelete(onAo3, settingOn = true))

        assertTrue(shouldConfirmDelete(goneFromAo3, settingOn = false))
        assertTrue(shouldConfirmDelete(nonAo3Import, settingOn = false))

        assertFalse(shouldConfirmDelete(listOf(onAo3), settingOn = false))
        assertTrue(shouldConfirmDelete(listOf(onAo3, nonAo3Import), settingOn = false))
    }

    @Test
    fun resolvesImportFormatAndOriginalFileFromWorkFileStore() = runBlocking {
        val tempDir = Files.createTempDirectory("kudos-a463-test")
        try {
            val store = WorkFileStore(tempDir)
            val workId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
            store.writeOriginal(workId, "pdf", "%PDF-1.4 sample".toByteArray())
            store.writeConversionRecord(
                workId,
                WorkConversionRecord(
                    format = "pdf",
                    originalFileName = "my-story.pdf",
                    converterPlatform = "android"
                ).encode()
            )
            val work = SavedWork(
                id = workId,
                title = "Converted Story",
                author = "Author",
                sourceUrl = "https://www.fanfiction.net/s/10/1/"
            )
            val reason = WorkRedownloadability.of(work, store)
            assertEquals("Imported PDF from FanFiction.net.", reason.rowTitle)

            val original = WorkRedownloadability.originalFile(workId, store)
            assertEquals("my-story.pdf", original?.suggestedName)
        } finally {
            tempDir.toFile().deleteRecursively()
        }
    }

    @Test
    fun worksUrlOnNonAo3HostWithNoAo3WorkIdGetsWarningAndAsks() {
        val mirrorWork = SavedWork(
            id = "66666666-6666-4666-8666-666666666666",
            title = "Mirror Copy",
            author = "Author",
            ao3WorkID = null,
            sourceUrl = "https://ao3.satr.dev/works/555",
            hasAo3WorkId = true
        )
        val mirrorReason = WorkRedownloadability.of(mirrorWork)
        assertFalse(mirrorReason.canRedownload)
        assertEquals("Imported from AO3 mirror.", mirrorReason.rowTitle)
        assertTrue(shouldConfirmDelete(mirrorWork, settingOn = false))

        val otherWorksUrl = SavedWork(
            id = "77777777-7777-4777-8777-777777777777",
            title = "Other Site Copy",
            author = "Author",
            ao3WorkID = null,
            sourceUrl = "https://example.org/works/555",
            hasAo3WorkId = true
        )
        val otherReason = WorkRedownloadability.of(otherWorksUrl)
        assertFalse(otherReason.canRedownload)
        assertEquals("Imported from another site.", otherReason.rowTitle)
        assertTrue(shouldConfirmDelete(otherWorksUrl, settingOn = false))
    }

    @Test
    fun concealedMatureWorksUseThisWorkAndHiddenTitle() {
        val secretWork = SavedWork(
            id = "88888888-8888-4888-8888-888888888888",
            title = "Secret Title",
            author = "Author",
            ao3WorkID = 10,
            sourceUrl = "https://archiveofourown.org/works/10",
            ao3Unavailable = true,
            rating = "Explicit"
        )

        val obscuredMsg = workDeletionMessage(
            listOf(secretWork),
            visibility = { LibraryPrivacyVisibility.Obscured }
        )
        assertFalse(obscuredMsg.contains("Secret Title"))
        assertEquals(
            "this work is no longer on AO3, so Kudos can't download it again. It stays in Recently Deleted for 90 days, then it's gone for good.",
            obscuredMsg
        )

        val hiddenMsg = deleteConfirmationMessage(
            work = secretWork,
            permanently = true,
            visibility = LibraryPrivacyVisibility.Hidden
        )
        assertFalse(hiddenMsg.contains("Secret Title"))
        assertEquals(
            "this work is no longer on AO3, so Kudos can't download it again. You can't undo this.",
            hiddenMsg
        )

        assertEquals(
            LibraryPrivacy.HIDDEN_WORK_TITLE,
            LibraryPrivacy.shownTitle(secretWork, LibraryPrivacyVisibility.Obscured)
        )
        assertEquals(
            LibraryPrivacy.HIDDEN_WORK_TITLE,
            LibraryPrivacy.shownTitle(secretWork, LibraryPrivacyVisibility.Hidden)
        )
        assertEquals(
            "Delete this work permanently?",
            recentlyDeletedDeleteTitle(secretWork, isHeldCopy = false, visibility = LibraryPrivacyVisibility.Obscured)
        )
        assertEquals(
            "Remove the copy of this work?",
            recentlyDeletedDeleteTitle(secretWork, isHeldCopy = true, visibility = LibraryPrivacyVisibility.Hidden)
        )
    }

    private fun sampleEntry(
        id: String,
        daysRemaining: Int = 10,
        noun: String = "work",
        isHeldCopy: Boolean = false,
        redownloadability: WorkRedownloadability = WorkRedownloadability.CanRedownload
    ): RecentlyDeletedEntry = RecentlyDeletedEntry(
        id = id,
        kicker = "Work",
        noun = noun,
        title = "Title $id",
        detail = "Author",
        daysRemaining = daysRemaining,
        isHeldCopy = isHeldCopy,
        deleteTitle = "Delete?",
        deleteLabel = "Delete Permanently",
        redownloadability = redownloadability
    )
}
