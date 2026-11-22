package io.github.cidy02.kudos.backup

import android.util.JsonReader
import android.util.JsonToken
import java.io.InputStream
import java.io.InputStreamReader
import java.io.Reader
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.JsonUnquotedLiteral

/*
 * PROTOTYPE ONLY (A-567 P1). Lives in tests; nothing here is wired into production. Two ways to turn
 * manifest bytes into the same event stream, so one consumer and one comparison serve both:
 *   - A567JsonReaderParser: platform android.util.JsonReader (strict, then lenient, like the route).
 *   - A567ChunkedTokenizer: a hand-written strict tokenizer over a streaming UTF-8 Reader and a 16 KiB
 *     char buffer; string values arrive in bounded chunks (the JsonReader API has no such thing).
 */

class A567ParseError(message: String) : Exception(message)

interface A567Events {
    fun beginObject()
    fun endObject()
    fun beginArray()
    fun endArray()
    fun name(name: String)

    /** A string value in bounded pieces; [last] closes it. JsonReader delivers one piece. */
    fun stringChunk(buffer: CharArray, offset: Int, length: Int, last: Boolean)

    /** Raw text of a number, true, false or null. */
    fun literal(text: String)
}

/**
 * Builds a JsonElement tree. Top-level array elements go to [records] (and are not retained) when it
 * is set; strings over [maxString] chars are not retained (their length is counted in [largeStrings]).
 */
@OptIn(ExperimentalSerializationApi::class)
class A567Tree(
    private val records: ((section: String, element: JsonElement) -> Unit)? = null,
    private val maxString: Int = Int.MAX_VALUE
) : A567Events {
    private sealed class Frame {
        class Obj(val map: LinkedHashMap<String, JsonElement> = LinkedHashMap(), var name: String? = null) : Frame()
        class Arr(val list: MutableList<JsonElement> = mutableListOf(), val section: String? = null) : Frame()
    }

    private val stack = ArrayDeque<Frame>()
    private var sb: StringBuilder? = null
    private var stringLength = 0L
    var root: JsonElement? = null
        private set
    var largeStrings = 0L
        private set
    var largestString = 0L
        private set
    var records_ = 0L
        private set

    private fun put(value: JsonElement) {
        when (val top = stack.lastOrNull()) {
            null -> root = value
            is Frame.Obj -> top.map[top.name!!] = value // duplicate keys: the last value wins, as in kotlinx
            is Frame.Arr -> if (top.section != null && records != null && stack.size == 2) {
                records_++
                records.invoke(top.section, value)
            } else {
                top.list += value
            }
        }
    }

    override fun beginObject() { stack.addLast(Frame.Obj()) }

    override fun endObject() {
        val frame = stack.removeLast() as Frame.Obj
        put(JsonObject(frame.map))
    }

    override fun beginArray() {
        val parent = stack.lastOrNull()
        val section = if (stack.size == 1 && parent is Frame.Obj) parent.name else null
        stack.addLast(Frame.Arr(section = section))
    }

    override fun endArray() {
        val frame = stack.removeLast() as Frame.Arr
        put(JsonArray(frame.list))
    }

    override fun name(name: String) { (stack.last() as Frame.Obj).name = name }

    override fun stringChunk(buffer: CharArray, offset: Int, length: Int, last: Boolean) {
        stringLength += length
        if (stringLength <= maxString) {
            (sb ?: StringBuilder().also { sb = it }).append(buffer, offset, length)
        } else {
            sb = null // over the retention limit: dropped, length still counted
        }
        if (last) {
            val text = sb?.toString()
            if (stringLength > maxString) largeStrings++
            largestString = maxOf(largestString, stringLength)
            put(if (text != null) JsonPrimitive(text) else JsonNull)
            sb = null
            stringLength = 0
        }
    }

    override fun literal(text: String) {
        put(
            when (text) {
                "null" -> JsonNull
                "true" -> JsonPrimitive(true)
                "false" -> JsonPrimitive(false)
                else -> JsonUnquotedLiteral(text)
            }
        )
    }
}

