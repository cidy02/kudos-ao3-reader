package io.github.cidy02.kudos.account

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.ViewModelStore
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.MemoryCookieStore
import io.github.cidy02.kudos.auth.MemorySessionStore
import io.github.cidy02.kudos.auth.testSession
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

class AO3CollectionReturnStateTest {
    private class Client : AO3Client, AO3AuthenticatedClient {
        val reads = mutableListOf<String>()
        var failure: AO3Error? = null
        var beforeResponse: suspend () -> Unit = {}
        override fun username() = "AO3_Reader"
        override fun sessionGeneration() = 1
        override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
            reads += url
            beforeResponse()
            failure?.let { return AO3Result.Failure(it) }
            val fixture = when {
                url.contains("/bookmarks") -> "ao3_demo_collection_bookmarks"
                url.contains("/people") -> "ao3_demo_collection_people"
                url.contains("/works") -> "ao3_tag_works"
                else -> "ao3_collection_show"
            }
            return challengeResponse(url, challengeFixture(fixture))
        }
        override suspend fun getAuthenticated(url: String) = get(url, emptyMap())
        override suspend fun postAuthenticated(url: String, formFields: List<Pair<String, String>>,
            headers: Map<String, String>): AO3Result<AO3HttpResponse> = error("Back must never write")
    }

    @Test fun returningKeepsSegmentPageAndScrollObjectAndOnlyPullOrConfirmedChangeReadsAgain() = runTest {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
        auth.restoreSession()
        val client = Client()
        val repository = AO3CollectionDetailRepository(client, auth, parseDispatcher = Dispatchers.Unconfined)
        val store = ViewModelStore()
        val provider = ViewModelProvider(store, object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: Class<T>): T = AO3CollectionDetailViewModel("winter_exchange", repository) as T
        })
        val model = provider["detail", AO3CollectionDetailViewModel::class.java]
        model.loadOnAppear()
        assertEquals(2, client.reads.size) // Profile, selected works only.
        model.segment.value = AO3CollectionSegment.Bookmarks
        model.loadOnAppear()
        model.load(AO3CollectionSegment.Bookmarks, 2)
        val shown = model.bookmarksPage
        assertNotNull(shown)
        val beforeReturn = client.reads.size
        val returned = provider["detail", AO3CollectionDetailViewModel::class.java]
        assertSame(model, returned)
        assertSame(model.listState, returned.listState)
        returned.loadOnAppear()
        assertEquals(beforeReturn, client.reads.size)
        assertEquals(AO3CollectionSegment.Bookmarks, returned.segment.value)
        assertSame(shown, returned.bookmarksPage)
        assertEquals(2, returned.currentPage(AO3CollectionSegment.Bookmarks))

        repository.collectionChanged("winter_exchange")
        returned.loadOnAppear(repository.collectionRevision("winter_exchange"))
        assertEquals(beforeReturn + 1, client.reads.size)
        returned.loadOnAppear(repository.collectionRevision("winter_exchange"))
        assertEquals(beforeReturn + 1, client.reads.size)
        returned.refresh()
        assertEquals(beforeReturn + 2, client.reads.size)
        store.clear()
    }

    @Test fun aSettledFailureIsNotRetriedByBack() = runTest {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
        auth.restoreSession()
        val client = Client().also { it.failure = AO3Error.Network("offline") }
        val model = AO3CollectionDetailViewModel("winter_exchange",
            AO3CollectionDetailRepository(client, auth, parseDispatcher = Dispatchers.Unconfined))
        model.loadOnAppear()
        model.loadOnAppear()
        assertEquals(1, client.reads.size)
        assertTrue(model.phase is AO3CollectionDetailPhase.Failed)
    }

    @Test fun aSessionThatEndsDuringTheHeaderReadCannotInstallItOrReadASegment() = runTest {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
        auth.restoreSession()
        val entered = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        val client = Client().also { it.beforeResponse = { entered.complete(Unit); release.await() } }
        val model = AO3CollectionDetailViewModel("winter_exchange",
            AO3CollectionDetailRepository(client, auth, parseDispatcher = Dispatchers.Unconfined))
        val load = async { model.loadOnAppear() }
        entered.await()
        auth.logout()
        release.complete(Unit)
        assertTrue(runCatching { load.await() }.isFailure)
        assertNull(model.show)
        assertEquals(1, client.reads.size)
        model.loadOnAppear()
        assertEquals(1, client.reads.size)
    }

    @Test fun aKeptSettingsHubOnlyReadsAgainAfterAConfirmedNestedChange() = runTest {
        val (_, client, repo) = challengeSetup()
        val model = AO3ChallengeSettingsState("winter_exchange", repo)
        model.loadOnAppear()
        val shown = model.state.value.data
        assertNotNull(shown)
        val before = client.gets.size
        model.close()
        model.loadOnAppear()
        assertSame(shown, model.state.value.data)
        assertEquals(before, client.gets.size)
        repo.collectionChanged("winter_exchange")
        model.close()
        model.loadOnAppear()
        assertEquals(before * 2, client.gets.size)
        model.close()
        model.loadOnAppear()
        assertEquals(before * 2, client.gets.size)
    }

    @Test fun relatedRouteModelsKeepSettledFailuresRatherThanReadingAgainOnReturn() = runTest {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
        auth.restoreSession()
        val client = Client().also { it.failure = AO3Error.Network("offline") }
        val repo = AO3CollectionDetailRepository(client, auth, parseDispatcher = Dispatchers.Unconfined)
        val writes = AO3WriteRepository(client)
        suspend fun check(open: suspend () -> Unit, close: () -> Unit) {
            open()
            val reads = client.reads.size
            close()
            open()
            assertEquals(reads, client.reads.size)
        }
        AO3ChallengeSettingsState("winter_exchange", repo).let { check(it::loadOnAppear, it::close) }
        AO3CollectionMaintainersState("winter_exchange", repo, writes).let { check(it::loadOnAppear, it::close) }
        AO3CollectionModerationState("winter_exchange", true, repo, writes).let { check(it::loadOnAppear, it::close) }
        AO3PromptMemeState("winter_exchange", repo, false, writes).let { check(it::loadOnAppear, it::close) }
        AO3TagSetState(42, repo, writes).let { check(it::loadOnAppear, it::close) }
        AO3ChallengeSignUpsState("winter_exchange", true, true, repo).let { check(it::loadOnAppear, it::close) }
        AO3ChallengeAssignmentsState("winter_exchange", true, true, true, repo, writes).let { check(it::loadOnAppear, it::close) }
        AO3ChallengeSignUpState("winter_exchange", 1, repo, writes).let { check(it::loadOnAppear, it::close) }
        AO3CollectionFormState("winter_exchange", repo, writes, this).let { check(it::loadOnAppear, it::close) }
    }
}
