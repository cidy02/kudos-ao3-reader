package io.github.cidy02.kudos.writing

import io.github.cidy02.kudos.auth.*
import io.github.cidy02.kudos.network.ao3.AO3Error
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

import io.github.cidy02.kudos.network.ao3.writes.DefaultAO3AuthenticatedClient

@OptIn(ExperimentalCoroutinesApi::class)
class WritingChaptersStateTest {
    
    @Test
    fun oneReadPerOpeningAndNoneAfter() = runTest {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
        auth.restoreSession()
        val baseClient = WorkFormScreenClient()
        val client = DefaultAO3AuthenticatedClient(baseClient, baseClient, auth)
        val scope = TestScope(StandardTestDispatcher(testScheduler))
        
        val model = WritingChaptersState(995006L, client, auth, scope)
        advanceUntilIdle()
        
        assertEquals(1, baseClient.gets.size)
        assertEquals("https://archiveofourown.org/works/995006/navigate", baseClient.gets.first())
        val chapters = model.state.value.chapters
        assertEquals(2, chapters?.size)
        assertEquals("Chapter 1", chapters?.get(0)?.displayName)
        assertEquals("2026-10-01", chapters?.get(0)?.dateText)
        
        // No extra read without reload
        model.state // just accessing
        advanceUntilIdle()
        assertEquals(1, baseClient.gets.size)
    }

    @Test
    fun failedRead() = runTest {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
        auth.restoreSession()
        val baseClient = WorkFormScreenClient()
        baseClient.failure = AO3Error.ParseError("test parse error")
        val client = DefaultAO3AuthenticatedClient(baseClient, baseClient, auth)
        val scope = TestScope(StandardTestDispatcher(testScheduler))
        
        val model = WritingChaptersState(424242L, client, auth, scope)
        advanceUntilIdle()
        
        assertEquals(1, baseClient.gets.size)
        assertNull(model.state.value.chapters)
        assertEquals("AO3's page format wasn't what the app expected.", model.state.value.errorMessage)
        
        baseClient.failure = null
        model.reload()
        advanceUntilIdle()
        
        assertEquals(2, baseClient.gets.size)
        assertEquals(3, model.state.value.chapters?.size)
        assertNull(model.state.value.errorMessage)
    }

    @Test
    fun signedOut() = runTest {
        val auth = AO3AuthRepository(MemorySessionStore(null), MemoryCookieStore())
        auth.restoreSession()
        val baseClient = WorkFormScreenClient()
        val client = DefaultAO3AuthenticatedClient(baseClient, baseClient, auth)
        val scope = TestScope(StandardTestDispatcher(testScheduler))
        
        val model = WritingChaptersState(995006L, client, auth, scope)
        advanceUntilIdle()
        
        assertEquals(0, baseClient.gets.size)
        assertEquals("Log in to AO3 first.", model.state.value.errorMessage)
    }
}
