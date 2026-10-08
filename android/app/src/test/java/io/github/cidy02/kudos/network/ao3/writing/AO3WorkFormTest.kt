package io.github.cidy02.kudos.network.ao3.writing

import okhttp3.FormBody
import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.time.LocalDate

class AO3WorkFormTest {
    private val parser = AO3WorkFormParser()
    private val fixtures = listOf("ao3_work_new_draft", "ao3_demo_work_draft_edit", "ao3_demo_work_posted_edit")

    @Test fun untouchedIosFieldsEqualBrowserControlsInMeaningForEveryFixtureAndSubmit() {
        for (fixture in fixtures) for (submit in AO3WorkSubmitAction.entries) {
            val html = withSubmitter(workFixture(fixture), submit)
            val form = parser.parse(html)
            val modeled = AO3WorkFormEncoder.iosParameters(form, submit)
            val browser = browserControls(html, submit)
            for ((name, actual) in modeled.groupBy({ it.first }, { it.second })) {
                val expected = browser.filter { it.first == name }.map { it.second }
                assertEquals("$fixture / $submit / $name", meaning(name, expected, form), meaning(name, actual, form))
            }
        }
    }

    @Test fun untouchedRemainingFieldsEqualBrowserControlsExactlyForEveryFixtureAndSubmit() {
        for (fixture in fixtures) for (submit in AO3WorkSubmitAction.entries) {
            val html = withSubmitter(workFixture(fixture), submit)
            val form = parser.parse(html)
            val modeled = AO3WorkFormEncoder.iosParameters(form, submit)
            val names = modeled.map { it.first }.toSet()
            val carried = AO3WorkFormEncoder.carriedParameters(form, submit)
            val browser = browserControls(html, submit).filterNot { it.first in names }
            for (name in (browser + carried).map { it.first }.distinct()) {
                assertEquals("$fixture / $submit / $name", browser.filter { it.first == name }, carried.filter { it.first == name })
            }
            assertEquals("$fixture / $submit / carry order", browser, carried)
            assertTrue("$fixture / $submit / both branches emitted a name", names.intersect(carried.map { it.first }.toSet()).isEmpty())
            assertEquals(modeled + carried, form.parameters(submit))
        }
    }

    // Exactly the three normalization rules Claude authorized. No generic blank,
    // whitespace, sorting, deduplication, date, select or HTML normalization.
    @Test fun aServedTagPaddedWithAZeroWidthSpaceIsTheSameTagAsTheOneTypedInTheEditor() {
        // Foundation's whitespace set, which iOS trims with, holds U+200B and U+0085; Kotlin's does not.
        assertEquals(listOf("Demo Fandom", "Second"), splitWorkList("\u200BDemo Fandom\u200B,\u0085Second "))
        assertEquals(trimWritingTag(" Demo Fandom\u200B"), splitWorkList("\u200BDemo Fandom").single())
    }

    private fun meaning(name: String, values: List<String>, form: AO3WorkForm): List<String> = when {
        name in commaLists -> values.map { it.split(',').joinToString(",") { part -> part.trim() } }
        name in AO3WorkSubmitAction.entries.map { it.fieldName } -> if (values.isEmpty()) emptyList() else listOf(name)
        form.servedControls.any { it.name == name && it.type == "checkbox" } && !name.endsWith("[]") -> values.takeLast(1)
        else -> values
    }

    @Test fun tokenPrecedenceAndWhitespaceFollowIosWhileRawHiddenTokensStayIntact() {
        val html = workFixture("ao3_work_new_draft").replace("content=\"draft-csrf==\"", "content=\"  meta-token==  \"")
        val form = parser.parse(html)
        assertEquals("meta-token==", form.csrfToken)
        assertEquals(listOf("draft-csrf=="), form.servedControls.single { it.name == "authenticity_token" }.values)
        assertEquals(listOf("meta-token=="), values(form.parameters(AO3WorkSubmitAction.SaveDraft), "authenticity_token"))
        val noMeta = Jsoup.parse(html).apply { select("meta[name=csrf-token]").remove() }.outerHtml()
        assertEquals("draft-csrf==", parser.parse(noMeta).csrfToken)
    }

    /**
     * A work with more than one chapter: AO3's edit page serves chapter 1's title and no text
     * box, and `works#update` assigns what it is sent to chapter 1. An empty text was refused
     * and took the whole save with it (audit A4-1).
     */
    @Test fun aWorkWithSeveralChaptersSendsNoChapterText() {
        val titled = workFixture("ao3_demo_work_posted_edit").replace("</form>",
            """<input type="text" name="work[chapter_attributes][title]" value="Prologue"></form>""")
        val form = parser.parse(titled)
        assertEquals("Prologue", form.chapter?.title)
        assertEquals(false, form.chapter?.contentServed)
        val sent = form.parameters(AO3WorkSubmitAction.Update)
        assertEquals(listOf("Prologue"), sent.filter { it.first == AO3WorkFormField.chapterTitle }.map { it.second })
        assertTrue(sent.none { it.first == AO3WorkFormField.chapterContent })
        // A draft in that state is not missing its text: there is no box to fill.
        assertFalse("Work Text" in form.copy(isPosted = false).missingRequiredFields())

        val single = parser.parse(workFixture("ao3_demo_work_draft_edit"))
        assertEquals(true, single.chapter?.contentServed)
        assertEquals(1, single.parameters(AO3WorkSubmitAction.SaveDraft).count { it.first == AO3WorkFormField.chapterContent })
    }

