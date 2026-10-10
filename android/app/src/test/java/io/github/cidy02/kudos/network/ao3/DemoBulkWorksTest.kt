package io.github.cidy02.kudos.network.ao3

import io.github.cidy02.kudos.network.ao3.writing.*
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteFormParser
import okhttp3.*
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.jsoup.Jsoup
import org.junit.Assert.*
import org.junit.Test
import java.io.File

class DemoBulkWorksTest {
    private val source = FixtureSource { name -> listOf("src/debug/assets", "app/src/debug/assets", "android/app/src/debug/assets")
        .map { File("$it/fixtures/$name.html") }.firstOrNull(File::isFile)?.readBytes() }
    private val base = "https://archiveofourown.org"
    private val ids = listOf(995006L, 995008L, 995009L)
    /** As the interceptor: a page the saved state has nothing to say about is the route's own fixture. */
    private fun get(state: DemoWorkSaves, path: String): Pair<Int, String> {
        val request = Request.Builder().url("$base$path").build()
        return state.answer(request, source, null)
            ?: (200 to source.read(DemoNetworkRoutes.fixtureName(request.url)!!)!!.decodeToString())
    }
    private fun post(state: DemoWorkSaves, path: String, fields: List<Pair<String, String>>, token: String): Pair<Int, String> =
        state.answer(Request.Builder().url("$base$path").post(AO3FormEncoding.encode(fields)
            .toRequestBody("application/x-www-form-urlencoded; charset=UTF-8".toMediaType())).header("X-CSRF-Token", token).build(), source, null)!!
    private fun list(state: DemoWorkSaves) = Jsoup.parse(get(state, "/users/AO3_Reader/works").second).select("li.work.blurb")

    @Test fun threeActualOwnPostedRowsAreEditableAndUniformEditUpdatesAllThenDeleteChangesOnlyConfirmedRows() {
        val state = DemoWorkSaves()
        assertEquals(ids.toSet(), list(state).map { it.id().removePrefix("work_").toLong() }.toSet())
        assertTrue(list(state).all { it.select("a[rel=author]").all { link -> link.attr("href").startsWith("/users/AO3_Reader/") } })
        for (id in ids) {
            val form = AO3WorkFormParser().parse(get(state, "/works/$id/edit").second, "$base/works/$id/edit")
            assertEquals(id, form.workID); assertTrue(form.isPosted)
            val tags = AO3WorkFormParser().parse(get(state, "/works/$id/edit_tags").second, "$base/works/$id/edit_tags")
            assertEquals(id, tags.workID); assertEquals(AO3WorkFormKind.EditTags, tags.kind)
        }
        val token = "demo-work-995006=="
        val open = post(state, "/users/AO3_Reader/works/edit_multiple", listOf("authenticity_token" to token) + ids.map { "work_ids[]" to "$it" }, token)
        val form = AO3BulkEditParser.parse(open.second, "$base/users/AO3_Reader/works/edit_multiple", ids)
        assertEquals(3, form.titles.size); assertTrue(form.options.getValue("work[restricted]").any { it.value == "0" && it.title == "Off" })
        val edit = AO3BulkEditChanges(ids, scalars = mapOf("work[rating_string]" to "Explicit", "work[language_id]" to "2"))
        val saved = post(state, "/users/AO3_Reader/works/update_multiple", edit.parameters(token), token)
        assertNotNull(AO3WriteFormParser().workWriteNotice(saved.second))
        for (id in ids) {
            val fresh = AO3WorkFormParser().parse(get(state, "/works/$id/edit").second, "$base/works/$id/edit")
            assertEquals("Explicit", fresh.rating); assertEquals("2", fresh.languageID)
            assertEquals("Explicit", AO3WorkFormParser().parse(get(state, "/works/$id/edit_tags").second, "$base/works/$id/edit_tags").rating)
        }
        val refused = post(state, "/users/AO3_Reader/works/update_multiple", AO3BulkEditChanges(listOf(995008), pseudsToAdd = "Refuse this edit").parameters("demo-work-995008=="), "demo-work-995008==")
        assertEquals("The Locked Lantern could not be updated.", AO3WriteFormParser().workWriteError(refused.second))
        assertEquals(3, list(state).size)
        val deleteToken = "demo-bulk-delete=="
        assertTrue(get(state, "/users/AO3_Reader/works/show_multiple").second.contains(deleteToken))
        val deleteFields = listOf("authenticity_token" to deleteToken) + ids.map { "work_ids[]" to "$it" } + ("commit" to "Yes, Delete Works")
        val no = post(state, "/users/AO3_Reader/works/delete_multiple", deleteFields, deleteToken)
        assertEquals("The Keeper’s Copy could not be deleted.", AO3WriteFormParser().workWriteError(no.second)); assertEquals(3, list(state).size)
        val yes = post(state, "/users/AO3_Reader/works/delete_multiple", deleteFields.filterNot { it == ("work_ids[]" to "995009") }, deleteToken)
        assertNotNull(AO3WriteFormParser().workWriteNotice(yes.second))
        assertEquals(listOf("work_995009"), list(state).map { it.id() })
        assertEquals(404, get(state, "/works/995006/edit").first)
        assertEquals(3, list(DemoWorkSaves()).size) // Relaunch/reset restores all rows.
    }
    @Test fun demoInterceptorAndBrowserShareOneMutableAnswerAndCannotReachSockets() {
        val held = DemoNetwork.workForms
        val state = DemoWorkSaves(); DemoNetwork.workForms = state
        try {
            val client = OkHttpClient.Builder().addInterceptor(DemoNetworkInterceptor(isActive = { true }, fixtures = { source }, workAnswers = state))
                .addInterceptor { error("Demo bulk work request escaped to a socket") }.build()
            client.newCall(Request.Builder().url("$base/users/AO3_Reader/works").build()).execute().use { assertEquals(200, it.code) }
            val address = "$base/users/AO3_Reader/works".toHttpUrl()
            assertEquals(get(state, "/users/AO3_Reader/works").second, DemoNetwork.webFixture(address, source)!!.decodeToString())
            val token = "demo-bulk-delete=="
            client.newCall(Request.Builder().url("$base/users/AO3_Reader/works/delete_multiple")
                .post(AO3FormEncoding.encode(listOf("authenticity_token" to token, "work_ids[]" to "995006", "commit" to "Yes, Delete Works"))
                    .toRequestBody("application/x-www-form-urlencoded; charset=UTF-8".toMediaType()))
                .header("X-CSRF-Token", token).build()).execute().use { assertEquals(200, it.code) }
            client.newCall(Request.Builder().url(address).build()).execute().use {
                assertTrue(Jsoup.parse(it.body.string()).select("li#work_995006").isEmpty())
            }
            val browser = Jsoup.parse(DemoNetwork.webFixture(address, source)!!.decodeToString())
            assertTrue(browser.select("li#work_995006").isEmpty())
            client.newCall(Request.Builder().url("$base/unbundled-bulk-form").build()).execute().use { assertEquals(404, it.code) }
        } finally { DemoNetwork.workForms = held }
    }
}
