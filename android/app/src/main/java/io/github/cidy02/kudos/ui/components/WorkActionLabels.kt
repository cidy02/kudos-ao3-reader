package io.github.cidy02.kudos.ui.components

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.PlaylistAdd
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.DownloadDone
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * Shared label/icon pairs for work lifecycle toggles — parity with iOS
 * `WorkActionLabels`.
 *
 * Icon language:
 * - **Download** (keep EPUB permanently): arrow download family
 * - **Saved for Later** (reading queue): clock / schedule
 * - **Bookmark**: reserved for AO3 bookmarks only
 */
object WorkActionLabels {
    data class Action(val title: String, val icon: ImageVector)

    fun download(isDownloaded: Boolean): Action =
        if (isDownloaded) {
            Action("Remove Download", Icons.Outlined.DownloadDone)
        } else {
            Action("Download", Icons.Outlined.Download)
        }

    /** Compact tile / badge when the work is kept offline. */
    val downloadedIcon: ImageVector get() = Icons.Filled.Download

    fun savedForLater(isQueued: Boolean): Action =
        if (isQueued) {
            Action("Remove from Saved for Later", Icons.Outlined.Schedule)
        } else {
            Action("Save for Later", Icons.Outlined.Schedule)
        }

    /** Filled/emphasized schedule for "this is Saved for Later" glyphs. */
    val savedForLaterIcon: ImageVector get() = Icons.Outlined.Schedule

    val addToQueueIcon: ImageVector get() = Icons.AutoMirrored.Outlined.PlaylistAdd
}
