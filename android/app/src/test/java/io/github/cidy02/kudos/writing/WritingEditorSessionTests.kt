package io.github.cidy02.kudos.writing

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.network.ao3.writing.recovery.WritingTextRecovery
import java.nio.file.Files
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.*
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class WritingEditorSessionTests {
    @get:Rule val temporary = TemporaryFolder()
    private val context: Application get() = ApplicationProvider.getApplicationContext()
    private fun store() = WritingTextRecovery(temporary.newFolder().toPath())
    private fun TestScope.session(store: WritingTextRecovery = store(),
        writes: MutableList<Pair<String, Int>> = mutableListOf(),
        counter: suspend (String) -> Int = { it.length },
        changed: (String) -> Unit = {}): WritingEditorSession = WritingEditorSession(
        WritingNativeTextField(context, "form"), "form", store, "Writer", "work:17", "content", this,
        { testScheduler.currentTime }, changed, counter, { text, sequence -> writes += text to sequence })

    @Test fun anEditWritesOnceAfterOnePointFiveSeconds() = runTest {
        val writes = mutableListOf<Pair<String, Int>>()
        val session = session(writes = writes)
        session.editor.view.text.append(" edit")
        advanceTimeBy(1_499); runCurrent(); assertTrue(writes.isEmpty())
        advanceTimeBy(1); runCurrent()
        assertEquals(listOf("form edit" to 1), writes)
        advanceTimeBy(30_000); runCurrent(); assertEquals(1, writes.size)
    }

    @Test fun continuousEditsWriteWithinTwentySeconds() = runTest {
        val writes = mutableListOf<Pair<String, Int>>()
        val session = session(writes = writes)
        repeat(20) { session.editor.view.text.append("x"); advanceTimeBy(1_000); runCurrent() }
        assertEquals(1, writes.size)
        assertEquals(1, writes.single().second)
    }

    @Test fun DoneForcesOneAndUnchangedTextDoesNotWriteAgain() = runTest {
        val writes = mutableListOf<Pair<String, Int>>()
        val changes = mutableListOf<String>()
        val session = session(writes = writes, changed = { changes += it })
        session.editor.view.text.append(" changed")
        assertEquals("form changed", session.done()); runCurrent()
        assertEquals(listOf("form changed" to 1), writes)
        assertEquals(listOf("form changed"), changes)
        session.done(); advanceTimeBy(30_000); runCurrent()
        assertEquals(1, writes.size)
        session.editor.view.text.append("x"); session.editor.view.text.delete(12, 13)
        session.done(); runCurrent(); assertEquals(1, writes.size)
    }

    @Test fun anOlderCountNeverReplacesANewerOne() = runTest {
        val opening = CompletableDeferred<Int>()
        val first = CompletableDeferred<Int>()
        val second = CompletableDeferred<Int>()
        val session = session(counter = { when (it) { "form" -> opening.await(); "form1" -> first.await(); else -> second.await() } })
        runCurrent()
        session.editor.view.text.append("1"); session.done(); runCurrent()
        session.editor.view.text.append("2"); session.done(); runCurrent()
        second.complete(22); runCurrent(); assertEquals(22, session.wordCount)
        first.complete(11); opening.complete(4); runCurrent(); assertEquals(22, session.wordCount)
    }

    @Test fun recoveryOfferedOnlyForDifferingCopiesRestoreReplacesAndDeleteRemovesOnlyThatFile() = runTest {
        val store = store()
        val key = store.fileURL("Writer", "work:17", "content")
        val same = store.sessionURL(key)
        val different = store.sessionURL(key)
        val other = store.sessionURL(key)
        withContext(Dispatchers.IO) {
            store.save("form", "form", same)
            store.save("restore", "older form", different)
            store.save("another copy", "form", other)
        }
        val writes = mutableListOf<Pair<String, Int>>()
        val session = session(store, writes)
        session.opening.join()
        assertEquals(setOf(different, other), session.recoveries.map { it.url }.toSet())
        session.selectRecovery(session.recoveries.first { it.url == different }).join()
        assertTrue(session.recoveryFormChanged)
        session.restore(); runCurrent()
        assertEquals("restore", session.editor.takeText())
        assertEquals(listOf("restore" to 1), writes)
        assertTrue(session.recoveries.isEmpty())
        session.editor.undo(); assertEquals("form", session.editor.takeText())
        val copy = WritingTextRecovery.Copy(different, withContext(Dispatchers.IO) { store.load(different)!! })
        session.selectRecovery(copy).join(); session.deleteSelectedCopy()!!.join()
        assertTrue(Files.exists(same)); assertTrue(Files.exists(other)); assertFalse(Files.exists(different))
    }

    @Test fun theScheduledCheckpointUsesTheExistingWriterAndE1Store() = runTest {
        val store = store()
        val session = WritingEditorSession(WritingNativeTextField(context, "form"), "form", store,
            "Writer", "work:17", "content", this, { testScheduler.currentTime }, count = { 1 })
        session.editor.view.text.append(" real checkpoint")
        advanceTimeBy(1_499); runCurrent()
        assertFalse(Files.exists(session.recoveryURL))
        advanceTimeBy(1); runCurrent(); session.awaitWrites()
        val entry = withContext(Dispatchers.IO) { store.load(session.recoveryURL)!! }
        assertEquals("form real checkpoint", entry.text)
        assertEquals(WritingTextRecovery.digest("form"), entry.originalDigest)
        assertEquals(1, session.scheduler.checkpointCount)
    }

    @Test fun anEqualOnlyRecoveryDoesNotOfferTheSheet() = runTest {
        val store = store()
        val key = store.fileURL("Writer", "work:17", "content")
        val file = store.sessionURL(key)
        withContext(Dispatchers.IO) { store.save("form", "form", file) }
        val session = session(store)
        session.opening.join()
        assertTrue(session.recoveries.isEmpty())
        assertNull(session.selectedRecovery)
        assertTrue(Files.exists(file))
    }

    @Test fun leavingWithoutDoneFlushesIntoTheParentAndLetsTheRecoveryWriteFinish() = runTest {
        val ownerJob = kotlinx.coroutines.Job(coroutineContext[kotlinx.coroutines.Job])
        val ownerScope = kotlinx.coroutines.CoroutineScope(coroutineContext + ownerJob)
        val writes = mutableListOf<Pair<String, Int>>()
        val changes = mutableListOf<String>()
        val session = WritingEditorSession(WritingNativeTextField(context, "form"), "form", store(),
            "Writer", "work:17", "content", ownerScope, { testScheduler.currentTime },
            onCheckpoint = { changes += it }, count = { 1 }, write = { value, sequence -> writes += value to sequence })
        session.editor.view.text.append(" departing")
        session.finish()
        ownerJob.join()
        assertEquals(listOf("form departing"), changes)
        assertEquals(listOf("form departing" to 1), writes)
        assertNull(session.editor.onEdited)
    }

    @Test fun aFailedWriteUsesTheReferencesEditorErrorWords() = runTest {
        val session = WritingEditorSession(WritingNativeTextField(context, "form"), "form", store(),
            "Writer", "work:17", "content", this, { testScheduler.currentTime }, count = { 1 },
            write = { _, _ -> throw java.io.IOException("disk full") })
        session.editor.view.text.append("x"); session.done(); runCurrent()
        assertEquals("Local recovery could not be saved: disk full", session.error)
    }

    @Test fun editorIsBuiltWithoutANetworkClient() {
        val constructors = WritingEditorSession::class.java.declaredConstructors
        assertTrue(constructors.none { constructor -> constructor.parameterTypes.any {
            it.name.contains("AO3Client") || it.name.contains("AuthRepository") || it.name.contains("WorkForm")
        } })
        val screen = Class.forName("io.github.cidy02.kudos.writing.WritingTextEditorScreenKt")
        assertTrue(screen.declaredMethods.filter { it.name == "WritingTextEditorScreen" }.all { method ->
            method.parameterTypes.none { it.name.contains("Client") || it.name.contains("Auth") || it.name.contains("Repository") }
        })
    }
}
