package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.network.ao3.AO3URLResolver
import io.github.cidy02.kudos.works.DownloadQueueItem
import io.github.cidy02.kudos.works.WorkTags

/**
 * What a queue's "Keep works offline" does. Port of `KeepOffline.swift`.
 *
 * Turning it on, or adding a work to a queue that keeps, fetches missing AO3
 * EPUBs through the serial download queue. Turning it off fetches nothing and
 * deletes nothing. The file on disk decides, not the `hasEpub` flag.
 */
object KeepOffline {
    /** A queue nobody has asked about (`null`) keeps, as queues always did. */
    fun queueKeeps(value: Boolean?): Boolean = value != false

    /**
     * AO3 works with no EPUB file on disk. Soft-deleted works and local imports
     * (no `/works/<id>`) are left out. [fileOnDisk] is the file, not the flag.
     */
    fun downloadItems(
        works: List<SavedWork>,
        fileOnDisk: (SavedWork) -> Boolean
    ): List<DownloadQueueItem> {
        return works.mapNotNull { work ->
            if (work.isDeleted) return@mapNotNull null
            val id = WorkTags.ao3WorkIdFromUrl(work.sourceUrl) ?: return@mapNotNull null
            if (fileOnDisk(work)) return@mapNotNull null
            DownloadQueueItem(
                ao3WorkId = id,
                title = work.title.ifBlank { "Work $id" },
                sourceUrl = work.sourceUrl.ifBlank { AO3URLResolver.canonicalWorkUrl(id) },
                // The queue skips a row whose flag already says downloaded. A missing
                // file has to force past that, or the flag would hide the gap.
                force = work.hasEpub,
                isComplete = work.isComplete,
                seriesUrl = work.seriesUrl
            )
        }
    }
}
