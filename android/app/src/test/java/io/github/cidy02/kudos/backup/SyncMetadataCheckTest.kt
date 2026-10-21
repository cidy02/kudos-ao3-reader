package io.github.cidy02.kudos.backup

import java.time.Instant
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

class SyncMetadataCheckTest {
    @Test fun failedPreparationCanBeRetriedAndOnlySuccessSaysReady() = runTest {
        var fail = true
        var time = Instant.parse("2026-10-21T12:00:00Z")
        val check = SyncMetadataCheck(now = { time }) { if (fail) error("Unreadable metadata") }
        assertEquals("Not Started", check.status.value.title)
        check.run()
        assertEquals("Needs Retry", check.status.value.title)
        assertEquals("Retry Metadata Prep", check.status.value.action)
        assertEquals("Unreadable metadata", check.status.value.error)
        assertEquals(time, check.status.value.lastChecked)
        fail = false
        time = time.plusSeconds(60)
        check.run()
        assertEquals("Ready", check.status.value.title)
        assertEquals("Check Metadata", check.status.value.action)
        assertEquals(time, check.status.value.lastChecked)
        assertNull(check.status.value.error)
    }

    @Test fun repeatedTapsDoNotOverlapAndCancellationAllowsAnotherCheck() = runTest {
        val started = CompletableDeferred<Unit>()
        val finish = CompletableDeferred<Unit>()
        var calls = 0
        val check = SyncMetadataCheck {
            calls++
            started.complete(Unit)
            finish.await()
        }
        val first = launch { check.run() }
        started.await()
        assertEquals("Preparing", check.status.value.title)
        check.run()
        assertEquals(1, calls)
        first.cancelAndJoin()
        assertEquals("Not Started", check.status.value.title)
        assertNull(check.status.value.lastChecked)
        assertFalse(check.status.value.checking)
        finish.complete(Unit)
        check.run()
        assertEquals(2, calls)
        assertEquals("Ready", check.status.value.title)
    }
}
