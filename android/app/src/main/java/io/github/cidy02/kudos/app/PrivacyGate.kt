package io.github.cidy02.kudos.app

import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/** Snapshot of session reveal state — see `PrivacyGate`. */
data class PrivacyRevealState(
    val revealAll: Boolean = false,
    val revealedIds: Set<String> = emptySet()
) {
    fun isRevealed(workId: String): Boolean = revealAll || workId in revealedIds
}

/**
 * Tracks which sensitive (Mature/Explicit) works have been temporarily revealed this
 * session. Port of Apple `PrivacyGate` (Features/Privacy/MatureContent.swift).
 *
 * Session-only and in-memory by design, never persisted — a reveal or a reveal-all
 * resets the next time the process starts, exactly like the "Hide mature content"
 * setting itself resets to on.
 */
class PrivacyGate {
    private val _state = MutableStateFlow(PrivacyRevealState())
    val state: StateFlow<PrivacyRevealState> = _state.asStateFlow()

    fun isRevealed(workId: String): Boolean = _state.value.isRevealed(workId)

    /** Reveals a single work (an Obscure-mode tap), optionally gated by biometric/passcode. */
    fun reveal(workId: String, activity: FragmentActivity? = null, requireBiometric: Boolean = false) {
        authenticate(activity, requireBiometric) {
            _state.update { it.copy(revealedIds = it.revealedIds + workId) }
        }
    }

    /** Shows or re-hides every sensitive work for the session, optionally gated by biometric/passcode. */
    fun toggleRevealAll(activity: FragmentActivity? = null, requireBiometric: Boolean = false) {
        if (_state.value.revealAll) {
            _state.update { PrivacyRevealState(revealAll = false, revealedIds = emptySet()) }
        } else {
            authenticate(activity, requireBiometric) {
                _state.update { current -> current.copy(revealAll = true) }
            }
        }
    }

    private fun authenticate(
        activity: FragmentActivity?,
        requireBiometric: Boolean,
        onSuccess: () -> Unit
    ) {
        if (!requireBiometric || activity == null) {
            onSuccess()
            return
        }
        val manager = BiometricManager.from(activity)
        val authenticators = BiometricManager.Authenticators.BIOMETRIC_STRONG or BiometricManager.Authenticators.DEVICE_CREDENTIAL
        val canAuth = manager.canAuthenticate(authenticators)
        if (canAuth != BiometricManager.BIOMETRIC_SUCCESS) {
            onSuccess()
            return
        }

        val executor = ContextCompat.getMainExecutor(activity)
        val prompt = BiometricPrompt(activity, executor, object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                super.onAuthenticationSucceeded(result)
                onSuccess()
            }
        })

        val promptInfo = BiometricPrompt.PromptInfo.Builder()
            .setTitle("View mature content")
            .setAllowedAuthenticators(authenticators)
            .build()

        prompt.authenticate(promptInfo)
    }
}
