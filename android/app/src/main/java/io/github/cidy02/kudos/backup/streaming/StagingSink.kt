package io.github.cidy02.kudos.backup.streaming

import io.github.cidy02.kudos.backup.BackupJson
import java.io.InputStream
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.decodeFromStream

/** A compact-JSON text being built: held in memory while small, written to chunk rows (addressed by char offset) once it grows. */
internal class StagedText(private val w: StagingWriter, private val chunkTable: String, private val ord: Long, private val overBudget: () -> Boolean = { false }) {
    val sb = StringBuilder()
    private var written = 0L
    var spilled = false
        private set

    /** Chars appended so far, including any already written to the database. */
    var length = 0L
        private set

    fun append(c: Char) { sb.append(c); length++; grown() }
    fun append(s: String) { sb.append(s); length += s.length; grown() }

    fun appendQuoted(s: String) {
        sb.append('"'); length++
        escape(s, 0, s.length)
        sb.append('"'); length++
        grown()
    }

    fun appendEscaped(b: CharArray, off: Int, len: Int) { escape(b, off, len); grown() }

    private fun escape(s: String, off: Int, len: Int) {
        val before = sb.length
        for (i in off until off + len) put(s[i])
        length += sb.length - before
    }

    private fun escape(b: CharArray, off: Int, len: Int) {
        val before = sb.length
        for (i in off until off + len) put(b[i])
        length += sb.length - before
    }

    private fun put(c: Char) {
        when {
            c == '"' -> sb.append("\\\"")
            c == '\\' -> sb.append("\\\\")
            c == '\b' -> sb.append("\\b")
            c == '\u000c' -> sb.append("\\f")
            c == '\n' -> sb.append("\\n")
            c == '\r' -> sb.append("\\r")
            c == '\t' -> sb.append("\\t")
            c < ' ' -> { sb.append("\\u00"); sb.append(HEX[c.code shr 4]); sb.append(HEX[c.code and 15]) }
            else -> sb.append(c)
        }
    }

    private fun grown() {
        if (overBudget()) { sb.setLength(0); return }
        if (!spilled && sb.length <= SPILL_AT) return
        spilled = true
        while (sb.length >= StagingWriter.CHUNK_CHARS) writeChunk(StagingWriter.CHUNK_CHARS)
    }

    private fun writeChunk(max: Int) {
        var cut = minOf(max, sb.length)
        if (cut > 1 && Character.isHighSurrogate(sb[cut - 1])) cut-- // never split a pair across rows
        w.chunk(chunkTable, ord, written, sb.substring(0, cut))
        written += cut
        sb.delete(0, cut)
    }

    /** Writes whatever is left. */
    fun close() {
        while (sb.isNotEmpty()) writeChunk(StagingWriter.CHUNK_CHARS)
    }

    companion object {
        /** Elements up to this many chars are held in memory until complete; larger ones stream to chunk rows as they grow. */
        const val SPILL_AT = 1 shl 20
        private val HEX = "0123456789abcdef".toCharArray()
    }
}

/**
 * Turns tokenizer events into staging rows. Duplicate keys (at any depth) keep the first value: the later
 * value is read and validated but not staged. Memory is bounded by [StagedText.SPILL_AT], the 16 KiB read
 * buffer, one key set per open object (all together under [MAX_LIVE_KEY_CHARS]) and, while one record is
 * decoded, the record itself (at most [TYPED_BUDGET_BYTES] of source). Resource limits found here are
 * remembered in [resourceFailure] and thrown by the caller once the whole document has been read.
 */
