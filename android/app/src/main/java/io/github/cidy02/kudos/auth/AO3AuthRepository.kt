package io.github.cidy02.kudos.auth

import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

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
     * Loads the persisted session once per process. When a [sessionValidator]
     * is configured, GETs a cheap AO3 page with the stored cookies:
     * - clearly logged-out → clear session ([AO3AuthState.Expired])
     * - network / non-AO3 failure → keep session (offline-preserving)
     * - logged-in → optionally refresh cookies/username and sign in
     */
    suspend fun restoreSession() {
        if (didRestore) return
        didRestore = true
        mutableState.value = AO3AuthState.Restoring
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
            currentSession = null
            mutableState.value = AO3AuthState.SignedOut
            mutableSessionHealth.value = AO3SessionHealth.Unknown
            return
        }

        currentSession = restored
        cookieStore.install(restored)

        val validator = sessionValidator
        if (validator == null) {
            mutableState.value = AO3AuthState.SignedIn(restored.username)
            mutableSessionHealth.value = AO3SessionHealth.Unknown
            return
        }

        try {
            when (val validation = validator.validate(restored)) {
                is AO3SessionValidation.Valid -> {
                    applyValidSession(validation.session)
                }
                AO3SessionValidation.Expired -> {
                    clearSession()
                    mutableState.value = AO3AuthState.Expired()
                    mutableSessionHealth.value = AO3SessionHealth.Expired
                }
            }
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            // Connectivity or non-definitive response — keep the saved session.
            mutableState.value = AO3AuthState.SignedIn(restored.username)
            mutableSessionHealth.value = AO3SessionHealth.Unreachable
        }
    }

    /**
     * On-demand re-validation of the stored session, driven by the account UI's
     * "Verify Session" control. Unlike [restoreSession] (single-shot at launch),
     * this can run whenever the user asks. Mirrors restore's valid/expired/
     * transient handling: a transient failure keeps the session and reports
     * [AO3SessionHealth.Unreachable] rather than logging the user out.
     */
    suspend fun verifySession() {
        val session = currentSession
        if (session == null || mutableState.value !is AO3AuthState.SignedIn) {
            mutableSessionHealth.value = AO3SessionHealth.Unknown
            return
        }
        val validator = sessionValidator
        if (validator == null) {
            // No live check available — leave health as-is / unknown.
            mutableSessionHealth.value = AO3SessionHealth.Unknown
            return
        }

        mutableSessionHealth.value = AO3SessionHealth.Verifying
        try {
            when (val validation = validator.validate(session)) {
                is AO3SessionValidation.Valid -> {
                    applyValidSession(validation.session)
                }
                AO3SessionValidation.Expired -> {
                    clearSession()
                    mutableState.value = AO3AuthState.Expired()
                    mutableSessionHealth.value = AO3SessionHealth.Expired
                }
            }
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            // Transient (offline / server hiccup): keep the session, flag unverified.
            mutableSessionHealth.value = AO3SessionHealth.Unreachable
        }
    }

    suspend fun acceptWebLogin(username: String): AO3Result<AO3Session> {
        mutableState.value = AO3AuthState.SigningIn
        val trimmed = username.trim()
        if (trimmed.isBlank()) {
            val error = AO3Error.Validation("AO3 username could not be detected.")
            mutableState.value = AO3AuthState.Error(error.message)
            mutableSessionHealth.value = AO3SessionHealth.Unknown
            return AO3Result.Failure(error)
        }

        val session = cookieStore.captureSession(trimmed)
        if (session == null) {
            val error = AO3Error.AuthenticationRequired
            mutableState.value = AO3AuthState.Error("AO3 login did not produce a usable session.")
            mutableSessionHealth.value = AO3SessionHealth.Unknown
            return AO3Result.Failure(error)
        }

        sessionStore.save(session)
        cookieStore.install(session)
        currentSession = session
        mutableState.value = AO3AuthState.SignedIn(session.username)
        // Fresh login is trusted for gating but has not been re-checked on demand.
        mutableSessionHealth.value = AO3SessionHealth.Unknown
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
        clearSession()
        mutableState.value = AO3AuthState.Expired()
        mutableSessionHealth.value = AO3SessionHealth.Expired
    }

    suspend fun logout() {
        clearSession()
        mutableState.value = AO3AuthState.SignedOut
        mutableSessionHealth.value = AO3SessionHealth.Unknown
    }

    private suspend fun applyValidSession(session: AO3Session) {
        sessionStore.save(session)
        cookieStore.install(session)
        currentSession = session
        mutableState.value = AO3AuthState.SignedIn(session.username)
        mutableSessionHealth.value = AO3SessionHealth.Healthy(System.currentTimeMillis())
    }

    private suspend fun clearSession() {
        currentSession = null
        sessionStore.delete()
        cookieStore.clear()
    }
}
