package io.github.cidy02.kudos.network.ao3

import io.github.cidy02.kudos.auth.*
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class CachedAO3SessionTest {
    private val session = AO3Session("Reader", listOf(AO3StoredCookie(AO3StoredCookie.SessionCookieName, "local-test")))
    private class Store(var saved: AO3Session?) : AO3SessionStore {
        override suspend fun load() = saved
        override suspend fun save(session: AO3Session) { saved = session }
        override suspend fun delete(): Boolean { saved = null; return true }
        override suspend fun isRemovalPending() = false
        override suspend fun markRemovalPending() { }
        override suspend fun clearRemovalPending() { }
    }
    private val cookies = object : AO3CookieStore {
        override suspend fun captureSession(username: String): AO3Session? = null
        override suspend fun install(session: AO3Session) { }
        override suspend fun clear() { }
    }
    private fun seed(generation: Int): AO3PageCache.Key {
        val key = AO3PageCache.Key("https://archiveofourown.org/users/Writer",
            AO3PageCache.Scope("Reader", generation), AO3PageCache.Kind.Dashboard)
        AO3PageCache.shared.insert(key, AO3HttpResponse(key.url, 200, emptyMap(), "private"))
        return key
    }

    @Test fun actualLogoutRemovesEvenTheOriginalKey() = runBlocking<Unit> {
        val auth = AO3AuthRepository(Store(session), cookies)
        auth.restoreSession()
        val key = seed(auth.generation.value)
        auth.logout()
        assertNull(AO3PageCache.shared.value(key, stale = true))
        assertNull(auth.username())
    }

    @Test fun sameUsernameSessionRefreshRemovesEvenTheOriginalKey() = runBlocking<Unit> {
        val auth = AO3AuthRepository(Store(session), cookies,
            sessionValidator = AO3SessionValidating { AO3SessionValidation.Valid(it) })
        auth.restoreSession()
        val generation = auth.generation.value
        val key = seed(generation)
        auth.verifySession()
        assertEquals("Reader", auth.username())
        assertTrue(auth.generation.value > generation)
        assertNull(AO3PageCache.shared.value(key, stale = true))
    }
}
