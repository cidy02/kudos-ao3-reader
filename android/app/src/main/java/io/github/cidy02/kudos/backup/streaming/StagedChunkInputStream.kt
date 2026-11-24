package io.github.cidy02.kudos.backup.streaming

import android.database.sqlite.SQLiteDatabase
import java.io.InputStream

/** UTF-8 view of compact JSON held in indexed SQLite text chunks, without assembling the record. */
internal class StagedChunkInputStream(
    private val db: SQLiteDatabase,
    private val table: String,
    private val ord: Long
) : InputStream() {
    private var nextStart = 0L
    private var bytes = ByteArray(0)
    private var position = 0
    private var ended = false

    override fun read(): Int {
        if (!fill()) return -1
        return bytes[position++].toInt() and 0xff
    }

    override fun read(destination: ByteArray, offset: Int, length: Int): Int {
        if (offset < 0 || length < 0 || offset > destination.size - length) throw IndexOutOfBoundsException()
        if (length == 0) return 0
        if (!fill()) return -1
        val count = minOf(length, bytes.size - position)
        bytes.copyInto(destination, offset, position, position + count)
        position += count
        return count
    }

    private fun fill(): Boolean {
        while (position == bytes.size && !ended) {
            val piece = db.rawQuery(
                "SELECT start, len, data FROM $table WHERE ord = ? AND start >= ? ORDER BY start LIMIT 1",
                arrayOf(ord.toString(), nextStart.toString())
            ).use { cursor ->
                if (cursor.moveToFirst()) Triple(cursor.getLong(0), cursor.getLong(1), cursor.getString(2)) else null
            }
            if (piece == null) { ended = true; break }
            check(piece.first == nextStart && piece.second == piece.third.length.toLong()) { "non-contiguous staged JSON chunks" }
            nextStart += piece.second
            bytes = piece.third.toByteArray(Charsets.UTF_8)
            position = 0
        }
        return position < bytes.size
    }
}
