package io.github.cidy02.kudos.works

import android.content.Context
import android.net.Uri
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

data class PendingDocumentImport(
    val uri: Uri,
    val displayName: String?,
    val bytes: ByteArray,
    val detection: DownloadDateDetection
)

data class SelectedDocumentImport(
    val pending: PendingDocumentImport,
    val downloadedAt: Instant
)

data class DocumentImportPreparation(
    val imports: List<PendingDocumentImport>,
    val failures: List<String>
)

/** Reads picker metadata and EPUB bytes before the confirmation UI commits anything. */
suspend fun prepareDocumentImports(
    context: Context,
    uris: List<Uri>,
    now: Instant = Instant.now()
): DocumentImportPreparation = withContext(Dispatchers.IO) {
    val imports = mutableListOf<PendingDocumentImport>()
    val failures = mutableListOf<String>()
    for (uri in uris) {
        val displayName = ExternalFileImport.displayNameFor(context, uri)
        val label = displayName?.takeIf { it.isNotBlank() } ?: "file"
        val bytesResult = runCatching {
            context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                ?: error("Could not read the selected file.")
        }
        val bytes = bytesResult.getOrNull()
        if (bytes == null) {
            failures += "$label: ${bytesResult.exceptionOrNull()?.message ?: "Could not read the selected file."}"
            continue
        }
        val detection = DownloadDateDetector.detect(
            fileCreated = null,
            fileModified = ExternalFileImport.lastModifiedFor(context, uri),
            epubGeneratedAt = DownloadDateDetector.epubGeneratedAt(bytes),
            now = now
        )
        imports += PendingDocumentImport(uri, displayName, bytes, detection)
    }
    DocumentImportPreparation(imports, failures)
}
