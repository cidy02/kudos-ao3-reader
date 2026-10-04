package io.github.cidy02.kudos.backup

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.works.EpubImportMetadata
import io.github.cidy02.kudos.works.converters.EpubBuilder
import java.io.ByteArrayOutputStream
import java.time.Instant
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * When a restore or a folder sync may write an archive's EPUB over a local one: iOS
 * `KudosBackupService.mayReplaceEPUB` and the validation in `ReadingQueueService.replaceEPUB`
 * (iOS tests `syncDownRejectsInvalidEPUBWithoutOverwritingLocalCopy`,
 * `mergeRefillsAnEPUBThatWentMissingLocally`, `mergeLeavesAnExistingLocalEPUBAlone`).
 */
class IncomingEpubGateTest {
    private val incoming = EpubBuilder.buildEpub("Incoming", "<p>Text.</p>")

    @Test
    fun theRuleIsIos() {
        // A new record has nothing to lose; a work with no file can always be filled in.
        assertTrue(mayReplaceEpub(hasLocalFile = true, isPreserved = true, isNewRecord = true, incomingIsNewer = false))
        assertTrue(mayReplaceEpub(hasLocalFile = false, isPreserved = true, isNewRecord = false, incomingIsNewer = false))
        // A preserved work that still has its file is never replaced, however new the archive.
        assertFalse(mayReplaceEpub(hasLocalFile = true, isPreserved = true, isNewRecord = false, incomingIsNewer = true))
        // An ordinary work is replaced only by a newer archive.
        assertTrue(mayReplaceEpub(hasLocalFile = true, isPreserved = false, isNewRecord = false, incomingIsNewer = true))
        assertFalse(mayReplaceEpub(hasLocalFile = true, isPreserved = false, isNewRecord = false, incomingIsNewer = false))
    }

    @Test
    fun aReadablePackageIsAWholeZipWithASpine() {
        assertTrue(EpubImportMetadata.isReadablePackage(incoming))
        assertFalse(EpubImportMetadata.isReadablePackage("not-an-epub".toByteArray()))
        assertFalse(EpubImportMetadata.isReadablePackage(ByteArray(0)))
        // Cut off part-way, as a copy still being uploaded is: the ZIP has no end record.
        assertFalse(EpubImportMetadata.isReadablePackage(incoming.copyOf(incoming.size - 40)))
    }

    @Test
    fun thePackageIsTheOneTheContainerNames() {
        val opf = """<package><manifest><item id="c" href="c.xhtml"/></manifest>""" +
            """<spine><itemref idref="c"/></spine></package>"""
        fun container(path: String) =
            """<container><rootfiles><rootfile full-path="$path"/></rootfiles></container>"""
        // iOS accepts a package document under whatever name the container gives.
        assertTrue(
            EpubImportMetadata.isReadablePackage(
                zip("META-INF/container.xml" to container("OPS/package.xml"), "OPS/package.xml" to opf)
            )
        )
        // A ZIP that holds a stray package document and no container is not an EPUB.
        assertFalse(EpubImportMetadata.isReadablePackage(zip("stray.opf" to opf)))
        // Nor is one whose container names a package that is not there.
        assertFalse(
            EpubImportMetadata.isReadablePackage(
                zip("META-INF/container.xml" to container("gone.opf"), "stray.opf" to opf)
            )
        )
    }

    private fun zip(vararg entries: Pair<String, String>): ByteArray = ByteArrayOutputStream().also { bytes ->
        ZipOutputStream(bytes).use { zip ->
            entries.forEach { (name, text) ->
                zip.putNextEntry(ZipEntry(name))
                zip.write(text.toByteArray())
                zip.closeEntry()
            }
        }
    }.toByteArray()

    @Test
    fun aNewerArchiveReplacesAnOrdinaryWorksEpub() {
        val result = restore(local(), hasFile = true, epub = incoming)

        assertArrayEquals(incoming, result.epubFilesToWriteByWorkId[WORK])
    }

    @Test
    fun anEqualClockStillAcceptsTheLaterAssetBatch() {
        val first = restore(local(), hasFile = true, epub = ByteArray(0))
        val second = BackupMergeService.merge(first.snapshot, archive(incoming))
        assertArrayEquals(incoming, second.epubFilesToWriteByWorkId[WORK])
    }

