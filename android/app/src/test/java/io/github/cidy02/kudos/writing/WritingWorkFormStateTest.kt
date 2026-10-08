package io.github.cidy02.kudos.writing

import io.github.cidy02.kudos.auth.*
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.writes.DefaultAO3AuthenticatedClient
import io.github.cidy02.kudos.network.ao3.writing.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import org.jsoup.Jsoup
import org.junit.Assert.*
import org.junit.Test
import java.time.LocalDate

class WritingWorkFormStateTest {
    @Test fun oneGetPerOpeningAndNoReadAfterAnyEditOrEditorReturn() = runTest {
        for (id in listOf(null, 995001L, 995006L)) {
            val setup = workFormSetup()
            val model = setup.model(id)
            model.load()
            model.load()
            model.title("changed")
            model.choice(WorkFormChoice.Language, "2")
            model.toggleTag(WorkFormTags.Categories, "F/F")
            model.toggle(WorkFormSwitch.Restricted, true)
            model.checkpoint(WorkFormText.Summary, "checkpoint")
            model.checkpoint(WorkFormText.Summary, "Done")
            model.load(retry = true)
            assertEquals(listOf(if (id == null) AO3WorkFormUrls.newWork() else AO3WorkFormUrls.editWork(id)), setup.client.gets)
            assertEquals("Done", model.state.value.form!!.summary)
            model.close()
            model.title("late callback")
            assertEquals("changed", model.state.value.form!!.title)
            setup.model(id).load()
            assertEquals(2, setup.client.gets.size)
            assertEquals(0, setup.client.posts)
        }
    }

    @Test fun signedOutAndSignedOutRetriesReadNothing() = runTest {
        val setup = workFormSetup(signedIn = false)
        for (id in listOf(null, 995001L, 995006L)) {
            val model = setup.model(id)
            model.load(); model.load(retry = true)
            assertNull(model.state.value.form)
            assertEquals("Log in to AO3 first.", model.state.value.failure)
        }
        assertTrue(setup.client.gets.isEmpty())
        assertEquals(0, setup.client.posts)
    }

    @Test fun eachSingleChoiceAndTitleHasTheExactIosPayloadDeltaAcrossAllThreeForms() = runTest {
        for (id in listOf(null, 995001L, 995006L)) {
            val setup = workFormSetup()
            val model = setup.model(id).also { it.load() }
            var old = model.state.value.form!!
            model.title("  Unicode 星 & \"title\"  ")
            assertDelta(old, model.state.value.form!!, mapOf(AO3WorkFormField.title to listOf("  Unicode 星 & \"title\"  ")))
            for ((choice, name, value) in listOf(
                Triple(WorkFormChoice.Rating, AO3WorkFormField.rating, "Mature"),
                Triple(WorkFormChoice.Language, AO3WorkFormField.languageID, "2"),
                Triple(WorkFormChoice.Comments, AO3WorkFormField.commentPermissions, "disable_all"),
                Triple(WorkFormChoice.Skin, AO3WorkFormField.workSkinID, "66"),
                Triple(WorkFormChoice.Skin, AO3WorkFormField.workSkinID, "")
            )) {
                old = model.state.value.form!!
                model.choice(choice, value)
                assertDelta(old, model.state.value.form!!, mapOf(name to listOf(value)))
            }
            old = model.state.value.form!!
            model.choice(WorkFormChoice.Rating, "invented")
            assertEquals(old, model.state.value.form)
            model.choice(WorkFormChoice.Rating, "")
            assertEquals("", model.state.value.form!!.rating)
            // iOS sends no rating when none is chosen. The encoder (3bb) then sends the control back as AO3
            // served it: the blank choice on a new form, the rating AO3 already holds on an existing one.
            // AO3 keeps what it had either way; choosing the blank line does not clear a rating on either app.
            assertDelta(old, model.state.value.form!!, mapOf(AO3WorkFormField.rating to
                old.servedControls.first { it.name == AO3WorkFormField.rating }.values))
            assertEquals(1, setup.client.gets.size); assertEquals(0, setup.client.posts)
        }
    }

    @Test fun multipleChoicesAppendInTapOrderRemoveAndClearWithTheIosEmptySentinel() = runTest {
        for (id in listOf(null, 995001L, 995006L)) for (kind in WorkFormTags.entries) {
            val setup = workFormSetup()
            val model = setup.model(id).also { it.load() }
            val name = if (kind == WorkFormTags.Warnings) AO3WorkFormField.warnings else AO3WorkFormField.categories
            for (option in model.state.value.form!!.tagOptions(kind)) {
                val old = model.state.value.form!!
                val values = old.tagValues(kind)
                val expected = if (option.value in values) values.filterNot { it == option.value } else values + option.value
                model.toggleTag(kind, option.value)
                assertDelta(old, model.state.value.form!!, mapOf(name to expected.ifEmpty { listOf("") }))
                assertEquals(expected, model.state.value.form!!.tagValues(kind))
            }
            for (value in model.state.value.form!!.tagValues(kind).toList()) model.toggleTag(kind, value)
            assertEquals(listOf(""), model.state.value.form!!.parameters(AO3WorkSubmitAction.Update).filter { it.first == name }.map { it.second })
            val old = model.state.value.form
            model.toggleTag(kind, "not served")
            assertEquals(old, model.state.value.form)
            assertEquals(1, setup.client.gets.size); assertEquals(0, setup.client.posts)
        }
    }

