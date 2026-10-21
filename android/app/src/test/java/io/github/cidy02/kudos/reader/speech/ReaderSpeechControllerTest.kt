package io.github.cidy02.kudos.reader.speech

import android.app.Application
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.work.Configuration
import androidx.work.WorkManager
import io.github.cidy02.kudos.reader.ReaderSpeechSource
import kotlin.coroutines.ContinuationInterceptor
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.withContext
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
@OptIn(ExperimentalCoroutinesApi::class)
class ReaderSpeechControllerTest {
    private lateinit var context: Context

    @Before fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        try {
            WorkManager.getInstance(context)
        } catch (_: IllegalStateException) {
            WorkManager.initialize(context, Configuration.Builder().build())
        }
    }

    @After fun tearDown() = Dispatchers.resetMain()

    @Test fun enginePreparationRunsOffMain() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val engine = Engine()
        val controller = ReaderSpeechController(context, tts = engine)
        try {
            controller.startReading(listOf("Freshly downloaded pack."))
            val call = engine.calls.receive()
            assertSame(Dispatchers.Default, call.dispatcher)
        } finally {
            controller.shutdown()
        }
    }

    @Test fun nextDuringAnIoPullRetainsTheTakenParagraphAndItsQueueIndex() = runTest {
        skipDuringPull(listOf(1), "P2")
    }

    @Test fun previousDuringAnIoPullRetainsTheTakenParagraph() = runTest {
        skipDuringPull(listOf(-1), "P0")
    }

    @Test fun repeatedSkipsDuringOnePullRetainEveryParagraph() = runTest {
        skipDuringPull(listOf(1, 1, -1), "P2")
    }

    private suspend fun TestScope.skipDuringPull(skips: List<Int>, expected: String) {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val engine = Engine()
        val controller = ReaderSpeechController(context, tts = engine)
        val pulling = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        var index = 0
        // Its own IO thread, stopped before tearDown resets Main: a pull still returning to Main
        // from Dispatchers.IO raced the reset ("Dispatchers.Main is used concurrently").
        val ioPool = java.util.concurrent.Executors.newSingleThreadExecutor()
        val io = ioPool.asCoroutineDispatcher()
        val source = ReaderSpeechSource {
            withContext(io) {
                val taken = index++
                if (taken == 1) {
                    // Like Readium: advance the iterator before an IO result returns to Main.
                    pulling.complete(Unit)
                    release.await()
                }
                if (taken < 4) "P$taken" else null
            }
        }
        try {
            controller.startReading(source)
            assertEquals("P0", engine.calls.receive().also { it.done.complete(Unit) }.text)
            pulling.await()
            skips.forEach { if (it > 0) controller.skipForward() else controller.skipBackward() }
            runCurrent()
            release.complete(Unit)
            assertEquals(expected, engine.calls.receive().text)
            if (expected == "P2") {
                controller.skipBackward()
                assertEquals("P1", engine.calls.receive().text)
                controller.skipForward()
                assertEquals("P2", engine.calls.receive().also { it.done.complete(Unit) }.text)
            } else {
                engine.finish()
                assertEquals("P1", engine.calls.receive().also { it.done.complete(Unit) }.text)
                assertEquals("P2", engine.calls.receive().also { it.done.complete(Unit) }.text)
            }
            assertEquals("P3", engine.calls.receive().text)
        } finally {
            release.complete(Unit)
            controller.shutdown()
            ioPool.shutdown()
            ioPool.awaitTermination(5, java.util.concurrent.TimeUnit.SECONDS)
            advanceUntilIdle()
        }
    }

    @Test fun holdReleaseReanchorsPlayingSpeechAtTheNewSource() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val engine = Engine()
        val controller = ReaderSpeechController(context, tts = engine)
        try {
            controller.startReading(listOf("Old locator.", "Old queue."))
            assertEquals("Old locator.", engine.calls.receive().text)
            controller.beginSeeking()
            controller.endSeeking(ReaderSpeechSource { "New locator." })
            assertEquals("New locator.", engine.calls.receive().text)
            assertEquals(SpeechStatus.PLAYING, controller.status.value)
        } finally {
            controller.shutdown()
        }
    }

    @Test fun holdReleaseKeepsPausedSpeechPausedUntilPlayAtTheNewSource() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val engine = Engine()
        val controller = ReaderSpeechController(context, tts = engine)
        var pulls = 0
        try {
            controller.startReading(listOf("Old locator.", "Old queue."))
            engine.calls.receive()
            controller.pause()
            controller.beginSeeking()
            controller.endSeeking(ReaderSpeechSource { pulls++; "New paused locator." })
            runCurrent()
            assertEquals(SpeechStatus.PAUSED, controller.status.value)
            assertEquals(0, pulls)
            assertTrue(engine.calls.tryReceive().isFailure)
            controller.resume()
            assertEquals("New paused locator.", engine.calls.receive().text)
            assertEquals(1, pulls)
        } finally {
            controller.shutdown()
        }
    }

    private data class Call(
        val text: String,
        val done: CompletableDeferred<Unit>,
        val dispatcher: ContinuationInterceptor?
    )

    private class Engine : TTSService {
        override val status = MutableStateFlow(SpeechStatus.STOPPED)
        override val spokenText = MutableStateFlow("")
        override val availableVoices = MutableStateFlow(emptyList<TTSVoice>())
        val calls = Channel<Call>(Channel.UNLIMITED)
        @Volatile private var active: CompletableDeferred<Unit>? = null

        override suspend fun speak(text: String) {
            val done = CompletableDeferred<Unit>()
            active = done
            status.value = SpeechStatus.PLAYING
            spokenText.value = text
            try {
                calls.send(Call(text, done, coroutineContext[ContinuationInterceptor]))
                done.await()
            } finally {
                if (active === done) status.value = SpeechStatus.STOPPED
            }
        }

        fun finish() { active?.complete(Unit) }
        override fun stop() { finish(); status.value = SpeechStatus.STOPPED }
        override fun pause() { status.value = SpeechStatus.PAUSED }
        override fun resume() { status.value = SpeechStatus.PLAYING }
        override fun setVoice(id: String) = Unit
        override fun setRate(rate: Float) = Unit
        override fun setPitch(pitch: Float) = Unit
    }
}
