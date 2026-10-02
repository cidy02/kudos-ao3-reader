package io.github.cidy02.kudos.core.model

sealed interface WorkDownloadAction {
    data object Download : WorkDownloadAction
    data object RemoveDownload : WorkDownloadAction
    data class KeptBy(val name: String) : WorkDownloadAction
}

/** Pure Android port of iOS `SavedWork.isDownloaded` and `WorkDownload.action(for:)`. */
object WorkDownloadSemantics {
    fun isDownloaded(
        hasEpub: Boolean,
        isSaved: Boolean,
        isKeptOffline: Boolean,
        hasAo3WorkId: Boolean
    ): Boolean = hasEpub && (isSaved || isKeptOffline || !hasAo3WorkId)

    fun action(
        hasEpub: Boolean,
        isDownloaded: Boolean,
        hasAo3WorkId: Boolean,
        keptBy: String?
    ): WorkDownloadAction? = when {
        !hasAo3WorkId -> null
        !hasEpub -> WorkDownloadAction.Download
        keptBy != null -> WorkDownloadAction.KeptBy(keptBy)
        isDownloaded -> WorkDownloadAction.RemoveDownload
        else -> WorkDownloadAction.Download
    }
}
