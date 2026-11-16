package io.github.cidy02.kudos.reader

import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.network.ao3.work.AO3_HTML_DOWNLOAD_MULTI_CHAPTER
import io.github.cidy02.kudos.reader.readium.ReadiumOpenResult
import io.github.cidy02.kudos.reader.readium.ReadiumPublicationOpener
import io.github.cidy02.kudos.reader.readium.ReadiumTocAdapter
import io.github.cidy02.kudos.works.converters.AO3HtmlDownloadConverter
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

/** The book built from AO3's HTML download, opened by the reader's own Readium path. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class AO3HtmlDownloadReadsLikeAnEpubTest {
    @Test
    fun theReaderSeesPrefaceChaptersAndAfterword() = runBlocking {
        val file = File.createTempFile("ao3-html", ".epub").apply {
            writeBytes(AO3HtmlDownloadConverter.toEpub(AO3_HTML_DOWNLOAD_MULTI_CHAPTER.toByteArray())!!)
        }
        val opened = ReadiumPublicationOpener(ApplicationProvider.getApplicationContext()).open(file)
        val publication = (opened as ReadiumOpenResult.Success).publication

        assertEquals("The Long Road & Back", publication.metadata.title)
        val sections = ReadiumTocAdapter.sections(publication)
        assertEquals(
            listOf(
                ReaderSectionKind.PREFACE to null,
                ReaderSectionKind.CHAPTER to 1,
                ReaderSectionKind.CHAPTER to 2,
                ReaderSectionKind.AFTERWORD to null
            ),
            sections.map { it.kind to it.storyChapterIndex }
        )
        assertEquals(listOf("Preface", "Chapter 1: Setting Out", "Chapter 2", "Afterword"), sections.map { it.title })
    }
}
