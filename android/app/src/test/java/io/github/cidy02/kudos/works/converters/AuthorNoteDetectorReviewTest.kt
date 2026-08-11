package io.github.cidy02.kudos.works.converters

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Adversarial cases written during review, independently of the port's own tests.
 *
 * Each one targets a specific way a faithful-looking port of
 * `Services/AuthorNoteDetector.swift` can still be wrong.
 */
class AuthorNoteDetectorReviewTest {

    /**
     * "royally" contains the substring "yall". iOS's `direct-reader-address`
     * phrases carry deliberate leading spaces for exactly this reason; a port that
     * trims them turns ordinary narration into apparatus.
     */
    @Test
    fun proseContainingYallAsASubstringIsNotANote() {
        val blocks = listOf(
            "The herald announced the visitor.",
            "She waved royally from the balcony, and the crowd roared back at her.",
            "He turned away before the cheering stopped."
        )
        assertTrue(AuthorNoteDetector.noteIndices(blocks).isEmpty())
    }

    /** A `~~~~` scene divider has no letter, so the tilde rule must not claim it. */
    @Test
    fun tildeSceneDividerIsNotASignature() {
        val blocks = listOf("She opened the door.", "~~~~", "The room was empty.")
        assertFalse(1 in AuthorNoteDetector.noteIndices(blocks))
    }

    /** The tilde rule caps the name at 60 chars; a long tilde-led line is prose. */
    @Test
    fun overlongTildeLineIsNotASignature() {
        val long = "~" + "a".repeat(80)
        val blocks = listOf("Opening.", long, "Closing.")
        assertFalse(1 in AuthorNoteDetector.noteIndices(blocks))
    }

    /** dash-signature is EDGES-only: the same line mid-work must not match. */
    @Test
    fun dashSignatureDoesNotFireInTheMiddleOfAWork() {
        val blocks = (1..12).map { "Paragraph number $it of ordinary narration." }.toMutableList()
        blocks[6] = "—Malthazar"
        val indices = AuthorNoteDetector.noteIndices(blocks)
        assertFalse("dash signature must be edges-only", 6 in indices)
    }

    /** ...but the same line at the very end is a note. */
    @Test
    fun dashSignatureFiresAtTheEnd() {
        val blocks = (1..12).map { "Paragraph number $it of ordinary narration." }.toMutableList()
        blocks[11] = "—Malthazar"
        assertTrue(11 in AuthorNoteDetector.noteIndices(blocks))
    }

    /**
     * `reader-question` is trusted ANYWHERE only because of its 60-char cap. A long
     * narrative sentence that happens to end in a question mark must not match.
     */
    @Test
    fun longNarrativeQuestionMidWorkIsNotANote() {
        val blocks = (1..12).map { "Paragraph number $it of ordinary narration." }.toMutableList()
        blocks[6] = "She stared at the sealed letter and wondered, not for the first time, " +
            "what do you think a person is supposed to do with a thing like that?"
        assertFalse(6 in AuthorNoteDetector.noteIndices(blocks))
    }

    /** A short reader question is a note wherever it sits. */
    @Test
    fun shortReaderQuestionIsANoteAnywhere() {
        val blocks = (1..12).map { "Paragraph number $it of ordinary narration." }.toMutableList()
        blocks[6] = "So..thoughts?"
        assertTrue(6 in AuthorNoteDetector.noteIndices(blocks))
    }

    /** Matching is case-insensitive on both sides, as iOS lowercases both. */
    @Test
    fun explicitMarkerMatchesRegardlessOfCase() {
        val blocks = listOf("A/N: thanks for reading!", "The story begins.")
        assertTrue(0 in AuthorNoteDetector.noteIndices(blocks))
        assertTrue(0 in AuthorNoteDetector.noteIndices(listOf("a/n: lower", "x")))
        assertTrue(0 in AuthorNoteDetector.noteIndices(listOf("A/N: UPPER", "x")))
    }

    /** Blank and whitespace-only blocks are skipped, never counted as notes. */
    @Test
    fun blankBlocksAreNeverNotes() {
        val blocks = listOf("", "   ", "\n\t", "Real narration here.")
        assertTrue(AuthorNoteDetector.noteIndices(blocks).isEmpty())
    }

    /** An empty document must not throw on the edge-window arithmetic. */
    @Test
    fun emptyDocumentIsHandled() {
        assertEquals(emptySet<Int>(), AuthorNoteDetector.noteIndices(emptyList()))
        assertEquals(emptySet<Int>(), AuthorNoteDetector.noteIndices(listOf("")))
    }

    /** A single-block document is simultaneously opening and closing; must not crash. */
    @Test
    fun singleBlockDocumentIsHandled() {
        assertTrue(0 in AuthorNoteDetector.noteIndices(listOf("A/N: solo note")))
        assertTrue(AuthorNoteDetector.noteIndices(listOf("Just one line of prose.")).isEmpty())
    }
}
