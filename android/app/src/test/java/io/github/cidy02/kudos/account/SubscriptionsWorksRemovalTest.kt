package io.github.cidy02.kudos.account

import android.app.Application
import androidx.lifecycle.ViewModelStore
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.MemoryCookieStore
import io.github.cidy02.kudos.auth.MemorySessionStore
import io.github.cidy02.kudos.auth.testSession
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.works.WorkRepository
import java.nio.file.Files
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class SubscriptionsWorksRemovalTest {
    @Test fun confirmedRemovalDropsWorkAndActionAndLoadsPrecedingPageOnlyWhenEmptied() = runTest {
        Dispatchers.setMain(UnconfinedTestDispatcher(testScheduler))
        val context = ApplicationProvider.getApplicationContext<Application>()
        val database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java).allowMainThreadQueries().build()
        val folder = Files.createTempDirectory("subscriptions-removal")
        val store = ViewModelStore()
        try {
            val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
            auth.restoreSession()
            val requests = mutableListOf<Int>()
            val client = object : AO3Client {
                override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
                    val page = url.toHttpUrl().queryParameter("page")?.toInt() ?: 1
                    requests += page
                    val id = if (page == 2) 456 else 123
                    val html = """<dl class='subscription'><dt><a href='/works/$id'>Work $id</a></dt>
                        <dd><form action='/users/me/subscriptions/$id'></form></dd></dl>
                        <ol class='pagination'><li>1</li><li>2</li></ol>"""
                    return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), html))
                }
            }
            val model = AccountListViewModel(AccountListType.Subscriptions, AccountListRepository(client, auth),
                WorkRepository(database, WorkFileStore(folder)))
            store.put("subscriptions", model)
            backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.uiState.collect() }
            model.uiState.first { it is AccountListUiState.Loaded }
            model.load(2)
            model.uiState.first { it is AccountListUiState.Loaded && it.page.currentPage == 2 }
            model.removeSubscription(456, 2)
            val steppedBack = model.uiState.first {
                it is AccountListUiState.Loaded && it.page.currentPage == 1
            } as AccountListUiState.Loaded
            assertEquals(listOf(1, 2, 1), requests)
            assertEquals(listOf(123L), steppedBack.page.works.map { it.id })
            assertFalse(steppedBack.page.unsubscribePaths.containsKey(456L))
            model.removeSubscription(123, 1)
            val empty = model.uiState.first { it is AccountListUiState.Loaded && it.page.works.isEmpty() } as AccountListUiState.Loaded
            assertTrue(empty.page.unsubscribePaths.isEmpty())
            assertEquals(listOf(1, 2, 1), requests)
        } finally {
            store.clear()
            database.close()
            folder.toFile().deleteRecursively()
            Dispatchers.resetMain()
        }
    }
}
