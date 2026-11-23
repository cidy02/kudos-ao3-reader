package io.github.cidy02.kudos.backup.streaming

import java.io.IOException
import java.io.InputStream
import java.io.InputStreamReader

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

/**
 * The shared manifest input contract (owner decision, REDESIGN_DECISIONS 2026-11-22), as a chunked
 * tokenizer over a UTF-8 stream with a fixed 16 KiB read buffer:
 *  - strict RFC 8259 syntax, plus a leading UTF-8 BOM and trailing commas in objects and arrays;
 *  - the root must be an object; any trailing content after it (other than whitespace) is invalid;
 *  - an escaped surrogate must be a high/low pair, a lone one is invalid;
 *  - nesting deeper than [MAX_DEPTH] containers is invalid;
 *  - no single-quoted strings, comments, `;` or `=` separators, unquoted keys or values;
 *  - malformed UTF-8 bytes decode to U+FFFD and raw control characters inside strings are accepted,
 *    both as in today's Android route.
 * Duplicate keys are not decided here (the consumer sees every `name`); the staging sink keeps the first.
 * The whole document is read to EOF before [parseDocument] returns.
 */
internal class ManifestTokenizer(
    input: InputStream,
    private val events: ManifestEvents,
    private val isCancelled: () -> Boolean = { false }
) {
    private val reader = InputStreamReader(input, Charsets.UTF_8)
    private val buf = CharArray(16 * 1024)
    private var pos = 0
    private var lim = 0
    private var base = 0L
    private val chunk = CharArray(CHUNK)
    private var chunkLen = 0
    private var keySink: StringBuilder? = null
    private val token = StringBuilder()

    private fun peek(): Int {
        while (pos == lim) {
            if (isCancelled()) throw ManifestStageException.Cancelled()
            val n = try {
                reader.read(buf, 0, buf.size)
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

    private fun next(): Int = peek().also { if (it >= 0) pos++ }

    private fun fail(why: String): Nothing =
        throw ManifestStageException.Invalid("$why (at character ${base + pos})", syntactic = true)

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
        if (peek() != '{'.code) fail("the document is not an object")
        value(0)
        ws()
        if (peek() != -1) fail("unexpected content after the document")
    }

    private fun value(depth: Int) {
        ws()
        when (peek()) {
            '{'.code -> {
                if (depth + 1 > MAX_DEPTH) fail("nesting is deeper than $MAX_DEPTH")
                pos++
                events.beginObject()
                ws()
                if (peek() == '}'.code) {
                    pos++
                } else {
                    while (true) {
                        ws()
                        if (peek() != '"'.code) fail("expected a quoted key")
                        events.name(key())
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
                events.endObject()
            }
            '['.code -> {
                if (depth + 1 > MAX_DEPTH) fail("nesting is deeper than $MAX_DEPTH")
                pos++
                events.beginArray()
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
                events.endArray()
            }
            '"'.code -> string()
            else -> events.literal(scalar())
        }
    }

    private fun scalar(): String {
        token.setLength(0)
        while (true) {
            val c = peek()
            val ok = c >= 'a'.code && c <= 'z'.code || c >= 'A'.code && c <= 'Z'.code ||
                c >= '0'.code && c <= '9'.code || c == '-'.code || c == '+'.code || c == '.'.code
            if (!ok) break
            pos++
            token.append(c.toChar())
            if (token.length > MAX_TOKEN) {
                throw ManifestStageException.ResourceExhausted("a number is longer than $MAX_TOKEN characters")
            }
        }
        val text = token.toString()
        if (text.isEmpty()) fail("expected a value")
        if (text != "true" && text != "false" && text != "null" && !isJsonNumber(text)) fail("not a JSON value: ${text.take(24)}")
        return text
    }

    /** `-? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?` */
    private fun isJsonNumber(s: String): Boolean {
        var i = 0
        val n = s.length
        if (i < n && s[i] == '-') i++
        if (i >= n) return false
        if (s[i] == '0') {
            i++
        } else if (s[i] in '1'..'9') {
            while (i < n && s[i] in '0'..'9') i++
        } else {
            return false
        }
        if (i < n && s[i] == '.') {
            i++
            val start = i
            while (i < n && s[i] in '0'..'9') i++
            if (i == start) return false
        }
        if (i < n && (s[i] == 'e' || s[i] == 'E')) {
            i++
            if (i < n && (s[i] == '+' || s[i] == '-')) i++
            val start = i
            while (i < n && s[i] in '0'..'9') i++
            if (i == start) return false
        }
        return i == n
    }

    private fun key(): String {
        val sb = StringBuilder()
        keySink = sb
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
            sink.append(chunk, 0, n)
            if (sink.length > MAX_KEY) throw ManifestStageException.ResourceExhausted("an object key is longer than $MAX_KEY characters")
        } else {
            events.stringChunk(chunk, 0, n, last)
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
            val h = Character.digit(next(), 16)
            if (h < 0) fail("bad \\u escape")
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
        private const val BOM = 0xFEFF
    }
}
