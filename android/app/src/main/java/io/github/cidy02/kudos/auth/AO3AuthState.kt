package io.github.cidy02.kudos.auth

sealed interface AO3AuthState {
    data object Restoring : AO3AuthState
    data object SignedOut : AO3AuthState
    data object SigningIn : AO3AuthState
    data class SignedIn(val username: String) : AO3AuthState
    data class Expired(val message: String = "Your AO3 session expired. Please log in again.") : AO3AuthState
    data class Error(val message: String) : AO3AuthState
}

val AO3AuthState.usernameOrNull: String?
    get() = (this as? AO3AuthState.SignedIn)?.username

val AO3AuthState.isSignedIn: Boolean
    get() = this is AO3AuthState.SignedIn
