package io.github.cidy02.kudos.backup.streaming

import io.github.cidy02.kudos.backup.A567Corpus
import java.io.ByteArrayInputStream
import java.io.File
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Round 4 contract rules; these fail against the round 3 staging API/limits. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ManifestRound4Test {
    @get:Rule val tmp = TemporaryFolder()
    private val root get() = File(tmp.root, "staging")
    private fun stage(text: String, options: ManifestStageOptions = ManifestStageOptions()) =
        ManifestStager.stage(ByteArrayInputStream(text.toByteArray()), root, options)
    private fun doc(body: String) = """{"version":8,"exportedAt":"2026-06-01T00:00:00Z","works":[],$body}"""
    private fun withWorks(records: String) = """{"version":8,"exportedAt":"2026-06-01T00:00:00Z","works":[$records]}"""

    @Test fun arrayRootIsSchemaEvenAtDepth513() {
        val input = "[".repeat(513) + "]".repeat(513)
        try { stage(input).close(); fail("accepted") } catch (e: ManifestStageException.Invalid) { assertEquals(false, e.syntactic) }
    }

    @Test fun memberOverflowStopsEmittingKeysWhileStillCheckingSyntax() {
        var names = 0
        val events = object : ManifestEvents {
            override fun beginObject() {}
            override fun endObject() {}
            override fun beginArray() {}
            override fun endArray() {}
            override fun name(name: String) { names++ }
            override fun stringChunk(buffer: CharArray, offset: Int, length: Int, last: Boolean) {}
            override fun literal(text: String) {}
        }
        val members = "\"a\":0,".repeat(ManifestTokenizer.MAX_MEMBERS) + "\"a\":0"
        try {
            ManifestTokenizer(ByteArrayInputStream("{\"x\":{$members}}".toByteArray()), events).parseDocument()
            fail("accepted")
        } catch (e: ManifestStageException.ResourceExhausted) {
            assertEquals(ManifestTokenizer.MAX_MEMBERS + 1, names) // root x plus at most the allowed inner members
        }
    }

    @Test fun rootAndUnknownMetadataHaveFixedPages() {
        stage(doc((0..20).joinToString(",") { "\"extra$it\":$it" })).use { s ->
            val all = mutableListOf<StagedRootEntry>()
            var after = -1L
            while (true) {
                val page = s.rootEntries(afterOrd = after, limit = 3)
                if (page.isEmpty()) break
                assertTrue(page.size <= 3)
                all += page
                after = page.last().ord
            }
            assertEquals(24, all.size)
            assertEquals((0L..23L).toList(), all.map { it.ord })
        }
        val unknown = (0..20).joinToString(",") { "\"extra$it\":$it" }
        stage(withWorks("{\"id\":\"${A567Corpus.uuid(1)}\",$unknown}")).use { s ->
            var after = -1L
            val seen = mutableListOf<String>()
            while (true) {
                val page = s.unknownRanges("works", 0, afterStart = after, limit = 4)
                if (page.isEmpty()) break
                assertTrue(page.size <= 4)
                seen += page.map { it.name }
                after = page.last().start
            }
            assertEquals((0..20).map { "extra$it" }, seen)
        }
    }

    @Test fun validationConsumesAtMostSixteenMiBOfRecordSourcePerBatch() {
        val blob = "a".repeat(7_500_000)
        val rows = (1..3).joinToString(",") { """{"id":"${A567Corpus.uuid(it)}","summary":"$blob"}""" }
        stage(withWorks(rows)).use { s ->
            val batches = mutableListOf<Pair<Int, Long>>()
            s.validate(Instant.parse("2026-06-15T00:00:00Z")) { count, bytes -> batches += count to bytes }
            assertEquals(listOf(2, 1), batches.map { it.first })
            assertTrue(batches.all { it.second <= StagedManifest.VALIDATION_BATCH_BYTES })
        }
    }

    @Test fun unknownLengthStillEnforcesComponentBudget() {
        val bytes = A567Corpus.manifestBytesOfSize(20L shl 20)
        try {
            ManifestStager.stage(ByteArrayInputStream(bytes), root, ManifestStageOptions(freeSpace = { 1L shl 40 }, componentBudgetFactor = 0.1)).close()
            fail("accepted")
        } catch (e: ManifestStageException.ResourceExhausted) {
            assertTrue(e.reason.contains("budget"))
        }
    }

    @Test fun firstDuplicateRecordFieldValueIsTheOneStaged() {
        stage(withWorks("{\"id\":\"${A567Corpus.uuid(1)}\",\"title\":\"first\",\"title\":\"second\"}")).use { s ->
            assertTrue(s.recordTextInMemory("works", 0).contains("\"title\":\"first\""))
            assertEquals(false, s.recordTextInMemory("works", 0).contains("second"))
            assertEquals("first", s.reconstruct().first.works.single().title)
        }
    }
}
