package io.github.cidy02.kudos.writing

import androidx.compose.runtime.*
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.network.ao3.search.AO3TagAutocompleteRepository
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.writing.AO3WorkFormRepository
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import kotlinx.coroutines.launch

/** The row already knows the id. Opening never reads the work to discover it. */
@Composable
internal fun WritingOwnWorkScreen(work: AO3WorkSummary, action: String, repository: AO3WorkFormRepository,
    auth: AO3AuthRepository, writes: AO3WriteRepository, autocomplete: AO3TagAutocompleteRepository?,
    settings: SettingsRepository?, onBack: () -> Unit, onChanged: () -> Unit,
    seriesRepository: io.github.cidy02.kudos.network.ao3.writing.AO3SeriesFormRepository? = null) {
    val scope = rememberCoroutineScope()
    when (action) {
        "edit" -> WritingWorkFormScreen(work.id, repository, auth, onBack, autocomplete, settings, writes,
            onSaved = onBack, seriesRepository = seriesRepository)
        "tags" -> {
            val model = remember(work.id, action) { WritingWorkFormState(work.id, repository, auth, writes, editTagsOnly = true) }
            WritingEditTagsScreen(model, work.title, autocomplete, settings, onBack, onSave = {
                scope.launch { model.save(); if (model.state.value.saved) onBack() }
            })
        }
        "chapter" -> {
            val model = remember(work.id, action) { WritingChapterFormState(work.id, null, work.chapters.substringBefore('/').toIntOrNull(),
                repository, auth, writes = writes) }
            WritingChapterFormScreen(model, work.title, onSaved = onChanged, onBack = onBack)
        }
    }
}
