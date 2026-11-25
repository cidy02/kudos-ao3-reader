package io.github.cidy02.kudos.core.model

import io.github.cidy02.kudos.backup.BackupMergeService
import java.time.Duration
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
     * Whether a work's resolved choice wants its own art (export and drawing agree).
     * Mirrors iOS `CoverArtPreference.wantsEmbeddedArt(for:defaults:)`.
     */
    fun wantsEmbeddedArt(
        work: SavedWork,
        globalUseEmbeddedCoverArt: Boolean = true
    ): Boolean = wantsEmbeddedArt(globalUseEmbeddedCoverArt, work.coverArtPreferenceRaw)

    /**
     * Merge (Merge / Reconcile / Folder Sync) for a present incoming value, per the contract table.
     * Stamps beyond `now + maxFutureSkew` are clamped on both sides. An absent key never reaches here.
     * Mirrors iOS `CoverArtPreference.incomingWins(localRaw:localStamp:incomingRaw:incomingStamp:now:)`.
     */
    fun incomingWins(
        localRaw: String?,
        localStamp: Instant?,
        incomingRaw: String,
        incomingStamp: Instant?,
        now: Instant = Instant.now(),
        maxFutureSkew: Duration = BackupMergeService.FUTURE_CLOCK_SKEW
    ): Boolean {
        val ceiling = now.plus(maxFutureSkew)
        val local = localStamp?.let { if (it.isAfter(ceiling)) ceiling else it }
        val incoming = incomingStamp?.let { if (it.isAfter(ceiling)) ceiling else it }
        return when {
            local == null && incoming == null -> localRaw == null || incomingRaw > localRaw
            local == null && incoming != null -> true
            local != null && incoming == null -> false
            else -> {
                val l = checkNotNull(local)
                val i = checkNotNull(incoming)
                if (i != l) i.isAfter(l) else incomingRaw > (localRaw ?: "")
            }
        }
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
     * intact).
     *
     * Stamps `changedAt` as `min(max(now, previous + 2 ms), now + maxFutureSkew)` at millisecond
     * precision (2 ms clears ISO-8601 millisecond rounding); a stored stamp already beyond the
     * cap counts as `now` so a fast clock heals on the next edit.
     * Mirrors iOS `SavedWork.setCoverArtPreference(_:)`.
     */
    fun applyEdit(
        currentRaw: String?,
        currentChangedAt: Instant?,
        selection: CoverArtPreference,
        now: Instant = Instant.now(),
        maxFutureSkew: Duration = BackupMergeService.FUTURE_CLOCK_SKEW
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
        val ceiling = nowMillis.plus(maxFutureSkew)
        val effectivePrevious = currentChangedAt?.let { previous ->
            if (previous.isAfter(ceiling)) nowMillis else previous
        }
        val stepped = effectivePrevious?.let { previous ->
            val plusTwo = previous.plusMillis(2)
            val truncated = plusTwo.truncatedTo(ChronoUnit.MILLIS)
            if (plusTwo.isAfter(truncated)) truncated.plusMillis(1) else truncated
        } ?: nowMillis
        val candidate = if (stepped.isAfter(nowMillis)) stepped else nowMillis
        val nextStamp = if (candidate.isAfter(ceiling)) ceiling else candidate
        return CoverArtPreferenceEdit(raw = targetRaw, changedAt = nextStamp)
    }

    fun followSettingsEffectiveLabel(globalUseEmbeddedCoverArt: Boolean): String =
        if (globalUseEmbeddedCoverArt) "Work's Art" else "Generated"

    fun followSettingsSummary(globalUseEmbeddedCoverArt: Boolean): String =
        "Currently ${followSettingsEffectiveLabel(globalUseEmbeddedCoverArt)}"
}
