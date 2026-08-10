package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.app.PrivacyRevealState
import io.github.cidy02.kudos.core.model.MatureContentMode
import io.github.cidy02.kudos.core.model.PrivacySettings
import io.github.cidy02.kudos.core.model.SavedWork

object LibraryPrivacy {
    /**
     * The single place session reveal is applied, so the rule cannot drift between
     * screens. Apple's equivalent predicate is
     * `hideMature && work.isAdult && !gate.isRevealed(work)`
     * (`Features/Privacy/MatureContent.swift`).
     */
    fun visibility(
        work: SavedWork,
        privacy: PrivacySettings,
        reveal: PrivacyRevealState = PrivacyRevealState()
    ): LibraryPrivacyVisibility {
        if (!privacy.hideMatureContent || !work.isAdultRated()) {
            return LibraryPrivacyVisibility.Visible
        }
        // Reveal beats *both* modes. Consulting it only for Obscure — which is what
        // callers used to do, one layer up, after Hidden items had already been
        // dropped — makes the eye button a dead control in Hide mode: the shelves
        // stay empty and only the icon flips.
        if (reveal.isRevealed(work.id)) return LibraryPrivacyVisibility.Visible
        return when (privacy.matureContentMode) {
            MatureContentMode.Hide -> LibraryPrivacyVisibility.Hidden
            MatureContentMode.Obscure -> LibraryPrivacyVisibility.Obscured
        }
    }

    private fun SavedWork.isAdultRated(): Boolean {
        val normalized = rating.trim().lowercase()
        return normalized == "mature" ||
            normalized == "explicit" ||
            normalized.contains("mature") ||
            normalized.contains("explicit")
    }
}
