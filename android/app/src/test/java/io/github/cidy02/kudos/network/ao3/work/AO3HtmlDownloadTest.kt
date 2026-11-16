package io.github.cidy02.kudos.network.ao3.work

import io.github.cidy02.kudos.network.ao3.AO3BinaryResponse
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.works.EpubImportMetadata
import io.github.cidy02.kudos.works.converters.AO3HtmlDownloadConverter
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.zip.ZipInputStream

/**
 * AO3 serving HTML only (November 2026). Fixtures are written out from otwarchive
 * 452391b648f2's own templates — `downloads/show` with its three partials under the
 * `barebones` layout, and `works/_work_header_navigation` for the menu — not from a
 * saved page.
 */
class AO3HtmlDownloadTest {
    @Test
    fun theMenuSaysWhichFormatsAreOffered() {
        assertEquals(setOf("html"), AO3EpubDownloader.offeredFormats(workPage("html")))
        assertEquals(
            setOf("azw3", "epub", "mobi", "pdf", "html"),
            AO3EpubDownloader.offeredFormats(workPage("azw3", "epub", "mobi", "pdf", "html"))
        )
        // A guest's view of a restricted work, or downloads switched off: no menu at all.
        assertNull(AO3EpubDownloader.offeredFormats("<html><body><ul class=\"work navigation actions\"></ul></body></html>"))
    }

    @Test
    fun anHtmlDownloadBecomesTheEpubAo3WouldHaveMade() = runTest {
        val fetched = mutableListOf<String>()
        val epub = AO3HtmlDownloadConverter.toEpub(AO3_HTML_DOWNLOAD_MULTI_CHAPTER.toByteArray()) { url ->
            fetched += url
            if (url.endsWith("map.png")) PNG else null
        }!!
        val files = unzip(epub)

        assertEquals("mimetype", files.keys.first())
        assertTrue(EpubImportMetadata.isReadablePackage(epub))

        // calibre's split: Preface, one section per chapter heading, Afterword.
        val nav = files.getValue("OEBPS/nav.xhtml")
        assertEquals(
            listOf("Preface", "Chapter 1: Setting Out", "Chapter 2", "Afterword"),
            Regex("<a href=\"section-\\d\\.xhtml\">([^<]+)</a>").findAll(nav).map { it.groupValues[1] }.toList()
        )
        assertEquals(4, Regex("<itemref ").findAll(files.getValue("OEBPS/content.opf")).count())
        assertTrue(files.getValue("OEBPS/section-1.xhtml").contains("The road began at the door."))
        assertFalse(files.getValue("OEBPS/section-1.xhtml").contains("It ended at the sea."))
        assertTrue(files.getValue("OEBPS/section-2.xhtml").contains("It ended at the sea."))
        assertTrue(files.getValue("OEBPS/section-2.xhtml").contains("Thanks for reading chapter two."))
        assertTrue(files.getValue("OEBPS/section-3.xhtml").contains("drop by the Archive and comment"))

        // The metadata calibre is handed.
        val opf = files.getValue("OEBPS/content.opf")
        assertTrue(opf.contains("<dc:title>The Long Road &amp; Back</dc:title>"))
        assertTrue(opf.contains("<dc:creator>ink_and_oak, second_author (their_pseud)</dc:creator>"))
        assertTrue(opf.contains("<dc:language>fr</dc:language>"))
        assertTrue(opf.contains("<dc:description>Two friends walk to the sea.</dc:description>"))
        assertTrue(opf.contains("<dc:source>https://archiveofourown.org/works/4242</dc:source>"))
        assertTrue(opf.contains("<dc:date>2026-03-09</dc:date>"))
        assertTrue(opf.contains("<meta name=\"calibre:series\" content=\"Roads\"/>"))
        assertTrue(opf.contains("<meta name=\"calibre:series_index\" content=\"2\"/>"))
        assertEquals(
            listOf("Teen And Up Audiences", "No Archive Warnings Apply", "Gen", "Original Work", "Fluff"),
            Regex("<dc:subject>([^<]+)</dc:subject>").findAll(opf).map { it.groupValues[1] }.toList()
        )

        // The preface keeps the structure importers read an AO3 EPUB's preface by.
        val preface = files.getValue("OEBPS/section-0.xhtml")
        assertTrue(preface.contains("<dl class=\"tags\">"))
        assertFalse(preface.contains("toc-heading"))
        // "See the end of the work for notes" now names the file the notes are in.
        assertTrue(preface.contains("href=\"section-3.xhtml#endnotes\""))
        assertTrue(files.getValue("OEBPS/section-3.xhtml").contains("id=\"endnotes\""))

        // The image that could be fetched is in the book; the one that could not is gone,
        // and nothing is left pointing at a host. Scripts and styles never make it in.
        assertEquals(listOf("https://img.example/map.png", "https://img.example/gone.jpg"), fetched)
        assertTrue(files.containsKey("OEBPS/images/image-1.png"))
        val chapterOne = files.getValue("OEBPS/section-1.xhtml")
        assertTrue(chapterOne.contains("src=\"images/image-1.png\""))
        assertFalse(files.values.any { it.contains("img.example") })
        assertFalse(files.values.any { it.contains("alert(1)") })
        assertTrue(chapterOne.contains("<br />"))

        // The same download always makes the same file, so two devices agree on its digest.
        val again = AO3HtmlDownloadConverter.toEpub(AO3_HTML_DOWNLOAD_MULTI_CHAPTER.toByteArray()) { if (it.endsWith("map.png")) PNG else null }!!
        assertTrue(epub.contentEquals(again))
    }

