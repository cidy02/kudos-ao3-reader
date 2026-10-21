package io.github.cidy02.kudos.backup

/**
 * iOS `MiniZip.findEOCD`, `locateCentralDirectory`, and `parseZip64Extra`
 * (`Reading/MiniZip.swift`). Streaming import never reads this directory, so a
 * broken one or a truncated ZIP64 extra was admitted. Entry paths, methods, and
 * duplicates stay with the stream: those already fail with their own errors.
 * An empty directory falls through so an empty archive is still "missing manifest".
 * The entry-count cap is iOS's backup limit, a loop guard, not a byte ceiling.
 */
internal object ZipCentralDirectory {
    private const val MALFORMED = "The archive's central directory is missing or malformed."
    private const val TRUNCATED = "An archive record is truncated or points outside the file."
    private const val ARCHIVE_TOO_LARGE = "The archive's total uncompressed size exceeds the allowed limit."
    private const val MAX_ENTRIES = 250_000

    fun requireReadable(bytes: ByteArray) {
        val eocd = findEocd(bytes) ?: throw BackupError.InvalidPackage(MALFORMED)
        val directory = locate(bytes, eocd)
        if (directory.count == 0) return
        if (directory.count > MAX_ENTRIES) throw BackupError.InvalidPackage(ARCHIVE_TOO_LARGE)
        var offset = directory.start
        repeat(directory.count) {
            val signature = u32(bytes, offset) ?: throw BackupError.InvalidPackage(MALFORMED)
            if (signature != 0x02014b50L) throw BackupError.InvalidPackage(MALFORMED)
            if (u16(bytes, offset + 8) == null || u16(bytes, offset + 10) == null) {
                throw BackupError.InvalidPackage(TRUNCATED)
            }
            val compressed = u32(bytes, offset + 20) ?: throw BackupError.InvalidPackage(TRUNCATED)
            val uncompressed = u32(bytes, offset + 24) ?: throw BackupError.InvalidPackage(TRUNCATED)
            val nameLength = u16(bytes, offset + 28) ?: throw BackupError.InvalidPackage(TRUNCATED)
            val extraLength = u16(bytes, offset + 30) ?: throw BackupError.InvalidPackage(TRUNCATED)
            val commentLength = u16(bytes, offset + 32) ?: throw BackupError.InvalidPackage(TRUNCATED)
            val localOffset = u32(bytes, offset + 42) ?: throw BackupError.InvalidPackage(TRUNCATED)
            val nameStart = checkedAdd(offset, 46) ?: throw BackupError.InvalidPackage(TRUNCATED)
            val nameEnd = checkedAdd(nameStart, nameLength) ?: throw BackupError.InvalidPackage(TRUNCATED)
            val extraEnd = checkedAdd(nameEnd, extraLength) ?: throw BackupError.InvalidPackage(TRUNCATED)
            val recordEnd = checkedAdd(extraEnd, commentLength) ?: throw BackupError.InvalidPackage(TRUNCATED)
            if (recordEnd > bytes.size) throw BackupError.InvalidPackage(TRUNCATED)
            if (compressed == 0xFFFFFFFFL || uncompressed == 0xFFFFFFFFL || localOffset == 0xFFFFFFFFL) {
                parseZip64Extra(
                    bytes,
                    nameEnd,
                    extraEnd,
                    needsUncompressed = uncompressed == 0xFFFFFFFFL,
                    needsCompressed = compressed == 0xFFFFFFFFL,
                    needsOffset = localOffset == 0xFFFFFFFFL
                )
            }
            offset = recordEnd
        }
    }

    private class Location(val count: Int, val start: Int)

    /** Scans back at most 65536 bytes past the record, matching MiniZip.findEOCD. */
    private fun findEocd(bytes: ByteArray): Int? {
        if (bytes.size < 22) return null
        var index = bytes.size - 22
        val lower = maxOf(0, bytes.size - 22 - 65536)
        while (index >= lower) {
            if (u32(bytes, index) == 0x06054b50L) return index
            index -= 1
        }
        return null
    }