    @Test fun originalFillerFixturesCoverTheAccountDraftAndPostedAssociations() {
        val draft = parser.parse(workFixture("ao3_demo_work_draft_edit"))
        assertEquals(995001L, draft.workID)
        assertEquals("Lanterns Above the Mill", draft.title)
        assertTrue(draft.isDraft); assertEquals(AO3WorkFormKind.Draft, draft.kind)
        assertTrue(workFixture("ao3_demo_drafts_1").contains("work_995001"))
        val posted = parser.parse(workFixture("ao3_demo_work_posted_edit"))
        assertEquals(995006L, posted.workID); assertTrue(posted.isPosted)
        assertEquals(2, posted.chaptersPosted); assertEquals("5", posted.chapterTotal)
        assertEquals(listOf("lantern_exchange", "star_atlas"), posted.collectionNames)
        assertEquals(listOf("PaperNavigator"), posted.gifts)
        assertEquals(listOf(AO3CurrentSeries(77, "Lantern Voyages", 5501)), posted.currentSeries)
        assertTrue(posted.backdate); assertTrue(posted.moderatedCommenting)
        assertEquals("55", posted.workSkinID)
        assertEquals(listOf("303", "404"), values(posted.parameters(AO3WorkSubmitAction.Update), "work[author_attributes][coauthors][]"))
        assertEquals("A Small \"North\" & 南", posted.parentWork.title)
        assertNull(posted.chapter)
        assertEquals(listOf("2019"), values(posted.parameters(AO3WorkSubmitAction.Update), AO3WorkFormField.chapterPublishedYear))
        assertEquals(listOf("Maps", "\"Wait & See\"", "夜の約束"), posted.additionalTags)
    }

    @Test fun everyControlAndOptionIsKeptEvenWhenNotSuccessfulOrUnderstood() {
        val extra = """
            <input type="hidden" name="future[]" value="a&amp;b">
            <input type="hidden" name="future[]" value="二">
            <input type="hidden" name="revision" value="first">
            <input type="hidden" name="revision" value="second">
            <input name="future_text" value="  &quot;留&quot; &amp; keep  ">
            <textarea name="future_prose">  &lt;p&gt;α &amp; β&lt;/p&gt;
second line  </textarea>
            <select name="future_choices[]" multiple>
              <option value="a" selected>A</option><option value="b" selected>B</option><option value="c">C</option>
            </select>
            <input type="checkbox" name="future_check" value="kept" checked>
            <input type="checkbox" name="future_off" value="off">
            <input name="disabled" value="still modeled" disabled>
            <input value="unnamed">
        """.trimIndent()
        val html = inject(workFixture("ao3_work_new_draft"), extra)
        val form = parser.parse(html)
        val raw = form.servedControls
        assertEquals(listOf("first", "second"), raw.filter { it.name == "revision" }.flatMap { it.values })
        assertEquals("off", raw.single { it.name == "future_off" }.values.single())
        assertEquals("still modeled", raw.single { it.name == "disabled" }.values.single())
        assertTrue(raw.any { it.name.isEmpty() && it.values == listOf("unnamed") })
        assertEquals(3, raw.single { it.name == "future_choices[]" }.options.size)
        val encoded = form.parameters(AO3WorkSubmitAction.SaveDraft)
        val unmodeled = encoded.filter { it.first.startsWith("future") || it.first == "revision" }
        assertEquals(browserControls(html, AO3WorkSubmitAction.SaveDraft).filter {
            it.first.startsWith("future") || it.first == "revision"
        }, unmodeled)
        assertFalse(encoded.any { it.first == "disabled" || it.first.isEmpty() || it.first == "future_off" })
    }

