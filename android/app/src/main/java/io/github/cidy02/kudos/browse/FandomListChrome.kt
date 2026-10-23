package io.github.cidy02.kudos.browse

import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material.icons.outlined.Description
import androidx.compose.ui.draw.clip
import io.github.cidy02.kudos.ui.subject.subjectPanel
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.setProgress
import kotlin.math.roundToInt
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.unit.Velocity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.foundation.layout.Spacer
import io.github.cidy02.kudos.ui.subject.compactCount
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.network.ao3.browse.AO3Fandom
import io.github.cidy02.kudos.network.ao3.browse.AO3MediaCategory
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectChip
import io.github.cidy02.kudos.ui.subject.SubjectChipStyle
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.SubjectToggle

private val IndexLetters = ('A'..'Z').map { it.toString() } + "#"
private val FavoriteGold = Color(0xFFD4A017)

/** Mint download mark, matching iOS `downloadBadge` (arrow plus a compact count). */
@Composable
private fun DownloadCount(count: Int) {
    if (count <= 0) return
    val tokens = LocalKudosTokens.current
    val tint = SubjectPalette.fromHue(0.4424, tokens.theme).accent
    Row(
        horizontalArrangement = Arrangement.spacedBy(3.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            Icons.Outlined.Download,
            contentDescription = "$count downloaded",
            tint = tint,
            modifier = Modifier.size(13.dp)
        )
        Text(
            text = count.compactCount(),
            color = tint,
            fontSize = 11.5.sp,
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.Medium
        )
    }
}

@Composable
fun fandomListPalette(categoryName: String): SubjectPalette =
    SubjectPalette.fromHue(HomeFacts.coverHue(categoryName), LocalKudosTokens.current.theme)

@Composable
fun FandomListHeader(category: AO3MediaCategory, tally: String, palette: SubjectPalette) {
    SubjectHeaderBlock(
        kicker = "Browse",
        title = category.name,
        palette = palette,
        subtitle = tally
    )
}

@Composable
fun FandomListSortRail(
    sort: FandomFamilySort,
    groupsVariants: Boolean,
    palette: SubjectPalette,
    onSort: (FandomFamilySort) -> Unit,
    onGroupsVariants: (Boolean) -> Unit
) {
    // iOS 1al: one rail, the two orders and then "Group variants" as a chip that is on or off.
    Row(
        modifier = Modifier
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 16.dp)
            .padding(top = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        SortPill("A–Z", sort == FandomFamilySort.Alphabetical, palette) {
            onSort(FandomFamilySort.Alphabetical)
        }
        SortPill("Most works", sort == FandomFamilySort.FamilyTotal, palette) {
            onSort(FandomFamilySort.FamilyTotal)
        }
        SubjectChip(
            text = "Group variants",
            style = SubjectChipStyle.Pill(isSelected = groupsVariants),
            palette = palette,
            modifier = Modifier.toggleable(
                value = groupsVariants,
                role = androidx.compose.ui.semantics.Role.Switch,
                onValueChange = onGroupsVariants
            )
        )
    }
}

@Composable
private fun SortPill(
    text: String,
    selected: Boolean,
    palette: SubjectPalette,
    onClick: () -> Unit
) {
    SubjectChip(
        text = text,
        style = SubjectChipStyle.Pill(isSelected = selected),
        palette = palette,
        modifier = Modifier.clickable(onClick = onClick)
    )
}

@Composable
fun FandomLetterHeader(letter: String, count: Int, palette: SubjectPalette) {
    val tokens = LocalKudosTokens.current
    Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(text = letter, color = palette.accent, fontSize = 15.sp, fontWeight = FontWeight.Bold)
            Text(
                text = count.toString(),
                color = tokens.secondaryInk,
                fontSize = 13.sp,
                fontFamily = FontFamily.Monospace
            )
        }
        Box(
            Modifier
                .padding(top = 4.dp)
                .fillMaxWidth()
                .height(0.5.dp)
                .background(tokens.separator)
        )
    }
}

@Composable
fun FandomFamilyRow(
    family: FandomFamily,
    sort: FandomFamilySort,
    library: FandomLibraryIndex,
    palette: SubjectPalette,
    onOpenFamily: (FandomFamily) -> Unit,
    onOpenMember: (AO3Fandom) -> Unit
) {
    if (family.memberCount == 1) {
        val member = family.members.first()
        SingleFandomRow(member, library, onOpen = { onOpenMember(member.fandom) })
    } else {
        FamilyBlock(family, sort, library, palette, onOpenFamily, onOpenMember)
    }
}

