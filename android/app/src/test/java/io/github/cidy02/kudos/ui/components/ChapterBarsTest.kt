package io.github.cidy02.kudos.ui.components

import io.github.cidy02.kudos.home.ResumeCardModel
import io.github.cidy02.kudos.works.ChapterLengthCache
import io.github.cidy02.kudos.works.WorkReadingPosition
import java.io.File
import java.nio.file.Files
import java.util.UUID
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Android port of iOS `ChapterBarsTests` (T-477 + T-514):
 * one test per edge-case rule (counts in, bars out), each failing if its rule is reverted.
 */
class ChapterBarsTest {

    @Test
    fun oneSevenAndFortyBarsKeepTheirWidthUntilTheLineIsFull() {
        val one = ChapterBarGeometry.metrics(count = 1, availableWidth = 400f, nominalWidth = 6f, gap = 2f)
        assertEquals(6f, one.width, 0.0001f)
        assertEquals(3f, one.radius, 0.0001f)

        val seven = ChapterBarGeometry.metrics(count = 7, availableWidth = 400f, nominalWidth = 6f, gap = 2f)
        assertEquals(6f, seven.width, 0.0001f)
        assertEquals(2f, seven.gap, 0.0001f)
        assertEquals(3f, seven.radius, 0.0001f)

        val forty = ChapterBarGeometry.metrics(count = 40, availableWidth = 400f, nominalWidth = 6f, gap = 2f)
        assertEquals(6f, forty.width, 0.0001f)
        assertEquals(2f, forty.gap, 0.0001f)
        assertEquals(minOf(3f, forty.width / 2f), forty.radius, 0.0001f)

        val cramped = ChapterBarGeometry.metrics(count = 40, availableWidth = 120f, nominalWidth = 6f, gap = 2f)
        assertTrue(cramped.width < 6f)
        assertEquals(2f, cramped.gap, 0.0001f)
        assertEquals(minOf(3f, cramped.width / 2f), cramped.radius, 0.0001f)

        val card = ChapterBarGeometry.metrics(count = 7, availableWidth = 800f, nominalWidth = 14f, gap = 4f)
        assertEquals(14f, card.width, 0.0001f)
        assertEquals(4f, card.gap, 0.0001f)
        assertEquals(3f, card.radius, 0.0001f)
    }

    @Test
    fun barsMarkReadCurrentUnreadAndUnposted() {
        val oneRead = ChapterBarGeometry.items(planned = null, posted = 1, progress = 1.0, weights = null)
        assertEquals(listOf(ChapterBarItem(role = ChapterBarRole.Read, weight = 1.0)), oneRead)

        val oneCurrent = ChapterBarGeometry.items(planned = null, posted = 1, progress = 0.4, weights = null)
        assertEquals(listOf(ChapterBarItem(role = ChapterBarRole.Current(fill = 0.4), weight = 1.0)), oneCurrent)

        val oneUnread = ChapterBarGeometry.items(planned = null, posted = 1, progress = null, weights = null)
        assertEquals(listOf(ChapterBarItem(role = ChapterBarRole.PostedUnread, weight = 1.0)), oneUnread)

        val seven = ChapterBarGeometry.items(planned = 7, posted = 5, progress = 0.5, weights = null)
        assertEquals(
            listOf(
                ChapterBarRole.Read,
                ChapterBarRole.Read,
                ChapterBarRole.Current(fill = 0.5),
                ChapterBarRole.PostedUnread,
                ChapterBarRole.PostedUnread,
                ChapterBarRole.NotPosted,
                ChapterBarRole.NotPosted
            ),
            seven.map { it.role }
        )

        val forty = ChapterBarGeometry.items(planned = 40, posted = 10, progress = null, weights = null)
        assertEquals(40, forty.size)
        assertTrue(forty.take(10).all { it.role == ChapterBarRole.PostedUnread })
        assertTrue(forty.drop(10).all { it.role == ChapterBarRole.NotPosted })
    }

    @Test
    fun newChaptersAreMarkedAndLengthsSetTheHeights() {
        val fresh = ChapterBarGeometry.items(
            planned = 7, posted = 5, progress = 0.5, weights = null, newChapterCount = 2
        )
        assertEquals(ChapterBarRole.NewChapter, fresh[3].role)
        assertEquals(ChapterBarRole.NewChapter, fresh[4].role)
        assertEquals(ChapterBarRole.Read, fresh[0].role)
        assertEquals(ChapterBarRole.NotPosted, fresh[5].role)

        val sized = ChapterBarGeometry.items(
            planned = 3, posted = 2, progress = null, weights = listOf(1.0, 3.0)
        )
        assertEquals(listOf(1.0, 3.0, 2.0), sized.map { it.weight })
        assertEquals(
            listOf(ChapterBarRole.PostedUnread, ChapterBarRole.PostedUnread, ChapterBarRole.NotPosted),
            sized.map { it.role }
        )
    }