    private fun locate(bytes: ByteArray, eocd: Int): Location {
        if (eocd >= 20 && u32(bytes, eocd - 20) == 0x07064b50L) {
            val locator = eocd - 20
            val disk = u32(bytes, locator + 4) ?: throw BackupError.InvalidPackage(MALFORMED)
            val record = u64AsInt(bytes, locator + 8) ?: throw BackupError.InvalidPackage(MALFORMED)
            val totalDisks = u32(bytes, locator + 16) ?: throw BackupError.InvalidPackage(MALFORMED)
            if (disk != 0L || totalDisks > 1L || u32(bytes, record) != 0x06064b50L) {
                throw BackupError.InvalidPackage(MALFORMED)
            }
            val diskNumber = u32(bytes, record + 16) ?: throw BackupError.InvalidPackage(MALFORMED)
            val directoryDisk = u32(bytes, record + 20) ?: throw BackupError.InvalidPackage(MALFORMED)
            if (diskNumber != 0L || directoryDisk != 0L) throw BackupError.InvalidPackage(MALFORMED)
            val count = u64AsInt(bytes, record + 32) ?: throw BackupError.InvalidPackage(MALFORMED)
            val start = u64AsInt(bytes, record + 48) ?: throw BackupError.InvalidPackage(MALFORMED)
            if (start > bytes.size) throw BackupError.InvalidPackage(MALFORMED)
            return Location(count, start)
        }
        val count = u16(bytes, eocd + 10) ?: throw BackupError.InvalidPackage(MALFORMED)
        val size = u32(bytes, eocd + 12) ?: throw BackupError.InvalidPackage(MALFORMED)
        val start = u32(bytes, eocd + 16) ?: throw BackupError.InvalidPackage(MALFORMED)
        if (count == 0xFFFF || size == 0xFFFFFFFFL || start == 0xFFFFFFFFL) {
            throw BackupError.InvalidPackage(MALFORMED)
        }
        if (start > bytes.size) throw BackupError.InvalidPackage(MALFORMED)
        return Location(count, start.toInt())
    }

    /**
     * Header id 0x0001 carries only the saturated fields, in order: uncompressed
     * size, compressed size, local-header offset. A block that runs past the extra
     * area is truncated. No block, or a block missing a field, is malformed.
     */
    private fun parseZip64Extra(
        bytes: ByteArray,
        extraStart: Int,
        extraEnd: Int,
        needsUncompressed: Boolean,
        needsCompressed: Boolean,
        needsOffset: Boolean
    ) {
        var cursor = extraStart
        while (true) {
            val fieldsStart = checkedAdd(cursor, 4) ?: break
            if (fieldsStart > extraEnd) break
            val headerId = u16(bytes, cursor) ?: throw BackupError.InvalidPackage(TRUNCATED)
            val blockSize = u16(bytes, cursor + 2) ?: throw BackupError.InvalidPackage(TRUNCATED)
            val blockEnd = checkedAdd(fieldsStart, blockSize) ?: throw BackupError.InvalidPackage(TRUNCATED)
            if (blockEnd > extraEnd) throw BackupError.InvalidPackage(TRUNCATED)
            if (headerId == 0x0001) {
                var field = fieldsStart
                if (needsUncompressed) field = readZip64Field(bytes, field, blockEnd)
                if (needsCompressed) field = readZip64Field(bytes, field, blockEnd)
                if (needsOffset) readZip64Field(bytes, field, blockEnd)
                return
            }
            cursor = blockEnd
        }
        throw BackupError.InvalidPackage(MALFORMED)
    }

    private fun readZip64Field(bytes: ByteArray, cursor: Int, blockEnd: Int): Int {
        val fieldEnd = checkedAdd(cursor, 8) ?: throw BackupError.InvalidPackage(MALFORMED)
        if (fieldEnd > blockEnd) throw BackupError.InvalidPackage(MALFORMED)
        u64AsInt(bytes, cursor) ?: throw BackupError.InvalidPackage(MALFORMED)
        return fieldEnd
    }

    private fun checkedAdd(start: Int, length: Int): Int? {
        val sum = start.toLong() + length.toLong()
        if (sum < 0L || sum > Int.MAX_VALUE) return null
        return sum.toInt()
    }

    private fun u16(bytes: ByteArray, offset: Int): Int? {
        if (offset < 0 || offset + 2 > bytes.size) return null
        return (bytes[offset].toInt() and 0xFF) or ((bytes[offset + 1].toInt() and 0xFF) shl 8)
    }

    private fun u32(bytes: ByteArray, offset: Int): Long? {
        if (offset < 0 || offset + 4 > bytes.size) return null
        return (bytes[offset].toLong() and 0xFF) or
            ((bytes[offset + 1].toLong() and 0xFF) shl 8) or
            ((bytes[offset + 2].toLong() and 0xFF) shl 16) or
            ((bytes[offset + 3].toLong() and 0xFF) shl 24)
    }

    /** Unsigned 64-bit that fits in a non-negative Int, as MiniZip's `Int(exactly:)`. */
    private fun u64AsInt(bytes: ByteArray, offset: Int): Int? {
        if (offset < 0 || offset + 8 > bytes.size) return null
        var value = 0L
        for (index in 0 until 8) {
            val piece = bytes[offset + index].toLong() and 0xFF
            if (index == 7 && piece > 0x7F) return null
            value = value or (piece shl (8 * index))
        }
        if (value > Int.MAX_VALUE) return null
        return value.toInt()
    }
}
