package io.github.cidy02.kudos.library

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import io.github.cidy02.kudos.app.PrivacyGate
import io.github.cidy02.kudos.app.PrivacyRevealState
import io.github.cidy02.kudos.core.model.PrivacySettings
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map

/**
 * [works] as a screen may read them when it marks, counts or suggests things from the Library
 * (Browse's stars, the badge on an AO3 result you already have, a filter's tag suggestions):
 * without what Hide Mature hides (audit A38). With a settings store, the stricter setting is
 * assumed until the real one has been read.
 */
@Composable
fun rememberShownWorks(
    works: List<SavedWork>,
    settingsRepository: SettingsRepository?,
    privacyGate: PrivacyGate?
): List<SavedWork> {
    val privacy by remember(settingsRepository) {
        settingsRepository?.settings?.map { it.privacy } ?: flowOf(PrivacySettings())
    }.collectAsState(initial = if (settingsRepository == null) PrivacySettings() else LibraryPrivacy.UNREAD_SETTING)
    val reveal by remember(privacyGate) {
        privacyGate?.state ?: MutableStateFlow(PrivacyRevealState())
    }.collectAsState()
    return remember(works, privacy, reveal) { LibraryPrivacy.withoutHidden(works, privacy, reveal) }
}
