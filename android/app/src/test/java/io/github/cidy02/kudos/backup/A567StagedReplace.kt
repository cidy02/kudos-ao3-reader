package io.github.cidy02.kudos.backup

import android.database.sqlite.SQLiteConstraintException
import android.database.sqlite.SQLiteDatabase
import androidx.room.withTransaction
import androidx.sqlite.db.SimpleSQLiteQuery
import io.github.cidy02.kudos.data.local.entity.TagEntity
import io.github.cidy02.kudos.data.local.entity.WorkTagCrossRef
import io.github.cidy02.kudos.data.local.entity.toDomain
import io.github.cidy02.kudos.data.local.entity.toEntity
import io.github.cidy02.kudos.works.EpubImportMetadata
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.works.WorkSearchIndex
import java.io.File
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonPrimitive

/**
 * PROTOTYPE ONLY (A-567 P1), tests only. Replace of the `works` section driven from a private SQLite
 * staging database in bounded batches, inside one Room transaction with BackupFileUndo, to learn
 * whether heap stays flat as incoming and existing rows grow and whether Replace's commit and
 * failure behaviour survives. Other sections would follow the same pattern; they are not modelled.
 * Overlapping ids between incoming and local rows (applyReplaceWork) are not modelled either.
 */
class A567Staging(val file: File) : AutoCloseable {
    val db: SQLiteDatabase = SQLiteDatabase.openOrCreateDatabase(file, null).also {
        it.execSQL("CREATE TABLE IF NOT EXISTS staged_works(seq INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE, json TEXT NOT NULL)")
        it.execSQL("CREATE TABLE IF NOT EXISTS live_works(id TEXT PRIMARY KEY, fingerprint TEXT NOT NULL)")
        it.execSQL("CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)")
    }

    var version = 0
    var exportedAt = ""
    var count = 0

    /** Streams the manifest into staging, then validates every staged row; nothing live is touched. */
    fun stage(manifest: File, onRecord: (Int) -> Unit = {}) {
        val insert = db.compileStatement("INSERT INTO staged_works(id, json) VALUES(?, ?)")
        db.beginTransaction()
        val tree = A567Tree(records = { section, element ->
            if (section == "works") {
                val id = BackupPaths.canonicalUuid((element as JsonObject)["id"]!!.jsonPrimitive.content, "works[$count].id")
                insert.bindString(1, id)
                insert.bindString(2, element.toString())
                try {
                    insert.executeInsert()
                } catch (_: SQLiteConstraintException) {
                    throw BackupError.InvalidPackage("Duplicate work id: $id")
                }
                count++
                if (count % 1000 == 0) { db.setTransactionSuccessful(); db.endTransaction(); db.beginTransaction() }
                onRecord(count)
            }
        })
        try {
            manifest.inputStream().buffered(1 shl 16).use { A567ChunkedTokenizer.run(it, tree) }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
        val root = tree.root as JsonObject
        version = root["version"]!!.jsonPrimitive.int
        exportedAt = (root["exportedAt"] as JsonPrimitive).content
        BackupValidator.validateManifest(KudosBackupManifest(version = version, exportedAt = exportedAt))
        forEachBatch { /* decoded and validated in the batch walk */ }
    }

    /** Keyset batches over the staged rows, decoded and validated with the manifest's own rules. */
    fun forEachBatch(size: Int = 500, body: (List<BackupWork>) -> Unit) {
        var last = 0L
        while (true) {
            val batch = mutableListOf<BackupWork>()
            db.rawQuery("SELECT seq, json FROM staged_works WHERE seq > ? ORDER BY seq LIMIT $size", arrayOf(last.toString())).use { c ->
                while (c.moveToNext()) {
                    last = c.getLong(0)
                    batch += BackupJson.decodeFromString(BackupWork.serializer(), c.getString(1))
                }
            }
            if (batch.isEmpty()) return
            body(BackupValidator.validateManifest(KudosBackupManifest(version = version, exportedAt = exportedAt, works = batch)).works)
        }
    }

    fun isStaged(id: String): Boolean = db.rawQuery("SELECT 1 FROM staged_works WHERE id = ?", arrayOf(id)).use { it.moveToFirst() }

    override fun close() = db.close()
}

const val TOKEN_ID = "a567-replace-commit"
const val TOKEN_NAME = "__a567_replace_commit__"

class A567StagedReplace(private val rig: A567Rig, private val staging: A567Staging, private val epubDirectory: File?) {
    class Hooks {
        var afterBatch: ((Int) -> Unit)? = null
        var beforeCommit: (() -> Unit)? = null
        var afterSweepBatch: ((Int) -> Unit)? = null
        /** Skip file rollback to model a process that dies inside the transaction. */
        var simulateProcessDeath = false
    }

