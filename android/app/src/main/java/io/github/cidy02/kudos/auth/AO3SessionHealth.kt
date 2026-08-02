package io.github.cidy02.kudos.auth

/**
 * Result of the most recent on-demand (or launch-time) session check, for the
 * account UI health indicator.
 *
 * Orthogonal to [AO3AuthState] (which says whether we hold a session at all);
 * this says how confident we are that a held session is still live. Port of
 * Apple `AO3SessionHealth`.
 */
sealed interface AO3SessionHealth {
    /** Signed out, or signed in but never re-checked this process. */
    data object Unknown : AO3SessionHealth

    /** A check is in flight. */
    data object Verifying : AO3SessionHealth

    /** Confirmed valid against AO3 at [verifiedAtEpochMillis]. */
    data class Healthy(val verifiedAtEpochMillis: Long) : AO3SessionHealth

    /** AO3 reported the session is no longer valid (user was signed out). */
    data object Expired : AO3SessionHealth

    /**
     * Couldn't reach AO3 to check (offline / transient). The session is kept —
     * a transient failure must never force a sign-out.
     */
    data object Unreachable : AO3SessionHealth

    val isChecking: Boolean
        get() = this is Verifying
}
