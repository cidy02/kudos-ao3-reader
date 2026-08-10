package io.github.cidy02.kudos.works.converters

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Mirrors iOS `KudosTests/AuthorNoteDetectorTests.swift` exactly.
 * Found those tests: yes — this file ports their cases one-for-one so the
 * phrase list / scope rules stay faithful.
 *
 * The asymmetry that guides every case: a missed note is cosmetic, while a
 * false positive demotes real prose to apparatus. Prose cases matter more.
 */
class AuthorNoteDetectorTest {

    private fun names(blocks: List<String>): List<String> =
        AuthorNoteDetector.diagnostics(blocks)
            .toList()
            .sortedBy { it.first }
            .map { it.second }

    // MARK: - Real-world notes

    @Test
    fun detectsTheNoteFromTheTravelingSwordPDF() {
        // Verbatim from the PDF the owner imported (a fanfiction.net-era fic).
        val blocks = listOf(
            "Yes I should be working on \"you're in the army now.\" I will finish it. I swear. " +
                "I'm just not feeling it right now. Im in the middle of a \"Frozen\" obsession.. " +
                "so enjoy this.",
            "Cold.",
            "That was all she was really aware of. The deep biting cold that had crawled its way " +
                "into her bones as she trudged thru the deep snow of the forest."
        )
        val notes = AuthorNoteDetector.noteIndices(blocks)
        assertTrue(0 in notes)
        assertFalse(1 in notes)
        assertFalse(2 in notes)
    }

    @Test
    fun detectsExplicitMarkersAnywhereInTheWork() {
        val blocks = listOf(
            "She walked into the room and the door closed behind her with a soft click.",
            "A/N: sorry this took so long, my laptop died.",
            "The story resumed where it had left off, as though nothing had happened at all.",
            "Disclaimer: I don't own these characters.",
            "Another paragraph of perfectly ordinary narration to fill the middle out."
        )
        val notes = AuthorNoteDetector.noteIndices(blocks)
        assertTrue(1 in notes)
        assertTrue(3 in notes)
        assertFalse(0 in notes)
        assertFalse(2 in notes)
        assertFalse(4 in notes)
    }

    @Test
    fun detectsBetaCreditsAndReviewAsks() {
        val blocks = listOf(
            "Beta'd by the wonderful someone-or-other, all remaining errors are mine.",
            "The prose of the story goes here and continues for a good long while yet.",
            "Thanks for reading! Please review, it makes my day."
        )
        val notes = AuthorNoteDetector.noteIndices(blocks)
        assertTrue(0 in notes)
        assertTrue(2 in notes)
        assertFalse(1 in notes)
    }

    // MARK: - Prose that must survive

    @Test
    fun narrationIsNotDemotedEvenWhenItSoundsChatty() {
        val blocks = List(3) { "Filler paragraph of narration." } + listOf(
            "She thought about the next chapter of her life and what it might hold for her.",
            "\"I will finish it,\" he said, \"whatever it costs me in the end.\"",
            "His obsession with the sword had cost him everything he had ever loved.",
            "Sorry for the delay, she wrote in the letter, and sealed it with wax."
        ) + List(3) { "More narration to keep these away from the edges." }

        val notes = AuthorNoteDetector.noteIndices(blocks)
        for (index in 3..6) {
            assertFalse("block $index was wrongly treated as a note", index in notes)
        }
    }

    @Test
    fun firstPersonProseIsNotANote() {
        val blocks = listOf(
            "I don't own anything worth stealing, which is why the theft confused me.",
            "The rest of the story continues from there without further interruption."
        )
        // Recorded honestly (iOS same): "I don't own" is ownership-disclaimer.
        assertEquals("ownership-disclaimer", AuthorNoteDetector.diagnostics(blocks)[0])
    }

    // MARK: - Scope mechanics

    @Test
    fun edgeScopedIndicatorsOnlyFireNearTheEnds() {
        val chatty = "Sorry for the wait, here is the new chapter at last."
        val filler = "Ordinary narration."
        assertTrue(0 in AuthorNoteDetector.noteIndices(listOf(chatty, filler, filler, filler)))
        val long = listOf(filler, filler, filler, chatty, filler, filler, filler)
        assertFalse(3 in AuthorNoteDetector.noteIndices(long))
        val tail = listOf(filler, filler, filler, filler, chatty)
        assertTrue(4 in AuthorNoteDetector.noteIndices(tail))
    }

