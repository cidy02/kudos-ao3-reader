package io.github.cidy02.kudos.backup

/**
 * Cross-platform `.kudosbackup` manifest versions.
 *
 * Apple (`hig-review`) currently writes **v8** (annotations). Android must accept
 * every version Apple still restores: 1…8. New fields are always optional with
 * defaults so older archives keep decoding.
 *
 * | Version | Notable content |
 * |---|---|
 * | 1 | Apple directory package (legacy read) |
 * | 2 | ZIP package baseline |
 * | 3–6 | Collections, queues, preservation, sync fields |
 * | 7 | Recently Deleted / permanentDeletionScheduledAt |
 * | 8 | In-book annotations (bookmarks/highlights/notes) |
 */
object BackupVersion {
    const val APPLE_V1 = 1
    const val ZIP_V2 = 2

    /** Matches Apple `KudosBackupManifest.currentVersion`. */
    const val CURRENT = 8

    val supported: Set<Int> = (APPLE_V1..CURRENT).toSet()

    fun isSupported(version: Int): Boolean = version in supported

    fun isZipCompatible(version: Int): Boolean {
        // v1 may appear as a directory package *or* (rarely) as a ZIP; accept
        // any supported version inside a ZIP so Apple v2–v8 imports work.
        return isSupported(version)
    }
}

object BackupLimits {
    const val MAX_ARCHIVE_BYTES: Long = 1024L * 1024L * 1024L
    const val MAX_ENTRY_BYTES: Long = 128L * 1024L * 1024L
    const val MAX_MANIFEST_BYTES: Long = 8L * 1024L * 1024L
    const val MAX_FONT_ENTRY_BYTES: Long = 4L * 1024L * 1024L
    const val MAX_TOTAL_FONT_BYTES: Long = 32L * 1024L * 1024L
}
