package io.github.cidy02.kudos.app

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
 * setting itself resets to on. This is the one shared instance for the whole app
 * (`KudosAppContainer.privacyGate`), read by every screen that can show an obscured
 * work, so revealing a work on one screen keeps it revealed everywhere else for the
 * rest of the session — matching Apple's single app-scoped `PrivacyGate` injected via
 * `.environment(privacyGate)` from `ContentView`.
 *
 * Exposed as one combined `StateFlow<PrivacyRevealState>` rather than two separate
 * flows so a ViewModel's `combine(...)` can fold this in as a single argument and
 * stay within Kotlin Flow's fixed-arity `combine` overloads.
 *
 * Biometric confirmation before a reveal (Apple's `authenticate { ... }`, gated by
 * `LAContext`/Face ID) is not ported — Android's own "biometric reveal for mature
 * works" is separately, explicitly tracked as a deferred feature
 * (`docs/audits/REMAINING_PARITY_AND_UI_GAPS.md`). This class is the piece that gap
 * sits on top of; adding it later means gating `reveal()`/`toggleRevealAll()` behind a
 * `BiometricPrompt` call, not restructuring this state.
 */
class PrivacyGate {
    private val _state = MutableStateFlow(PrivacyRevealState())
    val state: StateFlow<PrivacyRevealState> = _state.asStateFlow()

    fun isRevealed(workId: String): Boolean = _state.value.isRevealed(workId)

    /** Reveals a single work (an Obscure-mode tap). */
    fun reveal(workId: String) {
        _state.update { it.copy(revealedIds = it.revealedIds + workId) }
    }

    /** Shows or re-hides every sensitive work for the session. */
    fun toggleRevealAll() {
        _state.update { current ->
            if (current.revealAll) {
                PrivacyRevealState(revealAll = false, revealedIds = emptySet())
            } else {
                current.copy(revealAll = true)
            }
        }
    }
}
