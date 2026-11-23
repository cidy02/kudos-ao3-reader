package io.github.cidy02.kudos.backup.streaming

import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteStatement
import java.io.File

/**
 * The private per-run staging database (not Room's). Tables, all keyed by source position:
 *  - `meta(k, v)`: run facts (version, exportedAt, counts).
 *  - `root(ord, key, kind, known, oversize, chars, records)`: every distinct top-level key in source order
 *    (first occurrence wins) with its value kind and presence; `root_chunk` holds its compact JSON text.
 *    A known record array has kind `records` and no chunk rows.
 *  - `s_<section>(ord, kind, chars, oversize, typed_ok, k_*)` and `s_<section>_chunk(ord, seq, len, data)`:
 *    one row per array element in source order, the element's compact JSON text in chunks of at most
 *    [CHUNK_CHARS] chars, and indexed natural-key columns (see [ManifestSections]). `typed_ok` is 1 or 0
 *    for an element decoded at stage time, -1 for an oversize one (decoded when read back).
 *  - `unknown_range(section, ord, name, start, stop)`: for each record, the char range
 *    `[start, stop)` of every direct member the typed model does not know (`"name":value`) inside the
 *    record's compact text, so the A-541a overlay can carry them without re-parsing the record.
 */
internal class StagingWriter(
    file: File,
    private val freeSpace: () -> Long,
    private val isCancelled: () -> Boolean,
    private val checkpoint: (Long) -> Unit
) {
    val db: SQLiteDatabase = SQLiteDatabase.openOrCreateDatabase(file, null)
    private val statements = HashMap<String, SQLiteStatement>()
    private var pendingChars = 0L
    private var pendingRows = 0
    var committedRows = 0L
        private set

    init {
        db.execSQL("PRAGMA synchronous=OFF")
        db.execSQL("CREATE TABLE meta(k TEXT PRIMARY KEY, v TEXT)")
        db.execSQL(
            "CREATE TABLE root(ord INTEGER PRIMARY KEY, key TEXT NOT NULL UNIQUE, kind TEXT NOT NULL, " +
                "known INTEGER NOT NULL, oversize INTEGER NOT NULL, chars INTEGER NOT NULL, records INTEGER NOT NULL)"
        )
        db.execSQL(chunkTableSql("root_chunk"))
        db.execSQL("CREATE TABLE unknown_range(section TEXT NOT NULL, ord INTEGER NOT NULL, name TEXT NOT NULL, start INTEGER NOT NULL, stop INTEGER NOT NULL, PRIMARY KEY(section, ord, start)) WITHOUT ROWID")
        for (s in ManifestSections.all) {
            val keys = s.keys.joinToString("") { ", ${it.column} TEXT" }
            db.execSQL(
                "CREATE TABLE ${s.table}(ord INTEGER PRIMARY KEY, kind TEXT NOT NULL, chars INTEGER NOT NULL, " +
                    "oversize INTEGER NOT NULL, typed_ok INTEGER NOT NULL$keys)"
            )
            db.execSQL(chunkTableSql(s.chunkTable))
        }
        db.beginTransaction()
    }

    private fun chunkTableSql(name: String) =
        "CREATE TABLE $name(ord INTEGER NOT NULL, seq INTEGER NOT NULL, len INTEGER NOT NULL, data TEXT NOT NULL, PRIMARY KEY(ord, seq)) WITHOUT ROWID"

    private fun stmt(sql: String) = statements.getOrPut(sql) { db.compileStatement(sql) }

    fun chunk(table: String, ord: Long, seq: Int, data: String) {
        stmt("INSERT INTO $table(ord, seq, len, data) VALUES(?,?,?,?)").run {
            bindLong(1, ord); bindLong(2, seq.toLong()); bindLong(3, data.length.toLong()); bindString(4, data)
            executeInsert()
        }
        pendingChars += data.length
        maybeCommit()
    }

    fun root(ord: Long, key: String, kind: String, known: Boolean, oversize: Boolean, chars: Long, records: Long) {
        stmt("INSERT INTO root(ord, key, kind, known, oversize, chars, records) VALUES(?,?,?,?,?,?,?)").run {
            bindLong(1, ord); bindString(2, key); bindString(3, kind); bindLong(4, if (known) 1 else 0)
            bindLong(5, if (oversize) 1 else 0); bindLong(6, chars); bindLong(7, records)
            executeInsert()
        }
        row()
    }

    fun record(spec: SectionSpec, ord: Long, kind: String, chars: Long, oversize: Boolean, typedOk: Int, keys: List<String?>) {
        val cols = spec.keys.joinToString("") { ", ${it.column}" }
        val marks = ",?".repeat(spec.keys.size)
        stmt("INSERT INTO ${spec.table}(ord, kind, chars, oversize, typed_ok$cols) VALUES(?,?,?,?,?$marks)").run {
            bindLong(1, ord); bindString(2, kind); bindLong(3, chars); bindLong(4, if (oversize) 1 else 0); bindLong(5, typedOk.toLong())
            keys.forEachIndexed { i, v -> if (v == null) bindNull(6 + i) else bindString(6 + i, v) }
            executeInsert()
        }
        row()
    }

    fun unknown(section: String, ord: Long, name: String, start: Long, stop: Long) {
        stmt("INSERT INTO unknown_range(section, ord, name, start, stop) VALUES(?,?,?,?,?)").run {
            bindString(1, section); bindLong(2, ord); bindString(3, name); bindLong(4, start); bindLong(5, stop)
            executeInsert()
        }
        row()
    }

    private fun row() {
        pendingRows++
        maybeCommit()
    }

    /** Commits in bounded transactions, polls cancellation and refuses to continue on a nearly full disk. */
    fun maybeCommit() {
        if (pendingRows < COMMIT_ROWS && pendingChars < COMMIT_CHARS) return
        if (isCancelled()) throw ManifestStageException.Cancelled()
        committedRows += pendingRows
        pendingRows = 0
        pendingChars = 0
        db.setTransactionSuccessful()
        db.endTransaction()
        if (freeSpace() < MIN_FREE_BYTES) throw ManifestStageException.ResourceExhausted("not enough free disk space to keep staging the manifest")
        checkpoint(committedRows)
        db.beginTransaction()
    }

    fun commitAll() {
        db.setTransactionSuccessful()
        db.endTransaction()
        db.beginTransaction()
    }

    /** Indexes are built after the bulk load: one pass, no per-insert index maintenance. */
    fun finish(meta: Map<String, String>) {
        for ((k, v) in meta) {
            stmt("INSERT OR REPLACE INTO meta(k, v) VALUES(?,?)").run { bindString(1, k); bindString(2, v); executeInsert() }
        }
        db.setTransactionSuccessful()
        db.endTransaction()
        for (s in ManifestSections.all) {
            for (k in s.keys) db.execSQL("CREATE INDEX ${s.table}_${k.column} ON ${s.table}(${k.column})")
        }
        db.execSQL("CREATE INDEX unknown_range_by_section ON unknown_range(section, ord)")
        statements.values.forEach { it.close() }
        statements.clear()
    }

    /** Closes without deleting; the owner removes the directory. */
    fun abandon() {
        runCatching { statements.values.forEach { it.close() } }
        runCatching { if (db.inTransaction()) db.endTransaction() }
        runCatching { db.close() }
    }

    companion object {
        const val CHUNK_CHARS = 64 * 1024
        const val COMMIT_ROWS = 2000
        const val COMMIT_CHARS = 8L * 1024 * 1024
        const val MIN_FREE_BYTES = 8L * 1024 * 1024
    }
}
