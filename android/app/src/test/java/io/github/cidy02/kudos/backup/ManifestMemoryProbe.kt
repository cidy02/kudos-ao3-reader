package io.github.cidy02.kudos.backup

import java.io.File
import kotlin.random.Random
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Realistic-manifest generator plus the production read/merge/write steps, run in a child JVM
 * with a capped heap by [ManifestMemoryBenchmarkTest] (A-566). Only production functions run;
 * this file only wires them in the order Folder Sync and backup import call them.
 */
object ManifestMemoryProbe {
    private val words = "the quiet harbor lantern winter orchard velvet midnight ember thistle compass hollow river paper".split(" ")

    private fun phrase(rnd: Random, n: Int) = (1..n).joinToString(" ") { words[rnd.nextInt(words.size)] }

    private fun uuid(n: Int) = "%08x-0000-4000-8000-%012x".format(n, n)

    private fun work(i: Int, rnd: Random) = BackupWork(
        id = uuid(i),
        title = phrase(rnd, 6),
        author = phrase(rnd, 2),
        summary = phrase(rnd, 90),
        sourceURL = "https://archiveofourown.org/works/${100000 + i}",
        dateAdded = "2026-01-01T00:00:00.000Z",
        hasEPUB = true,
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
        userTags = List(3) { phrase(rnd, 1) },
        readiumLocator = """{"href":"chapter$i.xhtml","locations":{"progression":0.5,"fragments":["${phrase(rnd, 20)}"]}}"""
    )

    private fun session(i: Int, work: Int) = BackupReadingSession(
        id = uuid(5_000_000 + i),
        workID = uuid(work),
        sourceURL = "https://archiveofourown.org/works/${100000 + work}",
        workTitle = "Title $work",
        startedAt = "2026-02-01T10:00:00.000Z",
        endedAt = "2026-02-01T10:30:00.000Z",
        durationSeconds = 1800.0,
        deviceID = uuid(7),
        chapterTitle = "Chapter 3",
        lastModifiedAt = "2026-02-01T10:30:00.000Z"
    )

    private fun annotation(i: Int, work: Int, rnd: Random) = BackupAnnotation(
        id = uuid(9_000_000 + i),
        workID = uuid(work),
        selectedText = phrase(rnd, 25),
        note = phrase(rnd, 20),
        locatorString = """{"href":"c.xhtml","locations":{"progression":0.1}}""",
        createdAt = "2026-02-01T10:30:00.000Z"
    )

    /** Pretty-printed like the real writers; ~50% works, ~40% reading sessions; iOS-only keys on every record. */
    private fun encode(units: Int): String {
        val rnd = Random(units)
        val manifest = KudosBackupManifest(
            version = 8,
            exportedAt = "2026-06-01T00:00:00.000Z",
            works = List(units) { work(it, rnd) },
            readingSessions = List(units * 4) { session(it, it % units) },
            annotations = List(units) { annotation(it, it % units, rnd) }
        )
        val tree = BackupJson.encodeToJsonElement(KudosBackupManifest.serializer(), manifest) as JsonObject
        fun withUnknown(key: String) = JsonArray((tree[key] as JsonArray).map {
            JsonObject((it as JsonObject) + ("iosOnlyShelf" to JsonPrimitive("future-ios-field")))
        })
        val out = JsonObject(
            tree + mapOf(
                "works" to withUnknown("works"),
                "readingSessions" to withUnknown("readingSessions"),
                "annotations" to withUnknown("annotations"),
                "iosFutureTopLevel" to JsonPrimitive("kept")
            )
        )
        return BackupJson.encodeToString(JsonObject.serializer(), out)
    }

    /** The largest manifest not over [targetBytes]; written to [file]. */
    fun writeManifest(file: File, targetBytes: Long) {
        var units = (targetBytes / 6000).toInt().coerceAtLeast(10)
        var text = encode(units)
        repeat(6) {
            val ratio = targetBytes.toDouble() / text.length
            units = (units * ratio * 0.995).toInt().coerceAtLeast(1)
            text = encode(units)
        }
        while (text.length > targetBytes) {
            units = (units * 0.99).toInt()
            text = encode(units)
        }
        file.writeBytes(text.toByteArray(Charsets.UTF_8))
    }

    private fun read(file: File) = file.inputStream().use { it.readLimitedBytes(BackupPaths.MANIFEST, Long.MAX_VALUE) }

    /** Backup import, then recordImportedManifest folding the raw JSON into the stored overlay. */
    fun runImport(file: File): Int {
        val bytes = read(file)
        val (manifest, raw) = BackupValidator.decodeManifestWithRaw(bytes)
        val stored = parseJsonObjectOrNull(bytes)
        val merged = mergeImportedManifestJson(raw!!, stored)
        val saved = BackupJson.encodeToString(JsonObject.serializer(), merged).toByteArray(Charsets.UTF_8)
        return manifest.works.size + saved.size
    }

    /** One Folder Sync run: read live, merge any pending import, rebuild, carry unknown keys, publish. */
    fun runSync(file: File, pending: Boolean): Int {
        val atRead = read(file)
        var live: Pair<KudosBackupManifest, JsonObject?>? = BackupValidator.decodeManifestWithRaw(atRead)
        val importedWorks = live!!.first.works.size
        val readJson = live.second!!
        live = null // dropped once imported, as SyncRepository does
        val effective = if (pending) {
            val pendingJson = parseJsonObjectOrNull(read(file))!!
            carryUnknownRecordKeys(mergeImportedManifestJson(pendingJson, readJson), readJson)
        } else {
            readJson
        }
        // The snapshot the app rebuilds from its own database is about the size of the decoded manifest.
        val manifestOut = BackupValidator.decodeManifest(atRead)
        val outgoing = BackupJson.encodeToJsonElement(KudosBackupManifest.serializer(), manifestOut) as JsonObject
        val bytes = BackupJson.encodeToString(JsonObject.serializer(), carryUnknownRecordKeys(outgoing, effective))
            .toByteArray(Charsets.UTF_8)
        val unchanged = file.inputStream().use { it.hasExactly(atRead) }
        return importedWorks + bytes.size + if (unchanged) 1 else 0
    }

    /** args: scenario file [bytes for gen]. Exit 0 when it completes, 3 on OutOfMemoryError. */
    @JvmStatic
    fun main(args: Array<String>) {
        val file = File(args[1])
        try {
            when (args[0]) {
                "gen" -> writeManifest(file, args[2].toLong())
                "import" -> runImport(file)
                "sync" -> runSync(file, pending = false)
                "syncPending" -> runSync(file, pending = true)
            }
        } catch (_: OutOfMemoryError) {
            System.exit(3)
        }
        System.exit(0)
    }
}
