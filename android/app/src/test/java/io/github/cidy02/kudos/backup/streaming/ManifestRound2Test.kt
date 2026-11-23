package io.github.cidy02.kudos.backup.streaming

import io.github.cidy02.kudos.backup.A567Corpus
import io.github.cidy02.kudos.backup.BackupCollection
import io.github.cidy02.kudos.backup.BackupError
import io.github.cidy02.kudos.backup.BackupImportMode
import io.github.cidy02.kudos.backup.BackupLibrarySnapshot
import io.github.cidy02.kudos.backup.BackupMergeService
import io.github.cidy02.kudos.backup.KudosBackupManifest
import io.github.cidy02.kudos.backup.KudosBackupPackage
import io.github.cidy02.kudos.core.model.WorkCollection
import java.io.ByteArrayInputStream
import java.io.File
import java.io.IOException
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** A-567 P2 round 2: Codex parity review findings (Android) and the shared decisions of 2026-11-23. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ManifestRound2Test {
    @get:Rule val tmp = TemporaryFolder()
    private val root get() = File(tmp.root, "staging")
    private val now = Instant.parse("2026-06-15T00:00:00Z")

    private fun doc(body: String) = """{"version":8,"exportedAt":"2026-06-01T00:00:00.000Z",$body}"""
    private fun work(id: Int, extra: String = "") = """{"id":"${A567Corpus.uuid(id)}","title":"T","dateAdded":"2026-01-01T00:00:00.000Z"$extra}"""
    private fun stage(text: String, o: ManifestStageOptions = ManifestStageOptions()) = ManifestStager.stage(ByteArrayInputStream(text.toByteArray()), root, o)
    private fun left() = root.list()?.toList().orEmpty()

    private inline fun <reified T : ManifestStageException> fails(block: () -> StagedManifest): T {
        try {
            block().close()
        } catch (e: ManifestStageException) {
            assertTrue("expected ${T::class.simpleName}, got $e", e is T)
            assertEquals(emptyList<String>(), left())
            return e as T
        }
        fail("accepted"); error("unreachable")
    }

    // --- strict rows over the typed budget ---
    @Test fun aStrictRecordPastTheBudgetIsNeverReturnedAsAnApplyReadyRun() {
        val big = StagingSink.TYPED_BUDGET_BYTES.toInt()
        // 1 MiB + 1 without an id: strict decode rejects it (schema), no longer staged as "unchecked"
        val e = fails<ManifestStageException.Invalid> { stage(doc("\"works\":[{\"x\":\"${"a".repeat((1 shl 20) - 7)}\"}]")) }
        assertFalse(e.syntactic)
        fails<ManifestStageException.ResourceExhausted> { stage(doc("\"works\":[{\"x\":\"${"a".repeat(big - 7)}\"}]")) }
    }

    @Test fun theBudgetIsDecidedAtEofSoALaterSyntaxErrorOrIoFailureWins() {
        val huge = doc("\"works\":[{\"x\":\"${"a".repeat(StagingSink.TYPED_BUDGET_BYTES.toInt())}\"}]")
        assertTrue(fails<ManifestStageException.Invalid> { stage("$huge x") }.syntactic)
        val bytes = huge.toByteArray()
        var served = 0
        fails<ManifestStageException.Io> {
            ManifestStager.stage(object : java.io.InputStream() {
                override fun read(): Int = throw IOException("gone")
                override fun read(b: ByteArray, off: Int, len: Int): Int {
                    if (served >= bytes.size - 5) throw IOException("gone")
                    val n = minOf(len, bytes.size - 5 - served); System.arraycopy(bytes, served, b, off, n); served += n; return n
                }
            }, root)
        }
    }

    @Test fun aRecordUnderTheBudgetIsDecodedWithTheSamePathAsTheReader() {
        // a record the old in-memory decode and the tree decode would treat the same, but spilled to chunk rows (> 1 MiB)
        stage(doc("\"works\":[${work(1, ",\"summary\":\"${"s".repeat(3_000_000)}\"")}]")).use { s ->
            s.db.rawQuery("SELECT oversize, typed_ok FROM s_works", null).use { c -> c.moveToFirst(); assertEquals(1, c.getInt(0)); assertEquals(1, c.getInt(1)) }
        }
        fails<ManifestStageException.Invalid> { stage(doc("\"works\":[{\"title\":\"${"s".repeat(3_000_000)}\"}]")) }
    }

    // --- shared byte-exact behaviours not covered by the fixture index ---
    @Test fun nulInKeysAndIndexedStringsSurvive() {
        stage(doc("\"works\":[${work(1, ",\"sourceURL\":\"x\\u0000y\"")},${work(2, ",\"sourceURL\":\"x\"")}],\"a\":0,\"a\\u0000\":1")).use { s ->
            assertEquals(listOf("version", "exportedAt", "works", "a", "a\u0000"), s.rootEntries().map { it.key })
            val urls = s.records("works").map { it.keys["k_url"] }
            assertEquals(listOf("x\u0000y", "x"), urls)
            s.db.rawQuery("SELECT hex(k_url) FROM s_works ORDER BY ord", null).use { c -> c.moveToFirst(); assertEquals("780079", c.getString(0)) }
        }
    }

    @Test fun compositeIdentitiesAreSeparateColumnsSoDifferentPairsStayDifferent() {
        val a = "{\"id\":\"${A567Corpus.uuid(1)}\",\"kindRaw\":\"work\\u0000x\",\"targetKey\":\"y\"}"
        val b = "{\"id\":\"${A567Corpus.uuid(2)}\",\"kindRaw\":\"work\",\"targetKey\":\"x\\u0000y\"}"
        stage(doc("\"works\":[],\"readingFavorites\":[$a,$b]")).use { s ->
            val m = s.records("readingFavorites")
            assertEquals(listOf("work\u0000x" to "y", "work" to "x\u0000y"), m.map { it.keys["k_kind"] to it.keys["k_target"] })
            s.db.rawQuery("SELECT ord FROM s_readingFavorites WHERE k_kind = ? AND k_target = ?", arrayOf("work", "x\u0000y")).use { c -> assertTrue(c.moveToFirst()); assertEquals(1, c.getInt(0)); assertFalse(c.moveToNext()) }
        }
    }

    @Test fun nothingGeneratedIsStoredSoReconstructionIsDeterministic() {
        val text = doc("\"works\":[${work(1)}],\"bookmarks\":[{\"title\":\"\",\"urlString\":\"https://x\",\"dateAdded\":\"2026-01-01T00:00:00Z\"}]")
        stage(text).use { s ->
            val first = s.reconstruct(); val second = s.reconstruct()
            assertEquals(first.first, second.first)
            assertEquals(null, first.first.bookmarks.single().id) // no id is invented on the way in
            s.validate(now)
        }
    }

    // --- bounded consumption API ---
    @Test fun aRangeReadTouchesOnlyTheChunksItOverlaps() {
        val blob = (0 until 400_000).joinToString("") { ('a' + it % 26).toString() }
        stage(doc("\"works\":[${work(1, ",\"zzz\":\"$blob\"")}]")).use { s ->
            val r = s.unknownRanges("works", 0).single()
            val pieces = mutableListOf<CharSequence>()
            s.readRecord("works", 0, r.start + 100_000, r.start + 100_050) { pieces += it.toString() }
            assertEquals(1, pieces.size)
            assertEquals(50, pieces.single().length)
            val all = StringBuilder(); var n = 0
            s.readRecord("works", 0, r.start, r.stop) { assertTrue(it.length <= StagingWriter.CHUNK_CHARS); all.append(it); n++ }
            assertEquals("\"zzz\":\"$blob\"", all.toString())
            assertTrue(n >= 6)
            s.readRoot("exportedAt", 1, 5) { assertEquals("2026", it.toString()) }
        }
    }

    @Test fun rowMetadataIsAKeysetCursorWithoutPayloads() {
        stage(doc("\"works\":[${(1..25).joinToString(",") { work(it) }}]")).use { s ->
            val first = s.records("works", limit = 10)
            val second = s.records("works", afterOrd = first.last().ord, limit = 10)
            val third = s.records("works", afterOrd = second.last().ord, limit = 10)
            assertEquals((0L..24L).toList(), (first + second + third).map { it.ord })
            assertEquals(A567Corpus.uuid(3), first[2].keys["k_id"])
            assertEquals(5, third.size)
        }
    }

    @Test fun validationRunsOverTheFinalMetadataNotPerBatch() {
        // the same id 300 records apart: different 200-row batches, still a duplicate
        val works = (1..320).map { if (it == 310) work(5) else work(it) }.joinToString(",")
        stage(doc("\"works\":[$works]")).use { s ->
            try { s.validate(now); fail("accepted") } catch (e: BackupError.InvalidPackage) { assertTrue(e.message!!.contains("Duplicate")) }
        }
        stage(doc("\"works\":[${work(1)},{\"id\":\"nope\"}]")).use { s ->
            try { s.validate(now); fail("accepted") } catch (e: BackupError.InvalidUuid) { /* expected */ }
        }
        stage(doc("\"works\":[${work(1)}]")).use { it.validate(now) }
    }

    // --- presence and Replace policy ---
    @Test fun presenceDistinguishesMissingNullEmptyAndPopulated() {
        fun p(body: String) = stage(doc("\"works\":[]$body")).use { it.presence("collections") }
        assertEquals(SectionPresence.MISSING, p(""))
        assertEquals(SectionPresence.NULL, p(",\"collections\":null"))
        assertEquals(SectionPresence.EMPTY, p(",\"collections\":[]"))
        val c = "{\"id\":\"${A567Corpus.uuid(9)}\",\"name\":\"n\",\"dateAdded\":\"2026-01-01T00:00:00.000Z\"}"
        assertEquals(SectionPresence.POPULATED, p(",\"collections\":[$c]"))
    }

    @Test fun replacePolicyForTheFourGuardedSectionsAgainstPopulatedLocalState() {
        val local = setOf("a", "b", "c")
        for (section in ReplacePolicy.guardedSections) {
            assertEquals(section, local, ReplacePolicy.survivors(section, SectionPresence.MISSING, local, emptySet()))
            assertEquals(section, local, ReplacePolicy.survivors(section, SectionPresence.NULL, local, emptySet()))
            assertEquals(section, emptySet<String>(), ReplacePolicy.survivors(section, SectionPresence.EMPTY, local, emptySet()))
            assertEquals(section, setOf("a"), ReplacePolicy.survivors(section, SectionPresence.POPULATED, local, setOf("a", "z")))
        }
        // the other sections keep today's collapsed behaviour
        assertEquals(emptySet<String>(), ReplacePolicy.survivors("works", SectionPresence.MISSING, local, emptySet()))
        assertEquals(setOf("works", "collections").size, ReplacePolicy.guardedSections.intersect(setOf("works", "collections", "x")).size + 1)
    }

    @Test fun todaysAndroidReplaceCollapsesMissingNullAndEmptySoTheyAreNotWiredYet() {
        val local = WorkCollection(id = A567Corpus.uuid(7), name = "Local only", dateAdded = now)
        fun replaceWith(text: String): List<WorkCollection> = stage(text).use { s ->
            val (manifest, _) = s.reconstruct()
            BackupMergeService.merge(BackupLibrarySnapshot(collections = listOf(local)), KudosBackupPackage(manifest = manifest, epubFilesByWorkId = emptyMap(), fontFilesByFileName = emptyMap()), BackupImportMode.REPLACE_LIBRARY).snapshot.collections
        }
        // today all three shapes drop the local collection; the policy would keep it for missing and null
        for (body in listOf("\"works\":[]", "\"works\":[],\"collections\":null", "\"works\":[],\"collections\":[]")) {
            assertEquals(body, emptyList<WorkCollection>(), replaceWith(doc(body)))
        }
        assertEquals(setOf(local.id), ReplacePolicy.survivors("collections", SectionPresence.MISSING, setOf(local.id), emptySet()))
    }

    // --- outcome precedence and boundaries ---
    @Test fun cancellationOutranksASyntaxError() {
        var polls = 0
        fails<ManifestStageException.Cancelled> { stage("{\"version\":8,x", ManifestStageOptions(isCancelled = { polls++ >= 1 })) }
    }

    @Test fun aLimitHitBeforeAMalformedTailStillReportsSyntax() {
        assertTrue(fails<ManifestStageException.Invalid> { stage(doc("\"k\":${"1".repeat(70_000)},\"works\":[}")) }.syntactic)
    }

    @Test fun diskIsCheckedAtTheFinalCommitAndDuringIndexBuildEvenForATinyManifest() {
        var calls = 0
        stage(doc("\"works\":[${work(1)}]"), ManifestStageOptions(freeSpace = { calls++; 1L shl 40 })).close()
        // preflight, the post-parse commit, one check before each of the indexes and after the last two steps: no boundary may drop out
        val indexes = ManifestSections.all.sumOf { it.keys.size + it.compositeIndexes.size }
        assertEquals(1 + 1 + indexes + 2, calls)
        for (lowFrom in listOf(1, 2, calls - 1)) {
            var n = 0
            val e = fails<ManifestStageException.ResourceExhausted> { stage(doc("\"works\":[${work(1)}]"), ManifestStageOptions(freeSpace = { if (n++ < lowFrom) 1L shl 40 else 1024L })) }
            assertTrue(e.reason, e.reason.contains("disk"))
        }
    }

    @Test fun cancellationIsCheckedAfterParseDuringFinalizationAndBeforeReturning() {
        var calls = 0
        stage(doc("\"works\":[${work(1)}]"), ManifestStageOptions(freeSpace = { calls++; 1L shl 40 })).close()
        for (flipAt in listOf(2, 3, calls)) {
            var n = 0; var flag = false
            fails<ManifestStageException.Cancelled> {
                stage(doc("\"works\":[${work(1)}]"), ManifestStageOptions(isCancelled = { flag }, freeSpace = { if (++n == flipAt) flag = true; 1L shl 40 }))
            }
        }
    }

    @Test fun theStagingComponentBudgetIsEnforcedWhateverTheFreeSpace() {
        val bytes = A567Corpus.manifestBytesOfSize(20L shl 20)
        val e = fails<ManifestStageException.ResourceExhausted> {
            ManifestStager.stage(ByteArrayInputStream(bytes), root, ManifestStageOptions(expectedBytes = 1, freeSpace = { 1L shl 40 }))
        }
        assertTrue(e.reason, e.reason.contains("budget"))
    }

    @Test fun keyMemoryHeldByOpenObjectsIsBounded() {
        val keys = (0 until ManifestTokenizer.MAX_MEMBERS).joinToString(",") { "\"" + "k%06d".format(it).padEnd(65, 'x') + "\":0" }
        fails<ManifestStageException.ResourceExhausted> { stage(doc("\"x\":{$keys}")) }
    }

    // --- lifecycle ---
    @Test fun theDatabaseIsClosedWhenInitialisationFails() {
        val dir = File(tmp.root, "init").also { it.mkdirs() }
        File(dir, StagingWriter.MARKER).mkdirs() // the marker cannot be written
        var opened: android.database.sqlite.SQLiteDatabase? = null
        try {
            StagingWriter(dir, { 1L shl 40 }, null, {}, onOpened = { opened = it })
            fail("initialised")
        } catch (e: IOException) {
            // expected
        }
        assertNotNull(opened)
        assertFalse(opened!!.isOpen)
    }

    @Test fun aStartupSweepRemovesOnlyStaleMarkedRuns() {
        root.mkdirs()
        fun run(name: String, marker: Boolean, ageMillis: Long) = File(root, name).also {
            it.mkdirs(); File(it, "staging.db").writeText("x")
            if (marker) File(it, StagingWriter.MARKER).apply { writeText("run"); setLastModified(System.currentTimeMillis() - ageMillis) }
        }
        val stale = run("manifest-stale", true, 3 * 3_600_000L)
        val fresh = run("manifest-fresh", true, 1_000L)
        val unmarked = run("manifest-unmarked", false, 0)
        val foreign = run("somebody-else", true, 3 * 3_600_000L)
        val result = ManifestStager.sweepStaleRuns(root)
        assertEquals(listOf(stale), result.deleted)
        assertEquals(emptyList<File>(), result.failed)
        assertTrue(fresh.exists() && unmarked.exists() && foreign.exists() && !stale.exists())
    }

    @Test fun aCleanupThatFailsIsReportedNotSwallowed() {
        val bytes = A567Corpus.manifestBytesOfSize(3_000_000)
        var lockedDir: File? = null
        try {
            val e = fails0 {
                ManifestStager.stage(ByteArrayInputStream(bytes), root, ManifestStageOptions(checkpoint = {
                    lockedDir = root.listFiles()!!.single().also { d -> d.setWritable(false) }
                    throw IOException("boom")
                }))
            }
            assertTrue(e.suppressed.any { it is IOException && it.message!!.contains("could not delete") })
        } finally {
            lockedDir?.setWritable(true)
        }
    }

    private fun fails0(block: () -> StagedManifest): Throwable {
        try { block().close() } catch (e: ManifestStageException) { return e }
        fail("accepted"); error("unreachable")
    }
}
