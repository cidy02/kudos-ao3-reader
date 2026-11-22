package io.github.cidy02.kudos.backup

import java.io.BufferedWriter
import java.io.File
import java.io.OutputStream
import java.lang.management.ManagementFactory
import kotlin.random.Random

/**
 * A-567 P1 harness support (tests only; no production code is touched). JVM / Robolectric numbers:
 * labelled "JVM", never device.
 */
object A567Corpus {
    private val words = "the quiet harbor lantern winter orchard velvet midnight ember thistle compass hollow river paper".split(" ")
    private fun phrase(rnd: Random, n: Int) = (1..n).joinToString(" ") { words[rnd.nextInt(words.size)] }
    fun uuid(n: Int) = "%08x-0000-4000-8000-%012x".format(n, n)

    fun work(i: Int, rnd: Random = Random(i), hasEpub: Boolean = false) = BackupWork(
        id = uuid(i + 1),
        title = phrase(rnd, 6),
        author = phrase(rnd, 2),
        summary = phrase(rnd, 90),
        sourceURL = "https://archiveofourown.org/works/${100000 + i}",
        dateAdded = "2026-01-01T00:00:00.000Z",
        hasEPUB = hasEpub,
        rating = "Teen And Up Audiences",
        language = "English",
        wordCount = 1000 + i,
        chapters = "3/?",
        workWarnings = listOf("No Archive Warnings Apply"),
        workCategories = listOf("F/M", "Gen"),
        workTags = List(30) { "Tag ${phrase(rnd, 3)}" },
        workFandoms = List(2) { "Fandom ${phrase(rnd, 3)}" },
        workCharacters = List(8) { "Character ${phrase(rnd, 2)}" },
        workRelationships = List(5) { "A/B ${phrase(rnd, 2)}" },
        workFreeforms = List(15) { "Freeform ${phrase(rnd, 4)}" },
        userTags = List(3) { phrase(rnd, 1) }
    )

    fun session(i: Int, work: Int) = BackupReadingSession(
        id = uuid(5_000_000 + i), workID = uuid(work + 1),
        sourceURL = "https://archiveofourown.org/works/${100000 + work}", workTitle = "Title $work",
        startedAt = "2026-02-01T10:00:00.000Z", endedAt = "2026-02-01T10:30:00.000Z",
        durationSeconds = 1800.0, deviceID = uuid(7), chapterTitle = "Chapter 3",
        lastModifiedAt = "2026-02-01T10:30:00.000Z"
    )

    fun annotation(i: Int, work: Int, rnd: Random) = BackupAnnotation(
        id = uuid(9_000_000 + i), workID = uuid(work + 1),
        selectedText = phrase(rnd, 25), note = phrase(rnd, 20),
        locatorString = """{"href":"c.xhtml","locations":{"progression":0.1}}""",
        createdAt = "2026-02-01T10:30:00.000Z"
    )

    /** Rows for a unit mix of one work + 4 sessions + one annotation, as in A-566 (~6 KB per unit). */
    fun unitsFor(targetBytes: Long): Int = (targetBytes / 6000).toInt().coerceAtLeast(1)

    /** Works only (~3.5 KB each), for the store prototype where row count is the axis. */
    fun worksFor(targetBytes: Long): Int = (targetBytes / 3500).toInt().coerceAtLeast(1)

    /**
     * Streams a v8 manifest. [opaqueBytes] adds one top-level unknown string value of that many
     * bytes; [metaAfter] puts version/exportedAt after the arrays; [workOffset] shifts work ids
     * so two manifests can be disjoint (conflict copies, local vs incoming).
     */
    fun writeManifest(
        out: OutputStream,
        works: Int,
        sessionsPerWork: Int = 0,
        annotations: Int = 0,
        opaqueBytes: Long = 0,
        metaAfter: Boolean = false,
        workOffset: Int = 0,
        version: Int = 8,
        exportedAt: String = "2026-06-01T00:00:00.000Z",
        epubWorkIds: Set<Int> = emptySet()
    ) {
        val w = BufferedWriter(out.writer(Charsets.UTF_8), 1 shl 16)
        val rnd = Random(works + workOffset)
        fun array(name: String, n: Int, record: (Int) -> String, first: Boolean) {
            if (!first) w.write(",\n")
            w.write("\"$name\":[")
            for (i in 0 until n) {
                if (i > 0) w.write(",\n")
                w.write(record(i))
            }
            w.write("]")
        }
        w.write("{")
        if (!metaAfter) w.write("\"version\":$version,\"exportedAt\":\"$exportedAt\",")
        array("works", works, {
            BackupJson.encodeToString(BackupWork.serializer(), work(it + workOffset, rnd, hasEpub = (it + workOffset) in epubWorkIds))
        }, true)
        if (sessionsPerWork > 0 && works > 0) {
            array("readingSessions", works * sessionsPerWork, {
                BackupJson.encodeToString(BackupReadingSession.serializer(), session(it + workOffset, (it % works) + workOffset))
            }, false)
        }
        if (annotations > 0 && works > 0) {
            array("annotations", annotations, {
                BackupJson.encodeToString(BackupAnnotation.serializer(), annotation(it + workOffset, (it % works) + workOffset, rnd))
            }, false)
        }
        w.write(",\n\"iosFutureTopLevel\":\"kept\"")
        if (opaqueBytes > 0) {
            w.write(",\n\"iosOpaque\":\"")
            val chunk = "QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVo=".repeat(1024) // 36 KiB, JSON-safe
            var left = opaqueBytes
            while (left > 0) {
                val n = minOf(left, chunk.length.toLong()).toInt()
                w.write(chunk, 0, n)
                left -= n
            }
            w.write("\"")
        }
        if (metaAfter) w.write(",\n\"version\":$version,\"exportedAt\":\"$exportedAt\"")
        w.write("}")
        w.flush()
    }

