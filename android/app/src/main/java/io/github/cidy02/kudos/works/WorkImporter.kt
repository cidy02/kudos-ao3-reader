package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.files.FileWriteResult
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.work.AO3EpubDownloader
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadata
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadataRepository

sealed interface WorkImportResult {
    data class Success(val work: SavedWork) : WorkImportResult
    data class Failure(val work: SavedWork?, val error: AO3Error) : WorkImportResult
}

class WorkImporter(
    private val workRepository: WorkRepository,
    private val metadataRepository: AO3WorkMetadataRepository,
    private val downloader: AO3EpubDownloader,
    private val fileStore: WorkFileStore,
    private val merger: WorkMetadataMerger = WorkMetadataMerger()
) {
    suspend fun saveMetadataOnly(summary: AO3WorkSummary): WorkImportResult {
        val existing = workRepository.findBySourceUrl(summary.workUrl)
        val metadata = fetchCanonical(summary.id)
        val work = merger.merge(
            summary = summary,
            canonical = metadata,
            existing = existing,
            markSaved = true,
            hasEpub = existing?.hasEpub ?: false
        )
        return WorkImportResult.Success(workRepository.upsert(work))
    }

    suspend fun download(summary: AO3WorkSummary): WorkImportResult {
        val existing = workRepository.findBySourceUrl(summary.workUrl)
        val metadata = fetchCanonical(summary.id)
        val base = workRepository.upsert(
            merger.merge(
                summary = summary,
                canonical = metadata,
                existing = existing,
                markSaved = true,
                hasEpub = existing?.hasEpub ?: false
            )
        )

        return when (val download = downloader.download(summary.id)) {
            is AO3Result.Failure -> WorkImportResult.Failure(base, download.error)
            is AO3Result.Success -> persistDownloadedEpub(base, download.value)
        }
    }

    suspend fun downloadExisting(work: SavedWork): WorkImportResult {
        val workId = WorkTags.ao3WorkIdFromUrl(work.sourceUrl)
            ?: return WorkImportResult.Failure(work, AO3Error.Validation("No AO3 work id found for this work."))

        return when (val download = downloader.download(workId)) {
            is AO3Result.Failure -> WorkImportResult.Failure(work, download.error)
            is AO3Result.Success -> persistDownloadedEpub(work, download.value)
        }
    }

    private suspend fun persistDownloadedEpub(work: SavedWork, bytes: ByteArray): WorkImportResult {
        return when (val write = fileStore.writeWorkEpub(work.id, bytes)) {
            is FileWriteResult.Failure -> WorkImportResult.Failure(
                work,
                AO3Error.Validation(write.message)
            )
            is FileWriteResult.Success -> {
                val updated = workRepository.upsert(work.copy(hasEpub = true, isSaved = true, isFinished = false))
                WorkImportResult.Success(updated)
            }
        }
    }

    private suspend fun fetchCanonical(workId: Long): AO3WorkMetadata? {
        return when (val metadata = metadataRepository.fetch(workId)) {
            is AO3Result.Failure -> null
            is AO3Result.Success -> metadata.value.takeUnless { it.isEmpty }
        }
    }
}
