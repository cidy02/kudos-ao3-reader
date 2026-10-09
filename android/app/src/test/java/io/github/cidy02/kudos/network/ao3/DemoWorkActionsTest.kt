package io.github.cidy02.kudos.network.ao3

import io.github.cidy02.kudos.network.ao3.writing.*
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteFormParser
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.junit.Assert.*
import org.junit.Test
import java.io.File

class DemoWorkActionsTest {
    private val source = FixtureSource { name -> listOf("src/debug/assets", "app/src/debug/assets", "android/app/src/debug/assets")
        .map { File("$it/fixtures/$name.html") }.firstOrNull(File::isFile)?.readBytes() }
    private val base = "https://archiveofourown.org"
    private val drafts = "$base/users/AO3_Reader/works/drafts"
    private val requests = mutableListOf<String>()
    private fun client() = OkHttpClient.Builder().addInterceptor { chain ->
        requests += "${chain.request().method} ${chain.request().url.encodedPath}"
        chain.proceed(chain.request())
    }.addInterceptor(DemoNetworkInterceptor(isActive = { true }, fixtures = { source }))
        .addInterceptor { error("Work actions demo cannot reach a socket") }.build()
    private fun get(client: OkHttpClient, path: String): String = client.newCall(Request.Builder().url("$base$path").build()).execute().use {
        assertEquals(200, it.code); it.body.string()
    }
    private fun form(client: OkHttpClient, path: String) = AO3WorkFormParser().parse(get(client, path), "$base$path")
    private fun send(client: OkHttpClient, url: String, fields: List<Pair<String, String>>, token: String): Pair<Int, String> =
        client.newCall(Request.Builder().url(url).post(AO3FormEncoding.encode(fields)
            .toRequestBody("application/x-www-form-urlencoded; charset=UTF-8".toMediaType()))
            .header("X-CSRF-Token", token).header("Referer", url).build()).execute().use { it.code to it.body.string() }
    private fun send(client: OkHttpClient, form: AO3WorkForm, submit: AO3WorkSubmitAction) = send(client, form.actionUrl, form.parameters(submit), form.csrfToken)

    @Test fun draftPostsAndDropsFromDraftsWhileRefusedPostRetainsAo3Draft() {
        val client = client(); val draft = form(client, "/works/995001/edit")
        assertTrue(draft.missingRequiredFields().isEmpty()) // This real demo row is postable.
        val refused = send(client, draft.copy(title = "Refuse this post"), AO3WorkSubmitAction.Post)
        assertEquals(422, refused.first); assertEquals("This draft could not be posted.", AO3WriteFormParser().workWriteError(refused.second))
        assertEquals(draft.title, form(client, "/works/995001/edit").title)
        val posted = send(client, draft, AO3WorkSubmitAction.Post)
        assertEquals(200, posted.first); assertEquals("Work was successfully posted.", AO3WriteFormParser().workWriteNotice(posted.second))
        assertTrue(form(client, "/works/995001/edit").isPosted)
        val page = client.newCall(Request.Builder().url(drafts).build()).execute().use { AO3DraftsParser().parse(it.body.string(), 1) }
        assertFalse(page.page.works.any { it.id == 995001L })
        assertEquals(2, requests.count { it == "POST /works/995001" })
    }

    @Test fun newPreviewCreates995007AndLaterSaveUpdatesItAndResetRestoresInitialRows() {
        val client = client(); val new = form(client, "/works/new").copy(title = "Preview created this draft", chapter = AO3WorkChapterDraft(content = "<p>My preview &amp; 星.</p>"))
        val answer = send(client, new, AO3WorkSubmitAction.Preview)
        assertEquals(200, answer.first)
        val preview = AO3ChapterFormParser().preview(answer.second, new.actionUrl, workOnly = true)
        assertEquals(995007L, preview.workID); assertEquals("Draft was successfully created.", preview.notice)
        val adopted = new.adopting(preview)
        val saved = send(client, adopted.copy(title = "Saved the same draft"), AO3WorkSubmitAction.SaveDraft)
        assertEquals(200, saved.first); assertEquals("Saved the same draft", form(client, "/works/995007/edit").title)
        assertEquals(listOf("POST /works", "POST /works/995007"), requests.filter { it.startsWith("POST") })
        val reset = client()
        val page = reset.newCall(Request.Builder().url(drafts).build()).execute().use { AO3DraftsParser().parse(it.body.string(), 1) }
        assertFalse(page.page.works.any { it.id == 995007L })
        assertFalse(form(reset, "/works/995001/edit").isPosted)
    }

    @Test fun postedDeleteHasServedCountsOnePostAndRefusalLeavesItPresent() {
        val client = client(); val posted = form(client, "/works/995006/edit")
        assertTrue(posted.isPosted)
        assertEquals(200, send(client, posted.copy(title = "Refuse this delete"), AO3WorkSubmitAction.Update).first)
        var implications = AO3WorkDeleteParser.parse(get(client, "/works/995006/confirm_delete"), "$base/works/995006/confirm_delete", 995006)
        assertEquals(7, implications.comments); assertEquals(23, implications.kudos); assertEquals(4, implications.bookmarks)
        val deleteFields = listOf("authenticity_token" to implications.csrfToken, "_method" to implications.methodOverride)
        val refused = send(client, implications.actionUrl, deleteFields, implications.csrfToken)
        assertEquals(422, refused.first); assertEquals("This work could not be deleted.", AO3WriteFormParser().workWriteError(refused.second))
        assertEquals("Refuse this delete", form(client, "/works/995006/edit").title)
        assertEquals(200, send(client, posted, AO3WorkSubmitAction.Update).first)
        implications = AO3WorkDeleteParser.parse(get(client, "/works/995006/confirm_delete"), "$base/works/995006/confirm_delete", 995006)
        val deleted = send(client, implications.actionUrl, deleteFields, implications.csrfToken)
        assertEquals(200, deleted.first); assertEquals("Your work was deleted.", AO3WriteFormParser().workWriteNotice(deleted.second))
        client.newCall(Request.Builder().url("$base/works/995006/edit").build()).execute().use { assertEquals(404, it.code) }
        assertEquals(posted.title, form(client(), "/works/995006/edit").title)
    }

    @Test fun existingPreviewRendersUnsavedTextWithoutChangingTheStoredDraftAndInvalidDeleteTokenIsRefusedLocally() {
        val client = client(); val draft = form(client, "/works/995001/edit")
        val preview = send(client, draft.copy(title = "Unsaved preview title"), AO3WorkSubmitAction.Preview)
        assertEquals(200, preview.first); assertTrue(preview.second.contains("Unsaved preview title"))
        assertEquals(draft.title, form(client, "/works/995001/edit").title)
        val refused = send(client, "$base/works/995001", listOf("authenticity_token" to "wrong", "_method" to "delete"), "wrong")
        assertEquals(422, refused.first); assertEquals(draft.title, form(client, "/works/995001/edit").title)
    }
}
