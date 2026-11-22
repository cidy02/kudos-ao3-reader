package io.github.cidy02.kudos.backup

import java.io.File
import org.junit.Assume.assumeTrue
import org.junit.Test

/**
 * Opt-in (A567_ABOVE_OUT): above-cap runs in child JVMs, labelled "JVM, above-cap (cap bypassed in
 * harness)". Monolithic = today's decode body at a fixed heap; streamed/events = the chunked tokenizer
 * at a small fixed heap, so completion itself is the bounded-heap evidence.
 */
class A567AboveCapTest {
    private fun child(xmxMib: Int, vararg args: String): String {
        val java = File(System.getProperty("java.home"), "bin/java").path
        val p = ProcessBuilder(java, "-XX:+UseSerialGC", "-Xmx${xmxMib}m", "-cp", System.getProperty("java.class.path"),
            "io.github.cidy02.kudos.backup.A567AboveCapProbe", *args).redirectErrorStream(true).start()
        val text = p.inputStream.bufferedReader().readText()
        val code = p.waitFor()
        return text.lines().lastOrNull { it.startsWith("RESULT") } ?: "RESULT crash(exit $code) 0 0 ${text.takeLast(80)}"
    }

    @Test
    fun aboveCap() {
        val out = System.getenv("A567_ABOVE_OUT")
        assumeTrue("opt-in", out != null)
        val sizes = (System.getenv("A567_ABOVE_SIZES") ?: "8,32,128,256,512").split(",").map { it.trim().toLong() }
        val dir = File(System.getProperty("java.io.tmpdir"), "a567-above").apply { mkdirs() }
        val t = StringBuilder("| scenario | heap cap | input | result | peak MiB over baseline | wall ms | detail |\n|---|---|---|---|---|---|---|\n")
        fun row(scenario: String, xmx: Int, input: String, r: String) {
            val p = r.split(" ", limit = 5)
            t.append("| $scenario | -Xmx${xmx}m | $input | ${p[1]} | ${p[2]} | ${p[3]} | ${p.getOrElse(4) { "" }} |\n"); println("A567 ${t.lines().dropLast(1).last()}")
        }
        for (mib in sizes) {
            val f = File(dir, "m$mib.json")
            child(2048, "gen", f.path, (mib * 1048576).toString())
            row("monolithic (today's decode body, no cap)", 2048, "$mib MiB rows", child(2048, "monolithic", f.path))
            row("monolithic", 8192, "$mib MiB rows", child(8192, "monolithic", f.path))
            row("chunked tokenizer, record at a time", 64, "$mib MiB rows", child(64, "streamed", f.path))
            f.delete()
        }
        val opaque = File(dir, "opaque.json")
        for (mib in listOf(20L, 96L, 256L)) {
            child(2048, "gen", opaque.path, (mib * 1048576 + 1048576).toString(), (mib * 1048576).toString())
            row("monolithic", 2048, "$mib MiB opaque value", child(2048, "monolithic", opaque.path))
            row("chunked tokenizer, strings over 1 MiB not retained", 48, "$mib MiB opaque value", child(48, "streamed", opaque.path))
        }
        opaque.delete()
        val nested = File(dir, "nested.json")
        for (tags in listOf(500_000, 2_000_000, 4_000_000)) {
            child(2048, "genNested", nested.path, tags.toString())
            val size = "one work, $tags tags (${nested.length() / 1048576} MiB)"
            row("tokenizer events only (oversized record streamed)", 48, size, child(48, "events", nested.path))
            row("tokenizer + JsonElement of the record (typed decode)", 48, size, child(48, "nestedTree", nested.path))
            row("tokenizer + JsonElement of the record (typed decode)", 512, size, child(512, "nestedTree", nested.path))
        }
        nested.delete()
        File(out!!).writeText(t.toString())
    }
}
