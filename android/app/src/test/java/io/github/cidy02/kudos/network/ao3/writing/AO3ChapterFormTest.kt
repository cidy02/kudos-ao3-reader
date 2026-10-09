package io.github.cidy02.kudos.network.ao3.writing

import io.github.cidy02.kudos.network.ao3.account.AO3CollectionFields
import org.jsoup.Jsoup
import org.junit.Assert.*
import org.junit.Test

class AO3ChapterFormTest {
    @Test fun parsesEveryOriginalFixtureAndKeepsAllControlsIndependently() {
        for (work in listOf(995006L, 995001L)) for (kind in listOf("new", "draft", "posted", "oneshot")) {
            val html = workFixture("ao3_demo_chapter_${work}_$kind")
            val form = AO3ChapterFormParser().parse(html, AO3ChapterUrls.form(work, null))
            assertEquals(work, form.workID)
            assertEquals(kind == "new", form.chapterID == null)
            assertEquals(kind in listOf("new", "draft"), form.isDraft)
            assertEquals(kind != "oneshot", form.includePosition)
            assertEquals("2026", form.publishedYear); assertEquals("10", form.publishedMonth); assertEquals("5", form.publishedDay)
            assertEquals(listOf("101"), form.creators.selectedPseudIDs)
            assertEquals(listOf("101", "202"), form.creators.availablePseuds.map { it.value })
            assertEquals("<p>The lantern drifted past the mill. 星 &amp; water.</p>\n<p>Mira followed its light.</p>", form.content)
            assertEquals(2, form.servedControls.count { it.name == "future[state][]" })
            assertEquals(listOf("outside"), form.servedControls.last().values)
        }
    }

    @Test fun untouchedModeledFieldsMatchBrowserExceptSubmitLabelAndReplayIsExact() {
        for (work in listOf(995006L, 995001L)) for (kind in listOf("new", "draft", "posted", "oneshot")) {
            val html = workFixture("ao3_demo_chapter_${work}_$kind")
            val form = AO3ChapterFormParser().parse(html, AO3ChapterUrls.form(work, null))
            val submit = if (form.posts) AO3WorkSubmitAction.SaveDraft else AO3WorkSubmitAction.Update
            val ios = literalChapterFields(form, submit)
            assertEquals(ios, AO3ChapterFormEncoder.iosParameters(form, submit))
            val names = ios.map { it.first }.toSet()
            val browser = browserControls(html.replace("chapter-form", "work-form"), submit)
            val encoded = form.parameters(submit)
            val modeled = encoded.filter { it.first in names }
            assertEquals(browser.filter { it.first in names && it.first != submit.fieldName }, modeled.filter { it.first != submit.fieldName })
            assertEquals(listOf(submit.fieldName to "1"), modeled.filter { it.first == submit.fieldName })
            assertEquals(browser.filterNot { it.first in names }, encoded.filterNot { it.first in names })
            assertTrue(encoded.filterNot { it.first in names }.none { it.first in modeled.map { pair -> pair.first } })
        }
    }

    @Test fun everyEditedFieldFollowsIosBranchesAndAbsentOrDisabledFieldsAreNeverSent() {
        val html = workFixture("ao3_demo_chapter_995006_draft")
        val original = AO3ChapterFormParser().parse(html, AO3ChapterUrls.form(995006, 12302))
        val changed = original.copy(title = "  Title & 星  ", position = "13", wipLength = "19", summary = "", notes = "\n ",
            endnotes = "<p>end</p>", content = "<p>changed</p>", publishedYear = "2024", publishedMonth = "3", publishedDay = "7",
            creators = original.creators.copy(selectedPseudIDs = listOf("202", "101")))
        assertEquals(literalChapterFields(changed, AO3WorkSubmitAction.SaveDraft), AO3ChapterFormEncoder.iosParameters(changed, AO3WorkSubmitAction.SaveDraft))
        val doc = Jsoup.parse(html)
        doc.select("textarea[name='chapter[content]'], input[name='chapter[position]']").remove()
        doc.select("textarea[name='chapter[summary]']").attr("disabled", "disabled")
        val stripped = AO3ChapterFormParser().parse(doc.outerHtml(), AO3ChapterUrls.form(995006, 12302)).copy(content = "never send", summary = "never send")
        assertTrue(stripped.parameters(AO3WorkSubmitAction.SaveDraft).none { it.first in listOf(AO3ChapterField.content, AO3ChapterField.position, AO3ChapterField.summary) })
        assertTrue(stripped.parameters(AO3WorkSubmitAction.Post).none { it.first == "post_button" })
        val blank = original.copy(position = "", wipLength = "", publishedYear = "", creators = original.creators.copy(selectedPseudIDs = emptyList()))
        val ios = AO3ChapterFormEncoder.iosParameters(blank, AO3WorkSubmitAction.SaveDraft)
        assertTrue(ios.none { it.first in listOf(AO3ChapterField.position, AO3ChapterField.total, AO3ChapterField.year, AO3ChapterField.authorIDs) })
        // Omitted branches replay served values, as 3bb specifies (not an invented clearing rule).
        assertEquals(listOf(AO3ChapterField.year to "2026"), blank.parameters(AO3WorkSubmitAction.SaveDraft).filter { it.first == AO3ChapterField.year })
    }

