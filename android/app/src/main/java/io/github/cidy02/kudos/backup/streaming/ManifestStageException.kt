package io.github.cidy02.kudos.backup.streaming

/**
 * Distinct outcomes of validating and staging a manifest (A-567 P2). A caller maps these onto its own
 * route's errors; nothing here is wired to a production path yet.
 */
sealed class ManifestStageException(message: String, cause: Throwable? = null) : Exception(message, cause) {
    /**
     * The document is not a manifest this reader accepts. [syntactic] is true when the bytes are not
     * well-formed JSON under the shared contract (the sync recovery predicate's question), false when
     * the JSON is well formed but a typed decode of a record or of the root fields failed.
     */
    class Invalid(val reason: String, val syntactic: Boolean) : ManifestStageException(reason)

    class UnsupportedVersion(val version: Int) : ManifestStageException("Unsupported manifest version $version.")

    /** Reading the input or the staging database failed (not a full disk). */
    class Io(cause: Throwable) : ManifestStageException(cause.message ?: "I/O failure while staging the manifest.", cause)

    class Cancelled : ManifestStageException("Staging the manifest was cancelled.")

    /** Out of disk, heap, or a bounded buffer (key, token, per-object key count). */
    class ResourceExhausted(val reason: String, cause: Throwable? = null) : ManifestStageException(reason, cause)
}