    @Test fun browserSemanticsKeepUnknownHiddenTwinsRadiosSelectDefaultsAndDisabledLegend() {
        val extra = """
            <input type="hidden" name="future_boolean" value="0"><input type="checkbox" name="future_boolean" value="1" checked>
            <input type="radio" name="future_radio" value="a"><input type="radio" name="future_radio" value="b" checked>
            <input type="radio" name="future_duplicate" value="first" checked><input type="radio" name="future_duplicate" value="last" checked>
            <select name="future_default"><option>無名</option><option value="z">Z</option></select>
            <select name="future_listbox" size="3"><option value="a">A</option><option value="b">B</option></select>
            <select name="future_many[]" multiple><option selected value="one">One</option><optgroup disabled><option selected value="skip">Skip</option></optgroup><option selected value="two">Two</option></select>
            <fieldset disabled><legend><input name="future_legend" value="keep"></legend><input name="future_disabled" value="skip"></fieldset>
            <button type="button" name="future_button" value="skip">Not submit</button>
        """
        val html = inject(workFixture("ao3_work_new_draft"), extra)
        val form = parser.parse(html)
        val carried = AO3WorkFormEncoder.carriedParameters(form, AO3WorkSubmitAction.Preview)
        assertEquals(browserControls(html, AO3WorkSubmitAction.Preview).filter { it.first.startsWith("future") },
            carried.filter { it.first.startsWith("future") })
        assertEquals(listOf("0", "1"), values(carried, "future_boolean"))
        assertEquals(listOf("無名"), values(carried, "future_default"))
        assertEquals(listOf("one", "two"), values(carried, "future_many[]"))
        assertEquals(listOf("keep"), values(carried, "future_legend"))
        assertEquals(listOf("last"), values(carried, "future_duplicate"))
        assertTrue(values(carried, "future_listbox").isEmpty())
        assertEquals(2, form.servedControls.count { it.name == "future_duplicate" && "checked" in it.attributes })
    }

    @Test fun externallyAssociatedControlsAreRetainedInDocumentOrder() {
        val html = "<input form=work-form name=before value=first>" +
            workFixture("ao3_work_new_draft") + "<input form=work-form name=after value=last><input name=unrelated value=skip>"
        val form = parser.parse(html)
        assertEquals("before", form.servedControls.first().name)
        assertEquals("after", form.servedControls.last().name)
        assertFalse(form.servedControls.any { it.name == "unrelated" })
    }

    @Test fun changedTextLongTextSingleChoicesListsAndRepeatedSelectionsUseIosValues() {
        val original = parser.parse(workFixture("ao3_demo_work_draft_edit"))
        val text = "  <p>α & β \"keep\"</p>\n<p>夜</p>  "
        val form = original.copy(title = "New & \"Title\"", summary = text, notes = text, endnotes = text,
            rating = "Mature", languageID = "3", workSkinID = "66", commentPermissions = "disable_all",
            warnings = listOf("Major Character Death", "Rape/Non-Con"), categories = listOf("F/F", "Other"),
            fandoms = listOf("  星  ", "Maps & Mills"), relationships = listOf("a/b", "c/d"),
            characters = listOf("\"Mira\"", "Sol"), additionalTags = listOf("One", "Two"),
            collectionNames = listOf("other_collection"), gifts = listOf("OtherGiftee"),
            chapter = original.chapter!!.copy(title = "Second title", summary = text, content = text))
        val pairs = form.parameters(AO3WorkSubmitAction.SaveDraft)
        val expected = mapOf(AO3WorkFormField.title to listOf("New & \"Title\""),
            AO3WorkFormField.summary to listOf(text), AO3WorkFormField.notes to listOf(text), AO3WorkFormField.endnotes to listOf(text),
            AO3WorkFormField.rating to listOf("Mature"), AO3WorkFormField.languageID to listOf("3"),
            AO3WorkFormField.workSkinID to listOf("66"), AO3WorkFormField.commentPermissions to listOf("disable_all"),
            AO3WorkFormField.warnings to form.warnings, AO3WorkFormField.categories to form.categories,
            AO3WorkFormField.fandoms to listOf("星, Maps & Mills"), AO3WorkFormField.relationships to listOf("a/b, c/d"),
            AO3WorkFormField.characters to listOf("\"Mira\", Sol"), AO3WorkFormField.additionalTags to listOf("One, Two"),
            AO3WorkFormField.collectionNames to listOf("other_collection"), AO3WorkFormField.recipients to listOf("OtherGiftee"),
            AO3WorkFormField.chapterTitle to listOf("Second title"), AO3WorkFormField.chapterSummary to listOf(text),
            AO3WorkFormField.chapterContent to listOf(text))
        expected.forEach { (field, value) -> assertEquals(field, value, values(pairs, field)) }
        val body = FormBody.Builder().apply { pairs.forEach { (name, value) -> add(name, value) } }.build()
        for (i in pairs.indices) {
            assertEquals("encoded name $i", pairs[i].first, body.name(i))
            assertEquals("encoded value ${pairs[i].first}", pairs[i].second, body.value(i))
        }
        assertEquals(original.servedControls, form.servedControls)
    }