    @Test fun allSwitchesAndChapterTotalsChangeOnlyIosFields() = runTest {
        for (id in listOf(null, 995001L, 995006L)) {
            val setup = workFormSetup()
            val model = setup.model(id).also { it.load() }
            for ((switch, name) in listOf(WorkFormSwitch.Backdate to AO3WorkFormField.backdate,
                WorkFormSwitch.Restricted to AO3WorkFormField.restricted, WorkFormSwitch.Moderation to AO3WorkFormField.moderatedCommenting)) {
                for (on in listOf(true, false)) {
                    val old = model.state.value.form!!
                    model.toggle(switch, on)
                    assertDelta(old, model.state.value.form!!, mapOf(name to listOf(if (on) "1" else "0")))
                }
            }
            if (id == 995006L) {
                for ((on, value) in listOf(true to "2", false to "")) {
                    val old = model.state.value.form!!
                    model.toggle(WorkFormSwitch.Complete, on)
                    assertDelta(old, model.state.value.form!!, mapOf(AO3WorkFormField.wipLength to listOf(value)))
                    assertEquals(old.isChaptered, model.state.value.form!!.isChaptered)
                }
                val old = model.state.value.form!!
                model.chapterTotal("17")
                assertDelta(old, model.state.value.form!!, mapOf(AO3WorkFormField.wipLength to listOf("17")))
            }
            assertEquals(0, setup.client.posts)
        }
    }

    @Test fun editorCheckpointDoneAndLeaveChangeOnlyTheirBoundField() = runTest {
        for (id in listOf(null, 995001L, 995006L)) {
            val setup = workFormSetup()
            val model = setup.model(id).also { it.load() }
            val fields = if (id == 995006L) WorkFormText.entries.filterNot { it == WorkFormText.Content } else WorkFormText.entries
            for (field in fields) for (text in listOf("<p>checkpoint 星 &amp; water</p>\n", "<i>Done/leave</i>\n\n", "")) {
                val old = model.state.value.form!!
                val name = when (field) {
                    WorkFormText.Summary -> AO3WorkFormField.summary
                    WorkFormText.Notes -> AO3WorkFormField.notes
                    WorkFormText.Endnotes -> AO3WorkFormField.endnotes
                    WorkFormText.Content -> AO3WorkFormField.chapterContent
                }
                model.checkpoint(field, text)
                assertDelta(old, model.state.value.form!!, mapOf(name to listOf(text)))
                assertEquals(text, field.text(model.state.value.form!!))
            }
            assertEquals(if (id == null) "work:new" else "work:$id", model.state.value.form!!.recoveryTarget())
            assertEquals(listOf("summary", "notes", "endnotes", "content"), WorkFormText.entries.map { it.field })
            assertEquals("AO3_Reader", setup.auth.username())
            assertEquals(1, setup.client.gets.size); assertEquals(0, setup.client.posts)
        }
    }

    @Test fun dateWritesUnpaddedPartsAndRejectsOutOfRangeWithoutChangingBackdate() = runTest {
        for (id in listOf(null, 995001L)) {
            val setup = workFormSetup()
            val model = setup.model(id).also { it.load() }
            val old = model.state.value.form!!
            model.publicationDate(LocalDate.of(2024, 3, 7))
            assertDelta(old, model.state.value.form!!, mapOf(AO3WorkFormField.chapterPublishedYear to listOf("2024"),
                AO3WorkFormField.chapterPublishedMonth to listOf("3"), AO3WorkFormField.chapterPublishedDay to listOf("7")))
            assertEquals(old.backdate, model.state.value.form!!.backdate)
            val changed = model.state.value.form
            model.publicationDate(LocalDate.of(1949, 12, 31)); model.publicationDate(LocalDate.of(2026, 10, 8))
            assertEquals(changed, model.state.value.form)
        }
        val setup = workFormSetup()
        val posted = setup.model(995006L).also { it.load() }
        val old = posted.state.value.form
        posted.publicationDate(LocalDate.of(2024, 3, 7))
        assertEquals(old, posted.state.value.form) // No modeled chapter: raw posted date remains untouched.
    }

