package io.github.cidy02.kudos.backup.streaming

import io.github.cidy02.kudos.backup.A567Corpus
import io.github.cidy02.kudos.backup.BackupError
import io.github.cidy02.kudos.backup.BackupWork
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
}
