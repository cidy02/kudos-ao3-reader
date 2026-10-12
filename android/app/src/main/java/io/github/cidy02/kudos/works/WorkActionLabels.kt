package io.github.cidy02.kudos.works

/**
 * iOS `WorkActionLabels.finished`: the one wording of the finished toggle, wherever it is
 * offered. It names what the tap will do. Android had five ("Finished", "Mark unfinished",
 * "Mark Unfinished", "Mark Finished", and this one).
 */
fun finishedActionLabel(isFinished: Boolean): String =
    if (isFinished) "Mark as Still Reading" else "Mark as Finished"
