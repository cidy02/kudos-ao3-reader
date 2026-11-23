package io.github.cidy02.kudos.backup.streaming

import java.io.ByteArrayInputStream
import java.io.IOException
import java.io.InputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** The shared input contract (BOM, trailing commas, lone surrogate, scalar root, depth 512) and bounded streaming, tokenizer only. */
class ManifestTokenizerTest {
    /** Flattens events to a trace; string chunks are joined, and the largest chunk is recorded. */
    private class Trace : ManifestEvents {
        val events = mutableListOf<String>()
        var maxChunk = 0
        var chunks = 0
        var endsInHighSurrogate = false
        private val sb = StringBuilder()
        override fun beginObject() { events += "{" }
        override fun endObject() { events += "}" }
        override fun beginArray() { events += "[" }
        override fun endArray() { events += "]" }
        override fun name(name: String) { events += "k:$name" }
        override fun stringChunk(buffer: CharArray, offset: Int, length: Int, last: Boolean) {
            maxChunk = maxOf(maxChunk, length); chunks++
            if (length > 0 && Character.isHighSurrogate(buffer[offset + length - 1])) endsInHighSurrogate = true
            sb.append(buffer, offset, length)
            if (last) { events += "s:$sb"; sb.setLength(0) }
        }
        override fun literal(text: String) { events += "l:$text" }
    }

    private fun parse(bytes: ByteArray, trace: Trace = Trace()): Trace {
        ManifestTokenizer(ByteArrayInputStream(bytes), trace).parseDocument()
        return trace
    }

    private fun parse(text: String) = parse(text.toByteArray())

    private fun invalid(text: String, syntactic: Boolean = true) = invalid(text.toByteArray(), text.take(40), syntactic)

    private fun invalid(bytes: ByteArray, label: String, syntactic: Boolean = true) {
        try {
            parse(bytes)
            fail("accepted: $label")
        } catch (e: ManifestStageException.Invalid) {
            assertEquals(label, syntactic, e.syntactic)
        }
    }

