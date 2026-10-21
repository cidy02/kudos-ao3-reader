package io.github.cidy02.kudos.works

import android.content.Context
import android.net.Uri
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

data class PendingDocumentImport(
    val uri: Uri,
    val displayName: String?,
    val detection: DownloadDateDetection
)

data class SelectedDocumentImport(
    val pending: PendingDocumentImport,
    val downloadedAt: Instant
)

data class DocumentImportPreparation(
    val imports: List<PendingDocumentImport>,
    val failures: List<String>,
    val backups: List<Uri> = emptyList()
)

/** Inspects picks with bounded I/O; confirmation retains URIs, never document payloads. */
suspend fun prepareDocumentImports(
    context: Context,
    uris: List<Uri>,
    now: Instant = Instant.now()
): DocumentImportPreparation = withContext(Dispatchers.IO) {
    val imports = mutableListOf<PendingDocumentImport>()
    val failures = mutableListOf<String>()
    val backups = mutableListOf<Uri>()
    for (uri in uris) {
        val displayName = ExternalFileImport.displayNameFor(context, uri)
        val label = displayName?.takeIf { it.isNotBlank() } ?: "file"
        try {
            val inspection = context.contentResolver.openInputStream(uri)?.use {
                PickedDocumentReader.inspect(it, ExternalFileImport.sizeFor(context, uri), displayName, context.cacheDir)
            } ?: error("Could not read the selected file.")
            if (inspection.isBackup) {
                backups += uri
                continue
            }
            val detection = DownloadDateDetector.detect(
                fileCreated = null,
                fileModified = ExternalFileImport.lastModifiedFor(context, uri),
                epubGeneratedAt = inspection.generatedAt,
                now = now
            )
            imports += PendingDocumentImport(uri, displayName, detection)
        } catch (cancelled: kotlinx.coroutines.CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            failures += "$label: ${error.message ?: "Could not read the selected file."}"
        }
    }
    DocumentImportPreparation(imports, failures, backups)
}

/** Read one confirmed document at a time, with the same size bound as preparation. */
suspend fun readPickedDocument(context: Context, uri: Uri): ByteArray = withContext(Dispatchers.IO) {
    context.contentResolver.openInputStream(uri)?.use {
        PickedDocumentReader.readBytes(it, ExternalFileImport.sizeFor(context, uri))
    } ?: error("Could not read the selected file.")
}