    @Test
    fun aSingleChapterWorkHasOneSectionNamedForTheWork() = runTest {
        val files = unzip(AO3HtmlDownloadConverter.toEpub(SINGLE_CHAPTER.toByteArray())!!)
        assertEquals(
            listOf("Preface", "One Shot", "Afterword"),
            Regex("<a href=\"section-\\d\\.xhtml\">([^<]+)</a>").findAll(files.getValue("OEBPS/nav.xhtml"))
                .map { it.groupValues[1] }.toList()
        )
        assertTrue(files.getValue("OEBPS/section-1.xhtml").contains("All of it, at once."))
        assertTrue(files.getValue("OEBPS/content.opf").contains("<dc:creator>Anonymous</dc:creator>"))
    }

    @Test
    fun anOrdinaryPageIsNotABook() = runTest {
        assertNull(AO3HtmlDownloadConverter.toEpub(workPage("html").toByteArray()))
        assertNull(AO3HtmlDownloadConverter.toEpub("<html><body><div id=\"main\">Sorry.</div></body></html>".toByteArray()))
    }

    @Test
    fun whenAo3OffersOnlyHtmlTheDownloadIsStillAnEpubAndTheNextOneGoesStraightToHtml() = runTest {
        var clock = 0L
        val client = ScriptedClient(page = workPage("html"), html = SINGLE_CHAPTER)
        val downloader = AO3EpubDownloader(client, fetchImage = { null }, now = { clock })

        val first = downloader.download(7)
        assertTrue(EpubImportMetadata.isReadablePackage((first as AO3Result.Success).value))
        assertEquals(
            listOf(
                "https://archiveofourown.org/downloads/7/work.epub",
                "https://archiveofourown.org/works/7?view_adult=true",
                "https://archiveofourown.org/downloads/7/work.html"
            ),
            client.requests
        )

        client.requests.clear()
        assertTrue(downloader.download(8) is AO3Result.Success)
        assertEquals(listOf("https://archiveofourown.org/downloads/8/work.html"), client.requests)

        // Not for ever: EPUB is tried again once the memory lapses.
        clock += 16 * 60 * 1000
        client.requests.clear()
        downloader.download(9)
        assertEquals("https://archiveofourown.org/downloads/9/work.epub", client.requests.first())
    }

    @Test
    fun anEpubThatFailsWhileStillOnTheMenuIsAFailureAndHtmlIsNotAsked() = runTest {
        val client = ScriptedClient(page = workPage("epub", "html"), html = SINGLE_CHAPTER)
        val result = AO3EpubDownloader(client, fetchImage = { null }).download(7)
        assertTrue((result as AO3Result.Failure).error is AO3Error.Parse)
        assertFalse(client.requests.any { it.endsWith(".html") })
    }

    @Test
    fun withNoMenuToReadHtmlIsTriedAndTheFirstAnswerStandsIfItFailsToo() = runTest {
        val noMenu = "<html><body><p>This work is only available to registered users.</p></body></html>"
        val served = AO3EpubDownloader(ScriptedClient(page = noMenu, html = SINGLE_CHAPTER), fetchImage = { null })
        assertTrue(served.download(7) is AO3Result.Success)

        val refused = AO3EpubDownloader(ScriptedClient(page = noMenu, html = noMenu), fetchImage = { null })
        val error = (refused.download(7) as AO3Result.Failure).error
        assertEquals(AO3Error.Parse("AO3 returned an HTML page instead of an EPUB."), error)
    }

    @Test
    fun beingOfflineBlockedOrToldToSlowDownAsksForNothingMore() = runTest {
        for (error in listOf(
            AO3Error.Network("offline", offline = true), AO3Error.RateLimited(null), AO3Error.Maintenance,
            AO3Error.Forbidden, AO3Error.Server(503)
        )) {
            val client = ScriptedClient(page = workPage("html"), html = SINGLE_CHAPTER, epub = AO3Result.Failure(error))
            assertEquals(error, (AO3EpubDownloader(client, fetchImage = { null }).download(7) as AO3Result.Failure).error)
            assertEquals(1, client.requests.size)
        }
    }

