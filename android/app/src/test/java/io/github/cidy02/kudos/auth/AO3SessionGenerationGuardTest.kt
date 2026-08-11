package io.github.cidy02.kudos.auth

import java.nio.file.Files
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Generation-guard + removal-pending coverage for the verify/logout race and
 * failed-delete restore refusal (iOS `sessionGeneration` / A5-F4 ports).
 */
class AO3SessionGenerationGuardTest {

    /**
     * REPRODUCTION of the privacy defect: verify's network completes *after*
     * logout. Without the generation guard, verify re-saves the session and
     * re-installs cookies — the user believes they are signed out; they are not.
     */
    @Test
    fun verifyCompletingAfterLogoutDoesNotResaveOrReinstallCookies() = runTest {
        val session = testSession("AO3_Reader")
        val store = CountingSessionStore(session)
        val cookies = TrackingCookieStore()
        val allowVerifyNetwork = CompletableDeferred<Unit>()
        val verifyNetworkStarted = CompletableDeferred<Unit>()
        val validator = GatedValidator(
            restoreResult = AO3SessionValidation.Valid(session),
            onVerifyStart = { verifyNetworkStarted.complete(Unit) },
            awaitBeforeVerifyResult = allowVerifyNetwork,
            verifyResult = AO3SessionValidation.Valid(
                session.copy(
                    username = "resurrected",
                    cookies = listOf(
                        AO3StoredCookie(
                            name = AO3StoredCookie.SessionCookieName,
                            value = "zombie-cookie"
                        )
                    )
                )
            )
        )
        val repository = AO3AuthRepository(
            sessionStore = store,
            cookieStore = cookies,
            sessionValidator = validator
        )
        repository.restoreSession()
        assertEquals(AO3AuthState.SignedIn("AO3_Reader"), repository.state.value)
        store.resetCounts()
        cookies.resetTracking()

        val verifyJob = async { repository.verifySession() }
        // Deterministic rendezvous: verify is suspended inside the network call.
        verifyNetworkStarted.await()
        repository.logout()
        assertEquals(AO3AuthState.SignedOut, repository.state.value)
        assertNull(store.session)
        assertTrue(cookies.cleared)

        // Let verify finish. Generation guard must discard the apply.
        allowVerifyNetwork.complete(Unit)
        verifyJob.await()

        assertEquals(AO3AuthState.SignedOut, repository.state.value)
        assertNull(repository.username())
        assertNull(store.session)
        assertEquals(
            "verify must not re-save session after logout",
            0,
            store.saveCount
        )
        assertEquals(
            "verify must not re-install cookies after logout",
            0,
            cookies.installCount
        )
        assertFalse(
            cookies.installed?.cookies?.any { it.value == "zombie-cookie" } == true
        )
    }

    @Test
    fun verifyWithoutInterveningLogoutStillAppliesRefreshedSession() = runTest {
        val session = testSession("AO3_Reader")
        val refreshed = testSession("AO3_Reader").copy(
            cookies = listOf(
                AO3StoredCookie(name = AO3StoredCookie.SessionCookieName, value = "rotated")
            )
        )
        val store = CountingSessionStore(session)
        val cookies = TrackingCookieStore()
        val validator = GatedValidator(
            restoreResult = AO3SessionValidation.Valid(session),
            verifyResult = AO3SessionValidation.Valid(refreshed)
        )
        val repository = AO3AuthRepository(
            sessionStore = store,
            cookieStore = cookies,
            sessionValidator = validator
        )
        repository.restoreSession()
        store.resetCounts()
        cookies.resetTracking()

        repository.verifySession()

        assertEquals(AO3AuthState.SignedIn("AO3_Reader"), repository.state.value)
        assertEquals(refreshed, store.session)
        assertEquals(refreshed, cookies.installed)
        assertEquals(1, store.saveCount)
        assertEquals(1, cookies.installCount)
        assertTrue(repository.sessionHealth.value is AO3SessionHealth.Healthy)
    }

    @Test
    fun restoreSessionRefusesWhenRemovalPendingMarkerIsSet() = runTest {
        val leftover = testSession("should_not_restore")
        val store = CountingSessionStore(session = leftover, removalPending = true)
        val cookies = TrackingCookieStore()
        val repository = AO3AuthRepository(
            sessionStore = store,
            cookieStore = cookies,
            sessionValidator = null
        )

        repository.restoreSession()

        assertEquals(AO3AuthState.SignedOut, repository.state.value)
        assertNull(repository.username())
        // Retry delete during restore should clear the leftover blob + marker.
        assertNull(store.session)
        assertFalse(store.removalPending)
        assertEquals(0, cookies.installCount)
    }

