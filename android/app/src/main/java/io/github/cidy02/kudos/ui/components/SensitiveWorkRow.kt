package io.github.cidy02.kudos.ui.components

import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.ui.subject.HomeStatusArrangement
import io.github.cidy02.kudos.ui.subject.HomeStatusTray
import io.github.cidy02.kudos.ui.subject.SubjectKicker
import io.github.cidy02.kudos.ui.subject.SubjectStateBadge
import io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale
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
import androidx.compose.material.icons.outlined.Event
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
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.stateDescription
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
import io.github.cidy02.kudos.ui.subject.WorkReadingOrDownloadRing
import io.github.cidy02.kudos.ui.subject.downloadDimmed
import io.github.cidy02.kudos.ui.subject.rememberWorkDownloadFraction
import io.github.cidy02.kudos.library.readingProgressFraction
import androidx.compose.material3.Checkbox


/**
 * What a blurred mature work tells a screen reader: that it is hidden, and nothing else. It
 * takes everything drawn under the blur out of what accessibility is given. Put it **last**
 * on the blurred surface: before a click on the same chain it would take the click's action
 * too. iOS says the same words (`Features/Privacy/MatureContent.swift`); audits A18-5, A19-8.
 */
fun Modifier.hiddenMatureWorkSemantics(
    obscured: Boolean, selecting: Boolean = false, isSelected: Boolean = false
): Modifier = if (!obscured) this else clearAndSetSemantics {
    contentDescription = if (selecting) "Hidden mature work" else "Hidden mature work. Activate to reveal."
    if (selecting) {
        selected = isSelected
        stateDescription = if (isSelected) "Selected" else "Not selected"
        // TalkBack says "Double-tap to" before this, so iOS's hint "Double-tap to select this work." reads whole.
        onClick(label = "${if (isSelected) "deselect" else "select"} this work", action = null)
    }
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
    selectionAllowsDetails: Boolean = false,
    expandAll: Boolean = false,
    showsZeroStats: Boolean = LocalShowsZeroStats.current,
    mutedHistory: Boolean = false,
    /** iOS `AO3WorkRow.Presentation.searchLedger`: see [LedgerBody]. */
    ledger: Boolean = false,
    /** The ledger's closing date, as AO3 printed it. */
    dateText: String = "",
    /** With [ledger]: this row is a bookmark, and draws iOS's one bookmark card. */
    bookmark: LedgerBookmark? = null,
    /** Drawn last inside the card, in either form (History's visit line). */
    footer: (@Composable () -> Unit)? = null,
    /**
     * The tray of four symbols beside the title of the detailed card. iOS draws it on an AO3
     * work's card (`AO3WorkRow.standardCard`) and not on a saved work's (`WorkRow`).
     */
    showsStatusTray: Boolean = false,
    /**
     * A saved work's detailed card, iOS `WorkRow`: every fandom is on its line, and the card
     * unfolds beside its title only for a long summary or for tags. An AO3 work's card (`AO3WorkRow`) names one
     * fandom and counts the rest, and unfolds for those and for its warnings too.
     */
    savedWork: Boolean = false,
    /**
     * False where the card's foot carries kudos, comments and hits in a strip of its own (the
     * writer's own works, iOS `showsPerformance`): the line of figures then leaves them out.
     */
    figuresIncludePerformance: Boolean = true,
    onClick: () -> Unit,
    onReveal: (() -> Unit)? = null,
    onSelect: (() -> Unit)? = null,
    onTagClick: ((String) -> Unit)? = null,
    onTagSearch: ((SearchSubjectField, String) -> Unit)? = null,
    onLongClick: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
    authorIdentities: String = "",
    authorNames: List<String> = io.github.cidy02.kudos.works.resolveTappableAuthorNames(null, author),
    leadingProgress: (@Composable () -> Unit)? = null
) {
    var expanded by remember(id) { mutableStateOf(expandAll) }
    LaunchedEffect(expandAll) { expanded = expandAll }
    
    val savedCard = savedWork && !ledger
    val expandable = summary.length > 120 || discoveryTags.isNotEmpty() ||
        relationships.isNotEmpty() || characters.isNotEmpty() || freeforms.isNotEmpty() ||
        (!savedCard && (fandoms.size > 1 || warnings.any { it.isNotBlank() }))
    
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
    // Concealed content never opens a tag search. Remote selection keeps iOS's detail actions;
    // local selection continues to treat the whole row as its selection target.
    val tagSearch: (SearchSubjectField, String) -> Unit = when {
        obscured || (selecting && !selectionAllowsDetails) -> { _, _ -> cardTap() }
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
                    .then(if (mutedHistory) Modifier else Modifier.background(if (savedWork) palette.rowWash else palette.cardWash, MaterialTheme.shapes.medium))
            )
            .combinedClickable(
                onClick = cardTap,
                onLongClick = onLongClick,
                onClickLabel = if (obscured || !selecting) null else if (selected) "deselect this work" else "select this work"
            )
            // After the click, so its action stays: a blurred row is one button that says
            // nothing of the work. It used to read out the title and author it had just
            // blurred (audit A18-5; iOS `SensitiveWorkRow`, the same words as `WorkLedgerRow`).
            .then(
                if (obscured) Modifier.hiddenMatureWorkSemantics(true, selecting, selected)
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
                    leadingProgress?.invoke()
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .run { if (obscured) blur(16.dp) else this }
                            .padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalArrangement = Arrangement.spacedBy(if (ledger) 12.dp else 6.dp)
                    ) {
                        if (ledger) {
                            LedgerBody(
                                title = title, author = author, fandoms = fandoms, summary = summary,
                                tagGroups = buildList {
                                    val named = fandoms.filter { it.isNotBlank() }
                                    if (named.size > 1) add(Triple("Fandoms", named.drop(1), SearchSubjectField.FANDOM))
                                    val listed = warnings.filter { it.isNotBlank() }
                                    if (listed.isNotEmpty()) add(Triple("Archive Warnings", listed, SearchSubjectField.WARNING))
                                    if (relationships.isNotEmpty()) add(Triple("Relationships", relationships, SearchSubjectField.RELATIONSHIP))
                                    if (characters.isNotEmpty()) add(Triple("Characters", characters, SearchSubjectField.CHARACTER))
                                    if (freeforms.isNotEmpty()) add(Triple("Additional Tags", freeforms, SearchSubjectField.FREEFORM))
                                    if (relationships.isEmpty() && characters.isEmpty() && freeforms.isEmpty() &&
                                        discoveryTags.isNotEmpty()) add(Triple("Tags", discoveryTags, SearchSubjectField.FREEFORM))
                                },
                                rating = rating, categories = categories, warnings = warnings, isComplete = isComplete,
                                figures = ledgerMetadata(language, wordCount, chapters, comments, kudos, bookmarks, hits,
                                    showsZeroStats, includesPerformance = bookmark == null && figuresIncludePerformance),
                                dateText = bookmark?.date ?: dateText,
                                dateLabel = if (bookmark == null) "Updated" else "Bookmarked",
                                badges = bookmark?.badges.orEmpty(), footnote = bookmark?.footnote,
                                isFavorite = isFavorite && !selecting,
                                // A bookmark's card has nothing folded away: its note and tags are out.
                                expandable = expandable && bookmark == null, expanded = expanded,
                                // Under the blur, or while selecting, the glyph is part of the row.
                                onToggleExpanded = if (obscured || (selecting && !selectionAllowsDetails)) cardTap else { { expanded = !expanded } },
                                palette = palette, tagSearch = tagSearch
                            )
                        } else {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(4.dp),
                                verticalAlignment = Alignment.Top
                            ) {
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
                                    io.github.cidy02.kudos.works.detail.VerifiedAuthorByline(
                                        author, authorIdentities, authorNames, includesBy = savedCard
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
                                if (savedCard && expandable) {
                                    IconButton(onClick = if (obscured || (selecting && !selectionAllowsDetails)) cardTap else { { expanded = !expanded } }) {
                                        Icon(
                                            imageVector = if (expanded) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore,
                                            contentDescription = if (expanded) "Show less" else "Show more",
                                            tint = palette.accent
                                        )
                                    }
                                }
                                // iOS `standardCard`: AO3's own quadrant beside the title, a glance
                                // at what the chips below say in words. Not spoken (the chips
                                // are), and not at the large text sizes, where it would take the
                                // title's room.
                                if (showsStatusTray && !isAccessibilityFontScale()) {
                                    HomeStatusTray(
                                        rating = rating,
                                        categories = categories,
                                        warnings = warnings,
                                        isComplete = isComplete,
                                        arrangement = HomeStatusArrangement.Grid,
                                        tileSize = 22.dp,
                                        modifier = Modifier.clearAndSetSemantics {}
                                    )
                                }
                            }

                            if (fandoms.isNotEmpty() && savedCard) {
                                // iOS `WorkRow`: the fandoms on one line, all of them.
                                CardMetaLine(
                                    text = fandoms.joinToString(", "),
                                    icon = Icons.AutoMirrored.Outlined.MenuBook,
                                    accessibilityLabel = "Fandom: ${fandoms.joinToString(", ")}",
                                    color = if (mutedHistory) tokens.secondaryInk else MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.clickable { tagSearch(SearchSubjectField.FANDOM, fandoms.first()) }
                                )
                            } else if (fandoms.isNotEmpty()) {
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
                                    if (warnings.isNotEmpty() && !savedCard) {
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
                                        maxItems = tags.size,
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
                            // iOS's standard card closes with the day AO3 gives the work and the unfold control at the foot.
                            if (dateText.isNotBlank() || (!savedCard && expandable)) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    if (dateText.isNotBlank()) {
                                        CardMetaLine(
                                            text = dateText,
                                            icon = androidx.compose.material.icons.Icons.Outlined.Event,
                                            accessibilityLabel = "Updated $dateText",
                                            color = if (mutedHistory) tokens.secondaryInk else MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                    } else {
                                        Spacer(Modifier.weight(1f))
                                    }
                                    if (!savedCard && expandable) {
                                        IconButton(
                                            onClick = { expanded = !expanded }
                                        ) {
                                            Icon(
                                                imageVector = if (expanded) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore,
                                                contentDescription = if (expanded) "Show less" else "Show more",
                                                tint = palette.accent
                                            )
                                        }
                                    }
                                }
                            }
                        }
                        footer?.invoke()
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


/**
 * What a bookmark adds to the ledger card (iOS 1q, `AO3WorkRow.bookmarkCard`): "Rec" and
 * "Private" beside the kicker, the bookmark's own note and tags where the work's summary and
 * tags would be, and the day it was bookmarked closing the line of figures.
 */
class LedgerBookmark(
    val badges: List<String>, val date: String,
    val localFootnote: (@Composable () -> Unit)? = null,
    val footnote: @Composable () -> Unit
)

/**
 * iOS `AO3WorkRow.searchLedgerCard`, which Search, Browse and the AO3 lists draw: the fandom
 * as a kicker, the title and byline beside the tray of four symbols, the summary, then one
 * line of figures in words that ends with the date. It stands in for the fandom line, the row
 * of four word chips and the row of glyphs and numbers. At the large text sizes the tray goes
 * under the names and the date under the figures, as there.
 */
@Composable
private fun LedgerBody(
    title: String,
    author: String,
    fandoms: List<String>,
    summary: String,
    tagGroups: List<Triple<String, List<String>, SearchSubjectField>>,
    rating: String,
    categories: List<String>,
    warnings: List<String>,
    isComplete: Boolean?,
    figures: List<String>,
    dateText: String,
    dateLabel: String,
    badges: List<String>,
    footnote: (@Composable () -> Unit)?,
    isFavorite: Boolean,
    expandable: Boolean,
    expanded: Boolean,
    onToggleExpanded: () -> Unit,
    palette: SubjectPalette,
    tagSearch: (SearchSubjectField, String) -> Unit
) {
    val tokens = LocalKudosTokens.current
    val accessibility = isAccessibilityFontScale()
    val named = fandoms.filter { it.isNotBlank() }
    val identity: @Composable (Modifier) -> Unit = { modifier ->
        Column(modifier, verticalArrangement = Arrangement.spacedBy(5.dp)) {
            // The badges too: a private bookmark of a work that names no fandom had no line to
            // say "Private" on, and said nothing.
            if (named.isNotEmpty() || badges.isNotEmpty()) {
                Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.Top) {
                    named.firstOrNull()?.let { fandom ->
                        SubjectKicker(
                            text = HomeFacts.primaryFandom(named) ?: fandom,
                            palette = palette,
                            trailingCount = if (expanded) 0 else named.size - 1,
                            maxLines = if (accessibility) Int.MAX_VALUE else 1,
                            modifier = Modifier
                                .weight(1f, fill = false)
                                .semantics { contentDescription = "Fandom: $fandom" }
                                .clickable(onClickLabel = "search this fandom") {
                                    tagSearch(SearchSubjectField.FANDOM, fandom)
                                }
                        )
                    }
                    // iOS draws Private and Rec as `SubjectStateBadge`s in the secondary colour (A70).
                    badges.forEach { badge -> SubjectStateBadge(text = badge, color = tokens.secondaryInk) }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = title,
                    color = tokens.primaryInk,
                    fontSize = 19.sp,
                    lineHeight = 24.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = if (accessibility) 3 else 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false)
                )
                if (isFavorite) {
                    Icon(Icons.Filled.Star, contentDescription = "Favorite", tint = Color(0xFFFFCC00),
                        modifier = Modifier.size(16.dp))
                }
            }
            Text(
                text = "by ${author.ifBlank { "Anonymous" }}",
                style = MaterialTheme.typography.bodyMedium,
                color = tokens.secondaryInk,
                maxLines = if (accessibility) 2 else 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
    val signals: @Composable () -> Unit = {
        HomeStatusTray(
            rating = rating,
            categories = categories,
            warnings = warnings,
            isComplete = isComplete,
            arrangement = HomeStatusArrangement.Grid,
            tileSize = 22.dp
        )
    }
    if (accessibility) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            identity(Modifier.fillMaxWidth())
            signals()
        }
    } else {
        Row(horizontalArrangement = Arrangement.spacedBy(13.dp), verticalAlignment = Alignment.Top) {
            identity(Modifier.weight(1f))
            signals()
        }
    }

    footnote?.invoke()

    if (footnote == null && summary.isNotBlank()) {
        Text(
            text = summary,
            style = MaterialTheme.typography.bodyMedium,
            color = tokens.secondaryInk,
            maxLines = if (expanded) Int.MAX_VALUE else 3,
            overflow = TextOverflow.Ellipsis
        )
    }

    if (expanded && footnote == null) {
        tagGroups.forEach { (label, tags, field) ->
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(text = label, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = tokens.tertiaryInk)
                MetadataChipRow(labels = tags, maxItems = tags.size, onLabelClick = { tag -> tagSearch(field, tag) })
            }
        }
    }

    val line = figures.joinToString("  ·  ")
    if (line.isNotEmpty() || dateText.isNotBlank() || expandable) {
        val date: @Composable () -> Unit = {
            if (dateText.isNotBlank()) {
                Text(
                    text = dateText,
                    fontSize = 11.5.sp,
                    color = tokens.secondaryInk,
                    maxLines = 1,
                    softWrap = false,
                    modifier = Modifier.semantics { contentDescription = "$dateLabel $dateText" }
                )
            }
        }
        val unfold: @Composable () -> Unit = {
            if (expandable) {
                Icon(
                    imageVector = if (expanded) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore,
                    contentDescription = if (expanded) "Show less" else "Show more",
                    tint = palette.accent,
                    modifier = Modifier
                        .size(20.dp)
                        .clickable(role = Role.Button, onClick = onToggleExpanded)
                )
            }
        }
        // The date may not wrap; beside the figures at a large size it left them a column a
        // few letters wide (iOS T-386), so there it goes under them.
        if (accessibility) {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                if (line.isNotEmpty()) Text(line, fontSize = 11.5.sp, lineHeight = 17.sp, color = tokens.secondaryInk)
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    date()
                    unfold()
                }
            }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                if (line.isNotEmpty()) {
                    Text(line, fontSize = 11.5.sp, lineHeight = 16.sp, color = tokens.secondaryInk, modifier = Modifier.weight(1f))
                } else {
                    Spacer(Modifier.weight(1f))
                }
                date()
                unfold()
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
    onLongClick: (() -> Unit)? = null,
    ledger: Boolean = false,
    bookmark: LedgerBookmark? = null,
    footer: (@Composable () -> Unit)? = null,
    figuresIncludePerformance: Boolean = true,
    selecting: Boolean = false,
    selected: Boolean = false,
    selectionAllowsDetails: Boolean = false
) {
    val environment = LocalWorkRowEnvironment.current
    val row: @Composable (SavedWork?, Boolean, () -> Unit, () -> Unit) -> Unit = { local, obscured, click, longClick ->
        if (local != null) {
            Column {
                SensitiveWorkRow(work = local, onOpenWork = { click() }, expandAll = expandAll,
                    ledger = ledger, obscured = obscured, onReveal = click,
                    onLongClick = longClick, onTagClick = onTagClick, onTagSearch = onTagSearch,
                    footer = footer)
                if (bookmark != null && !obscured) (bookmark.localFootnote ?: bookmark.footnote).invoke()
            }
        } else {
            SensitiveWorkRow(
                id = work.id.toString(),
                title = work.title,
                author = work.authorText,
                authorIdentities = work.authorIdentitiesJSON, authorNames = work.authors,
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
                ledger = ledger,
                dateText = work.updatedDate,
                bookmark = bookmark,
                footer = footer,
                showsStatusTray = true,
                figuresIncludePerformance = figuresIncludePerformance,
                selecting = selecting,
                selectionAllowsDetails = selectionAllowsDetails,
                selected = selected,
                onClick = click,
                onSelect = { onOpenWork(work) },
                onTagClick = onTagClick,
                onTagSearch = onTagSearch,
                onLongClick = onLongClick ?: longClick
            )
        }
    }
    Box(modifier) {
        if (selecting) {
            row(null, false, { onOpenWork(work) }, {})
        } else if (environment != null) {
            RemoteWorkActionFrame(work, environment, onOpenWork, content = row)
        } else {
            var showMenu by remember(work.id) { mutableStateOf(false) }
            val clipboard = androidx.compose.ui.platform.LocalClipboardManager.current
            row(null, false, { onOpenWork(work) }, { showMenu = true })
            DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                DropdownMenuItem(text = { Text("Open Work") }, onClick = {
                    showMenu = false; onOpenWork(work)
                })
                DropdownMenuItem(text = { Text("Copy Link") }, onClick = {
                    showMenu = false
                    clipboard.setText(androidx.compose.ui.text.AnnotatedString(work.workUrl))
                })
            }
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
    mutedHistory: Boolean = false,
    ledger: Boolean = false,
    footer: (@Composable () -> Unit)? = null,
    downloadFraction: Double? = rememberWorkDownloadFraction(work)
) {
    SensitiveWorkRow(
        id = work.id,
        title = work.title,
        author = work.author,
        authorIdentities = work.authorIdentitiesJSON,
        fandoms = work.workFandoms,
        summary = remember(work.summary) { work.summary.strippingHtml() },
        discoveryTags = (work.workRelationships + work.workCharacters + work.workFreeforms),
        relationships = work.workRelationships,
        characters = work.workCharacters,
        freeforms = work.workFreeforms,
        warnings = work.workWarnings,
        categories = work.workCategories,
        rating = work.rating,
        isComplete = work.knownCompletion,
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
        ledger = ledger,
        footer = footer,
        savedWork = true,
        modifier = modifier.downloadDimmed(if (downloadFraction != null) 1f else 0f),
        leadingProgress = if (downloadFraction != null || work.hasStartedReading) {
            {
                WorkReadingOrDownloadRing(
                    downloadFraction = downloadFraction,
                    progress = work.readingProgressFraction(),
                    state = null,
                    diameter = 48.dp,
                    modifier = Modifier.padding(start = 16.dp)
                )
            }
        } else null
    )
}
