package io.github.cidy02.kudos.backup.streaming

import java.io.ByteArrayInputStream
import java.io.File
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The shared byte fixtures (`manifest-fixtures/cases.json`; files are literal bytes, `gen` entries are
 * `prefix + unit x count + suffix`, optionally inside the standard manifest wrapper) with their exact expected
 * stage outcome: ok, syntax, resource, schema or unsupportedVersion. The stage outcome is asserted on its own; reconstruction
 * is a separate step, run here only for the cases that stay small.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ManifestFixtureCasesTest {
    @get:Rule val tmp = TemporaryFolder()

    private val index: JsonObject by lazy {
        Json.parseToJsonElement(javaClass.classLoader!!.getResourceAsStream("manifest-fixtures/cases.json")!!.readBytes().decodeToString()).jsonObject
    }

    private fun bytes(case: JsonObject): ByteArray {
        case["file"]?.let { return javaClass.classLoader!!.getResourceAsStream("manifest-fixtures/${it.jsonPrimitive.content}")!!.readBytes() }
        val g = case.getValue("gen").jsonObject
        val wrap = g.getValue("wrap").jsonPrimitive.boolean
        val unit = g.getValue("unit").jsonPrimitive.content
        val count = g.getValue("count").jsonPrimitive.int
        val sb = StringBuilder()
        if (wrap) sb.append(index.getValue("wrapper").jsonPrimitive.content.substringBefore("BODY"))
        sb.append(g.getValue("prefix").jsonPrimitive.content)
        for (i in 0 until count) sb.append(unit)
        sb.append(g.getValue("suffix").jsonPrimitive.content)
        if (wrap) sb.append(index.getValue("wrapper").jsonPrimitive.content.substringAfter("BODY"))
        return sb.toString().toByteArray(Charsets.UTF_8)
    }

    private fun outcome(bytes: ByteArray, keep: ((StagedManifest) -> Unit)? = null): String = try {
        ManifestStager.stage(ByteArrayInputStream(bytes), File(tmp.root, "stage")).use { keep?.invoke(it) }
        "ok"
    } catch (e: ManifestStageException.Invalid) {
        if (e.syntactic) "syntax" else "schema"
    } catch (e: ManifestStageException.ResourceExhausted) {
        "resource"
    } catch (e: ManifestStageException.UnsupportedVersion) {
        "unsupportedVersion"
    }

    @Test fun everySharedCaseHasItsExactStageOutcome() {
        val cases = index.getValue("cases").jsonArray.map { it.jsonObject }
        assertTrue(cases.size >= 51)
        val wrong = mutableListOf<String>()
        for (case in cases) {
            val id = case.getValue("id").jsonPrimitive.content
            val got = outcome(bytes(case))
            if (got != case.getValue("expect").jsonPrimitive.content) wrong += "$id: expected ${case["expect"]!!.jsonPrimitive.content}, got $got"
            assertEquals("$id left staging files behind", emptyList<String>(), File(tmp.root, "stage").list()?.toList().orEmpty())
        }
        assertTrue(wrong.joinToString("\n"), wrong.isEmpty())
    }

    @Test fun everySharedSuccessHasTheRequiredCrossPlatformRootFields() {
        for (case in index.getValue("cases").jsonArray.map { it.jsonObject }) {
            if (case.getValue("expect").jsonPrimitive.content != "ok") continue
            val id = case.getValue("id").jsonPrimitive.content
            val text = bytes(case).toString(Charsets.UTF_8)
            for (field in listOf("\"bookmarks\":[]", "\"fonts\":[]", "\"settings\":")) {
                assertTrue("$id lacks $field", text.contains(field))
            }
        }
    }

    @Test fun missingIdSchemaFixtureHasAllOtherRequiredFields() {
        val case = index.getValue("cases").jsonArray.map { it.jsonObject }
            .first { it.getValue("id").jsonPrimitive.content == "record-1MiB-plus-1-missing-id-schema" }
        val source = bytes(case).toString(Charsets.UTF_8)
        for (field in listOf("\"bookmarks\":[]", "\"fonts\":[]", "\"settings\":{}")) {
            assertTrue("schema fixture lacks $field", source.contains(field))
        }
    }

    @Test fun distinctUnnormalisedKeysAreBothKeptAndEscapedDuplicatesAreFirstWins() {
        fun case(id: String) = index.getValue("cases").jsonArray.map { it.jsonObject }.first { it.getValue("id").jsonPrimitive.content == id }
        outcome(bytes(case("key-nfc-nfd-distinct"))) { s ->
            assertEquals(listOf("version", "exportedAt", "works", "bookmarks", "fonts", "settings", "é", "é"), s.rootEntries().map { it.key })
        }.also { assertEquals("ok", it) }
        outcome(bytes(case("key-escaped-duplicate-first-wins"))) { s ->
            assertEquals("1", s.rootTextInMemory("x"))
            assertEquals(7, s.rootEntries().size)
        }.also { assertEquals("ok", it) }
    }

    @Test fun theSmallOkCasesReconstructToTheirTypedManifest() {
        for (id in listOf("depth-512-total-ok", "trailing-commas-ok", "bom-ok", "surrogate-pair-ok")) {
            val case = index.getValue("cases").jsonArray.map { it.jsonObject }.first { it.getValue("id").jsonPrimitive.content == id }
            outcome(bytes(case)) { s -> s.reconstruct() }.also { assertEquals(id, "ok", it) }
        }
    }
}