    @Test
    fun aWorkThatIsGoneIsStillReportedAsGone() = runTest {
        val gone = object : AO3Client {
            val requests = mutableListOf<String>()
            override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
                requests += url
                return AO3Result.Failure(AO3Error.NotFound)
            }
            override suspend fun getBytes(url: String, headers: Map<String, String>): AO3Result<AO3BinaryResponse> {
                requests += url
                return AO3Result.Failure(AO3Error.NotFound)
            }
        }
        assertEquals(AO3Error.NotFound, (AO3EpubDownloader(gone, fetchImage = { null }).download(7) as AO3Result.Failure).error)
        assertEquals(2, gone.requests.size)
    }

    @Test
    fun anHtmlLinkChosenOnTheSiteIsImportedLikeAnEpubOne() = runTest {
        val url = "https://archiveofourown.org/downloads/7/One_Shot.html?updated_at=1763000000"
        assertTrue(AO3EpubDownloader.isEpubDownload(url))
        assertFalse(AO3EpubDownloader.isEpubDownload("https://archiveofourown.org/works/7/chapters/1.html"))
        val client = ScriptedClient(page = "", html = SINGLE_CHAPTER)
        assertTrue(AO3EpubDownloader(client, fetchImage = { null }).downloadUrl(url) is AO3Result.Success)
        assertEquals(listOf(url), client.requests)
    }

    private fun unzip(bytes: ByteArray): Map<String, String> = LinkedHashMap<String, String>().also { files ->
        ZipInputStream(bytes.inputStream()).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                files[entry.name] = zip.readBytes().toString(Charsets.ISO_8859_1)
            }
        }
    }
}

/** EPUB requests get AO3's "we could not render this" page unless [epub] says otherwise. */
private class ScriptedClient(
    private val page: String,
    private val html: String,
    private val epub: AO3Result<AO3BinaryResponse>? = null
) : AO3Client {
    val requests = mutableListOf<String>()

    override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        requests += url
        return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), page))
    }

    override suspend fun getBytes(url: String, headers: Map<String, String>): AO3Result<AO3BinaryResponse> {
        requests += url
        if (url.substringBefore('?').endsWith(".epub")) {
            epub?.let { return it }
        }
        val body = if (url.substringBefore('?').endsWith(".html")) html else "<!DOCTYPE html><html><body>Sorry.</body></html>"
        return AO3Result.Success(AO3BinaryResponse(url, 200, mapOf("Content-Type" to listOf("text/html")), body.toByteArray()))
    }
}

private val PNG = byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0)

/** `works/_work_header_navigation.html.erb`: the li, noscript and button share a line. */
private fun workPage(vararg formats: String): String = """
<html><body><ul class="work navigation actions">
  <li class="comments" id="show_comments_link_top"><a href="/works/7?show_comments=true">Comments</a></li>
  <li class="download"><noscript><h4 class="heading">Download</h4></noscript><button class="hidden">Download</button>
      <ul class="expandable secondary">
${formats.joinToString("\n") { "          <li><a href=\"/downloads/7/One_Shot.$it?updated_at=1763000000\">${it.uppercase()}</a></li>" }}
      </ul>
    </li>
</ul></body></html>
"""

private const val HEAD = """<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
  <meta charset="utf-8" />
  <meta http-equiv="x-ua-compatible" content="ie=edge" />
  <title>TITLE</title>
  <style type="text/css">
    p.message { text-align: center; }
    .toc-heading { display: none; }
  </style>
</head>
<body>
"""