@Composable
private fun SingleFandomRow(
    member: FandomFamily.Member,
    library: FandomLibraryIndex,
    onOpen: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    val large = io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale()
    Row(
        modifier = Modifier
            .fandomCard()
            .clickable(onClick = onOpen)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        if (library.isFavourited(member.originalName)) {
            Icon(Icons.Filled.Star, contentDescription = "Favorite", tint = FavoriteGold, modifier = Modifier.size(14.dp))
        }
        // iOS `FandomListRow`: three tiers, each on its own line and each a step quieter. The
        // qualifier ("(TV)") is what tells fandoms of one name apart, and was not drawn.
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = member.displayName.title,
                    color = tokens.primaryInk,
                    fontSize = 16.sp,
                    modifier = Modifier.weight(1f, fill = false)
                )
                if (!large) DownloadCount(library.downloadCount(member.originalName))
            }
            if (member.displayName.qualifier.isNotBlank()) {
                Text(text = member.displayName.qualifier, color = tokens.secondaryInk, fontSize = 13.sp)
            }
            if (large) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                member.fandom.workCount?.let { Text(groupedCount(it), color = tokens.secondaryInk, fontSize = 13.sp,
                    modifier = Modifier.semantics { contentDescription = "$it works" }) }
                DownloadCount(library.downloadCount(member.originalName))
            }
            member.aliases.forEach { alias ->
                Text(text = alias, color = tokens.secondaryInk, fontSize = 12.sp, fontStyle = aliasStyle(alias))
            }
        }
        if (!large && member.fandom.workCount != null) Text(
            text = groupedCount(member.workCount),
            color = tokens.secondaryInk,
            fontSize = 13.sp,
            style = TabularFigures,
            textAlign = TextAlign.End,
            modifier = Modifier.widthIn(min = 52.dp).semantics { contentDescription = "${member.workCount} works" }
        )
        if (!large && member.fandom.workCount != null) WorksGlyph()
    }
}

/** iOS `.monospacedDigit()`: the app's own face, its figures one width so a column of counts lines up. */
private val TabularFigures = androidx.compose.ui.text.TextStyle(fontFeatureSettings = "tnum")

/** iOS's `doc.text` after a works count: the same on every row, so quiet. */
@Composable
private fun WorksGlyph() {
    Icon(
        Icons.Outlined.Description,
        contentDescription = null,
        tint = LocalKudosTokens.current.secondaryInk,
        modifier = Modifier.size(13.dp)
    )
}

/** iOS `.cardRow()`: each fandom, and each family with its tags, is a card of its own. */
@Composable
private fun Modifier.fandomCard(): Modifier =
    padding(horizontal = 16.dp, vertical = 5.dp).fillMaxWidth().clip(RoundedCornerShape(16.dp)).subjectPanel(16.dp)

@Composable
private fun FamilyBlock(
    family: FandomFamily,
    sort: FandomFamilySort,
    library: FandomLibraryIndex,
    palette: SubjectPalette,
    onOpenFamily: (FandomFamily) -> Unit,
    onOpenMember: (AO3Fandom) -> Unit
) {
    val tokens = LocalKudosTokens.current
    val first = family.members.first()
    val large = io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale()
    Column(modifier = Modifier.fandomCard().padding(vertical = 4.dp)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable { onOpenFamily(family) }
                .padding(horizontal = 16.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(11.dp)
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = family.parsedTitle,
                    color = tokens.primaryInk,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold
                )
                first.aliases.forEach { alias ->
                    Text(text = alias, color = tokens.secondaryInk, fontSize = 12.sp, fontStyle = aliasStyle(alias))
                }
                if (large) {
                    if (sort == FandomFamilySort.FamilyTotal) Text(
                        (if (family.showsApproximateCount) "~" else "") + groupedCount(family.displayedWorkCount),
                        color = tokens.secondaryInk, fontSize = 13.sp)
                    Text("All ${family.memberCount} tags", color = palette.accent, fontSize = 11.sp)
                }
            }
            if (!large) Column(horizontalAlignment = Alignment.End) {
                if (sort == FandomFamilySort.FamilyTotal) {
                    val figure = if (family.showsApproximateCount) {
                        "~${groupedCount(family.displayedWorkCount)}"
                    } else {
                        groupedCount(family.displayedWorkCount)
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(text = figure, color = tokens.primaryInk, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                        WorksGlyph()
                    }
                }
                Text(
                    text = "All ${family.memberCount} tags",
                    color = palette.accent,
                    fontSize = 11.sp,
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.Medium
                )
            }
            Icon(
                Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                contentDescription = null,
                tint = tokens.tertiaryInk,
                modifier = Modifier.padding(top = 4.dp).size(12.dp)
            )
        }
        Column(
            modifier = Modifier.padding(start = 35.dp)
        ) {
            family.members.forEachIndexed { index, member ->
                if (index > 0) {
                    Box(
                        Modifier
                            .padding(end = 16.dp)
                            .fillMaxWidth()
                            .height(0.5.dp)
                            .background(tokens.glassStroke(0.10))
                    )
                }
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onOpenMember(member.fandom) }
                        .padding(end = 16.dp, top = 7.dp, bottom = 7.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(9.dp)
                ) {
                    if (library.isFavourited(member.originalName)) {
                        Icon(Icons.Filled.Star, contentDescription = "Favorite", tint = FavoriteGold, modifier = Modifier.size(14.dp))
                    }
                    Column(Modifier.weight(1f)) {
                        Text(member.qualifierDisplay, color = tokens.primaryInk, fontSize = 15.sp)
                        if (large) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            DownloadCount(library.downloadCount(member.originalName))
                            member.fandom.workCount?.let { Text(groupedCount(it), color = tokens.secondaryInk, fontSize = 12.sp) }
                        }
                    }
                    if (!large) DownloadCount(library.downloadCount(member.originalName))
                    if (!large && member.fandom.workCount != null) Text(
                        text = groupedCount(member.workCount),
                        color = tokens.secondaryInk,
                        fontSize = 12.sp,
                        style = TabularFigures,
                        fontWeight = FontWeight.Medium,
                        textAlign = TextAlign.End,
                        modifier = Modifier.widthIn(min = 52.dp)
                    )
                    Icon(
                        Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                        contentDescription = null,
                        tint = tokens.tertiaryInk,
                        modifier = Modifier.size(12.dp)
                    )
                }
            }
        }
    }
}

