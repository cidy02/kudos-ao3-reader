package io.github.cidy02.kudos.backup.streaming

import io.github.cidy02.kudos.backup.A567Corpus
import io.github.cidy02.kudos.backup.BackupValidator
import java.io.ByteArrayInputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ManifestStagingTest {
    @get:Rule val tmp = TemporaryFolder()

    private val root get() = File(tmp.root, "staging")

    private fun stage(text: String, options: ManifestStageOptions = ManifestStageOptions()) =
        ManifestStager.stage(ByteArrayInputStream(text.toByteArray()), root, options)

    private fun stage(bytes: ByteArray, options: ManifestStageOptions = ManifestStageOptions()) =
        ManifestStager.stage(ByteArrayInputStream(bytes), root, options)

    private fun leftovers() = root.list()?.toList().orEmpty()

    private fun doc(body: String, version: String = "8") =
        """{"version":$version,"exportedAt":"2026-06-01T00:00:00.000Z",$body}"""

    private fun work(id: Int = 1, extra: String = "") =
        """{"id":"${A567Corpus.uuid(id)}","title":"T","dateAdded":"2026-01-01T00:00:00.000Z"$extra}"""

    private inline fun <reified T : ManifestStageException> failing(input: () -> StagedManifest): T {
        try {
            input().close()
        } catch (e: ManifestStageException) {
            assertTrue("expected ${T::class.simpleName}, got $e", e is T)
            assertEquals("staging left files behind after $e", emptyList<String>(), leftovers())
            return e as T
        }
        fail("accepted")
        error("unreachable")
    }

    @Test fun reconstructsTheTypedManifestAndRawViewTodaysRouteProduces() {
        val bytes = A567Corpus.manifestBytesOfSize(300_000)
        val (today, todayRaw) = BackupValidator.decodeManifestWithRaw(bytes)
        stage(bytes).use { staged ->
            val (typed, raw) = staged.reconstruct()
            assertEquals(today, BackupValidator.validateManifest(typed))
            assertEquals(todayRaw, raw)
            assertEquals(8, staged.version)
            assertEquals(today.works.size.toLong(), staged.count("works"))
            assertEquals(today.readingSessions.size.toLong(), staged.count("readingSessions"))
            assertEquals(today.annotations.size.toLong(), staged.count("annotations"))
        }
        assertEquals(emptyList<String>(), leftovers())
    }

    @Test fun rootMetadataAfterTheArraysIsStillSeen() {
        val bytes = java.io.ByteArrayOutputStream().also { A567Corpus.writeManifest(it, works = 20, sessionsPerWork = 2, annotations = 5, metaAfter = true) }.toByteArray()
        stage(bytes).use { staged ->
            assertEquals(8, staged.version)
            assertEquals(listOf("works", "readingSessions", "annotations", "iosFutureTopLevel", "version", "exportedAt"), staged.rootEntries().map { it.key })
            assertEquals(false, staged.rootEntries().first { it.key == "iosFutureTopLevel" }.known)
        }
    }

    @Test fun anUnsupportedVersionAfterTheArraysIsReportedOnlyAfterEof() {
        val e = failing<ManifestStageException.UnsupportedVersion> { stage("""{"works":[${work()}],"version":9,"exportedAt":"2026-06-01T00:00:00.000Z"}""") }
        assertEquals(9, e.version)
        // a syntax error after the version wins over it, as the whole document is read first
        failing<ManifestStageException.Invalid> { stage("""{"version":9,"exportedAt":"2026-06-01T00:00:00.000Z","works":[}""") }
    }

    @Test fun aTypedDecodeFailureBeatsAnUnsupportedVersion() {
        val e = failing<ManifestStageException.Invalid> { stage(doc("\"works\":[{\"title\":\"no id\"}]", "9")) }
        assertEquals(false, e.syntactic)
    }

    @Test fun invalidSyntaxIsFlaggedSyntactic() {
        assertEquals(true, failing<ManifestStageException.Invalid> { stage(doc("\"works\":[") + "x") }.syntactic)
    }

    @Test fun aWrongKindSectionOrNullElementIsASchemaFailure() {
        for (body in listOf("\"works\":{}", "\"works\":\"x\"", "\"works\":[1]", "\"annotations\":[null]", "\"settings\":[]", "\"readingSessions\":5")) {
            val e = failing<ManifestStageException.Invalid> { stage(doc(body)) }
            assertEquals(body, false, e.syntactic)
        }
        stage(doc("\"works\":null")).use { assertEquals(0L, it.count("works")) } // null section: today's default
    }

    @Test fun theFirstValueOfADuplicateKeyWins() {
        stage("""{"version":8,"version":99,"exportedAt":"2026-06-01T00:00:00.000Z","exportedAt":"x","works":[${work(1)}],"works":[${work(2)}]}""").use { s ->
            assertEquals(8, s.version)
            val raw = s.reconstructRaw()
            assertEquals("2026-06-01T00:00:00.000Z", raw["exportedAt"]!!.jsonPrimitive.content)
            assertEquals(listOf(A567Corpus.uuid(1)), (raw["works"] as JsonArray).map { (it as JsonObject)["id"]!!.jsonPrimitive.content })
            assertEquals(1L, s.count("works"))
        }
        stage(doc("\"works\":[{\"id\":\"${A567Corpus.uuid(1)}\",\"title\":\"a\",\"title\":\"b\",\"future\":{\"x\":1,\"x\":2,\"y\":[{\"z\":1,\"z\":2}]}}]")).use { s ->
            val rec = Json.parseToJsonElement(s.recordTextInMemory("works", 0)) as JsonObject
            assertEquals("a", rec["title"]!!.jsonPrimitive.content)
            assertEquals("""{"x":1,"y":[{"z":1}]}""", rec["future"].toString())
        }
    }

    @Test fun aSkippedDuplicateValueIsStillValidated() {
        failing<ManifestStageException.Invalid> { stage("""{"version":8,"version":[1,2,,3],"exportedAt":"x","works":[]}""") }
        failing<ManifestStageException.Invalid> { stage("""{"version":8,"exportedAt":"x","works":[],"works":["\ud800"]}""") }
    }

    @Test fun naturalKeysAreStagedNormalisedAndIndexed() {
        val upper = A567Corpus.uuid(255).uppercase()
        val body = "\"works\":[{\"id\":\"$upper\",\"title\":\"T\",\"dateAdded\":\"2026-01-01T00:00:00.000Z\",\"ao3WorkID\":12345,\"sourceURL\":\"https://archiveofourown.org/works/12345\"}]," +
            "\"fonts\":[{\"name\":\"Fancy Font\",\"fileName\":\"Café.ttf\",\"dateAdded\":\"2026-01-01T00:00:00.000Z\"}]," +
            "\"annotations\":[{\"id\":\"${A567Corpus.uuid(2)}\",\"workID\":\"$upper\",\"locatorString\":\"loc-1\"}]," +
            "\"readingFavorites\":[{\"id\":\"${A567Corpus.uuid(3)}\",\"kindRaw\":\"fandom\",\"targetKey\":\"Some Fandom\"}]," +
            "\"fandomReadWatermarks\":[{\"id\":\"${A567Corpus.uuid(4)}\",\"fandomName\":\"Some Fandom\"}]," +
            "\"tombstones\":[{\"id\":\"${A567Corpus.uuid(5)}\",\"recordID\":\"$upper\",\"recordTypeRaw\":\"work\",\"lastModifiedAt\":\"2026-02-01T00:00:00.000Z\"}]"
        stage(doc(body)).use { s ->
            fun one(sql: String) = s.db.rawQuery(sql, null).use { c -> c.moveToFirst(); c.getString(0) }
            val lower = A567Corpus.uuid(255)
            assertEquals(lower, one("SELECT k_id FROM s_works WHERE k_id = '$lower'"))
            assertEquals("12345", one("SELECT k_ao3 FROM s_works"))
            assertEquals("https://archiveofourown.org/works/12345", one("SELECT k_url FROM s_works"))
            assertEquals(java.text.Normalizer.normalize("Café.ttf", java.text.Normalizer.Form.NFC).lowercase(), one("SELECT k_file FROM s_fonts"))
            assertEquals("fancy font", one("SELECT k_name FROM s_fonts"))
            assertEquals("loc-1", one("SELECT k_locator FROM s_annotations"))
            assertEquals(lower, one("SELECT k_work FROM s_annotations"))
            assertEquals("fandom", one("SELECT k_kind FROM s_readingFavorites"))
            assertEquals("Some Fandom", one("SELECT k_target FROM s_readingFavorites"))
            assertEquals("Some Fandom", one("SELECT k_fandom FROM s_fandomReadWatermarks"))
            assertEquals("work", one("SELECT k_rtype FROM s_tombstones"))
            assertEquals(lower, one("SELECT k_rid FROM s_tombstones"))
            assertEquals("2026-02-01T00:00:00.000Z", one("SELECT k_stamp FROM s_tombstones"))
            for ((table, column) in listOf("s_works" to "k_id", "s_works" to "k_ao3", "s_works" to "k_url", "s_annotations" to "k_work", "s_tombstones" to "k_rid", "s_fonts" to "k_file")) {
                val plan = s.db.rawQuery("EXPLAIN QUERY PLAN SELECT ord FROM $table WHERE $column = 'x'", null).use { c ->
                    buildString { while (c.moveToNext()) append(c.getString(c.getColumnIndexOrThrow("detail"))).append(';') }
                }
                assertTrue("$table.$column not served by an index: $plan", plan.contains("USING INDEX ${table}_$column") || plan.contains("USING COVERING INDEX ${table}_$column"))
            }
        }
    }

    @Test fun anOverlongOrNullKeyFieldLeavesTheColumnNull() {
        val long = "x".repeat(ManifestSections.MAX_KEY_CHARS + 1)
        stage(doc("\"works\":[{\"id\":\"${A567Corpus.uuid(1)}\",\"sourceURL\":\"$long\",\"ao3WorkID\":null}]")).use { s ->
            s.db.rawQuery("SELECT k_url, k_ao3, k_id FROM s_works", null).use { c ->
                c.moveToFirst()
                assertTrue(c.isNull(0)); assertTrue(c.isNull(1)); assertEquals(A567Corpus.uuid(1), c.getString(2))
            }
        }
    }

    @Test fun unknownMembersOfARecordAreRecordedAsRangesOfItsCompactText() {
        stage(doc("\"works\":[${work(1, ",\"future\":{\"a\":[1,2,{\"b\":null}]},\"zzz\":\"x\\u00e9\\n\",\"summary\":\"known\"")}]")).use { s ->
            val ranges = s.unknownRanges("works", 0)
            assertEquals(listOf("future", "zzz"), ranges.map { it.name })
            assertEquals("\"future\":{\"a\":[1,2,{\"b\":null}]}", s.recordTextInMemory("works", 0, ranges[0].start, ranges[0].stop))
            assertEquals("\"zzz\":\"xé\\u000a\"", s.recordTextInMemory("works", 0, ranges[1].start, ranges[1].stop))
            assertEquals(emptyList<StagedUnknownRange>(), stage(doc("\"works\":[${work(2)}]")).use { it.unknownRanges("works", 0) })
        }
    }

    @Test fun anOversizeRecordStreamsInChunksAndIsDecodedOnRead() {
        val blob = "QUJD".repeat(600_000) // 2.4M chars, over the in-memory decode limit
        stage(doc("\"works\":[${work(1, ",\"hugeUnknown\":\"$blob\"")},${work(2)}]")).use { s ->
            s.db.rawQuery("SELECT oversize, typed_ok, chars FROM s_works ORDER BY ord", null).use { c ->
                c.moveToFirst(); assertEquals(1, c.getInt(0)); assertEquals(1, c.getInt(1)); assertTrue(c.getLong(2) > 2_400_000)
                c.moveToNext(); assertEquals(0, c.getInt(0)); assertEquals(1, c.getInt(1))
            }
            val chunks = s.db.rawQuery("SELECT COUNT(*), MAX(len) FROM s_works_chunk WHERE ord = 0", null).use { c -> c.moveToFirst(); c.getLong(0) to c.getLong(1) }
            assertTrue(chunks.first >= 2_400_000 / StagingWriter.CHUNK_CHARS)
            assertTrue(chunks.second <= StagingWriter.CHUNK_CHARS)
            val r = s.unknownRanges("works", 0).single()
            assertEquals("\"hugeUnknown\":\"$blob\"", s.recordTextInMemory("works", 0, r.start, r.stop))
            assertEquals(blob, (Json.parseToJsonElement(s.recordTextInMemory("works", 0)) as JsonObject)["hugeUnknown"]!!.jsonPrimitive.content)
            s.reconstruct()
        }
    }

    @Test fun aHugeUnknownTopLevelValueIsChunkedWithNoSizeLimit() {
        val blob = "A".repeat(3_000_000)
        stage(doc("\"works\":[],\"iosOpaque\":\"$blob\"")).use { s ->
            val entry = s.rootEntries().first { it.key == "iosOpaque" }
            assertTrue(entry.oversize); assertEquals(false, entry.known)
            assertEquals("\"$blob\"", s.rootTextInMemory("iosOpaque"))
        }
    }

    @Test fun escapesAndSurrogatePairsRoundTripThroughTheStagedText() {
        val title = "q\\\"b\\\\s\\/\\b\\f\\n\\r\\t\\u0000\\u001f \\ud83d\\ude00 😀 物語"
        val body = "\"works\":[{\"id\":\"${A567Corpus.uuid(1)}\",\"title\":\"$title\"}]"
        val bytes = doc(body).toByteArray()
        val (_, todayRaw) = BackupValidator.decodeManifestWithRaw(bytes)
        stage(bytes).use { assertEquals(todayRaw, it.reconstructRaw()) }
    }

    @Test fun depthFiveHundredTwelveStagesAndFiveHundredThirteenFails() {
        fun deep(containers: Int) = doc("\"works\":[],\"deep\":" + "[".repeat(containers - 1) + "]".repeat(containers - 1))
        stage(deep(512)).use { s -> assertEquals(512 - 1, s.rootTextInMemory("deep").count { it == '[' }) } // root + the value = 512 containers
        failing<ManifestStageException.ResourceExhausted> { stage(deep(513)) }
    }

    @Test fun everyFailureOutcomeDeletesTheStagingDirectory() {
        failing<ManifestStageException.Invalid> { stage("not json") }
        failing<ManifestStageException.UnsupportedVersion> { stage(doc("\"works\":[]", "9")) }
        failing<ManifestStageException.Io> {
            val head = doc("\"works\":[" + (1..3000).joinToString(",") { work(it) }).toByteArray()
            var served = 0
            ManifestStager.stage(object : InputStream() {
                override fun read(): Int = throw IOException("disk gone")
                override fun read(b: ByteArray, off: Int, len: Int): Int {
                    if (served >= 100_000) throw IOException("disk gone")
                    val n = minOf(len, 100_000 - served)
                    System.arraycopy(head, served, b, off, n)
                    served += n
                    return n
                }
            }, root)
        }
        failing<ManifestStageException.Cancelled> { stage(A567Corpus.manifestBytesOfSize(2_000_000), ManifestStageOptions(isCancelled = { true })) }
        failing<ManifestStageException.ResourceExhausted> { stage("{}", ManifestStageOptions(freeSpace = { 0L })) }
        stage(A567Corpus.manifestBytesOfSize(100_000)).close()
        assertEquals(emptyList<String>(), leftovers())
    }

    @Test fun aDiskThatFillsMidRunIsResourceExhaustion() {
        var calls = 0
        val e = failing<ManifestStageException.ResourceExhausted> {
            stage(A567Corpus.manifestBytesOfSize(3_000_000), ManifestStageOptions(freeSpace = { if (calls++ < 1) 1L shl 40 else 1024L }))
        }
        assertTrue(e.reason, e.reason.contains("disk"))
    }

    @Test fun theUpFrontCheckUsesTheExpectedSize() {
        val seen = mutableListOf<Long>()
        failing<ManifestStageException.ResourceExhausted> {
            ManifestStager.stage(ByteArrayInputStream(ByteArray(0)), root, ManifestStageOptions(expectedBytes = 100L shl 20, freeSpace = { seen += 150L shl 20; 150L shl 20 }))
        }
        assertEquals(1, seen.size) // refused before any directory or database was created
    }

    @Test fun cancellationMidRunStopsAfterTheCurrentCommit() {
        val bytes = A567Corpus.manifestBytesOfSize(4_000_000)
        var polls = 0
        val e = failing<ManifestStageException.Cancelled> { stage(bytes, ManifestStageOptions(isCancelled = { ++polls > 5 })) }
        assertNotNull(e)
        assertTrue("stopped promptly, polls=$polls", polls < 60)
    }

    @Test fun recoveryVerdictProtectsEverythingButAMalformedFile() {
        fun verdict(text: String) = ManifestStager.recoveryVerdict(ByteArrayInputStream(text.toByteArray()))
        assertEquals(RecoveryVerdict.WELL_FORMED, verdict(doc("\"works\":[],")))
        assertEquals(RecoveryVerdict.WELL_FORMED, verdict("{\"version\":99}"))
        assertEquals(RecoveryVerdict.PROTECT, verdict("[]")) // a complete array is a schema failure: protected like any rejected whole document
        assertEquals(RecoveryVerdict.MALFORMED, verdict("[1,"))
        assertEquals(RecoveryVerdict.MALFORMED, verdict(doc("\"deep\":" + "[".repeat(600) + "]".repeat(599))))
        assertEquals(RecoveryVerdict.MALFORMED, verdict("{a:1}"))
        assertEquals(RecoveryVerdict.MALFORMED, verdict(doc("\"works\":[")))
        // a complete live file beyond the depth ceiling, or past any limit, must never be replaced from .bak
        assertEquals(RecoveryVerdict.PROTECT, verdict(doc("\"deep\":" + "[".repeat(600) + "]".repeat(600))))
        assertEquals(RecoveryVerdict.PROTECT, verdict(doc("\"k\":" + "1".repeat(70_000))))
        assertEquals(RecoveryVerdict.PROTECT, ManifestStager.recoveryVerdict(ByteArrayInputStream("{}".toByteArray()), isCancelled = { true }))
    }

    @Test fun failuresAreMappedToTheirOwnOutcome() {
        assertTrue(ManifestStager.map(android.database.sqlite.SQLiteFullException("database or disk is full")) is ManifestStageException.ResourceExhausted)
        assertTrue(ManifestStager.map(OutOfMemoryError()) is ManifestStageException.ResourceExhausted)
        assertTrue(ManifestStager.map(android.database.sqlite.SQLiteDiskIOException("io")) is ManifestStageException.Io)
        assertTrue(ManifestStager.map(android.database.sqlite.SQLiteException("x")) is ManifestStageException.Io)
        assertTrue(ManifestStager.map(IOException("x")) is ManifestStageException.Io)
        assertTrue(ManifestStager.map(kotlin.coroutines.cancellation.CancellationException("x")) is ManifestStageException.Cancelled)
        val other = IllegalStateException("a bug")
        assertTrue(ManifestStager.map(other) === other) // not swallowed into an outcome
    }

    @Test fun aSurrogatePairOnAChunkBoundaryIsNeverSplitAcrossRows() {
        val emoji = "\uD83D\uDE00"
        val head = work(1).dropLast(1) + ",\"hugeUnknown\":\""
        val atBoundary = StagingWriter.CHUNK_CHARS - 1 // index of the high surrogate: last char of the first chunk
        for (shift in 0..1) {
            val record = head + "a".repeat(atBoundary - head.length + shift) + emoji + "b".repeat(1_200_000) + "\"}"
            stage(doc("\"works\":[$record]")).use { s ->
                s.db.rawQuery("SELECT data FROM s_works_chunk WHERE ord = 0 ORDER BY start", null).use { c ->
                    while (c.moveToNext()) {
                        val d = c.getString(0)
                        assertTrue("shift=$shift chunk ends in a lone high surrogate", !Character.isHighSurrogate(d.last()))
                        assertTrue("shift=$shift chunk starts with a lone low surrogate", !Character.isLowSurrogate(d.first()))
                    }
                }
                assertEquals(record, s.recordTextInMemory("works", 0))
            }
        }
    }
}
