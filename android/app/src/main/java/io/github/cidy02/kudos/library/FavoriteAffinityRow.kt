package io.github.cidy02.kudos.library

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.settings.SettingsPanel
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.SubjectChip
import io.github.cidy02.kudos.ui.subject.SubjectChipStyle
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.SubjectSegmentedControl
import io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale
import io.github.cidy02.kudos.ui.subject.subjectPanel
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

internal fun affinityLogLine(row: ReadingAffinities.Row, scope: FavoriteScope): String {
    var count = "${row.worksRead} work${if (row.worksRead == 1) "" else "s"} read"
    if (scope == FavoriteScope.Tags) count += if (row.worksRead == 1) " carries this tag" else " carry this tag"
    return listOfNotNull(count,
        if (scope == FavoriteScope.Fandoms && row.favorited > 0) "${row.favorited} favorited" else null,
        if (row.totalSeconds > 0) ReadingInsights.durationLabel(row.totalSeconds) else null,
        row.lastRead?.let { "last read ${DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).format(it.atZone(ZoneId.systemDefault()))}" }
    ).joinToString(" · ")
}

internal fun affinityLibraryExtras(row: ReadingAffinities.Row): String? = listOfNotNull(
    if (row.downloadedInLibrary > 0) "${row.downloadedInLibrary} downloaded" else null,
    if (row.savedForLater > 0) "${row.savedForLater} in Saved for Later" else null
).takeIf { it.isNotEmpty() }?.joinToString(" · ")

internal fun affinityUnreadLabel(row: ReadingAffinities.Row): String =
    if (row.unreadInLibrary > 0) "${row.unreadInLibrary} unread work${if (row.unreadInLibrary == 1) "" else "s"}"
    else "No unread works"

internal fun affinityLibraryLine(row: ReadingAffinities.Row): String =
    if (row.unreadInLibrary == 0) "No unread works in your library"
    else listOfNotNull(affinityUnreadLabel(row), affinityLibraryExtras(row)).joinToString(" · ")

internal fun affinityInitials(name: String): String {
    val words = name.split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }
    return (if (words.size >= 2) words[0].take(1) + words[1].take(1)
        else (words.firstOrNull() ?: name).take(2)).uppercase()
}

/** One card for all three aggregate scopes, as FavoriteAffinityRow.swift. */
@Composable
fun FavoriteAffinityRow(row: ReadingAffinities.Row, scope: FavoriteScope,
                        onOpen: () -> Unit, modifier: Modifier = Modifier) {
    val tokens = LocalKudosTokens.current
    val palette = tokens.scopePalette
    val large = isAccessibilityFontScale()
    val tileSize = 38.dp * if (large) LocalDensity.current.fontScale else 1f
    val libraryDestination = scope == FavoriteScope.Fandoms || scope == FavoriteScope.Tags
    val authorDestination = scope == FavoriteScope.Authors && row.username != null
    val log = affinityLogLine(row, scope)
    val library = affinityLibraryLine(row)
    val shape = RoundedCornerShape(16.dp)
    Column(
        modifier.fillMaxWidth().clip(shape).background(tokens.cardFill).background(palette.cardWash)
            .border(0.5.dp, palette.cardBorder, shape)
            .then(if (libraryDestination) Modifier.clickable(onClickLabel = "Shows these works in your Library", onClick = onOpen) else Modifier)
            .semantics(mergeDescendants = true) {
                contentDescription = "${row.name}. $log. $library"
                if (authorDestination) customActions = listOf(CustomAccessibilityAction("Open author page") { onOpen(); true })
            }.padding(horizontal = 14.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(11.dp), verticalAlignment = Alignment.Top) {
            Box(Modifier.size(tileSize).clearAndSetSemantics {}.background(palette.chipFill,
                if (scope == FavoriteScope.Fandoms) RoundedCornerShape(11.dp) else CircleShape), contentAlignment = Alignment.Center) {
                Text(if (scope == FavoriteScope.Tags) "#" else affinityInitials(row.name),
                    fontSize = 15.sp, lineHeight = 19.sp, fontWeight = FontWeight.Bold, color = palette.accent)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(row.name, color = tokens.primaryInk, fontSize = 16.sp, lineHeight = 21.sp,
                        fontWeight = FontWeight.SemiBold, maxLines = if (large) Int.MAX_VALUE else 2,
                        overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                    Icon(Icons.Filled.Star, contentDescription = null, tint = tokens.favoriteGold, modifier = Modifier.size(11.dp))
                }
                Text(log, color = tokens.secondaryInk, fontSize = 11.5.sp, lineHeight = 16.sp)
                if (scope != FavoriteScope.Tags) Text(library,
                    color = if (row.unreadInLibrary > 0) palette.accent else tokens.secondaryInk,
                    fontSize = 11.sp, lineHeight = 16.sp)
            }
            if (authorDestination) IconButton(onClick = onOpen) {
                Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, "Open author page", tint = tokens.tertiaryInk)
            }
        }
        if (scope == FavoriteScope.Tags) {
            SubjectRowSeparator(inset = 0.dp)
            Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Text("IN YOUR LIBRARY", color = tokens.secondaryInk, fontWeight = FontWeight.Bold,
                    fontSize = 8.5.sp, lineHeight = 12.sp, letterSpacing = 0.85.sp)
                Text(affinityUnreadLabel(row), fontSize = 14.sp, lineHeight = 19.sp, fontWeight = FontWeight.SemiBold,
                    color = if (row.unreadInLibrary > 0) palette.accent else tokens.primaryInk)
                val detail = if (row.unreadInLibrary > 0) affinityLibraryExtras(row) else "Everything tagged this way has been opened"
                if (detail != null) Text(detail, fontSize = 11.5.sp, lineHeight = 16.sp, color = tokens.secondaryInk)
            }
        }
    }
}

