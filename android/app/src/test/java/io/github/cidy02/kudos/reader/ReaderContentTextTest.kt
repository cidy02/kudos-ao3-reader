package io.github.cidy02.kudos.reader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.assertFalse
import org.junit.Test
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.Manifest
import org.readium.r2.shared.publication.Metadata
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.services.content.Content
import org.readium.r2.shared.publication.services.content.ContentService
import io.github.cidy02.kudos.reader.readium.ReadiumNavigatorController
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertNull
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
@OptIn(ExperimentalReadiumApi::class)
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
    fun withAuthorsNotesOffANoteAndItsLabelAreSkippedButNotTheStory() {
        val blocks = listOf(
            ReaderContentText.SpeechBlock("Chapter Notes"),
            ReaderContentText.SpeechBlock("Content warning: a storm.", isQuote = true),
            ReaderContentText.SpeechBlock("Still the note.", isQuote = true),
            ReaderContentText.SpeechBlock("The city was quiet."),
            ReaderContentText.SpeechBlock("End Notes"),
            ReaderContentText.SpeechBlock("A label with no quotation after it leaves this spoken.")
        )
        assertEquals(
            listOf("The city was quiet.", "A label with no quotation after it leaves this spoken."),
            ReaderContentText.speakableParagraphs(blocks, readAuthorNotes = false)
        )
        assertEquals(
            listOf("Content warning: a storm.", "Still the note.", "The city was quiet.",
                "A label with no quotation after it leaves this spoken."),
            ReaderContentText.speakableParagraphs(blocks, readAuthorNotes = true)
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
    @Test
    fun firstSpeechComesFromTheCurrentResourceWithoutReadingOtherResources() = runBlocking {
        val current = locator("current.xhtml")
        val reads = mutableListOf<String>()
        var requestedFrom: Locator? = null
        val publication = Publication(
            manifest = Manifest(metadata = Metadata()),
            servicesBuilder = Publication.ServicesBuilder(content = {
                object : ContentService {
                    override fun content(from: Locator?): Content {
                        requestedFrom = from
                        return countingContent(listOf(
                            element("current.xhtml", "Current chapter."),
                            element("last.xhtml", "Last chapter.")
                        ), reads)
                    }
                }
            })
        )
        val source = ReaderContentText.source(publication, current)
        assertTrue(reads.isEmpty())
        assertEquals("Current chapter.", source.next())
        assertEquals(current, requestedFrom)
        assertEquals(listOf("current.xhtml"), reads)
        assertEquals("Last chapter.", source.next())
        assertEquals(listOf("current.xhtml", "last.xhtml"), reads)
        assertNull(source.next())
    }

    @Test
    fun incrementalSpeechKeepsTheNotesSwitchAndReadsThroughTheLastResource() = runBlocking {
        suspend fun spoken(notes: Boolean): List<String> {
            val source = ReaderContentText.source(notes) {
                countingContent(listOf(
                    element("current.xhtml", "Chapter Notes"),
                    element("current.xhtml", "A note.", quote = true),
                    element("current.xhtml", "Story."),
                    element("last.xhtml", "End Notes"),
                    element("last.xhtml", "Final note.", quote = true),
                    element("last.xhtml", "The end.")
                ), mutableListOf())
            }
            return buildList { while (true) add(source.next() ?: break) }
        }
        assertEquals(listOf("Story.", "The end."), spoken(false))
        assertEquals(listOf("A note.", "Story.", "Final note.", "The end."), spoken(true))
    }

    // Readium's own parser: the app's `locatorFromJson` refuses a bare locator by design.
    private fun locator(href: String): Locator = Locator.fromJSON(org.json.JSONObject(
        """{"href":"$href","type":"application/xhtml+xml"}"""
    ))!!

    private fun element(href: String, text: String, quote: Boolean = false): Content.Element {
        val location = locator(href)
        return Content.TextElement(
            locator = location,
            role = if (quote) Content.TextElement.Role.Quote(null, null) else Content.TextElement.Role.Body,
            segments = listOf(Content.TextElement.Segment(location, text, emptyList())),
            attributes = emptyList()
        )
    }

    private fun countingContent(elements: List<Content.Element>, reads: MutableList<String>): Content =
        object : Content {
            override fun iterator(): Content.Iterator = object : Content.Iterator {
                var index = 0
                override suspend fun hasNext(): Boolean = index < elements.size
                override fun next(): Content.Element = elements[index++].also { reads += it.locator.href.toString() }
                override suspend fun hasPrevious(): Boolean = index > 0
                override fun previous(): Content.Element = elements[--index]
            }
        }

}
