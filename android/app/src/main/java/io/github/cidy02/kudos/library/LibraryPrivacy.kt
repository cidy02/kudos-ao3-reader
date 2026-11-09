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

    /**
     * [works] without what Hide Mature hides, for a screen that marks, counts or ranks things
     * by the Library (Browse starred a fandom because of a hidden work).
     */
    fun withoutHidden(works: List<SavedWork>, privacy: PrivacySettings, reveal: PrivacyRevealState): List<SavedWork> =
        works.filter { visibility(it, privacy, reveal) != LibraryPrivacyVisibility.Hidden }

    /** The setting as a screen should assume it before it has been read: nothing mature shown. */
    val UNREAD_SETTING = PrivacySettings(hideMatureContent = true, matureContentMode = MatureContentMode.Hide)

    /** What an obscured work is called wherever it has a row of its own. */
    const val HIDDEN_WORK_TITLE = "Hidden mature work"

    /** The name a row may show for [display]: an obscured work has none of its own. */
    fun shownTitle(display: LibraryDisplayItem): String =
        shownTitle(display.item.work, display.privacyVisibility)

    fun shownTitle(work: SavedWork, visibility: LibraryPrivacyVisibility): String =
        if (visibility != LibraryPrivacyVisibility.Visible) HIDDEN_WORK_TITLE
        else work.title

    /**
     * AO3's own rule (`Taggable#adult?`, iOS `MatureContentRating.isAdult`): only General
     * Audiences and Teen And Up Audiences are not adult. Mature, Explicit, Not Rated, and any
     * rating this build does not recognise are adult. No rating data at all (`null`) fails
     * closed. A blank rating is "not supplied yet": not adult by itself.
     * Whitespace is collapsed and the comparison is case-insensitive.
     */
    fun isAdultRating(rating: String?): Boolean {
        if (rating == null) return true
        val normalized = rating.trim().replace(Regex("\\s+"), " ").lowercase(java.util.Locale.ROOT)
        return normalized != "" &&
            normalized != "general audiences" &&
            normalized != "teen and up audiences"
    }

    /**
     * Hide omits a remote row whose rating is known to be adult. A missing or blank rating is
     * not known, so the row is never omitted: it is blurred in both modes until revealed.
     * iOS `PrivacyGate.isHidden` / `isBlurred` for a remote id.
     */
    fun remoteVisibility(
        remoteId: String,
        rating: String?,
        privacy: PrivacySettings,
        reveal: PrivacyRevealState
    ): LibraryPrivacyVisibility {
        if (!privacy.hideMatureContent || reveal.isRevealed(remoteId)) {
            return LibraryPrivacyVisibility.Visible
        }
        if (rating.isNullOrBlank()) return LibraryPrivacyVisibility.Obscured
        if (!isAdultRating(rating)) return LibraryPrivacyVisibility.Visible
        return when (privacy.matureContentMode) {
            MatureContentMode.Hide -> LibraryPrivacyVisibility.Hidden
            MatureContentMode.Obscure -> LibraryPrivacyVisibility.Obscured
        }
    }

    /**
     * A rated local copy speaks for a remote blurb that has not supplied a rating yet
     * (iOS `remoteDefersToLocal`). A blank local rating does not.
     */
    fun remoteDefersToLocal(localRating: String, remoteRating: String?): Boolean =
        localRating.isNotEmpty() && remoteRating.isNullOrBlank()

    /**
     * How a remote listing is drawn. A library match that is still on the shelf uses the
     * local rule, and a known-adult remote rating conceals that card too. A blank remote
     * rating blurs unless the local copy already has a rating. Callers that have already
     * dropped a hidden local pass `local = null`, so a safe remote listing stays.
     */
    fun remoteRowVisibility(
        remoteId: String,
        rating: String?,
        local: SavedWork?,
        privacy: PrivacySettings,
        reveal: PrivacyRevealState
    ): LibraryPrivacyVisibility {
        // Revealing the library copy reveals its AO3 listing too: they are the same work.
        if (local != null && reveal.isRevealed(local.id)) return LibraryPrivacyVisibility.Visible
        val remote = remoteVisibility(remoteId, rating, privacy, reveal)
        if (local == null) return remote
        val localVisibility = visibility(local, privacy, reveal)
        if (localVisibility == LibraryPrivacyVisibility.Hidden) return remote
        val defer = remoteDefersToLocal(local.rating, rating)
        if (remote == LibraryPrivacyVisibility.Hidden && !defer) return LibraryPrivacyVisibility.Hidden
        if (localVisibility == LibraryPrivacyVisibility.Obscured ||
            (remote == LibraryPrivacyVisibility.Obscured && !defer)
        ) {
            return LibraryPrivacyVisibility.Obscured
        }
        return LibraryPrivacyVisibility.Visible
    }

    fun keepsRemoteRow(
        remoteId: String,
        rating: String?,
        local: SavedWork?,
        privacy: PrivacySettings,
        reveal: PrivacyRevealState
    ): Boolean = remoteRowVisibility(remoteId, rating, local, privacy, reveal) != LibraryPrivacyVisibility.Hidden

    private fun SavedWork.isAdultRated(): Boolean = isAdultRating(rating)
}
