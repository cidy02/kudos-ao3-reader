package io.github.cidy02.kudos.reader

import io.github.cidy02.kudos.app.Routes
import io.github.cidy02.kudos.core.model.ReadingAnnotation
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.network.ao3.AO3Error
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ReaderFanMenuTest {
    private val calls = mutableListOf<String>()

    @Test
    fun bookmarkRequiresALiveReadiumPosition() {
        assertFalse(readerHasBookmarkPosition(null))
        assertFalse(readerHasBookmarkPosition(ReaderProgress(0, 0.0)))
        val noPosition = ReaderLocatorCodec.encodeEnvelope(
            """{"href":"one.xhtml","type":"application/xhtml+xml","locations":{"progression":0.1}}"""
        )
        assertFalse(readerHasBookmarkPosition(ReaderProgress(0, 0.1, noPosition)))
        val positioned = ReaderLocatorCodec.encodeEnvelope(
            """{"href":"one.xhtml","type":"application/xhtml+xml","locations":{"position":1}}"""
        )
        assertTrue(readerHasBookmarkPosition(ReaderProgress(0, 0.0, positioned)))
    }

    @Test
    fun restrictedAndMissingWorkKudosFailuresUseIosWords() {
        assertEquals("AO3 refused the request (HTTP 403). Wait a while before trying again.",
            readerKudosErrorMessage(AO3Error.Forbidden))
        assertEquals("That work or page couldn't be found (it may be restricted).",
            readerKudosErrorMessage(AO3Error.NotFound))
    }

    private fun pills(workId: Long? = 123, chapter: Int? = null, searchable: Boolean = true, percent: Int? = null) =
        readerFanPills(
            percent = percent,
            searchable = searchable,
            ao3WorkId = workId,
            commentsChapter = chapter,
            onContents = { calls += "contents:$it" },
            onFind = { calls += "find" },
            onComments = { id, position -> calls += Routes.comments(id, chapterPosition = position) },
            onSettings = { calls += "settings" },
            onHighlightSelection = { calls += "highlight" },
            onNoteSelection = { calls += "note" }
        )

    @Test
    fun iosPillsKeepTheirOrderAndDispatchTheExistingDestinations() {
        val menu = pills(chapter = 2)
        assertEquals(
            listOf("contents", "bookmarks", "find", "comments", "settings", "highlightSelection", "noteSelection"),
            menu.map { it.id }
        )
        assertEquals(
            listOf("Contents", "Bookmarks & Highlights", "Find in Work", "Comments", "Themes & Settings",
                "Highlight selection", "Add note to selection"),
            menu.map { it.title }
        )
        // Highlight and Add Note stay reachable: Android has no selection-menu equivalents.
        menu.forEach { it.action() }
        assertEquals(listOf("contents:0", "contents:1", "find", Routes.comments(123, chapterPosition = 2),
            "settings", "highlight", "note"), calls)
        // Mark finished remains on the existing work page, reached through title-tap.
        assertFalse(menu.any { it.id == "markFinished" })
    }

    @Test
    fun anImportWithoutAo3IdentityOmitsCommentsAndKudosButKeepsLocalActions() {
        assertEquals(listOf("contents", "bookmarks", "find", "settings", "highlightSelection", "noteSelection"),
            pills(workId = null).map { it.id })
        assertNull(readerKudosAction(null, given = false, working = false) { calls += "kudos" })
        assertTrue(calls.isEmpty())
    }

    @Test
    fun unavailableSearchIsVisibleAndDisabledAndKnownZeroProgressIsLabelled() {
        val menu = pills(searchable = false, percent = 0)
        assertEquals("Contents · 0%", menu.first().title)
        assertFalse(menu.single { it.id == "find" }.isEnabled)
        assertEquals("Contents · 42%", pills(percent = 42).first().title)
    }

    @Test
    fun commentsUsesAllWithoutAPositionAndNormalizesFrontAndBackMatter() {
        val sections = ReaderSectionBuilder.build(
            listOf(ReaderSectionBuilder.RawTOCEntry("Preface", 0),
                ReaderSectionBuilder.RawTOCEntry("Chapter One", 2),
                ReaderSectionBuilder.RawTOCEntry("Chapter Two", 3),
                ReaderSectionBuilder.RawTOCEntry("Afterword", 4)),
            listOf("preface.xhtml", "summary.xhtml", "one.xhtml", "two.xhtml", "afterword.xhtml")
        )
        assertNull(sections.commentsChapter(null))
        assertNull(emptyList<ReaderSection>().commentsChapter(0))
        assertEquals(listOf(1, 1, 1, 2, 2), sections.indices.map { sections.commentsChapter(it) })
        assertEquals(1, sections.commentsChapter(-1))
        assertEquals(1, sections.commentsChapter(99))
        pills(chapter = sections.commentsChapter(4)).single { it.id == "comments" }.action()
        pills(chapter = null).single { it.id == "comments" }.action()
        assertEquals(listOf(Routes.comments(123, chapterPosition = 2), Routes.comments(123)), calls)
    }

    @Test
    fun kudosIsAvailableForAnAo3WorkAndDisabledOnlyWhileWorkingOrAlreadyGiven() {
        val idle = readerKudosAction(123, given = false, working = false) { calls += "kudos" }!!
        assertTrue(idle.isEnabled)
        assertEquals("Give kudos", idle.accessibilityLabel)
        idle.action()
        assertEquals(listOf("kudos"), calls)
        assertFalse(readerKudosAction(123, given = false, working = true) {}!!.isEnabled)
        val given = readerKudosAction(123, given = true, working = false) {}!!
        assertFalse(given.isEnabled)
        assertTrue(given.isEmphasized)
        assertEquals("Kudos given", given.accessibilityLabel)
        // No login/restricted/finished/selection input: iOS does not gate the menu on them.
    }

    @Test
    fun shareUsesStoredAo3IdentityThenSourceLinkAndOmitsUnavailableFileSharing() {
        val work = SavedWork(title = "Import", author = "Author")
        assertEquals("https://archiveofourown.org/works/789",
            readerShareUrl(work.copy(ao3WorkID = 789, sourceUrl = "https://archiveofourown.org/works/123")))
        assertEquals("https://archiveofourown.org/works/123",
            readerShareUrl(work.copy(sourceUrl = "https://archiveofourown.org/works/123")))
        assertEquals("https://example.org/story", readerShareUrl(work.copy(sourceUrl = "https://example.org/story")))
        assertNull(readerShareUrl(work))
        assertNull(readerShareUrl(work.copy(sourceUrl = "file:///tmp/original.html")))
    }

    @Test
    fun bookmarkStateMatchesTheExistingNearPositionToggleInsteadOfTheWholeChapter() {
        val bookmark = ReadingAnnotation(workID = "work", spineIndex = 2, progression = 0.4)
        val marks = listOf(bookmark)
        val locator = ReaderLocatorCodec.encodeEnvelope(
            """{"href":"two.xhtml","type":"application/xhtml+xml","locations":{"position":2}}"""
        )
        assertFalse(readerIsBookmarked(marks, null))
        assertFalse(readerIsBookmarked(marks, ReaderProgress(2, 0.4)))
        assertTrue(readerIsBookmarked(marks, ReaderProgress(2, 0.8, locator, totalProgression = 0.41)))
        assertFalse(readerIsBookmarked(marks, ReaderProgress(2, 0.8, locator, totalProgression = 0.5)))
        assertFalse(readerIsBookmarked(marks, ReaderProgress(1, 0.4, locator)))
        assertTrue(readerIsBookmarked(marks, ReaderProgress(2, 0.4, locator)))
    }
}
