package io.github.cidy02.kudos.files

import java.nio.charset.Charset
import java.nio.charset.CharsetDecoder
import java.nio.charset.CodingErrorAction
import java.nio.ByteBuffer

/**
 * Multi-encoding decode chain for imported text (iOS `ImportedDocumentConverter.decode`).
 *
 * Fan-fiction downloaded from older archives is routinely Windows-1252 or
 * Latin-1, not UTF-8, so a strict UTF-8 read either throws or produces replacement
 * characters through the whole work.
 *
 * **UTF-16 is tried only behind a byte-order mark, and before the single-byte
 * encodings.** Without the BOM gate, a UTF-16 decode succeeds on almost any
 * even-length byte sequence and returns CJK-looking mojibake — so an ordinary
 * Latin-1 file with an even byte count would import as garbage instead of
 * falling through to an encoding that actually fits it. That ordering is the
 * whole point of this function; don't "simplify" it into a plain try-list.
 */
object TextDecoding {

    fun decode(bytes: ByteArray): String? {
        if (bytes.isEmpty()) return null

        utf16WithBom(bytes)?.let { return it }

        for (charset in listOf(Charsets.UTF_8, WINDOWS_1252, Charsets.ISO_8859_1)) {
            strictDecode(bytes, charset)?.let { return it }
        }
        // Latin-1 maps every byte, so reaching here means the input was empty
        // after decoding rather than undecodable.
        return null
    }

    private fun utf16WithBom(bytes: ByteArray): String? {
        if (bytes.size < 2) return null
        val b0 = bytes[0].toInt() and 0xFF
        val b1 = bytes[1].toInt() and 0xFF
        val charset = when {
            b0 == 0xFF && b1 == 0xFE -> Charsets.UTF_16LE
            b0 == 0xFE && b1 == 0xFF -> Charsets.UTF_16BE
            else -> return null
        }
        // Drop the BOM itself so it doesn't become a stray leading character.
        return strictDecode(bytes.copyOfRange(2, bytes.size), charset)
    }

    /**
     * Strict so an encoding that doesn't fit *fails* instead of silently
     * substituting U+FFFD — otherwise UTF-8 would "succeed" on every input and
     * the rest of the chain would never run.
     */
    private fun strictDecode(bytes: ByteArray, charset: Charset): String? = runCatching {
        val decoder: CharsetDecoder = charset.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
        decoder.decode(ByteBuffer.wrap(bytes)).toString().takeIf { it.isNotEmpty() }
    }.getOrNull()

    private val WINDOWS_1252: Charset = runCatching { Charset.forName("windows-1252") }
        .getOrDefault(Charsets.ISO_8859_1)
}
