package io.github.cidy02.kudos.reader

/**
 * App-owned reader error type. Readium/engine-specific failures are mapped onto
 * these cases so the UI and tests never depend on Readium types directly.
 */
sealed class ReaderError(val message: String) {
    /** The work is no longer present in the local library. */
    data object WorkNotFound : ReaderError("This work is no longer in your library.")

    /** The work exists but has not been downloaded yet (no EPUB). */
    data object NotDownloaded : ReaderError("This work has not been downloaded yet.")

    /** `hasEpub` is true but the backing EPUB file is gone from app storage. */
    data object FileMissing : ReaderError("The EPUB file for this work is missing.")

    /** Readium could not open the publication (corrupt/unsupported/parse error). */
    data class OpenFailed(val reason: String) : ReaderError(reason)

    /** Restoring the saved position failed; reading can still continue from start. */
    data object ProgressRestoreFailed :
        ReaderError("Could not restore your last position; starting from the beginning.")

    data class Unknown(val reason: String) : ReaderError(reason)
}
