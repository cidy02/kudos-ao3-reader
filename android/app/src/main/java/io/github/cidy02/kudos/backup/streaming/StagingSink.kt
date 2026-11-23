package io.github.cidy02.kudos.backup.streaming

import io.github.cidy02.kudos.backup.BackupJson
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerializationException

/** A compact-JSON text being built: held in memory while small, written to chunk rows once it grows. */
internal class StagedText(private val w: StagingWriter, private val chunkTable: String, private val ord: Long) {
    val sb = StringBuilder()
    private var seq = 0
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
            c < ' ' -> { sb.append("\\u00"); sb.append(HEX[c.code shr 4]); sb.append(HEX[c.code and 15]) }
            else -> sb.append(c)
        }
    }

    private fun grown() {
        if (!spilled && sb.length <= DECODE_LIMIT) return
        spilled = true
        while (sb.length >= StagingWriter.CHUNK_CHARS) writeChunk(StagingWriter.CHUNK_CHARS)
    }

    private fun writeChunk(max: Int) {
        var cut = minOf(max, sb.length)
        if (cut > 1 && Character.isHighSurrogate(sb[cut - 1])) cut-- // never split a pair across rows
        w.chunk(chunkTable, ord, seq++, sb.substring(0, cut))
        sb.delete(0, cut)
    }

    /** Writes whatever is left; returns the number of chunk rows. */
    fun close(): Int {
        while (sb.isNotEmpty()) writeChunk(StagingWriter.CHUNK_CHARS)
        return seq
    }

    companion object {
        /** Elements up to this many chars are decoded with the typed model while staging; larger ones are decoded on read. */
        const val DECODE_LIMIT = 1 shl 20
        private val HEX = "0123456789abcdef".toCharArray()
    }
}

/**
 * Turns tokenizer events into staging rows. Duplicate keys (at any depth) keep the first value: the
 * later value is read and validated but not staged. Memory is bounded by [StagedText.DECODE_LIMIT], the
 * 16 KiB read buffer and one key set per open object.
 */
internal class StagingSink(
    private val w: StagingWriter,
    private val tick: () -> Unit
) : ManifestEvents {
    private class Frame(val isObject: Boolean, val kind: Int) {
        var count = 0
        var keys: HashSet<String>? = null
    }

    private val stack = ArrayList<Frame>()
    private var skipBase = -1

    private var rootKey = ""
    private var rootOrd = 0L
    private var rootKind = ""
    private var rootSection: SectionSpec? = null
    private var sectionOrd = 0L
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

    /** First typed-decode failure found while staging; thrown after EOF so I/O and syntax outcomes keep their precedence. */
    var pendingFailure: String? = null
        private set
    var records = 0L
        private set

    private fun skipping() = skipBase >= 0

    private fun kindOf(text: String) = when (text[0]) { 't', 'f' -> "bool"; 'n' -> "null"; else -> "number" }

    private fun startValue(kind: String) {
        val top = stack.last()
        when (top.kind) {
            ROOT -> {
                rootKind = kind
                val section = ManifestSections.byName[rootKey]
                if (section != null && kind == "array") {
                    rootSection = section
                    sectionOrd = 0
                    out = null
                } else {
                    rootSection = null
                    out = StagedText(w, "root_chunk", rootOrd)
                }
            }
            SECTION -> {
                val s = rootSection!!
                out = StagedText(w, s.chunkTable, sectionOrd)
                elementKind = kind
                captured.clear()
                unknowns.clear()
                field = null
            }
            else -> {
                if (!top.isObject) {
                    if (top.count++ > 0) out!!.append(',')
                } else if (top.kind == RECORD) {
                    val f = field!!
                    capturing = (kind == "string" || kind == "number") && rootSection!!.keys.any { f in it.fields }
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
        val oversize = o.spilled
        var typedOk = -1
        if (!oversize) {
            typedOk = if (decodes(spec.serializer, o.sb.toString())) 1 else 0
            if (typedOk == 0 && pendingFailure == null) pendingFailure = "${spec.name}[$ord] is not a valid ${spec.name} record"
        }
        o.close()
        val keys = spec.keys.map { k -> k.make(k.fields.map { captured[it] }) }
        w.record(spec, ord, elementKind, o.length, oversize, typedOk, keys)
        for ((name, start, stop) in unknowns) w.unknown(spec.name, ord, name, start, stop)
        sectionOrd++
        records++
        out = null
        tick()
    }

    private fun finishRoot() {
        val section = rootSection
        if (section != null) {
            w.root(rootOrd, rootKey, "records", true, false, 0, sectionOrd)
        } else {
            val o = out!!
            val oversize = o.spilled
            o.close()
            w.root(rootOrd, rootKey, rootKind, rootKey in ManifestSections.knownRootKeys, oversize, o.length, 0)
        }
        rootOrd++
        rootSection = null
        out = null
        tick()
    }

    @Suppress("UNCHECKED_CAST")
    private fun decodes(serializer: KSerializer<*>, text: String): Boolean = try {
        BackupJson.decodeFromString(serializer as KSerializer<Any>, text)
        true
    } catch (_: SerializationException) {
        false
    } catch (_: IllegalArgumentException) {
        false
    }

    override fun beginObject() {
        if (stack.isEmpty()) { stack += Frame(true, ROOT); return }
        if (skipping()) { stack += Frame(true, PLAIN); return }
        val parent = stack.last().kind
        startValue("object")
        out!!.append('{')
        stack += Frame(true, if (parent == SECTION) RECORD else PLAIN)
    }

    override fun endObject() {
        if (skipping()) { stack.removeAt(stack.size - 1); if (stack.size == skipBase) skipBase = -1; return }
        val frame = stack.removeAt(stack.size - 1)
        if (frame.kind == ROOT) return
        out!!.append('}')
        endValue()
    }

    override fun beginArray() {
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
        if (skipping()) { stack.removeAt(stack.size - 1); if (stack.size == skipBase) skipBase = -1; return }
        val frame = stack.removeAt(stack.size - 1)
        if (frame.kind != SECTION) out!!.append(']')
        endValue()
    }

    override fun name(name: String) {
        if (skipping()) return
        val top = stack.last()
        val keys = top.keys ?: HashSet<String>().also { top.keys = it }
        if (!keys.add(name)) { skipBase = stack.size; return }
        if (keys.size > MAX_KEYS_PER_OBJECT) throw ManifestStageException.ResourceExhausted("an object has more than $MAX_KEYS_PER_OBJECT keys")
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
        if (skipping()) {
            if (stack.size == skipBase) skipBase = -1
            return
        }
        startValue(kindOf(text))
        out!!.append(text)
        if (capturing) capBuf.append(text)
        endValue()
    }

    private companion object {
        const val ROOT = 0
        const val PLAIN = 1
        const val SECTION = 2
        const val RECORD = 3
        const val MAX_KEYS_PER_OBJECT = 262_144
    }
}
