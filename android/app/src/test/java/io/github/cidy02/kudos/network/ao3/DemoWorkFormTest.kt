package io.github.cidy02.kudos.network.ao3

import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.MemoryCookieStore
import io.github.cidy02.kudos.auth.MemorySessionStore
import io.github.cidy02.kudos.auth.testSession
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteFormParser
import io.github.cidy02.kudos.network.ao3.writes.DefaultAO3AuthenticatedClient
import io.github.cidy02.kudos.network.ao3.writing.AO3WorkFormKind
import io.github.cidy02.kudos.network.ao3.writing.AO3WorkFormParser
import io.github.cidy02.kudos.network.ao3.writing.AO3WorkFormRepository
import io.github.cidy02.kudos.network.ao3.writing.AO3WorkFormUrls
import io.github.cidy02.kudos.network.ao3.writing.AO3WorkSubmitAction
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import okhttp3.FormBody
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import org.junit.Assert.*
import org.junit.Test

class DemoWorkFormTest {
    private val source = FixtureSource { name ->
        listOf("src/debug/assets", "app/src/debug/assets", "android/app/src/debug/assets")
            .map { File("$it/fixtures/$name.html") }.firstOrNull(File::isFile)?.readBytes()
    }

    @Test fun demoRepositoryReadsAllThreeFormsLocallyAndBrowserSharesEachAnswer() = runTest {
        val network = localClient(source)
        val get = object : AO3Client {
            override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
                network.newCall(Request.Builder().url(url).apply { headers.forEach { (name, value) -> header(name, value) } }.build())
                    .execute().use { return AO3Result.Success(AO3HttpResponse(url, it.code, emptyMap(), it.body.string())) }
            }
        }
        val noWrites = object : AO3FormPostClient {
            override suspend fun postForm(url: String, formFields: List<Pair<String, String>>, headers: Map<String, String>): AO3Result<AO3HttpResponse> =
                error("Form fixture test must never POST")
        }
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
        auth.restoreSession()
        val repository = AO3WorkFormRepository(DefaultAO3AuthenticatedClient(get, noWrites, auth), auth, parseDispatcher = Dispatchers.Unconfined)
        val loaded = listOf(repository.loadNewWorkForm(), repository.loadWorkForm(995001), repository.loadWorkForm(995006))
        for ((index, result) in loaded.withIndex()) {
            val form = (result as AO3Result.Success).value
            val url = if (index == 0) "https://archiveofourown.org/works/new" else "https://archiveofourown.org/works/${form.workID}/edit"
            val browser = DemoNetwork.webFixture(url.toHttpUrl(), source)!!.decodeToString()
            assertEquals(form, AO3WorkFormParser().parse(browser, url))
        }
        assertEquals(listOf(AO3WorkFormKind.New, AO3WorkFormKind.Draft, AO3WorkFormKind.Edit), loaded.map { (it as AO3Result.Success).value.kind })
    }

    @Test fun exactDraftAndPostedEditRoutesDoNotReplaceLegacyAnswers() {
        val expected = mapOf("new" to "ao3_work_new_draft", "995001/edit" to "ao3_demo_work_draft_edit",
            "995006/edit" to "ao3_demo_work_posted_edit", "123/edit" to "ao3_work_edit",
            "995001" to "ao3_work_bookmarked_subscribed", "995006/chapters/775006/edit" to "ao3_work_bookmarked_subscribed")
        expected.forEach { (path, fixture) ->
            assertEquals(path, fixture, DemoNetworkRoutes.fixtureName("https://archiveofourown.org/works/$path".toHttpUrl()))
        }
    }

    @Test fun missingAssetsFailLocallyForInterceptorAndBrowser() {
        val empty = FixtureSource { null }
        val client = localClient(empty)
        for (path in listOf("new", "995001/edit", "995006/edit")) {
            val url = "https://archiveofourown.org/works/$path"
            client.newCall(Request.Builder().url(url).build()).execute().use { assertEquals(404, it.code) }
            assertNull(DemoNetwork.webFixture(url.toHttpUrl(), empty))
        }
    }

    @Test fun postedTagsDemoReadsPostsRefusesAndRefreshesLocallyWithoutChangingText() {
        val network = localClient(source)
        val parser = AO3WorkFormParser()
        val tagsUrl = AO3WorkFormUrls.editTags(995006)
        fun read(url: String): String = network.newCall(Request.Builder().url(url).build()).execute().use {
            assertEquals(200, it.code); it.body.string()
        }
        val initial = parser.parse(read(AO3WorkFormUrls.editWork(995006)))
        val tagsHtml = read(tagsUrl)
        assertEquals(DemoNetwork.webFixture(tagsUrl.toHttpUrl(), source)!!.decodeToString(), tagsHtml)
        val tags = parser.parse(tagsHtml, tagsUrl)
        assertEquals(AO3WorkFormKind.EditTags, tags.kind)
        fun post(fields: List<Pair<String, String>>): Pair<Int, String> {
            val body = FormBody.Builder().apply { fields.forEach { (key, value) -> add(key, value) } }.build()
            return network.newCall(Request.Builder().url(tags.actionUrl).post(body)
                .header("X-CSRF-Token", tags.csrfToken).header("Referer", tagsUrl).build()).execute().use { it.code to it.body.string() }
        }
        val accepted = tags.copy(fandoms = listOf("A new fandom & 星"), categories = emptyList(),
            relationships = emptyList(), characters = listOf("New character"), additionalTags = emptyList(), rating = "Mature")
        val saved = post(accepted.parameters(AO3WorkSubmitAction.Update))
        assertEquals(200, saved.first); assertNotNull(AO3WriteFormParser().workWriteNotice(saved.second))
        val fresh = parser.parse(read(AO3WorkFormUrls.editWork(995006)))
        assertEquals(accepted.fandoms, fresh.fandoms); assertEquals(emptyList<String>(), fresh.categories)
        assertEquals(accepted.rating, fresh.rating); assertEquals(accepted.characters, fresh.characters)
        assertEquals(emptyList<String>(), fresh.relationships); assertEquals(emptyList<String>(), fresh.additionalTags)
        assertEquals(initial.title, fresh.title); assertEquals(initial.summary, fresh.summary)
        assertEquals(initial.notes, fresh.notes); assertEquals(initial.chapter, fresh.chapter)
        assertEquals(accepted.fandoms, parser.parse(read(tagsUrl), tagsUrl).fandoms)
        val refused = post(accepted.copy(additionalTags = listOf("Refuse this tag")).parameters(AO3WorkSubmitAction.Update))
        assertEquals(422, refused.first)
        assertEquals("Additional tags: Refuse this tag could not be saved.", AO3WriteFormParser().writeErrorMessage(refused.second))
        assertEquals(fresh, parser.parse(read(AO3WorkFormUrls.editWork(995006))))
        assertEquals(emptyList<String>(), parser.parse(read(tagsUrl), tagsUrl).additionalTags)
        val badToken = post(accepted.copy(csrfToken = "bad").parameters(AO3WorkSubmitAction.Update))
        assertEquals(422, badToken.first)
        assertEquals("AO3 didn't accept the change.", AO3WriteFormParser().writeErrorMessage(badToken.second))
        val restarted = localClient(source)
        restarted.newCall(Request.Builder().url(tagsUrl).build()).execute().use {
            assertEquals(tags, parser.parse(it.body.string(), tagsUrl))
        }
    }

    private fun localClient(source: FixtureSource) = OkHttpClient.Builder()
        .addInterceptor(DemoNetworkInterceptor(isActive = { true }, fixtures = { source }))
        .addInterceptor { error("Work form demo must never reach a socket") }.build()
}
