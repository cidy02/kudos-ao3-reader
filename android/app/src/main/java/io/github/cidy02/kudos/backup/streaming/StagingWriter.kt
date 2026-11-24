package io.github.cidy02.kudos.backup.streaming

import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteStatement
import java.io.File

/**
 * The private per-run staging database (not Room's). Tables, all keyed by source position:
 *  - `meta(k, v)`: run facts (version, exportedAt).
 *  - `root(ord, key, kind, known, oversize, chars, records)`: every distinct top-level key in source order
 *    (first occurrence wins) with its value kind and presence; `root_chunk` holds its compact JSON text.
 *    A known record array has kind `records` and no chunk rows.
 *  - `s_<section>(ord, kind, chars, oversize, typed_ok, k_*)` and `s_<section>_chunk(ord, start, len, data)`:
 *    one row per array element in source order, the element's compact JSON text in chunks of at most
 *    [CHUNK_CHARS] chars addressed by their char offset `start` (primary key `(ord, start)`, so a range read
 *    touches only the chunks it overlaps), and indexed natural-key columns (see [ManifestSections]).
 *    `typed_ok` is always 1 in a successful run: every record was decoded under the typed budget.
 *  - `unknown_range(section, ord, name, start, stop)`: for each record, the char range `[start, stop)` of every
 *    direct member the typed model does not know (`"name":value`) inside the record's compact text.
 */
internal class StagingWriter(
    private val directory: File,
    private val freeSpace: () -> Long,
    private val budgetBytes: () -> Long,
    private val checkpoint: (Long) -> Unit,
    onOpened: (SQLiteDatabase) -> Unit = {}
) {
    private val file = File(directory, "staging.db")
    val db: SQLiteDatabase = SQLiteDatabase.openOrCreateDatabase(file, null)
    private val statements = HashMap<String, SQLiteStatement>()
    private var pendingChars = 0L
    private var pendingRows = 0
    var sourceBytes: () -> Long = { 0L }
    var committedRows = 0L
        private set

    init {
        try {
            onOpened(db)
            File(directory, MARKER).writeText("run")
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
                    "CREATE TABLE ${s.table}(ord INTEGER PRIMARY KEY, kind TEXT NOT NULL, chars INTEGER NOT NULL, source_bytes INTEGER NOT NULL, " +
                        "oversize INTEGER NOT NULL, typed_ok INTEGER NOT NULL$keys)"
                )
                db.execSQL(chunkTableSql(s.chunkTable))
            }
            db.beginTransaction()
        } catch (t: Throwable) {
            abandon()
            throw t
        }
    }

    private fun chunkTableSql(name: String) =
        "CREATE TABLE $name(ord INTEGER NOT NULL, start INTEGER NOT NULL, len INTEGER NOT NULL, data TEXT NOT NULL, PRIMARY KEY(ord, start)) WITHOUT ROWID"

    private fun stmt(sql: String) = statements.getOrPut(sql) { db.compileStatement(sql) }

    fun chunk(table: String, ord: Long, start: Long, data: String) {
        stmt("INSERT INTO $table(ord, start, len, data) VALUES(?,?,?,?)").run {
            bindLong(1, ord); bindLong(2, start); bindLong(3, data.length.toLong()); bindString(4, data)
            executeInsert()
        }
        pendingChars += data.length
        maybeCommit()
    }

    /** The whole staged text of one element or root value; bounded by the typed budget or the root limit, for decoding only. */
    fun readText(table: String, ord: Long): String {
        val sb = StringBuilder()
        var at = 0L
        while (true) {
            val piece = db.rawQuery("SELECT start, data FROM $table WHERE ord = ? AND start >= ? ORDER BY start LIMIT 1", arrayOf(ord.toString(), at.toString())).use { c ->
                if (c.moveToFirst()) c.getLong(0) to c.getString(1) else null
            } ?: return sb.toString()
            sb.append(piece.second)
            at = piece.first + piece.second.length
        }
    }

    fun root(ord: Long, key: String, kind: String, known: Boolean, oversize: Boolean, chars: Long, records: Long) {
        stmt("INSERT INTO root(ord, key, kind, known, oversize, chars, records) VALUES(?,?,?,?,?,?,?)").run {
            bindLong(1, ord); bindString(2, key); bindString(3, kind); bindLong(4, if (known) 1 else 0)
            bindLong(5, if (oversize) 1 else 0); bindLong(6, chars); bindLong(7, records)
            executeInsert()
        }
        row()
    }

    fun record(spec: SectionSpec, ord: Long, kind: String, chars: Long, sourceBytes: Long, oversize: Boolean, typedOk: Int, keys: List<String?>) {
        val cols = spec.keys.joinToString("") { ", ${it.column}" }
        val marks = ",?".repeat(spec.keys.size)
        stmt("INSERT INTO ${spec.table}(ord, kind, chars, source_bytes, oversize, typed_ok$cols) VALUES(?,?,?,?,?,?$marks)").run {
            bindLong(1, ord); bindString(2, kind); bindLong(3, chars); bindLong(4, sourceBytes)
            bindLong(5, if (oversize) 1 else 0); bindLong(6, typedOk.toLong())
            keys.forEachIndexed { i, v -> if (v == null) bindNull(7 + i) else bindString(7 + i, v) }
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

    /** Commits in bounded transactions; every commit rechecks free space and the component budget. */
    fun maybeCommit() {
        if (pendingRows < COMMIT_ROWS && pendingChars < COMMIT_CHARS) return
        committedRows += pendingRows
        pendingRows = 0
        pendingChars = 0
        db.setTransactionSuccessful()
        db.endTransaction()
        checkDisk()
        checkpoint(committedRows)
        db.beginTransaction()
    }

    /** Free space and the staging component budget; called at batch boundaries and around every finalization step. */
    fun checkDisk() {
        File(directory, MARKER).setLastModified(System.currentTimeMillis())
        sourceBytes()
        if (freeSpace() < MIN_FREE_BYTES) throw ManifestStageException.ResourceExhausted("not enough free disk space to keep staging the manifest")
        if (directory.walkTopDown().filter { it.isFile }.sumOf { it.length() } > budgetBytes()) {
            throw ManifestStageException.ResourceExhausted("staging exceeded its disk budget")
        }
    }

    fun commitAll() {
        db.setTransactionSuccessful()
        db.endTransaction()
        checkDisk()
        db.beginTransaction()
    }

    /** Indexes are built after the bulk load, one at a time with a disk and cancellation check between them. */
    fun finish(meta: Map<String, String>, between: () -> Unit) {
        for ((k, v) in meta) {
            stmt("INSERT OR REPLACE INTO meta(k, v) VALUES(?,?)").run { bindString(1, k); bindString(2, v); executeInsert() }
        }
        db.setTransactionSuccessful()
        db.endTransaction()
        statements.values.forEach { it.close() }
        statements.clear()
        for (s in ManifestSections.all) {
            for (k in s.keys) { between(); checkDisk(); db.execSQL("CREATE INDEX ${s.table}_${k.column} ON ${s.table}(${k.column})") }
            for (cols in s.compositeIndexes) { between(); checkDisk(); db.execSQL("CREATE INDEX ${s.table}_${cols.joinToString("_")} ON ${s.table}(${cols.joinToString(",")})") }
        }
        between(); checkDisk()
        db.execSQL("CREATE INDEX unknown_range_by_section ON unknown_range(section, ord)")
        between(); checkDisk()
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
        const val MARKER = "RUN"
    }
}
