package io.github.cidy02.kudos.works

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * "Open with Kudos" / "Share to Kudos" handling (iOS `ExternalFileImport`).
 *
 * `MainActivity`'s manifest entry advertises `ACTION_VIEW`/`ACTION_SEND` for the
 * mime types Kudos can import; this is the other half — without it the Activity
 * launches and the incoming file is silently dropped.
 *
 * Process-scoped rather than Activity-scoped on purpose: the Activity is not
 * recreated on configuration change (see `android:configChanges`), and a shared
 * flow lets Compose pick the file up whenever it next composes, including when
 * the app was already running and only `onNewIntent` fired.
 */
object ExternalFileImport {

    private val _pending = MutableStateFlow<List<Uri>>(emptyList())

    /** URIs handed to us by another app, waiting to be imported. */
    val pending: StateFlow<List<Uri>> = _pending.asStateFlow()

    /**
     * Extracts any importable URIs from [intent] and queues them.
     *
     * The URIs come from another app and are untrusted: they are only ever read,
     * and `WorkImporter` still applies its own extension allowlist and ZIP-magic
     * validation before anything is written to the library.
     */
    fun offer(intent: Intent?) {
        val uris = extractUris(intent ?: return)
        if (uris.isNotEmpty()) {
            _pending.value = _pending.value + uris
        }
    }

    /** Takes the queued URIs and clears the queue, so one file imports once. */
    fun consume(): List<Uri> {
        val current = _pending.value
        if (current.isNotEmpty()) _pending.value = emptyList()
        return current
    }

    internal fun extractUris(intent: Intent): List<Uri> = when (intent.action) {
        Intent.ACTION_VIEW -> listOfNotNull(intent.data)
        Intent.ACTION_SEND -> listOfNotNull(intent.streamExtra())
        Intent.ACTION_SEND_MULTIPLE -> intent.streamExtras()
        else -> emptyList()
    }

    @Suppress("DEPRECATION")
    private fun Intent.streamExtra(): Uri? =
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
        }

    @Suppress("DEPRECATION")
    private fun Intent.streamExtras(): List<Uri> =
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java).orEmpty()
        } else {
            getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM).orEmpty()
        }

    /**
     * SAF display name for [uri], falling back to the last path segment.
     * Shared with Settings' own EPUB picker so both paths name files the same way.
     */
    fun displayNameFor(context: Context, uri: Uri): String? {
        val fromResolver = runCatching {
            context.contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) cursor.getString(index) else null
                } else {
                    null
                }
            }
        }.getOrNull()
        return fromResolver?.takeIf { it.isNotBlank() } ?: uri.lastPathSegment
    }
}
