package io.github.cidy02.kudos.ui.components

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.outlined.ExpandLess
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.core.strippingHtml
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.works.CanonicalWork
import androidx.compose.foundation.background
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Surface
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.filled.Star
import androidx.compose.ui.graphics.Color
import kotlin.math.absoluteValue
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.search.LocalTagSearch
import io.github.cidy02.kudos.search.SearchSubjectField
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import androidx.compose.material3.Checkbox


/**
 * What a blurred mature work tells a screen reader: that it is hidden, and nothing else. It
 * takes everything drawn under the blur out of what accessibility is given. Put it **last**
 * on the blurred surface: before a click on the same chain it would take the click's action
 * too. iOS says the same words (`Features/Privacy/MatureContent.swift`); audits A18-5, A19-8.
 */
fun Modifier.hiddenMatureWorkSemantics(obscured: Boolean, selecting: Boolean = false): Modifier =
    if (!obscured) this else clearAndSetSemantics {
        contentDescription = if (selecting) "Hidden mature work" else "Hidden mature work. Activate to reveal."
    }

/**
 * Dense AO3 work summary for Search / Browse / Account lists.
 *
 * Material 3 [Card] expressing Apple `AO3WorkRow` hierarchy:
 * title → author → fandom → summary → status chips → list stats.
 * Tags use progressive disclosure (expand) so the default row stays scannable.
 *
 * [expandAll] is a batch seed from the parent (Search "Expand all" / "Collapse
 * all"): every time it changes, local expand state is reset to match. Individual
 * cards can still be toggled afterward — expand-all is not a permanent lock.
 *
 * Whole-card tap opens Work Detail. [WorkDetailsIconButton] is the explicit
 * MD3 detail affordance (same destination for remote works until download-into-
 * reader lands).
 */


private fun sensitiveRowBlendOver(base: Color, overlay: Color): Color {
    val a = overlay.alpha
    val inv = 1f - a
    return Color(
        red = base.red * inv + overlay.red * a,
        green = base.green * inv + overlay.green * a,
        blue = base.blue * inv + overlay.blue * a,
        alpha = 1f
    )
}


