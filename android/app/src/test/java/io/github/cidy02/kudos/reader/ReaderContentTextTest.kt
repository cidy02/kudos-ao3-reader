package io.github.cidy02.kudos.reader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.assertFalse
import org.junit.Test
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.Manifest
import org.readium.r2.shared.publication.Metadata
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ReaderContentTextTest {
    @Test
    fun readAloudIsUnavailableWithoutAnExtractableContentService() {
        val publication = Publication(manifest = Manifest(metadata = Metadata()))
        assertFalse(ReaderContentText.isAvailable(publication))
    }

    @Test
    fun splitsLongTextIntoSpeakableChunks() {
        val text = (1..20).joinToString(" ") { "Sentence number $it is here." }
        val chunks = ReaderContentText.splitIntoSpeakableChunks(text)
        assertTrue(chunks.size > 1)
        assertTrue(chunks.all { it.isNotBlank() })
        assertEquals(text.replace(Regex("\\s+"), " ").trim(), chunks.joinToString(" "))
    }

    @Test
    fun aoThreesLabelsAndPlugAreDroppedAndParagraphsKeptApart() {
        val text = """
            Chapter Notes
            I wrote this on a train.
            Author’s Note:
            Author's End NoteThank you to everyone who's been with me.
            The city   was quiet.
            Please drop by the Archive and comment to let the creator know if you enjoyed their work!
        """.trimIndent()
        assertEquals(
            listOf("I wrote this on a train.", "Author's End NoteThank you to everyone who's been with me.",
                "The city was quiet."),
            ReaderContentText.speakableParagraphs(text)
        )
    }

    @Test
    fun aLinkIsSaidAsItsSite() {
        assertEquals(
            listOf("Posted at archiveofourown.org. Updates: wittyy-name.tumblr.com and example.com."),
            ReaderContentText.speakableParagraphs(
                "Posted at https://archiveofourown.org/works/407062. Updates: http://wittyy-name.tumblr.com/ " +
                    "and www.example.com."
            )
        )
    }

    @Test
    fun emptyTextYieldsNoChunks() {
        assertTrue(ReaderContentText.splitIntoSpeakableChunks("   ").isEmpty())
    }
}