    class Counts(var created: Int = 0, var removed: Int = 0, var deferred: Int = 0, var epubsInstalled: Int = 0)

    /** Records the local rows Replace may sweep, as the merge's captured snapshot does (id + a change fingerprint). */
    fun captureLive(onBatch: (Int) -> Unit = {}) {
        var seen = 0
        staging.db.execSQL("DELETE FROM live_works")
        var last = ""
        while (true) {
            var n = 0
            val batch = mutableListOf<Pair<String, String>>()
            rig.database.openHelper.readableDatabase.query(SimpleSQLiteQuery(
                "SELECT id, id || '|' || IFNULL(lastModifiedAt, '') || '|' || isDeleted FROM works WHERE id > ? ORDER BY id LIMIT 1000", arrayOf(last)
            )).use { c -> while (c.moveToNext()) { batch += c.getString(0) to c.getString(1); n++ } }
            if (batch.isEmpty()) break
            staging.db.beginTransaction()
            try {
                batch.forEach { (id, fp) -> staging.db.execSQL("INSERT OR REPLACE INTO live_works(id, fingerprint) VALUES(?, ?)", arrayOf(id, fp)) }
                staging.db.setTransactionSuccessful()
            } finally { staging.db.endTransaction() }
            last = batch.last().first
            seen += batch.size; onBatch(seen)
        }
    }

    private fun fingerprintNow(id: String): String? = rig.database.openHelper.readableDatabase.query(SimpleSQLiteQuery(
        "SELECT id || '|' || IFNULL(lastModifiedAt, '') || '|' || isDeleted FROM works WHERE id = ?", arrayOf(id)
    )).use { if (it.moveToFirst()) it.getString(0) else null }

    suspend fun apply(now: Instant, hooks: Hooks = Hooks()): Counts = rig.gate.withLock {
        withContext(Dispatchers.IO) {
            val counts = Counts()
            val undo = BackupFileUndo()
            try {
                rig.database.withTransaction {
                    try {
                        sweepOmitted(now, counts, hooks)
                        upsertStaged(now, counts, undo, hooks)
                        // Durable commit discriminator: written in the same transaction, so it exists iff the rows do.
                        rig.database.tagDao().upsert(TagEntity(id = TOKEN_ID, name = TOKEN_NAME, dateCreated = now))
                        hooks.beforeCommit?.invoke()
                    } catch (error: Throwable) {
                        if (!hooks.simulateProcessDeath) undo.rollback(error)
                        throw error
                    }
                }
            } catch (error: Throwable) {
                // A cancellation can surface after Room committed; the marker says which side of the commit we are on.
                val committed = withContext(kotlinx.coroutines.NonCancellable) { rig.database.tagDao().getById(TOKEN_ID) != null }
                if (committed) {
                    undo.discard()
                    withContext(kotlinx.coroutines.NonCancellable) { rig.database.tagDao().deleteById(TOKEN_ID) }
                } else if (!hooks.simulateProcessDeath) {
                    undo.rollback(error)
                }
                throw error
            }
            undo.discard()
            rig.database.tagDao().deleteById(TOKEN_ID)
            counts
        }
    }