internal val AO3_HTML_DOWNLOAD_MULTI_CHAPTER = HEAD.replace("TITLE", "The Long Road &amp; Back - ink_and_oak, second_author (their_pseud) - Original Work") + """
<div id="preface">
  <h2 class="toc-heading">Preface</h2>

  <p class="message">
    <b>The Long Road &amp; Back</b><br />
    Posted originally on the <a href="https://archiveofourown.org/">Archive of Our Own</a> at <a href="https://archiveofourown.org/works/4242">https://archiveofourown.org/works/4242</a>.
  </p>

  <div class="meta">
    <dl class="tags">
          <dt>Rating:</dt>
          <dd><a href="https://archiveofourown.org/tags/Teen%20And%20Up%20Audiences">Teen And Up Audiences</a></dd>
          <dt>Archive Warning:</dt>
          <dd><a href="https://archiveofourown.org/tags/No%20Archive%20Warnings%20Apply">No Archive Warnings Apply</a></dd>
          <dt>Category:</dt>
          <dd><a href="https://archiveofourown.org/tags/Gen">Gen</a></dd>
          <dt>Fandom:</dt>
          <dd><a href="https://archiveofourown.org/tags/Original%20Work">Original Work</a></dd>
          <dt>Additional Tags:</dt>
          <dd><a href="https://archiveofourown.org/tags/Fluff">Fluff</a></dd>
        <dt>Language:</dt>
        <dd>Français</dd>
        <dt>Series:</dt>
        <dd>Part 2 of <a href="https://archiveofourown.org/series/99">Roads</a></dd>
        <dt>Collections:</dt>
        <dd><a href="https://archiveofourown.org/collections/walks">Long Walks</a></dd>
      <dt>Stats:</dt>
      <dd>
        Published: 2026-03-01
          Completed: 2026-03-09
        Words: 1,234
        Chapters: 2/2
      </dd>
    </dl>
    <h1>The Long Road &amp; Back</h1>
    <div class="byline">by <a rel="author" href="https://archiveofourown.org/users/ink_and_oak/pseuds/ink_and_oak">ink_and_oak</a>, <a rel="author" href="https://archiveofourown.org/users/second_author/pseuds/their_pseud">second_author (their_pseud)</a></div>
      <p>Summary</p>
      <blockquote class="userstuff"><p>Two friends walk to the sea.</p></blockquote>

      <p>Notes</p>
        <blockquote class="userstuff"><p>Written for a friend.</p></blockquote>
        <div class="endnote-link">
          See the end of the work for <a href="#endnotes">more notes</a>
        </div>

  </div>
</div>

<div id="chapters" class="userstuff">
<div class="meta group">
  <h2 class="heading">
      Chapter 1: Setting Out
  </h2>

    <p>Chapter Notes</p>
      <blockquote class="userstuff"><p>A short start.</p></blockquote>
</div>

<!--chapter content-->
<div class="userstuff">
  <p>The road began at the door.<br>It went on.</p>
  <p><img src="https://img.example/map.png" alt="A map" onerror="alert(1)"></p>
  <p><img src="https://img.example/gone.jpg" alt="Lost"></p>
  <script>alert(1)</script>
</div>
<!--/chapter content-->

<div class="meta group">
  <h2 class="heading">
      Chapter 2
  </h2>

    <p>Chapter Notes</p>
      <div class="endnote-link">
        See the end of the chapter for <a href="#endnotes2">notes</a>
      </div>
</div>

<!--chapter content-->
<div class="userstuff">
  <p>It ended at the sea.</p>
</div>
<!--/chapter content-->

  <div class="meta" id="endnotes2">
    <p>Chapter End Notes</p>
    <blockquote class="userstuff"><p>Thanks for reading chapter two.</p></blockquote>
  </div>
</div>

<div id="afterword">
  <h2 class="toc-heading">Afterword</h2>

    <div class="meta">
        <div id="endnotes">
          <p>End Notes</p>
          <blockquote class="userstuff"><p>That is all.</p></blockquote>
        </div>
    </div>

  <p class="message">Please <a href="https://archiveofourown.org/works/4242/comments/new">drop by the Archive and comment</a> to let the creator know if you enjoyed their work!</p>
</div>

</body>
</html>
"""

private val SINGLE_CHAPTER = HEAD.replace("TITLE", "One Shot - Anonymous - No fandom specified") + """
<div id="preface">
  <h2 class="toc-heading">Preface</h2>

  <p class="message">
    <b>One Shot</b><br />
    Posted originally on the <a href="https://archiveofourown.org/">Archive of Our Own</a> at <a href="https://archiveofourown.org/works/7">https://archiveofourown.org/works/7</a>.
  </p>

  <div class="meta">
    <dl class="tags">
          <dt>Rating:</dt>
          <dd><a href="https://archiveofourown.org/tags/Not%20Rated">Not Rated</a></dd>
        <dt>Language:</dt>
        <dd>English</dd>
      <dt>Stats:</dt>
      <dd>
        Published: 2026-11-10
        Words: 5
        Chapters: 1/1
      </dd>
    </dl>
    <h1>One Shot</h1>
    <div class="byline">by Anonymous</div>

  </div>
</div>

<div id="chapters" class="userstuff">
    <h2 class="toc-heading">One Shot</h2>
    <div class="userstuff">
      <p>All of it, at once.</p>
    </div>
</div>

<div id="afterword">
  <h2 class="toc-heading">Afterword</h2>


  <p class="message">Please <a href="https://archiveofourown.org/works/7/comments/new">drop by the Archive and comment</a> to let the creator know if you enjoyed their work!</p>
</div>

</body>
</html>
"""
