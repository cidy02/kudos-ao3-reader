package io.github.cidy02.kudos.backup.streaming

import io.github.cidy02.kudos.backup.A567Corpus
import io.github.cidy02.kudos.backup.BackupError
import io.github.cidy02.kudos.backup.BackupWork
import io.github.cidy02.kudos.backup.BackupValidator
import io.github.cidy02.kudos.backup.BackupJson
import io.github.cidy02.kudos.backup.BackupSettingsPayload
import io.github.cidy02.kudos.backup.KudosBackupManifest
import io.github.cidy02.kudos.reader.speech.PronunciationCorrections
import java.io.ByteArrayInputStream
import java.io.File
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlinx.serialization.ExperimentalSerializationApi

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ManifestRound5Test {
    @get:Rule val tmp = TemporaryFolder()
    private val root get() = File(tmp.root, "stage")
    private val now = Instant.parse("2026-06-15T00:00:00Z")
    private fun stage(text: String, options: ManifestStageOptions = ManifestStageOptions()) =
        ManifestStager.stage(ByteArrayInputStream(text.toByteArray()), root, options)
    private fun doc(body: String) = """{"version":8,"exportedAt":"2026-06-01T00:00:00Z","works":[],$body}"""
    private fun work(fields: String) = """{"id":"${A567Corpus.uuid(1)}",$fields}"""

    @Test fun arrayRootSchemaOutranksNumberAndKeyBudgets() {
        for (text in listOf("[${"1".repeat(65_537)}]", "[{\"${"a".repeat(65_537)}\":1}]")) {
            try { stage(text).close(); fail("accepted") }
            catch (e: ManifestStageException.Invalid) { assertFalse(e.syntactic) }
        }
    }

    @Test fun controlsKeepTheirShortestJsonEscapeAndDoNotInflateStaging() {
        val source = "\\b\\f\\n\\r\\t".repeat(10_000)
        stage(doc("\"x\":\"$source\"")).use { s ->
            assertEquals("\"$source\"", s.rootTextInMemory("x"))
            assertEquals(2.5, ManifestStageOptions().componentBudgetFactor, 0.0)
        }
    }

    @Test fun booleanTextKeysAreIndexedAndDuplicateFontsFailValidation() {
        val fonts = """"fonts":[{"name":"A","fileName":true,"dateAdded":"2026-01-01T00:00:00Z"},{"name":"B","fileName":"true","dateAdded":"2026-01-01T00:00:00Z"}]"""
        stage(doc(fonts)).use { s ->
            assertEquals(listOf("true", "true"), s.records("fonts").map { it.keys["k_file"] })
            try { s.validate(now); fail("duplicate font accepted") }
            catch (e: BackupError.InvalidPackage) { assertTrue(e.message!!.contains("Duplicate font")) }
        }
    }

    @Test fun numericNaturalKeysAreBoundedAndCanonical() {
        val first = work("\"ao3WorkID\":\"00123\",\"sourceURL\":${"1".repeat(3_000)}")
        val second = """{"id":"${A567Corpus.uuid(2)}","ao3WorkID":123}"""
        stage("""{"version":8,"exportedAt":"2026-06-01T00:00:00Z","works":[$first,$second]}""").use { s ->
            val rows = s.records("works")
            assertEquals("123", rows[0].keys["k_ao3"])
            assertEquals("123", rows[1].keys["k_ao3"])
            assertNull(rows[0].keys["k_url"])
        }
    }

    @Test fun oversizedStrictRecordStopsSpillingWhileSyntaxTailStillWins() {
        var highWater = 0L
        val options = ManifestStageOptions(checkpoint = { highWater = maxOf(highWater, root.walkTopDown().filter { it.isFile }.sumOf { it.length() }) })
        val text = """{"version":8,"exportedAt":"2026-06-01T00:00:00Z","works":[${work("\"summary\":\"${"a".repeat(20 shl 20)}\"")}]}x"""
        try { stage(text, options).close(); fail("accepted") }
        catch (e: ManifestStageException.Invalid) { assertTrue(e.syntactic) }
        assertTrue("staged $highWater bytes after strict record exceeded 8 MiB", highWater < (14L shl 20))
    }

    @Test fun aDuplicateAtTheLiveKeyLimitCostsNoMoreUnits() {
        val wide = "k".repeat(ManifestTokenizer.MAX_KEY - 5)
        val members = (0 until 159).joinToString(",") { "\"${it.toString().padStart(5, '0')}$wide\":0" }
        val last = "z".repeat((StagingSink.MAX_LIVE_KEY_CHARS - 23L - 159L * ManifestTokenizer.MAX_KEY).toInt())
        stage(doc("\"x\":{$members,\"$last\":0,\"$last\":1}")).use { s ->
            assertEquals("object", s.rootEntries().last().kind)
        }
    }

    @Test fun validatorExposesCanonicalProjectionWithoutASecondDecode() {
        val id = A567Corpus.uuid(1).uppercase()
        val seen = mutableListOf<BackupWork>()
        stage("""{"version":8,"exportedAt":"2026-06-01T00:00:00Z","works":[{"id":"$id"}]}""").use { s ->
            s.validate(now, onValidatedRecord = { section, ord, record ->
                assertEquals("works", section)
                assertEquals(0L, ord)
                seen += record as BackupWork
            })
        }
        assertEquals(listOf(A567Corpus.uuid(1)), seen.map { it.id })
    }

    @Test fun wrongKindSharedLossyRootUsesKnownValueBudget() {
        stage(doc("\"documents\":\"a\"")).close()
        try {
            stage(doc("\"documents\":\"${"a".repeat(16 * 1024 * 1024)}\"")).close()
            fail("accepted")
        } catch (e: ManifestStageException.ResourceExhausted) {
            assertTrue(e.reason.contains("documents"))
        }
    }

    @Test fun knownRootStopsWritingAtItsSourceByteLimitAndStillFindsSyntax() {
        var highWater = 0L
        val options = ManifestStageOptions(checkpoint = {
            highWater = maxOf(highWater, root.walkTopDown().filter { it.isFile }.sumOf { it.length() })
        })
        val huge = "a".repeat(40 shl 20)
        try {
            stage(doc("\"settings\":\"$huge\""), options).close()
            fail("accepted oversized settings")
        } catch (e: ManifestStageException.ResourceExhausted) {
            assertTrue(e.reason.contains("settings"))
        }
        assertTrue("root_chunk wrote $highWater bytes", highWater < (36L shl 20))
        try {
            stage(doc("\"settings\":\"$huge\"") + "x", options).close()
            fail("accepted trailing garbage")
        } catch (e: ManifestStageException.Invalid) {
            assertTrue(e.syntactic)
        }
    }

    @Test fun duplicateIdentityPrecedesLaterBadRecordAndMatchesValidatorMessage() {
        val id = A567Corpus.uuid(1)
        val other = A567Corpus.uuid(2)
        val date = "2026-01-01T00:00:00Z"
        val cases = listOf(
            "works" to """{"id":"$id"},{"id":"$id"},{"id":"$other","dateAdded":"bad"}""",
            "fonts" to """{"name":"A","fileName":"FONT.ttf","dateAdded":"$date"},{"name":"B","fileName":"font.ttf","dateAdded":"$date"},{"name":"C","fileName":"other.ttf","dateAdded":"bad"}""",
            "collections" to """{"id":"$id","name":"A","dateAdded":"$date"},{"id":"$id","name":"B","dateAdded":"$date"},{"id":"$other","name":"C","dateAdded":"bad"}""",
            "savedSearches" to """{"id":"$id","name":"A","dateAdded":"$date"},{"id":"$id","name":"B","dateAdded":"$date"},{"id":"$other","name":"C","dateAdded":"bad"}"""
        )
        for ((section, records) in cases) {
            val text = if (section == "works")
                """{"version":8,"exportedAt":"2026-06-01T00:00:00Z","works":[$records]}"""
            else doc("\"$section\":[$records]")
            stage(text).use { staged ->
                val oracle = try {
                    BackupValidator.validateManifest(staged.reconstruct().first, now)
                    fail("oracle accepted duplicate $section")
                    ""
                } catch (e: BackupError.InvalidPackage) { e.message }
                val seen = mutableListOf<Long>()
                try {
                    staged.validate(now, onValidatedRecord = { _, ord, _ -> seen += ord })
                    fail("staged validator accepted duplicate $section")
                } catch (e: BackupError.InvalidPackage) {
                    assertEquals(section, oracle, e.message)
                }
                assertEquals(section, listOf(0L), seen)
            }
        }
    }

    @OptIn(ExperimentalSerializationApi::class)
    @Test fun streamedRootShapesKeepProductionSchemaAndIgnoreOnlyTheJsonElementPayload() {
        val production = BackupSettingsPayload.serializer().descriptor
        val shape = RootSettingsShape.serializer().descriptor
        fun fields(d: kotlinx.serialization.descriptors.SerialDescriptor) =
            (0 until d.elementsCount).map { i ->
                Triple(d.getElementName(i), d.getElementDescriptor(i).serialName, d.isElementOptional(i))
            }
        assertEquals(
            fields(production).filterNot { it.first == "libraryPageArrangement" },
            fields(shape)
        )
        assertEquals(fields(PronunciationCorrections.serializer().descriptor), fields(RootPronunciationShape.serializer().descriptor))
        val values = listOf(
            "\"settings\":{\"libraryPageArrangement\":{\"shelves\":[{\"id\":1}]},\"readerFontPt\":19.5},\"pronunciations\":{\"global\":{\"a\":\"b\"},\"fandoms\":{\"f\":{\"x\":\"y\"}}}",
            "\"settings\":{\"readerFontPt\":\"bad\"}",
            "\"pronunciations\":{\"global\":{\"a\":[]}}",
            "\"pronunciations\":{\"fandoms\":{\"f\":5}}"
        )
        for (value in values) {
            val text = doc(value)
            val productionAccepts = runCatching { BackupJson.decodeFromString(KudosBackupManifest.serializer(), text) }.isSuccess
            val stagedAccepts = try { stage(text).close(); true }
                catch (_: ManifestStageException.Invalid) { false }
            assertEquals(value, productionAccepts, stagedAccepts)
        }
    }

    @Test fun invalidUuidTakesPrecedenceOverAnIndexKeyThatNormalizesToAnEarlierId() {
        val id = A567Corpus.uuid(1)
        val text = """{"version":8,"exportedAt":"2026-06-01T00:00:00Z","works":[{"id":"$id"},{"id":"$id "}]}"""
        stage(text).use { staged ->
            assertEquals(staged.records("works")[0].keys["k_id"], staged.records("works")[1].keys["k_id"])
            try { staged.validate(now); fail("accepted malformed UUID") }
            catch (e: BackupError.InvalidUuid) { assertEquals("works[1].id", e.field) }
        }
    }
}