    @Test fun checkboxesReplaceTheirHiddenTwinsAndChangesNeverReplayOldCheckedValues() {
        val original = parser.parse(workFixture("ao3_demo_work_posted_edit"))
        for (on in listOf(false, true)) {
            val form = original.copy(backdate = on, restricted = on, moderatedCommenting = on,
                anonymous = on, collectionInbox = on, parentWork = original.parentWork.copy(isTranslation = on))
            val pairs = form.parameters(AO3WorkSubmitAction.Update)
            for (name in listOf(AO3WorkFormField.backdate, AO3WorkFormField.restricted,
                AO3WorkFormField.moderatedCommenting, AO3WorkFormField.anonymous, AO3WorkFormField.collectionInbox,
                AO3WorkFormField.parentTranslation)) assertEquals(name, listOf(if (on) "1" else "0"), values(pairs, name))
        }
    }

    @Test fun changedHiddenCreatorsSeriesParentAndDatesUseTheIosBranch() {
        val original = parser.parse(workFixture("ao3_demo_work_draft_edit"))
        val form = original.copy(csrfToken = "fresh & token==", methodOverride = "put",
            creators = original.creators.copy(selectedPseudIDs = listOf("202", "101"), coauthorByline = "Quiet & 星"),
            series = original.series.map { it.copy(isSelected = it.seriesID == 88L) },
            parentWork = AO3ParentWorkDraft("https://example.test/inspiration", "New & 星", "Map Keeper", "3", true),
            chapter = original.chapter!!.copy(publishedYear = "2019", publishedMonth = "11", publishedDay = "5"))
        val pairs = form.parameters(AO3WorkSubmitAction.SaveDraft)
        val expected = mapOf(AO3WorkFormField.authenticityToken to listOf("fresh & token=="), AO3WorkFormField.methodOverride to listOf("put"),
            AO3WorkFormField.authorIDs to listOf("202", "101"), AO3WorkFormField.authorByline to listOf("Quiet & 星"),
            AO3WorkFormField.seriesID to listOf("88"), AO3WorkFormField.parentURL to listOf("https://example.test/inspiration"),
            AO3WorkFormField.parentTitle to listOf("New & 星"), AO3WorkFormField.parentAuthor to listOf("Map Keeper"),
            AO3WorkFormField.parentLanguageID to listOf("3"), AO3WorkFormField.parentTranslation to listOf("1"),
            AO3WorkFormField.chapterPublishedYear to listOf("2019"), AO3WorkFormField.chapterPublishedMonth to listOf("11"),
            AO3WorkFormField.chapterPublishedDay to listOf("5"))
        expected.forEach { (name, value) -> assertEquals(name, value, values(pairs, name)) }
        val newSeries = form.copy(series = form.series.map { it.copy(isSelected = false) }, newSeriesTitle = "  New Series  ")
        val modeled = AO3WorkFormEncoder.iosParameters(newSeries, AO3WorkSubmitAction.SaveDraft)
        assertEquals(listOf("New Series"), values(modeled, AO3WorkFormField.seriesTitle))
        assertTrue(values(modeled, AO3WorkFormField.seriesID).isEmpty())
    }

    @Test fun unknownVisibleCollectionsKeepTheirServedOptionsWithoutAnotherRead() {
        val html = inject(workFixture("ao3_work_new_draft"), """
            <select name="work[collections_to_add]" multiple>
              <option selected value="ink_atlas">Ink Atlas &amp; 星</option><option value="mill_exchange">Mill Exchange</option>
            </select>
            <input type=hidden name="work[collections_to_remove][]" value="old_atlas">
            <input type=hidden name="work[collections_to_remove][]" value="old_mill">
            <input name="work[pseuds_to_add]" value="QuietNavigator">
        """)
        val form = parser.parse(html)
        val offers = form.servedControls.single { it.name == "work[collections_to_add]" }.options
        assertEquals(listOf("ink_atlas", "mill_exchange"), offers.map { it.value })
        assertEquals("Ink Atlas & 星", offers.first().text)
        val pairs = form.parameters(AO3WorkSubmitAction.SaveDraft)
        assertEquals(listOf("ink_atlas"), values(pairs, "work[collections_to_add]"))
        assertEquals(listOf("old_atlas", "old_mill"), values(pairs, "work[collections_to_remove][]"))
        assertEquals(listOf("QuietNavigator"), values(pairs, "work[pseuds_to_add]"))
    }

    @Test fun clearingChoicesEmitsOneBlankAndHiddenArrayTwinsNeverDuplicateSelections() {
        val html = inject(workFixture("ao3_demo_work_draft_edit"),
            "<input type=hidden name='work[archive_warning_strings][]' value=''><input type=hidden name='work[category_strings][]' value=''>")
        val form = parser.parse(html)
        val unchanged = form.parameters(AO3WorkSubmitAction.SaveDraft)
        assertEquals(form.warnings, values(unchanged, AO3WorkFormField.warnings))
        assertEquals(form.categories, values(unchanged, AO3WorkFormField.categories))
        val cleared = form.copy(warnings = emptyList(), categories = emptyList()).parameters(AO3WorkSubmitAction.SaveDraft)
        assertEquals(listOf(""), values(cleared, AO3WorkFormField.warnings))
        assertEquals(listOf(""), values(cleared, AO3WorkFormField.categories))
    }

