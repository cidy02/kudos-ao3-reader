package io.github.cidy02.kudos.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.app.PrivacyRevealState
import io.github.cidy02.kudos.core.model.PrivacySettings
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.works.WorkSearchIndex

/** What iOS `AddLibraryWorksSheet` decides, kept apart from the drawing so it can be tested. */
internal object AddLibraryWorks {
    /**
     * The works the picker may name. A work Hide Mature keeps out of the Library, or draws
     * obscured, is left out until it is revealed: the picker shows titles and authors, and
     * its search would answer for a work it could not show.
     */
    fun eligible(candidates: List<SavedWork>, privacy: PrivacySettings, reveal: PrivacyRevealState): List<SavedWork> =
        candidates.filter { LibraryPrivacy.visibility(it, privacy, reveal) == LibraryPrivacyVisibility.Visible }
            .sortedByDescending { it.dateAdded }

    /** Global Search's matching: every term, across title, author, series and tags. */
    fun matching(eligible: List<SavedWork>, query: String): List<SavedWork> {
        val terms = WorkSearchIndex.terms(query)
        return if (terms.isEmpty()) eligible else eligible.filter { WorkSearchIndex.matches(it, terms) }
    }

    /** The chosen works, in the order the list shows them. */
    fun chosen(eligible: List<SavedWork>, selection: Set<String>): List<SavedWork> = eligible.filter { it.id in selection }

    fun confirmationTitle(count: Int): String = if (count == 0) "Add" else "Add $count"
}

/**
 * iOS `AddLibraryWorksSheet`: opened from inside a collection or a reading queue, to pick
 * Library works and add them there. One picker for both: what differs is which works the
 * destination can still take ([candidates]) and what adding does ([onAdd]).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun AddLibraryWorksSheet(
    destinationName: String,
    scopeName: String,
    candidates: List<SavedWork>,
    privacy: PrivacySettings,
    reveal: PrivacyRevealState,
    onToggleMature: () -> Unit,
    onDismiss: () -> Unit,
    onAdd: (List<SavedWork>) -> Unit
) {
    var query by remember { mutableStateOf("") }
    var selection by remember { mutableStateOf(emptySet<String>()) }
    val openAuthor = io.github.cidy02.kudos.works.detail.LocalOpenAuthor.current
    val eligible = remember(candidates, privacy, reveal) { AddLibraryWorks.eligible(candidates, privacy, reveal) }
    val matches = remember(eligible, query) { AddLibraryWorks.matching(eligible, query) }
    val chosen = AddLibraryWorks.chosen(eligible, selection)

    ModalBottomSheet(onDismissRequest = onDismiss, modifier = Modifier.fillMaxWidth()) {
        AddLibraryWorksContent(
            destinationName = destinationName,
            scopeName = scopeName,
            candidates = candidates,
            eligible = eligible,
            matches = matches,
            chosen = chosen,
            query = query,
            onQueryChange = { query = it },
            selection = selection,
            onSelectionChange = { selection = it },
            privacy = privacy,
            reveal = reveal,
            onToggleMature = onToggleMature,
            onDismiss = onDismiss,
            onAdd = onAdd,
            openAuthor = openAuthor
        )
    }
}

@Composable
internal fun AddLibraryWorksContent(
    destinationName: String,
    scopeName: String,
    candidates: List<SavedWork>,
    eligible: List<SavedWork>,
    matches: List<SavedWork>,
    chosen: List<SavedWork>,
    query: String,
    onQueryChange: (String) -> Unit,
    selection: Set<String>,
    onSelectionChange: (Set<String>) -> Unit,
    privacy: PrivacySettings,
    reveal: PrivacyRevealState,
    onToggleMature: () -> Unit,
    onDismiss: () -> Unit,
    onAdd: (List<SavedWork>) -> Unit,
    openAuthor: (String) -> Unit = io.github.cidy02.kudos.works.detail.LocalOpenAuthor.current
) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Add to $destinationName", style = MaterialTheme.typography.titleLarge,
                maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            // Every works list offers the reveal while Hide Mature is on.
            if (privacy.hideMatureContent && eligible.isNotEmpty()) {
                TextButton(onClick = onToggleMature) { Text(if (reveal.revealAll) "Hide mature" else "Show mature") }
            }
        }
        when {
            // Hide Mature can empty the picker on its own; that is not "nothing to add".
            eligible.isEmpty() && candidates.isNotEmpty() -> EmptyStateCard(
                title = "Mature works are hidden",
                message = "Hide Mature is hiding every work you can add here.",
                primaryActionLabel = "Show mature",
                onPrimaryAction = onToggleMature
            )
            eligible.isEmpty() -> EmptyStateCard(
                title = "No works to add",
                message = "Your Library has no works you can add to this $scopeName."
            )
            else -> {
                OutlinedTextField(
                    value = query,
                    onValueChange = onQueryChange,
                    label = { Text("Search your library") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )
                if (matches.isEmpty()) {
                    EmptyStateCard(
                        title = "No matching works",
                        message = "Your Library has no works matching “$query”.",
                        primaryActionLabel = "Clear Search",
                        onPrimaryAction = { onQueryChange("") }
                    )
                }
                LazyColumn(
                    modifier = Modifier.fillMaxWidth().heightIn(max = 400.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    items(matches, key = { it.id }) { work ->
                        val selected = work.id in selection
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                // One control with a state TalkBack can say (audit A13).
                                .toggleable(value = selected, role = Role.Checkbox) {
                                    onSelectionChange(if (it) selection + work.id else selection - work.id)
                                }
                                .padding(vertical = 4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            Checkbox(checked = selected, onCheckedChange = null)
                            Column(modifier = Modifier.weight(1f)) {
                                Text(work.title.ifBlank { "Untitled work" }, style = MaterialTheme.typography.bodyLarge,
                                    maxLines = 2, overflow = TextOverflow.Ellipsis)
                                if (work.author.isNotBlank()) {
                                    io.github.cidy02.kudos.works.detail.VerifiedAuthorByline(
                                        work.author, work.authorIdentitiesJSON,
                                        includesBy = true,
                                        compact = !io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale(),
                                        onOpenAuthor = { onDismiss(); openAuthor(it) }
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedButton(onClick = onDismiss, modifier = Modifier.weight(1f)) { Text("Cancel") }
            Button(onClick = { onAdd(chosen) }, modifier = Modifier.weight(1f), enabled = chosen.isNotEmpty()) {
                Text(AddLibraryWorks.confirmationTitle(chosen.size))
            }
        }
    }
}