    fun manifestBytesOfSize(targetBytes: Long, opaqueBytes: Long = 0, version: Int = 8): ByteArray {
        val rowTarget = (targetBytes - opaqueBytes).coerceAtLeast(2000)
        val units = unitsFor(rowTarget)
        return java.io.ByteArrayOutputStream().also {
            writeManifest(it, works = units, sessionsPerWork = 4, annotations = units, opaqueBytes = opaqueBytes, version = version)
        }.toByteArray()
    }

    fun manifestFileOfSize(file: File, targetBytes: Long, opaqueBytes: Long = 0) {
        val rowTarget = (targetBytes - opaqueBytes).coerceAtLeast(2000)
        val units = unitsFor(rowTarget)
        file.outputStream().use {
            writeManifest(it, works = units, sessionsPerWork = 4, annotations = units, opaqueBytes = opaqueBytes)
        }
    }
}

/** Heap sampler + disk high-water + stage timer around one measured run. */
class A567Run(private val diskRoots: List<File>) {
    class Result(
        val wallMs: Long,
        val peakHeapMiB: Double,
        val retainedMiB: Double,
        val diskHighMiB: Double,
        val stages: Map<String, Long>,
        val outcome: String
    )

    val stages = linkedMapOf<String, Long>()

    inline fun <T> stage(name: String, body: () -> T): T {
        val t0 = System.nanoTime()
        try {
            return body()
        } finally {
            stages[name] = (stages[name] ?: 0L) + (System.nanoTime() - t0) / 1_000_000
        }
    }

    fun measure(body: () -> String): Result {
        val baseline = settledHeap()
        val peakA = java.util.concurrent.atomic.AtomicLong(baseline)
        val diskA = java.util.concurrent.atomic.AtomicLong(0)
        val stopA = java.util.concurrent.atomic.AtomicBoolean(false)
        val sampler = Thread {
            var tick = 0
            while (!stopA.get()) {
                peakA.accumulateAndGet(usedHeap(), ::maxOf)
                if (tick++ % 10 == 0) diskA.accumulateAndGet(diskBytes(), ::maxOf)
                Thread.sleep(2)
            }
        }.apply { isDaemon = true; start() }
        val t0 = System.nanoTime()
        val outcome = try {
            body()
        } catch (t: Throwable) {
            "${t::class.simpleName}: ${t.message?.take(80)}"
        }
        val wall = (System.nanoTime() - t0) / 1_000_000
        stopA.set(true)
        sampler.join()
        val after = settledHeap()
        diskA.accumulateAndGet(diskBytes(), ::maxOf)
        return Result(wall, mib(peakA.get() - baseline), mib(after - baseline), mib(diskA.get()), stages.toMap(), outcome)
    }

    private fun diskBytes(): Long = diskRoots.sumOf { root ->
        if (!root.exists()) 0L else root.walkTopDown().filter { it.isFile }.sumOf { it.length() }
    }

    companion object {
        fun usedHeap(): Long = Runtime.getRuntime().let { it.totalMemory() - it.freeMemory() }
        fun settledHeap(): Long {
            repeat(3) { System.gc() }
            return usedHeap()
        }
        fun mib(bytes: Long) = bytes / 1048576.0
        fun heapMaxMiB() = ManagementFactory.getMemoryMXBean().heapMemoryUsage.max / 1048576
        fun median(values: List<Double>): Double = values.sorted().let { it[it.size / 2] }
        fun medianL(values: List<Long>): Long = values.sorted().let { it[it.size / 2] }
    }
}