    @Test fun backdateFillsTodayOnlyForAnExistingChapterWithAnEmptyYear() = runTest {
        val setup = workFormSetup()
        setup.client.body = Jsoup.parse(workFixture("ao3_work_new_draft")).apply {
            select("select[name^='work[chapter_attributes][published_at']").remove()
        }.outerHtml()
        val model = setup.model(null).also { it.load() }
        val old = model.state.value.form!!
        assertEquals("", old.chapter!!.publishedYear)
        model.toggle(WorkFormSwitch.Backdate, true)
        assertDelta(old, model.state.value.form!!, mapOf(AO3WorkFormField.backdate to listOf("1"),
            AO3WorkFormField.chapterPublishedYear to listOf("2026"), AO3WorkFormField.chapterPublishedMonth to listOf("10"),
            AO3WorkFormField.chapterPublishedDay to listOf("7")))
    }

    @Test fun sessionChangesAndClosedModelsRejectLateCheckpointAndReadResults() = runTest {
        val setup = workFormSetup()
        val model = setup.model(995001L).also { it.load() }
        val old = model.state.value.form
        setup.auth.logout()
        model.checkpoint(WorkFormText.Content, "late private text")
        model.title("late title")
        assertEquals(old, model.state.value.form)
        val loading = workFormSetup()
        loading.client.beforeResponse = { loading.auth.logout() }
        val stale = loading.model(995001L)
        assertThrows(CancellationException::class.java) { kotlinx.coroutines.runBlocking { stale.load() } }
        assertNull(stale.state.value.form)
        assertEquals(1, loading.client.gets.size)
    }

    @Test fun failuresHaveIosWordsAndOnlyExplicitRetryReadsAgain() = runTest {
        val setup = workFormSetup()
        setup.client.failure = AO3Error.Overloaded(503, null)
        val model = setup.model(null)
        model.load(); model.load()
        assertEquals("AO3 had a server problem (HTTP 503). Try again shortly.", model.state.value.failure)
        assertEquals(1, setup.client.gets.size)
        assertEquals("AO3's page format wasn't what the app expected.", workFormFailure(AO3Error.Overloaded(200, null)))
        assertEquals("AO3 is rate-limiting requests. Wait a moment and try again.", workFormFailure(AO3Error.Overloaded(429, null)))
        setup.client.failure = null
        model.load(retry = true)
        assertNotNull(model.state.value.form)
        assertEquals(2, setup.client.gets.size); assertEquals(0, setup.client.posts)
    }
}

/** Full ordered untouched round trip stays byte-for-byte identical outside the named changes. */
internal fun assertDelta(old: AO3WorkForm, changed: AO3WorkForm, expected: Map<String, List<String>>) {
    assertEquals(old.servedControls, changed.servedControls)
    for (submit in AO3WorkSubmitAction.entries) {
        val before = old.parameters(submit)
        val after = changed.parameters(submit)
        assertEquals("untouched fields / $submit", before.filterNot { it.first in expected }, after.filterNot { it.first in expected })
        for ((name, values) in expected) assertEquals("$name / $submit", values, after.filter { it.first == name }.map { it.second })
    }
}

internal data class WorkFormTestSetup(val auth: AO3AuthRepository, val client: WorkFormScreenClient, val repository: AO3WorkFormRepository) {
    fun model(id: Long?) = WritingWorkFormState(id, repository, auth, today = { LocalDate.of(2026, 10, 7) })
}
internal suspend fun workFormSetup(signedIn: Boolean = true): WorkFormTestSetup {
    val auth = AO3AuthRepository(MemorySessionStore(if (signedIn) testSession() else null), MemoryCookieStore())
    auth.restoreSession()
    val client = WorkFormScreenClient()
    val authenticated = DefaultAO3AuthenticatedClient(client, client, auth)
    return WorkFormTestSetup(auth, client, AO3WorkFormRepository(authenticated, auth, parseDispatcher = Dispatchers.Unconfined))
}
internal class WorkFormScreenClient : AO3Client, AO3FormPostClient {
    val gets = mutableListOf<String>()
    var posts = 0
    var body: String? = null
    var failure: AO3Error? = null
    var beforeResponse: suspend () -> Unit = {}
    override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        gets += url
        beforeResponse()
        failure?.let { return AO3Result.Failure(it) }
        val fixture = when {
            url.endsWith("/995001/edit") -> "ao3_demo_work_draft_edit"
            url.endsWith("/995006/edit") -> "ao3_demo_work_posted_edit"
            else -> "ao3_work_new_draft"
        }
        return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), body ?: workFixture(fixture)))
    }
    override suspend fun postForm(url: String, formFields: List<Pair<String, String>>, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        posts++
        error("Brief 3bf must never send anything")
    }
}
