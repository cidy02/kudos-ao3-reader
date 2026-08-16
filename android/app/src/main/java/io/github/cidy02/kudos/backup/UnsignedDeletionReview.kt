package io.github.cidy02.kudos.backup

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * D8 notify-on-use + anomaly hold. Populated by [BackupRepository] after a
 * successful merge; [io.github.cidy02.kudos.app.KudosApp] presents the
 * review dialog / digest.
 */
object UnsignedDeletionReview {
    data class Hold(
        val titles: List<String>,
        val workIds: List<String>,
        val sourceLabel: String
    ) {
        val count: Int get() = titles.size
    }

    private val pendingHoldState = MutableStateFlow<Hold?>(null)
    private val pendingDigestState = MutableStateFlow<String?>(null)

    val pendingHold: StateFlow<Hold?> = pendingHoldState.asStateFlow()
    val pendingDigest: StateFlow<String?> = pendingDigestState.asStateFlow()

    fun record(summary: BackupRestoreSummary, source: String) {
        if (summary.unsignedHidesHeld >= BackupMergeService.UNSIGNED_HIDE_HOLD_FLOOR) {
            pendingHoldState.value = Hold(
                titles = summary.unsignedHideTitles,
                workIds = summary.heldUnsignedHideWorkIDs,
                sourceLabel = source
            )
            pendingDigestState.value = null
        } else if (summary.unsignedHidesApplied > 0) {
            val applied = summary.unsignedHidesApplied
            pendingDigestState.value =
                "$applied work${if (applied == 1) "" else "s"} moved to Recently Deleted by $source."
            pendingHoldState.value = null
        }
    }

    fun dismissHold() {
        pendingHoldState.value = null
    }

    fun dismissDigest() {
        pendingDigestState.value = null
    }

    fun resetForTests() {
        pendingHoldState.value = null
        pendingDigestState.value = null
    }
}
