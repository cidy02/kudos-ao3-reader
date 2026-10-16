package io.github.cidy02.kudos.auth

import android.app.Application
import android.webkit.CookieManager
import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import java.nio.file.Files
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// Ports CookieAllowListTests at the actual capture/install/merge/persistence boundaries.
class AO3CookieAllowListTest {
    private fun mixedSession() = AO3Session("AO3_Reader", listOf(
        AO3StoredCookie(AO3StoredCookie.SessionCookieName, "session"),
        AO3StoredCookie("user_credentials", "remember"),
        AO3StoredCookie("_ga", "analytics"),
        AO3StoredCookie("viewed_adult", "true"),
        AO3StoredCookie("user_credentials", "foreign", domain = "evil.example")
    ))

    @Test
    fun responseCookiesDropOffDomainAndNonIdentityCookies() {
        val cookies = AndroidAO3CookieStore.parseSetCookieHeaders(setCookieLines = listOf(
            "_otwarchive_session=fresh; Path=/users; Secure; HttpOnly",
            "user_credentials=remember; Path=/; Secure",
            "_ga=drop; Path=/; Secure",
            "viewed_adult=true; Path=/; Secure",
            "user_credentials=foreign; Domain=evil.example; Path=/; Secure"
        ))
        assertEquals(AO3StoredCookie.IdentityCookieNames, cookies.map { it.name }.toSet())
        assertEquals("/users", cookies.first().path)
        assertTrue(cookies.first().isSecure)
        assertTrue(cookies.first().isHttpOnly)
        assertFalse(cookies.any { it.value == "foreign" })
    }

