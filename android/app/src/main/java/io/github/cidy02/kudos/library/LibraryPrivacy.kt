package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.core.model.MatureContentMode
import io.github.cidy02.kudos.core.model.PrivacySettings
import io.github.cidy02.kudos.core.model.SavedWork

object LibraryPrivacy {
    fun visibility(work: SavedWork, privacy: PrivacySettings): LibraryPrivacyVisibility {
        if (!privacy.hideMatureContent || !work.isAdultRated()) {
            return LibraryPrivacyVisibility.Visible
        }
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