    @Test
    fun logoutMarksRemovalPendingWhenDeleteFailsAndRestoreRefuses() = runTest {
        val session = testSession("stuck")
        val store = CountingSessionStore(session = session, failDelete = true)
        val cookies = TrackingCookieStore()
        val repository = AO3AuthRepository(
            sessionStore = store,
            cookieStore = cookies,
            sessionValidator = null
        )
        repository.restoreSession()
        assertEquals(AO3AuthState.SignedIn("stuck"), repository.state.value)

        repository.logout()

        assertEquals(AO3AuthState.SignedOut, repository.state.value)
        assertTrue(store.removalPending)
        // Blob may still be on "disk" because delete failed.
        assertEquals(session, store.session)
        assertTrue(cookies.cleared)

        // New process: new repository, same durable store.
        store.failDelete = false
        val again = AO3AuthRepository(
            sessionStore = store,
            cookieStore = TrackingCookieStore(),
            sessionValidator = null
        )
        again.restoreSession()
        assertEquals(AO3AuthState.SignedOut, again.state.value)
        assertNull(store.session)
        assertFalse(store.removalPending)
    }

    @Test
    fun fileSessionStoreRemovalPendingSurvivesAndBlocksLoadPath() = runTest {
        val directory = Files.createTempDirectory("kudos-removal-pending").toFile()
        val file = directory.resolve("session.json")
        val store = FileAO3SessionStore(file)
        store.save(testSession("file_user"))
        assertEquals("file_user", store.load()?.username)

        // Simulate failed delete: mark pending while leaving the file in place.
        store.markRemovalPending()
        assertTrue(store.isRemovalPending())
        assertTrue(file.exists())

        val repository = AO3AuthRepository(
            sessionStore = store,
            cookieStore = TrackingCookieStore(),
            sessionValidator = null
        )
        repository.restoreSession()

        assertEquals(AO3AuthState.SignedOut, repository.state.value)
        assertFalse(file.exists())
        assertFalse(store.isRemovalPending())
    }

    @Test
    fun fileSessionStoreDeleteReturnValueReflectsSuccess() = runTest {
        val directory = Files.createTempDirectory("kudos-delete-ok").toFile()
        val file = directory.resolve("session.json")
        val store = FileAO3SessionStore(file)
        store.save(testSession())
        assertTrue(store.delete())
        assertNull(store.load())
        // Second delete of missing file is still success.
        assertTrue(store.delete())
    }
}

/**
 * First [validate] (restore) returns [restoreResult] immediately.
 * Subsequent calls signal [onVerifyStart], await [awaitBeforeVerifyResult] if set,
 * then return [verifyResult].
 */
private class GatedValidator(
    private val restoreResult: AO3SessionValidation,
    private val verifyResult: AO3SessionValidation,
    private val onVerifyStart: suspend () -> Unit = {},
    private val awaitBeforeVerifyResult: CompletableDeferred<Unit>? = null
) : AO3SessionValidating {
    private var calls = 0

    override suspend fun validate(session: AO3Session): AO3SessionValidation {
        calls += 1
        if (calls == 1) return restoreResult
        onVerifyStart()
        awaitBeforeVerifyResult?.await()
        return verifyResult
    }
}

/** Counts install/clear for race assertions. */
private class TrackingCookieStore : AO3CookieStore {
    var installed: AO3Session? = null
    var installCount: Int = 0
    var cleared: Boolean = false

    fun resetTracking() {
        installCount = 0
        cleared = false
        installed = null
    }

    override suspend fun captureSession(username: String): AO3Session? = null

    override suspend fun install(session: AO3Session) {
        installed = session
        installCount += 1
        cleared = false
    }

    override suspend fun clear() {
        cleared = true
        installed = null
    }
}

/** In-memory session store with save/delete counters for race tests. */
private class CountingSessionStore(
    var session: AO3Session? = null,
    var removalPending: Boolean = false,
    var failDelete: Boolean = false
) : AO3SessionStore {
    var saveCount: Int = 0
        private set

    fun resetCounts() {
        saveCount = 0
    }

    override suspend fun load(): AO3Session? = session

    override suspend fun save(session: AO3Session) {
        saveCount += 1
        this.session = session
        removalPending = false
    }

    override suspend fun delete(): Boolean {
        if (failDelete) return false
        session = null
        return true
    }

    override suspend fun isRemovalPending(): Boolean = removalPending

    override suspend fun markRemovalPending() {
        removalPending = true
    }

    override suspend fun clearRemovalPending() {
        removalPending = false
    }
}
