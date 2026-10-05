package io.github.cidy02.kudos.reader

import android.app.Application
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.files.WorkFileStore
import java.nio.file.Files
import java.nio.file.Path
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class)
class ReaderWorkActionsTest {
    @get:Rule val temporary = TemporaryFolder()
    private lateinit var context: Context
    private lateinit var store: WorkFileStore
    private lateinit var actions: ReaderWorkActions
    private val work = SavedWork(id = "11111111-1111-1111-1111-111111111111", title = "Story", author = "Author")
    private val other = work.copy(id = "22222222-2222-2222-2222-222222222222")

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        // FileProvider keeps its folders per authority in a static, and Robolectric gives each
        // test a new files directory: without this every test after the first asks about a
        // folder the remembered ones do not hold, and gets no address.
        FileProvider::class.java.getDeclaredField("sCache").apply { isAccessible = true }
            .let { (it.get(null) as MutableMap<*, *>).clear() }
        store = WorkFileStore(context.filesDir.toPath())
        actions = ReaderWorkActions(context)
    }

    @After
    fun tearDown() {
        listOf("works", "originals", "updates", "datastore", "cookies", "works-other").forEach {
            val root = context.filesDir.toPath().resolve(it)
            if (Files.isSymbolicLink(root)) Files.delete(root) else root.toFile().deleteRecursively()
        }
        context.getDatabasePath("private.db").delete()
        context.cacheDir.resolve("secret.epub").delete()
    }

    private fun epub(target: SavedWork = work): Path = store.workEpubPath(target.id).also {
        Files.createDirectories(it.parent)
        Files.write(it, byteArrayOf(0x50, 0x4B, 0x03, 0x04))
    }

    private fun original(extension: String = "pdf") = runBlocking {
        store.writeOriginal(work.id, extension, "Original contents".toByteArray())
        store.originalFile(work.id)!!
    }

    @Test
    fun addressesPointAtExistingWorkFilesWithTheirRealMimeAndTitleNotACopy() {
        val path = epub()
        original()
        val named = work.copy(title = "雪 / A&B? #2: ‘story’ 📖")
        val epubAddress = actions.fileAddress(named)!!
        val originalAddress = actions.fileAddress(named, original = true)!!
        assertEquals("content", epubAddress.uri.scheme)
        assertEquals("${context.packageName}.fileprovider", epubAddress.uri.authority)
        assertEquals("application/epub+zip", epubAddress.mimeType)
        assertEquals("application/pdf", originalAddress.mimeType)
        listOf(epubAddress to "epub", originalAddress to "pdf").forEach { (address, extension) ->
            assertEquals(2, address.uri.pathSegments.size)
            context.contentResolver.query(address.uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)!!.use {
                assertTrue(it.moveToFirst())
                assertEquals("雪 A&B? #2: ‘story’ 📖.$extension", it.getString(0))
            }
            assertEquals(address.mimeType, context.contentResolver.getType(address.uri))
        }
        // Same process only: proves provider mapping, not an external app's permission.
        context.contentResolver.openInputStream(epubAddress.uri)!!.use {
            assertArrayEquals(Files.readAllBytes(path), it.readBytes())
        }
        assertEquals(listOf("${work.id}.epub"), path.parent.toFile().list()!!.toList())
    }

    /** The title is the author's text; the receiving app is told to use it as a file name. */
    @Test
    fun aTitleCannotPutAPathOrAControlCharacterInTheSharedFilesName() {
        assertEquals("etc passwd.epub", shareFileName("../../etc/passwd", "epub"))
        assertEquals("a b c d.epub", shareFileName("a\\b\u0000c\nd", "epub"))
        assertEquals("Work.pdf", shareFileName(" /./ ", "pdf"))
        assertEquals("雪".repeat(80) + ".epub", shareFileName("雪".repeat(200), "epub"))
        // The cut never leaves half of a two-unit character behind.
        assertEquals("x".repeat(79) + ".epub", shareFileName("x".repeat(79) + "📖", "epub"))
    }

    @Test
    fun originalUsesTheFilesExtensionIncludingTextHtmlZipAndUnknown() {
        listOf("txt" to "text/plain", "html" to "text/html", "zip" to "application/zip",
            "unknownformat" to "application/octet-stream").forEach { (extension, mime) ->
            original(extension)
            assertEquals(mime, actions.fileAddress(work, original = true)!!.mimeType)
        }
    }

    @Test
    fun missingFilesAndUnreadableFlagsAndInvalidIdsReturnNothing() {
        assertNull(actions.fileAddress(work))
        assertNull(actions.fileAddress(work, original = true))
        epub()
        assertNull(actions.fileAddress(work.copy(hasEpub = false)))
        assertNull(actions.fileAddress(work.copy(id = "../${other.id}")))
        assertNull(actions.fileAddress(work.copy(id = "../${other.id}"), original = true))
        assertNull(actions.fileAddress(work.copy(id = "not-a-uuid")))
    }

    @Test
    fun aConversionSidecarAndAnotherWorksFileCannotStandInForTheOriginal() = runBlocking {
        epub(other)
        store.writeOriginal(other.id, "pdf", byteArrayOf(1))
        store.writeConversionRecord(work.id, "{}".toByteArray())
        assertNull(actions.fileAddress(work))
        assertNull(actions.fileAddress(work, original = true))
        assertNull(actions.originalIntent(work))
        assertNull(readerOriginalAction(actions.originalIntent(work) != null) {})
    }

    @Test
    fun providerRejectsEveryNonRootDirectoryAndKeepsTheExistingUpdateRoot() {
        val authority = "${context.packageName}.fileprovider"
        listOf(context.getDatabasePath("private.db").toPath(),
            context.filesDir.toPath().resolve("datastore/settings.preferences_pb"),
            context.filesDir.toPath().resolve("cookies/session"),
            context.filesDir.toPath().resolve("works-other/secret.epub"),
            context.cacheDir.toPath().resolve("secret.epub"),
            temporary.root.toPath().resolve("outside.epub")).forEach { path ->
            Files.createDirectories(path.parent)
            Files.write(path, byteArrayOf(1))
            assertThrows(IllegalArgumentException::class.java) {
                FileProvider.getUriForFile(context, authority, path.toFile())
            }
        }
        val apk = context.filesDir.toPath().resolve("updates/app.apk")
        Files.createDirectories(apk.parent)
        Files.write(apk, byteArrayOf(1))
        assertEquals("content", FileProvider.getUriForFile(context, authority, apk.toFile()).scheme)
    }

    @Test
    fun canonicalChecksRejectSymlinksToOutsideFilesAndToAnotherWorkOrSidecar() = runBlocking {
        val own = epub()
        val another = epub(other)
        val outside = temporary.newFile("outside.epub").toPath()
        for (target in listOf(outside, another, own.parent.resolve("../datastore/private.epub"))) {
            Files.createDirectories(target.normalize().parent)
            Files.write(target.normalize(), byteArrayOf(1))
            Files.delete(own)
            Files.createSymbolicLink(own, target)
            assertNull(actions.fileAddress(work))
        }
        original()
        val source = store.originalFile(work.id)!!
        store.writeConversionRecord(work.id, "{}".toByteArray())
        Files.delete(source)
        Files.createSymbolicLink(source, source.parent.resolve("${work.id}.conversion.json"))
        assertNull(actions.fileAddress(work, original = true))
        Files.delete(source)
        Files.createSymbolicLink(source, outside)
        assertNull(actions.originalIntent(work))
    }

    @Test
    fun aSymlinkedProviderRootCannotExposeEvenAnExistingWorkFile() {
        val outside = temporary.newFolder("outside").toPath()
        Files.write(outside.resolve("${work.id}.epub"), byteArrayOf(1))
        Files.createSymbolicLink(context.filesDir.toPath().resolve("works"), outside)
        assertNull(actions.fileAddress(work))
    }

    @Test
    fun shareChoosesAo3IdentityThenHttpSourceThenReadableEpubForEachOrigin() {
        epub()
        val cases = listOf(
            work.copy(ao3WorkID = 789, sourceUrl = "https://example.org/story") to "https://archiveofourown.org/works/789",
            work.copy(sourceUrl = "https://archiveofourown.org/works/123/chapters/456") to "https://archiveofourown.org/works/123",
            work.copy(sourceUrl = "https://example.org/story") to "https://example.org/story",
            work.copy(sourceUrl = "http://example.org/story", ao3Unavailable = true) to "http://example.org/story",
            work.copy(ao3WorkID = 789, ao3Unavailable = true, hasEpub = false) to "https://archiveofourown.org/works/789",
            work.copy(sourceUrl = "httpish://example.org/story") to "httpish://example.org/story"
        )
        cases.forEach { (target, url) ->
            val intent = actions.shareIntent(target)!!
            assertEquals("text/plain", intent.type)
            assertEquals("${work.title}\n$url", intent.getStringExtra(Intent.EXTRA_TEXT))
            assertFalse(intent.hasExtra(Intent.EXTRA_STREAM))
            assertEquals(0, intent.flags)
        }
        listOf(work, work.copy(sourceUrl = "file:///private/original.html"),
            work.copy(sourceUrl = "invalid address"), work.copy(sourceUrl = "mailto:author@example.org"))
            .forEach { assertEquals("application/epub+zip", actions.shareIntent(it)!!.type) }
        assertNull(actions.shareIntent(work.copy(hasEpub = false)))
        Files.delete(store.workEpubPath(work.id))
        assertNull(actions.shareIntent(work))
        assertEquals("text/plain", actions.shareIntent(cases.first().first)!!.type)
    }

    @Test
    fun originalNeedsOnlyItsArchivedFileAndHasIosAccessibilityLabel() {
        assertNull(readerOriginalAction(actions.originalIntent(work) != null) {})
        original()
        var opened = false
        val action = readerOriginalAction(actions.originalIntent(work) != null) { opened = true }!!
        assertEquals("original", action.id)
        assertEquals("View the original file this work was converted from", action.accessibilityLabel)
        assertTrue(action.isEnabled)
        action.action()
        assertTrue(opened)
        assertNotNull(actions.originalIntent(work.copy(hasEpub = false)))
    }

    @Test
    fun matureFinishedAndHistoryHiddenWorksKeepActionsButDeletedWorksNeverGetAddresses() {
        epub()
        original()
        listOf(work.copy(rating = "Mature"), work.copy(rating = "Explicit"), work.copy(isFinished = true),
            work.copy(hiddenFromHistoryAt = Instant.now())).forEach {
            assertNotNull(actions.shareIntent(it))
            assertNotNull(actions.originalIntent(it))
        }
        val deleted = work.copy(isDeleted = true)
        assertNull(actions.fileAddress(deleted))
        assertNull(actions.fileAddress(deleted, original = true))
        assertNull(actions.shareIntent(deleted.copy(ao3WorkID = 123)))
        assertNull(actions.originalIntent(deleted))
        val recorded = mutableListOf<Intent>()
        actions.share(deleted) { recorded.add(it) }
        actions.openOriginal(deleted) { recorded.add(it) }
        assertTrue(recorded.isEmpty())
    }

    @Test
    fun recordingLauncherReceivesSendChooserAndViewWithOneReadOnlyUri() {
        epub()
        original()
        val beforeFiles = context.filesDir.walkTopDown().map { it.relativeTo(context.filesDir).path }.toList()
        val beforeCache = context.cacheDir.walkTopDown().map { it.relativeTo(context.cacheDir).path }.toList()
        val recorded = mutableListOf<Intent>()
        assertNull(actions.share(work) { recorded.add(it) })
        assertNull(actions.openOriginal(work) { recorded.add(it) })
        assertEquals(Intent.ACTION_CHOOSER, recorded[0].action)
        @Suppress("DEPRECATION")
        val send = recorded[0].getParcelableExtra<Intent>(Intent.EXTRA_INTENT)!!
        @Suppress("DEPRECATION")
        val stream = send.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)!!
        assertEquals(Intent.ACTION_SEND, send.action)
        assertEquals("application/epub+zip", send.type)
        assertEquals(actions.fileAddress(work)!!.uri, stream)
        assertEquals(work.title, send.getStringExtra(Intent.EXTRA_SUBJECT))
        val view = recorded[1]
        assertEquals(Intent.ACTION_VIEW, view.action)
        assertEquals("application/pdf", view.type)
        assertEquals(actions.fileAddress(work, original = true)!!.uri, view.data)
        assertFalse(view.hasExtra(Intent.EXTRA_STREAM))
        listOf(send, view).forEach {
            assertEquals(Intent.FLAG_GRANT_READ_URI_PERMISSION, it.flags)
            assertEquals(1, it.clipData!!.itemCount)
            assertEquals(if (it === send) stream else view.data, it.clipData!!.getItemAt(0).uri)
        }
        assertEquals(Intent.FLAG_GRANT_READ_URI_PERMISSION, recorded[0].flags)
        assertEquals(1, recorded[0].clipData!!.itemCount)
        assertEquals(stream, recorded[0].clipData!!.getItemAt(0).uri)
        assertEquals(beforeFiles, context.filesDir.walkTopDown().map { it.relativeTo(context.filesDir).path }.toList())
        assertEquals(beforeCache, context.cacheDir.walkTopDown().map { it.relativeTo(context.cacheDir).path }.toList())

        recorded.clear()
        assertNull(actions.share(work.copy(sourceUrl = "https://example.org/story")) { recorded.add(it) })
        @Suppress("DEPRECATION")
        val link = recorded.single().getParcelableExtra<Intent>(Intent.EXTRA_INTENT)!!
        assertEquals(Intent.ACTION_SEND, link.action)
        assertEquals("text/plain", link.type)
        assertEquals("${work.title}\nhttps://example.org/story", link.getStringExtra(Intent.EXTRA_TEXT))
        assertFalse(link.hasExtra(Intent.EXTRA_STREAM))
        assertEquals(0, link.flags)
    }

    @Test
    fun missingViewerReturnsPlainMessageInsteadOfCrashingAndMissingFilesNeverLaunch() {
        original()
        assertEquals("No app on this device can open this file.",
            actions.openOriginal(work) { throw ActivityNotFoundException() })
        Files.delete(store.originalFile(work.id)!!)
        val recorded = mutableListOf<Intent>()
        assertNotNull(actions.openOriginal(work) { recorded.add(it) })
        assertNotNull(actions.share(work) { recorded.add(it) })
        assertTrue(recorded.isEmpty())
    }
}
