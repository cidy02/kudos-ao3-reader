package io.github.cidy02.kudos.auth

import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class AO3AuthRepository(
    private val sessionStore: AO3SessionStore,
    private val cookieStore: AO3CookieStore,
    private val cookieJar: AO3CookieJar = AO3CookieJar()
) {
    private val mutableState = MutableStateFlow<AO3AuthState>(AO3AuthState.Restoring)
    val state: StateFlow<AO3AuthState> = mutableState.asStateFlow()

    private var currentSession: AO3Session? = null
    private var didRestore = false

    suspend fun restoreSession() {
        if (didRestore) return
        didRestore = true
        mutableState.value = AO3AuthState.Restoring
        val restored = sessionStore.load()
        if (restored == null || !restored.hasSessionCookie()) {
            currentSession = null
            mutableState.value = AO3AuthState.SignedOut
            return
        }

        currentSession = restored
        cookieStore.install(restored)
        mutableState.value = AO3AuthState.SignedIn(restored.username)
    }

    suspend fun acceptWebLogin(username: String): AO3Result<AO3Session> {
        mutableState.value = AO3AuthState.SigningIn
        val trimmed = username.trim()
        if (trimmed.isBlank()) {
            val error = AO3Error.Validation("AO3 username could not be detected.")
            mutableState.value = AO3AuthState.Error(error.message)
            return AO3Result.Failure(error)
        }

        val session = cookieStore.captureSession(trimmed)
        if (session == null) {
            val error = AO3Error.AuthenticationRequired
            mutableState.value = AO3AuthState.Error("AO3 login did not produce a usable session.")
            return AO3Result.Failure(error)
        }

        sessionStore.save(session)
        cookieStore.install(session)
        currentSession = session
        mutableState.value = AO3AuthState.SignedIn(session.username)
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
    }

    suspend fun logout() {
        clearSession()
        mutableState.value = AO3AuthState.SignedOut
    }

    private suspend fun clearSession() {
        currentSession = null
        sessionStore.delete()
        cookieStore.clear()
    }
}