@OptIn(ExperimentalFoundationApi::class)
@Composable
fun SensitiveWorkRow(
    id: String,
    title: String,
    author: String,
    fandoms: List<String>,
    summary: String,
    discoveryTags: List<String>,
    relationships: List<String> = emptyList(),
    characters: List<String> = emptyList(),
    freeforms: List<String> = emptyList(),
    warnings: List<String>,
    categories: List<String>,
    rating: String,
    isComplete: Boolean? = null,
    wordCount: Int?,
    chapters: String,
    kudos: Int?,
    comments: Int? = null,
    bookmarks: Int? = null,
    hits: Int? = null,
    language: String? = null,
    isFavorite: Boolean = false,
    obscured: Boolean = false,
    selected: Boolean = false,
    selecting: Boolean = false,
    expandAll: Boolean = false,
    showsZeroStats: Boolean = LocalShowsZeroStats.current,
    mutedHistory: Boolean = false,
    onClick: () -> Unit,
    onReveal: (() -> Unit)? = null,
    onSelect: (() -> Unit)? = null,
    onTagClick: ((String) -> Unit)? = null,
    onTagSearch: ((SearchSubjectField, String) -> Unit)? = null,
    onLongClick: (() -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    var expanded by remember(id) { mutableStateOf(expandAll) }
    LaunchedEffect(expandAll) { expanded = expandAll }
    
    val expandable = summary.length > 120 || fandoms.size > 1 || discoveryTags.isNotEmpty() ||
        relationships.isNotEmpty() || characters.isNotEmpty() || freeforms.isNotEmpty() ||
        warnings.any { it.isNotBlank() }
    
    val tokens = LocalKudosTokens.current
    val palette = SubjectPalette.fromHue(HomeFacts.workHue(fandoms, title), tokens.theme)
    val defaultTagSearch = LocalTagSearch.current
    val cardTap: () -> Unit = {
        when {
            selecting -> onSelect?.invoke()
            obscured -> onReveal?.invoke()
            else -> onClick()
        }
    }
    // A fandom or tag inside a blurred or selectable row is part of the row: the tap reveals
    // or selects. It used to open a search for a fandom the blur was hiding.
    val tagSearch: (SearchSubjectField, String) -> Unit = when {
        obscured || selecting -> { _, _ -> cardTap() }
        onTagSearch != null -> onTagSearch
        else -> { field, tag -> if (onTagClick != null) onTagClick(tag) else defaultTagSearch(field, tag) }
    }

    Box(modifier = modifier.workCardZoomSource(id.toLongOrNull() ?: 0L)) {
        val cardMod = Modifier
            .fillMaxWidth()
            .then(
                if (selected) Modifier.background(MaterialTheme.colorScheme.primaryContainer, MaterialTheme.shapes.medium)
                else Modifier
                    .background(tokens.cardFill, MaterialTheme.shapes.medium)
                    .then(if (mutedHistory) Modifier else Modifier.background(palette.cardWash, MaterialTheme.shapes.medium))
            )
            .combinedClickable(
                onClick = cardTap,
                onLongClick = onLongClick,
                // iOS's hints while selecting ("Double-tap to select this work.").
                onClickLabel = if (!selecting) null else if (selected) "deselect this work" else "select this work"
            )
            // After the click, so its action stays: a blurred row is one button that says
            // nothing of the work. It used to read out the title and author it had just
            // blurred (audit A18-5; iOS `SensitiveWorkRow`, the same words as `WorkLedgerRow`).
            .then(
                if (obscured) Modifier.hiddenMatureWorkSemantics(true, selecting)
                else Modifier.semantics { contentDescription = "$title, by ${author.ifBlank { "Anonymous" }}" }
            )

        Card(
            colors = CardDefaults.cardColors(containerColor = Color.Transparent),
            shape = MaterialTheme.shapes.medium,
            modifier = cardMod
        ) {
            Box(modifier = Modifier.fillMaxWidth().clipToBounds()) {
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    if (selecting) {
                        Checkbox(
                            checked = selected,
                            onCheckedChange = { onSelect?.invoke() },
                            modifier = Modifier.padding(start = 16.dp, top = 12.dp, bottom = 12.dp)
                        )
                    }
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .run { if (obscured) blur(16.dp) else this }
                            .padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(4.dp),
                            verticalAlignment = Alignment.Top
                        ) {
                            if (expandable) {
                                IconButton(
                                    onClick = { expanded = !expanded }
                                ) {
                                    Icon(
                                        imageVector = if (expanded) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore,
                                        contentDescription = if (expanded) "Show less" else "Show more"
                                    )
                                }
                            }
                            Column(
                                modifier = Modifier.weight(1f),
                                verticalArrangement = Arrangement.spacedBy(2.dp)
                            ) {
                                Text(
                                    text = title,
                                    style = MaterialTheme.typography.titleMedium,
                                    color = MaterialTheme.colorScheme.onSurface,
                                    maxLines = 2,
                                    overflow = TextOverflow.Ellipsis
                                )
                                Text(
                                    text = "by ${author.ifBlank { "Anonymous" }}",
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                            if (isFavorite && !selecting) {
                                Icon(
                                    imageVector = Icons.Filled.Star,
                                    contentDescription = "Favorite",
                                    tint = Color(0xFFFFCC00),
                                    modifier = Modifier.padding(8.dp)
                                )
                            }
                        }

                        if (fandoms.isNotEmpty()) {
                            val hidden = if (expanded) 0 else fandoms.size - 1
                            val visibleFandoms = if (expanded) fandoms else fandoms.take(1)
                            visibleFandoms.forEachIndexed { index, fandom ->
                                CardMetaLine(
                                    text = if (index == 0 && hidden > 0) {
                                        "$fandom  +$hidden other${if (hidden == 1) "" else "s"}"
                                    } else {
                                        fandom
                                    },
                                    icon = Icons.AutoMirrored.Outlined.MenuBook,
                                    accessibilityLabel = "Fandom: $fandom",
                                    color = if (mutedHistory) tokens.secondaryInk else MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.clickable {
                                        tagSearch(SearchSubjectField.FANDOM, fandom)
                                    }
                                )
                            }
                        }

                        if (summary.isNotBlank()) {
                            Text(
                                text = summary,
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = if (expanded) Int.MAX_VALUE else 3,
                                overflow = TextOverflow.Ellipsis
                            )
                        }

                        if (expanded) {
                            val hasCategorizedDiscoveryTags = relationships.isNotEmpty() ||
                                characters.isNotEmpty() || freeforms.isNotEmpty()
                            val groups = buildList {
                                if (warnings.isNotEmpty()) {
                                    add(Triple("Archive Warnings", warnings, SearchSubjectField.WARNING))
                                }
                                if (relationships.isNotEmpty()) {
                                    add(Triple("Relationships", relationships, SearchSubjectField.RELATIONSHIP))
                                }
                                if (characters.isNotEmpty()) {
                                    add(Triple("Characters", characters, SearchSubjectField.CHARACTER))
                                }
                                if (freeforms.isNotEmpty()) {
                                    add(Triple("Additional Tags", freeforms, SearchSubjectField.FREEFORM))
                                }
                                if (!hasCategorizedDiscoveryTags && discoveryTags.isNotEmpty()) {
                                    add(Triple("Tags", discoveryTags, SearchSubjectField.FREEFORM))
                                }
                            }
                            groups.forEach { (label, tags, field) ->
                                Text(
                                    text = label,
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                                MetadataChipRow(
                                    labels = tags,
                                    maxItems = 16,
                                    onLabelClick = { tag -> tagSearch(field, tag) }
                                )
                            }
                        }

                        WorkStatusChipRow(
                            stats = statusChips(
                                rating = rating,
                                categories = categories,
                                warnings = warnings,
                                isComplete = isComplete,
                                expanded = expanded
                            )
                        )

                        Spacer(modifier = Modifier.height(2.dp))

                        WorkListStatsRow(
                            stats = listRowStats(
                                language = language,
                                wordCount = wordCount,
                                chapters = chapters,
                                comments = comments,
                                kudos = kudos,
                                bookmarks = bookmarks,
                                hits = hits,
                                showsZeroStats = showsZeroStats
                            )
                        )
                    }
                }
                if (obscured) {
                    Surface(
                        shape = RoundedCornerShape(50),
                        color = tokens.secondaryInk,
                        contentColor = tokens.background,
                        modifier = Modifier.align(Alignment.Center)
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(
                                imageVector = Icons.Filled.VisibilityOff,
                                contentDescription = null,
                                modifier = Modifier.size(16.dp)
                            )
                            Text(
                                text = "Tap to reveal",
                                style = MaterialTheme.typography.labelMedium,
                                maxLines = 1
                            )
                        }
                    }
                }
            }
        }
    }
}


