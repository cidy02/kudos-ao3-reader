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
    fun emptyTextYieldsNoChunks() {
        assertTrue(ReaderContentText.splitIntoSpeakableChunks("   ").isEmpty())
    }
}
