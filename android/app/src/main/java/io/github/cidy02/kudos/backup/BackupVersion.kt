package io.github.cidy02.kudos.backup

object BackupVersion {
    const val APPLE_V1 = 1
    const val ZIP_V2 = 2

    val supported: Set<Int> = setOf(APPLE_V1, ZIP_V2)
}

object BackupLimits {
    const val MAX_ARCHIVE_BYTES: Long = 1024L * 1024L * 1024L
    const val MAX_ENTRY_BYTES: Long = 128L * 1024L * 1024L
    const val MAX_MANIFEST_BYTES: Long = 8L * 1024L * 1024L
}