@Composable
fun SensitiveWorkRow(
    work: AO3WorkSummary,
    onOpenWork: (AO3WorkSummary) -> Unit,
    modifier: Modifier = Modifier,
    expandAll: Boolean = false,
    onTagClick: ((String) -> Unit)? = null,
    onTagSearch: ((SearchSubjectField, String) -> Unit)? = null,
    onLongClick: (() -> Unit)? = null
) {
    var showMenu by remember { mutableStateOf(false) }
    
    Box(modifier = modifier) {
        SensitiveWorkRow(
            id = work.id.toString(),
            title = work.title,
            author = work.authorText,
            fandoms = work.fandoms.filter { it.isNotBlank() },
            summary = work.summary,
            discoveryTags = (work.relationships + work.characters + work.freeforms).filter { it.isNotBlank() },
            relationships = work.relationships.filter { it.isNotBlank() },
            characters = work.characters.filter { it.isNotBlank() },
            freeforms = work.freeforms.filter { it.isNotBlank() },
            warnings = work.warnings,
            categories = work.categories,
            rating = work.rating,
            isComplete = work.isComplete,
            wordCount = work.wordCount,
            chapters = work.chapters,
            kudos = work.kudos,
            comments = work.comments,
            bookmarks = work.bookmarks,
            hits = work.hits,
            language = work.language,
            expandAll = expandAll,
            onClick = { onOpenWork(work) },
            onTagClick = onTagClick,
            onTagSearch = onTagSearch,
            onLongClick = onLongClick ?: { showMenu = true }
        )
        
        DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
            DropdownMenuItem(
                text = { Text("Open Work") },
                onClick = {
                    showMenu = false
                    onOpenWork(work)
                }
            )
            DropdownMenuItem(
                text = { Text("Copy Link") },
                onClick = {
                    showMenu = false
                }
            )
        }
    }
}


@Composable
fun SensitiveWorkRow(
    work: SavedWork,
    onOpenWork: (String) -> Unit,
    modifier: Modifier = Modifier,
    expandAll: Boolean = false,
    selecting: Boolean = false,
    selected: Boolean = false,
    obscured: Boolean = false,
    onSelect: (() -> Unit)? = null,
    onReveal: (() -> Unit)? = null,
    onTagClick: ((String) -> Unit)? = null,
    onTagSearch: ((SearchSubjectField, String) -> Unit)? = null,
    onLongClick: (() -> Unit)? = null,
    showsZeroStats: Boolean = LocalShowsZeroStats.current,
    mutedHistory: Boolean = false
) {
    SensitiveWorkRow(
        id = work.id,
        title = work.title,
        author = work.author,
        fandoms = work.workFandoms,
        summary = remember(work.summary) { work.summary.strippingHtml() },
        discoveryTags = (work.workRelationships + work.workCharacters + work.workFreeforms),
        relationships = work.workRelationships,
        characters = work.workCharacters,
        freeforms = work.workFreeforms,
        warnings = work.workWarnings,
        categories = work.workCategories,
        rating = work.rating,
        isComplete = work.isComplete,
        wordCount = work.wordCount,
        chapters = work.chapters,
        kudos = work.kudos,
        comments = work.comments,
        bookmarks = work.bookmarks,
        hits = work.hits,
        language = work.language,
        isFavorite = work.isFavorite,
        obscured = obscured,
        selecting = selecting,
        selected = selected,
        expandAll = expandAll,
        onClick = { onOpenWork(work.id) },
        onSelect = onSelect,
        onReveal = onReveal,
        onTagClick = onTagClick,
        onTagSearch = onTagSearch,
        onLongClick = onLongClick,
        showsZeroStats = showsZeroStats,
        mutedHistory = mutedHistory,
        modifier = modifier
    )
}