/** android.util.JsonReader -> events. Needs Robolectric (real implementation) in unit tests. */
object A567JsonReaderParser {
    private const val MAX_DEPTH = 512

    /** Strict first, then lenient: the order today's route uses (strict Json, then BackupJson). */
    fun parse(bytes: ByteArray, events: () -> A567Events): A567Events {
        val strict = events()
        return try {
            run(bytes.inputStream(), strict, lenient = false); strict
        } catch (_: Exception) {
            val lenient = events()
            run(bytes.inputStream(), lenient, lenient = true); lenient
        }
    }

    fun run(input: InputStream, events: A567Events, lenient: Boolean) {
        JsonReader(InputStreamReader(input, Charsets.UTF_8)).use { reader ->
            reader.isLenient = lenient
            if (reader.peek() != JsonToken.BEGIN_OBJECT) throw A567ParseError("root is not an object")
            value(reader, events, 0)
            // JsonReader stops after one value; the route requires EOF.
            if (reader.peek() != JsonToken.END_DOCUMENT) throw A567ParseError("trailing content")
        }
    }

    private fun value(r: JsonReader, e: A567Events, depth: Int) {
        if (depth > MAX_DEPTH) throw A567ParseError("too deep")
        when (r.peek()) {
            JsonToken.BEGIN_OBJECT -> {
                r.beginObject(); e.beginObject()
                while (r.hasNext()) { e.name(r.nextName()); value(r, e, depth + 1) }
                r.endObject(); e.endObject()
            }
            JsonToken.BEGIN_ARRAY -> {
                r.beginArray(); e.beginArray()
                while (r.hasNext()) value(r, e, depth + 1)
                r.endArray(); e.endArray()
            }
            JsonToken.STRING -> r.nextString().let { s -> e.stringChunk(s.toCharArray(), 0, s.length, true) }
            JsonToken.NUMBER -> e.literal(r.nextString())
            JsonToken.BOOLEAN -> e.literal(r.nextBoolean().toString())
            JsonToken.NULL -> { r.nextNull(); e.literal("null") }
            else -> throw A567ParseError("unexpected ${r.peek()}")
        }
    }
}

/** Strict RFC 8259 tokenizer over a Reader with a bounded buffer; strings leave in [CHUNK]-char pieces. */
class A567ChunkedTokenizer(private val reader: Reader, private val events: A567Events, private val lenient: Boolean = false) {
    private val buf = CharArray(16 * 1024)
    private var pos = 0
    private var lim = 0
    private val chunk = CharArray(CHUNK)

    private fun peek(): Int {
        if (pos == lim) {
            val n = reader.read(buf, 0, buf.size)
            if (n < 0) return -1
            pos = 0; lim = n
        }
        return buf[pos].code
    }

    private fun next(): Int = peek().also { if (it >= 0) pos++ }
    private fun fail(why: String): Nothing = throw A567ParseError(why)

    private fun ws() {
        while (true) {
            when (peek()) {
                ' '.code, '\t'.code, '\n'.code, '\r'.code -> pos++
                else -> return
            }
        }
    }

    fun parseDocument() {
        ws()
        if (peek() != '{'.code) fail("root is not an object")
        value(0)
        ws()
        if (peek() != -1) fail("trailing content")
    }

