package io.github.cidy02.kudos.auth

import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import java.nio.file.Files
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AO3SessionStoreTest {
    @Test
    fun savesLoadsAndDeletesSessionFile() = runTest {
        val directory = Files.createTempDirectory("kudos-session-test").toFile()
        val store = FileAO3SessionStore(directory.resolve("session.json"))
        val session = testSession()

        store.save(session)
        assertEquals(session, store.load())

        store.delete()
        assertNull(store.load())
    }

    @Test
    fun corruptSessionFileIsDeletedAndTreatedAsSignedOut() = runTest {
        val directory = Files.createTempDirectory("kudos-session-corrupt-test").toFile()
        val file = directory.resolve("session.json")
        file.writeText("not json")

        val store = FileAO3SessionStore(file)

        assertNull(store.load())
        assertFalse(file.exists())
    }
}

class AO3CookieStoreTest {
    @Test
    fun parsesCookieManagerHeaderIntoAo3Cookies() {
        val cookies = AndroidAO3CookieStore.parseCookieHeader(
            "_otwarchive_session=secret; viewed_adult=true; malformed"
        )

        assertEquals(2, cookies.size)
        assertEquals("_otwarchive_session", cookies[0].name)
        assertEquals("secret", cookies[0].value)
        assertTrue(cookies.all { it.domain == ".archiveofourown.org" })
    }
}

class AO3CookieJarTest {
    @Test
    fun attachesCookiesOnlyForSecureAo3HostsAndMatchingPaths() {
        val clock = Clock.fixed(Instant.parse("2026-06-27T12:00:00Z"), ZoneOffset.UTC)
        val session = AO3Session(
            username = "AO3_Reader",
            cookies = listOf(
                AO3StoredCookie(name = "_otwarchive_session", value = "secret"),
                AO3StoredCookie(name = "pref", value = "works", path = "/works"),
                AO3StoredCookie(
                    name = "old",
                    value = "expired",
                    expiresAtEpochMillis = Instant.parse("2026-06-27T11:00:00Z").toEpochMilli()
                )
            )
        )
        val jar = AO3CookieJar(clock)

        assertEquals(
            "pref=works; _otwarchive_session=secret",
            jar.cookieHeader(session, "${AO3Constants.BASE_URL}/works/123")
        )
        assertEquals(
            "_otwarchive_session=secret",
            jar.cookieHeader(session, "${AO3Constants.BASE_URL}/users/AO3_Reader/readings")
        )
        assertNull(jar.cookieHeader(session, "https://example.com/works/123"))
        assertNull(jar.cookieHeader(session, "http://archiveofourown.org/works/123"))
    }
}

class AO3AuthenticatedRequestTest {
    @Test
    fun repositoryBuildsAuthenticatedHeadersForAo3Only() = runTest {
        val store = MemorySessionStore(testSession())
        val cookies = MemoryCookieStore()
        val repository = AO3AuthRepository(store, cookies)

        repository.restoreSession()

        val headers = (
            repository.authenticatedHeaders("${AO3Constants.BASE_URL}/users/AO3_Reader/bookmarks")
                as AO3Result.Success
            ).value
        assertTrue(headers.getValue("Cookie").contains("_otwarchive_session=secret"))
        assertEquals(
            AO3Error.AuthenticationRequired,
            (repository.authenticatedHeaders("https://example.com/") as AO3Result.Failure).error
        )
    }
}

class AO3WebLoginInspectionTest {
    @Test
    fun parsesWebViewInspectionJsonResult() {
        val inspection = AO3WebLoginInspection.parseJavascriptResult(
            "\"{\\\"loggedIn\\\":true,\\\"username\\\":\\\"AO3_Reader\\\"}\""
        )

        assertTrue(inspection.loggedIn)
        assertEquals("AO3_Reader", inspection.username)
    }
}

class AccountLogoutTest {
    @Test
    fun logoutClearsStoredAndWebSessionsWithoutLocalLibraryDependency() = runTest {
        val store = MemorySessionStore(testSession())
        val cookies = MemoryCookieStore()
        val repository = AO3AuthRepository(store, cookies)

        repository.restoreSession()
        repository.logout()

        assertNull(store.session)
        assertTrue(cookies.cleared)
        assertEquals(AO3AuthState.SignedOut, repository.state.value)
    }
}

internal fun testSession(username: String = "AO3_Reader"): AO3Session {
    return AO3Session(
        username = username,
        cookies = listOf(AO3StoredCookie(name = AO3StoredCookie.SessionCookieName, value = "secret"))
    )
}

internal class MemorySessionStore(
    var session: AO3Session? = null
) : AO3SessionStore {
    override suspend fun load(): AO3Session? = session
    override suspend fun save(session: AO3Session) {
        this.session = session
    }
    override suspend fun delete() {
        session = null
    }
}

internal class MemoryCookieStore(
    var capturedSession: AO3Session? = testSession()
) : AO3CookieStore {
    var installed: AO3Session? = null
    var cleared: Boolean = false

    override suspend fun captureSession(username: String): AO3Session? {
        return capturedSession?.copy(username = username)
    }

    override suspend fun install(session: AO3Session) {
        installed = session
    }

    override suspend fun clear() {
        cleared = true
    }
}
