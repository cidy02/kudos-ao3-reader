package io.github.cidy02.kudos.reader

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.ui.subject.KudosTokens
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.ToolbarCircleButton
import kotlinx.coroutines.launch
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.ExperimentalReadiumApi
import kotlin.math.roundToInt

/** Find in Work, using the reader's palette and the iOS sheet's wording/grouping. */

/** One swipe action. Wide enough for "Bookmark" on one line. */
private val SearchActionWidth = 84.dp

@OptIn(ExperimentalMaterial3Api::class, ExperimentalReadiumApi::class)
@Composable
fun ReaderSearchSheet(
    publication: Publication,
    sections: List<ReaderSection>,
    currentSpineIndex: Int?,
    tokens: KudosTokens,
    onDismiss: () -> Unit,
    onSelectHit: (ReaderSearchHit) -> Unit,
    onBookmarkHit: (ReaderSearchHit) -> Unit
) {
    val scope = rememberCoroutineScope()
    val model = remember(publication) { ReaderSearchModel(scope, { ReaderSearch.open(publication, it) }) }
    val state by model.state.collectAsState()
    var query by remember(publication) { mutableStateOf("") }
    val focus = remember { FocusRequester() }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val chapterKey = sections.firstOrNull { it.spineIndex == currentSpineIndex }
        ?.let { ReaderSectionBuilder.hrefKey(it.href) }
    val groups = remember(state.hits, sections, currentSpineIndex) {
        ReaderSearchGrouping.grouped(
            state.hits, { ReaderSectionBuilder.hrefKey(it.locator.href.toString()) },
            sections, currentSpineIndex
        )
    }
    val dismiss = {
        model.reset()
        scope.launch {
            sheetState.hide()
            onDismiss()
        }
        Unit
    }
    DisposableEffect(model) { onDispose { model.reset() } }

    ModalBottomSheet(
        onDismissRequest = {
            model.reset()
            onDismiss()
        },
        sheetState = sheetState,
        containerColor = tokens.background,
        contentColor = tokens.primaryInk,
        dragHandle = {
            Box(
                Modifier.padding(vertical = 12.dp).size(32.dp, 4.dp)
                    .background(tokens.secondaryInk, RoundedCornerShape(2.dp))
            )
        }
    ) {
        CompositionLocalProvider(LocalKudosTokens provides tokens, LocalContentColor provides tokens.primaryInk) {
            LaunchedEffect(focus) { focus.requestFocus() }
            Column(Modifier.fillMaxWidth().fillMaxHeight(0.85f).navigationBarsPadding()) {
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        "Find in Work", style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f)
                    )
                    ToolbarCircleButton(onClick = dismiss, accessibilityName = "Done") {
                        Icon(Icons.Filled.Check, contentDescription = null, tint = tokens.accent)
                    }
                }
                BasicTextField(
                    value = query,
                    onValueChange = {
                        query = it
                        model.search(it, chapterKey)
                    },
                    singleLine = true,
                    textStyle = MaterialTheme.typography.bodyLarge.copy(color = tokens.primaryInk),
                    cursorBrush = SolidColor(tokens.accent),
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.None,
                        autoCorrectEnabled = false,
                        imeAction = ImeAction.Search
                    ),
                    keyboardActions = KeyboardActions(onSearch = { model.search(query, chapterKey, debounce = false) }),
                    modifier = Modifier.padding(horizontal = 16.dp).padding(bottom = 12.dp)
                        .fillMaxWidth().focusRequester(focus),
                    decorationBox = { field ->
                        Row(
                            Modifier.height(48.dp).background(tokens.glassFill(), RoundedCornerShape(11.dp))
                                .padding(horizontal = 12.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(Icons.Filled.Search, contentDescription = null, tint = tokens.secondaryInk)
                            Box(Modifier.weight(1f)) {
                                if (query.isEmpty()) Text("Find in Work", color = tokens.secondaryInk)
                                field()
                            }
                            if (query.isNotEmpty()) {
                                IconButton(onClick = {
                                    query = ""
                                    model.reset()
                                    focus.requestFocus()
                                }) {
                                    Icon(Icons.Filled.Cancel, contentDescription = "Clear search", tint = tokens.secondaryInk)
                                }
                            }
                        }
                    }
                )
                when (state.phase) {
                    ReaderSearchPhase.Idle -> SearchEmptyState(
                        "Find in Work", "Search the text of this work. Tap a result to jump to that passage."
                    )
                    ReaderSearchPhase.Searching -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = tokens.accent)
                    }
                    ReaderSearchPhase.Failed -> SearchEmptyState("Couldn't Search", state.error, failed = true)
                    ReaderSearchPhase.Done -> {
                        if (state.hits.isEmpty()) {
                            // iOS uses ContentUnavailableView.search(text: query), a system-provided string.
                            SearchEmptyState("No Results for “$query”", "Check the spelling or try a new search.")
                        } else {
                            LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(bottom = 16.dp)) {
                                if (state.isSearchingCurrentChapter && groups.firstOrNull()?.spineIndex != currentSpineIndex) {
                                    item(key = "pending") {
                                        SearchGroupTitle("This Chapter")
                                        Row(
                                            Modifier.padding(horizontal = 20.dp, vertical = 12.dp),
                                            verticalAlignment = Alignment.CenterVertically,
                                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                                        ) {
                                            CircularProgressIndicator(Modifier.size(16.dp), color = tokens.accent, strokeWidth = 2.dp)
                                            Text("Searching…", color = tokens.secondaryInk)
                                        }
                                    }
                                }
                                groups.forEach { group ->
                                    item(key = "group:${group.spineIndex}") { SearchGroupTitle(group.title) }
                                    items(group.results, key = { it.id }) { hit ->
                                        LaunchedEffect(hit.id) { model.loadMoreIfNeeded(hit.id) }
                                        SearchResultRow(
                                            hit = hit,
                                            onGo = {
                                onSelectHit(hit)
                                dismiss()
                            },
                                            onBookmark = { onBookmarkHit(hit) }
                                        )
                                    }
                                }
                                if (state.isLoadingMore) {
                                    item(key = "loading") {
                                        Box(Modifier.fillMaxWidth().padding(12.dp), contentAlignment = Alignment.Center) {
                                            CircularProgressIndicator(Modifier.size(24.dp), color = tokens.accent)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SearchEmptyState(title: String, message: String, failed: Boolean = false) {
    val tokens = LocalKudosTokens.current
    Column(
        Modifier.fillMaxSize().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            if (failed) Icons.Filled.Warning else Icons.Filled.Search,
            contentDescription = null, tint = tokens.secondaryInk, modifier = Modifier.size(40.dp)
        )
        Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
        if (message.isNotEmpty()) {
            Text(message, color = tokens.secondaryInk, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp))
        }
    }
}

@Composable
private fun SearchGroupTitle(title: String) {
    val tokens = LocalKudosTokens.current
    Text(
        title, style = MaterialTheme.typography.labelLarge, color = tokens.secondaryInk,
        modifier = Modifier.fillMaxWidth().background(tokens.cardFill).padding(horizontal = 20.dp, vertical = 10.dp)
    )
}

@Composable
private fun SearchResultRow(hit: ReaderSearchHit, onGo: () -> Unit, onBookmark: () -> Unit) {
    val tokens = LocalKudosTokens.current
    val clipboard = LocalClipboardManager.current
    val copy = { clipboard.setText(AnnotatedString(hit.copyText)) }
    var offset by remember { mutableFloatStateOf(0f) }
    var rowWidth by remember { mutableFloatStateOf(1f) }
    var dragging by remember { mutableStateOf(false) }
    val actionWidth = with(LocalDensity.current) { SearchActionWidth.toPx() }
    val revealWidth = (actionWidth * 3).coerceAtMost(rowWidth)
    val displayOffset by animateFloatAsState(offset, animationSpec = if (dragging) snap() else tween(180))

    Box(Modifier.fillMaxWidth().clipToBounds().onSizeChanged { rowWidth = it.width.toFloat() }) {
        // Swipe actions, including full-swipe Go. The row also exposes all three
        // as accessibility actions, so a gesture is never needed to bookmark/copy.
        Row(
            Modifier.matchParentSize().background(tokens.accent).clearAndSetSemantics { },
            horizontalArrangement = Arrangement.End,
            verticalAlignment = Alignment.CenterVertically
        ) {
            // First declared iOS trailing action (Go) is nearest the trailing edge.
            listOf("Copy" to copy, "Bookmark" to onBookmark, "Go" to onGo).forEach { (title, action) ->
                val tint = when (title) {
                    "Go" -> tokens.accent
                    "Bookmark" -> if (tokens.theme.isDarkFamily) Color(0xFFFF9F0A) else Color(0xFFFF9500)
                    else -> Color(0xFF8E8E93)
                }
                TextButton(
                    onClick = { offset = 0f; action() },
                    modifier = Modifier.width(SearchActionWidth).fillMaxHeight().background(tint),
                    contentPadding = PaddingValues(horizontal = 4.dp)
                ) {
                    Text(
                        title, color = Color.White, style = MaterialTheme.typography.labelMedium,
                        maxLines = 1, softWrap = false
                    )
                }
            }
        }
        Column(
            Modifier.offset { IntOffset(displayOffset.roundToInt(), 0) }.fillMaxWidth()
                .background(tokens.background)
                .draggable(
                    state = rememberDraggableState { offset = (offset + it).coerceIn(-rowWidth, 0f) },
                    orientation = Orientation.Horizontal,
                    onDragStarted = { dragging = true },
                    onDragStopped = {
                        dragging = false
                        if (-offset >= rowWidth * 0.85f) {
                            offset = 0f
                            onGo()
                        } else {
                            offset = if (-offset >= revealWidth / 2) -revealWidth else 0f
                        }
                    }
                )
                .clickable { if (offset < 0f) offset = 0f else onGo() }
                .semantics(mergeDescendants = true) {
                    customActions = listOf(
                        CustomAccessibilityAction("Go") { onGo(); true },
                        CustomAccessibilityAction("Bookmark") { onBookmark(); true },
                        CustomAccessibilityAction("Copy") { copy(); true }
                    )
                }
                .padding(horizontal = 20.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            if (hit.chapterTitle.isNotEmpty()) {
                Text(
                    hit.chapterTitle, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold,
                    color = tokens.accent, maxLines = 1, overflow = TextOverflow.Ellipsis
                )
            }
            Text(
                buildAnnotatedString {
                    withStyle(SpanStyle(color = tokens.secondaryInk)) { append(hit.before) }
                    withStyle(SpanStyle(color = tokens.primaryInk, fontWeight = FontWeight.Bold)) { append(hit.match) }
                    withStyle(SpanStyle(color = tokens.secondaryInk)) { append(hit.after) }
                },
                style = MaterialTheme.typography.bodyMedium, maxLines = 5, overflow = TextOverflow.Ellipsis
            )
        }
    }
    HorizontalDivider(color = tokens.separator, thickness = 0.5.dp)
}
