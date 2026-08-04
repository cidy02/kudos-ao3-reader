package io.github.cidy02.kudos.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalContext
import io.github.cidy02.kudos.KudosApplication
import kotlinx.coroutines.launch

/**
 * Persisted collapse state for carousel/shelf sections, shared by Home and
 * Library (iOS backs the same thing with `@AppStorage`).
 *
 * Both screens previously used a `remember { mutableStateMapOf() }`, so a
 * collapsed shelf silently re-expanded on every navigation.
 */
class CollapsedSections internal constructor(
    private val collapsedIds: Set<String>,
    private val setCollapsed: (String, Boolean) -> Unit
) {
    operator fun get(sectionId: String): Boolean = sectionId in collapsedIds

    fun toggle(sectionId: String) {
        setCollapsed(sectionId, sectionId !in collapsedIds)
    }
}

/**
 * Reads the shared collapse set off the app container, the same way
 * `SettingsScreen` reaches the container for repositories the nav host doesn't
 * thread through. Falls back to in-memory-only when there is no container
 * (previews/tests), so callers never need a null branch.
 */
@Composable
fun rememberCollapsedSections(): CollapsedSections {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val repository = remember(context) {
        (context.applicationContext as? KudosApplication)?.container?.settingsRepository
    }
    val collapsedIds by (repository?.collapsedSections
        ?: kotlinx.coroutines.flow.flowOf(emptySet()))
        .collectAsState(initial = emptySet())

    // No container (preview/test): keep the old session-only behaviour.
    val fallback = remember { mutableSetOf<String>() }
    return remember(collapsedIds, repository) {
        if (repository == null) {
            CollapsedSections(fallback) { id, collapsed ->
                if (collapsed) fallback.add(id) else fallback.remove(id)
            }
        } else {
            CollapsedSections(collapsedIds) { id, collapsed ->
                scope.launch { repository.setSectionCollapsed(id, collapsed) }
            }
        }
    }
}
