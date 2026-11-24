package io.github.cidy02.kudos.backup.streaming

import io.github.cidy02.kudos.backup.A567Corpus
import io.github.cidy02.kudos.backup.A567Run
import io.github.cidy02.kudos.backup.BackupJson
import io.github.cidy02.kudos.backup.BackupWork
import java.io.File
import java.nio.file.Files
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Opt-in (A567_P2_OUT=<file>; A567_P2_SIZES=8,32,128,256,512 in MiB; run with A567_TEST_HEAP=256m): staging at
 * P1's feasibility thresholds, JVM under Robolectric (labelled so; not a device). "Live delta" is heap after GC
 * at every few commits minus the settled baseline; "peak" is a 2 ms sampler and includes garbage. Native SQLite
 * memory is outside the Java heap and is not measured here.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ManifestStagingLargeTest {
    private class Row(val label: String, val wallMs: Long, val peakMiB: Double, val liveMiB: Double, val dbMiB: Double, val diskMiB: Double, val retainedMiB: Double, val detail: String)

    private fun measureOnce(label: String, file: File, root: File, expect: (StagedManifest) -> String): Row {
        val baseline = A567Run.settledHeap()
        var live = 0L
        var commits = 0
        var dbBytes = 0L
        var detail = ""
        val result = A567Run(listOf(root)).measure {
            val options = ManifestStageOptions(expectedBytes = file.length(), checkpoint = {
                if (commits++ % 4 == 0) live = maxOf(live, A567Run.settledHeap() - baseline)
            })
            file.inputStream().buffered(1 shl 16).use { input ->
                ManifestStager.stage(input, root, options).use { staged ->
                    dbBytes = staged.stagedBytes()
                    detail = expect(staged)
                }
            }
            "ok"
        }
        assertEquals("staging left files behind", emptyList<String>(), root.list()?.toList().orEmpty())
        assertEquals(label, "ok", result.outcome)
        return Row(label, result.wallMs, result.peakHeapMiB, A567Run.mib(live), A567Run.mib(dbBytes), result.diskHighMiB, result.retainedMiB, detail)
    }

    private fun median(label: String, runs: Int, file: File, root: File, expect: (StagedManifest) -> String): Row {
        val rows = (1..runs).map { measureOnce(label, file, root, expect) }
        val m = rows.sortedBy { it.wallMs }[rows.size / 2]
        return Row(label, m.wallMs, A567Run.median(rows.map { it.peakMiB }), A567Run.median(rows.map { it.liveMiB }), m.dbMiB, A567Run.median(rows.map { it.diskMiB }), A567Run.median(rows.map { it.retainedMiB }), m.detail)
    }

    private fun worksCheck(staged: StagedManifest): String {
        val n = staged.count("works")
        listOf(0L, n / 2, n - 1).forEach { BackupJson.decodeFromString(BackupWork.serializer(), staged.recordTextInMemory("works", it)) }
        return "works=$n sessions=${staged.count("readingSessions")} annotations=${staged.count("annotations")}"
    }

    /** Opt-in three real near-8 MiB strict rows, both flat and 160k-tag-heavy. JVM heap excludes native SQLite. */
    @Test
    fun threeNearBudgetRecordsPeak() {
        val out = System.getenv("A567_P2_OUT")
        assumeTrue("opt-in", out != null)
        val dir = Files.createTempDirectory("a567p2-three").toFile()
        val root = File(dir, "staging")
        val target = StagingSink.TYPED_BUDGET_BYTES.toInt() - 4096
        val now = Instant.parse("2026-06-15T00:00:00Z")
        val report = StringBuilder("\nThree near-8 MiB strict records (Robolectric JVM, sampled heap; native SQLite excluded):\n")
        try {
            for (structured in listOf(false, true)) {
                val label = if (structured) "160000 tags" else "flat summary"
                val tags = if (structured) (0 until 160_000).joinToString(",") { "\"tag-$it\"" } else ""
                val suffix = if (structured) "\",\"workTags\":[$tags]}" else "\"}"
                val file = File(dir, if (structured) "structured.json" else "flat.json")
                file.bufferedWriter().use { w ->
                    w.write("{\"version\":8,\"exportedAt\":\"2026-06-01T00:00:00Z\",\"works\":[")
                    for (id in 1..3) {
                        if (id > 1) w.write(",")
                        val prefix = "{\"id\":\"${A567Corpus.uuid(id)}\",\"summary\":\""
                        w.write(prefix)
                        var remaining = target - prefix.length - suffix.length
                        assertTrue("record exceeds typed budget", remaining > 0)
                        val pad = "a".repeat(8192)
                        while (remaining >= pad.length) { w.write(pad); remaining -= pad.length }
                        w.write(pad.substring(0, remaining))
                        w.write(suffix)
                    }
                    w.write("]}")
                }
                val results = (0..3).map { run ->
                    val batches = mutableListOf<Pair<Int, Long>>()
                    val result = A567Run(listOf(root)).measure {
                        file.inputStream().buffered(1 shl 16).use { input ->
                            ManifestStager.stage(input, root, ManifestStageOptions(expectedBytes = file.length())).use { staged ->
                                assertEquals(3L, staged.count("works"))
                                assertTrue(staged.records("works").all { it.sourceBytes in 7_900_000L..StagingSink.TYPED_BUDGET_BYTES })
                                staged.validate(now) { count, bytes -> batches += count to bytes }
                            }
                        }
                        "ok"
                    }
                    assertEquals("$label run $run", "ok", result.outcome)
                    assertEquals(listOf(2, 1), batches.map { it.first })
                    assertTrue("$label run $run left staging files", root.list()?.isEmpty() != false)
                    result
                }.drop(1) // first is warm-up
                val peak = A567Run.median(results.map { it.peakHeapMiB })
                val retained = A567Run.median(results.map { it.retainedMiB })
                report.append("$label: median sampled peak ${"%.1f".format(peak)} MiB; retained ${"%.1f".format(retained)} MiB; input ${file.length()} bytes\n")
                println("A567P2 three-record $label peak ${"%.1f".format(peak)} MiB")
                assertTrue("$label peak $peak MiB exceeds 64 MiB", peak <= 64.0)
            }
            File(out!!).appendText(report.toString())
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun scaling() {
        val out = System.getenv("A567_P2_OUT")
        assumeTrue("opt-in", out != null)
        val sizes = (System.getenv("A567_P2_SIZES") ?: "8,32,128,256,512").split(",").map { it.trim().toLong() }
        val dir = Files.createTempDirectory("a567p2").toFile()
        val root = File(dir, "staging")
        val rows = mutableListOf<Row>()
        val t = StringBuilder("| axis / input | wall ms | heap peak MiB (sampled, upper bound) | max live delta MiB (after GC, during run) | staging DB MiB | temp disk high-water MiB | retained after close MiB | detail |\n|---|---|---|---|---|---|---|---|\n")
        fun add(r: Row) {
            rows += r
            t.append("| ${r.label} | ${r.wallMs} | ${"%.1f".format(r.peakMiB)} | ${"%.1f".format(r.liveMiB)} | ${"%.1f".format(r.dbMiB)} | ${"%.1f".format(r.diskMiB)} | ${"%.1f".format(r.retainedMiB)} | ${r.detail} |\n")
            println("A567P2 ${t.lines().dropLast(1).last()}")
        }
        val warm = File(dir, "warm.json").also { A567Corpus.manifestFileOfSize(it, 4L shl 20) }
        measureOnce("warm-up", warm, root, ::worksCheck); warm.delete()
        val byMib = linkedMapOf<Long, Row>()
        for (mib in sizes) {
            val f = File(dir, "m$mib.json").also { A567Corpus.manifestFileOfSize(it, mib shl 20) }
            val row = median("rows $mib MiB", if (mib == 128L || mib == 512L) 3 else 1, f, root, ::worksCheck)
            add(row); byMib[mib] = row
            assertTrue("$mib MiB staging DB ${row.dbMiB} MiB over budget", row.dbMiB <= mib * DB_BUDGET + 32)
            f.delete()
        }
        for (mib in listOf(20L, 96L, 256L).filter { it <= (sizes.max()) }) {
            val f = File(dir, "o$mib.json").also { A567Corpus.manifestFileOfSize(it, (mib + 1) shl 20, opaqueBytes = mib shl 20) }
            add(median("one opaque top-level value $mib MiB", 1, f, root) { s ->
                val e = s.rootEntries().first { it.key == "iosOpaque" }
                assertTrue(e.oversize); assertEquals((mib shl 20) + 2, e.chars)
                "works=${s.count("works")} oversize chars=${e.chars}"
            })
            f.delete()
        }
        for (tags in listOf(180_000, 500_000, 2_000_000)) {
            val f = File(dir, "n$tags.json")
            f.bufferedWriter().use { w ->
                w.write("{\"version\":8,\"exportedAt\":\"2026-06-01T00:00:00.000Z\",\"works\":[{\"id\":\"${A567Corpus.uuid(1)}\",\"title\":\"big\",\"dateAdded\":\"2026-01-01T00:00:00.000Z\",\"workTags\":[")
                for (i in 0 until tags) { if (i > 0) w.write(","); w.write("\"tag number $i of the growing nested array\"") }
                w.write("]}]}")
            }
            if (f.length() > StagingSink.TYPED_BUDGET_BYTES) {
                // over the 8 MiB typed budget: resource exhaustion after EOF, nothing left behind
                try { f.inputStream().buffered(1 shl 16).use { ManifestStager.stage(it, root).close() }; error("accepted") } catch (e: ManifestStageException.ResourceExhausted) { /* expected */ }
                assertEquals(emptyList<String>(), root.list()?.toList().orEmpty())
                t.append("| one work with $tags tags (${f.length() shr 20} MiB) | over the typed budget: ResourceExhausted, nothing left | | | | | | |\n")
            } else {
                val row = median("one work with $tags tags (${f.length() shr 20} MiB, accepted strict record)", 1, f, root) { s ->
                    s.db.rawQuery("SELECT oversize, typed_ok, chars FROM s_works", null).use { c -> c.moveToFirst(); assertEquals(1, c.getInt(0)); assertEquals(1, c.getInt(1)); "oversize record chars=${c.getLong(2)}, decoded under the budget" }
                }
                add(row)
                assertTrue("largest accepted strict record peaked ${row.peakMiB} MiB over baseline", row.peakMiB <= 64)
            }
            f.delete()
        }
        // cancellation latency during staging of the largest run that fits the budget
        val cancelMib = if (128L in sizes) 128L else sizes.max()
        val big = File(dir, "cancel.json").also { A567Corpus.manifestFileOfSize(it, cancelMib shl 20) }
        val start = System.nanoTime()
        val flagAt = start + 50_000_000L
        var seen = 0L
        try {
            big.inputStream().buffered(1 shl 16).use { ManifestStager.stage(it, root, ManifestStageOptions(isCancelled = { (System.nanoTime() >= flagAt).also { hit -> if (hit && seen == 0L) seen = System.nanoTime() } })).close() }
            error("not cancelled")
        } catch (e: ManifestStageException.Cancelled) {
            val latencyMs = (System.nanoTime() - seen) / 1_000_000
            t.append("\nCancellation during staging of $cancelMib MiB: flag set 50 ms in, quiescent (directory deleted) ${latencyMs} ms after the first poll that saw it.\n")
            assertTrue("cancellation latency $latencyMs ms", latencyMs < 1000)
        }
        assertEquals(emptyList<String>(), root.list()?.toList().orEmpty())
        big.delete()
        // thresholds (P1): 64 MiB ceiling, <= 8 MiB growth 128 -> 512 MiB, 512 MiB run <= 5x the 128 MiB run
        val live = rows.maxOf { it.liveMiB }
        t.append("\nmax live delta over every run: ${"%.1f".format(live)} MiB (ceiling 64)\n")
        val a = byMib[128]; val b = byMib[512]
        if (a != null && b != null) {
            t.append("growth of the live delta 128 -> 512 MiB: ${"%.1f".format(b.liveMiB - a.liveMiB)} MiB (limit 8); 512 MiB wall ${b.wallMs} ms vs 128 MiB ${a.wallMs} ms = ${"%.2f".format(b.wallMs.toDouble() / a.wallMs)}x (limit 5x)\n")
            assertTrue("growth ${b.liveMiB - a.liveMiB}", b.liveMiB - a.liveMiB <= 8)
            assertTrue("time ratio", b.wallMs <= 5 * a.wallMs)
        }
        File(out!!).writeText(t.toString())
        assertTrue("live delta $live MiB", live <= 64)
        dir.deleteRecursively()
    }

    private companion object {
        /** Shared component budget, including indexes; measured staging must stay below this. */
        const val DB_BUDGET = 2.5
    }
}
