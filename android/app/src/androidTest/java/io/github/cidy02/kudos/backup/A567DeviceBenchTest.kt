package io.github.cidy02.kudos.backup

import android.util.Log
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.Test

/**
 * A-567 P1 device run (label results "device (Pixel)"). Parser comparison only: today's monolithic decode,
 * android.util.JsonReader and the chunked tokenizer on generated manifests, in the app's own cache dir
 * (the .bench sandbox). Files are deleted after each case; peak storage is recorded.
 */
class A567DeviceBenchTest {
    private fun peakOf(body: () -> String): Triple<String, Double, Long> {
        val rt = Runtime.getRuntime()
        repeat(3) { System.gc() }
        val base = rt.totalMemory() - rt.freeMemory()
        val peak = java.util.concurrent.atomic.AtomicLong(base)
        val stop = java.util.concurrent.atomic.AtomicBoolean(false)
        val th = Thread { while (!stop.get()) { peak.accumulateAndGet(rt.totalMemory() - rt.freeMemory(), ::maxOf); Thread.sleep(3) } }.apply { start() }
        val t0 = System.nanoTime()
        val r = try { body() } catch (e: OutOfMemoryError) { "OutOfMemoryError" } catch (e: Throwable) { "${e::class.simpleName}: ${e.message?.take(60)}" }
        val wall = (System.nanoTime() - t0) / 1_000_000
        stop.set(true); th.join()
        return Triple(r, (peak.get() - base) / 1048576.0, wall)
    }

    @Test
    fun parsers() {
        val ctx = InstrumentationRegistry.getInstrumentation().targetContext
        check(ctx.packageName.endsWith(".bench")) { "refusing to run outside the .bench sandbox: ${ctx.packageName}" }
        val dir = File(ctx.cacheDir, "a567").apply { mkdirs() }
        val out = StringBuilder("device (Pixel) ${android.os.Build.MODEL} Android ${android.os.Build.VERSION.RELEASE}; heap limit ${Runtime.getRuntime().maxMemory() / 1048576} MiB\n")
        out.append("| input | parser | outcome | heap peak MiB over baseline (sampled) | wall ms | file MiB (storage) |\n|---|---|---|---|---|---|\n")
        var peakStorage = 0L
        fun row(label: String, f: File, parser: String, body: () -> String) {
            val (r, peak, wall) = peakOf(body)
            out.append("| $label | $parser | $r | ${"%.1f".format(peak)} | $wall | ${f.length() / 1048576} |\n"); Log.i("A567", out.lines().dropLast(1).last())
        }
        fun stream(f: File, run: (java.io.InputStream, A567Events) -> Unit): String {
            var works = 0L
            val tree = A567Tree(records = { s, el -> if (s == "works") { BackupJson.decodeFromJsonElement(BackupWork.serializer(), el); works++ } }, maxString = 1 shl 20)
            f.inputStream().buffered(1 shl 16).use { run(it, tree) }
            return "ok works=$works"
        }
        val jr = { i: java.io.InputStream, e: A567Events -> A567JsonReaderParser.run(i, e, lenient = false) }
        val tk = { i: java.io.InputStream, e: A567Events -> A567ChunkedTokenizer.run(i, e) }
        fun case(label: String, size: Long, opaque: Long) {
            val f = File(dir, "m.json")
            A567Corpus.manifestFileOfSize(f, size, opaqueBytes = opaque)
            peakStorage = maxOf(peakStorage, dir.walkTopDown().filter { it.isFile }.sumOf { it.length() })
            row(label, f, "monolithic (today's decode body)") {
                val raw = parseJsonObjectOrNull(f.readBytes())
                "ok works=${BackupValidator.validateManifest(BackupJson.decodeFromJsonElement(KudosBackupManifest.serializer(), raw!!)).works.size}"
            }
            row(label, f, "JsonReader") { stream(f, jr) }
            row(label, f, "chunked tokenizer") { stream(f, tk) }
            f.delete()
        }
        try {
            for (mib in listOf(4L, 8L, 32L, 128L)) case("$mib MiB rows", mib * 1048576, 0)
            for (mib in listOf(20L, 96L)) case("$mib MiB opaque value", mib * 1048576 + 1048576, mib * 1048576)
        } finally {
            dir.deleteRecursively()
        }
        out.append("\npeak sandbox storage during the run: ${peakStorage / 1048576} MiB; deleted after each case (cache dir now ${dir.exists()})\n")
        File(ctx.cacheDir, "a567-device.md").writeText(out.toString())
        Log.i("A567", "DONE")
    }
}
