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

/**
 * On-demand [AO3AuthRepository.verifySession] — same valid / expired / transient
 * branches as restore, plus [AO3SessionHealth] transitions.
 */
class AO3VerifySessionTest {
    @Test
    fun verifySessionValidMarksHealthyAndKeepsSignedIn() = runTest {
        val session = testSession("AO3_Reader")
        val store = MemorySessionStore(session)
        val cookies = MemoryCookieStore()
        val repository = AO3AuthRepository(
            sessionStore = store,
            cookieStore = cookies,
            sessionValidator = FixedValidator(AO3SessionValidation.Valid(session))
        )
        repository.restoreSession()
        assertEquals(AO3AuthState.SignedIn("AO3_Reader"), repository.state.value)
        assertTrue(repository.sessionHealth.value is AO3SessionHealth.Healthy)

        repository.verifySession()

        assertEquals(AO3AuthState.SignedIn("AO3_Reader"), repository.state.value)
        assertTrue(repository.sessionHealth.value is AO3SessionHealth.Healthy)
        assertEquals(session, store.session)
    }

    @Test
    fun verifySessionExpiredClearsSession() = runTest {
        val session = testSession("AO3_Reader")
        val store = MemorySessionStore(session)
        val cookies = MemoryCookieStore()
        val sequence = SequenceValidator(
            first = AO3SessionValidation.Valid(session),
            rest = AO3SessionValidation.Expired
        )
        val repository = AO3AuthRepository(
            sessionStore = store,
            cookieStore = cookies,
            sessionValidator = sequence
        )
        repository.restoreSession()
        assertEquals(AO3AuthState.SignedIn("AO3_Reader"), repository.state.value)
        assertTrue(repository.sessionHealth.value is AO3SessionHealth.Healthy)

        repository.verifySession()

        assertTrue(repository.state.value is AO3AuthState.Expired)
        assertEquals(AO3SessionHealth.Expired, repository.sessionHealth.value)
        assertNull(store.session)
        assertTrue(cookies.cleared)
        assertNull(repository.username())
    }

    @Test
    fun verifySessionTransientKeepsSessionAndMarksUnreachable() = runTest {
        val session = testSession("AO3_Reader")
        val store = MemorySessionStore(session)
        val cookies = MemoryCookieStore()
        val sequence = SequenceValidator(
            first = AO3SessionValidation.Valid(session),
            throwOnRest = IOException("offline")
        )
        val repository = AO3AuthRepository(
            sessionStore = store,
            cookieStore = cookies,
            sessionValidator = sequence
        )
        repository.restoreSession()
        assertEquals(AO3AuthState.SignedIn("AO3_Reader"), repository.state.value)

        repository.verifySession()

        assertEquals(AO3AuthState.SignedIn("AO3_Reader"), repository.state.value)
        assertEquals(AO3SessionHealth.Unreachable, repository.sessionHealth.value)
        assertEquals(session, store.session)
        assertEquals(session, cookies.installed)
    }

    @Test
    fun verifySessionWhenSignedOutIsNoOpUnknown() = runTest {
        val repository = AO3AuthRepository(
            sessionStore = MemorySessionStore(null),
            cookieStore = MemoryCookieStore(),
            sessionValidator = FixedValidator(AO3SessionValidation.Expired)
        )
        repository.restoreSession()
        assertEquals(AO3AuthState.SignedOut, repository.state.value)

        repository.verifySession()

        assertEquals(AO3AuthState.SignedOut, repository.state.value)
        assertEquals(AO3SessionHealth.Unknown, repository.sessionHealth.value)
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

/**
 * First [validate] returns [first]; subsequent calls return [rest] or throw [throwOnRest].
 * Used to exercise restore-then-verifySession sequences with different outcomes.
 */
private class SequenceValidator(
    private val first: AO3SessionValidation,
    private val rest: AO3SessionValidation? = null,
    private val throwOnRest: Exception? = null
) : AO3SessionValidating {
    private var calls = 0

    override suspend fun validate(session: AO3Session): AO3SessionValidation {
        calls += 1
        if (calls == 1) return first
        throwOnRest?.let { throw it }
        return rest ?: first
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