internal class StagingSink(
    private val w: StagingWriter,
    private val src: SourcePosition,
    private val onRecordStaged: (Long) -> Unit,
    private val tick: () -> Unit
) : ManifestEvents {
    private class Frame(val isObject: Boolean, val kind: Int) {
        var count = 0
        var keys: HashSet<String>? = null
        var keyChars = 0L
    }

    private val stack = ArrayList<Frame>()
    private var skipBase = -1
    private var liveKeyChars = 0L

    private var rootKey = ""
    private var rootOrd = 0L
    private var rootKind = ""
    private var rootStart = 0L
    private var rootSection: SectionSpec? = null
    private var sectionOrd = 0L
    private var elementStart = 0L
    private var out: StagedText? = null
    private var elementKind = ""
    private var inString = false

    private var field: String? = null
    private var fieldStart = 0L
    private var capturing = false
    private val capBuf = StringBuilder()
    private var capOverflow = false
    private val captured = HashMap<String, String?>()
    private val unknowns = ArrayList<Triple<String, Long, Long>>()

    /** First typed-decode failure; decided after EOF so I/O, cancellation, syntax and resource outcomes keep precedence. */
    var pendingFailure: String? = null
        private set

    /** First resource limit hit here (record over the typed budget, root value over its limit, key memory). */
    var resourceFailure: String? = null
        private set
    var records = 0L
        private set

    private fun resource(reason: String) {
        if (resourceFailure == null) resourceFailure = reason
    }

    private fun skipping() = skipBase >= 0

    private fun kindOf(text: String) = when (text[0]) { 't', 'f' -> "bool"; 'n' -> "null"; else -> "number" }

    private fun startValue(kind: String) {
        val top = stack.last()
        when (top.kind) {
            ROOT -> {
                rootKind = kind
                rootStart = src.valueStart
                val section = ManifestSections.byName[rootKey]
                if (section != null && kind == "array") {
                    rootSection = section
                    sectionOrd = 0
                    out = null
                } else {
                    rootSection = null
                    val boundedValue = rootKey in ManifestSections.knownRootKeys ||
                        (rootKey in IOS_LOSSY_ROOT_KEYS && kind != "array")
                    out = StagedText(w, "root_chunk", rootOrd) {
                        if (boundedValue && src.sourceBytes() - rootStart > MAX_ROOT_VALUE_BYTES) {
                            resource("the value of '$rootKey' is larger than $MAX_ROOT_VALUE_BYTES source bytes")
                            true
                        } else false
                    }
                }
            }
            SECTION -> {
                val s = rootSection!!
                out = StagedText(w, s.chunkTable, sectionOrd) {
                    if (src.sourceBytes() - elementStart > TYPED_BUDGET_BYTES) {
                        resource("a ${s.name} record is larger than the typed budget of $TYPED_BUDGET_BYTES bytes")
                        true
                    } else false
                }
                elementKind = kind
                elementStart = src.valueStart
                captured.clear()
                unknowns.clear()
                field = null
            }
            else -> {
                if (!top.isObject) {
                    if (top.count++ > 0) out!!.append(',')
                } else if (top.kind == RECORD) {
                    val f = field!!
                    capturing = (kind == "string" || kind == "number" || kind == "bool") && rootSection!!.keys.any { it.field == f }
                    capBuf.setLength(0)
                    capOverflow = false
                }
            }
        }
    }

    private fun endValue() {
        when (stack.last().kind) {
            ROOT -> finishRoot()
            SECTION -> finishElement()
            RECORD -> endField()
        }
    }

    private fun endField() {
        val f = field ?: return
        val o = out!!
        if (f !in rootSection!!.knownFields) unknowns += Triple(f, fieldStart, o.length)
        if (capturing) captured[f] = if (capOverflow) null else capBuf.toString()
        capturing = false
        field = null
    }

    private fun finishElement() {
        val spec = rootSection!!
        val o = out!!
        val ord = sectionOrd
        val sourceBytes = src.sourceBytes() - elementStart
        val oversize = o.spilled
        var typedOk = 0
        when {
            sourceBytes > TYPED_BUDGET_BYTES -> resource("a ${spec.name} record is larger than the typed budget of $TYPED_BUDGET_BYTES bytes")
            else -> {
                typedOk = if (oversize) {
                    o.close()
                    w.openTextStream(spec.chunkTable, ord).use { if (decodes(spec.serializer, it)) 1 else 0 }
                } else {
                    if (decodes(spec.serializer, o.sb.toString())) 1 else 0
                }
                if (typedOk == 0 && pendingFailure == null) pendingFailure = "${spec.name}[$ord] is not a valid ${spec.name} record"
            }
        }
        o.close()
        val keys = spec.keys.map { k -> k.make(captured[k.field]) }
        w.record(spec, ord, elementKind, o.length, sourceBytes, oversize, typedOk, keys)
        for ((name, start, stop) in unknowns) w.unknown(spec.name, ord, name, start, stop)
        sectionOrd++
        records++
        out = null
        tick()
        onRecordStaged(records)
    }

    private fun finishRoot() {
        val section = rootSection
        if (section != null) {
            w.root(rootOrd, rootKey, "records", true, false, 0, sectionOrd)
        } else {
            val o = out!!
            val oversize = o.spilled
            o.close()
            val known = rootKey in ManifestSections.knownRootKeys
            val boundedValue = known || (rootKey in IOS_LOSSY_ROOT_KEYS && rootKind != "array")
            if (boundedValue && src.sourceBytes() - rootStart > MAX_ROOT_VALUE_BYTES) {
                resource("the value of '$rootKey' is larger than $MAX_ROOT_VALUE_BYTES source bytes")
            }
            w.root(rootOrd, rootKey, rootKind, known, oversize, o.length, 0)
        }
        rootOrd++
        rootSection = null
        out = null
        tick()
    }

    /** The compact staged JSON has already passed strict tokenization and first-wins filtering. */
    @Suppress("UNCHECKED_CAST")
    private fun decodes(serializer: KSerializer<*>, text: String): Boolean = try {
        BackupJson.decodeFromString(serializer as KSerializer<Any>, text)
        true
    } catch (_: SerializationException) {
        false
    } catch (_: IllegalArgumentException) {
        false
    }

    @OptIn(ExperimentalSerializationApi::class)
    @Suppress("UNCHECKED_CAST")
    private fun decodes(serializer: KSerializer<*>, stream: InputStream): Boolean = try {
        BackupJson.decodeFromStream(serializer as KSerializer<Any>, stream)
        true
    } catch (_: SerializationException) {
        false
    } catch (_: IllegalArgumentException) {
        false
    }

    override fun beginObject() {
        if (resourceFailure != null) return
        if (stack.isEmpty()) { stack += Frame(true, ROOT); return }
        if (skipping()) { stack += Frame(true, PLAIN); return }
        val parent = stack.last().kind
        startValue("object")
        out!!.append('{')
        stack += Frame(true, if (parent == SECTION) RECORD else PLAIN)
    }

    private fun pop(): Frame {
        val frame = stack.removeAt(stack.size - 1)
        liveKeyChars -= frame.keyChars
        return frame
    }

    override fun endObject() {
        if (resourceFailure != null) return
        if (skipping()) { pop(); if (stack.size == skipBase) skipBase = -1; return }
        val frame = pop()
        if (frame.kind == ROOT) return
        out!!.append('}')
        if (resourceFailure != null) return
        endValue()
    }

    override fun beginArray() {
        if (resourceFailure != null) return
        if (skipping()) { stack += Frame(false, PLAIN); return }
        val parent = stack.last().kind
        startValue("array")
        if (parent == ROOT && rootSection != null) {
            stack += Frame(false, SECTION)
        } else {
            out!!.append('[')
            stack += Frame(false, PLAIN)
        }
    }

    override fun endArray() {
        if (resourceFailure != null) return
        if (skipping()) { pop(); if (stack.size == skipBase) skipBase = -1; return }
        val frame = pop()
        if (frame.kind != SECTION) out!!.append(']')
        if (resourceFailure != null) return
        endValue()
    }

    override fun name(name: String) {
        if (resourceFailure != null) return
        if (skipping()) return
        val top = stack.last()
        val keys = top.keys ?: HashSet<String>().also { top.keys = it }
        if (resourceFailure == null && !keys.contains(name)) {
            keys.add(name)
            top.keyChars += name.length
            liveKeyChars += name.length
            if (liveKeyChars > MAX_LIVE_KEY_CHARS) resource("open objects hold more than $MAX_LIVE_KEY_CHARS key characters")
        } else if (keys.contains(name)) {
            skipBase = stack.size
            return
        }
        if (top.kind == ROOT) {
            rootKey = name
            return
        }
        val o = out!!
        if (top.count++ > 0) o.append(',')
        if (top.kind == RECORD) { field = name; fieldStart = o.length }
        o.appendQuoted(name)
        o.append(':')
    }

    override fun stringChunk(buffer: CharArray, offset: Int, length: Int, last: Boolean) {
        if (resourceFailure != null) return
        if (skipping()) {
            if (last && stack.size == skipBase) skipBase = -1
            return
        }
        if (!inString) {
            startValue("string")
            out!!.append('"')
            inString = true
        }
        out!!.appendEscaped(buffer, offset, length)
        if (resourceFailure != null) return
        if (capturing) {
            if (capBuf.length + length > ManifestSections.MAX_KEY_CHARS) capOverflow = true else capBuf.append(buffer, offset, length)
        }
        if (last) {
            out!!.append('"')
            inString = false
            endValue()
        }
    }

    override fun literal(text: String) {
        if (resourceFailure != null) return
        if (skipping()) {
            if (stack.size == skipBase) skipBase = -1
            return
        }
        startValue(kindOf(text))
        out!!.append(text)
        if (capturing) {
            if (capBuf.length + text.length > ManifestSections.MAX_KEY_CHARS) capOverflow = true
            else capBuf.append(text)
        }
        if (resourceFailure != null) return
        endValue()
    }

    companion object {
        /** Source bytes of one strict record: larger is resource exhaustion (shared decision 5), decided after EOF. */
        const val TYPED_BUDGET_BYTES = 8L * 1024 * 1024

        /** Source bytes of one known non-array root value (including whitespace inside it). */
        const val MAX_ROOT_VALUE_BYTES = 16L * 1024 * 1024

        /** UTF-16 units of distinct keys held by all open objects at once. The 182,361 x 60 fixture crosses this limit. */
        const val MAX_LIVE_KEY_CHARS = 10L * 1024 * 1024
        private val IOS_LOSSY_ROOT_KEYS = setOf("writingRecovery", "documents")
        private const val ROOT = 0
        private const val PLAIN = 1
        private const val SECTION = 2
        private const val RECORD = 3
    }
}
