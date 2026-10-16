package io.github.cidy02.kudos.auth

import io.github.cidy02.kudos.network.ao3.AO3Result
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** A61 #1 and #3: a web login that is left or cannot be saved leaves no half-signed-in state. */
@OptIn(ExperimentalCoroutinesApi::class)
class AO3WebLoginAcceptTest {
    @Test fun aSessionThatCannotBeSavedSecurelyIsAnErrorNotACrash() = runTest {
        val store = object : AO3SessionStore by MemorySessionStore() {
            override suspend fun save(session: AO3Session) = throw IllegalStateException("Keystore unavailable")
        }
        val cookies = MemoryCookieStore()
        val repository = AO3AuthRepository(store, cookies)
        val result = repository.acceptWebLogin("AO3_Reader")
        assertTrue(result is AO3Result.Failure)
        assertTrue(repository.state.value is AO3AuthState.Error)
        assertNull(repository.username())
        assertTrue("the web view's login does not linger", cookies.cleared)
    }

    @Test fun aLoginLeftWhileItsCookiesAreReadIsNotLeftSigningIn() = runTest {
        val held = CompletableDeferred<Unit>()
        val cookies = object : AO3CookieStore by MemoryCookieStore() {
            override suspend fun captureSession(username: String): AO3Session? { held.await(); return testSession(username) }
        }
        val store = MemorySessionStore()
        val repository = AO3AuthRepository(store, cookies)
        val login = launch { repository.acceptWebLogin("AO3_Reader") }
        runCurrent()
        assertEquals(AO3AuthState.SigningIn, repository.state.value)
        login.cancel(); runCurrent()
        assertEquals(AO3AuthState.SignedOut, repository.state.value)
        assertNull(store.session)
    }
}
