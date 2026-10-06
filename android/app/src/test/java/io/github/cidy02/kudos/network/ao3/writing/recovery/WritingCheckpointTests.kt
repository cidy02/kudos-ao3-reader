package io.github.cidy02.kudos.network.ao3.writing.recovery

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS policy/scheduler test names; virtual monotonic time replaces polling real time. */
class WritingCheckpointPolicyTests {
    @Test fun checkpointsAfterTheIdleDelay() {
        val policy = WritingCheckpointPolicy()
        val start = 0L
        val lastEdit = start + 1_000
        assertEquals(lastEdit + 1_500, policy.deadline(lastEdit, start))
    }
    @Test fun continuousTypingStillCheckpointsByTheMaximumInterval() {
        val start = 0L
        assertEquals(start + 20_000, WritingCheckpointPolicy().deadline(start + 19_900, start))
    }
    @Test fun theNumbersAreTheDocumentedOnes() {
        assertEquals(1_500L, WritingCheckpointPolicy().idleDelay)
        assertEquals(20_000L, WritingCheckpointPolicy().maxInterval)
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class WritingCheckpointSchedulerTests {
    private val quick = WritingCheckpointPolicy(idleDelay = 50, maxInterval = 5_000)

    @Test fun firesOnceAfterTheIdleDelay() = runTest {
        var fired = 0
        val scheduler = WritingCheckpointScheduler(this, { testScheduler.currentTime }, quick) { fired++ }
        scheduler.noteEdit(); scheduler.noteEdit()
        assertEquals(0, fired)
        advanceTimeBy(50); runCurrent()
        assertEquals(1, fired)
        advanceTimeBy(200); runCurrent()
        assertEquals(1, fired)
        assertEquals(1, scheduler.checkpointCount)
    }
    @Test fun fireNowCheckpointsImmediatelyAndDropsThePendingTimer() = runTest {
        var fired = 0
        val scheduler = WritingCheckpointScheduler(this, { testScheduler.currentTime }, quick) { fired++ }
        scheduler.noteEdit(); scheduler.fireNow()
        assertEquals(1, fired)
        advanceTimeBy(200); runCurrent()
        assertEquals(1, fired)
    }
    @Test fun cancelStopsTheTimerWithoutCheckpointing() = runTest {
        var fired = 0
        val scheduler = WritingCheckpointScheduler(this, { testScheduler.currentTime }, quick) { fired++ }
        scheduler.noteEdit(); scheduler.cancel()
        advanceTimeBy(200); runCurrent()
        assertEquals(0, fired)
    }
    @Test fun continuousEditsStillCheckpoint() = runTest {
        var fired = 0
        val policy = WritingCheckpointPolicy(idleDelay = 200, maxInterval = 300)
        val scheduler = WritingCheckpointScheduler(this, { testScheduler.currentTime }, policy) { fired++ }
        repeat(50) { scheduler.noteEdit(); advanceTimeBy(20); runCurrent() }
        assertTrue(fired >= 1)
        scheduler.cancel()
    }

    @Test fun fireNowWithoutEditsStillIncrementsTheSequenceBeforeCallingBack() = runTest {
        val counts = mutableListOf<Int>()
        lateinit var scheduler: WritingCheckpointScheduler
        scheduler = WritingCheckpointScheduler(this, { testScheduler.currentTime }) { counts += scheduler.checkpointCount }
        scheduler.fireNow(); scheduler.fireNow()
        assertEquals(listOf(1, 2), counts)
    }
    @Test fun movingTheIdleDeadlineDoesNotCreateASecondTimer() = runTest {
        var fired = 0
        val scheduler = WritingCheckpointScheduler(this, { testScheduler.currentTime }, quick) { fired++ }
        scheduler.noteEdit(); advanceTimeBy(40)
        scheduler.noteEdit(); advanceTimeBy(10); runCurrent()
        assertEquals(0, fired)
        advanceTimeBy(40); runCurrent()
        assertEquals(1, fired)
    }
}
