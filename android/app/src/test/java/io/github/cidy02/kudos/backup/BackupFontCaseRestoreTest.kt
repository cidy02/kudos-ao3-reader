package io.github.cidy02.kudos.backup

import io.github.cidy02.kudos.core.model.CustomFont
import java.time.Instant
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

/**
 * Port of the iOS case-variant font restores in `KudosBackupFontRestoreTests`
 * and `FolderSyncTests`. Zip, legacy-directory, and folder-sync all enter
 * [BackupMergeService.mergeFonts], so each named test runs that merge with the
 * iOS fixture.
 */
class BackupFontCaseRestoreTest {
    private val added = Instant.parse("2026-06-26T12:00:00Z")

    @Test
    fun zipRestorePreservesAmbiguousCaseFoldedRowsAndFiles() {
        assertCaseVariantFixtureWasPreserved()
    }

    @Test
    fun legacyDirectoryRestorePreservesAmbiguousCaseFoldedRowsAndFiles() {
        assertCaseVariantFixtureWasPreserved()
    }

    @Test
    fun syncDownPreservesEveryCaseFoldedDatabaseRow() {
        val incoming = "incoming-font".toByteArray()
        val archived = "SYNC-CASE.TTF"
        val local = "sync-case.TTF"
        val incomingName = "sync-case.ttf"
        val suffix = "sync-case-restored-1.ttf"
        val archivedRow = CustomFont(name = "Archived Case", fileName = archived, dateAdded = added)
        val localRow = CustomFont(name = "Local Case", fileName = local, dateAdded = added)
        val result = restore(
            fonts = listOf(archivedRow, localRow),
            files = mapOf(archived to incoming, local to incoming),
            incomingName = incomingName,
            incomingBytes = incoming,
            readerFontId = "custom:$archived"
        )
        assertEquals(setOf(archived, local, suffix), result.snapshot.fonts.map { it.fileName }.toSet())
        assertEquals(archived, result.snapshot.fonts.first { it.id == archivedRow.id }.fileName)
        assertEquals(local, result.snapshot.fonts.first { it.id == localRow.id }.fileName)
        assertArrayEquals(incoming, result.snapshot.fontFilesByFileName[archived])
        assertArrayEquals(incoming, result.snapshot.fontFilesByFileName[local])
        assertArrayEquals(incoming, result.fontFilesToWriteByFileName[suffix])
        assertEquals("custom:$archived", result.snapshot.settings.readerFontID)
    }

    @Test
    fun restorePreservesOneRowAndTwoCaseVariantFilesWhenIncomingMatchesOrphan() {
        val incoming = "incoming-font".toByteArray()
        val rowBytes = "original-row-bytes".toByteArray()
        val archived = "ONE-ROW-CASE.TTF"
        val orphan = "one-row-case.ttf"
        val suffix = "ONE-ROW-CASE-restored-1.TTF"
        val row = CustomFont(name = "Existing", fileName = archived, dateAdded = added)
        val result = restore(
            fonts = listOf(row),
            files = mapOf(archived to rowBytes, orphan to incoming),
            incomingName = archived,
            incomingBytes = incoming,
            readerFontId = "custom:$archived"
        )
        assertArrayEquals(rowBytes, result.snapshot.fontFilesByFileName[archived])
        assertArrayEquals(incoming, result.snapshot.fontFilesByFileName[orphan])
        assertArrayEquals(incoming, result.fontFilesToWriteByFileName[suffix])
        assertEquals(archived, result.snapshot.fonts.first { it.id == row.id }.fileName)
        assertEquals(setOf(archived, suffix), result.snapshot.fonts.map { it.fileName }.toSet())
        assertFalse(orphan in result.snapshot.fonts.map { it.fileName })
        assertEquals("custom:$archived", result.snapshot.settings.readerFontID)
    }

    @Test
    fun restoreTreatsTwoLocalFilesAsAmbiguousWhenIncomingMatchesDatabaseFile() {
        assertLocalFileAmbiguityWasPreserved(incomingNameMatchesDatabase = true)
    }

    @Test
    fun zipRestoreTreatsTwoLocalFilesAsAmbiguousWhenIncomingMatchesDatabaseFile() {
        assertLocalFileAmbiguityWasPreserved(incomingNameMatchesDatabase = true)
    }

