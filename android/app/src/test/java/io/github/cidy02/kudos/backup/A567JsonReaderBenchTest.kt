package io.github.cidy02.kudos.backup

import java.io.File
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Opt-in (A567_JR_OUT): android.util.JsonReader on the same large inputs, in-process under Robolectric (JVM). */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class A567JsonReaderBenchTest {
    @Test
    fun bench() {
        val out = System.getenv("A567_JR_OUT")
        assumeTrue("opt-in", out != null)
        val dir = File(System.getProperty("java.io.tmpdir"), "a567-jr").apply { mkdirs() }
        val t = StringBuilder("| input | parser | outcome | heap peak MiB over settled baseline (sampled) | retained after | wall ms |\n|---|---|---|---|---|---|\n")
        fun go(label: String, f: File, parser: String, run: (java.io.InputStream, A567Events) -> Unit) {
            var works = 0L
            val tree = A567Tree(records = { s, el -> if (s == "works") { BackupJson.decodeFromJsonElement(BackupWork.serializer(), el); works++ } }, maxString = 1 shl 20)
            val r = A567Run(emptyList()).measure {
                try { f.inputStream().buffered(1 shl 16).use { run(it, tree) }; "ok works=$works largestString=${tree.largestString}" } catch (e: OutOfMemoryError) { "OutOfMemoryError" }
            }
            t.append("| $label | $parser | ${r.outcome} | ${"%.1f".format(r.peakHeapMiB)} | ${"%.1f".format(r.retainedMiB)} | ${r.wallMs} |\n"); println("A567 JR ${t.lines().dropLast(1).last()}")
        }
        val jr = { i: java.io.InputStream, e: A567Events -> A567JsonReaderParser.run(i, e, lenient = false) }
        val tk = { i: java.io.InputStream, e: A567Events -> A567ChunkedTokenizer.run(i, e) }
        for (mib in listOf(8L, 32L, 128L)) {
            val f = File(dir, "m$mib.json"); A567Corpus.manifestFileOfSize(f, mib * 1048576)
            go("$mib MiB rows", f, "JsonReader", jr); go("$mib MiB rows", f, "tokenizer", tk); f.delete()
        }
        for (mib in listOf(20L, 96L)) {
            val f = File(dir, "o$mib.json"); A567Corpus.manifestFileOfSize(f, mib * 1048576 + 1048576, opaqueBytes = mib * 1048576)
            go("$mib MiB opaque value", f, "JsonReader", jr); go("$mib MiB opaque value", f, "tokenizer", tk); f.delete()
        }
        File(out!!).writeText(t.toString())
    }
}
