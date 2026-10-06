package io.github.cidy02.kudos.network.ao3.writing.recovery

import java.io.IOException
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.attribute.FileTime
import java.time.Clock
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.random.Random
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.cancel
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class WritingRecoveryWriterTests : RecoveryDiskFixture() {
    @Test fun writesTheTextAndTheOriginalsDigest() = runBlocking {
        val store = makeStore()
        val url = sessionURL(store, "s1")
        val writer = WritingRecoveryWriter(store, url, "before")
        assertTrue(writer.write("<p>after</p>", 1))
        val entry = store.load(url)!!
        assertEquals("<p>after</p>", entry.text)
        assertEquals(WritingTextRecovery.digest("before"), entry.originalDigest)
    }

    @Test fun anOlderCheckpointNeverReplacesANewerOne() = runBlocking {
        val store = makeStore()
        val url = sessionURL(store, "s1")
        val writer = WritingRecoveryWriter(store, url, "")
        assertTrue(writer.write("newer", 2))
        assertFalse(writer.write("older", 1))
        assertEquals("newer", store.load(url)?.text)
    }

    @Test fun aFailedNewerWriteIsWhatALaterCallWrites() = runBlocking {
        val store = makeStore()
        val url = sessionURL(store, "s1")
        val writer = WritingRecoveryWriter(store, url, "")
        Files.write(store.directory, byteArrayOf())
        assertThrows(IOException::class.java) { runBlocking { writer.write("newer", 2) } }
        Files.delete(store.directory)
        assertTrue(writer.write("older", 1))
        assertEquals("newer", store.load(url)?.text)
    }

    @Test fun aCorruptCopyIsSkippedNotFatal() {
        val store = makeStore()
        store.save("good one", "", sessionURL(store, "a"))
        store.save("good two", "", sessionURL(store, "b"))
        Files.write(sessionURL(store, "c"), "{ not json".toByteArray())
        assertEquals(setOf("good one", "good two"), store.copies(key(store)).map { it.entry.text }.toSet())
    }

    @Test fun pruningKeepsTheNewestByDateWithoutReadingThem() {
        val store = makeStore()
        Files.createDirectories(store.directory)
        val urls = (0..6).map { index -> sessionURL(store, "session$index").also {
            Files.write(it, (if (index == 1) "garbage" else "{}").toByteArray())
            Files.setLastModifiedTime(it, FileTime.fromMillis(1_800_000_000_000 + index * 60_000L))
        } }
        store.prune(urls[6])
        assertEquals(urls.drop(2).toSet(), store.allCopyURLs().toSet())
    }

    @Test fun theCopyBeingWrittenAlwaysSurvives() {
        val store = makeStore()
        Files.createDirectories(store.directory)
        val urls = (0..6).map { index -> sessionURL(store, "session$index").also {
            Files.write(it, "{}".toByteArray())
            Files.setLastModifiedTime(it, FileTime.fromMillis(1_800_000_000_000 + index * 60_000L))
        } }
        store.prune(urls[0])
        assertEquals((listOf(urls[0]) + urls.drop(3)).toSet(), store.allCopyURLs().toSet())
    }

    /** Observe completed replacements from the next save's clock read, without a fake disk writer. */
    @Test fun aHundredOutOfOrderCheckpointsOnlyLandInIncreasingOrderAndTheLastWins() = runBlocking {
        val landed = mutableListOf<Int>()
        lateinit var store: WritingTextRecovery
        lateinit var url: Path
        val clock = object : Clock() {
            override fun getZone(): ZoneId = ZoneOffset.UTC
            override fun withZone(zone: ZoneId): Clock = this
            override fun instant(): Instant {
                store.load(url)?.let { landed += it.text.toInt() }
                return Instant.ofEpochSecond(1_800_000_000)
            }
        }
        store = makeStore(clock)
        url = sessionURL(store, "s1")
        val writer = WritingRecoveryWriter(store, url, "")
        val results = (1..100).shuffled(Random(3)).map { sequence ->
            async { writer.write(sequence.toString(), sequence) }
        }.awaitAll()
        landed += store.load(url)!!.text.toInt()
        assertEquals(100, results.size)
        assertTrue(results.any { it })
        assertEquals(100, landed.last())
        assertTrue(landed.zipWithNext().all { (before, after) -> before < after })
        assertEquals(setOf(url), store.allCopyURLs().toSet())
    }

    /** Cancel during an active save, with 98 writes behind it; every visible JSON stays complete. */
    @Test fun cancellationMidQueueLeavesACompleteCopyOrThePreviousOneNeverAPartialFile() = runBlocking {
        val writing = CountDownLatch(1)
        val release = CountDownLatch(1)
        var calls = 0
        val clock = object : Clock() {
            override fun getZone(): ZoneId = ZoneOffset.UTC
            override fun withZone(zone: ZoneId): Clock = this
            override fun instant(): Instant {
                calls += 1
                if (calls == 2) {
                    writing.countDown()
                    check(release.await(5, TimeUnit.SECONDS)) { "Timed out waiting to release active write" }
                }
                return Instant.ofEpochSecond(1_800_000_000 + calls.toLong())
            }
        }
        val store = makeStore(clock)
        val url = sessionURL(store, "s1")
        val writer = WritingRecoveryWriter(store, url, "original")
        writer.write("previous", 1)
        val previousBytes = Files.readAllBytes(url)
        val next = "<p>" + "日本語 &amp; 👩🏽‍💻\n".repeat(20_000) + "</p>"
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val active = scope.launch { writer.write(next, 2) }
        val jobs = mutableListOf(active)
        try {
            assertTrue(writing.await(5, TimeUnit.SECONDS))
            (3..100).forEach { sequence ->
                jobs += scope.launch(start = CoroutineStart.UNDISPATCHED) { writer.write("queued $sequence", sequence) }
            }
            assertArrayEquals(previousBytes, Files.readAllBytes(url))
            scope.cancel()
        } finally {
            scope.cancel()
            release.countDown()
            jobs.joinAll()
        }
        val entry = store.load(url)!!
        assertTrue(entry.text == "previous" || entry.text == next)
        assertEquals(WritingTextRecovery.digest("original"), entry.originalDigest)
        // Cancellation is not swallowed and no temporary file survives a completed/cancelled queue.
        assertTrue(active.isCancelled)
        Files.newDirectoryStream(store.directory).use { assertEquals(listOf(url), it.toList()) }
        val reopened = WritingTextRecovery(store.directory)
        assertEquals(entry, reopened.load(url))
    }

    @Test fun aFailedAtomicReplacementKeepsThePreviousCopyAndCleansTheTemporaryFile() {
        val store = makeStore()
        val destination = sessionURL(store, "s1")
        // A nonempty directory at the destination makes an atomic file replacement fail.
        Files.createDirectories(destination)
        val previous = destination.resolve("previous")
        Files.write(previous, "previous copy".toByteArray())
        assertThrows(IOException::class.java) { store.save("new copy", "", destination) }
        assertEquals("previous copy", String(Files.readAllBytes(previous)))
        Files.newDirectoryStream(store.directory).use { assertEquals(listOf(destination), it.toList()) }
    }
}