    @Test
    fun aPreservedWorkThatStillHasItsFileIsNeverReplaced() {
        val result = restore(local(status = "preserved"), hasFile = true, epub = incoming)

        assertTrue(result.epubFilesToWriteByWorkId.isEmpty())
        assertTrue(result.snapshot.works.single().hasEpub)
    }

    @Test
    fun aPreservedWorkWhoseFileIsGoneIsFilledIn() {
        val result = restore(local(status = "preserved"), hasFile = false, epub = incoming)

        assertArrayEquals(incoming, result.epubFilesToWriteByWorkId[WORK])
    }

    @Test
    fun bytesThatAreNotAnEpubNeverReplaceALocalFile() {
        val result = restore(local(), hasFile = true, epub = "not-an-epub".toByteArray())

        assertTrue(result.epubFilesToWriteByWorkId.isEmpty())
        assertTrue("the valid local copy is still claimed", result.snapshot.works.single().hasEpub)
    }

    @Test
    fun aNewWorkWithAnUnreadableEpubArrivesWithoutAFile() {
        val result = BackupMergeService.merge(
            current = BackupLibrarySnapshot(),
            backup = archive("not-an-epub".toByteArray())
        )

        assertTrue(result.epubFilesToWriteByWorkId.isEmpty())
        assertFalse(result.snapshot.works.single().hasEpub)
    }

    @Test
    fun anOlderArchiveStillFillsAFileThatWentMissing() {
        // The flag says there is an EPUB and the disk says there is not: nothing to protect.
        val result = restore(local(modified = AFTER_ARCHIVE), hasFile = false, epub = incoming)

        assertArrayEquals(incoming, result.epubFilesToWriteByWorkId[WORK])
    }

    @Test
    fun fileMergeFillsAGapButLeavesAPresentFileAlone() {
        val present = restore(local(), hasFile = true, epub = incoming, mode = BackupImportMode.MERGE)
        val missing = restore(local(), hasFile = false, epub = incoming, mode = BackupImportMode.MERGE)

        assertTrue(present.epubFilesToWriteByWorkId.isEmpty())
        assertArrayEquals(incoming, missing.epubFilesToWriteByWorkId[WORK])
    }

    private fun restore(
        local: SavedWork,
        hasFile: Boolean,
        epub: ByteArray,
        mode: BackupImportMode = BackupImportMode.RECONCILE
    ) = BackupMergeService.merge(
        current = BackupLibrarySnapshot(
            works = listOf(local),
            epubWorkIds = if (hasFile) setOf(WORK) else emptySet()
        ),
        backup = archive(epub),
        mode = mode
    )

    private fun local(status: String? = null, modified: Instant = BEFORE_ARCHIVE) = SavedWork(
        id = WORK,
        title = "Local",
        author = "Author",
        dateAdded = BEFORE_ARCHIVE,
        lastModifiedAt = modified,
        isSaved = true,
        hasEpub = true,
        epubPreservationStatusRaw = status
    )

    private fun archive(epub: ByteArray) = KudosBackupPackage(
        manifest = KudosBackupManifest(
            version = BackupVersion.CURRENT,
            exportedAt = "2026-03-01T00:00:00Z",
            exportedBy = BackupExportedBy(
                platform = "ios",
                appVersion = "test",
                schemaVersion = BackupVersion.CURRENT
            ),
            works = listOf(
                BackupWork(
                    id = WORK,
                    title = "Archived",
                    author = "Author",
                    summary = "",
                    sourceURL = "",
                    dateAdded = "2026-01-01T00:00:00Z",
                    isFavorite = false,
                    isSaved = true,
                    isFinished = false,
                    hasEPUB = true,
                    isComplete = true,
                    lastSpineIndex = 0,
                    lastScrollFraction = 0.0,
                    lastModifiedAt = "2026-02-01T00:00:00Z"
                )
            ),
            settings = BackupSettingsPayload()
        ),
        epubFilesByWorkId = mapOf(WORK to epub),
        fontFilesByFileName = emptyMap()
    )

    private companion object {
        const val WORK = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        val BEFORE_ARCHIVE: Instant = Instant.parse("2026-01-01T00:00:00Z")
        val AFTER_ARCHIVE: Instant = Instant.parse("2026-02-15T00:00:00Z")
    }
}
