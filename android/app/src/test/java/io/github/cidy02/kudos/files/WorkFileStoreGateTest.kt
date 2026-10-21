package io.github.cidy02.kudos.files

import io.github.cidy02.kudos.backup.PersistenceGate
import java.nio.file.Files
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Library file writes wait while a Replace or folder sync holds [PersistenceGate],
 * and a caller that already holds it (the Replace writing files, the launch sweep
 * deleting them) can write without deadlocking.
 */
class WorkFileStoreGateTest {
    private val workId = "11111111-1111-1111-1111-111111111111"

    @Test
    fun epubAndOriginalWritesWaitUntilTheGateIsReleased() = runBlocking {
        val root = Files.createTempDirectory("kudos-gate-wait")
        val gate = PersistenceGate()
        val store = WorkFileStore(root, gate)
        val held = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        val holder = async {
            gate.withLock {
                held.complete(Unit)
                release.await()
            }
        }
        held.await()

        val write = async {
            store.writeWorkEpub(workId, byteArrayOf(1, 2, 3))
            store.writeOriginal(workId, "txt", byteArrayOf(4, 5))
        }
        assertNull(withTimeoutOrNull(300) { write.await() })
        assertFalse(store.workEpubExists(workId))
        assertFalse(store.originalExists(workId))

        release.complete(Unit)
        withTimeout(5_000) { write.await() }
        holder.await()
        assertTrue(store.workEpubExists(workId))
        assertTrue(store.originalExists(workId))
    }

    @Test
    fun writesAndDeletesReenterWhenTheCallerAlreadyHoldsTheGate() = runBlocking {
        val root = Files.createTempDirectory("kudos-gate-reenter")
        val gate = PersistenceGate()
        val store = WorkFileStore(root, gate)
        withTimeout(5_000) {
            gate.withLock {
                assertTrue(store.writeWorkEpub(workId, byteArrayOf(1)) is FileWriteResult.Success)
                assertTrue(store.writeOriginal(workId, "txt", byteArrayOf(2)) is FileWriteResult.Success)
                assertTrue(store.writeConversionRecord(workId, byteArrayOf(3)))
                assertTrue(store.workEpubExists(workId))
                assertTrue(store.originalExists(workId))
                assertTrue(store.conversionRecordExists(workId))
                assertTrue(store.deleteWorkEpub(workId))
                assertTrue(store.deleteOriginal(workId))
            }
        }
        assertFalse(store.workEpubExists(workId))
        assertFalse(store.originalExists(workId))
    }
}