    private suspend fun sweepOmitted(now: Instant, counts: Counts, hooks: Hooks) {
        var last = ""
        var seen = 0
        while (true) {
            val captured = mutableListOf<Pair<String, String>>()
            staging.db.rawQuery("SELECT id, fingerprint FROM live_works WHERE id > ? ORDER BY id LIMIT 500", arrayOf(last)).use { c ->
                while (c.moveToNext()) captured += c.getString(0) to c.getString(1)
            }
            if (captured.isEmpty()) return
            for ((id, fingerprint) in captured) {
                if (staging.isStaged(id)) continue
                val entity = rig.database.workDao().getById(id) ?: continue
                if (entity.isDeleted) continue
                if (fingerprintNow(id) != fingerprint) { // edited after staging: local wins; today still re-indexes it
                    counts.deferred++
                    val tags = rig.database.tagDao().getTagsForWork(id).map { it.name }
                    rig.database.workDao().upsert(WorkSearchIndex.reindex(entity.toDomain(), tags).toEntity())
                    continue
                }
                val parked = entity.toDomain().copy(
                    isDeleted = true, deletedAt = now, permanentDeletionScheduledAt = now.plus(WorkRepository.RECOVERY_WINDOW)
                )
                val tags = rig.database.tagDao().getTagsForWork(id).map { it.name }
                rig.database.workDao().upsert(WorkSearchIndex.reindex(parked, tags).toEntity())
                counts.removed++
            }
            last = captured.last().first
            seen += captured.size; hooks.afterSweepBatch?.invoke(seen)
        }
    }

    private suspend fun upsertStaged(now: Instant, counts: Counts, undo: BackupFileUndo, hooks: Hooks) {
        val exportedAt = BackupValidator.parseInstant(staging.exportedAt, "exportedAt")
        var processed = 0
        var last = 0L
        while (true) {
            val batch = mutableListOf<BackupWork>()
            staging.db.rawQuery("SELECT seq, json FROM staged_works WHERE seq > ? ORDER BY seq LIMIT 500", arrayOf(last.toString())).use { c ->
                while (c.moveToNext()) { last = c.getLong(0); batch += BackupJson.decodeFromString(BackupWork.serializer(), c.getString(1)) }
            }
            if (batch.isEmpty()) break
            val works = BackupValidator.validateManifest(KudosBackupManifest(version = staging.version, exportedAt = staging.exportedAt, works = batch)).works
            for (archived in works) {
                val packaged = epubDirectory?.let { File(it, "${archived.id}.epub") }?.takeIf { it.isFile }?.readBytes()
                val readable = packaged?.takeIf { EpubImportMetadata.isReadablePackage(it, rig.cacheRoot) }
                if (readable != null) {
                    undo.beforeWrite(rig.workFiles.workEpubPath(archived.id))
                    rig.workFiles.writeWorkEpub(archived.id, readable).let { check(it is io.github.cidy02.kudos.files.FileWriteResult.Success) { "EPUB write failed: $it" } }
                    counts.epubsInstalled++
                }
                val saved = archived.toSavedWork(hasEpub = readable != null, exportedAt = exportedAt).copy(
                    remoteEpubPending = readable == null && archived.hasEPUB
                ).let { it.copy(assetIdentifier = BackupPaths.iosEpubAssetIdentifier(it.id)) }
                rig.database.workDao().upsert(saved.toEntity())
                archived.userTags.normalizedNames().forEach { name ->
                    val tag = rig.database.tagDao().getByNameCaseInsensitive(name)
                        ?: TagEntity(id = java.util.UUID.randomUUID().toString(), name = name, dateCreated = now).also { rig.database.tagDao().upsert(it) }
                    rig.database.tagDao().addToWork(WorkTagCrossRef(workId = saved.id, tagId = tag.id))
                }
                val stored = rig.database.tagDao().getTagsForWork(saved.id).map { it.name }
                rig.database.workDao().upsert(WorkSearchIndex.reindex(saved, stored).toEntity())
                counts.created++
            }
            processed += works.size
            hooks.afterBatch?.invoke(processed)
        }
    }
}
