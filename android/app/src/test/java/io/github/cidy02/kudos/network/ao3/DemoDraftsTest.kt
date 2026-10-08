package io.github.cidy02.kudos.network.ao3

import io.github.cidy02.kudos.network.ao3.writing.AO3DraftsParser
import io.github.cidy02.kudos.network.ao3.writing.DraftExpiry
import io.github.cidy02.kudos.network.ao3.writing.AO3WorkForm
import io.github.cidy02.kudos.network.ao3.writing.AO3WorkFormParser
import io.github.cidy02.kudos.network.ao3.writing.AO3WorkSubmitAction
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteFormParser
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

class DemoDraftsTest {
    private val source = FixtureSource { name ->
        listOf("src/debug/assets", "app/src/debug/assets", "android/app/src/debug/assets")
            .map { File("$it/fixtures/$name.html") }.firstOrNull(File::isFile)?.readBytes()
    }
    private val base = "https://archiveofourown.org/users/AO3_Reader/works/drafts"

    @Test fun realInterceptorServesTwoLocalPagesWithTheClockPinnedInAnyYear() {
        for (instant in listOf("2000-02-28T12:00:00Z", "2033-12-31T12:00:00Z")) {
            val clock = Clock.fixed(Instant.parse(instant), ZoneOffset.UTC)
            val client = client(source, clock)
            val parser = AO3DraftsParser()
            val first = parser.parse(html(client, base), 1)
            val second = parser.parse(html(client, "$base?page=2"), 2)
            assertEquals(listOf(29, 7), first.deletionDates.values.map { DraftExpiry.daysLeft(it, clock) })
            assertEquals(listOf(1, 0), second.deletionDates.values.map { DraftExpiry.daysLeft(it, clock) })
            assertEquals(LocalDate.now(clock), DraftExpiry.createdDate(first.deletionDates.getValue(995001L)))
            assertNull(first.deletionDates[995003L])
            assertEquals(listOf(995004L, 995005L), second.page.works.map { it.id })
            assertEquals("page 1 of 2 · 1 expiring this week on this page", DraftExpiry.tally(first, clock))
            assertEquals("page 2 of 2 · 2 expiring this week on this page", DraftExpiry.tally(second, clock))
        }
    }

    @Test fun draftsRoutesCannotReplaceTheWorksPageAndBrowserEditorsAreAlreadyBundled() {
        assertEquals("ao3_demo_drafts_1", DemoNetworkRoutes.fixtureName(base.toHttpUrl()))
        assertEquals("ao3_demo_drafts_2", DemoNetworkRoutes.fixtureName("$base/?page=2".toHttpUrl()))
        assertEquals("ao3_author_works", DemoNetworkRoutes.fixtureName("https://archiveofourown.org/users/AO3_Reader/works".toHttpUrl()))
        assertEquals("ao3_author_works", DemoNetworkRoutes.fixtureName("https://archiveofourown.org/users/AO3_Reader/works/drafts/edit".toHttpUrl()))
        assertNotNull(DemoNetwork.webFixture("https://archiveofourown.org/works/new".toHttpUrl(), source))
        assertNotNull(DemoNetwork.webFixture("https://archiveofourown.org/works/995001/edit".toHttpUrl(), source))
        val clock = Clock.fixed(Instant.parse("2026-10-05T12:00:00Z"), ZoneOffset.UTC)
        val browser = AO3DraftsParser().parse(DemoNetwork.webFixture(base.toHttpUrl(), source, clock)!!.decodeToString(), 1)
        assertEquals(29, DraftExpiry.daysLeft(browser.deletionDates.getValue(995001L), clock))
    }

    @Test fun missingDraftsAssetsAreTerminalLocalFailuresOnBothPagesAndInTheBrowser() {
        val empty = FixtureSource { null }
        val client = client(empty, Clock.systemUTC())
        for (url in listOf(base, "$base?page=2")) {
            client.newCall(Request.Builder().url(url).build()).execute().use { assertEquals(404, it.code) }
            assertNull(DemoNetwork.webFixture(url.toHttpUrl(), empty))
        }
    }