    @Test
    fun progressLabelNamesTheChapterAndThePercent() {
        assertEquals("Ch 7 · 58%", ChapterBarGeometry.progressLabel("12/20", progress = 0.58, isFinished = false))
        assertNull(ChapterBarGeometry.progressLabel("12/20", progress = 0.0, isFinished = false))
        assertEquals("Ch 12 · 100%", ChapterBarGeometry.progressLabel("12/20", progress = null, isFinished = true))
        assertEquals(
            "Ch 2 · 50%",
            ChapterBarGeometry.progressLabel("3/3", progress = 0.5, isFinished = false, weights = listOf(1, 1, 2))
        )
    }

    @Test
    fun aChangedFileDropsTheCachedChapterLengths() {
        val dir = Files.createTempDirectory("chapter-cache").toFile()
        try {
            val file = File(dir, "work.epub")
            file.writeText("not an epub")
            val id = UUID.randomUUID().toString()
            ChapterLengthCache.store(id, file, weights = listOf(4, 9), cacheDir = dir)
            assertEquals(listOf(4, 9), ChapterLengthCache.weights(id, file, dir))

            file.writeText("not an epub anymore")
            assertNull(ChapterLengthCache.weights(id, file, dir))
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun measuredChaptersFollowTheEpubAndIgnoreFrontMatter() {
        val dir = Files.createTempDirectory("chapter-measure").toFile()
        try {
            val file = File(dir, "work.epub")
            writeMinimalEpub(
                file,
                chapters = listOf(
                    "Preface" to "preface words ignored",
                    "Chapter 1" to List(10) { "word" }.joinToString(" "),
                    "Chapter 2" to List(40) { "word" }.joinToString(" "),
                    "Afterword" to "afterword ignored"
                )
            )
            val id = UUID.randomUUID().toString()
            val lengths = ChapterLengthCache.lengths(id, file, dir)!!
            assertEquals(2, lengths.words.size)
            assertTrue(lengths.words[1] > lengths.words[0])
            assertEquals(lengths, ChapterLengthCache.lengths(id, file, dir))
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun defaultTwelveOfTwentyCardIsUnchanged() {
        val layout = ChapterBarGeometry.layout(
            planned = 20,
            posted = 12,
            read = 6,
            chapterProgress = 0.22,
            scale = ChapterBarScale.Card,
            availableWidth = 326f
        )
        assertEquals(20, layout.bars.size)
        assertTrue(layout.bars.take(6).all { it.role == ChapterBarRole.Read })
        assertEquals(ChapterBarRole.Current(fill = 0.22), layout.bars[6].role)
        assertTrue(layout.bars.subList(7, 12).all { it.role == ChapterBarRole.PostedUnread })
        assertTrue(layout.bars.drop(12).all { it.role == ChapterBarRole.NotPosted })
        assertNull(layout.trackFill)
        assertFalse(layout.showsOpenTotalDots)
        assertEquals(1, layout.chaptersPerBar)
        assertNull(layout.groupNote)
        assertEquals((326f - 19 * 4f) / 20f, layout.metrics.width, 0.0001f) // 12.5

        val model = ResumeCardModel(
            title = "The Cartographer's Daughter",
            chapters = "12/20",
            rawProgress = 0.58,
            rawChapterProgress = 0.22,
            chapterName = "Ch 7, The Salt Road",
            updated = "Oct 21"
        )
        val cardLayout = model.chapterBarLayout(lengths = null)
        assertEquals(20, cardLayout.bars.size)
        assertTrue(cardLayout.bars.take(6).all { it.role == ChapterBarRole.Read })
        assertTrue(cardLayout.bars.drop(12).all { it.role == ChapterBarRole.NotPosted })
        assertFalse(cardLayout.showsOpenTotalDots)
        assertNull(cardLayout.trackFill)
        assertEquals("12 of 20 posted", model.postedLabel)
        assertEquals("12 of 20", model.postedShortLabel)
        assertEquals("Resume Chapter 7", model.detailPrimaryTitle(fallback = "Read"))
    }

    @Test
    fun unknownTotalDrawsPostedBarsAndThreeFadingDotsWithoutDashedBars() {
        val layout = ChapterBarModel.layout(
            chapters = "12/?",
            read = 6,
            chapterProgress = 0.22,
            progress = null,
            weights = null,
            scale = ChapterBarScale.Card
        )
        assertEquals(12, layout.bars.size)
        assertFalse(layout.bars.any { it.role == ChapterBarRole.NotPosted })
        assertTrue(layout.bars.take(6).all { it.role == ChapterBarRole.Read })
        assertEquals(ChapterBarRole.Current(fill = 0.22), layout.bars[6].role)
        assertTrue(layout.bars.drop(7).all { it.role == ChapterBarRole.PostedUnread })
        assertTrue(layout.showsOpenTotalDots)
        assertNull(layout.trackFill)
        assertEquals("Chapters: 6 read, 12 posted, total not set by the author", layout.accessibilityLabel)
    }

    @Test
    fun oneChapterWorkDrawsATrackWithNoBarsAndButtonReadsResume() {
        val card = ChapterBarModel.layout(
            chapters = "1/1",
            progress = 0.38,
            weights = null,
            scale = ChapterBarScale.Card
        )
        assertTrue(card.bars.isEmpty())
        assertEquals(0.38, card.trackFill!!, 0.0001)
        assertFalse(card.showsOpenTotalDots)
        assertEquals("One chapter, 38 percent read", card.accessibilityLabel)

        val row = ChapterBarModel.layout(
            chapters = "1/1",
            progress = null,
            weights = null,
            newChapterCount = 1,
            scale = ChapterBarScale.Row
        )
        assertTrue(row.bars.isEmpty())
        assertEquals(1.0, row.trackFill!!, 0.0001)
        assertEquals("New work, one chapter", row.accessibilityLabel)

        val model = ResumeCardModel(
            title = "One-shot",
            chapters = "1/1",
            rawProgress = 0.38,
            rawChapterProgress = 0.38,
            chapterName = "Chapter 1"
        )
        assertEquals("Resume", model.detailPrimaryTitle(fallback = "Read"))
        assertEquals("One chapter", model.postedLabel)

        val unreadModel = model.copy(rawProgress = null, rawChapterProgress = null, chapterName = null)
        assertEquals("Read", unreadModel.detailPrimaryTitle(fallback = "Read"))
    }

    @Test
    fun moreChaptersThanFitGroupIntoEqualBarsWithANote() {
        val longCard = ChapterBarGeometry.layout(
            planned = 200,
            posted = 143,
            read = 61,
            chapterProgress = 0.40,
            scale = ChapterBarScale.Card,
            fit = 37
        )
        assertEquals(6, longCard.chaptersPerBar)
        assertEquals(34, longCard.bars.size)
        assertEquals("Each bar is 6 chapters", longCard.groupNote)
        assertFalse(longCard.showsOpenTotalDots)
        assertTrue(longCard.bars.take(10).all { it.role == ChapterBarRole.Read })
        assertEquals(ChapterBarRole.Current(fill = 1.4 / 6.0), longCard.bars[10].role)
        // Group 23 covers chapters 138..<144 (5 posted, 1 unposted) and counts as posted.
        assertEquals(ChapterBarRole.PostedUnread, longCard.bars[23].role)
        assertTrue(longCard.bars.drop(24).all { it.role == ChapterBarRole.NotPosted })

        val longOpen = ChapterBarGeometry.layout(
            planned = null,
            posted = 312,
            read = 100,
            scale = ChapterBarScale.Card
        )
        assertEquals(7, longOpen.chaptersPerBar)
        assertEquals(45, longOpen.bars.size)
        assertTrue(longOpen.showsOpenTotalDots)
        assertFalse(longOpen.bars.any { it.role == ChapterBarRole.NotPosted })
        assertEquals("Each bar is 7 chapters", longOpen.groupNote)

        val longRow = ChapterBarGeometry.layout(
            planned = null,
            posted = 214,
            newChapterCount = 2,
            scale = ChapterBarScale.Row,
            availableWidth = 204f
        )
        assertEquals(6, longRow.chaptersPerBar)
        assertEquals(36, longRow.bars.size)
        assertTrue(longRow.showsOpenTotalDots)
        assertEquals(ChapterBarRole.Current(fill = 0.5), longRow.bars.last().role)
    }

    @Test
    fun fewChaptersCapBarWidthAtTwentySevenPoints() {
        val layout = ChapterBarGeometry.layout(
            planned = 4,
            posted = 3,
            read = 1,
            chapterProgress = 0.60,
            scale = ChapterBarScale.Card,
            availableWidth = 326f
        )
        assertEquals(4, layout.bars.size)
        assertEquals(
            listOf(
                ChapterBarRole.Read,
                ChapterBarRole.Current(fill = 0.60),
                ChapterBarRole.PostedUnread,
                ChapterBarRole.NotPosted
            ),
            layout.bars.map { it.role }
        )
        assertEquals(27f, layout.metrics.width, 0.0001f)
    }

    @Test
    fun unknownLengthsGiveEveryBarOneHeight() {
        val layout = ChapterBarGeometry.layout(
            planned = 20,
            posted = 12,
            read = 0,
            weights = null,
            heights = null,
            scale = ChapterBarScale.Card
        )
        assertEquals(20, layout.bars.size)
        assertTrue(layout.bars.all { it.weight == 1.0 })
    }

    @Test
    fun readCountIsCappedAtPostedChapters() {
        val layout = ChapterBarGeometry.layout(
            planned = 20,
            posted = 12,
            read = 16,
            chapterProgress = 0.5,
            scale = ChapterBarScale.Card
        )
        assertEquals(20, layout.bars.size)
        assertTrue(layout.bars.take(12).all { it.role == ChapterBarRole.Read })
        assertTrue(layout.bars.drop(12).all { it.role == ChapterBarRole.NotPosted })
        assertEquals("Chapters: 12 read, 12 posted, 8 not posted yet", layout.accessibilityLabel)
    }

    @Test
    fun talkBackSummaryDescribesTheWholeImage() {
        val usual = ChapterBarGeometry.layout(planned = 20, posted = 12, read = 6, scale = ChapterBarScale.Card)
        assertEquals("Chapters: 6 read, 12 posted, 8 not posted yet", usual.accessibilityLabel)

        val openTotal = ChapterBarGeometry.layout(planned = null, posted = 12, read = 6, scale = ChapterBarScale.Card)
        assertEquals("Chapters: 6 read, 12 posted, total not set by the author", openTotal.accessibilityLabel)

        val grouped = ChapterBarGeometry.layout(planned = 200, posted = 143, read = 61, scale = ChapterBarScale.Card, fit = 37)
        assertEquals(
            "Chapters: 61 read, 143 posted, 57 not posted yet. Each bar is 6 chapters",
            grouped.accessibilityLabel
        )

        val rowFresh = ChapterBarGeometry.layout(planned = 30, posted = 15, newChapterCount = 3, scale = ChapterBarScale.Row)
        assertEquals("3 new chapters, 15 posted, 15 not posted yet", rowFresh.accessibilityLabel)

        val rowOpenFresh = ChapterBarGeometry.layout(planned = nilOrZero(), posted = 5, newChapterCount = 1, scale = ChapterBarScale.Row)
        assertEquals("1 new chapter, 5 posted, total not set by the author", rowOpenFresh.accessibilityLabel)
    }

    @Test
    fun workReadingPositionExtractsWrappedAndBareChapterProgress() {
        val wrapped = """{"platform":"android","engine":"readium-kotlin","version":1,"locator":{"title":"Chapter 3","locations":{"progression":0.42}}}"""
        assertEquals("Chapter 3", WorkReadingPosition.title(wrapped))
        assertEquals(0.42, WorkReadingPosition.chapterProgress(wrapped)!!, 0.0001)

        val bare = """{"title":"Chapter 2","locations":{"progression":0.75}}"""
        assertEquals("Chapter 2", WorkReadingPosition.title(bare))
        assertEquals(0.75, WorkReadingPosition.chapterProgress(bare)!!, 0.0001)
    }

    private fun nilOrZero(): Int? = null

    private fun writeMinimalEpub(dest: File, chapters: List<Pair<String, String>>) {
        ZipOutputStream(dest.outputStream()).use { zip ->
            zip.putNextEntry(ZipEntry("META-INF/container.xml"))
            zip.write(
                """<?xml version="1.0"?>
                <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
                  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
                </container>""".toByteArray()
            )
            zip.closeEntry()

            val items = chapters.indices.joinToString("\n") { i ->
                """<item id="c$i" href="c$i.xhtml" media-type="application/xhtml+xml"/>"""
            }
            val itemRefs = chapters.indices.joinToString("\n") { i ->
                """<itemref idref="c$i"/>"""
            }
            zip.putNextEntry(ZipEntry("OEBPS/content.opf"))
            zip.write(
                """<?xml version="1.0"?>
                <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
                  <manifest>
                    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
                    $items
                  </manifest>
                  <spine>$itemRefs</spine>
                </package>""".toByteArray()
            )
            zip.closeEntry()

            val navLinks = chapters.mapIndexed { i, (title, _) ->
                """<li><a href="c$i.xhtml">$title</a></li>"""
            }.joinToString("\n")
            zip.putNextEntry(ZipEntry("OEBPS/nav.xhtml"))
            zip.write(
                """<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
                <body><nav epub:type="toc"><ol>$navLinks</ol></nav></body></html>""".toByteArray()
            )
            zip.closeEntry()

            chapters.forEachIndexed { i, (title, body) ->
                zip.putNextEntry(ZipEntry("OEBPS/c$i.xhtml"))
                zip.write("<html><head><title>$title</title></head><body><p>$body</p></body></html>".toByteArray())
                zip.closeEntry()
            }
        }
    }
}
