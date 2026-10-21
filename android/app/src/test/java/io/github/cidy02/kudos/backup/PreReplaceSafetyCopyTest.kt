package io.github.cidy02.kudos.backup

import android.content.Context
import android.content.pm.ProviderInfo
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import androidx.test.core.app.ApplicationProvider
import java.time.Instant
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Replace's undo copy uses iOS's names and is a document the Import picker can open. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class PreReplaceSafetyCopyTest {
    private lateinit var context: Context

    @Before
    fun cleanCopies() {
        context = ApplicationProvider.getApplicationContext()
        SafetyCopies.directory(context).listFiles()?.forEach { file ->
            if (file.name.endsWith(".kudosbackup") || file.name.startsWith(".")) file.delete()
        }
    }

    @Test
    fun undoCopiesKeepDistinctNamesAndTheImportPickerCanReadThem() {
        val at = Instant.parse("2026-10-20T15:04:05Z")
        val directory = SafetyCopies.directory(context)
        val firstBytes = "first library".toByteArray()
        val secondBytes = "second library".toByteArray()
        val first = SafetyCopies.write(directory, firstBytes, at)
        val second = SafetyCopies.write(directory, secondBytes, at)

        assertEquals(PreReplaceBackupNaming.fileName(at, 0), first)
        assertEquals(PreReplaceBackupNaming.fileName(at, 1), second)
        assertNotEquals(first, second)
        assertTrue(first.startsWith("Kudos Library Before Replace "))
        assertTrue(second.endsWith(" (2).kudosbackup"))
        assertArrayEquals(firstBytes, java.io.File(directory, first).readBytes())
        assertArrayEquals(secondBytes, java.io.File(directory, second).readBytes())
        assertTrue(directory.listFiles()!!.none { it.name.startsWith(".") })

        val authority = "${context.packageName}.safetycopies"
        assertNotNull(context.packageManager.resolveContentProvider(authority, 0))

        val info = ProviderInfo().apply {
            this.authority = authority
            exported = true
            grantUriPermissions = true
            readPermission = android.Manifest.permission.MANAGE_DOCUMENTS
            writePermission = android.Manifest.permission.MANAGE_DOCUMENTS
        }
        val provider = KudosSafetyDocumentsProvider()
        provider.attachInfo(context, info)
        val names = provider.queryChildDocuments(
            KudosSafetyDocumentsProvider.ROOT_DOCUMENT_ID, null, null as String?
        ).use { cursor ->
            val index = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            buildList {
                while (cursor.moveToNext()) add(cursor.getString(index))
            }
        }
        assertEquals(setOf(first, second), names.toSet())
        assertArrayEquals(firstBytes, provider.openDocument(first, "r", null).readBytes())
        assertArrayEquals(secondBytes, provider.openDocument(second, "r", null).readBytes())

        val intent = OpenBackupDocument().createIntent(
            context,
            arrayOf("application/zip", "application/octet-stream", "*/*")
        )
        @Suppress("DEPRECATION")
        val initial = intent.getParcelableExtra<Uri>(DocumentsContract.EXTRA_INITIAL_URI)
        assertEquals(authority, initial!!.authority)
        assertEquals(
            KudosSafetyDocumentsProvider.ROOT_DOCUMENT_ID,
            DocumentsContract.getDocumentId(initial)
        )
    }

    private fun ParcelFileDescriptor.readBytes(): ByteArray =
        ParcelFileDescriptor.AutoCloseInputStream(this).use { it.readBytes() }
}
