package io.github.cidy02.kudos.works.detail

import io.github.cidy02.kudos.app.ReaderLaunchRequest
import io.github.cidy02.kudos.ui.components.ChapterBarGeometry
import io.github.cidy02.kudos.ui.components.ChapterBarModel
import io.github.cidy02.kudos.ui.components.ChapterBarRole
import io.github.cidy02.kudos.works.launchReaderAfterRefresh
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withContext
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WorkDetailResumeTest {
    @Test
    fun chapterBarGeometryProducesReadCurrentPostedAndUnpostedRoles() {
        val items = ChapterBarGeometry.items(
            planned = 5,
            posted = 4,
            progress = 0.5,
            weights = listOf(10.0, 10.0, 20.0, 10.0)
        )
        assertEquals(5, items.size)
        assertEquals(ChapterBarRole.Read, items[0].role)
        assertEquals(ChapterBarRole.Read, items[1].role)
        val current = items[2].role as ChapterBarRole.Current
        assertEquals(0.25, current.fill, 0.001)
        assertEquals(ChapterBarRole.PostedUnread, items[3].role)
        assertEquals(ChapterBarRole.NotPosted, items[4].role)
    }

    @Test
    fun chapterBarModelHandlesQuestionMarkPlannedCount() {
        val items = ChapterBarModel.items(
            chapters = "4/?",
            progress = 0.25,
            weights = null
        )
        assertEquals(4, items.size)
        assertEquals(ChapterBarRole.Read, items[0].role)
        assertEquals(ChapterBarRole.PostedUnread, items[1].role)
    }

    @Test fun extremeChapterMetadataProducesBoundedBarsAndKeepsExactSpokenCounts() {
        val model = ResumeCardModel("T", emptyList(), "4/2147483647", 0.5, null, null, 0)
        assertEquals(128, model.chapterItems(null).size)
        assertTrue(model.chapterBarsLabel!!.contains("4 of 2147483647 chapters posted"))
    }

    @Test fun chapterBarsLabelHandlesUnknownTotalsRoundingAndUnpostedOrNewCounts() {
        val unknownTotal = ResumeCardModel("T", emptyList(), "200/?", 0.506, null, null, 0)
        assertEquals(
            "51 percent read, 200 chapters posted, total not set by the author",
            unknownTotal.chapterBarsLabel
        )
        val withUnpostedAndNew = ResumeCardModel("T", emptyList(), "150/200", null, null, null, 3)
        assertEquals(
            "150 of 200 chapters posted, 50 not posted yet, 3 new",
            withUnpostedAndNew.chapterBarsLabel
        )
    }

    @Test fun postedShortLabelUsesQuestionMarkForUnknownTotal() {
        assertEquals("4 of ?", ResumeCardModel("T", emptyList(), "4/?", null, null, null, 0).postedShortLabel)
        assertEquals("10 of 12", ResumeCardModel("T", emptyList(), "10/12", null, null, null, 0).postedShortLabel)
    }

    @Test
    fun workReadingPositionExtractsChapterProgressFromEnvelopeAndRawJson() {
        val raw = """{"href":"ch3.xhtml","locations":{"progression":0.42,"totalProgression":0.6}}"""
        val wrapped = """{"workId":"w1","locator":{"href":"ch3.xhtml","locations":{"progression":0.85}}}"""
        assertEquals(0.42, WorkReadingPosition.chapterProgress(raw)!!, 0.001)
        assertEquals(0.85, WorkReadingPosition.chapterProgress(wrapped)!!, 0.001)
        assertNull(WorkReadingPosition.chapterProgress(null))
        assertNull(WorkReadingPosition.chapterProgress("not json"))
        assertEquals(1, WorkReadingPosition.positionsForEntryLength(500))
        assertEquals(2, WorkReadingPosition.positionsForEntryLength(1025))
    }

    @Test
    fun resumeCardModelFormatsDetailChapterNameProgressLineAndPrimaryTitle() {
        val model = ResumeCardModel(
            title = "Salt & Copper",
            fandoms = listOf("Fandom A"),
            chapters = "10/12",
            rawProgress = 0.52,
            rawChapterProgress = 0.37,
            chapterName = "Chapter 7: The Salt Road",
            newChapterCount = 2
        )
        assertEquals("Ch 7, The Salt Road", model.detailChapterName)
        assertEquals("37% of the chapter · 52% of the work", model.detailProgressLine)
        assertEquals("Resume Chapter 7", model.detailPrimaryTitle("Read"))
        assertEquals(7, model.chapterNumber)
        assertEquals("2 new chapters", model.updateChapterValue)

        val noChapterProg = model.copy(rawChapterProgress = null, chapterName = "Afterword")
        assertEquals("52% of the work", noChapterProg.detailProgressLine)
        assertEquals("Afterword", noChapterProg.detailChapterName)

        val unread = model.copy(rawProgress = null, rawChapterProgress = null, chapterName = null)
        assertNull(unread.detailProgressLine)
        assertEquals("Read", unread.detailPrimaryTitle("Read"))
        assertEquals("Not started", unread.detailChapterName)
    }

    @Test
    fun chapterLengthCacheRejectsStaleTimestampOrByteCount() {
        val record = ChapterLengthCache.Record(
            byteCount = 4200L,
            modifiedAtMillis = 123456L,
            weights = listOf(10, 20)
        )
        assertEquals(listOf(10, 20), ChapterLengthCache.keptWeights(record, 4200L, 123456L))
        assertNull(ChapterLengthCache.keptWeights(record, 4201L, 123456L))
        assertNull(ChapterLengthCache.keptWeights(record, 4200L, 123457L))
    }

    @Test
    fun readerLaunchRequestIsOneShotPerWorkId() {
        ReaderLaunchRequest.request("work-1", openContents = true)
        assertNotNull(ReaderLaunchRequest.peek("work-1"))
        assertNull(ReaderLaunchRequest.consume("work-2"))
        val consumed = ReaderLaunchRequest.consume("work-1")
        assertNotNull(consumed)
        assertTrue(consumed!!.openContents)
        assertFalse(consumed.startReadAloud)
        assertNull(ReaderLaunchRequest.consume("work-1"))
    }

    @Test fun readAloudLaunchWaitsForSpeechReadinessThenStartsOnlyOnce() {
        class FakeSpeechController {
            var ready = false
            var starts = 0
            fun receive() {
                ReaderLaunchRequest.consumeWhenReady("work-speech", ready)?.let {
                    if (it.startReadAloud) starts++
                }
            }
        }
        val speech = FakeSpeechController()
        ReaderLaunchRequest.request("work-speech", startReadAloud = true)
        speech.receive()
        assertNotNull(ReaderLaunchRequest.peek("work-speech"))
        speech.ready = true
        speech.receive()
        speech.receive()
        assertEquals(1, speech.starts)
        assertNull(ReaderLaunchRequest.peek("work-speech"))
    }

    @Test fun cancellingRefreshBeforeNavigationNeverArmsReaderLaunch() = runTest {
        val entered = CompletableDeferred<Unit>()
        val finishRefresh = CompletableDeferred<Unit>()
        var navigations = 0
        val launch = launch {
            launchReaderAfterRefresh("work-cancel", true, true,
                refresh = { entered.complete(Unit); withContext(NonCancellable) { finishRefresh.await() } },
                onOpenReader = { navigations++; true })
        }
        entered.await()
        assertNull(ReaderLaunchRequest.peek("work-cancel"))
        launch.cancel()
        finishRefresh.complete(Unit)
        launch.join()
        assertNull(ReaderLaunchRequest.peek("work-cancel"))
        assertEquals(0, navigations)
    }

    @Test fun canLaunchFalseAfterRefreshNeverArmsOrOpensReader() = runTest {
        var navigations = 0
        launchReaderAfterRefresh(
            "work-disposed",
            openContents = true,
            startReadAloud = true,
            refresh = {},
            canLaunch = { false },
            onOpenReader = { navigations++; true }
        )
        assertNull(ReaderLaunchRequest.peek("work-disposed"))
        assertEquals(0, navigations)
    }

    @Test fun failedPopNavigationReturningFalseClearsArmedRequest() = runTest {
        var attempts = 0
        launchReaderAfterRefresh(
            "work-pop-failed",
            openContents = false,
            startReadAloud = true,
            refresh = {},
            canLaunch = { true },
            onOpenReader = { attempts++; false }
        )
        assertEquals(1, attempts)
        assertNull(ReaderLaunchRequest.peek("work-pop-failed"))
    }

    @Test fun failedReaderNavigationClearsItsLaunch() = runTest {
        try {
            launchReaderAfterRefresh("work-failed", false, true,
                refresh = {}, onOpenReader = { throw IllegalStateException("navigation failed") })
            throw AssertionError("Navigation should fail")
        } catch (error: IllegalStateException) {
            assertEquals("navigation failed", error.message)
        }
        assertNull(ReaderLaunchRequest.peek("work-failed"))
    }

    @Test fun closingOlderReaderDoesNotClearReplacementRequest() {
        ReaderLaunchRequest.request("work-a", startReadAloud = true)
        val tokenA = ReaderLaunchRequest.tokenFor("work-a")!!
        ReaderLaunchRequest.request("work-b", openContents = true)
        ReaderLaunchRequest.clearIfMatches("work-a", tokenA)
        assertTrue(ReaderLaunchRequest.consume("work-b")!!.openContents)

        ReaderLaunchRequest.request("work-a", startReadAloud = true)
        val olderToken = ReaderLaunchRequest.tokenFor("work-a")!!
        ReaderLaunchRequest.request("work-a", openContents = true)
        ReaderLaunchRequest.clearIfMatches("work-a", olderToken)
        assertTrue(ReaderLaunchRequest.consume("work-a")!!.openContents)
    }
}
