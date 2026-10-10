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
        // A save, a post or a delete AO3 confirmed: the list this was opened from is read again. It
        // went back to the list as it stood, with the old title or a work that no longer exists (the
        // fault found on iOS as T-379; only the chapter form told the list).
        "edit" -> WritingWorkFormScreen(work.id, repository, auth, onBack, autocomplete, settings, writes,
            onSaved = { onChanged(); onBack() }, seriesRepository = seriesRepository)
        "tags" -> {
            val model = remember(work.id, action) { WritingWorkFormState(work.id, repository, auth, writes, editTagsOnly = true) }
            WritingEditTagsScreen(model, work.title, autocomplete, settings, onBack, onSave = {
                scope.launch { model.save(); if (model.state.value.saved) { onChanged(); onBack() } }
            })
        }
        "chapter" -> {
            val model = remember(work.id, action) { WritingChapterFormState(work.id, null, work.chapters.substringBefore('/').toIntOrNull(),
                repository, auth, writes = writes) }
            WritingChapterFormScreen(model, work.title, onSaved = onChanged, onBack = onBack)
        }
    }
}