    @Test fun emptyValueBranchesMatchIosAndOmittedNamesAreCarriedAsServed() {
        val form = parser.parse(workFixture("ao3_demo_work_draft_edit")).copy(rating = "", commentPermissions = "",
            creators = AO3CreatorDraft(), languageID = "", summary = "", notes = "", endnotes = "",
            fandoms = emptyList(), relationships = emptyList(), characters = emptyList(), additionalTags = emptyList(),
            gifts = emptyList(), collectionNames = emptyList(), collections = emptyList(), chapterTotal = "", anonymous = null, collectionInbox = null,
            chapter = AO3WorkChapterDraft(), workSkinID = "")
        val modeled = AO3WorkFormEncoder.iosParameters(form, AO3WorkSubmitAction.SaveDraft)
        for (name in listOf(AO3WorkFormField.rating, AO3WorkFormField.commentPermissions, AO3WorkFormField.authorIDs,
            AO3WorkFormField.authorByline, AO3WorkFormField.chapterPublishedYear, AO3WorkFormField.chapterPublishedMonth,
            AO3WorkFormField.chapterPublishedDay)) assertTrue(name, values(modeled, name).isEmpty())
        for (name in listOf(AO3WorkFormField.summary, AO3WorkFormField.notes, AO3WorkFormField.endnotes,
            AO3WorkFormField.fandoms, AO3WorkFormField.languageID, AO3WorkFormField.recipients,
            AO3WorkFormField.collectionNames, AO3WorkFormField.wipLength, AO3WorkFormField.workSkinID,
            AO3WorkFormField.chapterTitle, AO3WorkFormField.chapterSummary, AO3WorkFormField.chapterContent)) {
            assertEquals(name, listOf(""), values(modeled, name))
        }
        // Claude's rule 3 applies to names the iOS branch doesn't emit. Keep the
        // served value; this is deliberately stronger preservation than iOS.
        assertEquals(listOf("Teen And Up Audiences"), values(form.parameters(AO3WorkSubmitAction.SaveDraft), AO3WorkFormField.rating))
    }

    @Test fun datePartsUseFirstOptionFallbackAndYearAloneGatesIosDateEmission() {
        val html = workFixture("ao3_demo_work_draft_edit").replace(" selected=\"selected\"", "")
        val form = parser.parse(html)
        assertEquals("2026", form.chapter!!.publishedYear)
        assertEquals("3", form.chapter.publishedMonth)
        assertEquals("5", form.chapter.publishedDay)
        assertEquals("", form.rating) // iOS ordinary selects have no first-option fallback
        val modeled = AO3WorkFormEncoder.iosParameters(form.copy(chapter = form.chapter.copy(publishedYear = "2019",
            publishedMonth = "", publishedDay = "")), AO3WorkSubmitAction.SaveDraft)
        assertEquals(listOf("2019"), values(modeled, AO3WorkFormField.chapterPublishedYear))
        assertEquals(listOf(""), values(modeled, AO3WorkFormField.chapterPublishedMonth))
        assertEquals(listOf(""), values(modeled, AO3WorkFormField.chapterPublishedDay))
    }

    @Test fun optionsAreWhateverTheFormServesIncludingFutureLanguagesSkinsPseudsAndSeries() {
        val html = workFixture("ao3_work_new_draft").replace("</select>", "<option value='909'>未来 &amp; More</option></select>")
        val form = parser.parse(html)
        for (options in listOf(form.ratingOptions, form.languageOptions, form.workSkinOptions,
            form.creators.availablePseuds, form.seriesOptions)) {
            assertEquals(AO3FormOption("909", "未来 & More"), options.last())
        }
        assertEquals("未来 & More", form.series.last().title)
    }

    @Test fun loginErrorOverloadAndUnsafeOrUnrelatedFormsFailWithTypedErrors() {
        assertThrows(AO3WorkFormParseException.LoginRequired::class.java) {
            parser.parse("<form id=new_user action='/users/login'><input name='user[login]'></form>")
        }
        assertThrows(AO3WorkFormParseException.Overloaded::class.java) {
            parser.parse("<h1>Archive of Our Own is temporarily overloaded</h1>")
        }
        for (html in listOf("<h1>Error</h1><p>Sorry, page not found</p>",
            "<form action='/works' method=get><input name=query></form>",
            "<form action='/works/123' method=post><input name=_method value=delete></form>",
            workFixture("ao3_work_new_draft").replace("action=\"/works\"", "action=\"https://evil.example/works\""),
            workFixture("ao3_work_new_draft").replace("draft-csrf==", ""))) {
            assertThrows(AO3WorkFormParseException.InvalidForm::class.java) { parser.parse(html) }
        }
        val text = inject(workFixture("ao3_work_new_draft"), "<textarea name=future>AO3 is temporarily overloaded</textarea>")
        assertEquals(AO3WorkFormKind.New, parser.parse(text).kind)
    }