    @Test fun acceptsALeadingBomButOnlyAtTheStart() {
        val bom = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte())
        assertEquals(listOf("{", "}"), parse(bom + "{}".toByteArray()).events)
        invalid(" ".toByteArray() + bom + "{}".toByteArray(), "BOM after whitespace")
        invalid("{}".toByteArray() + bom, "BOM after the document")
        invalid(bom + bom + "{}".toByteArray(), "two BOMs")
    }

    @Test fun acceptsOneTrailingCommaInObjectsAndArrays() {
        assertEquals(listOf("{", "k:a", "[", "l:1", "l:2", "]", "k:b", "l:3", "}"), parse("""{"a":[1,2,],"b":3,}""").events)
    }

    @Test fun rejectsDoubledOrLeadingCommas() {
        for (text in listOf("""{"a":1,,}""", """{,}""", """{"a":[,]}""", """{"a":[1,,2]}""", """{"a":[,1]}""", """{"a":1,,"b":2}""")) invalid(text)
    }

    @Test fun rejectsATopLevelScalarArrayOrNothing() {
        for (text in listOf("", " \n", "5", "\"x\"", "null", "true")) invalid(text)
        // a complete array is well-formed JSON but not a manifest: schema, not syntax
        for (text in listOf("[]", "[{}]", " [1,[2,{\"a\":[]}],]  ")) invalid(text, syntactic = false)
        for (text in listOf("[", "[1,", "[] x", "[1 2]", "[{\"a\"}]")) invalid(text)
    }

    @Test fun rejectsAnyContentAfterTheDocument() {
        for (text in listOf("{}x", "{}{}", "{},", "{}}", "{}\u0000", "{} 1")) invalid(text)
        assertEquals(listOf("{", "}"), parse("{}  \n\r\t").events)
    }

    @Test fun rejectsLoneSurrogateEscapes() {
        for (text in listOf("""{"a":"\ud800"}""", """{"a":"\udc00"}""", """{"a":"\ud800x"}""", """{"a":"\ud800\u0041"}""", """{"a":"\udc00\ud800"}""", """{"\ud800":1}""")) invalid(text)
        assertEquals("s:\uD83D\uDE00", parse("""{"a":"\ud83d\ude00"}""").events[2])
    }

    @Test fun dropsTodaysLenientSyntax() {
        val lenient = listOf(
            "{'a':1}", """{"a":'x'}""", """{"a":1 /* c */}""", "{\"a\":1 // c\n}", """{a:1}""", """{"a":x}""", """{"a";1}""",
            """{"a"=1}""", """{"a":1;"b":2}""", """{"a":1 "b":2}""", """{"a" 1}""", """{"a":NaN}""", """{"a":Infinity}""",
            """{"a":+1}""", """{"a":.5}""", """{"a":-}""", """{"a":01}""", """{"a":1.}""", """{"a":1e}""", """{"a":-01}""",
            """{"a":TRUE}""", """{"a":nul}"""
        )
        for (text in lenient) invalid(text)
        assertEquals(listOf("{", "k:a", "l:-0.5e+10", "k:b", "l:0", "}"), parse("""{"a":-0.5e+10,"b":0}""").events)
    }

    @Test fun nestingLimitIsFiveHundredTwelveContainers() {
        fun nested(containers: Int) = "{\"a\":" + "[".repeat(containers - 1) + "]".repeat(containers - 1) + "}" // the root object counts as one
        assertEquals(1025, parse(nested(512)).events.size) // {, k:a, 511 x [, 511 x ], } : 512 containers are accepted
        for (doc in listOf(nested(513), "{\"a\":" + "{\"a\":".repeat(600) + "1" + "}".repeat(600) + "}")) {
            try { parse(doc); fail("accepted") } catch (e: ManifestStageException.ResourceExhausted) { /* depth policy is a resource outcome, not malformed */ }
        }
    }

    @Test fun scanningContinuesPastTheDepthLimitSoAMalformedTailReportsSyntax() {
        val deep = "{\"a\":" + "[".repeat(600) + "]".repeat(600)
        invalid("$deep,\"b\":}")                 // malformed after the deep value
        invalid("{\"a\":" + "[".repeat(100_000)) // unterminated deep value
        invalid("{\"a\":" + "[".repeat(600) + "]".repeat(599) + "}")  // one close short
        invalid("{\"a\":" + "[".repeat(600) + "}".repeat(600) + "}") // mismatched brackets
        invalid("{\"a\":" + "[".repeat(600) + "]".repeat(87) + "}" + "]".repeat(512) + "}") // a mismatch inside the skipped part
        invalid("{\"a\":" + "[".repeat(520) + "]".repeat(7) + "}" + "]".repeat(512) + "}")
        invalid("{\"a\":" + "{\"k\":".repeat(600) + "1" + "}".repeat(600) + ",}x")
        try { parse("$deep}"); fail("accepted") } catch (e: ManifestStageException.ResourceExhausted) { /* a complete deep file is resource, not syntax */ }
        val t = Trace()
        try { ManifestTokenizer(ByteArrayInputStream("{\"a\":[1],\"b\":${"[".repeat(600)}${"]".repeat(600)},\"c\":2}".toByteArray()), t).parseDocument() } catch (e: ManifestStageException.ResourceExhausted) { }
        assertTrue("no event after the limit was hit", t.events.none { it == "k:c" || it == "l:2" })
    }

    @Test fun stringsLeaveInBoundedPiecesAndNeverSplitASurrogatePair() {
        val emoji = "\uD83D\uDE00"
        for (pad in listOf(ManifestTokenizer.CHUNK - 2, ManifestTokenizer.CHUNK - 1, ManifestTokenizer.CHUNK, ManifestTokenizer.CHUNK + 1)) {
            val raw = "a".repeat(pad) + emoji + "b".repeat(100)
            val escaped = "a".repeat(pad) + "\\ud83d\\ude00" + "b".repeat(100)
            for (body in listOf(raw, escaped)) {
                val t = parse("{\"k\":\"$body\"}")
                assertEquals("pad=$pad", "s:${"a".repeat(pad)}$emoji${"b".repeat(100)}", t.events.last { it.startsWith("s:") })
                assertTrue(t.maxChunk <= ManifestTokenizer.CHUNK)
                assertFalse("pad=$pad split a pair", t.endsInHighSurrogate)
            }
        }
        val big = parse("{\"k\":\"" + "x".repeat(5_000_000) + "\"}")
        assertTrue(big.maxChunk <= ManifestTokenizer.CHUNK)
        assertTrue(big.chunks >= 5_000_000 / ManifestTokenizer.CHUNK)
    }

    @Test fun rawControlCharactersAndMalformedUtf8AreSyntaxErrors() {
        for (c in listOf(0x00, 0x09, 0x0A, 0x0D, 0x1F)) invalid("{\"k\":\"a${c.toChar()}b\"}".toByteArray(), "raw U+%04X".format(c))
        invalid("{\"k\":\"T".toByteArray() + byteArrayOf(0xFF.toByte()) + "\"}".toByteArray(), "byte FF")
        invalid("{\"k\":\"T".toByteArray() + byteArrayOf(0xE2.toByte()) + "\"}".toByteArray(), "truncated sequence")
        invalid("{\"k\":\"T".toByteArray() + byteArrayOf(0xC0.toByte(), 0xAF.toByte()) + "\"}".toByteArray(), "overlong")
        invalid("{\"k".toByteArray() + byteArrayOf(0xED.toByte(), 0xA0.toByte(), 0x80.toByte()) + "\":1}".toByteArray(), "encoded surrogate in a key")
        invalid("{\"k\":\"T".toByteArray() + byteArrayOf(0xE2.toByte()), "truncated sequence at EOF")
        assertEquals("s:a\\nb", parse("{\"k\":\"a\\nb\"}").events.last { it.startsWith("s:") }.replace("\n", "\\n"))
    }

    @Test fun escapeDigitsAreAsciiOnly() {
        invalid("{\"k\":\"\\u\uFF10\uFF10\uFF14\uFF11\"}")
        invalid("{\"k\":\"\\u00g1\"}")
        assertEquals("s:AA", parse("{\"k\":\"\\u0041\\u0041\"}").events.last { it.startsWith("s:") })
        assertEquals("s:\u00ab", parse("{\"k\":\"\\u00aB\"}").events.last { it.startsWith("s:") })
    }

    @Test fun aBomSplitAcrossReadsIsStillABom() {
        val doc = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte()) + "{\"a\":1}".toByteArray()
        val oneByteAtATime = object : InputStream() {
            var i = 0
            override fun read(): Int = if (i < doc.size) doc[i++].toInt() and 0xFF else -1
            override fun read(b: ByteArray, off: Int, len: Int): Int { val c = read(); if (c < 0) return -1; b[off] = c.toByte(); return 1 }
        }
        val t = Trace()
        ManifestTokenizer(oneByteAtATime, t).parseDocument()
        assertEquals(listOf("{", "k:a", "l:1", "}"), t.events)
    }

    @Test fun numbersAreScannedByGrammarAndBoundedWithoutBecomingBareWords() {
        for (ok in listOf("0", "-0", "7", "-12", "1.5", "1e5", "1E+5", "1.5e-3", "0.0")) assertEquals("l:$ok", parse("{\"k\":$ok}").events[2])
        for (bad in listOf("-", "-a", "1.", ".1", "1e", "1e+", "0x1", "1_0", "00", "-01", "1.2.3")) invalid("{\"k\":$bad}")
        assertEquals(2 + 65_536, parse("{\"k\":" + "1".repeat(65_536) + "}").events[2].length)
        try { parse("{\"k\":" + "1".repeat(65_537) + "}"); fail("accepted") } catch (e: ManifestStageException.ResourceExhausted) { /* expected */ }
        invalid("{\"k\":" + "a".repeat(65_537) + "}") // a bare word is syntax, not an oversized number
    }

    @Test fun membersAreCountedBeforeDuplicateRemovalAtEveryDepth() {
        fun members(n: Int) = "\"a\":0,".repeat(n - 1) + "\"a\":0"
        parse("{${members(ManifestTokenizer.MAX_MEMBERS)}}")
        for (doc in listOf("{${members(ManifestTokenizer.MAX_MEMBERS + 1)}}", "{\"x\":{${members(ManifestTokenizer.MAX_MEMBERS + 1)}}}", "{\"x\":0,\"x\":{${members(ManifestTokenizer.MAX_MEMBERS + 1)}}}")) {
            try { parse(doc); fail("accepted") } catch (e: ManifestStageException.ResourceExhausted) { /* expected */ }
        }
    }

    @Test fun aKeyIsMeasuredInUtf16UnitsOfItsDecodedValue() {
        parse("{\"" + "a".repeat(ManifestTokenizer.MAX_KEY) + "\":1}")
        parse("{\"" + "\uD83D\uDE00".repeat(ManifestTokenizer.MAX_KEY / 2) + "\":1}")
        parse("{\"" + "\\ud83d\\ude00".repeat(ManifestTokenizer.MAX_KEY / 2) + "\":1}")
        for (key in listOf("a".repeat(ManifestTokenizer.MAX_KEY + 1), "\uD83D\uDE00".repeat(ManifestTokenizer.MAX_KEY / 2) + "a")) {
            try { parse("{\"$key\":1}"); fail("accepted") } catch (e: ManifestStageException.ResourceExhausted) { /* expected */ }
        }
    }

    @Test fun aMalformedTailReportsSyntaxEvenAfterALimitWasHit() {
        invalid("{\"" + "k".repeat(ManifestTokenizer.MAX_KEY + 1) + "\":1} x")
        invalid("{\"k\":" + "1".repeat(65_537) + ",}}")
    }

    @Test fun unterminatedAndTruncatedInputIsInvalid() {
        for (text in listOf("{", "{\"a\"", "{\"a\":", "{\"a\":1", "{\"a\":[", "{\"a\":\"x", "{\"a\":\"x\\", "{\"a\":\"\\u12")) invalid(text)
    }

    @Test fun readsToEofBeforeReturningSoALateErrorStillFails() {
        invalid("""{"version":99,"works":[]} trailing""")
        invalid("""{"works":[{"id":"x"}],"version":8""")
    }

    @Test fun anIoFailureIsItsOwnOutcome() {
        val failing = object : InputStream() {
            var n = 0
            override fun read(): Int = if (n++ < 20) '{'.code else throw IOException("boom")
            override fun read(b: ByteArray, off: Int, len: Int): Int {
                if (n++ > 0) throw IOException("boom")
                val text = "{\"a\":[1,2,3,".toByteArray()
                System.arraycopy(text, 0, b, off, text.size)
                return text.size
            }
        }
        try {
            ManifestTokenizer(failing, Trace()).parseDocument()
            fail("no failure")
        } catch (e: ManifestStageException.Io) {
            assertEquals("boom", e.cause?.message)
        }
    }

    @Test fun cancellationStopsWithinOneReadBuffer() {
        val doc = "{\"a\":[" + "1,".repeat(2_000_000) + "1]}"
        var reads = 0
        val counting = object : InputStream() {
            val inner = ByteArrayInputStream(doc.toByteArray())
            override fun read(): Int = inner.read()
            override fun read(b: ByteArray, off: Int, len: Int): Int = inner.read(b, off, len).also { reads++ }
        }
        try {
            ManifestTokenizer(counting, Trace(), isCancelled = { reads >= 40 }).parseDocument()
            fail("not cancelled")
        } catch (e: ManifestStageException.Cancelled) {
            assertEquals("no read after the cancel was seen", 40, reads)
        }
    }
}