@Composable
fun FandomLetterIndex(
    available: Set<String>,
    onPick: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    val letters = IndexLetters.filter { it in available }
    var current by remember(available) { mutableStateOf(letters.firstOrNull()) }
    fun pickLetter(letter: String) {
        current = letter
        onPick(letter)
    }
    Column(
        modifier
            .clearAndSetSemantics {
                contentDescription = "Fandom index"
                stateDescription = current ?: "No sections"
                if (letters.isNotEmpty()) {
                    progressBarRangeInfo = ProgressBarRangeInfo(
                        letters.indexOf(current).coerceAtLeast(0).toFloat(),
                        0f..(letters.size - 1).toFloat(), (letters.size - 2).coerceAtLeast(0))
                    setProgress { value ->
                        val letter = letters[value.roundToInt().coerceIn(letters.indices)]
                        if (letter == current) false else { pickLetter(letter); true }
                    }
                }
            }
            .pointerInput(available) {
                fun pick(y: Float) {
                    val index = ((y / size.height.coerceAtLeast(1).toFloat()) * IndexLetters.size)
                        .toInt()
                        .coerceIn(IndexLetters.indices)
                    val letter = IndexLetters[index]
                    if (letter in available) pickLetter(letter)
                }
                awaitEachGesture {
                    val down = awaitFirstDown()
                    pick(down.position.y)
                    drag(down.id) { change ->
                        pick(change.position.y)
                        if (change.positionChange() != androidx.compose.ui.geometry.Offset.Zero) {
                            change.consume()
                        }
                    }
                }
            },
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        IndexLetters.forEach { letter ->
            Text(
                text = letter,
                color = indexLetterColor(letter in available),
                fontSize = 8.5.sp,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Medium,
                modifier = Modifier.padding(horizontal = 2.dp),
                maxLines = 1
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FandomListFilterSheet(
    options: FandomListFilterOptions,
    families: List<FandomFamily>,
    groupsVariants: Boolean,
    library: FandomLibraryIndex,
    palette: SubjectPalette,
    onApply: (FandomListFilterOptions) -> Unit,
    onDismiss: () -> Unit
) {
    var draft by remember(options) { mutableStateOf(options) }
    val tallies = remember(families, library) { FandomFamilyFilters.tallies(families, library) }
    val remaining = remember(families, draft, library) {
        FandomFamilyFilters.tagCount(FandomFamilyFilters.apply(families, draft, library))
    }
    val tokens = LocalKudosTokens.current
    val keepSheetInPlace = remember {
        object : NestedScrollConnection {
            override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource) = Offset(0f, available.y)
            override suspend fun onPostFling(consumed: Velocity, available: Velocity) = Velocity(0f, available.y)
        }
    }
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = tokens.theme.cardBackdrop,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .fillMaxHeight(0.9f)
                .padding(horizontal = 16.dp)
                .padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Filter", color = tokens.primaryInk, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                TextButton(
                    onClick = { draft = FandomListFilterOptions() },
                    enabled = draft.hasActiveFilters
                ) { Text("Reset") }
            }
            Column(Modifier.weight(1f).nestedScroll(keepSheetInPlace).verticalScroll(rememberScrollState())) {
                SheetLabel("Minimum works")
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    MinimumWorks.entries.forEach { choice ->
                        SubjectChip(
                            text = choice.title,
                            style = SubjectChipStyle.Pill(draft.minimumWorks == choice),
                            palette = palette,
                            modifier = Modifier.clickable { draft = draft.copy(minimumWorks = choice) }
                        )
                    }
                }
                if (draft.minimumWorks != MinimumWorks.Any) {
                    val hidden = tallies.tagsBelowMinimumWorks(draft.minimumWorks)
                    val floor = draft.minimumWorks.title.removeSuffix("+")
                    Text(
                        text = "${groupedCount(hidden)} tags will be hidden because they have fewer than $floor works.",
                        color = tokens.secondaryInk,
                        fontSize = 11.5.sp
                    )
                }
                Spacer(Modifier.height(16.dp))
                SheetLabel("Tag kinds")
                FilterToggle("Hide RPF tags", tagCountLabel(tallies.rpfTags), draft.hideRPF, palette.accent) {
                    draft = draft.copy(hideRPF = it)
                }
                FilterToggle("Hide All Media Types umbrellas", tagCountLabel(tallies.allMediaTypesTags), draft.hideAllMediaTypes, palette.accent) {
                    draft = draft.copy(hideAllMediaTypes = it)
                }
                FilterToggle("Hide Related Fandoms groupings", tagCountLabel(tallies.relatedFandomsTags), draft.hideRelatedFandoms, palette.accent) {
                    draft = draft.copy(hideRelatedFandoms = it)
                }
                Spacer(Modifier.height(16.dp))
                SheetLabel("Yours")
                FilterToggle("Favourited only", tagCountLabel(tallies.favouritedTags), draft.favouritedOnly, palette.accent) {
                    draft = draft.copy(favouritedOnly = it)
                }
                FilterToggle("I have downloads from", tagCountLabel(tallies.downloadTags), draft.downloadsOnly, palette.accent) {
                    draft = draft.copy(downloadsOnly = it)
                }
                Spacer(Modifier.height(16.dp))
                SheetLabel("Grouping")
                FilterToggle(
                    title = "Only fandoms with more than one tag",
                    detail = if (groupsVariants) {
                        val count = tallies.multiTagFamilies
                        if (count == 1) "1 fandom" else "${groupedCount(count)} fandoms"
                    } else {
                        "Turn on Group variants to use this filter"
                    },
                    checked = draft.multiTagOnly && groupsVariants,
                    accent = palette.accent,
                    enabled = groupsVariants
                ) { draft = draft.copy(multiTagOnly = it) }
            }
            TextButton(
                onClick = { onApply(draft) },
                modifier = Modifier
                    .padding(top = 16.dp)
                    .fillMaxWidth()
                    .background(palette.accent, RoundedCornerShape(14.dp))
            ) {
                Text(
                    text = "Show ${groupedCount(remaining)} tags",
                    color = palette.labelOnAccent,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.padding(vertical = 8.dp)
                )
            }
        }
    }
}

