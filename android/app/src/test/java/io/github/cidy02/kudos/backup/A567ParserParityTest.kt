package io.github.cidy02.kudos.backup

import io.github.cidy02.kudos.works.PickedDocumentReader
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.zip.ZipInputStream
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.intOrNull
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A-567 P1 parser prototypes against today's routes on one corpus: every existing manifest fixture
 * plus the malformed cases of the plan's P1 section. "Today" is [oracle]: parseJsonObjectOrNull
 * (strict kotlinx, then lenient), BackupValidator's decode body, isStrictJsonObject (live recovery's
 * whole-JSON test) and PickedDocumentReader.isBackupManifest (the picker's sniff).
 * Differences are findings; the ones already understood are pinned in [knownJsonReader] and
 * [knownTokenizer] with their reason, so the gate fails on any new or vanished difference.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class A567ParserParityTest {
    data class Result(
        val parsed: Boolean,
        val strict: Boolean,
        val decode: String,
        val typed: Any?,
        val raw: JsonObject?,
        val sniff: Boolean
    ) {
        fun same(o: Result) = parsed == o.parsed && strict == o.strict && decode == o.decode && typed == o.typed &&
            (decode != "ok" || raw == o.raw) && sniff == o.sniff

        fun diff(o: Result) = buildList {
            if (parsed != o.parsed) add("parseJsonObjectOrNull ${if (parsed) "ok" else "null"} vs ${if (o.parsed) "ok" else "null"}")
            if (strict != o.strict) add("strict whole-object $strict vs ${o.strict}")
            if (decode != o.decode) add("decode $decode vs ${o.decode}")
            if (decode == "ok" && o.decode == "ok" && (typed != o.typed || raw != o.raw)) add("typed/raw values differ")
            if (sniff != o.sniff) add("picker sniff $sniff vs ${o.sniff}")
        }.joinToString("; ")
    }

    /** The production decode body without its 8 MiB guard, so the same function serves the above-cap cases. */
    private fun decodeBody(raw: JsonObject?, bytes: ByteArray): Pair<String, Any?> {
        val manifest = try {
            if (raw != null) {
                BackupJson.decodeFromJsonElement(KudosBackupManifest.serializer(), raw)
            } else {
                BackupJson.decodeFromString<KudosBackupManifest>(bytes.toString(Charsets.UTF_8))
            }
        } catch (e: kotlinx.serialization.SerializationException) {
            return "InvalidJson" to null
        } catch (e: IllegalArgumentException) {
            return "InvalidJson" to null
        }
        return try {
            "ok" to BackupValidator.validateManifest(manifest, now = java.time.Instant.now())
        } catch (e: Throwable) {
            e::class.simpleName!! to null
        }
    }

    private fun oracle(bytes: ByteArray): Result {
        val parsed = parseJsonObjectOrNull(bytes)
        val real = runCatching { BackupValidator.decodeManifestWithRaw(bytes) }
        val decode = real.fold({ "ok" }, { it::class.simpleName!! })
        return Result(parsed != null, isStrictJsonObject(bytes), decode, real.getOrNull()?.first, real.getOrNull()?.second,
            PickedDocumentReader.isBackupManifest(bytes))
    }

    /** PickedDocumentReader.isBackupManifest's test, applied to a parsed root. */
    private fun sniff(root: JsonObject?): Boolean =
        root != null && (root["version"] as? kotlinx.serialization.json.JsonPrimitive)?.intOrNull != null &&
            root["works"] is kotlinx.serialization.json.JsonArray

    private fun viaJsonReader(bytes: ByteArray): Result {
        val strictTree = runCatching { A567Tree().also { A567JsonReaderParser.run(bytes.inputStream(), it, lenient = false) } }.getOrNull()
        val tree = strictTree ?: runCatching { A567Tree().also { A567JsonReaderParser.run(bytes.inputStream(), it, lenient = true) } }.getOrNull()
        val root = tree?.root as? JsonObject
        val (decode, typed) = decodeBody(root, bytes)
        val strictRoot = strictTree?.root as? JsonObject
        return Result(root != null, strictRoot != null, decode, typed, root, sniff(strictRoot))
    }

    private fun viaTokenizer(bytes: ByteArray): Result {
        val strictTree = runCatching { A567Tree().also { A567ChunkedTokenizer.run(bytes.inputStream(), it) } }.getOrNull()
        val tree = strictTree ?: runCatching { A567Tree().also { A567ChunkedTokenizer.run(bytes.inputStream(), it, lenient = true) } }.getOrNull()
        val root = tree?.root as? JsonObject
        val strictRoot = strictTree?.root as? JsonObject
        val (decode, typed) = decodeBody(root, bytes)
        return Result(root != null, strictRoot != null, decode, typed, root, sniff(strictRoot))
    }

    private fun exportedZipManifest(): ByteArray {
        val zip = javaClass.classLoader!!.getResourceAsStream("cross-platform/ios-export.kudosbackup")!!.readBytes()
        ZipInputStream(zip.inputStream()).use { z ->
            while (true) {
                val entry = z.nextEntry ?: break
                if (entry.name == BackupPaths.MANIFEST) return z.readBytes()
            }
        }
        error("no manifest in ios-export.kudosbackup")
    }

    private fun resource(path: String) = javaClass.classLoader!!.getResourceAsStream(path)!!.readBytes()

    private fun doc(body: String, version: String = "8") =
        """{"version":$version,"exportedAt":"2026-06-01T00:00:00.000Z",$body}""".toByteArray()

    private fun work(id: Int = 1, extra: String = "") =
        """{"id":"${A567Corpus.uuid(id)}","title":"T","dateAdded":"2026-01-01T00:00:00.000Z"$extra}"""

    private fun valid(): ByteArray = A567Corpus.manifestBytesOfSize(40_000)

    val corpus: List<Pair<String, ByteArray>> by lazy {
        val v = valid()
        val s = v.toString(Charsets.UTF_8)
        buildList {
            add("fixture ios-sync-folder" to resource("cross-platform/ios-sync-folder/KudosLibrary/manifest.json"))
            add("fixture android-after-ios-sync-folder" to resource("cross-platform/android-after-ios-sync-folder/KudosLibrary/manifest.json"))
            add("fixture ios-export.kudosbackup manifest" to exportedZipManifest())
            add("generated v8 (works, sessions, annotations)" to v)
            add("generated, metadata after arrays" to ByteArrayOutputStream().also {
                A567Corpus.writeManifest(it, works = 5, sessionsPerWork = 2, annotations = 3, metaAfter = true)
            }.toByteArray())
            add("generated, version 3" to A567Corpus.manifestBytesOfSize(20_000, version = 3))
            add("generated, 1 KiB opaque top-level value" to A567Corpus.manifestBytesOfSize(20_000, opaqueBytes = 1024))
            add("empty works" to doc("\"works\":[]"))
            // document shape
            add("empty input" to ByteArray(0))
            add("whitespace only" to " \n".toByteArray())
            add("UTF-8 BOM prefix" to byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte()) + v)
            add("top-level array" to "[]".toByteArray())
            add("top-level string" to "\"x\"".toByteArray())
            add("top-level null" to "null".toByteArray())
            add("trailing: garbage word" to v + "x".toByteArray())
            add("trailing: second object" to v + "{}".toByteArray())
            add("trailing: whitespace only" to v + " \n\n".toByteArray())
            add("trailing: NUL byte" to v + byteArrayOf(0))
            add("trailing: comma" to v + ",".toByteArray())
            // keys
            add("escaped keys (\\u0076ersion, wor\\u006bs)" to """{"\u0076ersion":8,"exportedAt":"2026-06-01T00:00:00.000Z","wor\u006bs":[${work()}]}""".toByteArray())
            add("duplicate key: version 8 then 99" to """{"version":8,"version":99,"exportedAt":"2026-06-01T00:00:00.000Z","works":[]}""".toByteArray())
            add("duplicate key: version 99 then 8" to """{"version":99,"version":8,"exportedAt":"2026-06-01T00:00:00.000Z","works":[]}""".toByteArray())
            add("duplicate key: works twice" to doc("\"works\":[${work(1)}],\"works\":[${work(2)}]"))
            add("duplicate key inside a record" to doc("\"works\":[{\"id\":\"${A567Corpus.uuid(1)}\",\"title\":\"a\",\"title\":\"b\"}]"))
            add("empty key" to doc("\"works\":[],\"\":1"))
            // strings
            add("escapes: \\u0000, surrogate pair" to doc("\"works\":[${work(1, ",\"summary\":\"a\\u0000b\\ud83d\\ude00\"")}]"))
            add("escapes: lone high surrogate" to doc("\"works\":[${work(1, ",\"summary\":\"\\ud800\"")}]"))
            add("escapes: invalid \\x" to doc("\"works\":[${work(1, ",\"summary\":\"\\x\"")}]"))
            add("escapes: bad \\u12" to doc("\"works\":[${work(1, ",\"summary\":\"\\u12\"")}]"))
            add("raw newline inside string" to doc("\"works\":[${work(1, ",\"summary\":\"a\nb\"")}]"))
            add("raw tab inside string" to doc("\"works\":[${work(1, ",\"summary\":\"a\tb\"")}]"))
            add("unterminated string" to """{"version":8,"exportedAt":"2026""".toByteArray())
            // numbers and scalars
            for ((label, token) in listOf(
                "leading zero" to "08", "decimal" to "8.0", "exponent" to "1e1", "plus sign" to "+8", "bare fraction" to ".5",
                "NaN" to "NaN", "bare minus" to "-", "true" to "true", "string 8" to "\"8\"", "null" to "null",
                "huge int" to "99999999999999999999", "negative" to "-1", "zero" to "0", "float 8.5" to "8.5", "Infinity" to "Infinity"
            )) {
                add("version = $label" to """{"version":$token,"exportedAt":"2026-06-01T00:00:00.000Z","works":[]}""".toByteArray())
            }
            add("version missing" to """{"exportedAt":"2026-06-01T00:00:00.000Z","works":[]}""".toByteArray())
            add("version 9 (unsupported)" to doc("\"works\":[]", "9"))
            add("exportedAt missing" to """{"version":8,"works":[]}""".toByteArray())
            add("exportedAt not a date" to """{"version":8,"exportedAt":"yesterday","works":[]}""".toByteArray())
            add("exportedAt number" to """{"version":8,"exportedAt":5,"works":[]}""".toByteArray())
            // separators
            add("missing comma between members" to """{"version":8 "exportedAt":"2026-06-01T00:00:00.000Z","works":[]}""".toByteArray())
            add("double comma in object" to """{"version":8,,"exportedAt":"2026-06-01T00:00:00.000Z","works":[]}""".toByteArray())
            add("trailing comma in object" to """{"version":8,"exportedAt":"2026-06-01T00:00:00.000Z","works":[],}""".toByteArray())
            add("trailing comma in array" to doc("\"works\":[${work()},]"))
            add("double comma in array" to doc("\"works\":[${work()},,${work(2)}]"))
            add("missing colon" to """{"version" 8,"exportedAt":"2026-06-01T00:00:00.000Z","works":[]}""".toByteArray())
            add("semicolon separator" to """{"version":8;"exportedAt":"2026-06-01T00:00:00.000Z","works":[]}""".toByteArray())
            add("equals as colon" to """{"version"=8,"exportedAt":"2026-06-01T00:00:00.000Z","works":[]}""".toByteArray())
            add("unclosed object" to """{"version":8,"exportedAt":"2026-06-01T00:00:00.000Z","works":[]""".toByteArray())
            add("unclosed array" to """{"version":8,"exportedAt":"2026-06-01T00:00:00.000Z","works":[""".toByteArray())
            add("extra closing brace" to v + "}".toByteArray())
            // lenient-only syntax (accepted today through BackupJson isLenient)
            add("lenient: unquoted keys" to """{version:8,exportedAt:"2026-06-01T00:00:00.000Z",works:[]}""".toByteArray())
            add("lenient: single-quoted strings" to """{'version':8,'exportedAt':'2026-06-01T00:00:00.000Z','works':[]}""".toByteArray())
            add("lenient: unquoted string value" to """{"version":8,"exportedAt":2026-06-01T00:00:00.000Z,"works":[]}""".toByteArray())
            add("lenient: block comment" to """{"version":8,/*c*/"exportedAt":"2026-06-01T00:00:00.000Z","works":[]}""".toByteArray())
            add("lenient: line comment" to "{\"version\":8,// c\n\"exportedAt\":\"2026-06-01T00:00:00.000Z\",\"works\":[]}".toByteArray())
            add("lenient: quoted number" to """{"version":"8","exportedAt":"2026-06-01T00:00:00.000Z","works":[]}""".toByteArray())
            // invalid UTF-8
            add("invalid UTF-8: 0xFF in title" to doc("\"works\":[${work(1)}]").let {
                val text = it.toString(Charsets.ISO_8859_1).replace("\"title\":\"T\"", "\"title\":\"T\u00ff\"")
                text.toByteArray(Charsets.ISO_8859_1)
            })
            add("invalid UTF-8: truncated multibyte before quote" to doc("\"works\":[${work(1)}]").let {
                it.toString(Charsets.ISO_8859_1).replace("\"title\":\"T\"", "\"title\":\"T\u00e2\"").toByteArray(Charsets.ISO_8859_1)
            })
            add("invalid UTF-8: overlong slash in key" to doc("\"works\":[]").let {
                it.toString(Charsets.ISO_8859_1).replace("\"works\"", "\"wor\u00c0\u00afks\"").toByteArray(Charsets.ISO_8859_1)
            })
            add("valid UTF-8: emoji and CJK in title" to doc("\"works\":[${work(1).replace("\"T\"", "\"\uD83D\uDE00 \u7269\u8A9E\"")}]"))
            // wrong section kinds
            add("works is an object" to doc("\"works\":{}"))
            add("works is a string" to doc("\"works\":\"x\""))
            add("works is null" to doc("\"works\":null"))
            add("works elements are not objects" to doc("\"works\":[1,\"x\",null,[]]"))
            add("works missing" to doc("\"bookmarks\":[]"))
            add("readingSessions is a number" to doc("\"works\":[],\"readingSessions\":5"))
            add("settings is an array" to doc("\"works\":[],\"settings\":[]"))
            add("exportedBy is a string" to doc("\"works\":[],\"exportedBy\":\"x\""))
            add("annotations contains null" to doc("\"works\":[],\"annotations\":[null]"))
            // lossy typed elements
            add("work: id missing" to doc("\"works\":[{\"title\":\"x\"}]"))
            add("work: id null" to doc("\"works\":[{\"id\":null,\"title\":\"x\"}]"))
            add("work: id not a uuid" to doc("\"works\":[{\"id\":\"nope\",\"title\":\"x\"}]"))
            add("work: wordCount \"abc\"" to doc("\"works\":[${work(1, ",\"wordCount\":\"abc\"")}]"))
            add("work: wordCount \"12\" (quoted)" to doc("\"works\":[${work(1, ",\"wordCount\":\"12\"")}]"))
            add("work: wordCount 1.5" to doc("\"works\":[${work(1, ",\"wordCount\":1.5")}]"))
            add("work: wordCount negative" to doc("\"works\":[${work(1, ",\"wordCount\":-1")}]"))
            add("work: isFavorite \"yes\"" to doc("\"works\":[${work(1, ",\"isFavorite\":\"yes\"")}]"))
            add("work: isFavorite 1" to doc("\"works\":[${work(1, ",\"isFavorite\":1")}]"))
            add("work: title is a number" to doc("\"works\":[${work(1).replace("\"T\"", "5")}]"))
            add("work: title is an object" to doc("\"works\":[${work(1).replace("\"T\"", "{}")}]"))
            add("work: workTags has null and numbers" to doc("\"works\":[${work(1, ",\"workTags\":[null,1,\"a\"]")}]"))
            add("work: unknown nested key kept" to doc("\"works\":[${work(1, ",\"future\":{\"a\":[1,2,{\"b\":null}]}")}]"))
            add("work: lastScrollFraction 2.0 (validator rejects)" to doc("\"works\":[${work(1, ",\"lastScrollFraction\":2.0")}]"))
            add("work: dateAdded not a date (validator rejects)" to doc("\"works\":[${work(1).replace("2026-01-01T00:00:00.000Z", "never")}]"))
            add("works: duplicate id (validator rejects)" to doc("\"works\":[${work(1)},${work(1)}]"))
            add("works: duplicate id, different case" to doc("\"works\":[${work(10)},${work(10).uppercase().replace("\"ID\"", "\"id\"")}]"))
            // truncated live input
            for (fraction in listOf(0.25, 0.5, 0.9)) {
                add("truncated at ${(fraction * 100).toInt()}%" to v.copyOf((v.size * fraction).toInt()))
            }
            add("truncated: last byte missing" to v.copyOf(v.size - 1))
            add("truncated: after a comma" to s.substring(0, s.indexOf("},") + 2).toByteArray())
            add("truncated: mid-escape" to "{\"version\":8,\"exportedAt\":\"2026-06-01T00:00:00.000Z\",\"works\":[{\"id\":\"a\\".toByteArray())
            // depth
            add("nesting depth 100 (unknown key)" to doc("\"deep\":${"[".repeat(100)}${"]".repeat(100)},\"works\":[]"))
            add("nesting depth 600 (unknown key)" to doc("\"deep\":${"[".repeat(600)}${"]".repeat(600)},\"works\":[]"))
        }
    }

    /** Differences understood and accepted as findings; each maps a case name to why. */
    private val lenientSuperset = "JsonReader's lenient mode accepts what today's lenient kotlinx parse rejects (a fallback the route then fails on)"
    private val strictNumbers = "JsonReader's strict mode rejects bare number-like tokens that kotlinx strict accepts as literals; the lenient retry then accepts, so only the strict-whole-object flag differs"
    private val knownJsonReader = mapOf(
        "UTF-8 BOM prefix" to "JsonReader skips a BOM; today rejects the document",
        "escapes: invalid \\x" to lenientSuperset,
        "version = leading zero" to strictNumbers,
        "version = plus sign" to strictNumbers,
        "version = bare fraction" to strictNumbers,
        "version = NaN" to strictNumbers,
        "version = bare minus" to strictNumbers,
        "version = Infinity" to strictNumbers,
        "trailing comma in array" to lenientSuperset,
        "double comma in array" to lenientSuperset,
        "semicolon separator" to lenientSuperset,
        "equals as colon" to lenientSuperset,
        "lenient: unquoted keys" to "JsonReader sniffs true on the lenient tree; the picker's strict parse says false",
        "lenient: single-quoted strings" to lenientSuperset,
        "lenient: block comment" to lenientSuperset,
        "lenient: line comment" to lenientSuperset,
        "nesting depth 600 (unknown key)" to "prototype depth cap 512 is a new limit (needs a compatibility decision); kotlinx accepts it"
    )
    private val knownTokenizer = mapOf(
        "nesting depth 600 (unknown key)" to "prototype depth cap 512 is a new limit (needs a compatibility decision); kotlinx accepts it"
    )

    @Test
    fun parityAgainstTodaysRoutes() {
        val out = System.getenv("A567_PARSER_OUT")
        val table = StringBuilder("| case | today (parse/strict/decode/sniff) | JsonReader | tokenizer |\n|---|---|---|---|\n")
        val unexpected = mutableListOf<String>()
        var jsonReaderSame = 0
        var tokenizerSame = 0
        corpus.forEach { (name, bytes) ->
            val today = oracle(bytes)
            val reader = viaJsonReader(bytes)
            val tokenizer = viaTokenizer(bytes)
            val readerDiff = if (today.same(reader)) "same" else today.diff(reader)
            val tokenizerDiff = if (today.same(tokenizer)) "same" else today.diff(tokenizer)
            if (readerDiff == "same") jsonReaderSame++
            if (tokenizerDiff == "same") tokenizerSame++
            table.append("| $name | ${today.parsed}/${today.strict}/${today.decode}/${today.sniff} | $readerDiff | $tokenizerDiff |\n")
            if ((readerDiff == "same") == (name in knownJsonReader)) unexpected += "JsonReader $name: $readerDiff"
            if ((tokenizerDiff == "same") == (name in knownTokenizer)) unexpected += "tokenizer $name: $tokenizerDiff"
        }
        table.append("\nJsonReader identical on $jsonReaderSame of ${corpus.size}; tokenizer identical on $tokenizerSame of ${corpus.size}.\n")
        if (out != null) File(out).writeText(table.toString())
        if (System.getenv("A567_DISCOVER") != null) { println(table); return }
        assertTrue(unexpected.joinToString("\n"), unexpected.isEmpty())
        assertEquals(corpus.size, corpus.map { it.first }.toSet().size)
    }
}
