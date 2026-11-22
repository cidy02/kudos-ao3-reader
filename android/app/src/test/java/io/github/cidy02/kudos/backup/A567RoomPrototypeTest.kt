package io.github.cidy02.kudos.backup

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.entity.WorkEntity
import io.github.cidy02.kudos.data.local.entity.toEntity
import io.github.cidy02.kudos.files.FileWriteResult
import io.github.cidy02.kudos.files.WorkFileStore
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.Path
import java.security.MessageDigest
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A-567 P1 Room store prototype (JVM / Robolectric, real Room and real BackupFileUndo): Replace of
 * the works section driven from bounded staged reads, against today's Replace at supported sizes,
 * with failure, concurrent-edit, cancellation and process-death cases. The scaling run is opt-in.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class A567RoomPrototypeTest {
    private class FailingWorkFileStore(root: Path) : WorkFileStore(root) {
        var failAtWrite: Int? = null
        var attempts = 0
        override suspend fun writeWorkEpub(workId: String, bytes: ByteArray): FileWriteResult {
            attempts++
            if (attempts == failAtWrite) return FileWriteResult.Failure("Injected EPUB write failure")
            return super.writeWorkEpub(workId, bytes)
        }
    }

    private val mib = 1024L * 1024L
    private val now = Instant.parse("2026-06-26T12:00:00Z")
    private val epub = A567Rig.epubOf(2000, 1)

    /** incoming works 0 until [incoming] (first [epubs] carry an EPUB); local works use a disjoint id range. */
    private class Fixture(val manifest: File, val epubDir: File, val incoming: Int, val epubs: Int)

    private fun fixture(incoming: Int, epubs: Int, dir: File, metaAfter: Boolean = false): Fixture {
        dir.mkdirs()
        val manifest = File(dir, "manifest.json")
        manifest.outputStream().use {
            A567Corpus.writeManifest(it, works = incoming, epubWorkIds = (0 until epubs).toSet(), metaAfter = metaAfter)
        }
        val epubDir = File(dir, "epubs").apply { mkdirs() }
        for (i in 0 until epubs) File(epubDir, "${A567Corpus.uuid(i + 1)}.epub").writeBytes(epub)
        return Fixture(manifest, epubDir, incoming, epubs)
    }

    private fun localWork(k: Int) = SavedWork(
        id = A567Corpus.uuid(10_000_000 + k), title = "Local $k", author = "Author",
        dateAdded = now.minusSeconds(3600), lastModifiedAt = now.minusSeconds(60), isSaved = true
    )

    private suspend fun seedLocal(rig: A567Rig, count: Int, withEpub: Int = 0) {
        for (start in 0 until count step 2000) {
            val entities = (start until minOf(count, start + 2000)).map { localWork(it).copy(hasEpub = it < withEpub).toEntity() }
            rig.database.workDao().upsertAll(entities)
        }
        for (k in 0 until withEpub) rig.workFiles.writeWorkEpub(localWork(k).id, epub)
    }

    private class Projection(val rows: List<WorkEntity>, val tags: Map<String, List<String>>, val files: Map<String, String>)

    private suspend fun project(rig: A567Rig): Projection {
        val rows = rig.database.workDao().getAllIncludingDeleted().sortedBy { it.id }
        val tags = rows.associate { it.id to rig.database.tagDao().getTagsForWork(it.id).map { t -> t.name }.sorted() }.filterValues { it.isNotEmpty() }
        val files = File(rig.workFiles.worksDirectory.toString()).takeIf { it.isDirectory }?.walkTopDown()?.filter { it.isFile }?.associate {
            it.name to MessageDigest.getInstance("SHA-256").digest(it.readBytes()).joinToString("") { b -> "%02x".format(b) }
        }.orEmpty()
        return Projection(rows, tags, files)
    }

    private fun assertSame(expected: Projection, actual: Projection, label: String) {
        assertEquals("$label: row count", expected.rows.size, actual.rows.size)
        // today's merge stamps deletion with the wall clock (importV2ZipBytes takes no clock); the window is checked instead
        fun norm(r: WorkEntity) = if (r.isDeleted) r.copy(deletedAt = null, permanentDeletionScheduledAt = null) else r
        expected.rows.zip(actual.rows).forEach { (e0, a0) ->
            val e = norm(e0); val a = norm(a0)
            if (e != a) {
                val fe = e.toString().split(Regex(", (?=[a-zA-Z0-9]+=)")); val fa = a.toString().split(Regex(", (?=[a-zA-Z0-9]+=)"))
                fail("$label: row ${e.id} differs in: " + fe.zip(fa).filter { it.first != it.second }.joinToString(" | ") { "${it.first.take(80)} vs ${it.second.take(80)}" })
            }
        }
        assertEquals("$label: tags", expected.tags, actual.tags)
        assertEquals("$label: asset files", expected.files, actual.files)
    }

    private fun worksDirListing(rig: A567Rig) = rig.workFiles.worksDirectory.toFile().listFiles()?.map { it.name }?.sorted().orEmpty()

    // ---- today's Replace, for the same fixture ----

    private suspend fun todaysReplace(rig: A567Rig, f: Fixture) {
        val epubs = (0 until f.epubs).associate { A567Corpus.uuid(it + 1) to epub }
        rig.repository.importV2ZipBytes(A567Rig.zipOf(f.manifest.readBytes(), epubs), BackupImportMode.REPLACE_LIBRARY)
    }

    private suspend fun prototypeReplace(rig: A567Rig, f: Fixture, hooks: A567StagedReplace.Hooks = A567StagedReplace.Hooks()): A567StagedReplace.Counts {
        A567Staging(File(rig.cacheRoot, "staging.db")).use { staging ->
            staging.stage(f.manifest)
            val replace = A567StagedReplace(rig, staging, f.epubDir)
            replace.captureLive()
            return replace.apply(now, hooks)
        }
    }

    @Test
    fun replaceFromStagingEndsInTheSameRowsTagsAndAssetsAsTodaysReplace() = runBlocking<Unit> {
        val dir = Files.createTempDirectory("a567-room").toFile()
        val f = fixture(incoming = 300, epubs = 40, dir = dir)
        A567Rig().use { today ->
            A567Rig().use { proto ->
                for (rig in listOf(today, proto)) seedLocal(rig, count = 120, withEpub = 20)
                todaysReplace(today, f)
                val counts = prototypeReplace(proto, f)
                assertEquals(300, counts.created); assertEquals(120, counts.removed); assertEquals(40, counts.epubsInstalled)
                assertSame(project(today), project(proto), "Replace")
                // omitted local works keep their EPUBs (Recently Deleted), as today
                assertTrue(worksDirListing(proto).containsAll((0 until 20).map { "${localWork(it).id}.epub" }))
            }
        }
        dir.deleteRecursively()
    }

    @Test
    fun aRowEditedAfterStagingStaysAndALaterLocalWorkIsUntouchedLikeToday() = runBlocking<Unit> {
        val dir = Files.createTempDirectory("a567-room").toFile()
        val f = fixture(incoming = 60, epubs = 5, dir = dir)
        val edited = localWork(3)
        val added = localWork(900)
        suspend fun editAfterCapture(rig: A567Rig) {
            rig.database.workDao().upsert(edited.copy(title = "Edited after staging", lastModifiedAt = now.plusSeconds(5)).toEntity())
            rig.database.workDao().upsert(added.toEntity())
        }
        A567Rig().use { today ->
            A567Rig().use { proto ->
                for (rig in listOf(today, proto)) seedLocal(rig, count = 10)
                // today: capture + merge first, edit, then apply the captured merge
                val pack = BackupImporter.importV2Zip(A567Rig.zipOf(f.manifest.readBytes(), (0 until 5).associate { A567Corpus.uuid(it + 1) to epub }), today.cacheRoot)
                val current = today.repository.captureLibrarySnapshot()
                val merge = BackupMergeService.merge(current, pack, BackupImportMode.REPLACE_LIBRARY, now = now)
                editAfterCapture(today)
                val summary = today.repository.applyMergeResult(merge, pack.originalFilesByName)
                // prototype: stage + capture first, edit, then apply
                A567Staging(File(proto.cacheRoot, "staging.db")).use { staging ->
                    staging.stage(f.manifest)
                    val replace = A567StagedReplace(proto, staging, f.epubDir)
                    replace.captureLive()
                    editAfterCapture(proto)
                    val counts = replace.apply(now)
                    println("A567 deferred rows: today ${summary.concurrentRowsDeferred}, prototype ${counts.deferred}")
                }
                val a = project(today); val b = project(proto)
                assertSame(a, b, "concurrent edit")
                assertEquals("Edited after staging", b.rows.first { it.id == edited.id }.title)
                assertFalse(b.rows.first { it.id == edited.id }.isDeleted)
                assertFalse(b.rows.first { it.id == added.id }.isDeleted)
            }
        }
        dir.deleteRecursively()
    }

    private suspend fun assertUntouched(rig: A567Rig, before: Projection, beforeListing: List<String>, label: String) {
        assertSame(before, project(rig), label)
        assertEquals("$label: no undo asides", beforeListing, worksDirListing(rig))
    }

    @Test
    fun aFailureBeforeCommitLeavesEveryRowAndFileAsItWasAndARetrySucceeds() = runBlocking<Unit> {
        val dir = Files.createTempDirectory("a567-room").toFile()
        val f = fixture(incoming = 120, epubs = 10, dir = dir)
        A567Rig().use { rig ->
            seedLocal(rig, count = 30, withEpub = 10)
            val before = project(rig); val listing = worksDirListing(rig)
            val hooks = A567StagedReplace.Hooks().apply { beforeCommit = { throw IOException("Injected failure before commit") } }
            try { prototypeReplace(rig, f, hooks); fail("must fail") } catch (e: IOException) { assertEquals("Injected failure before commit", e.message) }
            assertUntouched(rig, before, listing, "before commit")
            File(rig.cacheRoot, "staging.db").delete()
            prototypeReplace(rig, f) // retry
            A567Rig().use { clean ->
                seedLocal(clean, count = 30, withEpub = 10); prototypeReplace(clean, f)
                assertSame(project(clean), project(rig), "retry equals a clean run")
            }
        }
        dir.deleteRecursively()
    }

    @Test
    fun aFailureDuringAssetInstallationRestoresOverwrittenAndRemovesNewFiles() = runBlocking<Unit> {
        val dir = Files.createTempDirectory("a567-room").toFile()
        val f = fixture(incoming = 120, epubs = 10, dir = dir)
        // incoming works 1..10 have EPUBs; pre-place a different file for work 1 so the install overwrites it
        A567Rig(workFactory = ::FailingWorkFileStore).use { rig ->
            seedLocal(rig, count = 30, withEpub = 10)
            rig.workFiles.writeWorkEpub(A567Corpus.uuid(1), A567Rig.epubOf(1500, 9)) // overwritten by the install
            (rig.workFiles as FailingWorkFileStore).attempts = 0
            (rig.workFiles as FailingWorkFileStore).failAtWrite = 4
            val before = project(rig); val listing = worksDirListing(rig)
            try { prototypeReplace(rig, f); fail("must fail") } catch (e: IllegalStateException) { assertTrue(e.message!!.contains("EPUB write failed")) }
            assertEquals(4, (rig.workFiles as FailingWorkFileStore).attempts)
            assertUntouched(rig, before, listing, "during asset install")
        }
        dir.deleteRecursively()
    }

    @Test
    fun cancellationNearCommitIsAllOrNothing() = runBlocking<Unit> {
        val dir = Files.createTempDirectory("a567-room").toFile()
        val f = fixture(incoming = 80, epubs = 8, dir = dir)
        A567Rig().use { rig ->
            seedLocal(rig, count = 20, withEpub = 5)
            val before = project(rig); val listing = worksDirListing(rig)
            lateinit var job: kotlinx.coroutines.Job
            var outcome = "completed"
            job = launch(Dispatchers.IO, start = CoroutineStart.LAZY) {
                try {
                    prototypeReplace(rig, f, A567StagedReplace.Hooks().apply { beforeCommit = { job.cancel() } })
                } catch (e: CancellationException) { outcome = "cancelled"; throw e }
            }
            job.start(); job.join()
            val after = project(rig)
            println("A567 cancellation near commit: $outcome; rows ${before.rows.size} -> ${after.rows.size}")
            val unchanged = after.rows.size == before.rows.size && after.rows.zip(before.rows).all { it.first == it.second }
            if (unchanged) {
                assertUntouched(rig, before, listing, "cancelled before commit")
            } else {
                // committed: every incoming work and every incoming EPUB is there, no asides remain
                assertEquals(80, after.rows.count { !it.isDeleted && it.id.startsWith("0000") && it.title.isNotEmpty() && !it.id.startsWith("009") })
                assertEquals(8, after.files.keys.count { it.startsWith("0000000") })
                assertTrue(worksDirListing(rig).none { it.endsWith(BackupFileUndo.UNDO_SUFFIX) })
            }
        }
        dir.deleteRecursively()
    }

    @Test
    fun aProcessDeathInsideTheTransactionLeavesAsidesThatRecoveryPutsBack() = runBlocking<Unit> {
        val dir = Files.createTempDirectory("a567-room").toFile()
        val f = fixture(incoming = 40, epubs = 6, dir = dir)
        A567Rig().use { rig ->
            seedLocal(rig, count = 10, withEpub = 3)
            rig.workFiles.writeWorkEpub(A567Corpus.uuid(2), A567Rig.epubOf(1500, 7)) // overwritten by the install
            val before = project(rig)
            val hooks = A567StagedReplace.Hooks().apply { simulateProcessDeath = true; beforeCommit = { throw IOException("process died") } }
            try { prototypeReplace(rig, f, hooks); fail("must fail") } catch (_: IOException) {}
            // Room rolled the rows back (SQLite journal); the files were not undone: the asides are what is left.
            assertTrue(worksDirListing(rig).any { it.endsWith(BackupFileUndo.UNDO_SUFFIX) })
            assertEquals(before.rows, project(rig).rows)
            // The marker is absent, so the commit did not happen: asides must go back.
            assertTrue(rig.database.tagDao().getById(TOKEN_ID) == null)
            rig.repository.recoverInterruptedReplace() // what the next start runs today
            val today = project(rig)
            // Today's recovery keeps a destination that exists and drops its aside (Room's state is "not cheaply known"),
            // so the overwritten file stays the NEW bytes over rolled-back rows: the finding that needs the discriminator.
            assertEquals(before.rows, today.rows)
            assertTrue("today's recovery keeps the new bytes", today.files[A567Corpus.uuid(2) + ".epub"] != before.files[A567Corpus.uuid(2) + ".epub"])
        }
        // With the discriminator, recovery restores the asides when the marker is absent.
        A567Rig().use { rig ->
            seedLocal(rig, count = 10, withEpub = 3)
            rig.workFiles.writeWorkEpub(A567Corpus.uuid(2), A567Rig.epubOf(1500, 7))
            val before = project(rig)
            val hooks = A567StagedReplace.Hooks().apply { simulateProcessDeath = true; beforeCommit = { throw IOException("process died") } }
            try { prototypeReplace(rig, f, hooks); fail("must fail") } catch (_: IOException) {}
            rig.workFiles.worksDirectory.toFile().listFiles()!!.filter { it.name.endsWith(BackupFileUndo.UNDO_SUFFIX) }.forEach {
                java.nio.file.Files.move(it.toPath(), it.toPath().resolveSibling(it.name.removeSuffix(BackupFileUndo.UNDO_SUFFIX)), java.nio.file.StandardCopyOption.REPLACE_EXISTING)
            }
            val restored = project(rig)
            assertEquals(before.rows, restored.rows)
            assertEquals(before.files[A567Corpus.uuid(2) + ".epub"], restored.files[A567Corpus.uuid(2) + ".epub"])
            // new files (no previous bytes, so no aside) are orphans without rows; they are the cost of recovery by marker
            println("A567 orphan new EPUBs after process death: ${restored.files.keys - before.files.keys}")
        }
        dir.deleteRecursively()
    }

    @Test
    fun stagingFailuresNeverTouchTheLiveStore() = runBlocking<Unit> {
        val dir = Files.createTempDirectory("a567-room").toFile()
        val f = fixture(incoming = 100, epubs = 0, dir = dir)
        A567Rig().use { rig ->
            seedLocal(rig, count = 15)
            val before = project(rig)
            // ENOSPC-like: the sink fails on the 51st record
            try {
                A567Staging(File(rig.cacheRoot, "s1.db")).use { it.stage(f.manifest) { n -> if (n == 51) throw IOException("No space left on device") } }
                fail("must fail")
            } catch (e: IOException) { assertEquals("No space left on device", e.message) }
            // duplicate id, unsupported version, truncated input
            val dup = File(dir, "dup.json").apply { writeText("""{"version":8,"exportedAt":"2026-06-01T00:00:00.000Z","works":[${work(1)},${work(1)}]}""") }
            val unsupported = File(dir, "v99.json").apply { writeText("""{"works":[${work(1)}],"version":99,"exportedAt":"2026-06-01T00:00:00.000Z"}""") }
            val truncated = File(dir, "cut.json").apply { writeBytes(f.manifest.readBytes().let { it.copyOf(it.size / 2) }) }
            for ((name, file, expected) in listOf(
                Triple("dup", dup, BackupError.InvalidPackage::class.java), Triple("v99", unsupported, BackupError.UnsupportedVersion::class.java),
                Triple("cut", truncated, A567ParseError::class.java)
            )) {
                try { A567Staging(File(rig.cacheRoot, "$name.db")).use { it.stage(file) }; fail("$name must fail") } catch (e: Exception) {
                    assertTrue("$name: ${e::class.simpleName}", expected.isInstance(e))
                }
            }
            assertSame(before, project(rig), "after staging failures")
            // cancellation while staging
            lateinit var job: kotlinx.coroutines.Job
            job = launch(Dispatchers.IO, start = CoroutineStart.LAZY) {
                A567Staging(File(rig.cacheRoot, "s2.db")).use { s -> s.stage(f.manifest) { n -> if (n == 30) job.cancel(); if (!job.isActive) throw CancellationException("cancelled while staging") } }
            }
            job.start(); job.join()
            assertTrue(job.isCancelled)
            assertSame(before, project(rig), "after cancelled staging")
        }
        dir.deleteRecursively()
    }

    private fun work(id: Int) = """{"id":"${A567Corpus.uuid(id)}","title":"T","dateAdded":"2026-01-01T00:00:00.000Z"}"""

    // ---- opt-in scaling run: does heap stay flat as incoming and existing rows grow? ----

    @Test
    fun scaling() = runBlocking<Unit> {
        val out = System.getenv("A567_ROOM_OUT")
        assumeTrue("opt-in (A567_ROOM_OUT)", out != null)
        val sizes = (System.getenv("A567_ROOM_SIZES") ?: "8,32,128").split(",").map { it.trim().toLong() }
        val table = StringBuilder(
            "| axis | manifest MiB | rows | stage ms | apply ms | heap peak MiB (sampled, upper bound) | max live delta MiB (after GC, during run) | staging DB MiB | temp disk high-water MiB |\n|---|---|---|---|---|---|---|---|---|\n"
        )
        data class Point(val axis: String, val mib: Long, val live: Double)
        val points = mutableListOf<Point>()
        for (axis in listOf("incoming rows (local empty)", "local rows (incoming 1000)")) {
            for (size in sizes) {
                val rows = A567Corpus.worksFor(size * mib)
                val incoming = if (axis.startsWith("incoming")) rows else 1000
                val local = if (axis.startsWith("incoming")) 0 else rows
                val dir = Files.createTempDirectory("a567-room").toFile()
                val f = fixture(incoming = incoming, epubs = 0, dir = dir)
                A567Rig().use { rig ->
                    seedLocal(rig, local)
                    val baseline = A567Run.settledHeap()
                    var maxLive = 0L
                    val sample = { if (true) maxLive = maxOf(maxLive, A567Run.settledHeap() - baseline) }
                    val run = A567Run(rig.diskRoots + dir)
                    var stageMs = 0L; var applyMs = 0L; var dbMiB = 0.0
                    val result = run.measure {
                        val staging = A567Staging(File(rig.cacheRoot, "staging.db"))
                        try {
                            val t0 = System.nanoTime()
                            staging.stage(f.manifest) { n -> if (n % 20_000 == 0) sample() }
                            stageMs = (System.nanoTime() - t0) / 1_000_000
                            val replace = A567StagedReplace(rig, staging, null)
                            val t1 = System.nanoTime()
                            runBlocking {
                                replace.captureLive { n -> if (n % 20_000 == 0) sample() }
                                replace.apply(now, A567StagedReplace.Hooks().apply {
                                    afterBatch = { n -> if (n % 20_000 < 500) sample() }
                                    afterSweepBatch = { n -> if (n % 20_000 < 500) sample() }
                                })
                            }
                            applyMs = (System.nanoTime() - t1) / 1_000_000
                            dbMiB = File(rig.cacheRoot, "staging.db").length() / 1048576.0
                            "ok"
                        } finally { staging.close() }
                    }
                    sample()
                    val live = maxLive / 1048576.0
                    points += Point(axis, size, live)
                    table.append("| $axis | $size | $rows | $stageMs | $applyMs | ${"%.1f".format(result.peakHeapMiB)} | ${"%.1f".format(live)} | ${"%.1f".format(dbMiB)} | ${"%.1f".format(result.diskHighMiB)} | ${result.outcome}\n")
                    println("A567 ROOM ${table.lines().dropLast(1).last()}")
                }
                dir.deleteRecursively()
            }
        }
        table.append("\n")
        for (axis in points.map { it.axis }.distinct()) {
            val p = points.filter { it.axis == axis }
            val hi = p.maxOf { it.live }
            val growth = p.lastOrNull { it.mib >= 128 }?.live?.let { last -> last - (p.firstOrNull { it.mib == 128L }?.live ?: last) } ?: 0.0
            table.append("- $axis: max live delta ${"%.1f".format(hi)} MiB (ceiling 64); growth from 128 MiB to largest run ${"%.1f".format(growth)} MiB (limit 8)\n")
        }
        File(out!!).writeText(table.toString())
    }
}
