package io.github.cidy02.kudos.writing

import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.writing.*
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test
import java.time.LocalDate

class WritingChapterFormStateTest {
    @Test fun oneOpeningReadEditsAllFourRecoveryFieldsAndReturnsWithoutReading() = runTest {
        val setup = workFormSetup()
        setup.client.body = workFixture("ao3_demo_chapter_995006_new")
        val model = WritingChapterFormState(995006, null, null, setup.repository, setup.auth, writes = setup.writes)
        model.load(); model.load(); model.load(retry = true)
        assertEquals(1, setup.client.gets.size)
        model.title("  Title & 星  "); model.total("17"); model.afterChapter("12")
        for (field in ChapterFormText.entries) model.checkpoint(field, "<p>${field.field} &amp; 星</p>\n")
        val form = model.state.value.form!!
        assertEquals("work:995006:chapter:new", form.recoveryTarget()); assertEquals("AO3_Reader", model.account)
        assertEquals(listOf("content", "summary", "notes", "endnotes"), ChapterFormText.entries.map { it.field })
        for (field in ChapterFormText.entries) assertEquals("<p>${field.field} &amp; 星</p>\n", field.text(form))
        assertEquals("13", form.position); assertEquals("12", chapterAfterText(form.position))
        assertEquals("17", form.wipLength); assertEquals("Tide · chapter 13", chapterSubtitle("Tide", form))
        assertEquals(1, setup.client.gets.size); assertEquals(0, setup.client.posts)
        model.close(); model.title("late"); assertEquals(form, model.state.value.form)
    }

    @Test fun publicationAndLastControlsChangeOnlyTheirOwnFieldsAndNoWorkTotalIsWritten() = runTest {
        val setup = workFormSetup()
        setup.client.body = workFixture("ao3_demo_chapter_995006_posted")
        val model = WritingChapterFormState(995006, 12302, 2, setup.repository, setup.auth, today = { LocalDate.of(2026, 10, 9) }, writes = setup.writes)
        model.load()
        val original = model.state.value.form!!
        model.lastChapter(true)
        assertEquals(original, model.state.value.form); assertTrue(model.state.value.isLastChapter)
        model.dateEnabled(false)
        assertEquals("", model.state.value.form!!.publishedYear)
        model.dateEnabled(true)
        assertEquals("9", model.state.value.form!!.publishedDay)
        model.date(LocalDate.of(2030, 3, 7)) // iOS chapter date has no work-date bounds.
        assertEquals(LocalDate.of(2030, 3, 7), model.state.value.form!!.publicationDate())
        assertEquals(original.position, model.state.value.form!!.position); assertEquals(original.wipLength, model.state.value.form!!.wipLength)
        assertEquals(1, setup.client.gets.size); assertEquals(0, setup.client.posts)
    }

    @Test fun failedOpeningIsRememberedAndExplicitRetryMakesExactlyOneMoreRead() = runTest {
        val setup = workFormSetup()
        setup.client.failure = AO3Error.Forbidden
        val model = WritingChapterFormState(995006, null, null, setup.repository, setup.auth, writes = setup.writes)
        model.load(); model.load()
        assertEquals(1, setup.client.gets.size)
        assertEquals(workFormFailure(AO3Error.Forbidden), model.state.value.failure)
        setup.client.failure = null; setup.client.body = workFixture("ao3_demo_chapter_995006_new")
        model.load(retry = true); assertEquals(2, setup.client.gets.size); assertNotNull(model.state.value.form)
    }

    @Test fun thrownReadFailureIsRememberedAndExplicitRetryIsAvailable() = runTest {
        val setup = workFormSetup()
        setup.client.beforeResponse = { throw java.io.IOException("local offline") }
        val model = WritingChapterFormState(995006, null, null, setup.repository, setup.auth, writes = setup.writes)
        model.load(); model.load()
        assertEquals(1, setup.client.gets.size); assertFalse(model.state.value.loading)
        assertEquals("Couldn't reach AO3. Check your connection and try again.", model.state.value.failure)
        setup.client.beforeResponse = {}; setup.client.body = workFixture("ao3_demo_chapter_995006_new")
        model.load(retry = true)
        assertEquals(2, setup.client.gets.size); assertNotNull(model.state.value.form)
    }

    @Test fun positionAndChapterNameAreIosWordsAndDraftWorkHasNoChapterEntry() = runTest {
        assertEquals("bad", chapterPosition("bad")); assertEquals("0", chapterAfterText("1")); assertEquals("1", chapterPosition("0"))
        assertEquals("-1", chapterPosition("-1")); assertNull(chapterNumber("0"))
        val setup = workFormSetup(); val parent = setup.model(995001).also { it.load() }
        assertNull(parent.chapterModel(null, null))
        val form = AO3ChapterFormParser().parse(workFixture("ao3_demo_chapter_995006_posted"), AO3ChapterUrls.form(995006, 12302))
        assertEquals("Chapter 2: Second Tide & 星", chapterDeleteName(form))
        assertEquals("Chapter 2", chapterDeleteName(form.copy(title = "  ")))
        assertEquals("this chapter", chapterDeleteName(form.copy(position = "?", title = "")))
    }
}
