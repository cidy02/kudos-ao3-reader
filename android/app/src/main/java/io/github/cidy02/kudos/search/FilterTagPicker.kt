package io.github.cidy02.kudos.search

import io.github.cidy02.kudos.app.DebugShotEffect
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.material.icons.outlined.Remove
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.Box
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.draw.alpha
import androidx.compose.foundation.border
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
import androidx.compose.material.icons.outlined.RadioButtonUnchecked
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
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
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
import io.github.cidy02.kudos.ui.components.WorkSymbolTile
import io.github.cidy02.kudos.ui.components.WorkSymbolTileView
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
    repository: AO3TagAutocompleteRepository?, fandomContext: List<String>, onChange: (String, String) -> Unit
) {
    var picking by remember { mutableStateOf(false) }
    DebugShotEffect("filter-tags", ready = kind == "fandom") { picking = true }

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
        var popular by remember { mutableStateOf<List<String>>(emptyList()) }
        var loadingPopular by remember { mutableStateOf(false) }
        val fandom = fandomContext.firstOrNull()?.takeIf { it.isNotBlank() && kind != "fandom" }
        LaunchedEffect(fandom, kind, repository) {
            popular = emptyList()
            if (fandom != null && repository != null) {
                loadingPopular = true
                try {
                    val result = repository.popularTags(fandom, kind)
                    currentCoroutineContext().ensureActive()
                    if (result is AO3Result.Success) popular = result.value
                } finally { if (currentCoroutineContext().isActive) loadingPopular = false }
            }
        }
        val showingPopular = query.isBlank() && fandom != null && repository != null
        val currentToken = currentTagToken(query)
        LaunchedEffect(currentToken, kind, repository) {
            remote = emptyList()
            searching = false
            val term = currentToken
            if (repository != null && term.isNotEmpty()) {
                searching = true
                try {
                    delay(300)
                    val result = repository.autocomplete(kind, term, minimumTermLength = 1)
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
        val suggestions = if (showingPopular) popular else if (query.isBlank()) emptyList() else typed + candidates.filter {
            needle.isNotEmpty() && WorkSearchIndex.normalize(it).contains(needle)
        } + remote
        val matches = suggestions.distinct().filter { it !in selected }
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
                        Icon(Icons.Outlined.Check, "Done", tint = tokens.accentInk)
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
                        SubjectFieldLabel(if (showingPopular) "Popular in $fandom" else "Results")
                    }
                    val waiting = searching || (loadingPopular && showingPopular)
                    if (waiting || matches.isEmpty()) item {
                        Column(Modifier.subjectPanel()) {
                            if (waiting) io.github.cidy02.kudos.ui.subject.SubjectSkeletonLoading(
                                if (showingPopular) "Loading…" else "Searching…"
                            ) {
                                Column(Modifier.fillMaxWidth().padding(13.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                    repeat(4) { io.github.cidy02.kudos.ui.subject.SubjectSkeletonBlock() }
                                }
                            }
                            if (!waiting && matches.isEmpty()) FilterNote(
                                if (query.isBlank())
                                    "Type above to search AO3 ${title.lowercase()}."
                                else "No tags found for “$query”.",
                                Modifier.padding(13.dp)
                            )
                            if (!waiting && matches.isEmpty() && query.isBlank() && kind != "fandom" && fandom == null) {
                                FilterNote("Choose a fandom to see its most-used ${title.lowercase()} here.",
                                    Modifier.padding(start = 13.dp, end = 13.dp, bottom = 13.dp))
                            }
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

/**
 * How a facet row draws its state. iOS has two looks and this row is both (`rowHasSymbol`):
 *  - a symbol card (`FilterSymbolChipCard`): 1.5 pt stroke and label in the include / exclude
 *    colour, fill at 0.12 / 0.08, the symbol dimmed to 0.4 when excluded, a filled check or minus
 *    circle at the end and no word;
 *  - a word row (`TagPickerView.tagRows`, a list facet): no stroke, the label primary (secondary
 *    and struck through once excluded), an included row washed at 0.10, and the "Include" /
 *    "Exclude" word with its coloured circle at the end; nothing at all while clear.
 */
internal data class FacetLook(
    val borderWidth: Dp,
    val fillAlpha: Float,
    val labelInStateColour: Boolean,
    val symbolAlpha: Float,
    val word: String?
)

internal fun facetLook(state: FilterSelectionState, rowHasSymbol: Boolean): FacetLook {
    val set = state != FilterSelectionState.CLEAR
    val excluded = state == FilterSelectionState.EXCLUDED
    return if (rowHasSymbol) FacetLook(
        borderWidth = if (set) 1.5.dp else 0.dp,
        fillAlpha = when (state) {
            FilterSelectionState.CLEAR -> 0f
            FilterSelectionState.INCLUDED -> 0.12f
            FilterSelectionState.EXCLUDED -> 0.08f
        },
        labelInStateColour = set,
        symbolAlpha = if (excluded) 0.4f else 1f,
        word = null
    ) else FacetLook(
        borderWidth = 0.dp,
        fillAlpha = if (state == FilterSelectionState.INCLUDED) 0.10f else 0f,
        labelInStateColour = false,
        symbolAlpha = 1f,
        word = when (state) {
            FilterSelectionState.CLEAR -> null
            FilterSelectionState.INCLUDED -> "Include"
            FilterSelectionState.EXCLUDED -> "Exclude"
        }
    )
}

/** Tags the status word, so a test can find it: it is read out by nothing (see [FilterFacetRow]). */
internal const val FACET_STATUS_WORD_TAG = "facetStatusWord"

/**
 * Same three-state rendering as iOS cyclingFacetRow, symbol cards and TagPickerView.tagRows; see
 * [FacetLook]. TalkBack gets the label once: the title's own text when that is the name (the
 * merged node carries it as text), or [accessibilityTitle] as the description with the drawn
 * short title cleared when the two differ. The state is the node's stateDescription, and the
 * drawn word is cleared from the semantics.
 */
@Composable
internal fun FilterFacetRow(
    title: String,
    state: FilterSelectionState,
    symbol: WorkSymbolTile? = null,
    accessibilityTitle: String = title,
    dense: Boolean = false,
    onBackdrop: Boolean = false,
    onClick: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    val color = selectionColor(state)
    val look = facetLook(state, rowHasSymbol = symbol != null)
    val shape = RoundedCornerShape(if (symbol != null) 12.dp else 10.dp)
    val spokenSeparately = accessibilityTitle != title
    Row(
        Modifier.fillMaxWidth()
            .heightIn(min = 48.dp)
            .then(if (onBackdrop) Modifier.clip(shape).background(tokens.cardFill, shape) else Modifier)
            .background(if (look.fillAlpha > 0f) color.copy(alpha = look.fillAlpha) else Color.Transparent, shape)
            .then(if (look.borderWidth > 0.dp) Modifier.border(look.borderWidth, color, shape) else Modifier)
            .clickable(role = Role.Button, onClickLabel = state.nextActionLabel.lowercase(), onClick = onClick)
            .semantics(mergeDescendants = true) {
                if (spokenSeparately) contentDescription = accessibilityTitle
                if (state != FilterSelectionState.CLEAR) stateDescription =
                    if (state == FilterSelectionState.INCLUDED) "Included" else "Excluded"
            }
            .padding(horizontal = if (dense) 8.dp else 10.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(if (dense) 6.dp else 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (symbol != null) WorkSymbolTileView(symbol, 22.dp, Modifier.alpha(look.symbolAlpha))
        Text(title,
            Modifier.weight(1f).then(if (spokenSeparately) Modifier.clearAndSetSemantics { } else Modifier),
            color = when {
                look.labelInStateColour -> color
                state == FilterSelectionState.EXCLUDED -> tokens.secondaryInk
                else -> tokens.primaryInk
            },
            fontSize = if (dense) 13.sp else 14.sp,
            textDecoration = if (state == FilterSelectionState.EXCLUDED) TextDecoration.LineThrough else null)
        if (symbol != null) {
            FacetIndicator(state, color)
        } else if (look.word != null) {
            Row(
                Modifier.testTag(FACET_STATUS_WORD_TAG).clearAndSetSemantics { },
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    if (state == FilterSelectionState.INCLUDED) Icons.Default.AddCircle else Icons.Default.RemoveCircle,
                    null, tint = color, modifier = Modifier.size(16.dp)
                )
                Text(look.word, color = color, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

/** iOS `FilterSymbolChipCard.indicator`: an empty ring, or a filled circle with a check or a minus. */
@Composable
private fun FacetIndicator(state: FilterSelectionState, color: Color) {
    val tokens = LocalKudosTokens.current
    val set = state != FilterSelectionState.CLEAR
    Box(
        Modifier.size(18.dp).clip(CircleShape)
            .then(
                if (set) Modifier.background(color, CircleShape)
                else Modifier.border(1.5.dp, tokens.secondaryInk.copy(alpha = 0.35f), CircleShape)
            ),
        contentAlignment = Alignment.Center
    ) {
        if (set) Icon(
            if (state == FilterSelectionState.INCLUDED) Icons.Outlined.Check else Icons.Outlined.Remove,
            null, tint = Color.White, modifier = Modifier.size(12.dp)
        )
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
                stateDescription = "Tap to ${state.nextActionLabel.lowercase()} this tag"
                customActions = listOf(CustomAccessibilityAction("Cycle tag") { onClick(); true })
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