    // iOS AO3WorkFormParsingTests: same case names and original reference assertions.
    @Test fun parsesWorkEditFormGroups() {
        val form = parser.parse(workFixture("ao3_work_edit"))
        assertEquals(AO3WorkFormKind.Edit, form.kind); assertEquals(424242L, form.workID)
        assertTrue(form.actionUrl.endsWith("/works/424242")); assertEquals("patch", form.methodOverride)
        assertEquals("work-csrf-token==", form.csrfToken); assertTrue(form.isPosted); assertFalse(form.isDraft)
        assertEquals("The Weight of Water", form.title); assertEquals("Explicit", form.rating)
        assertEquals(listOf("Choose Not To Use Archive Warnings"), form.warnings)
        assertEquals("Choose Not To Use Archive Warnings", form.warningOptions.first().value)
        assertEquals(listOf("Jujutsu Kaisen", "Haikyuu!!"), form.fandoms); assertEquals("1", form.languageID)
        assertEquals(listOf("F/M", "M/M"), form.categories); assertEquals(6, form.categoryOptions.size)
        assertEquals(listOf("Geto/Gojo", "Hinata/Kageyama"), form.relationships)
        assertEquals(listOf("Gojo Satoru", "Geto Suguru"), form.characters)
        assertEquals(listOf("Hurt/Comfort", "Original Tag That Is New"), form.additionalTags)
        assertEquals(listOf("nanami_week"), form.collectionNames); assertEquals(listOf("giftee"), form.gifts)
        assertTrue(form.series.any { it.seriesID == 77L && it.isSelected }); assertEquals("First Rain", form.parentWork.title)
        assertTrue(form.summary.contains("long walk")); assertEquals("Thanks for reading.", form.notes)
        assertEquals("More later.", form.endnotes); assertEquals("20", form.chapterTotal); assertTrue(form.isChaptered)
        assertFalse(form.restricted); assertTrue(form.moderatedCommenting); assertEquals("disable_anon", form.commentPermissions)
        assertTrue(form.missingRequiredFields().isEmpty())
    }

    @Test fun clearedWorkSkinIsStillPosted() {
        val form = parser.parse(workFixture("ao3_work_edit")).copy(workSkinID = "")
        assertEquals(listOf(""), values(form.parameters(AO3WorkSubmitAction.Update), AO3WorkFormField.workSkinID))
    }

    @Test fun postingAWorkSendsTheWorkFormsOwnPostButton() {
        val html = workFixture("ao3_work_new_draft")
        assertTrue(html.contains("name=\"post_button\"")); assertFalse(html.contains("post_without_preview_button"))
        val form = parser.parse(html)
        assertEquals(listOf("1"), values(form.parameters(AO3WorkSubmitAction.Post), "post_button"))
    }

    @Test fun missingRequiredFieldsNamesWhatPostNeeds() {
        val form = parser.parse(workFixture("ao3_work_new_draft"))
        assertEquals(AO3WorkFormKind.New, form.kind); assertTrue(form.isDraft); assertFalse(form.isPosted)
        for (name in listOf("Title", "Rating", "Archive Warning", "Fandoms", "Language", "Work Text"))
            assertTrue(name, name in form.missingRequiredFields())
    }

    private fun draftWithPublishedDate(): AO3WorkForm {
        val doc = Jsoup.parse(workFixture("ao3_work_new_draft"))
        doc.select("select[name]").filter { it.attr("name").contains("published_at(") }.forEach { it.remove() }
        doc.selectFirst("form#work-form")!!.append("""
            <select name="work[chapter_attributes][published_at(3i)]">
              <option value="6">6</option><option value="7" selected="selected">7</option>
            </select>
            <select name="work[chapter_attributes][published_at(2i)]">
              <option value="2">February</option><option value="3" selected="selected">March</option>
            </select>
            <select name="work[chapter_attributes][published_at(1i)]">
              <option value="2025">2025</option><option value="2024" selected="selected">2024</option>
            </select>
        """)
        return parser.parse(doc.outerHtml())
    }

    @Test fun publicationDateKeepsAO3sUnpaddedFormat() {
        val form = draftWithPublishedDate()
        assertEquals(listOf("2024", "3", "7"), listOf(form.chapter!!.publishedYear, form.chapter.publishedMonth, form.chapter.publishedDay))
        val date = LocalDate.of(2024, 3, 7)
        assertEquals(listOf("2024", "3", "7"), listOf(date.year.toString(), date.monthValue.toString(), date.dayOfMonth.toString()))
    }

