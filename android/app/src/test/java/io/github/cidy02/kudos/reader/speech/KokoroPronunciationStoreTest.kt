package io.github.cidy02.kudos.reader.speech

import java.nio.file.Files
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class KokoroPronunciationStoreTest {
    private val root = Files.createTempDirectory("kudos-pronunciations").toFile()
    private val store = KokoroPronunciationStore(root)

    @After fun cleanUp() { root.deleteRecursively() }

    @Test fun iosDocumentRoundTripsAllScopesExactCaseAndUnicodeOutsideModelDirectory() {
        val document = KokoroPronunciationStore.Document(
            global = mapOf("Anna" to "ˈænə", "anna" to "ˈɑnə"),
            fandoms = mapOf("Haikyū!!" to mapOf("Tobio" to "tˈoʊbioʊ")),
            works = mapOf("42" to mapOf("Sam" to "sæm"))
        )
        assertEquals(KokoroPronunciationStore.Document(), store.load())
        store.save(document)
        assertEquals(document, KokoroPronunciationStore(root).load())
        assertEquals(root, store.file.parentFile)
        assertFalse(root.resolve("tts_models").exists())
        assertEquals(setOf("version", "global", "fandoms", "works"),
            Json.parseToJsonElement(store.file.readText()).jsonObject.keys)
    }

    @Test fun workBeatsFandomBeatsGlobalWithoutFoldingCaseOrChangingOtherScopes() {
        val corrections = PronunciationCorrections(
            global = mapOf("Sam" to "global", "sam" to "lowercase", "Other" to "kept"),
            fandoms = mapOf("LOTR" to mapOf("Sam" to "fandom")),
            works = mapOf("42" to mapOf("Sam" to "work"))
        )
        assertEquals("global", corrections.lexicon()["Sam"])
        assertEquals("fandom", corrections.lexicon("LOTR")["Sam"])
        assertEquals("work", corrections.lexicon("LOTR", "42")["Sam"])
        assertEquals("global", corrections.lexicon("Other fandom", "43")["Sam"])
        assertEquals("lowercase", corrections.lexicon("LOTR", "42")["sam"])
        assertEquals("kept", corrections.lexicon("LOTR", "42")["Other"])
    }

    @Test fun renameAndDeleteAreGlobalOnlyAndIndependentStoreInstancesSeeEdits() {
        store.save(KokoroPronunciationStore.Document(global = mapOf("Old" to "old"),
            works = mapOf("42" to mapOf("Old" to "work"))))
        KokoroPronunciationStore(root).setOverride("New", "new", previousWord = "Old")
        assertEquals(mapOf("New" to "new"), store.load().global)
        store.removeOverride("New")
        assertTrue(store.load().global.isEmpty())
        assertEquals(mapOf("Old" to "work"), store.load().works["42"])
    }

    @Test fun incomingWinsEveryLayerWithoutLosingLocalOnlyWords() {
        store.save(KokoroPronunciationStore.Document(
            global = mapOf("Sam" to "old", "Local" to "keep"),
            fandoms = mapOf("LOTR" to mapOf("Sam" to "old", "Local" to "keep")),
            works = mapOf("42" to mapOf("Sam" to "old", "Local" to "keep"))
        ))
        store.apply(PronunciationCorrections(mapOf("Sam" to "new"),
            mapOf("LOTR" to mapOf("Sam" to "new")), mapOf("42" to mapOf("Sam" to "new"))))
        val expected = mapOf("Sam" to "new", "Local" to "keep")
        assertEquals(expected, store.load().global)
        assertEquals(expected, store.load().fandoms["LOTR"])
        assertEquals(expected, store.load().works["42"])
        val before = store.file.readText()
        store.apply(PronunciationCorrections())
        assertEquals(before, store.file.readText())
    }

    @Test fun corruptFileIsNeverReplacedByEditingAnApparentlyEmptyStore() {
        store.file.writeText("not a valid document")
        assertTrue(runCatching { store.setOverride("Sam", "sæm") }.isFailure)
        assertEquals("not a valid document", store.file.readText())
    }

    @Test fun selectionUsesOnlyTheFirstWordAndIosPunctuationRules() {
        val cases = mapOf(
            "  “Hermione,” Granger" to "Hermione",
            "(O'Neill!) next" to "O'Neill",
            "[Jean-Luc], Picard" to "Jean-Luc",
            "'Anna-' next" to "'Anna-'",
            "\u00a0Éowyn\u00a0of Rohan" to "Éowyn",
            "«𐐀name» next" to "𐐀name",
            "… next" to "",
            "\n\t" to ""
        )
        cases.forEach { (selection, expected) -> assertEquals(selection, expected, pronunciationSelectionWord(selection)) }
    }

    @Test fun inlinePasteUsesIosBracketRulesAndLastDuplicateWinsAtImport() {
        val parsed = KokoroInlinePronunciation.entries("notes [a][Sam](/old/)\n[Sam] (/sæm/) [bad](/ /)")
        assertEquals(listOf("Sam" to "old", "Sam" to "sæm"), parsed)
        store.apply(PronunciationCorrections(global = parsed.toMap()))
        val copied = KokoroInlinePronunciation.text(store.load().global)
        assertEquals("[Sam](/sæm/)", copied)
        assertEquals(store.load().global, KokoroInlinePronunciation.entries(copied).toMap())
    }

    @Test fun lexiconUsesModelTokensAndNeverInjectsOrPartiallyAppliesInvalidRows() {
        val rendered = KokoroPronunciationLexicon.render(mapOf(
            "Sam" to "sæm", "bad\nrow" to "sæm", "two words" to "sæm", "Unknown" to "s?m"
        ), setOf("s", "æ", "m"))
        assertEquals("Sam s æ m\n", rendered)
    }
}