    @Test
    fun onlyAllowListedCookiesArePersisted() = runTest {
        val directory = Files.createTempDirectory("kudos-cookie-allow-list").toFile()
        try {
            val file = java.io.File(directory, "session.json")
            val store = FileAO3SessionStore(file)
            store.save(mixedSession())
            val written = Json.decodeFromString(AO3Session.serializer(), file.readText())
            assertEquals(AO3StoredCookie.IdentityCookieNames, written.cookies.map { it.name }.toSet())
            assertFalse(file.readText().contains("analytics"))
            assertFalse(file.readText().contains("foreign"))
            assertEquals(written, store.load())
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun legacyStoredCookiesAreFilteredBeforeUse() = runTest {
        val directory = Files.createTempDirectory("kudos-cookie-legacy").toFile()
        try {
            val file = java.io.File(directory, "session.json")
            file.writeText(Json.encodeToString(AO3Session.serializer(), mixedSession()))
            val loaded = FileAO3SessionStore(file).load()!!
            assertEquals(AO3StoredCookie.IdentityCookieNames, loaded.cookies.map { it.name }.toSet())
            assertEquals("_otwarchive_session=session; user_credentials=remember",
                AO3CookieJar().cookieHeader(loaded, AO3Constants.BASE_URL))
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun mergingPrunesOldAndResponseNonIdentityCookiesEvenWithoutAnIdentityRefresh() {
        for (headers in listOf(emptyList(), listOf(
            "_ga=new-tracker; Path=/; Secure",
            "viewed_adult=true; Path=/; Secure"
        ), listOf(
            "_otwarchive_session=rotated; Path=/; Secure; HttpOnly",
            "_ga=new-tracker; Path=/; Secure"
        ))) {
            val merged = LiveAO3SessionValidator.mergingResponseCookies(mixedSession(),
                AO3HttpResponse(AO3Constants.BASE_URL, 200, mapOf("Set-Cookie" to headers), ""), "AO3_Reader")
            assertEquals(AO3StoredCookie.IdentityCookieNames, merged.cookies.map { it.name }.toSet())
            assertFalse(merged.cookies.any { it.value == "foreign" })
            assertEquals("remember", merged.cookies.single { it.name == "user_credentials" }.value)
            if (headers.any { it.startsWith("_otwarchive_session=") }) {
                assertEquals("rotated", merged.cookies.single { it.name == AO3StoredCookie.SessionCookieName }.value)
            }
        }
    }

    @Test
    fun authRepositoryFiltersBeforeSavingAndInstallingAnAcceptedSession() = runTest {
        val store = MemorySessionStore(null)
        val cookies = MemoryCookieStore(mixedSession())
        val repository = AO3AuthRepository(store, cookies)
        repository.acceptWebLogin("AO3_Reader")
        assertEquals(AO3StoredCookie.IdentityCookieNames, store.load()!!.cookies.map { it.name }.toSet())
        assertEquals(store.load(), cookies.installed)
    }
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class AO3CookieBridgeAllowListTest {
    private val manager get() = CookieManager.getInstance()

    @Before
    fun prepareCookies() {
        manager.removeAllCookies(null)
        manager.setAcceptCookie(true)
    }

    @After
    fun removeTestCookies() {
        manager.removeAllCookies(null)
        manager.flush()
    }

    @Test
    fun captureAO3CookiesFiltersNonIdentity() = runTest {
        for (pair in listOf("_otwarchive_session=session", "user_credentials=remember", "_ga=tracker", "viewed_adult=true")) {
            manager.setCookie(AO3Constants.BASE_URL, "$pair; Path=/; Secure")
        }
        assertTrue(manager.getCookie(AO3Constants.BASE_URL).contains("_ga=tracker"))
        val session = AndroidAO3CookieStore(manager).captureSession("AO3_Reader")!!
        assertEquals(AO3StoredCookie.IdentityCookieNames, session.cookies.map { it.name }.toSet())
    }

    // Port of AO3AuthTests.logoutClearsPersistedAndWebSessions, using the real bridge.
    @Test
    fun logoutClearsPersistedAndWebSessions() = runTest {
        val session = AO3Session("AO3_Reader", listOf(
            AO3StoredCookie(AO3StoredCookie.SessionCookieName, "session")
        ))
        val store = MemorySessionStore(session)
        val repository = AO3AuthRepository(store, AndroidAO3CookieStore(manager))
        repository.restoreSession()
        val scopedUrls = listOf(
            "${AO3Constants.BASE_URL}/users/AO3_Reader/readings",
            "https://www.archiveofourown.org/works/123"
        )
        manager.setCookie(scopedUrls[0], "user_credentials=path; Path=/users; Secure; HttpOnly")
        manager.setCookie(scopedUrls[1], "user_credentials=subdomain; Path=/works; Secure; HttpOnly")
        assertTrue(manager.getCookie(scopedUrls[0]).contains("user_credentials=path"))
        assertTrue(manager.getCookie(scopedUrls[1]).contains("user_credentials=subdomain"))

        repository.logout()

        assertEquals(AO3AuthState.SignedOut, repository.state.value)
        assertEquals("Logged out of AO3.", repository.noticeMessage.value)
        assertNull(store.load())
        assertFalse(store.isRemovalPending())
        assertNull(repository.username())
        for (url in scopedUrls + AO3Constants.BASE_URL) {
            assertTrue(manager.getCookie(url).isNullOrBlank())
        }
    }

    @Test
    fun installDropsNonIdentityCookiesFromAnOlderSession() = runTest {
        AndroidAO3CookieStore(manager).install(AO3Session("AO3_Reader", listOf(
            AO3StoredCookie(AO3StoredCookie.SessionCookieName, "session"),
            AO3StoredCookie("user_credentials", "remember"),
            AO3StoredCookie("_ga", "tracker"),
            AO3StoredCookie("viewed_adult", "true")
        )))
        val installed = manager.getCookie(AO3Constants.BASE_URL)
        assertTrue(installed.contains("_otwarchive_session=session"))
        assertTrue(installed.contains("user_credentials=remember"))
        assertFalse(installed.contains("_ga="))
        assertFalse(installed.contains("viewed_adult="))
    }
}