@Composable
private fun SheetLabel(text: String) {
    Text(
        text = text.uppercase(),
        color = LocalKudosTokens.current.secondaryInk,
        fontSize = 11.sp,
        fontWeight = FontWeight.SemiBold,
        letterSpacing = 0.8.sp,
        modifier = Modifier.padding(bottom = 6.dp, top = 8.dp)
    )
}

@Composable
private fun FilterToggle(
    title: String,
    detail: String,
    checked: Boolean,
    accent: Color,
    enabled: Boolean = true,
    onChecked: (Boolean) -> Unit
) {
    val tokens = LocalKudosTokens.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(text = title, color = tokens.primaryInk, fontSize = 15.sp)
            Text(text = detail, color = tokens.secondaryInk, fontSize = 12.sp)
        }
        SubjectToggle(
            checked = checked,
            onCheckedChange = onChecked,
            enabled = enabled,
            accent = accent,
            contentDescription = title
        )
    }
}

private fun tagCountLabel(count: Int): String =
    if (count == 1) "1 tag" else "${groupedCount(count)} tags"

/** Dim missing index letters without a second text style. */
@Composable
fun indexLetterColor(available: Boolean): Color {
    val ink = LocalKudosTokens.current.secondaryInk
    return if (available) ink else ink.copy(alpha = ink.alpha * 0.28f)
}

/** An alias in italic where its script has one (iOS `aliasText`; A58 #20). */
private fun aliasStyle(alias: String): androidx.compose.ui.text.font.FontStyle =
    if (FandomScript.hasItalicForm(alias)) androidx.compose.ui.text.font.FontStyle.Italic
    else androidx.compose.ui.text.font.FontStyle.Normal
