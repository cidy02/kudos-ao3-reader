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
 *
 * When [requireBiometricToReveal] is true, [reveal]/[toggleRevealAll] gate on
 * `BiometricPrompt` with biometric-or-device-credential (iOS
 * `LAContext.evaluatePolicy(.deviceOwnerAuthentication)`). Callers must pass a
 * [FragmentActivity]; without one the content stays hidden (no silent downgrade).
 * If the device has no lock enrolled, reveal proceeds — same as iOS.
 */
class PrivacyGate {
    private val _state = MutableStateFlow(PrivacyRevealState())
    val state: StateFlow<PrivacyRevealState> = _state.asStateFlow()

    /**
     * Mirrors Settings → Privacy → "Require biometric to reveal".
     * Updated from the app shell when settings flow emits; never read from disk here.
     */
    @Volatile
    var requireBiometricToReveal: Boolean = false

    fun isRevealed(workId: String): Boolean = _state.value.isRevealed(workId)

    /** Reveals a single work (an Obscure-mode tap), optionally gated by biometric/passcode. */
    fun reveal(workId: String, activity: FragmentActivity? = null) {
        authenticate(activity) {
            _state.update { it.copy(revealedIds = it.revealedIds + workId) }
        }
    }

    /**
     * Shows or re-hides every sensitive work for the session.
     * Re-hiding never requires auth; revealing-all does when the setting is on.
     */
    fun toggleRevealAll(activity: FragmentActivity? = null) {
        if (_state.value.revealAll) {
            _state.update { PrivacyRevealState(revealAll = false, revealedIds = emptySet()) }
        } else {
            authenticate(activity) {
                _state.update { current -> current.copy(revealAll = true) }
            }
        }
    }

    private fun authenticate(activity: FragmentActivity?, onSuccess: () -> Unit) {
        if (!requireBiometricToReveal) {
            onSuccess()
            return
        }
        // Setting is on but we have no Activity to host the prompt — stay locked.
        // Never silently reveal when the user asked for a biometric gate.
        if (activity == null) return

        val manager = BiometricManager.from(activity)
        val authenticators =
            BiometricManager.Authenticators.BIOMETRIC_STRONG or
                BiometricManager.Authenticators.DEVICE_CREDENTIAL
        val canAuth = manager.canAuthenticate(authenticators)
        // No passcode/biometrics enrolled — don't lock the user out of their library
        // (iOS: canEvaluatePolicy fails → onSuccess).
        if (canAuth != BiometricManager.BIOMETRIC_SUCCESS) {
            onSuccess()
            return
        }

        val executor = ContextCompat.getMainExecutor(activity)
        val prompt = BiometricPrompt(
            activity,
            executor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    super.onAuthenticationSucceeded(result)
                    onSuccess()
                }
                // Cancel / failure: leave content hidden (iOS parity).
            }
        )

        val promptInfo = BiometricPrompt.PromptInfo.Builder()
            .setTitle("View mature content")
            .setAllowedAuthenticators(authenticators)
            .build()

        prompt.authenticate(promptInfo)
    }
}
