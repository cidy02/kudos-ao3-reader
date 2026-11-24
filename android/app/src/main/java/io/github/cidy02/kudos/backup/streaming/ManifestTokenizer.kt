package io.github.cidy02.kudos.backup.streaming

import java.io.IOException
import java.io.InputStream
import java.io.InputStreamReader
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction

/** Token events from [ManifestTokenizer]. Strings arrive in bounded pieces; numbers, true, false and null as validated text. */
internal interface ManifestEvents {
    fun beginObject()
    fun endObject()
    fun beginArray()
    fun endArray()
    fun name(name: String)

    /** One piece of a string value; [last] closes it. A piece never ends between the halves of a surrogate pair. */
    fun stringChunk(buffer: CharArray, offset: Int, length: Int, last: Boolean)

    /** A number (RFC 8259 grammar), `true`, `false` or `null`. */
    fun literal(text: String)
}

/** Where the tokenizer is in the source, in UTF-8 bytes, for source-size limits. */
internal interface SourcePosition {
    /** Bytes consumed so far (a BOM counts). */
    fun sourceBytes(): Long

    /** Byte offset where the value being reported began (first byte after whitespace), valid during that value's first event. */
    val valueStart: Long
}

/**
 * The shared manifest input contract (owner decision 2026-11-22; shared decisions 2026-11-23), as a chunked
 * tokenizer over a UTF-8 stream with a fixed 16 KiB read buffer:
 *  - strict RFC 8259 syntax plus a leading UTF-8 BOM and a single trailing comma in objects and arrays;
 *  - the root must be an object; anything but whitespace after it is invalid;
 *  - an escaped surrogate must be a high/low pair; escape hex digits are ASCII only;
 *  - raw control characters U+0000-U+001F inside strings and malformed UTF-8 are syntax errors;
 *  - numbers follow the JSON grammar and are scanned incrementally; a bare word is a syntax error;
 *  - at most [MAX_DEPTH] containers including the root (deeper is [ManifestStageException.ResourceExhausted], not
 *    a syntax error, so a complete live file past the ceiling is never eligible for `.bak` replacement).
 * Limits that do not make the document malformed (key length in UTF-16 units, number length in source characters,
 * members per object counted before duplicate removal, at every depth) are remembered and thrown after the whole
 * document has been read, so a malformed or unreadable tail reports its own class first.
 * Duplicate keys are not decided here; the consumer sees every `name`.
 */
