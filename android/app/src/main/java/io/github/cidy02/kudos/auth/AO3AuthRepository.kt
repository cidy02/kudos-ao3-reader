package io.github.cidy02.kudos.auth

import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class AO3AuthRepository(
    private val sessionStore: AO3SessionStore,
    private val cookieStore: AO3CookieStore,
    private val cookieJar: AO3CookieJar = AO3CookieJar(),
    private val sessionValidator: AO3SessionValidating? = null
) {
    private val mutableState = MutableStateFlow<AO3AuthState>(AO3AuthState.Restoring)
    val state: StateFlow<AO3AuthState> = mutableState.asStateFlow()

    private val mutableSessionHealth = MutableStateFlow<AO3SessionHealth>(AO3SessionHealth.Unknown)
    /**
     * Orthogonal to [state]: confidence that an already-held session is still live.
     * Driven by launch-time [restoreSession] validation and on-demand [verifySession].
     */
    val sessionHealth: StateFlow<AO3SessionHealth> = mutableSessionHealth.asStateFlow()

    private var currentSession: AO3Session? = null
    private var didRestore = false

    /**
     * Bumped on every identity transition (restore start, login start, logout,
     * expiry clear, successful verify-refresh). Continuations that captured an
     * older generation must not write session state or install cookies.
     * Port of iOS `AO3AuthService.sessionGeneration`.
     */
    private var sessionGeneration: Int = 0

    /**
     * Short critical-section lock for generation check + session mutation.
     * Never held across network validation — only around local apply/clear.
     */
    private val sessionMutex = Mutex()

    /**
     * Loads the persisted session once per process. When a [sessionValidator]
     * is configured, GETs a cheap AO3 page with the stored cookies:
     * - clearly logged-out → clear session ([AO3AuthState.Expired])
     * - network / non-AO3 failure → keep session (offline-preserving)
     * - logged-in → optionally refresh cookies/username and sign in
     */
    suspend fun restoreSession() {
        if (didRestore) return
        didRestore = true
        val expectedGeneration = sessionMutex.withLock {
            mutableState.value = AO3AuthState.Restoring
            advanceSessionGenerationLocked()
        }

        // A previous logout/expiry couldn't fully clear the durable store.
        // Retry delete, but never restore a leftover blob this launch.
        if (sessionStore.isRemovalPending()) {
            retryPendingRemoval()
            sessionMutex.withLock {
                if (sessionGeneration != expectedGeneration) return
                currentSession = null
                mutableState.value = AO3AuthState.SignedOut
                mutableSessionHealth.value = AO3SessionHealth.Unknown
            }
            return
        }

        // sessionStore.load() only guarantees catching malformed-content errors
        // (IllegalArgumentException/SerializationException) internally; a plain
        // IOException (corrupt/half-written file, disk error) must not crash
        // launch — fall back to signed-out, same as a missing session.
        val restored = try {
            sessionStore.load()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            null
        }
        if (restored == null || !restored.hasSessionCookie()) {
            sessionMutex.withLock {
                if (sessionGeneration != expectedGeneration) return
                currentSession = null
                mutableState.value = AO3AuthState.SignedOut
                mutableSessionHealth.value = AO3SessionHealth.Unknown
            }
            return
        }

        sessionMutex.withLock {
            if (sessionGeneration != expectedGeneration) return
            currentSession = restored
            // Install under the lock so a concurrent logout cannot clear cookies
            // only to have this continuation reinstall them immediately after.
            cookieStore.install(restored)
        }

        val validator = sessionValidator
        if (validator == null) {
            sessionMutex.withLock {
                if (sessionGeneration != expectedGeneration) return
                mutableState.value = AO3AuthState.SignedIn(restored.username)
                mutableSessionHealth.value = AO3SessionHealth.Unknown
            }
            return
        }

        try {
            when (val validation = validator.validate(restored)) {
                is AO3SessionValidation.Valid -> {
                    sessionMutex.withLock {
                        if (sessionGeneration != expectedGeneration) return
                        if (currentSession != restored) return
                        applyValidSessionLocked(validation.session, markHealthy = true)
                    }
                }
                AO3SessionValidation.Expired -> {
                    sessionMutex.withLock {
                        if (sessionGeneration != expectedGeneration) return
                        clearSessionLocked()
                        mutableState.value = AO3AuthState.Expired()
                        mutableSessionHealth.value = AO3SessionHealth.Expired
                    }
                }
            }
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            // Connectivity or non-definitive response — keep the saved session.
            sessionMutex.withLock {
                if (sessionGeneration != expectedGeneration) return
                if (currentSession != restored) return
                mutableState.value = AO3AuthState.SignedIn(restored.username)
                mutableSessionHealth.value = AO3SessionHealth.Unreachable
            }
        }
    }

    /**
     * On-demand re-validation of the stored session, driven by the account UI's
     * "Verify Session" control. Unlike [restoreSession] (single-shot at launch),
     * this can run whenever the user asks. Mirrors restore's valid/expired/
     * transient handling: a transient failure keeps the session and reports
     * [AO3SessionHealth.Unreachable] rather than logging the user out.
     *
     * Captures [sessionGeneration] before the network call; after return, the
     * check-plus-apply runs under [sessionMutex] so a concurrent [logout] that
     * advanced the generation cannot be overwritten by this continuation.
     */
    suspend fun verifySession() {
        val (session, expectedGeneration) = sessionMutex.withLock {
            val current = currentSession
            if (current == null || mutableState.value !is AO3AuthState.SignedIn) {
                mutableSessionHealth.value = AO3SessionHealth.Unknown
                return
            }
            current to sessionGeneration
        }
        val validator = sessionValidator
        if (validator == null) {
            // No live check available — leave health as-is / unknown.
            mutableSessionHealth.value = AO3SessionHealth.Unknown
            return
        }

        sessionMutex.withLock {
            if (sessionGeneration != expectedGeneration) return
            mutableSessionHealth.value = AO3SessionHealth.Verifying
        }
        try {
            // Network — intentionally outside the mutex so logout is not stalled.
            when (val validation = validator.validate(session)) {
                is AO3SessionValidation.Valid -> {
                    sessionMutex.withLock {
                        if (sessionGeneration != expectedGeneration) return
                        if (currentSession != session) return
                        // Bump generation so any other in-flight continuation
                        // that captured the pre-refresh generation goes stale.
                        advanceSessionGenerationLocked()
                        applyValidSessionLocked(validation.session, markHealthy = true)
                    }
                }
                AO3SessionValidation.Expired -> {
                    sessionMutex.withLock {
                        if (sessionGeneration != expectedGeneration) return
                        clearSessionLocked()
                        mutableState.value = AO3AuthState.Expired()
                        mutableSessionHealth.value = AO3SessionHealth.Expired
                    }
                }
            }
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            // Transient (offline / server hiccup): keep the session, flag unverified.
            sessionMutex.withLock {
                if (sessionGeneration != expectedGeneration) return
                mutableSessionHealth.value = AO3SessionHealth.Unreachable
            }
        }
    }

    suspend fun acceptWebLogin(username: String): AO3Result<AO3Session> {
        val expectedGeneration = sessionMutex.withLock {
            mutableState.value = AO3AuthState.SigningIn
            advanceSessionGenerationLocked()
        }
        val trimmed = username.trim()
        if (trimmed.isBlank()) {
            val error = AO3Error.Validation("AO3 username could not be detected.")
            sessionMutex.withLock {
                if (sessionGeneration != expectedGeneration) {
                    return AO3Result.Failure(error)
                }
                mutableState.value = AO3AuthState.Error(error.message)
                mutableSessionHealth.value = AO3SessionHealth.Unknown
            }
            return AO3Result.Failure(error)
        }

        val session = cookieStore.captureSession(trimmed)
        if (session == null) {
            val error = AO3Error.AuthenticationRequired
            sessionMutex.withLock {
                if (sessionGeneration != expectedGeneration) {
                    return AO3Result.Failure(error)
                }
                mutableState.value = AO3AuthState.Error("AO3 login did not produce a usable session.")
                mutableSessionHealth.value = AO3SessionHealth.Unknown
            }
            return AO3Result.Failure(error)
        }

        sessionMutex.withLock {
            if (sessionGeneration != expectedGeneration) {
                // Logout / another login won while we captured cookies — do not
                // reinstall this (possibly stale) WebView snapshot.
                return AO3Result.Failure(AO3Error.AuthenticationRequired)
            }
            // Fresh login is trusted for gating but has not been re-checked on demand.
            applyValidSessionLocked(session, markHealthy = false)
        }
        return AO3Result.Success(session)
    }

    fun authenticatedHeaders(url: String): AO3Result<Map<String, String>> {
        val session = currentSession ?: return AO3Result.Failure(AO3Error.AuthenticationRequired)
        val cookieHeader = cookieJar.cookieHeader(session, url)
            ?: return AO3Result.Failure(AO3Error.AuthenticationRequired)
        return AO3Result.Success(mapOf("Cookie" to cookieHeader))
    }

    fun username(): String? = currentSession?.username

    suspend fun sessionDidExpire() {
        sessionMutex.withLock {
            clearSessionLocked()
            mutableState.value = AO3AuthState.Expired()
            mutableSessionHealth.value = AO3SessionHealth.Expired
        }
    }

    suspend fun logout() {
        sessionMutex.withLock {
            clearSessionLocked()
            mutableState.value = AO3AuthState.SignedOut
            mutableSessionHealth.value = AO3SessionHealth.Unknown
        }
    }

    /**
     * Must be called while [sessionMutex] is held. Writes durable session +
     * installs cookies + updates in-memory state.
     */
    private suspend fun applyValidSessionLocked(session: AO3Session, markHealthy: Boolean) {
        sessionStore.save(session)
        // save() also clears removal-pending on file stores; call explicitly so
        // in-memory / custom stores stay consistent.
        sessionStore.clearRemovalPending()
        cookieStore.install(session)
        currentSession = session
        mutableState.value = AO3AuthState.SignedIn(session.username)
        mutableSessionHealth.value = if (markHealthy) {
            AO3SessionHealth.Healthy(System.currentTimeMillis())
        } else {
            AO3SessionHealth.Unknown
        }
    }

    /**
     * Must be called while [sessionMutex] is held. Advances generation so every
     * in-flight continuation becomes stale, then clears memory + durable store
     * + cookies. Honours delete failure by marking removal pending.
     */
    private suspend fun clearSessionLocked() {
        advanceSessionGenerationLocked()
        currentSession = null
        val deleted = sessionStore.delete()
        if (deleted) {
            sessionStore.clearRemovalPending()
        } else {
            sessionStore.markRemovalPending()
        }
        cookieStore.clear()
    }

    private fun advanceSessionGenerationLocked(): Int {
        sessionGeneration += 1
        return sessionGeneration
    }

    /** Best-effort retry of a previously failed durable delete. */
    private suspend fun retryPendingRemoval() {
        val deleted = sessionStore.delete()
        if (deleted) {
            sessionStore.clearRemovalPending()
        }
        // If still failing, leave the marker set so the next launch also refuses.
    }
}