    private fun value(depth: Int) {
        if (depth > MAX_DEPTH) fail("too deep")
        ws()
        when (val c = peek()) {
            '{'.code -> {
                pos++; events.beginObject(); ws()
                if (peek() == '}'.code) { pos++ } else {
                    while (true) {
                        ws()
                        if (peek() == '"'.code) events.name(key())
                        else if (lenient) events.name(bare().also { if (it.isEmpty()) fail("expected a name") })
                        else fail("expected a name")
                        ws()
                        if (next() != ':'.code) fail("expected ':'")
                        value(depth + 1)
                        ws()
                        when (next()) { ','.code -> continue; '}'.code -> break; else -> fail("expected ',' or '}'") }
                    }
                }
                events.endObject()
            }
            '['.code -> {
                pos++; events.beginArray(); ws()
                if (peek() == ']'.code) { pos++ } else {
                    while (true) {
                        value(depth + 1)
                        ws()
                        when (next()) { ','.code -> continue; ']'.code -> break; else -> fail("expected ',' or ']'") }
                    }
                }
                events.endArray()
            }
            '"'.code -> string { chunkOut, last -> events.stringChunk(chunk, 0, chunkOut, last) }
            else -> events.literal(bare().also { if (it.isEmpty()) fail("expected a value") })
        }
    }

    /**
     * A bare token ends at whitespace or one of `"`,`,`,`:`,`[`,`]`,`{`,`}`. kotlinx reads numbers, true,
     * false, null and any other unquoted run this way even in strict mode; keys need it only when lenient.
     */
    private fun bare(): String {
        val sb = StringBuilder()
        while (true) {
            val c = peek()
            if (c < 0 || c == ' '.code || c == '\t'.code || c == '\n'.code || c == '\r'.code ||
                c == '"'.code || c == ','.code || c == ':'.code || c == '['.code || c == ']'.code ||
                c == '{'.code || c == '}'.code) return sb.toString()
            sb.append(next().toChar())
            if (sb.length > MAX_KEY) fail("bare token too long")
        }
    }

    /** Object keys are bounded by [MAX_KEY] chars; they are identifiers, never payloads. */
    private fun key(): String {
        val sb = StringBuilder()
        string { n, _ -> sb.append(chunk, 0, n); if (sb.length > MAX_KEY) fail("key too long") }
        return sb.toString()
    }

    /** Reads one string; hands the decoded characters out in chunks of at most [CHUNK]. */
    private fun string(emit: (Int, Boolean) -> Unit) {
        next() // opening quote
        var n = 0
        fun put(ch: Char, emitFn: (Int, Boolean) -> Unit) {
            if (n == chunk.size) { emitFn(n, false); n = 0 }
            chunk[n++] = ch
        }
        while (true) {
            val c = next()
            when {
                c < 0 -> fail("unterminated string")
                c == '"'.code -> { emit(n, true); return }
                // kotlinx accepts raw control characters inside strings, so the route does too.
                c == '\\'.code -> {
                    val e = next()
                    val decoded: Char = when (e) {
                        '"'.code -> '"'; '\\'.code -> '\\'; '/'.code -> '/'
                        'b'.code -> '\b'; 'f'.code -> '\u000c'; 'n'.code -> '\n'; 'r'.code -> '\r'; 't'.code -> '\t'
                        'u'.code -> {
                            var v = 0
                            repeat(4) {
                                val h = Character.digit(next(), 16)
                                if (h < 0) fail("bad \\u escape")
                                v = v * 16 + h
                            }
                            v.toChar()
                        }
                        else -> fail("bad escape")
                    }
                    put(decoded, emit)
                }
                else -> put(c.toChar(), emit)
            }
        }
    }

    companion object {
        const val CHUNK = 8 * 1024
        const val MAX_KEY = 64 * 1024
        const val MAX_DEPTH = 512

        fun run(input: InputStream, events: A567Events, lenient: Boolean = false) =
            A567ChunkedTokenizer(InputStreamReader(input, Charsets.UTF_8), events, lenient).parseDocument()

        /** Strict, then lenient, like the route; the input is read again, so it must be re-openable (a spool). */
        fun parse(bytes: ByteArray, events: () -> A567Events): A567Events = try {
            events().also { run(bytes.inputStream(), it) }
        } catch (_: A567ParseError) {
            events().also { run(bytes.inputStream(), it, lenient = true) }
        }
    }
}