    @Test fun backdateOnPostsTheChosenDate() {
        val form = draftWithPublishedDate().let { it.copy(backdate = true,
            chapter = it.chapter!!.copy(publishedYear = "2019", publishedMonth = "11", publishedDay = "5")) }
        val pairs = form.parameters(AO3WorkSubmitAction.SaveDraft)
        assertEquals(listOf("1"), values(pairs, AO3WorkFormField.backdate))
        assertEquals(listOf("2019"), values(pairs, AO3WorkFormField.chapterPublishedYear))
        assertEquals(listOf("11"), values(pairs, AO3WorkFormField.chapterPublishedMonth))
        assertEquals(listOf("5"), values(pairs, AO3WorkFormField.chapterPublishedDay))
    }

    @Test fun backdateOffLeavesTheDateFieldsUntouched() {
        val pairs = draftWithPublishedDate().parameters(AO3WorkSubmitAction.SaveDraft)
        assertEquals(listOf("0"), values(pairs, AO3WorkFormField.backdate))
        assertEquals(listOf("2024"), values(pairs, AO3WorkFormField.chapterPublishedYear))
        assertEquals(listOf("3"), values(pairs, AO3WorkFormField.chapterPublishedMonth))
        assertEquals(listOf("7"), values(pairs, AO3WorkFormField.chapterPublishedDay))
    }

    @Test fun pickingASeriesPostsOnlyThatSeries() {
        val original = parser.parse(workFixture("ao3_work_edit"))
        val form = original.copy(series = original.series.map { it.copy(isSelected = it.seriesID == 88L) })
        assertEquals(listOf("88"), values(form.parameters(AO3WorkSubmitAction.Update), AO3WorkFormField.seriesID))
    }

    @Test fun aWhitespaceOnlySeriesTitleIsNotPosted() {
        val original = parser.parse(workFixture("ao3_work_edit"))
        val form = original.copy(series = original.series.map { it.copy(isSelected = false) }, newSeriesTitle = "   ")
        assertEquals(listOf(""), values(form.parameters(AO3WorkSubmitAction.Update), AO3WorkFormField.seriesTitle))
        assertEquals(listOf("Water"), values(form.copy(newSeriesTitle = "  Water  ").parameters(AO3WorkSubmitAction.Update), AO3WorkFormField.seriesTitle))
    }

    @Test fun theWorkFormReadsItsCurrentSeriesAndPostsNoneOfIt() {
        val html = inject(workFixture("ao3_work_edit").replace("selected=\"selected\" value=\"77\"", "value=\"77\""),
            """<dt>Current Series</dt><dd><ul><li><a href="/series/77">Water</a></li><li><a href="/serial_works/4401">Remove Work From Series</a></li></ul></dd>
            <dd><ul><li><a href="/series/91">Salt</a></li><li><a href="/serial_works/4402">Remove Work From Series</a></li></ul></dd>""")
        val form = parser.parse(html)
        assertEquals(listOf(AO3CurrentSeries(77, "Water", 4401), AO3CurrentSeries(91, "Salt", 4402)), form.currentSeries)
        val pairs = form.parameters(AO3WorkSubmitAction.Update)
        assertEquals(listOf(""), values(pairs, AO3WorkFormField.seriesID))
        assertEquals(listOf(""), values(pairs, AO3WorkFormField.seriesTitle))
        assertFalse(pairs.any { it.first.contains("serial") })
    }

    @Test fun postedFieldKeepsDisplayedChipOrder() {
        val original = parser.parse(workFixture("ao3_work_edit"))
        val pairs = original.copy(relationships = listOf("Zukka", "Zutara", "Kataang")).parameters(AO3WorkSubmitAction.Update)
        assertEquals(listOf("Zukka, Zutara, Kataang"), values(pairs, AO3WorkFormField.relationships))
    }

    @Test fun theCollectionsPickerDecidesWhatIsPosted() {
        val form = parser.parse(workFixture("ao3_work_edit"))
        assertEquals(listOf("nanami_week"), values(form.parameters(AO3WorkSubmitAction.Update), AO3WorkFormField.collectionNames))
        assertEquals(listOf(""), values(form.copy(collections = form.collections.map { it.copy(isSelected = false) }).parameters(AO3WorkSubmitAction.Update), AO3WorkFormField.collectionNames))
        assertEquals(listOf("slowburn_2026"), values(form.copy(collections = form.collections.map { it.copy(isSelected = false) } +
            AO3CollectionOffer("slowburn_2026", "Slow Burn Exchange 2026", isSelected = true)).parameters(AO3WorkSubmitAction.Update), AO3WorkFormField.collectionNames))
    }

    @Test fun clearingEveryCategoryPostsAnEmptyValue() {
        val pairs = parser.parse(workFixture("ao3_work_edit")).copy(categories = emptyList()).parameters(AO3WorkSubmitAction.Update)
        assertEquals(listOf(""), values(pairs, AO3WorkFormField.categories))
    }

    @Test fun categoriesStillPostOneValueEachWhenSet() {
        val pairs = parser.parse(workFixture("ao3_work_edit")).copy(categories = listOf("23", "22")).parameters(AO3WorkSubmitAction.Update)
        assertEquals(listOf("23", "22"), values(pairs, AO3WorkFormField.categories))
    }

