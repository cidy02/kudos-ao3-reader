package io.github.cidy02.kudos.core.model

import java.time.Instant
import java.time.temporal.ChronoUnit

/**
 * Per-work cover art preference, matching iOS T-573 (`UIComponents/CoverArtPreference.swift`).
 *
 * Stored as a plain nullable string on the work (`"embedded"`, `"generated"`, `"follow"`, or `null`).
 * `null` follows the global "Use art from the work when there is some" setting; so does [FOLLOW_RAW],
 * which a reader's reset writes after an explicit choice so the reset syncs as a newer edit (an
 * absent key never clears a choice in merge). Unknown strings from future builds stay intact in
 * storage/backups and resolve as [FollowSettings] (`null`).
 */
enum class CoverArtPreference(val storageValue: String?) {
    FollowSettings(null),
    Embedded("embedded"),
    Generated("generated");

    companion object {
        /** Stored when a reader goes back to Follow Settings after choosing; read like `null`. */
        const val FOLLOW_RAW: String = "follow"

        /**
         * Returns only an explicit known choice ([Embedded] or [Generated]), or `null` for
         * `null`, [FOLLOW_RAW], or any unknown future string (matching iOS `CoverArtPreference.resolved`).
         */
        fun resolved(raw: String?): CoverArtPreference? = when (raw) {
            "embedded" -> Embedded
            "generated" -> Generated
            else -> null
        }

        fun fromStorage(raw: String?): CoverArtPreference = resolved(raw) ?: FollowSettings
    }
}

/** Result of a reader cover-choice edit that actually changes the stored choice. */
data class CoverArtPreferenceEdit(
    val raw: String,
    val changedAt: Instant
)

/**
 * Pure cover-selection and reader-edit rules shared by every cover surface, Work Detail,
 * `WorkRepository`, and tests (mirroring iOS `UIComponents/CoverArtPreference.swift`).
 */
object CoverArtResolution {
    /**
     * Whether the work's own art is wanted. A work with no art draws the generated cover either way.
     * Mirrors iOS `CoverArtPreference.wantsEmbeddedArt(override:global:)`.
     */
    fun wantsEmbeddedArt(
        globalUseEmbeddedCoverArt: Boolean,
        workPreferenceRaw: String?
    ): Boolean = when (CoverArtPreference.resolved(workPreferenceRaw)) {
        CoverArtPreference.Embedded -> true
        CoverArtPreference.Generated -> false
        null, CoverArtPreference.FollowSettings -> globalUseEmbeddedCoverArt
    }

    /**
     * Returns true iff a work should show its embedded EPUB art (falling back to generated
     * whenever [hasEmbeddedArt] is false).
     * Mirrors iOS `CoverArtPreference.showsEmbeddedArt(override:global:hasArt:)`.
     */
    fun shouldUseEmbeddedArt(
        globalUseEmbeddedCoverArt: Boolean,
        workPreferenceRaw: String?,
        hasEmbeddedArt: Boolean = true
    ): Boolean = hasEmbeddedArt && wantsEmbeddedArt(globalUseEmbeddedCoverArt, workPreferenceRaw)

    /**
     * Computes the stored `(raw, changedAt)` pair for a reader's edit, or returns `null` when
     * no write should occur (tapping the already-selected option, or tapping Follow Settings when
     * nothing explicit is resolved — keeping untouched `null` rows and unknown future strings
     * intact). Stamps `changedAt` monotonically as `max(now, previous + 1 ms)` at millisecond
     * precision so SQLite epoch-millis and ISO-8601 `.SSS` serialization preserve strict ordering.
     * Mirrors iOS `SavedWork.setCoverArtPreference(_:)`.
     */
    fun applyEdit(
        currentRaw: String?,
        currentChangedAt: Instant?,
        selection: CoverArtPreference,
        now: Instant = Instant.now()
    ): CoverArtPreferenceEdit? {
        val targetRaw = when (selection) {
            CoverArtPreference.FollowSettings -> {
                if (CoverArtPreference.resolved(currentRaw) == null) return null
                CoverArtPreference.FOLLOW_RAW
            }
            CoverArtPreference.Embedded, CoverArtPreference.Generated ->
                checkNotNull(selection.storageValue)
        }
        if (currentRaw == targetRaw) return null
        val nowMillis = now.truncatedTo(ChronoUnit.MILLIS)
        val minNext = currentChangedAt?.let { previous ->
            val plusOne = previous.plusMillis(1)
            val truncated = plusOne.truncatedTo(ChronoUnit.MILLIS)
            if (plusOne.isAfter(truncated)) truncated.plusMillis(1) else truncated
        }
        val nextStamp = if (minNext != null && minNext.isAfter(nowMillis)) minNext else nowMillis
        return CoverArtPreferenceEdit(raw = targetRaw, changedAt = nextStamp)
    }

    fun followSettingsEffectiveLabel(globalUseEmbeddedCoverArt: Boolean): String =
        if (globalUseEmbeddedCoverArt) "Work's Art" else "Generated"

    fun followSettingsSummary(globalUseEmbeddedCoverArt: Boolean): String =
        "Currently ${followSettingsEffectiveLabel(globalUseEmbeddedCoverArt)}"
}