internal class ManifestTokenizer(
    input: InputStream,
    private val events: ManifestEvents,
    private val isCancelled: () -> Boolean = { false }
) : SourcePosition {
    private val reader = InputStreamReader(
        input,
        Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
    )
    private val buf = CharArray(16 * 1024)
    private var pos = 0
    private var lim = 0
    private var base = 0L
    private var bytesBase = 0L
    private var scanPos = 0
    private var scanBytes = 0L
    private val chunk = CharArray(CHUNK)
    private var chunkLen = 0
    private var keySink: StringBuilder? = null
    private var keyOverflow = false
    private val token = StringBuilder()
    private var deferred: String? = null
    private var muted = false
    override var valueStart = 0L
        private set

    private fun peek(): Int {
        while (pos == lim) {
            if (isCancelled()) throw ManifestStageException.Cancelled()
            bytesBase = sourceBytes()
            scanPos = 0
            scanBytes = 0
            val n = try {
                reader.read(buf, 0, buf.size)
            } catch (e: CharacterCodingException) {
                throw ManifestStageException.Invalid("malformed UTF-8 (near character ${base + lim})", syntactic = true)
            } catch (e: IOException) {
                throw ManifestStageException.Io(e)
            }
            if (n < 0) return -1
            base += lim
            pos = 0
            lim = n
        }
        return buf[pos].code
    }

    override fun sourceBytes(): Long {
        while (scanPos < pos) {
            val c = buf[scanPos++].code
            scanBytes += if (c < 0x80) 1 else if (c < 0x800) 2 else if (c in 0xD800..0xDFFF) 2 else 3
        }
        return bytesBase + scanBytes
    }

    private fun next(): Int = peek().also { if (it >= 0) pos++ }

    private fun fail(why: String): Nothing =
        throw ManifestStageException.Invalid("$why (at character ${base + pos})", syntactic = true)

    private fun defer(reason: String) {
        if (deferred == null) deferred = reason
    }

    private fun ws() {
        while (true) {
            when (peek()) {
                ' '.code, '\t'.code, '\n'.code, '\r'.code -> pos++
                else -> return
            }
        }
    }

    fun parseDocument() {
        if (peek() == BOM) pos++
        ws()
        val arrayRoot = peek() == '['.code
        if (arrayRoot) {
            muted = true
            skipValue() // a complete array is well-formed JSON: it is a schema failure, not a syntax error
        } else {
            if (peek() != '{'.code) fail("the document is not an object")
            value(0)
        }
        ws()
        if (peek() != -1) fail("unexpected content after the document")
        deferred?.let { throw ManifestStageException.ResourceExhausted(it) }
        if (arrayRoot) throw ManifestStageException.Invalid("the document is an array, not an object", syntactic = false)
    }

    /** Depth beyond the ceiling is a resource outcome, but the rest of the document is still scanned (no events, no retention) so a malformed tail reports syntax first. */
    private fun tooDeep() {
        defer("nesting is deeper than $MAX_DEPTH containers")
        muted = true
        skipValue()
    }

    private fun skipKey() {
        ws()
        if (peek() != '"'.code) fail("expected a quoted key")
        key()
        ws()
        if (next() != ':'.code) fail("expected ':'")
    }

    /** Validates one value (at the current position) without recursion or events: a stack of one bit per open container. */
    private fun skipValue() {
        val isObject = java.util.BitSet()
        var sp = 0
        var expectValue = true
        while (true) {
            if (expectValue) {
                ws()
                when (peek()) {
                    '{'.code -> {
                        pos++; isObject.set(sp++); ws()
                        if (peek() == '}'.code) { pos++; sp--; expectValue = false } else skipKey()
                    }
                    '['.code -> {
                        pos++; isObject.clear(sp++); ws()
                        if (peek() == ']'.code) { pos++; sp--; expectValue = false }
                    }
                    '"'.code -> { string(); expectValue = false }
                    else -> { scalar(); expectValue = false }
                }
            } else {
                if (sp == 0) return
                ws()
                val obj = isObject[sp - 1]
                val c = next()
                when {
                    c == ','.code -> {
                        ws()
                        if (peek() == (if (obj) '}'.code else ']'.code)) { pos++; sp-- } else { if (obj) skipKey(); expectValue = true }
                    }
                    c == (if (obj) '}'.code else ']'.code) -> sp--
                    else -> fail(if (obj) "expected ',' or '}'" else "expected ',' or ']'")
                }
            }
        }
    }

    private fun value(depth: Int) {
        ws()
        valueStart = sourceBytes()
        when (peek()) {
            '{'.code -> {
                if (depth + 1 > MAX_DEPTH) { tooDeep(); return }
                pos++
                if (!muted) events.beginObject()
                ws()
                if (peek() == '}'.code) {
                    pos++
                } else {
                    var members = 0
                    while (true) {
                        ws()
                        if (peek() != '"'.code) fail("expected a quoted key")
                        if (++members == MAX_MEMBERS + 1) {
                            defer("an object has more than $MAX_MEMBERS members")
                            muted = true // the resource outcome is decided; validate the tail without staging more keys
                        }
                        key().let { if (!muted) events.name(it) }
                        ws()
                        if (next() != ':'.code) fail("expected ':'")
                        value(depth + 1)
                        ws()
                        when (next()) {
                            ','.code -> {
                                ws()
                                if (peek() == '}'.code) { pos++; break } // trailing comma
                            }
                            '}'.code -> break
                            else -> fail("expected ',' or '}'")
                        }
                    }
                }
                if (!muted) events.endObject()
            }
            '['.code -> {
                if (depth + 1 > MAX_DEPTH) { tooDeep(); return }
                pos++
                if (!muted) events.beginArray()
                ws()
                if (peek() == ']'.code) {
                    pos++
                } else {
                    while (true) {
                        value(depth + 1)
                        ws()
                        when (next()) {
                            ','.code -> {
                                ws()
                                if (peek() == ']'.code) { pos++; break } // trailing comma
                            }
                            ']'.code -> break
                            else -> fail("expected ',' or ']'")
                        }
                    }
                }
                if (!muted) events.endArray()
            }
            '"'.code -> string()
            else -> scalar().let { if (!muted) events.literal(it) }
        }
    }

    private fun digits(): Int {
        var n = 0
        while (peek() in '0'.code..'9'.code) { take(); n++ }
        return n
    }

    /** Appends the current char to the token (until the limit; past it the char is only validated) and consumes it. */
    private fun take() {
        val c = next()
        if (token.length < MAX_TOKEN) token.append(c.toChar()) else defer("a number is longer than $MAX_TOKEN characters")
    }

    /** `true`, `false`, `null`, or a number scanned with the JSON grammar: `-? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?`. */
    private fun scalar(): String {
        token.setLength(0)
        val first = peek()
        if (first == 't'.code || first == 'f'.code || first == 'n'.code) {
            while (peek() in 'a'.code..'z'.code && token.length < 8) take()
            val word = token.toString()
            if (word != "true" && word != "false" && word != "null") fail("not a JSON value: $word")
            return word
        }
        if (first == '-'.code) take()
        when (peek()) {
            '0'.code -> take()
            in '1'.code..'9'.code -> digits()
            else -> fail("expected a value")
        }
        if (peek() == '.'.code) {
            take()
            if (digits() == 0) fail("a fraction needs digits")
        }
        if (peek() == 'e'.code || peek() == 'E'.code) {
            take()
            if (peek() == '+'.code || peek() == '-'.code) take()
            if (digits() == 0) fail("an exponent needs digits")
        }
        return token.toString()
    }

    private fun key(): String {
        val sb = StringBuilder()
        keySink = sb
        keyOverflow = false
        string()
        keySink = null
        return sb.toString()
    }

    private fun put(c: Char) {
        if (chunkLen == chunk.size) flush(false)
        chunk[chunkLen++] = c
    }

    private fun flush(last: Boolean) {
        var n = chunkLen
        val carry = !last && n > 0 && Character.isHighSurrogate(chunk[n - 1])
        if (carry) n--
        val sink = keySink
        if (sink != null) {
            if (!keyOverflow) {
                sink.append(chunk, 0, n)
                if (sink.length > MAX_KEY) {
                    keyOverflow = true
                    defer("an object key is longer than $MAX_KEY UTF-16 code units")
                }
            }
        } else {
            if (!muted) events.stringChunk(chunk, 0, n, last)
        }
        if (carry) {
            chunk[0] = chunk[n]
            chunkLen = 1
        } else {
            chunkLen = 0
        }
    }

    private fun hex4(): Int {
        var v = 0
        repeat(4) {
            val c = next()
            val h = when (c) {
                in '0'.code..'9'.code -> c - '0'.code
                in 'a'.code..'f'.code -> c - 'a'.code + 10
                in 'A'.code..'F'.code -> c - 'A'.code + 10
                else -> fail("bad \\u escape")
            }
            v = v * 16 + h
        }
        return v
    }

    private fun string() {
        next() // opening quote
        chunkLen = 0
        while (true) {
            val c = next()
            when {
                c < 0 -> fail("unterminated string")
                c == '"'.code -> { flush(true); return }
                c < 0x20 -> fail("raw control character in a string")
                c == '\\'.code -> {
                    when (val e = next()) {
                        '"'.code -> put('"')
                        '\\'.code -> put('\\')
                        '/'.code -> put('/')
                        'b'.code -> put('\b')
                        'f'.code -> put('\u000c')
                        'n'.code -> put('\n')
                        'r'.code -> put('\r')
                        't'.code -> put('\t')
                        'u'.code -> {
                            val v = hex4()
                            if (v in 0xD800..0xDBFF) {
                                if (next() != '\\'.code || next() != 'u'.code) fail("a high surrogate escape is not followed by a low one")
                                val lo = hex4()
                                if (lo !in 0xDC00..0xDFFF) fail("a high surrogate escape is not followed by a low one")
                                put(v.toChar())
                                put(lo.toChar())
                            } else if (v in 0xDC00..0xDFFF) {
                                fail("a low surrogate escape without a high one")
                            } else {
                                put(v.toChar())
                            }
                        }
                        else -> fail("bad escape \\${if (e < 0) "<end>" else e.toChar().toString()}")
                    }
                }
                else -> put(c.toChar())
            }
        }
    }

    companion object {
        const val CHUNK = 8 * 1024
        const val MAX_KEY = 64 * 1024
        const val MAX_TOKEN = 64 * 1024
        const val MAX_DEPTH = 512
        const val MAX_MEMBERS = 262_144
        private const val BOM = 0xFEFF
    }
}
