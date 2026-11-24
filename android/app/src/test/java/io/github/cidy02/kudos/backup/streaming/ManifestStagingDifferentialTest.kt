package io.github.cidy02.kudos.backup.streaming

import io.github.cidy02.kudos.backup.A567Corpus
import io.github.cidy02.kudos.backup.A567ParserParityTest
import io.github.cidy02.kudos.backup.BackupError
import io.github.cidy02.kudos.backup.BackupValidator
import io.github.cidy02.kudos.backup.isStrictJsonObject
import java.io.ByteArrayInputStream
import java.io.File
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A-567 P2 differential: the staging pipeline (parse + stage + typed reconstruct + `validateManifest`)
 * against today's `BackupValidator.decodeManifestWithRaw` and `isStrictJsonObject`, on every manifest
 * fixture and P1's 107-case corpus. Outcomes, typed manifests and raw views are equal except where the
 * owner-approved input contract (REDESIGN_DECISIONS 2026-11-22) or the numeric grammar deliberately
 * differs; those cases are pinned below with the exact outcome on each side, so a vanished or new
 * difference fails the gate.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ManifestStagingDifferentialTest {
    @get:Rule val tmp = TemporaryFolder()

    private data class Outcome(val cls: String, val typed: Any? = null, val raw: JsonObject? = null)

    private fun today(bytes: ByteArray): Outcome =
        runCatching { BackupValidator.decodeManifestWithRaw(bytes) }.fold({ Outcome("ok", it.first, it.second) }, { Outcome(it::class.simpleName!!) })

    private fun mine(bytes: ByteArray): Outcome = try {
        ManifestStager.stage(ByteArrayInputStream(bytes), File(tmp.root, "stage")).use { staged ->
            val (typed, raw) = staged.reconstruct()
            Outcome("ok", BackupValidator.validateManifest(typed), raw)
        }
    } catch (e: ManifestStageException.Invalid) {
        Outcome("InvalidJson")
    } catch (e: ManifestStageException.UnsupportedVersion) {
        Outcome("UnsupportedVersion")
    } catch (e: ManifestStageException.ResourceExhausted) {
        Outcome("ResourceExhausted")
    } catch (e: BackupError) {
        Outcome(e::class.simpleName!!)
    }

    private fun resource(path: String) = javaClass.classLoader!!.getResourceAsStream(path)!!.readBytes()

    private val cases: List<Pair<String, ByteArray>> by lazy {
        A567ParserParityTest().corpus + listOf("fixture android-export.kudosbackup manifest" to manifestOf(File("src/debug/assets/fixtures/android-export.kudosbackup").readBytes()))
    }

    private fun manifestOf(zip: ByteArray): ByteArray {
        java.util.zip.ZipInputStream(zip.inputStream()).use { z ->
            while (true) {
                val entry = z.nextEntry ?: break
                if (entry.name == "manifest.json") return z.readBytes()
            }
        }
        error("no manifest")
    }

    /** Case name -> (today, mine) for cases that differ on purpose; the value is why. */
    private val approved = mapOf(
        "UTF-8 BOM prefix" to Triple("InvalidJson", "ok", "owner: a leading BOM is accepted"),
        "trailing comma in object" to Triple("InvalidJson", "ok", "owner: trailing commas are accepted"),
        "trailing comma in array" to Triple("InvalidJson", "ok", "owner: trailing commas are accepted"),
        "escapes: lone high surrogate" to Triple("ok", "InvalidJson", "owner: a lone surrogate is rejected"),
        "duplicate key: version 8 then 99" to Triple("UnsupportedVersion", "ok", "owner: the first duplicate wins"),
        "duplicate key: version 99 then 8" to Triple("ok", "UnsupportedVersion", "owner: the first duplicate wins"),
        "duplicate key: works twice" to Triple("ok", "ok", "owner: the first duplicate wins (different works kept)"),
        "duplicate key inside a record" to Triple("ok", "ok", "owner: the first duplicate wins (different title kept)"),
        "nesting depth 600 (unknown key)" to Triple("ok", "ResourceExhausted", "owner: depth limit 512 (a resource outcome, not malformed)"),
        "raw newline inside string" to Triple("ok", "InvalidJson", "shared decision 6: raw controls are syntax errors"),
        "raw tab inside string" to Triple("ok", "InvalidJson", "shared decision 6: raw controls are syntax errors"),
        "invalid UTF-8: 0xFF in title" to Triple("ok", "InvalidJson", "shared decision 6: malformed UTF-8 is a syntax error"),
        "invalid UTF-8: truncated multibyte before quote" to Triple("ok", "InvalidJson", "shared decision 6: malformed UTF-8 is a syntax error"),
        "invalid UTF-8: overlong slash in key" to Triple("ok", "InvalidJson", "shared decision 6: malformed UTF-8 is a syntax error"),
        "lenient: unquoted keys" to Triple("ok", "InvalidJson", "owner: unquoted tokens are dropped"),
        "missing comma between members" to Triple("ok", "InvalidJson", "owner: the kotlinx lenient fallback is dropped (it accepted a missing comma)"),
        "version = leading zero" to Triple("ok", "InvalidJson", "RFC 8259 number grammar: a leading zero is not a number (iOS rejects it too)")
    )

    /** Cases where only the whole-document well-formedness answer differs (the decode outcome is equal or listed above). */
    private val strictDiffers = setOf(
        "UTF-8 BOM prefix", "trailing comma in object", "trailing comma in array", "escapes: lone high surrogate",
        "nesting depth 600 (unknown key)", "version = leading zero", "version = plus sign", "version = bare fraction",
        "version = NaN", "version = bare minus", "version = Infinity", "raw newline inside string", "raw tab inside string",
        "invalid UTF-8: 0xFF in title", "invalid UTF-8: truncated multibyte before quote", "invalid UTF-8: overlong slash in key"
    )

    @Test fun everyCaseHasTheSameOutcomeExceptTheApprovedOnes() {
        val unexpected = mutableListOf<String>()
        var equal = 0
        for ((name, bytes) in cases) {
            val t = today(bytes)
            val m = mine(bytes)
            val same = t.cls == m.cls && (t.cls != "ok" || (t.typed == m.typed && t.raw == m.raw))
            val pinned = approved[name]
            when {
                pinned == null && same -> equal++
                pinned == null -> unexpected += "$name: today=${t.cls} mine=${m.cls}${if (t.cls == "ok" && m.cls == "ok") " (values differ)" else ""}"
                same -> unexpected += "$name: no longer differs (pinned: ${pinned.third})"
                t.cls != pinned.first || m.cls != pinned.second -> unexpected += "$name: today=${t.cls} mine=${m.cls}, pinned ${pinned.first} -> ${pinned.second}"
                else -> {}
            }
        }
        assertTrue(unexpected.joinToString("\n"), unexpected.isEmpty())
        assertTrue("only $equal equal cases", equal >= cases.size - approved.size)
        assertEquals(approved.keys, approved.keys.intersect(cases.map { it.first }.toSet()))
        assertEquals(cases.size, cases.map { it.first }.toSet().size)
        assertTrue(cases.size >= 108)
    }

    @Test fun wholeDocumentWellFormednessMatchesTheRecoveryPredicateExceptWhereTheContractChanged() {
        val unexpected = mutableListOf<String>()
        for ((name, bytes) in cases) {
            val today = isStrictJsonObject(bytes)
            val mine = ManifestStager.recoveryVerdict(ByteArrayInputStream(bytes)) == RecoveryVerdict.WELL_FORMED
            if ((today == mine) == (name in strictDiffers)) unexpected += "$name: today=$today mine=$mine"
        }
        assertTrue(unexpected.joinToString("\n"), unexpected.isEmpty())
    }

    // The approved drops, one explicit assertion each (outcome on both sides).
    @Test fun aLeadingBomIsAcceptedNow() = pin("UTF-8 BOM prefix")
    @Test fun trailingCommasAreAcceptedNow() { pin("trailing comma in object"); pin("trailing comma in array") }
    @Test fun aLoneSurrogateIsRejectedNow() = pin("escapes: lone high surrogate")
    @Test fun theFirstDuplicateWinsNow() {
        pin("duplicate key: version 8 then 99"); pin("duplicate key: version 99 then 8")
        pin("duplicate key: works twice"); pin("duplicate key inside a record")
        val (name, bytes) = cases.first { it.first == "duplicate key: works twice" }
        assertNotEquals(name, today(bytes).raw, mine(bytes).raw)
        val firstWork = mine(bytes)
        assertEquals(A567Corpus.uuid(1), (firstWork.typed as io.github.cidy02.kudos.backup.KudosBackupManifest).works.single().id)
        assertEquals(A567Corpus.uuid(1), (firstWork.raw!!.getValue("works") as kotlinx.serialization.json.JsonArray).single().let {
            (it as JsonObject).getValue("id").let { value -> (value as kotlinx.serialization.json.JsonPrimitive).content }
        })
        val nested = cases.first { it.first == "duplicate key inside a record" }.second
        val staged = mine(nested)
        assertEquals("a", (staged.typed as io.github.cidy02.kudos.backup.KudosBackupManifest).works.single().title)
        assertEquals("a", staged.raw!!.getValue("works").let { it as kotlinx.serialization.json.JsonArray }.single().let {
            (it as JsonObject).getValue("title").let { value -> (value as kotlinx.serialization.json.JsonPrimitive).content }
        })
    }

    @Test fun escapedDuplicateInsideARecordKeepsTheFirstField() {
        val bytes = """{"version":8,"exportedAt":"2026-06-01T00:00:00Z","works":[{"id":"${A567Corpus.uuid(1)}","title":"first","\u0074itle":"second"}]}""".toByteArray()
        val result = mine(bytes)
        assertEquals("ok", result.cls)
        assertEquals("first", (result.typed as io.github.cidy02.kudos.backup.KudosBackupManifest).works.single().title)
        assertEquals("first", (result.raw!!.getValue("works") as kotlinx.serialization.json.JsonArray).single().let {
            (it as JsonObject).getValue("title").let { value -> (value as kotlinx.serialization.json.JsonPrimitive).content }
        })
    }
    @Test fun depthBeyondFiveHundredTwelveIsRejectedNow() = pin("nesting depth 600 (unknown key)")
    @Test fun unquotedAndMissingCommaLenienceIsDroppedNow() { pin("lenient: unquoted keys"); pin("missing comma between members") }
    @Test fun aLeadingZeroNumberIsRejectedNow() = pin("version = leading zero")

    private fun pin(name: String) {
        val bytes = cases.first { it.first == name }.second
        val p = approved.getValue(name)
        assertEquals("$name today", p.first, today(bytes).cls)
        assertEquals("$name mine", p.second, mine(bytes).cls)
    }

    @Test fun theManifestFixturesStageAndMatchToday() {
        for (name in listOf("fixture ios-sync-folder", "fixture android-after-ios-sync-folder", "fixture ios-export.kudosbackup manifest", "fixture android-export.kudosbackup manifest")) {
            val bytes = cases.first { it.first == name }.second
            val t = today(bytes)
            assertEquals(name, "ok", t.cls)
            assertEquals(name, t, mine(bytes))
        }
    }

    private val fixedNow = java.time.Instant.parse("2026-06-15T00:00:00Z")

    @Test fun boundedValidationReachesTheSameOutcomeAsValidateManifest() {
        val unexpected = mutableListOf<String>()
        var checked = 0
        for ((name, bytes) in cases) {
            val staged = try {
                ManifestStager.stage(ByteArrayInputStream(bytes), File(tmp.root, "stage"))
            } catch (e: ManifestStageException) {
                continue
            }
            staged.use {
                val today = runCatching { BackupValidator.validateManifest(it.reconstruct().first, fixedNow) }.fold({ "ok" }, { e -> e::class.simpleName!! })
                val bounded = runCatching { it.validate(fixedNow) }.fold({ "ok" }, { e -> e::class.simpleName!! })
                checked++
                if (today != bounded) unexpected += "$name: validateManifest=$today bounded=$bounded"
            }
        }
        assertTrue("checked $checked", checked > 30)
        assertTrue(unexpected.joinToString("\n"), unexpected.isEmpty())
    }
}
