package io.github.cidy02.kudos.network.ao3.writing

import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.MemoryCookieStore
import io.github.cidy02.kudos.auth.MemorySessionStore
import io.github.cidy02.kudos.auth.testSession
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3FormPostClient
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.writes.DefaultAO3AuthenticatedClient
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test
import kotlin.coroutines.CoroutineContext

class AO3WorkFormRepositoryTest {
    @Test fun newDraftAndPostedFormsEachReadOnlyTheirOwnPageThroughAuthenticatedClient() = runTest {
        val (auth, client, repository) = setup()
        assertTrue(repository.loadNewWorkForm() is AO3Result.Success)
        assertTrue(repository.loadWorkForm(995001) is AO3Result.Success)
        assertTrue(repository.loadWorkForm(995006) is AO3Result.Success)
        assertEquals(listOf(AO3WorkFormUrls.newWork(), AO3WorkFormUrls.editWork(995001), AO3WorkFormUrls.editWork(995006)), client.gets)
        assertTrue(client.headers.all { it["Cookie"].orEmpty().isNotEmpty() })
        assertEquals("AO3_Reader", auth.username())
    }

    @Test fun signedOutReadsNothing() = runTest {
        val (_, client, repository) = setup(false)
        assertEquals(AO3Result.Failure(AO3Error.AuthenticationRequired), repository.loadNewWorkForm())
        assertEquals(AO3Result.Failure(AO3Error.AuthenticationRequired), repository.loadWorkForm(995001))
        assertTrue(client.gets.isEmpty())
    }

    @Test fun logoutDuringReadDiscardsThePrivateResponse() = runTest {
        val (auth, client, repository) = setup()
        client.beforeResponse = { auth.logout() }
        var cancelled = false
        try { repository.loadWorkForm(995001) } catch (_: CancellationException) { cancelled = true }
        assertTrue(cancelled); assertEquals(1, client.gets.size)
    }

    @Test fun cancellationPropagatesWithoutParseOrRetry() = runTest {
        val (_, client, repository) = setup()
        client.beforeResponse = { throw CancellationException() }
        var cancelled = false
        try { repository.loadNewWorkForm() } catch (_: CancellationException) { cancelled = true }
        assertTrue(cancelled); assertEquals(1, client.gets.size)
    }

    @Test fun aSessionChangeDuringParsingDiscardsThePrivateForm() = runTest {
        val (auth, client, _) = setup()
        var queuedParse: Runnable? = null
        val parseDispatcher = object : CoroutineDispatcher() {
            override fun dispatch(context: CoroutineContext, block: Runnable) { queuedParse = block }
        }
        val repository = AO3WorkFormRepository(client.authenticated(auth), auth,
            parseDispatcher = parseDispatcher)
        val loaded = async { repository.loadWorkForm(995001) }
        // Pause precisely at the parse dispatcher boundary, after the GET.
        runCurrent()
        assertNotNull(queuedParse)
        auth.logout()
        queuedParse!!.run()
        var cancelled = false
        try { loaded.await() } catch (_: CancellationException) { cancelled = true }
        assertTrue(cancelled)
    }

    @Test fun loginOverloadAndErrorBodiesMapToTypedFailuresWithoutAnAnonymousRetry() = runTest {
        val (auth, client, repository) = setup()
        client.body = "<form id=new_user action='/users/login'></form>"
        assertEquals(AO3Result.Failure(AO3Error.AuthenticationRequired), repository.loadNewWorkForm())
        assertNull(auth.username()); assertEquals(1, client.gets.size)
        val (_, overloadClient, overloadRepository) = setup()
        overloadClient.body = "<h1>AO3 is temporarily overloaded</h1>"
        assertEquals(AO3Result.Failure(AO3Error.Overloaded(200, null)), overloadRepository.loadNewWorkForm())
        overloadClient.body = "<h1>Error</h1>"
        val failure = overloadRepository.loadNewWorkForm()
        assertTrue(failure is AO3Result.Failure && failure.error is AO3Error.Parse)
        assertEquals(2, overloadClient.gets.size)
    }

    @Test fun sharedClientFailuresAreReturnedWithoutRepositoryRetries() = runTest {
        val (_, client, repository) = setup()
        for (error in listOf(AO3Error.Forbidden, AO3Error.NotFound, AO3Error.RateLimited(1000), AO3Error.Network("offline"))) {
            client.failure = error
            assertEquals(AO3Result.Failure(error), repository.loadNewWorkForm())
        }
        assertEquals(4, client.gets.size)
    }

    @Test fun urlsHaveNoExtraQueriesAndRejectInvalidWorkIds() {
        assertEquals("https://archiveofourown.org/works/new", AO3WorkFormUrls.newWork())
        assertEquals("https://archiveofourown.org/works/995001/edit", AO3WorkFormUrls.editWork(995001))
        assertThrows(IllegalArgumentException::class.java) { AO3WorkFormUrls.editWork(0) }
    }

    private suspend fun setup(signedIn: Boolean = true): Triple<AO3AuthRepository, WorkFormMemoryClient, AO3WorkFormRepository> {
        val auth = AO3AuthRepository(MemorySessionStore(if (signedIn) testSession() else null), MemoryCookieStore())
        auth.restoreSession()
        val client = WorkFormMemoryClient()
        return Triple(auth, client, AO3WorkFormRepository(client.authenticated(auth), auth, parseDispatcher = Dispatchers.Unconfined))
    }
}

private class WorkFormMemoryClient : AO3Client {
    val gets = mutableListOf<String>()
    val headers = mutableListOf<Map<String, String>>()
    var beforeResponse: suspend () -> Unit = {}
    var body: String? = null
    var failure: AO3Error? = null
    override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        gets += url; this.headers += headers
        beforeResponse()
        failure?.let { return AO3Result.Failure(it) }
        val fixture = when {
            url.endsWith("/995001/edit") -> "ao3_demo_work_draft_edit"
            url.endsWith("/995006/edit") -> "ao3_demo_work_posted_edit"
            else -> "ao3_work_new_draft"
        }
        return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), body ?: workFixture(fixture)))
    }

    fun authenticated(auth: AO3AuthRepository) = DefaultAO3AuthenticatedClient(this, object : AO3FormPostClient {
        override suspend fun postForm(url: String, formFields: List<Pair<String, String>>, headers: Map<String, String>): AO3Result<AO3HttpResponse> =
            error("Work form foundations must never POST")
    }, auth)
}
