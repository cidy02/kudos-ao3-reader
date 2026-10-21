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

    @Test fun playerAndMediaSessionDispatchTheSameChapterActions() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val controller = ReaderSpeechController(context, tts = Engine())
        val calls = mutableListOf<String>()
        try {
            controller.onSkipNext = { calls += "next chapter" }
            controller.onSkipPrevious = { calls += "previous chapter" }
            controller.skipForward()
            controller.skipBackward()
            val session = org.robolectric.util.ReflectionHelpers.getField<android.media.session.MediaSession>(
                controller, "mediaSession"
            )
            val handler = org.robolectric.util.ReflectionHelpers.getField<Any>(session, "mCallback")
            val remote = org.robolectric.util.ReflectionHelpers.getField<android.media.session.MediaSession.Callback>(
                handler, "mCallback"
            )
            remote.onSkipToNext()
            remote.onSkipToPrevious()
            assertEquals(listOf("next chapter", "previous chapter", "next chapter", "previous chapter"), calls)
        } finally {
            controller.shutdown()
        }
    }

    @Test fun chapterTapDuringAPullReplacesTheOldSourceAndCannotSpeakItsLateParagraph() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val engine = Engine()
        val controller = ReaderSpeechController(context, tts = engine)
        val pulling = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        val ioPool = java.util.concurrent.Executors.newSingleThreadExecutor()
        val io = ioPool.asCoroutineDispatcher()
        val source = ReaderSpeechSource {
            withContext(io) {
                pulling.complete(Unit)
                release.await()
                "Late paragraph from the old chapter."
            }
        }
        try {
            controller.onSkipNext = {
                controller.beginSeeking()
                controller.endSeeking(ReaderSpeechSource { "New chapter start." })
            }
            controller.startReading(source)
            runCurrent()
            pulling.await()
            controller.skipForward()
            assertEquals("New chapter start.", engine.calls.receive().text)
            release.complete(Unit)
            runCurrent()
            assertTrue(engine.calls.tryReceive().isFailure)
        } finally {
            release.complete(Unit)
            controller.shutdown()
            ioPool.shutdown()
            ioPool.awaitTermination(5, java.util.concurrent.TimeUnit.SECONDS)
            advanceUntilIdle()
        }
    }

    @Test fun lateOldChapterPullCannotClearTheNewPullsPauseGuard() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val engine = Engine()
        val controller = ReaderSpeechController(context, tts = engine)
        val oldRelease = CompletableDeferred<Unit>()
        val newRelease = CompletableDeferred<Unit>()
        try {
            controller.startReading(ReaderSpeechSource {
                // Models file IO that cannot return to Main immediately on cancellation.
                withContext(kotlinx.coroutines.NonCancellable) { oldRelease.await(); "Old chapter." }
            })
            runCurrent()
            controller.onSkipNext = {
                controller.beginSeeking()
                controller.endSeeking(ReaderSpeechSource { newRelease.await(); "New chapter." })
            }
            controller.skipForward()
            runCurrent()
            oldRelease.complete(Unit)
            runCurrent()
            controller.pause()
            newRelease.complete(Unit)
            runCurrent()
            assertEquals(SpeechStatus.PAUSED, controller.status.value)
            assertTrue(engine.calls.tryReceive().isFailure)
            controller.resume()
            assertEquals("New chapter.", engine.calls.receive().text)
        } finally {
            oldRelease.complete(Unit)
            newRelease.complete(Unit)
            controller.shutdown()
            runCurrent()
        }
    }

    @Test fun lateOldChapterEndCannotStopTheNewChapterPull() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val engine = Engine()
        val controller = ReaderSpeechController(context, tts = engine)
        val oldRelease = CompletableDeferred<Unit>()
        val newRelease = CompletableDeferred<Unit>()
        try {
            controller.startReading(ReaderSpeechSource {
                withContext(kotlinx.coroutines.NonCancellable) { oldRelease.await(); null }
            })
            runCurrent()
            controller.onSkipNext = {
                controller.beginSeeking()
                controller.endSeeking(ReaderSpeechSource { newRelease.await(); "New chapter." })
            }
            controller.skipForward()
            runCurrent()
            oldRelease.complete(Unit)
            runCurrent()
            assertEquals(SpeechStatus.PLAYING, controller.status.value)
            assertTrue(engine.calls.tryReceive().isFailure)
            newRelease.complete(Unit)
            assertEquals("New chapter.", engine.calls.receive().text)
            assertEquals(SpeechStatus.PLAYING, controller.status.value)
        } finally {
            oldRelease.complete(Unit)
            newRelease.complete(Unit)
            controller.shutdown()
            runCurrent()
        }
    }

    @Test fun chapterTapWhilePausedWaitsForPlayAtTheNewChapter() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val engine = Engine()
        val controller = ReaderSpeechController(context, tts = engine)
        var pulls = 0
        try {
            controller.onSkipPrevious = {
                controller.beginSeeking()
                controller.endSeeking(ReaderSpeechSource { pulls++; "Previous chapter start." })
            }
            controller.startReading(listOf("Current chapter."))
            engine.calls.receive()
            controller.pause()
            controller.skipBackward()
            runCurrent()
            assertEquals(SpeechStatus.PAUSED, controller.status.value)
            assertEquals(0, pulls)
            assertTrue(engine.calls.tryReceive().isFailure)
            controller.resume()
            assertEquals("Previous chapter start.", engine.calls.receive().text)
        } finally {
            controller.shutdown()
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
