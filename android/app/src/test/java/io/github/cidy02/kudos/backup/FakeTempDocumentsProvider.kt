package io.github.cidy02.kudos.backup

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.ProviderInfo
import android.content.res.AssetFileDescriptor
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import org.robolectric.shadows.ShadowContentResolver

/**
 * File-backed SAF stand-in for unit tests.
 *
 * Implemented as a plain [ContentProvider] (not [android.provider.DocumentsProvider])
 * because Robolectric + API 35's DocumentsProvider rejects the pre-O
 * `query(uri, projection, selection, …)` signature that
 * [androidx.documentfile.provider.DocumentFile] still uses, with
 * `UnsupportedOperationException: Pre-Android-O query format not supported`.
 *
 * Speaks enough of the DocumentsContract wire format for DocumentFile and
 * ContentResolver open/create/rename/delete used by [SyncRepository]:
 *  - query document / child documents
 *  - call(create/delete/rename)
 *  - openFile → real [ParcelFileDescriptor] (so `FileDescriptor.sync()` works)
 */
class FakeTempDocumentsProvider : ContentProvider() {
    private data class Node(
        val id: String,
        val name: String,
        val parentId: String?,
        val directory: Boolean,
        val file: File
    )

    private val nodes = ConcurrentHashMap<String, Node>()
    private lateinit var rootDir: File

    fun install(context: Context, root: File): Uri {
        rootDir = root
        rootDir.mkdirs()
        nodes.clear()
        nodes[ROOT_DOCUMENT_ID] = Node(
            id = ROOT_DOCUMENT_ID,
            name = rootDir.name,
            parentId = null,
            directory = true,
            file = rootDir
        )

        val info = ProviderInfo().apply {
            authority = AUTHORITY
            exported = true
            grantUriPermissions = true
        }
        attachInfo(context, info)
        // attachInfo may reset provider state on some paths — re-seed root.
        nodes[ROOT_DOCUMENT_ID] = Node(
            id = ROOT_DOCUMENT_ID,
            name = rootDir.name,
            parentId = null,
            directory = true,
            file = rootDir
        )
        ShadowContentResolver.registerProviderInternal(AUTHORITY, this)

        val treeUri = DocumentsContract.buildTreeDocumentUri(AUTHORITY, ROOT_DOCUMENT_ID)
        val flags =
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
        context.grantUriPermission(context.packageName, treeUri, flags)
        return treeUri
    }

    override fun onCreate(): Boolean = true

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor {
        return queryInternal(uri, projection)
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        queryArgs: Bundle?,
        cancellationSignal: android.os.CancellationSignal?
    ): Cursor {
        return queryInternal(uri, projection)
    }

    private fun queryInternal(uri: Uri, projection: Array<out String>?): Cursor {
        val path = uri.pathSegments
        // tree/{treeId}/document/{docId}/children
        // tree/{treeId}/document/{docId}
        // document/{docId}
        // document/{docId}/children
        return when {
            path.size >= 4 &&
                path[0] == "tree" &&
                path[2] == "document" &&
                path.getOrNull(4) == "children" -> {
                cursorFor(childrenOf(path[3]), projection)
            }
            path.size >= 4 && path[0] == "tree" && path[2] == "document" -> {
                cursorFor(listOf(requireNode(path[3])), projection)
            }
            path.size >= 3 && path[0] == "document" && path.getOrNull(2) == "children" -> {
                cursorFor(childrenOf(path[1]), projection)
            }
            path.size >= 2 && path[0] == "document" -> {
                cursorFor(listOf(requireNode(path[1])), projection)
            }
            path.size >= 1 && path[0] == "root" -> {
                // Minimal roots listing for completeness.
                val cols = projection ?: DEFAULT_ROOT_PROJECTION
                val cursor = MatrixCursor(cols)
                val row = cursor.newRow()
                for (col in cols) {
                    when (col) {
                        DocumentsContract.Root.COLUMN_ROOT_ID -> row.add(ROOT_DOCUMENT_ID)
                        DocumentsContract.Root.COLUMN_DOCUMENT_ID -> row.add(ROOT_DOCUMENT_ID)
                        DocumentsContract.Root.COLUMN_TITLE -> row.add("Fake SAF Root")
                        DocumentsContract.Root.COLUMN_FLAGS -> row.add(
                            DocumentsContract.Root.FLAG_SUPPORTS_CREATE or
                                DocumentsContract.Root.FLAG_SUPPORTS_IS_CHILD
                        )
                        else -> row.add(null)
                    }
                }
                cursor
            }
            else -> throw FileNotFoundException("Unsupported query uri: $uri")
        }
    }

