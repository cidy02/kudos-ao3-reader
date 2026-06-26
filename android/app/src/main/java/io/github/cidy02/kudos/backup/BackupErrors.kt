package io.github.cidy02.kudos.backup

sealed class BackupError(message: String, cause: Throwable? = null) : Exception(message, cause) {
    class InvalidPackage(message: String = "This file is not a valid Kudos backup.") :
        BackupError(message)

    class UnsupportedVersion(val version: Int) :
        BackupError("This backup uses unsupported format version $version.")

    object MissingManifest : BackupError("The backup is missing manifest.json.")

    class InvalidJson(cause: Throwable) :
        BackupError("The backup manifest is not valid JSON.", cause)

    class InvalidDate(val field: String, val value: String) :
        BackupError("The backup has an invalid date for $field: $value")

    class InvalidUuid(val field: String, val value: String) :
        BackupError("The backup has an invalid UUID for $field: $value")

    class UnsafePath(val path: String) :
        BackupError("The backup contains an unsafe path: $path")

    class DuplicateEntry(val path: String) :
        BackupError("The backup contains a duplicate entry: $path")

    class EntryTooLarge(val path: String) :
        BackupError("The backup entry is too large: $path")

    class ArchiveTooLarge :
        BackupError("The backup archive is too large.")
}
