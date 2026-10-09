package io.github.cidy02.kudos.writing

import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.writing.*
import kotlinx.coroutines.test.runTest
import org.jsoup.Jsoup
import org.junit.Assert.*
import org.junit.Test
import java.time.LocalDate

class WritingChapterRefreshTest {
    @Test fun confirmedRefreshReadsOnceAndPreservesUnsavedWorkFieldsButReplacesChapterOneAndTotals() = runTest {
        val setup = workFormSetup(); val parent = setup.model(995006).also { it.load() }
        parent.title("Unsaved work title"); parent.checkpoint(WorkFormText.Summary, "Unsaved work summary")
        val before = parent.state.value.form!!
        val doc = Jsoup.parse(workFixture("ao3_demo_work_posted_edit"))
        doc.selectFirst("[name='work[wip_length]']")!!.attr("value", "2")
        doc.selectFirst("[name='work[chapter_attributes][published_at(1i)]']")!!.select("option").forEach {
            if (it.attr("value") == "2026") it.attr("selected", "selected") else it.removeAttr("selected")
        }
        setup.client.body = doc.outerHtml()
        parent.chapterSaved(); parent.refreshPublication(); parent.refreshPublication()
        val after = parent.state.value.form!!
        assertEquals(before.title, after.title); assertEquals(before.summary, after.summary)
        assertEquals(before.rating, after.rating); assertEquals(before.collectionNames, after.collectionNames)
        assertEquals("2", after.chapterTotal)
        assertEquals("2026", after.parameters(AO3WorkSubmitAction.Update).first { it.first == AO3WorkFormField.chapterPublishedYear }.second)
        assertFalse(parent.state.value.publicationNeedRefresh); assertEquals(2, setup.client.gets.size); assertEquals(0, setup.client.posts)
    }

    @Test fun refreshFailureRemembersAttemptBlocksSaveAndExplicitReloadReadsOnce() = runTest {
        val setup = workFormSetup(); val parent = setup.model(995006).also { it.load() }
        val form = parent.state.value.form
        setup.client.failure = AO3Error.Forbidden
        parent.chapterSaved(); parent.refreshPublication(); parent.refreshPublication(); parent.save()
        assertEquals(2, setup.client.gets.size); assertEquals(0, setup.client.posts)
        assertEquals(form, parent.state.value.form); assertTrue(parent.state.value.publicationNeedRefresh)
        assertEquals("Reload chapter totals before saving this work. " + workFormFailure(AO3Error.Forbidden), parent.state.value.saveError)
        setup.client.failure = null; parent.refreshPublication(retry = true)
        assertEquals(3, setup.client.gets.size); assertFalse(parent.state.value.publicationNeedRefresh)
    }

    @Test fun refreshKeepsUnsavedPublicationDateAndDropsTextAO3StoppedServing() = runTest {
        val setup = workFormSetup()
        val initial = workFixture("ao3_demo_work_draft_edit").replace("save_button", "update_button")
        setup.client.body = initial
        val parent = setup.model(995001).also { it.load() }
        parent.publicationDate(LocalDate.of(2024, 3, 7)); parent.title("Unsaved")
        val fresh = Jsoup.parse(initial)
        fresh.select("textarea[name='work[chapter_attributes][content]']").remove()
        fresh.selectFirst("[name='work[chapter_attributes][title]']")!!.attr("value", "Changed chapter one")
        setup.client.body = fresh.outerHtml()
        parent.chapterSaved(); parent.refreshPublication()
        val form = parent.state.value.form!!
        assertEquals("2024", form.chapter!!.publishedYear); assertEquals("3", form.chapter.publishedMonth); assertEquals("7", form.chapter.publishedDay)
        assertEquals("Changed chapter one", form.chapter.title); assertEquals("Unsaved", form.title)
        assertFalse(form.chapter.contentServed)
        assertTrue(form.parameters(AO3WorkSubmitAction.Update).none { it.first == AO3WorkFormField.chapterContent })
    }
}