    private fun client(source: FixtureSource, clock: Clock): OkHttpClient = OkHttpClient.Builder()
        .addInterceptor(DemoNetworkInterceptor(isActive = { true }, fixtures = { source }, clock = clock))
        .addInterceptor { error("The drafts demo must never reach the network") }.build()

    @Test fun demoSavesNewAndExistingDraftAndUpdatesPostedWorkThenResetsOnRelaunch() {
        val client = client(source, Clock.systemUTC())
        val parser = AO3WorkFormParser()
        for ((path, title) in listOf("/works/new" to "A locally saved new draft", "/works/995001/edit" to "Changed lanterns",
            "/works/995006/edit" to "Changed posted tide")) {
            val url = "https://archiveofourown.org$path"
            val form = parser.parse(html(client, url), url).copy(title = title)
            val answer = save(client, form)
            assertEquals(200, answer.first)
            assertNotNull(AO3WriteFormParser().workWriteNotice(answer.second))
            val workId = form.workID ?: 995007L
            val editedUrl = "https://archiveofourown.org/works/$workId/edit"
            val edited = parser.parse(html(client, editedUrl), editedUrl)
            assertEquals(title, edited.title)
            assertEquals(workId, edited.workID)
            assertEquals(form.isPosted, edited.isPosted)
        }
        val drafts = AO3DraftsParser().parse(html(client, base), 1)
        assertEquals("A locally saved new draft", drafts.page.works.first { it.id == 995007L }.title)
        assertEquals("Changed lanterns", drafts.page.works.first { it.id == 995001L }.title)
        assertTrue(drafts.page.works.none { it.id == 995006L })
        val reset = client(source, Clock.systemUTC())
        val fresh = AO3DraftsParser().parse(html(reset, base), 1)
        assertTrue(fresh.page.works.none { it.id == 995007L })
        assertEquals("Lanterns Above the Mill", fresh.page.works.first { it.id == 995001L }.title)
    }

    @Test fun refusedTitleAndInvalidTokenStayLocalAndNeverChangeTheDraft() {
        val client = client(source, Clock.systemUTC())
        val url = "https://archiveofourown.org/works/995001/edit"
        val form = AO3WorkFormParser().parse(html(client, url), url)
        val refused = save(client, form.copy(title = "Refuse this draft"))
        assertEquals(422, refused.first)
        assertEquals("Title is too long (maximum is 255 characters)", AO3WriteFormParser().workWriteError(refused.second))
        assertEquals(form.title, AO3WorkFormParser().parse(html(client, url), url).title)
        assertEquals(422, save(client, form.copy(csrfToken = "wrong")).first)
        assertEquals(form.title, AO3WorkFormParser().parse(html(client, url), url).title)
    }

    @Test fun workSaveWithoutBundledAssetsIsATerminalLocalFailure() {
        val client = client(FixtureSource { null }, Clock.systemUTC())
        val form = AO3WorkFormParser().parse(source.read("ao3_demo_work_draft_edit")!!.decodeToString(),
            "https://archiveofourown.org/works/995001/edit")
        assertEquals(404, save(client, form).first)
    }

    private fun save(client: OkHttpClient, form: AO3WorkForm): Pair<Int, String> {
        val submit = if (form.isPosted) AO3WorkSubmitAction.Update else AO3WorkSubmitAction.SaveDraft
        val body = AO3FormEncoding.encode(form.parameters(submit))
            .toRequestBody("application/x-www-form-urlencoded; charset=UTF-8".toMediaType())
        return client.newCall(Request.Builder().url(form.actionUrl).post(body)
            .header("X-CSRF-Token", form.csrfToken).header("Referer", form.actionUrl).build()).execute().use {
            it.code to it.body.string()
        }
    }

    private fun html(client: OkHttpClient, url: String): String =
        client.newCall(Request.Builder().url(url).build()).execute().use {
            assertEquals(200, it.code); it.body.string()
        }
}
