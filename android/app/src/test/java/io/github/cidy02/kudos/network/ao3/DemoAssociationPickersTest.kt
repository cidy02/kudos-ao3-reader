package io.github.cidy02.kudos.network.ao3

import io.github.cidy02.kudos.auth.*
import io.github.cidy02.kudos.network.ao3.account.AO3AccountParser
import io.github.cidy02.kudos.network.ao3.account.AO3AccountUrls
import io.github.cidy02.kudos.network.ao3.search.AO3TagAutocompleteRepository
import io.github.cidy02.kudos.network.ao3.writes.DefaultAO3AuthenticatedClient
import io.github.cidy02.kudos.network.ao3.writing.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import org.junit.Assert.*
import org.junit.Test
import java.io.File

class DemoAssociationPickersTest {
    private val source = FixtureSource { name ->
        listOf("src/debug/assets", "app/src/debug/assets", "android/app/src/debug/assets")
            .map { File("$it/fixtures/$name.html") }.firstOrNull(File::isFile)?.readBytes()
    }

    @Test fun accountCollectionsHaveOneSharedAnswerAndThreeWorkFormsUseLocalOffers() = runTest {
        val client = localClient()
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
        auth.restoreSession()
        val repository = AO3WorkFormRepository(DefaultAO3AuthenticatedClient(client, client, auth), auth, parseDispatcher = Dispatchers.Unconfined)
        val url = AO3AccountUrls().collectionsUrl("AO3_Reader")
        val browser = DemoNetwork.webFixture(url.toHttpUrl(), source)!!.decodeToString()
        val account = AO3AccountParser().parseCollections(browser)
        val offers = (repository.loadCollectionOffers() as AO3Result.Success).value
        assertEquals(account.map { it.name }, offers.map { it.name })
        assertEquals(account.map { it.title }, offers.map { it.title })
        assertTrue(offers.first().access.isModerated)
        assertFalse(offers.last().access.isOpen)
        assertTrue(offers.last().access.isUnrevealed)
        for (result in listOf(repository.loadNewWorkForm(), repository.loadWorkForm(995001), repository.loadWorkForm(995006))) {
            val form = (result as AO3Result.Success).value
            val enriched = form.applyingCollectionStates(offers)
            assertEquals(form.postedCollectionNames, enriched.postedCollectionNames)
            assertEquals(form.servedControls, enriched.servedControls)
        }
        assertEquals(0, client.posts)
    }

    @Test fun collectionAutocompleteHasSeveralEmptyAndFailedLocalAnswersWithoutSockets() = runTest {
        val client = localClient()
        val repository = AO3TagAutocompleteRepository(client)
        val several = (repository.openCollections("demo") as AO3Result.Success).value
        assertEquals(listOf("demo_lanterns", "demo_atlas", "demo_exchange"), several.map { it.name })
        assertEquals(listOf("Demo Lanterns", "Demo Atlas & 星", "Demo Exchange"), several.map { it.title })
        assertTrue(several.all { !it.access.isDescribed && !it.isSelected })
        assertTrue((repository.openCollections("none") as AO3Result.Success).value.isEmpty())
        assertEquals(AO3Result.Failure(AO3Error.Forbidden), repository.openCollections("fail"))
        val reads = client.gets
        repository.openCollections("\u200b  \n")
        assertEquals(reads, client.gets)
        assertEquals(0, client.posts)
    }

    private fun localClient() = LocalAssociationClient(OkHttpClient.Builder()
        .addInterceptor(DemoNetworkInterceptor(isActive = { true }, fixtures = { source }))
        .addInterceptor { throw AssertionError("Association demo tried to open a socket") }.build())

    private class LocalAssociationClient(private val http: OkHttpClient) : AO3Client, AO3FormPostClient {
        var gets = 0
        var posts = 0
        override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
            gets++
            return http.newCall(Request.Builder().url(url).apply { headers.forEach { (name, value) -> header(name, value) } }.build())
                .execute().use { response ->
                    if (response.code == 403) AO3Result.Failure(AO3Error.Forbidden)
                    else AO3Result.Success(AO3HttpResponse(url, response.code, emptyMap(), response.body.string()))
                }
        }
        override suspend fun postForm(url: String, formFields: List<Pair<String, String>>, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
            posts++; error("Association demo must never POST")
        }
    }
}