    @Test
    fun legacyDirectoryRestoreTreatsTwoLocalFilesAsAmbiguousWhenIncomingMatchesDatabaseFile() {
        assertLocalFileAmbiguityWasPreserved(incomingNameMatchesDatabase = true)
    }

    @Test
    fun syncDownTreatsTwoLocalFilesAsAmbiguousWhenIncomingMatchesDatabaseFile() {
        assertLocalFileAmbiguityWasPreserved(incomingNameMatchesDatabase = false)
    }

    private fun assertCaseVariantFixtureWasPreserved() {
        val incoming = "incoming-font".toByteArray()
        val archived = "RESTORE-CASE.TTF"
        val local = "restore-case.ttf"
        val suffix = "RESTORE-CASE-restored-1.TTF"
        val archivedRow = CustomFont(name = "Archived Case", fileName = archived, dateAdded = added)
        val localRow = CustomFont(name = "Local Case", fileName = local, dateAdded = added)
        val result = restore(
            fonts = listOf(archivedRow, localRow),
            files = mapOf(archived to incoming, local to incoming),
            incomingName = archived,
            incomingBytes = incoming,
            readerFontId = "custom:$archived"
        )
        assertEquals(setOf(archived, local, suffix), result.snapshot.fonts.map { it.fileName }.toSet())
        assertEquals(archived, result.snapshot.fonts.first { it.id == archivedRow.id }.fileName)
        assertEquals(local, result.snapshot.fonts.first { it.id == localRow.id }.fileName)
        assertArrayEquals(incoming, result.snapshot.fontFilesByFileName[local])
        assertArrayEquals(incoming, result.snapshot.fontFilesByFileName[archived])
        assertArrayEquals(incoming, result.fontFilesToWriteByFileName[suffix])
        assertEquals("custom:$archived", result.snapshot.settings.readerFontID)
    }

    private fun assertLocalFileAmbiguityWasPreserved(incomingNameMatchesDatabase: Boolean) {
        val incoming = "incoming-font".toByteArray()
        val orphanBytes = "case-variant-orphan".toByteArray()
        val archived = if (incomingNameMatchesDatabase) "LOCAL-AMBIGUITY.TTF" else "SYNC-LOCAL.ttf"
        val orphan = if (incomingNameMatchesDatabase) "local-ambiguity.ttf" else "sync-local.TTF"
        val incomingName = if (incomingNameMatchesDatabase) archived else "sync-local.ttf"
        val suffix = if (incomingNameMatchesDatabase) {
            "LOCAL-AMBIGUITY-restored-1.TTF"
        } else {
            "sync-local-restored-1.ttf"
        }
        val row = CustomFont(name = "Existing", fileName = archived, dateAdded = added)
        val result = restore(
            fonts = listOf(row),
            files = mapOf(archived to incoming, orphan to orphanBytes),
            incomingName = incomingName,
            incomingBytes = incoming,
            readerFontId = "custom:$archived"
        )
        assertArrayEquals(incoming, result.fontFilesToWriteByFileName[suffix])
        assertEquals(archived, result.snapshot.fonts.first { it.id == row.id }.fileName)
        assertArrayEquals(incoming, result.snapshot.fontFilesByFileName[archived])
        assertArrayEquals(orphanBytes, result.snapshot.fontFilesByFileName[orphan])
        assertEquals(setOf(archived, suffix), result.snapshot.fonts.map { it.fileName }.toSet())
        assertEquals("custom:$archived", result.snapshot.settings.readerFontID)
    }

    private fun restore(
        fonts: List<CustomFont>,
        files: Map<String, ByteArray>,
        incomingName: String,
        incomingBytes: ByteArray,
        readerFontId: String
    ): BackupMergeResult {
        val manifest = KudosBackupManifest(
            version = BackupVersion.CURRENT,
            exportedAt = "2026-06-26T12:00:00Z",
            fonts = listOf(BackupFont("Incoming", incomingName, "2026-06-26T12:00:00Z")),
            settings = BackupSettingsPayload(readerFontID = readerFontId)
        )
        return BackupMergeService.merge(
            current = BackupLibrarySnapshot(fonts = fonts, fontFilesByFileName = files),
            backup = KudosBackupPackage(
                manifest = manifest,
                fontFilesByFileName = mapOf(incomingName to incomingBytes)
            )
        )
    }
}
