package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.files.FileWriteResult
import io.github.cidy02.kudos.files.ImportedFileFormat
import io.github.cidy02.kudos.files.TextDecoding
import io.github.cidy02.kudos.works.converters.CalibreMetadata
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.work.AO3EpubDownloader
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadata
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadataRepository
import java.time.Instant
import java.util.Locale

sealed interface WorkImportResult {
    data class Success(val work: SavedWork) : WorkImportResult
    data class Failure(val work: SavedWork?, val error: AO3Error) : WorkImportResult
}

class WorkImporter(
    val workRepository: WorkRepository,
    private val metadataRepository: AO3WorkMetadataRepository,
    private val downloader: AO3EpubDownloader,
    private val fileStore: WorkFileStore,
    private val merger: WorkMetadataMerger = WorkMetadataMerger()
) {
    /**
     * [markSaved] defaults true for the ordinary explicit-save/download callers.
     * Queue-add (see `WorkDetailScreen.ensureLocalThen`) passes `markSaved = false,
     * isQueuedForLater = true` so a not-yet-saved work stays queue-only
     * (`SavedWork.isQueueOnlyWork`) instead of becoming a full Library item — an
     * already-saved match still keeps `isSaved = true` either way, since the merger
     * ORs onto the existing value rather than overwriting it.
     */
    suspend fun saveMetadataOnly(
        summary: AO3WorkSummary,
        markSaved: Boolean = true,
        isQueuedForLater: Boolean = false
    ): WorkImportResult {
        val existing = findExisting(summary)
        val metadata = fetchCanonical(summary.id)
        var work = merger.merge(
            summary = summary,
            canonical = metadata,
            existing = existing,
            markSaved = markSaved,
            hasEpub = existing?.hasEpub ?: false,
            isQueuedForLater = isQueuedForLater
        )
        
        // Ensure series data is properly preserved from summary when queuing
        if (isQueuedForLater && !summary.seriesTitle.isNullOrBlank()) {
            work = work.copy(
                seriesTitle = summary.seriesTitle,
                seriesPosition = summary.seriesPosition ?: work.seriesPosition,
                seriesUrl = summary.seriesUrl ?: work.seriesUrl
            )
        }
        
        val saved = workRepository.upsert(work)
        return WorkImportResult.Success(reviveIfNeeded(existing, saved))
    }

    suspend fun download(summary: AO3WorkSummary): WorkImportResult {
        val existing = findExisting(summary)
        val metadata = fetchCanonical(summary.id)
        val merged = workRepository.upsert(
            merger.merge(
                summary = summary,
                canonical = metadata,
                existing = existing,
                markSaved = true,
                hasEpub = existing?.hasEpub ?: false
            )
        )
        val base = reviveIfNeeded(existing, merged)

        return when (val download = downloader.download(summary.id)) {
            is AO3Result.Failure -> {
                if (download.error is AO3Error.NotFound) {
                    val updated = workRepository.upsert(base.copy(ao3Unavailable = true, lastAvailabilityCheck = Instant.now(), lastModifiedAt = Instant.now()))
                    WorkImportResult.Failure(updated, download.error)
                } else {
                    WorkImportResult.Failure(base, download.error)
                }
            }
            is AO3Result.Success -> persistDownloadedEpub(base, download.value)
        }
    }

    /**
     * WorkMetadataMerger.merge already clears a revived match's soft-delete fields
     * (it's a pure function with no repository access), but that leaves the match's
     * sync tombstone in place — a later backup merge would treat the tombstone as
     * authoritative and silently re-hide the just-revived work on another device.
     * Route confirmed revivals through the repository's own restore path so the
     * tombstone is retracted and lastModifiedAt reflects the revival, same as the
     * DownloadQueue resolved-match path already does.
     */
    private suspend fun reviveIfNeeded(existing: SavedWork?, saved: SavedWork): SavedWork {
        if (existing?.isDeleted != true) return saved
        return workRepository.restoreFromRecentlyDeleted(saved.id) ?: saved
    }

    suspend fun downloadExisting(work: SavedWork): WorkImportResult {
        val workId = WorkTags.ao3WorkIdFromUrl(work.sourceUrl)
            ?: return WorkImportResult.Failure(work, AO3Error.Validation("No AO3 work id found for this work."))

        return when (val download = downloader.download(workId)) {
            is AO3Result.Failure -> {
                if (download.error is AO3Error.NotFound) {
                    val updated = workRepository.upsert(work.copy(ao3Unavailable = true, lastAvailabilityCheck = Instant.now(), lastModifiedAt = Instant.now()))
                    WorkImportResult.Failure(updated, download.error)
                } else {
                    WorkImportResult.Failure(work, download.error)
                }
            }
            is AO3Result.Success -> persistDownloadedEpub(work, download.value)
        }
    }

    /**
     * Import a user-picked local `.epub` (SAF), not an AO3 download.
     *
     * Title comes from the file display name (minus extension) — no OPF metadata
     * parse. [SavedWork.sourceUrl] is left blank so AO3-only affordances no-op.
     */
    suspend fun importLocalEpub(
        displayName: String?,
        bytes: ByteArray
    ): WorkImportResult {
        if (bytes.isEmpty()) {
            return WorkImportResult.Failure(
                null,
                AO3Error.Validation("The selected file was empty.")
            )
        }

        val title = titleFromDisplayName(displayName)

        // Sniff the real format rather than trusting the extension: files that
        // travel through Discord/Reddit arrive renamed (`fic.epub.zip`).
        val format = ImportedFileFormat.sniff(bytes, displayName)
        val finalBytes = when (format) {
            ImportedFileFormat.EPUB -> bytes
            ImportedFileFormat.PDF ->
                io.github.cidy02.kudos.works.converters.PDFWorkConverter().convert(title, bytes)
            ImportedFileFormat.HTML ->
                io.github.cidy02.kudos.works.converters.HTMLWorkConverter().convert(title, bytes)
            ImportedFileFormat.TEXT ->
                io.github.cidy02.kudos.works.converters.PlainTextWorkConverter().convert(title, bytes)
            ImportedFileFormat.ZIP ->
                io.github.cidy02.kudos.works.converters.ArchiveWorkConverter.convert(title, bytes)
            ImportedFileFormat.UNKNOWN -> null
        } ?: return WorkImportResult.Failure(null, AO3Error.Validation(unsupportedMessage(format)))

        // Every path above either passes an EPUB through or builds one, so the
        // result must be a ZIP by the time it reaches the file store.
        if (!looksLikeZip(finalBytes)) {
            return WorkImportResult.Failure(
                null,
                AO3Error.Validation("Not a valid EPUB (file is not a ZIP archive).")
            )
        }

        // calibre / FanFicFare exports carry a label block; recovering it means a
        // converted work keeps its real title, tags and — most usefully — the
        // source URL, instead of being stranded with no origin.
        val exported = TextDecoding.decode(bytes)
            ?.lineSequence()
            ?.take(40)
            ?.toList()
            ?.let(CalibreMetadata::parse)

        val work = SavedWork(
            title = exported?.title?.takeIf { it.isNotBlank() } ?: title,
            author = exported?.author.orEmpty(),
            sourceUrl = exported?.sourceUrl.orEmpty(),
            summary = exported?.summary.orEmpty(),
            rating = exported?.rating.orEmpty(),
            workFandoms = exported?.fandoms.orEmpty(),
            workFreeforms = exported?.freeforms.orEmpty(),
            hasEpub = true,
            isSaved = true,
            lastModifiedAt = Instant.now()
        )

        // Converted imports keep their source so "Rebuild from Original" can re-run
        // a newer converter later. A plain EPUB import has nothing to rebuild from.
        if (format != ImportedFileFormat.EPUB) {
            fileStore.writeOriginal(work.id, format.name.lowercase(Locale.ROOT), bytes)
        }

        return when (val write = fileStore.writeWorkEpub(work.id, finalBytes)) {
            is FileWriteResult.Failure -> WorkImportResult.Failure(
                work,
                AO3Error.Validation(write.message)
            )
            is FileWriteResult.Success -> {
                val saved = workRepository.upsert(work)
                WorkImportResult.Success(saved)
            }
        }
    }

    /**
     * True when this work was converted from a non-EPUB source we still hold, so
     * the UI can offer "Rebuild from Original" (iOS `WorkReconversion.candidate`).
     */
    suspend fun canRebuildFromOriginal(work: SavedWork): Boolean =
        fileStore.originalExists(work.id)

    /**
     * Re-runs the current converters over the archived source and replaces the
     * EPUB (iOS `WorkReconversion.rebuildFromOriginal`).
     *
     * Reading progress and every other local field are untouched — only the file
     * is replaced — so a rebuild never costs the reader their place.
     */
    suspend fun rebuildFromOriginal(work: SavedWork): WorkImportResult {
        val (extension, bytes) = fileStore.readOriginal(work.id)
            ?: return WorkImportResult.Failure(
                work,
                AO3Error.Validation("No archived original for this work.")
            )
        val format = ImportedFileFormat.sniff(bytes, "original.$extension")
        val rebuilt = when (format) {
            ImportedFileFormat.PDF ->
                io.github.cidy02.kudos.works.converters.PDFWorkConverter().convert(work.title, bytes)
            ImportedFileFormat.HTML ->
                io.github.cidy02.kudos.works.converters.HTMLWorkConverter().convert(work.title, bytes)
            ImportedFileFormat.TEXT ->
                io.github.cidy02.kudos.works.converters.PlainTextWorkConverter().convert(work.title, bytes)
            ImportedFileFormat.ZIP ->
                io.github.cidy02.kudos.works.converters.ArchiveWorkConverter.convert(work.title, bytes)
            ImportedFileFormat.EPUB -> bytes
            ImportedFileFormat.UNKNOWN -> null
        } ?: return WorkImportResult.Failure(work, AO3Error.Validation(unsupportedMessage(format)))

        return when (val write = fileStore.writeWorkEpub(work.id, rebuilt)) {
            is FileWriteResult.Failure -> WorkImportResult.Failure(work, AO3Error.Validation(write.message))
            is FileWriteResult.Success -> WorkImportResult.Success(
                workRepository.upsert(work.copy(hasEpub = true, lastModifiedAt = Instant.now()))
            )
        }
    }

    private suspend fun persistDownloadedEpub(work: SavedWork, bytes: ByteArray): WorkImportResult {
        return when (val write = fileStore.writeWorkEpub(work.id, bytes)) {
            is FileWriteResult.Failure -> WorkImportResult.Failure(
                work,
                AO3Error.Validation(write.message)
            )
            is FileWriteResult.Success -> {
                // Preserve local user state (isFinished, favorite, progress); only the
                // file-backed flags change here. A re-download of a finished work must
                // not silently clear the user's Finished marker.
                //
                // isSaved is deliberately NOT forced true here (it used to be) - a
                // queue-only work (T-89) whose EPUB preserve-download completes here
                // must not have that silently flip it into a full Library item. Every
                // caller that actually wants isSaved=true already produced a `work`
                // with isSaved=true before reaching this point (download()'s merge step
                // runs markSaved=true; downloadExisting()'s callers redownload an
                // already-saved work), so omitting it from the copy and letting it keep
                // `work.isSaved` as-is is a no-op for them and the fix for queue-only.
                //
                // `downloadExisting` (the DownloadQueue resolved-match path) hands this
                // `work` straight through without going via WorkMetadataMerger, so a
                // soft-deleted match reaching here can still have isDeleted=true (the
                // DownloadQueue caller already revives via restoreFromRecentlyDeleted
                // before calling in, but that isn't guaranteed for every caller) —
                // restore it through the repository so the tombstone is retracted too,
                // not just the local fields, before writing the download-specific ones.
                if (work.isDeleted) {
                    workRepository.restoreFromRecentlyDeleted(work.id)
                }
                val updated = workRepository.upsert(
                    work.copy(
                        hasEpub = true,
                        isDeleted = false,
                        deletedAt = null,
                        permanentDeletionScheduledAt = null,
                        lastModifiedAt = Instant.now()
                    )
                )
                WorkImportResult.Success(updated)
            }
        }
    }

    private suspend fun findExisting(summary: AO3WorkSummary): SavedWork? {
        return WorkIdentityIndex.findExisting(
            candidateSourceUrl = summary.workUrl,
            byId = { workRepository.getWork(it) },
            bySourceUrl = { workRepository.findBySourceUrl(it) }
        )
    }

    private suspend fun fetchCanonical(workId: Long): AO3WorkMetadata? {
        return when (val metadata = metadataRepository.fetch(workId)) {
            is AO3Result.Failure -> null
            is AO3Result.Success -> metadata.value.takeUnless { it.isEmpty }
        }
    }

    companion object {
        /** ZIP local-file-header magic — a real EPUB is a ZIP container. */
        private val ZIP_MAGIC = byteArrayOf(0x50, 0x4B, 0x03, 0x04)

        /** Format-specific guidance instead of one generic rejection string. */
        internal fun unsupportedMessage(format: ImportedFileFormat): String = when (format) {
            ImportedFileFormat.PDF ->
                "This PDF's text can't be extracted — it's scanned or compressed. " +
                    "Try exporting it as EPUB, HTML, or plain text first."
            ImportedFileFormat.ZIP ->
                "Couldn't find anything readable in that archive. It needs an EPUB, " +
                    "or HTML/text files to build one from."
            else ->
                "Unsupported file type. Kudos can import EPUB, PDF, HTML, and TXT files."
        }

        fun isSupportedFileName(fileName: String?): Boolean {
            if (fileName.isNullOrBlank()) return false
            val last = fileName.substringAfterLast('/').substringAfterLast('\\')
            val ext = last.substringAfterLast('.', missingDelimiterValue = "")
                .lowercase(Locale.ROOT)
            return ext in listOf("epub", "pdf", "html", "htm", "txt")
        }

        fun looksLikeZip(bytes: ByteArray): Boolean {
            if (bytes.size < ZIP_MAGIC.size) return false
            return bytes[0] == ZIP_MAGIC[0] &&
                bytes[1] == ZIP_MAGIC[1] &&
                bytes[2] == ZIP_MAGIC[2] &&
                bytes[3] == ZIP_MAGIC[3]
        }

        /** Filename-minus-extension title, same style as Settings font import. */
        fun titleFromDisplayName(displayName: String?): String {
            val nameWithoutExt = displayName
                ?.substringAfterLast('/')
                ?.substringAfterLast('\\')
                ?.substringBeforeLast('.')
                ?.trim()
                .orEmpty()
            return nameWithoutExt.ifBlank { "Imported EPUB" }
        }
    }
}