    override fun getType(uri: Uri): String? {
        val docId = documentIdFrom(uri) ?: return null
        val node = nodes[docId] ?: return null
        return if (node.directory) {
            DocumentsContract.Document.MIME_TYPE_DIR
        } else {
            mimeForName(node.name)
        }
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int {
        val docId = documentIdFrom(uri) ?: return 0
        return if (deleteNode(docId)) 1 else 0
    }

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?
    ): Int = 0

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        return openNodeFile(uri, mode)
    }

    override fun openAssetFile(uri: Uri, mode: String): AssetFileDescriptor {
        // ContentResolver.openInputStream/openOutputStream go through this path.
        val pfd = openNodeFile(uri, mode)
        return AssetFileDescriptor(pfd, 0, AssetFileDescriptor.UNKNOWN_LENGTH)
    }

    private fun openNodeFile(uri: Uri, mode: String): ParcelFileDescriptor {
        val docId = documentIdFrom(uri)
            ?: throw FileNotFoundException("No document id in $uri")
        val node = requireNode(docId)
        if (node.directory) {
            throw FileNotFoundException("Cannot open directory $docId")
        }
        val pfdMode = ParcelFileDescriptor.parseMode(mode)
        if (!node.file.exists() && (pfdMode and ParcelFileDescriptor.MODE_CREATE) != 0) {
            node.file.parentFile?.mkdirs()
            node.file.createNewFile()
        }
        return ParcelFileDescriptor.open(node.file, pfdMode)
    }

    override fun call(method: String, arg: String?, extras: Bundle?): Bundle? {
        // DocumentsContract.create/delete/renameDocument put these @hide keys:
        //   EXTRA_URI = "uri"
        //   Document.COLUMN_MIME_TYPE / COLUMN_DISPLAY_NAME for create+rename
        // See AOSP DocumentsContract.java.
        val result = Bundle()
        when (method) {
            METHOD_CREATE_DOCUMENT -> {
                val parent = extras.uriExtra()
                    ?: throw IllegalArgumentException("missing parent uri")
                val mime = extras?.getString(DocumentsContract.Document.COLUMN_MIME_TYPE)
                    ?: throw IllegalArgumentException("missing mime")
                val displayName = extras.getString(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                    ?: throw IllegalArgumentException("missing display name")
                val parentId = documentIdFrom(parent)
                    ?: throw FileNotFoundException("parent id from $parent")
                val newId = createNode(parentId, mime, displayName)
                result.putParcelable(EXTRA_URI, documentUriUsingTree(parent, newId))
            }
            METHOD_DELETE_DOCUMENT -> {
                val target = extras.uriExtra()
                    ?: throw IllegalArgumentException("missing uri")
                val docId = documentIdFrom(target)
                    ?: throw FileNotFoundException("doc id from $target")
                deleteNode(docId)
            }
            METHOD_RENAME_DOCUMENT -> {
                val target = extras.uriExtra()
                    ?: throw IllegalArgumentException("missing uri")
                val displayName = extras?.getString(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                    ?: throw IllegalArgumentException("missing display name")
                val docId = documentIdFrom(target)
                    ?: throw FileNotFoundException("doc id from $target")
                renameNode(docId, displayName)
                result.putParcelable(EXTRA_URI, documentUriUsingTree(target, docId))
            }
            else -> return super.call(method, arg, extras)
        }
        return result
    }

    private fun Bundle?.uriExtra(): Uri? {
        if (this == null) return null
        return getParcelable(EXTRA_URI, Uri::class.java)
            ?: @Suppress("DEPRECATION") getParcelable(EXTRA_URI)
    }

    private fun createNode(parentDocumentId: String, mimeType: String, displayName: String): String {
        val parent = requireNode(parentDocumentId)
        if (!parent.directory) throw IllegalStateException("Parent is not a directory")

        // Keep the exact display name (including extension). Real providers may
        // append a MIME-derived extension; SyncRepository tolerates that for temps
        // by retaining the createDocument handle. Tests need stable names.
        val existing = nodes.values.firstOrNull {
            it.parentId == parentDocumentId && it.name == displayName
        }
        if (existing != null) return existing.id

        val isDir = mimeType == DocumentsContract.Document.MIME_TYPE_DIR
        val childFile = File(parent.file, displayName)
        if (isDir) {
            if (!childFile.mkdirs() && !childFile.isDirectory) {
                throw IOException("Could not create directory $displayName")
            }
        } else {
            parent.file.mkdirs()
            if (!childFile.exists() && !childFile.createNewFile()) {
                throw IOException("Could not create file $displayName")
            }
        }

        val id = UUID.randomUUID().toString()
        nodes[id] = Node(
            id = id,
            name = displayName,
            parentId = parentDocumentId,
            directory = isDir,
            file = childFile
        )
        return id
    }

    private fun deleteNode(documentId: String): Boolean {
        val node = nodes[documentId] ?: return false
        if (node.id == ROOT_DOCUMENT_ID) {
            throw IllegalArgumentException("Cannot delete root")
        }
        nodes.values
            .filter { it.parentId == documentId }
            .map { it.id }
            .forEach { deleteNode(it) }
        if (node.directory) {
            node.file.deleteRecursively()
        } else {
            node.file.delete()
        }
        nodes.remove(documentId)
        return true
    }

    private fun renameNode(documentId: String, displayName: String) {
        val node = requireNode(documentId)
        if (node.id == ROOT_DOCUMENT_ID) {
            throw IllegalArgumentException("Cannot rename root")
        }
        val target = File(node.file.parentFile, displayName)
        if (target.absolutePath == node.file.absolutePath) return

        nodes.values
            .filter {
                it.id != documentId &&
                    it.parentId == node.parentId &&
                    it.name == displayName
            }
            .forEach { deleteNode(it.id) }
        if (target.exists() && !target.delete()) {
            throw IOException("Could not replace existing target: $displayName")
        }
        if (!node.file.renameTo(target)) {
            throw IOException("Rename failed for ${node.name} -> $displayName")
        }
        nodes[documentId] = node.copy(name = displayName, file = target)
    }

    private fun childrenOf(parentDocumentId: String): List<Node> {
        requireNode(parentDocumentId)
        return nodes.values.filter { it.parentId == parentDocumentId }
    }

    private fun requireNode(documentId: String): Node {
        return nodes[documentId]
            ?: throw FileNotFoundException("No document $documentId")
    }

    private fun cursorFor(docs: Collection<Node>, projection: Array<out String>?): Cursor {
        val cols = projection ?: DEFAULT_DOCUMENT_PROJECTION
        val cursor = MatrixCursor(cols)
        for (node in docs) {
            val row = ArrayList<Any?>(cols.size)
            for (col in cols) {
                row.add(columnValue(node, col))
            }
            cursor.addRow(row)
        }
        return cursor
    }

    private fun columnValue(node: Node, column: String): Any? {
        return when (column) {
            DocumentsContract.Document.COLUMN_DOCUMENT_ID -> node.id
            DocumentsContract.Document.COLUMN_DISPLAY_NAME -> node.name
            DocumentsContract.Document.COLUMN_MIME_TYPE ->
                if (node.directory) {
                    DocumentsContract.Document.MIME_TYPE_DIR
                } else {
                    mimeForName(node.name)
                }
            DocumentsContract.Document.COLUMN_SIZE ->
                if (node.directory) 0L else node.file.length()
            DocumentsContract.Document.COLUMN_LAST_MODIFIED -> node.file.lastModified()
            DocumentsContract.Document.COLUMN_FLAGS -> {
                var flags =
                    DocumentsContract.Document.FLAG_SUPPORTS_WRITE or
                        DocumentsContract.Document.FLAG_SUPPORTS_DELETE or
                        DocumentsContract.Document.FLAG_SUPPORTS_RENAME
                if (node.directory) {
                    flags = flags or DocumentsContract.Document.FLAG_DIR_SUPPORTS_CREATE
                }
                flags
            }
            else -> null
        }
    }

    private fun mimeForName(name: String): String {
        return when {
            name.endsWith(".json", ignoreCase = true) ||
                name.endsWith(".bak", ignoreCase = true) ||
                name.contains(".json") -> "application/json"
            name.endsWith(".epub", ignoreCase = true) -> "application/epub+zip"
            name.endsWith(".ttf", ignoreCase = true) ||
                name.endsWith(".otf", ignoreCase = true) -> "font/ttf"
            else -> "application/octet-stream"
        }
    }

    private fun documentIdFrom(uri: Uri): String? {
        val path = uri.pathSegments
        // tree/{treeId}/document/{docId}[…]
        if (path.size >= 4 && path[0] == "tree" && path[2] == "document") {
            return path[3]
        }
        // document/{docId}
        if (path.size >= 2 && path[0] == "document") {
            return path[1]
        }
        // tree/{treeId}  → tree document id is the tree id itself
        if (path.size == 2 && path[0] == "tree") {
            return path[1]
        }
        return null
    }

    private fun documentUriUsingTree(treeOrDocUri: Uri, documentId: String): Uri {
        // Prefer preserving the tree prefix so DocumentFile stays in tree mode.
        val treeId = try {
            DocumentsContract.getTreeDocumentId(treeOrDocUri)
        } catch (_: Exception) {
            ROOT_DOCUMENT_ID
        }
        val treeUri = DocumentsContract.buildTreeDocumentUri(AUTHORITY, treeId)
        return DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
    }

    companion object {
        const val AUTHORITY = "io.github.cidy02.kudos.test.documents"
        const val ROOT_DOCUMENT_ID = "root"

        private val DEFAULT_ROOT_PROJECTION = arrayOf(
            DocumentsContract.Root.COLUMN_ROOT_ID,
            DocumentsContract.Root.COLUMN_DOCUMENT_ID,
            DocumentsContract.Root.COLUMN_TITLE,
            DocumentsContract.Root.COLUMN_FLAGS
        )

        private val DEFAULT_DOCUMENT_PROJECTION = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_FLAGS,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED
        )

        // Framework DocumentsContract @hide constants (AOSP DocumentsContract.java).
        private const val METHOD_CREATE_DOCUMENT = "android:createDocument"
        private const val METHOD_DELETE_DOCUMENT = "android:deleteDocument"
        private const val METHOD_RENAME_DOCUMENT = "android:renameDocument"
        private const val EXTRA_URI = "uri"
    }
}
