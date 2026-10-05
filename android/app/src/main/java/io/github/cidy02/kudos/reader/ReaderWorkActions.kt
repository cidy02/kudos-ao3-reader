package io.github.cidy02.kudos.reader

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.files.WorkFileStore
import java.nio.file.Files
import java.nio.file.LinkOption
import java.util.Locale

internal data class WorkFileAddress(val uri: Uri, val mimeType: String)

/**
 * The name another app is told to use for the file. A title is the author's text, so it gets
 * no path separators or control characters (a careless receiver would write where they point),
 * no leading dot, and a length every file system takes (80 characters is under 255 bytes even
 * at three bytes each).
 */
internal fun shareFileName(title: String, extension: String): String {
    val name = title.replace(Regex("[/\\\\\\p{Cntrl}]"), " ").replace(Regex("\\s+"), " ")
        .trim().trimStart('.', ' ').take(80).trimEnd { it.isHighSurrogate() }.trim()
    return "${name.ifEmpty { "Work" }}.$extension"
}

/** A work-scoped, read-only handoff of the file in its existing private home. */
internal class ReaderWorkActions(private val context: Context) {
    private val store = WorkFileStore(context.filesDir.toPath())

    // Deliberately accepts a work, never a caller-supplied path. Canonical checks also
    // reject links to another work, sidecars, and links escaping either provider root.
    fun fileAddress(work: SavedWork, original: Boolean = false): WorkFileAddress? = runCatching {
        if (work.isDeleted || (!original && !work.hasEpub)) return@runCatching null
        val path = if (original) {
            store.originalFile(work.id) ?: return@runCatching null
        } else store.workEpubPath(work.id)
        if (!Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)) return@runCatching null
        val root = context.filesDir.canonicalFile.toPath().resolve(if (original) "originals" else "works")
        val file = path.toFile().canonicalFile
        // Direct children only. Reject a symlinked directory too, even when its
        // destination is inside the other allowed root.
        if (root.toFile().canonicalFile.toPath() != root || file.toPath() != root.resolve(path.fileName)) {
            return@runCatching null
        }
        val extension = file.extension
        val displayName = shareFileName(work.title, extension)
        val mime = when (extension.lowercase(Locale.ROOT)) {
            "epub" -> "application/epub+zip"
            else -> MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension.lowercase(Locale.ROOT))
                ?: "application/octet-stream"
        }
        WorkFileAddress(
            FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file, displayName),
            mime
        )
    }.getOrNull()

    /** iOS shareURL: AO3 identity, HTTP source, then a readable EPUB. */
    fun shareIntent(work: SavedWork): Intent? {
        if (work.isDeleted) return null
        val link = readerShareUrl(work)
        if (link != null) {
            return Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_SUBJECT, work.title)
                putExtra(Intent.EXTRA_TEXT, "${work.title}\n$link")
            }
        }
        val address = fileAddress(work) ?: return null
        return Intent(Intent.ACTION_SEND).apply {
            type = address.mimeType
            putExtra(Intent.EXTRA_SUBJECT, work.title)
            putExtra(Intent.EXTRA_STREAM, address.uri)
            clipData = ClipData.newRawUri(work.title, address.uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
    }

    fun originalIntent(work: SavedWork): Intent? {
        val address = fileAddress(work, original = true) ?: return null
        return Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(address.uri, address.mimeType)
            clipData = ClipData.newRawUri(work.title, address.uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
    }

    // The system grants only the selected recipient this one URI. No package-wide
    // grant, persistable grant, write grant, or file copy is made here.
    fun share(work: SavedWork, launch: (Intent) -> Unit = { context.startActivity(it) }): String? {
        val intent = shareIntent(work) ?: return "This work has no link or readable file to share."
        return try {
            launch(Intent.createChooser(intent, "Share Work"))
            null
        } catch (_: ActivityNotFoundException) {
            "No app on this device can share this work."
        }
    }

    fun openOriginal(work: SavedWork, launch: (Intent) -> Unit = { context.startActivity(it) }): String? {
        val intent = originalIntent(work) ?: return "The original file is no longer stored on this device."
        return try {
            launch(intent)
            null
        } catch (_: ActivityNotFoundException) {
            "No app on this device can open this file."
        }
    }
}
