package io.github.cidy02.kudos.backup

import java.io.File
import java.util.concurrent.atomic.AtomicLong
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/**
 * Child-JVM scenarios for A-567 P1 above-cap runs (labelled separately from the capped end-to-end rows).
 * No Android classes: the chunked tokenizer and today's pure decode path only. Prints one line:
 * "RESULT <ok|oom|error> peakMiB wallMs detail". The parent sets -Xmx.
 */
object A567AboveCapProbe {
    private fun peakSampler(): Pair<AtomicLong, Thread> {
        val peak = AtomicLong()
        val t = Thread {
            while (true) {
                val rt = Runtime.getRuntime(); peak.accumulateAndGet(rt.totalMemory() - rt.freeMemory(), ::maxOf)
                try { Thread.sleep(3) } catch (_: InterruptedException) { return@Thread }
            }
        }.apply { isDaemon = true; start() }
        return peak to t
    }

    /** Today's body without the 8 MiB guard: read all bytes, parse tree, typed decode, validate. */
    private fun monolithic(file: File): String {
        val bytes = file.readBytes()
        val raw = parseJsonObjectOrNull(bytes)
        val manifest = BackupJson.decodeFromJsonElement(KudosBackupManifest.serializer(), raw!!)
        return "works=${BackupValidator.validateManifest(manifest).works.size}"
    }

    /** Tokenizer, one record at a time into typed decoders, nothing retained. */
    private fun streamed(file: File): String {
        var works = 0L; var other = 0L
        val tree = A567Tree(records = { section, el ->
            when (section) {
                "works" -> { BackupJson.decodeFromJsonElement(BackupWork.serializer(), el); works++ }
                "readingSessions" -> { BackupJson.decodeFromJsonElement(BackupReadingSession.serializer(), el); other++ }
                "annotations" -> { BackupJson.decodeFromJsonElement(BackupAnnotation.serializer(), el); other++ }
            }
        }, maxString = 1 shl 20)
        file.inputStream().buffered(1 shl 16).use { A567ChunkedTokenizer.run(it, tree) }
        return "works=$works other=$other largestString=${tree.largestString} large=${tree.largeStrings}"
    }

    /** Events only (no tree): the oversized-record case, a single work with a huge nested array. */
    private fun eventsOnly(file: File): String {
        var tokens = 0L
        val events = object : A567Events {
            override fun beginObject() { tokens++ }
            override fun endObject() {}
            override fun beginArray() { tokens++ }
            override fun endArray() {}
            override fun name(name: String) {}
            override fun stringChunk(buffer: CharArray, offset: Int, length: Int, last: Boolean) { if (last) tokens++ }
            override fun literal(text: String) { tokens++ }
        }
        file.inputStream().buffered(1 shl 16).use { A567ChunkedTokenizer.run(it, events) }
        return "tokens=$tokens"
    }

    /** Same oversized record but built into a JsonElement tree for typed decode (what a record-at-a-time decoder needs). */
    private fun nestedTree(file: File): String {
        var el: JsonElement? = null
        val tree = A567Tree(records = { _, e -> el = e })
        file.inputStream().buffered(1 shl 16).use { A567ChunkedTokenizer.run(it, tree) }
        return "decoded=${BackupJson.decodeFromJsonElement(BackupWork.serializer(), el!!).workTags.size}"
    }

    @JvmStatic
    fun main(args: Array<String>) {
        val file = File(args[1])
        val (peak, sampler) = peakSampler()
        val base = Runtime.getRuntime().let { it.totalMemory() - it.freeMemory() }
        val t0 = System.nanoTime()
        var status = "ok"; var detail = ""
        try {
            detail = when (args[0]) {
                "gen" -> { A567Corpus.manifestFileOfSize(file, args[2].toLong(), opaqueBytes = args.getOrNull(3)?.toLong() ?: 0); "bytes=${file.length()}" }
                "genNested" -> { genNested(file, args[2].toInt()); "bytes=${file.length()}" }
                "monolithic" -> monolithic(file)
                "streamed" -> streamed(file)
                "events" -> eventsOnly(file)
                "nestedTree" -> nestedTree(file)
                else -> error("scenario")
            }
        } catch (_: OutOfMemoryError) { status = "oom" } catch (e: Throwable) { status = "error"; detail = "${e::class.simpleName}: ${e.message?.take(80)}" }
        val wall = (System.nanoTime() - t0) / 1_000_000
        println("RESULT $status ${"%.1f".format((peak.get() - base) / 1048576.0)} $wall $detail")
        System.exit(0)
    }

    /** One work whose workTags holds [tags] strings. */
    private fun genNested(file: File, tags: Int) {
        file.bufferedWriter().use { w ->
            w.write("{\"version\":8,\"exportedAt\":\"2026-06-01T00:00:00.000Z\",\"works\":[{\"id\":\"${A567Corpus.uuid(1)}\",\"title\":\"big\",\"dateAdded\":\"2026-01-01T00:00:00.000Z\",\"workTags\":[")
            for (i in 0 until tags) { if (i > 0) w.write(","); w.write("\"tag number $i of the growing nested array\"") }
            w.write("]}]}")
        }
    }
}