    @Test fun missingFormThrowsParse() {
        assertThrows(AO3WorkFormParseException.InvalidForm::class.java) { parser.parse("<html><body>no form</body></html>") }
    }

    @Test fun namedParamKeysMatchOtwarchive() {
        assertEquals("work[title]", AO3WorkFormField.title); assertEquals("work[rating_string]", AO3WorkFormField.rating)
        assertEquals("work[archive_warning_strings][]", AO3WorkFormField.warnings)
        assertEquals("work[fandom_string]", AO3WorkFormField.fandoms)
        assertEquals("work[freeform_string]", AO3WorkFormField.additionalTags); assertEquals("work[wip_length]", AO3WorkFormField.wipLength)
    }

    private fun inject(html: String, controls: String) = html.replace("</form>", "$controls</form>")
    private fun values(pairs: List<Pair<String, String>>, name: String) = pairs.filter { it.first == name }.map { it.second }
    private val commaLists = setOf(AO3WorkFormField.fandoms, AO3WorkFormField.relationships, AO3WorkFormField.characters,
        AO3WorkFormField.additionalTags, AO3WorkFormField.collectionNames, AO3WorkFormField.recipients)
}

internal fun workFixture(name: String): String = listOf("src/debug/assets", "app/src/debug/assets", "android/app/src/debug/assets")
    .map { File("$it/fixtures/$name.html") }.first(File::isFile).readText()

/** Independent browser oracle: reads the DOM, not the production control snapshot or encoder. */
internal fun browserControls(html: String, submit: AO3WorkSubmitAction): List<Pair<String, String>> {
    val doc = Jsoup.parse(html)
    val form = doc.selectFirst("form#work-form") ?: error("Missing fixture form")
    val result = mutableListOf<Pair<String, String>>()
    val controls = doc.select("input, textarea, select, button")
    for (control in controls) {
        val associated = if (control.hasAttr("form")) control.attr("form") == form.id()
            else control.parents().firstOrNull { it.tagName() == "form" } == form
        if (!associated || !control.hasAttr("name") || control.attr("name").isEmpty() || disabledInBrowser(control)) continue
        val name = control.attr("name")
        val type = control.attr("type").lowercase().ifEmpty { if (control.tagName() == "button") "submit" else "text" }
        when (control.tagName()) {
            "textarea" -> result += name to control.wholeText()
            "select" -> {
                val options = control.select("option")
                val explicit = options.filter { it.hasAttr("selected") }
                val selected = if (control.hasAttr("multiple")) explicit else listOfNotNull(explicit.lastOrNull()
                    ?: options.firstOrNull { !it.hasAttr("disabled") && it.parents().none { p -> p.tagName() == "optgroup" && p.hasAttr("disabled") } }
                        ?.takeIf { (control.attr("size").toIntOrNull() ?: 1) <= 1 })
                for (option in selected) if (!option.hasAttr("disabled") && option.parents().none { it.tagName() == "optgroup" && it.hasAttr("disabled") })
                    result += name to if (option.hasAttr("value")) option.attr("value") else option.text()
            }
            else -> {
                if (type in listOf("reset", "button", "image") || control.tagName() == "button" && type != "submit") continue
                if (type in listOf("radio", "checkbox") && !control.hasAttr("checked")) continue
                if (type == "radio") {
                    val last = controls.lastOrNull { radio ->
                        radio.tagName() == "input" && radio.attr("type").equals("radio", true) &&
                            radio.attr("name") == name && radio.hasAttr("checked") &&
                            (if (radio.hasAttr("form")) radio.attr("form") == form.id()
                                else radio.parents().firstOrNull { it.tagName() == "form" } == form)
                    }
                    if (last != control) continue
                }
                if (type == "submit" && name != submit.fieldName) continue
                result += name to if (control.hasAttr("value")) control.attr("value") else if (type in listOf("radio", "checkbox")) "on" else ""
            }
        }
    }
    return result
}

private fun withSubmitter(html: String, submit: AO3WorkSubmitAction): String {
    if (Jsoup.parse(html).select("input[name], button[name]").any { it.attr("name") == submit.fieldName }) return html
    // iOS's enum contains chapter/preview actions not offered by each work page.
    // Add only a submitter for those pure encoder cases, then parse/encode that
    // entire served form unchanged. No invented pair in the browser oracle.
    return html.replace("</form>", "<input type=submit name='${submit.fieldName}' value='Fixture submit'></form>")
}

private fun disabledInBrowser(control: Element): Boolean {
    if (control.hasAttr("disabled")) return true
    for (parent in control.parents()) if (parent.tagName() == "fieldset" && parent.hasAttr("disabled")) {
        val legend = parent.children().firstOrNull { it.tagName() == "legend" }
        if (legend == null || legend !in control.parents()) return true
    }
    return false
}