@Composable
internal fun FavoriteScopesStrip(preferences: FavoritePreferences,
                                 onScope: (FavoriteScope) -> Unit,
                                 onOrder: (ReadingAffinities.Order) -> Unit,
                                 onUnread: (Boolean) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        FavoriteSegments(FavoriteScope.entries, preferences.scope, onScope, { it.title }, "Favorites scope")
        if (preferences.scope != FavoriteScope.Works) {
            FavoriteSegments(ReadingAffinities.Order.entries, preferences.order, onOrder, { it.title }, "Favorites order")
        }
        if (preferences.scope == FavoriteScope.Tags) {
            LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(listOf(false, true)) { unread ->
                    SubjectChip(if (unread) "Unread works" else "All", style = SubjectChipStyle.Pill(preferences.tagsUnreadOnly == unread),
                        palette = LocalKudosTokens.current.scopePalette,
                        modifier = Modifier.semantics { selected = preferences.tagsUnreadOnly == unread }
                            .clickable { onUnread(unread) })
                }
            }
        }
    }
}

@Composable
private fun <T> FavoriteSegments(options: List<T>, selectedOption: T, onSelect: (T) -> Unit,
                                 title: (T) -> String, description: String) {
    val tokens = LocalKudosTokens.current
    if (isAccessibilityFontScale()) {
        SettingsPanel {
            options.forEachIndexed { index, option ->
                if (index > 0) SubjectRowSeparator()
                Text(title(option), color = if (option == selectedOption) tokens.scopePalette.accent else tokens.primaryInk,
                    fontSize = 13.sp, lineHeight = 19.sp, fontWeight = FontWeight.Medium,
                    modifier = Modifier.fillMaxWidth().semantics { selected = option == selectedOption }
                        .clickable(role = Role.RadioButton) { onSelect(option) }.padding(14.dp))
            }
        }
    } else SubjectSegmentedControl(options = options, selected = selectedOption, onSelect = onSelect, title = title,
        contentDescription = description, modifier = Modifier.padding(horizontal = 16.dp))
}

@Composable
internal fun FavoriteAffinityList(state: LibraryUiState, onScope: (FavoriteScope) -> Unit,
                                  onOrder: (ReadingAffinities.Order) -> Unit, onUnread: (Boolean) -> Unit,
                                  onOpen: (FavoriteScope, ReadingAffinities.Row) -> Unit) {
    val preferences = state.favoritePreferences
    val scope = preferences.scope
    val allRows = ReadingAffinities.forScope(scope, state.collectionMembers, state.readingSummaries, preferences.order)
    val rows = if (scope == FavoriteScope.Tags && preferences.tagsUnreadOnly) allRows.filter { it.unreadInLibrary > 0 } else allRows
    val tokens = LocalKudosTokens.current
    val topInset = WindowInsets.systemBars.asPaddingValues().calculateTopPadding()
    LazyColumn(modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(top = topInset + 56.dp, bottom = 18.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        item {
            SubjectHeaderBlock(kicker = "Library", title = "Favorites", palette = tokens.scopePalette,
                subtitle = "${rows.size} ${if (rows.size == 1) scope.singularNoun else scope.title.lowercase()}")
        }
        item { FavoriteScopesStrip(preferences, onScope, onOrder, onUnread) }
        when {
            state.loading -> item { LoadingStateCard("Loading Favorites", Modifier.padding(horizontal = 16.dp)) }
            state.error != null -> item { ErrorStateCard("Favorites", state.error, Modifier.padding(horizontal = 16.dp)) }
            rows.isEmpty() -> item {
                val hiddenByUnread = allRows.isNotEmpty() && scope == FavoriteScope.Tags
                FavoriteAffinityEmptyCard(scope, hiddenByUnread, Modifier.padding(horizontal = 16.dp, vertical = 14.dp))
            }
            else -> {
                item { SectionRuleHeader(scope.title, count = rows.size, modifier = Modifier.padding(top = 18.dp)) }
                items(rows, key = { it.name }) { row ->
                    FavoriteAffinityRow(row, scope, { onOpen(scope, row) }, Modifier.padding(horizontal = 16.dp))
                }
            }
        }
    }
}

@Composable
internal fun FavoriteAffinityEmptyCard(scope: FavoriteScope, hiddenByUnread: Boolean, modifier: Modifier = Modifier) {
    val tokens = LocalKudosTokens.current
    Column(modifier.fillMaxWidth().subjectPanel().padding(horizontal = 14.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(if (hiddenByUnread) "No unread works" else "Nothing read yet", fontSize = 15.sp, lineHeight = 20.sp,
            fontWeight = FontWeight.SemiBold, color = tokens.primaryInk)
        Text(if (hiddenByUnread) "Every work in your library under these tags has been opened. Tap All to see them again."
            else "These ${scope.title.lowercase()} come from works you have read and are ranked by your reading. You don't need to favorite them first.",
            fontSize = 12.5.sp, lineHeight = 18.sp, color = tokens.secondaryInk)
    }
}
