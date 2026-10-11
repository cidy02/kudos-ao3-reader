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

    /**
     * The works a small cover or a list of names may show. An obscured work is drawn as
     * "Hidden mature work" where it has a card of its own; where there is no such card (a
     * collection tile's covers) it is left out, as a hidden one already is.
     */
    fun nameableWorks(items: List<LibraryDisplayItem>): List<SavedWork> =
        items.filter { it.privacyVisibility == LibraryPrivacyVisibility.Visible }.map { it.item.work }

    /** What an obscured work is called wherever it has a row of its own. */
    const val HIDDEN_WORK_TITLE = "Hidden mature work"

    /** The name a row may show for [display]: an obscured work has none of its own. */
    fun shownTitle(display: LibraryDisplayItem): String =
        if (display.privacyVisibility == LibraryPrivacyVisibility.Obscured) HIDDEN_WORK_TITLE
        else display.item.work.title

    private fun SavedWork.isAdultRated(): Boolean {
        val normalized = rating.trim().lowercase()
        return normalized == "mature" ||
            normalized == "explicit" ||
            normalized.contains("mature") ||
            normalized.contains("explicit")
    }
}
