package io.github.cidy02.kudos.search

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.RemoveCircle
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import io.github.cidy02.kudos.network.ao3.search.AO3TagAutocompleteRepository
import io.github.cidy02.kudos.ui.components.GlassFieldBar
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.ReaderTheme
import io.github.cidy02.kudos.ui.subject.SubjectFieldLabel
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.subjectPanel
import io.github.cidy02.kudos.works.WorkSearchIndex
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.delay

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun FilterTagRow(
    title: String, kind: String, included: String, excluded: String, candidates: List<String>,
    repository: AO3TagAutocompleteRepository?, onChange: (String, String) -> Unit
) {
    var picking by remember { mutableStateOf(false) }
    val includedTags = AO3SearchFilters.commaSeparatedValues(included)
    val excludedTags = AO3SearchFilters.commaSeparatedValues(excluded)
    val selected = (includedTags + excludedTags).distinct().sorted()
    fun state(tag: String) = tagSelection(tag, included, excluded)
    fun cycle(tag: String) {
        val (nextIncluded, nextExcluded) = cycleFilterTag(tag, included, excluded)
        onChange(nextIncluded, nextExcluded)
    }
    SubjectFormRow(title, value = tagSelectionSummary(included, excluded), valueMaxLines = 3,
        showsDisclosure = true, onClick = { picking = true })
    if (selected.isNotEmpty()) {
        // iOS selected-tag capsules, not Material chips. Each tap continues the cycle.
        FlowRow(
            Modifier.fillMaxWidth().padding(horizontal = 13.dp).padding(bottom = 11.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            selected.forEach { tag -> FilterTagCapsule(tag, state(tag)) { cycle(tag) } }
        }
    }
    if (picking) {
        val tokens = LocalKudosTokens.current
        var query by remember { mutableStateOf("") }
        var remote by remember { mutableStateOf<List<String>>(emptyList()) }
        var searching by remember { mutableStateOf(false) }
        val currentToken = currentTagToken(query)
        LaunchedEffect(currentToken, kind, repository) {
            remote = emptyList()
            searching = false
            val term = currentToken
            if (repository != null && term.length >= 2) {
                searching = true
                try {
                    delay(300)
                    val result = repository.autocomplete(kind, term)
                    currentCoroutineContext().ensureActive()
                    if (result is AO3Result.Success) remote = result.value
                } finally {
                    if (currentCoroutineContext().isActive) searching = false
                }
            }
        }
        val needle = WorkSearchIndex.normalize(currentToken)
        // Arbitrary comma-separated entry and library suggestions remain Android extras.
        val typed = AO3SearchFilters.commaSeparatedValues(query)
        val matches = (typed + candidates.filter {
            needle.isEmpty() || WorkSearchIndex.normalize(it).contains(needle)
        } + remote).distinct().filter { it !in selected }
        ModalBottomSheet(
            onDismissRequest = { picking = false },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
            containerColor = tokens.background
        ) {
            Column(
                Modifier.fillMaxWidth().padding(horizontal = SubjectMetrics.headerGutter).padding(bottom = 28.dp),
                verticalArrangement = Arrangement.spacedBy(18.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(title, Modifier.weight(1f), color = tokens.primaryInk,
                        fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
                    IconButton(onClick = { picking = false }) {
                        Icon(Icons.Outlined.Check, "Done", tint = tokens.accent)
                    }
                }
                GlassFieldBar(query, { query = it }, "Search $title", Modifier.fillMaxWidth())
                LazyColumn(Modifier.fillMaxWidth().heightIn(max = 520.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (selected.isNotEmpty()) item {
                        FilterGroup("Selected") {
                            selected.forEachIndexed { index, tag ->
                                if (index > 0) SubjectRowSeparator()
                                FilterFacetRow(tag, state(tag)) { cycle(tag) }
                            }
                        }
                    }
                    item {
                        SubjectFieldLabel("Results")
                    }
                    if (searching || matches.isEmpty()) item {
                        Column(Modifier.subjectPanel()) {
                            if (searching) FilterNote("Searching…", Modifier.padding(13.dp))
                            if (matches.isEmpty()) FilterNote(
                                if (query.isBlank() && repository != null)
                                    "Type above to search AO3 ${title.lowercase()}."
                                else if (query.isBlank()) "Search $title"
                                else "No tags found for “$query”.",
                                Modifier.padding(13.dp)
                            )
                        }
                    }
                    itemsIndexed(matches, key = { _, tag -> tag }) { _, tag ->
                        Column(Modifier.subjectPanel()) {
                            FilterFacetRow(tag, state(tag)) { cycle(tag) }
                        }
                    }
                }
            }
        }
    }
}

/** Same three-state rendering as iOS cyclingFacetRow and TagPickerView.tagRows. */
@Composable
internal fun FilterFacetRow(title: String, state: FilterSelectionState, onClick: () -> Unit) {
    val tokens = LocalKudosTokens.current
    val color = selectionColor(state)
    Row(
        Modifier.fillMaxWidth()
            .background(if (state == FilterSelectionState.INCLUDED) color.copy(alpha = 0.10f) else Color.Transparent)
            .clickable(role = Role.Button, onClick = onClick)
            .semantics(mergeDescendants = true) { stateDescription = state.status }
            .padding(horizontal = 13.dp, vertical = 11.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(title, Modifier.weight(1f),
            color = if (state == FilterSelectionState.EXCLUDED) tokens.secondaryInk else tokens.primaryInk,
            fontSize = 14.5.sp,
            textDecoration = if (state == FilterSelectionState.EXCLUDED) TextDecoration.LineThrough else null)
        if (state != FilterSelectionState.CLEAR) {
            Icon(if (state == FilterSelectionState.INCLUDED) Icons.Default.AddCircle else Icons.Default.RemoveCircle,
                null, tint = color, modifier = Modifier.size(16.dp))
            Text(state.status, color = color, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun FilterTagCapsule(tag: String, state: FilterSelectionState, onClick: () -> Unit) {
    val color = selectionColor(state)
    Row(
        Modifier.clip(RoundedCornerShape(50)).background(color.copy(alpha = 0.15f))
            .clickable(role = Role.Button, onClick = onClick)
            .semantics(mergeDescendants = true) {
                contentDescription = "${if (state == FilterSelectionState.EXCLUDED) "Excluded" else "Included"}: $tag"
                stateDescription = "Tap to ${state.next.status.lowercase()} this tag"
            }.padding(horizontal = 9.dp, vertical = 5.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(if (state == FilterSelectionState.EXCLUDED) Icons.Default.RemoveCircle else Icons.Default.AddCircle,
            null, tint = color, modifier = Modifier.size(13.dp))
        Text(tag, color = color, fontSize = 12.sp,
            textDecoration = if (state == FilterSelectionState.EXCLUDED) TextDecoration.LineThrough else null)
    }
}

// Exact semantic colors in iOS UIComponents/SemanticThemeColors.swift, including Dark/OLED/Sepia.
@Composable
private fun selectionColor(state: FilterSelectionState): Color {
    val theme = LocalKudosTokens.current.theme
    return if (state == FilterSelectionState.EXCLUDED) when (theme) {
        ReaderTheme.Light -> Color(0.80f, 0.15f, 0.15f)
        ReaderTheme.Sepia -> Color(0.62f, 0.20f, 0.14f)
        ReaderTheme.Dark, ReaderTheme.Oled -> Color(0.95f, 0.38f, 0.38f)
    } else when (theme) {
        ReaderTheme.Light -> Color(0.20f, 0.55f, 0.25f)
        ReaderTheme.Sepia -> Color(0.35f, 0.50f, 0.20f)
        ReaderTheme.Dark, ReaderTheme.Oled -> Color(0.40f, 0.78f, 0.45f)
    }
}

private val FilterSelectionState.status: String
    get() = when (this) {
        FilterSelectionState.CLEAR -> "Clear"
        FilterSelectionState.INCLUDED -> "Include"
        FilterSelectionState.EXCLUDED -> "Exclude"
    }