    @Test
    fun diagnosticsNameTheRuleThatMatched() {
        assertEquals(listOf("an-abbreviation"), names(listOf("A/N: hello")))
        assertEquals(listOf("disclaimer"), names(listOf("Disclaimer: not mine")))
        assertEquals(listOf("beta-credit"), names(listOf("Beta: someone")))
    }

    @Test
    fun emptyAndWhitespaceBlocksAreIgnored() {
        assertTrue(AuthorNoteDetector.noteIndices(listOf("", "   ", "\n")).isEmpty())
    }

    // MARK: - FanFiction.net sign-offs

    @Test
    fun aTildeSignOffIsANote() {
        assertEquals(
            listOf("reader-question", "tilde-signature"),
            names(listOf("prose", "So..thoughts?", "~Malthazar LOS"))
        )
        assertEquals(listOf("tilde-signature"), names(listOf("~ Malthazar LOS")))
        assertEquals(listOf("tilde-signature"), names(listOf("~Malthazar LOS.")))
    }

    @Test
    fun aSignOffIsStillANoteAwayFromTheEdges() {
        val blocks = listOf(
            "Prose one that runs on for a good while and says nothing about writing.",
            "Prose two, likewise entirely story.",
            "Prose three, still story.",
            "~Malthazar LOS*Chapter 2*: A Queens Gratitude",
            "Prose four, where the story picks up again.",
            "Prose five.",
            "Prose six."
        )
        assertEquals(setOf(3), AuthorNoteDetector.noteIndices(blocks))
    }

    @Test
    fun closingNotesFromARealFanFictionPDF() {
        val cases = listOf(
            "I actually already had more planned out…but it's 2:30 in the morning and " +
                "this seemed like a good place to end for now.",
            "Here ya go people. More to come!",
            "Next chapter for yall great readers. I appreciate the reviews. They spur me to keep writing.",
            "There it is, Chapter 10. I hope you all enjoyed it, we're finally getting places,lol",
            "Also a Happy Easter to all my readers.",
            "Painfully short chapter….but no worries people. The next will make up for it I promise!",
            "How many of you would be interested in another fic, a collection of oneshots?"
        )
        for (note in cases) {
            assertTrue(
                "undetected: $note",
                names(listOf("story", "story", "story", note)).isNotEmpty()
            )
        }
    }

    @Test
    fun realProseIsNotMistakenForASignOff() {
        assertTrue(names(listOf("\"Goodnight…\"")).isEmpty())
        assertTrue(names(listOf("She mumbled quietly.")).isEmpty())
        // "yall" is a substring of "royally" — the reason those phrases carry a space.
        assertTrue(
            names(listOf("She bowed, royally unimpressed with the whole affair.")).isEmpty()
        )
        assertTrue(
            names(listOf("How long had she been staring at the queen, lost in her thoughts?"))
                .isEmpty()
        )
        assertTrue(names(listOf("* * *")).isEmpty())
    }

    // MARK: - Output shape

    @Test
    fun notesBecomeAsidesAndProseStaysParagraphs() {
        val body = paragraphsWithAuthorNotes(
            listOf(
                "A/N: quick note before we start.",
                "The story begins on a cold morning in the middle of nowhere at all."
            )
        )
        assertTrue(body.contains("""class="author-note""""))
        assertTrue(body.contains("<aside"))
        assertTrue(body.contains("<p>A/N: quick note before we start.</p>"))
        assertTrue(body.contains("<p>The story begins on a cold morning"))
        val asideEnd = body.indexOf("</aside>")
        assertTrue(asideEnd >= 0)
        assertTrue(body.indexOf("The story begins") > asideEnd)
    }

    @Test
    fun consecutiveNotesShareOneAside() {
        val body = paragraphsWithAuthorNotes(
            listOf(
                "A/N: first line of the note.",
                "Beta'd by someone lovely.",
                "Thanks for reading, please review!",
                "The actual story starts here and runs on for a while."
            )
        )
        assertEquals(1, body.split("<aside").size - 1)
        assertEquals(1, body.split("</aside>").size - 1)
    }

    // Adversarial case from self-review: ordinary prose that only *mentions*
    // reviewing, mid-work — must not fire (review-ask is edges-only).
    @Test
    fun midWorkReviewPhraseInNarrationIsNotANote() {
        val filler = "Ordinary narration fills this paragraph out to keep distance."
        val blocks = listOf(filler, filler, filler) +
            listOf("She asked him to please review the contract before signing it.") +
            listOf(filler, filler, filler)
        assertTrue(
            "mid-work 'please review' in narration must not be a note",
            AuthorNoteDetector.noteIndices(blocks).isEmpty()
        )
    }
}