    @Test fun theTokenGoesInTheBodyEvenWhenOnlyTheMetaTagCarriesIt() {
        val whole = workFixture("ao3_demo_chapter_995006_draft")
        val html = whole.replace("<input type=\"hidden\" name=\"authenticity_token\" value=\"demo-chapter-995006==\">", "")
        assertTrue("name=\"authenticity_token\"" !in html)
        val body = AO3ChapterFormParser().parse(html, AO3ChapterUrls.form(995006, 12311)).parameters(AO3WorkSubmitAction.SaveDraft)
        assertEquals("authenticity_token" to "demo-chapter-995006==", body.first())
        assertEquals(1, body.count { it.first == "authenticity_token" })
        assertTrue(body.any { it.first == "_method" && it.second == "patch" })
        assertEquals(AO3ChapterFormParser().parse(whole, AO3ChapterUrls.form(995006, 12311)).parameters(AO3WorkSubmitAction.SaveDraft).toSet(), body.toSet())
    }

    @Test fun datesDefaultToFirstOptionTokenPrefersMetaAndUnsafeOrNonChapterFormsFail() {
        val html = workFixture("ao3_demo_chapter_995006_new")
        val doc = Jsoup.parse(html)
        doc.select("option[selected]").removeAttr("selected")
        doc.selectFirst("meta[name=csrf-token]")!!.attr("content", "  meta==  ")
        val form = AO3ChapterFormParser().parse(doc.outerHtml(), AO3ChapterUrls.form(995006, null))
        assertEquals("meta==", form.csrfToken); assertEquals("", form.publishedYear); assertEquals("10", form.publishedMonth)
        for (action in listOf("https://example.invalid/works/995006/chapters", "/works/995006/chapters/new", "/works/995006")) {
            doc.selectFirst("form")!!.attr("action", action)
            assertThrows(AO3WorkFormParseException.InvalidForm::class.java) { AO3ChapterFormParser().parse(doc.outerHtml(), AO3ChapterUrls.form(995006, null)) }
        }
        assertThrows(AO3WorkFormParseException.LoginRequired::class.java) { AO3ChapterFormParser().parse("<form id=new_user action='/users/login'></form>", AO3ChapterUrls.form(995006, null)) }
    }

    @Test fun previewAdoptsOnlyConfirmedSameWorkDraftIdentityAndNeverInventsControls() {
        val form = AO3ChapterFormParser().parse(workFixture("ao3_demo_chapter_995006_new"), AO3ChapterUrls.form(995006, null))
        val html = "<meta name=csrf-token content='fresh=='><main id=main><div id=previewpane><h3 class=title>New Tide</h3><div class=userstuff><p>Kept <img src='https://example.invalid/image'>text</p></div></div><form method=post action='/works/995006/chapters/12303'><input name=_method value=patch><input name=edit_button type=submit><input name=post_button type=submit></form></main>"
        val preview = AO3ChapterFormParser().preview(html, AO3ChapterUrls.form(995006, null))
        val draft = form.adopting(preview)
        assertEquals(12303L, draft.chapterID); assertEquals("patch", draft.methodOverride); assertEquals("fresh==", draft.csrfToken)
        assertEquals(form.content, draft.content); assertTrue(draft.isDraft)
        assertEquals(listOf("post_button" to "1"), draft.parameters(AO3WorkSubmitAction.Post).filter { it.first == "post_button" })
        assertTrue(preview.blocks.none { it.text.contains("img") })
        assertEquals(AO3CollectionFields.UNCONFIRMED, assertThrows(IllegalArgumentException::class.java) { form.adopting(preview.copy(workID = 995001)) }.message)
        assertThrows(AO3WorkFormParseException.InvalidForm::class.java) { AO3ChapterFormParser().preview("<main></main>", AO3ChapterUrls.form(995006, null)) }
    }

    @Test fun deleteParsesBothFixturesAndRejectsAnotherChapter() {
        for ((work, chapter) in listOf(995006L to 12302L, 995001L to 12311L)) {
            val parsed = AO3ChapterFormParser().deleteForm(workFixture("ao3_demo_chapter_${work}_delete"), AO3ChapterUrls.confirmDelete(work, chapter), work, chapter)
            assertEquals(AO3ChapterUrls.chapter(work, chapter), parsed.actionUrl)
            assertEquals("demo-delete-$work==", parsed.csrfToken); assertEquals("delete", parsed.methodOverride)
            assertThrows(AO3WorkFormParseException.InvalidForm::class.java) { AO3ChapterFormParser().deleteForm(workFixture("ao3_demo_chapter_${work}_delete"), AO3ChapterUrls.confirmDelete(work, chapter), work, chapter + 1) }
        }
    }
}

/** Literal iOS ordering/conditions, independent of the production encoder. */
internal fun literalChapterFields(form: AO3ChapterForm, submit: AO3WorkSubmitAction): List<Pair<String, String>> = buildList {
    add("authenticity_token" to form.csrfToken)
    if (!form.methodOverride.isNullOrEmpty()) add("_method" to requireNotNull(form.methodOverride))
    add("chapter[title]" to form.title)
    if (form.includePosition && form.position.isNotEmpty()) add("chapter[position]" to form.position)
    if (form.wipLength.isNotEmpty()) add("chapter[wip_length]" to form.wipLength)
    add("chapter[summary]" to form.summary); add("chapter[notes]" to form.notes)
    add("chapter[endnotes]" to form.endnotes); add("chapter[content]" to form.content)
    if (form.publishedYear.isNotEmpty()) {
        add("chapter[published_at(1i)]" to form.publishedYear); add("chapter[published_at(2i)]" to form.publishedMonth); add("chapter[published_at(3i)]" to form.publishedDay)
    }
    form.creators.selectedPseudIDs.forEach { add("chapter[author_attributes][ids][]" to it) }
    add(submit.fieldName to "1")
}
