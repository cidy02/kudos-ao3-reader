package io.github.cidy02.kudos.backup

import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.database.MatrixCursor
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.DocumentsProvider
import androidx.activity.result.contract.ActivityResultContracts
import java.io.File
import java.io.FileNotFoundException

/**
 * Lists the undo copies [SafetyCopies] writes, so Import's document picker can
 * open the same directory iOS's import sheet lists. Read-only. Not a FileProvider
 * path: that one shares individual files, and a library archive does not belong there.
 */
class KudosSafetyDocumentsProvider : DocumentsProvider() {
    override fun onCreate(): Boolean = true

    override fun queryRoots(projection: Array<out String>?): Cursor {
        val cursor = MatrixCursor(projection ?: ROOT_COLUMNS)
        put(
            cursor,
            mapOf(
                DocumentsContract.Root.COLUMN_ROOT_ID to ROOT_DOCUMENT_ID,
                DocumentsContract.Root.COLUMN_DOCUMENT_ID to ROOT_DOCUMENT_ID,
                DocumentsContract.Root.COLUMN_TITLE to "Kudos undo copies",
                DocumentsContract.Root.COLUMN_FLAGS to DocumentsContract.Root.FLAG_LOCAL_ONLY,
                DocumentsContract.Root.COLUMN_MIME_TYPES to "*/*",
                DocumentsContract.Root.COLUMN_ICON to io.github.cidy02.kudos.R.drawable.ic_kudos_mark
            )
        )
        return cursor
    }

    override fun queryDocument(documentId: String, projection: Array<out String>?): Cursor {
        val cursor = MatrixCursor(projection ?: DOCUMENT_COLUMNS)
        if (documentId == ROOT_DOCUMENT_ID) {
            put(cursor, directoryRow())
        } else {
            put(cursor, fileRow(copyFile(documentId)))
        }
        return cursor
    }

    override fun queryChildDocuments(
        parentDocumentId: String,
        projection: Array<out String>?,
        sortOrder: String?
    ): Cursor {
        val cursor = MatrixCursor(projection ?: DOCUMENT_COLUMNS)
        if (parentDocumentId != ROOT_DOCUMENT_ID) return cursor
        val directory = SafetyCopies.directory(requireNotNull(context))
        directory.listFiles()?.sortedBy { it.name }?.forEach { file ->
            if (isListedCopy(file)) put(cursor, fileRow(file))
        }
        return cursor
    }

    override fun openDocument(
        documentId: String,
        mode: String,
        signal: CancellationSignal?
    ): ParcelFileDescriptor {
        if (mode.contains("w")) throw UnsupportedOperationException("Undo copies are read-only.")
        return ParcelFileDescriptor.open(copyFile(documentId), ParcelFileDescriptor.MODE_READ_ONLY)
    }

    private fun directoryRow(): Map<String, Any?> = mapOf(
        DocumentsContract.Document.COLUMN_DOCUMENT_ID to ROOT_DOCUMENT_ID,
        DocumentsContract.Document.COLUMN_DISPLAY_NAME to "Kudos undo copies",
        DocumentsContract.Document.COLUMN_MIME_TYPE to DocumentsContract.Document.MIME_TYPE_DIR,
        DocumentsContract.Document.COLUMN_FLAGS to 0,
        DocumentsContract.Document.COLUMN_SIZE to 0L,
        DocumentsContract.Document.COLUMN_LAST_MODIFIED to
            SafetyCopies.directory(requireNotNull(context)).lastModified()
    )

    private fun fileRow(file: File): Map<String, Any?> = mapOf(
        DocumentsContract.Document.COLUMN_DOCUMENT_ID to file.name,
        DocumentsContract.Document.COLUMN_DISPLAY_NAME to file.name,
        DocumentsContract.Document.COLUMN_MIME_TYPE to "application/octet-stream",
        DocumentsContract.Document.COLUMN_FLAGS to 0,
        DocumentsContract.Document.COLUMN_SIZE to file.length(),
        DocumentsContract.Document.COLUMN_LAST_MODIFIED to file.lastModified()
    )

    private fun copyFile(documentId: String): File {
        require(isSafeCopyName(documentId)) { "Unsafe undo-copy id." }
        val directory = SafetyCopies.directory(requireNotNull(context)).canonicalFile
        val file = File(directory, documentId).canonicalFile
        require(file.parentFile == directory) { "Unsafe undo-copy path." }
        if (!file.isFile) throw FileNotFoundException(documentId)
        return file
    }

    private fun isListedCopy(file: File): Boolean =
        file.isFile && isSafeCopyName(file.name)

    companion object {
        const val ROOT_DOCUMENT_ID = "root"

        fun authority(context: Context): String = "${context.packageName}.safetycopies"

        private val ROOT_COLUMNS = arrayOf(
            DocumentsContract.Root.COLUMN_ROOT_ID,
            DocumentsContract.Root.COLUMN_MIME_TYPES,
            DocumentsContract.Root.COLUMN_FLAGS,
            DocumentsContract.Root.COLUMN_ICON,
            DocumentsContract.Root.COLUMN_TITLE,
            DocumentsContract.Root.COLUMN_DOCUMENT_ID,
            DocumentsContract.Root.COLUMN_AVAILABLE_BYTES
        )

        private val DOCUMENT_COLUMNS = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            DocumentsContract.Document.COLUMN_FLAGS,
            DocumentsContract.Document.COLUMN_SIZE
        )

        internal fun isSafeCopyName(name: String): Boolean =
            name.isNotEmpty() &&
                !name.contains('/') &&
                !name.contains('\\') &&
                name != "." &&
                name != ".." &&
                !name.contains("..") &&
                !name.startsWith(".") &&
                name.endsWith(".${PreReplaceBackupNaming.fileExtension}")
    }
}

private fun put(cursor: MatrixCursor, values: Map<String, Any?>) {
    val row = arrayOfNulls<Any>(cursor.columnCount)
    for (index in row.indices) {
        row[index] = values[cursor.getColumnName(index)]
    }
    cursor.addRow(row)
}

/** Import Backup. Opens on the undo-copy root so the picker lists what Replace just wrote. */
class OpenBackupDocument : ActivityResultContracts.OpenDocument() {
    override fun createIntent(context: Context, input: Array<String>): Intent {
        return super.createIntent(context, input).apply {
            putExtra(
                DocumentsContract.EXTRA_INITIAL_URI,
                DocumentsContract.buildDocumentUri(
                    KudosSafetyDocumentsProvider.authority(context),
                    KudosSafetyDocumentsProvider.ROOT_DOCUMENT_ID
                )
            )
        }
    }
}
