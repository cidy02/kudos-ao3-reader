package io.github.cidy02.kudos.auth

import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import java.io.IOException
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AO3SessionRestoreValidationTest {
    @Test
    fun restoreKeepsSessionWhenValidatorSaysValid() = runTest {
        val session = testSession("AO3_Reader")
        val store = MemorySessionStore(session)
        val cookies = MemoryCookieStore()
        val repository = AO3AuthRepository(
            sessionStore = store,
            cookieStore = cookies,
            sessionValidator = FixedValidator(AO3SessionValidation.Valid(session.copy(username = "AO3_Reader")))
        )

        repository.restoreSession()

        assertEquals(AO3AuthState.SignedIn("AO3_Reader"), repository.state.value)
        assertEquals(session, store.session)
        assertEquals(session, cookies.installed)
    }

    @Test
    fun restoreClearsSessionWhenClearlyLoggedOut() = runTest {
        val session = testSession("AO3_Reader")
        val store = MemorySessionStore(session)
        val cookies = MemoryCookieStore()
        val repository = AO3AuthRepository(
            sessionStore = store,
            cookieStore = cookies,
            sessionValidator = FixedValidator(AO3SessionValidation.Expired)
        )

        repository.restoreSession()

        assertTrue(repository.state.value is AO3AuthState.Expired)
        assertNull(store.session)
        assertTrue(cookies.cleared)
        assertNull(repository.username())
    }

    @Test
    fun restoreKeepsSessionWhenValidationNetworkFails() = runTest {
        val session = testSession("AO3_Reader")
        val store = MemorySessionStore(session)
        val cookies = MemoryCookieStore()
        val repository = AO3AuthRepository(
            sessionStore = store,
            cookieStore = cookies,
            sessionValidator = FailingValidator(IOException("offline"))
        )

        repository.restoreSession()

        assertEquals(AO3AuthState.SignedIn("AO3_Reader"), repository.state.value)
        assertEquals(session, store.session)
        assertEquals(session, cookies.installed)
    }

    @Test
    fun restoreWithoutValidatorSignsInFromDisk() = runTest {
        val session = testSession()
        val repository = AO3AuthRepository(
            sessionStore = MemorySessionStore(session),
            cookieStore = MemoryCookieStore(),
            sessionValidator = null
        )

        repository.restoreSession()

        assertEquals(AO3AuthState.SignedIn(session.username), repository.state.value)
    }

    @Test
    fun restoreSavesRefreshedSessionFromValidator() = runTest {
        val session = testSession("old_name")
        val refreshed = testSession("fresh_name").copy(
            cookies = listOf(
                AO3StoredCookie(name = AO3StoredCookie.SessionCookieName, value = "rotated")
            )
        )
        val store = MemorySessionStore(session)
        val cookies = MemoryCookieStore()
        val repository = AO3AuthRepository(
            sessionStore = store,
            cookieStore = cookies,
            sessionValidator = FixedValidator(AO3SessionValidation.Valid(refreshed))
        )

        repository.restoreSession()

        assertEquals(AO3AuthState.SignedIn("fresh_name"), repository.state.value)
        assertEquals(refreshed, store.session)
        assertEquals(refreshed, cookies.installed)
        assertTrue(
            (
                repository.authenticatedHeaders("https://archiveofourown.org/")
                    as AO3Result.Success
                ).value.getValue("Cookie").contains("rotated")
        )
    }
}

class LiveAO3SessionValidatorTest {
    @Test
    fun validLoggedInFixtureKeepsSession() = runTest {
        val html = resourceText("ao3/account/logged_in.html")
        val client = FixedGetClient(
            AO3Result.Success(
                AO3HttpResponse(
                    url = "https://archiveofourown.org/",
                    statusCode = 200,
                    headers = emptyMap(),
                    body = html
                )
            )
        )
        val validator = LiveAO3SessionValidator(client)
        val session = testSession("stale_name")

        val result = validator.validate(session)

        val valid = result as AO3SessionValidation.Valid
        assertEquals("AO3 Reader", valid.session.username)
        assertTrue(valid.session.hasSessionCookie())
    }

    @Test
    fun loggedOutFixtureExpiresSession() = runTest {
        val html = resourceText("ao3/account/login_required.html")
        val client = FixedGetClient(
            AO3Result.Success(
                AO3HttpResponse(
                    url = "https://archiveofourown.org/",
                    statusCode = 200,
                    headers = emptyMap(),
                    body = html
                )
            )
        )
        val validator = LiveAO3SessionValidator(client)

        assertEquals(
            AO3SessionValidation.Expired,
            validator.validate(testSession())
        )
    }

    @Test
    fun nonAo3PageThrowsSoCallerKeepsSession() = runTest {
        val client = FixedGetClient(
            AO3Result.Success(
                AO3HttpResponse(
                    url = "https://archiveofourown.org/",
                    statusCode = 200,
                    headers = emptyMap(),
                    body = "<html><body><div id=\"main\">challenge wall</div></body></html>"
                )
            )
        )
        val validator = LiveAO3SessionValidator(client)

        try {
            validator.validate(testSession())
            throw AssertionError("expected IOException")
        } catch (error: IOException) {
            assertTrue(error.message!!.contains("did not look like an AO3 page"))
        }
    }

    @Test
    fun networkFailureThrowsSoCallerKeepsSession() = runTest {
        val client = FixedGetClient(
            AO3Result.Failure(AO3Error.Network("offline"))
        )
        val validator = LiveAO3SessionValidator(client)

        try {
            validator.validate(testSession())
            throw AssertionError("expected IOException")
        } catch (error: IOException) {
            assertTrue(error.message!!.contains("unavailable"))
        }
    }

    @Test
    fun authenticationRequiredMapsToExpired() = runTest {
        val client = FixedGetClient(
            AO3Result.Failure(AO3Error.AuthenticationRequired)
        )
        val validator = LiveAO3SessionValidator(client)

        assertEquals(AO3SessionValidation.Expired, validator.validate(testSession()))
    }

    @Test
    fun mergesSetCookieFromValidationResponse() = runTest {
        val html = resourceText("ao3/account/logged_in.html")
        val client = FixedGetClient(
            AO3Result.Success(
                AO3HttpResponse(
                    url = "https://archiveofourown.org/",
                    statusCode = 200,
                    headers = mapOf(
                        "Set-Cookie" to listOf("_otwarchive_session=rotated-from-ao3; path=/; secure")
                    ),
                    body = html
                )
            )
        )
        val validator = LiveAO3SessionValidator(client)
        val result = validator.validate(testSession()) as AO3SessionValidation.Valid

        assertTrue(
            result.session.cookies.any {
                it.name == AO3StoredCookie.SessionCookieName && it.value == "rotated-from-ao3"
            }
        )
    }
}

private class FixedValidator(
    private val result: AO3SessionValidation
) : AO3SessionValidating {
    override suspend fun validate(session: AO3Session): AO3SessionValidation = result
}

private class FailingValidator(
    private val error: Exception
) : AO3SessionValidating {
    override suspend fun validate(session: AO3Session): AO3SessionValidation {
        throw error
    }
}

private class FixedGetClient(
    private val result: AO3Result<AO3HttpResponse>
) : AO3Client {
    override suspend fun get(
        url: String,
        headers: Map<String, String>
    ): AO3Result<AO3HttpResponse> = result
}

private fun resourceText(path: String): String {
    val resource = Thread.currentThread().contextClassLoader?.getResource(path)
        ?: error("Missing test resource: $path")
    return resource.readText()
}
