package io.github.cidy02.kudos.reader

import androidx.compose.foundation.lazy.items
import androidx.compose.material3.HorizontalDivider
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.BorderColor
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.core.model.ReadingAnnotation
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SwipeAction
import io.github.cidy02.kudos.ui.subject.SwipeActionRow
import io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale
import io.github.cidy02.kudos.ui.subject.SubjectSegmentedControl
import io.github.cidy02.kudos.ui.subject.ToolbarCircleButton
import kotlin.math.roundToInt

/**
 * Contents sheet matching iOS `ReaderContentsSheet.swift`:
 * Segmented control for Contents, Bookmarks, and Highlights.
 * Highlights display with a quote bar in their saved highlight swatch color.
 */
@Composable
fun ReaderContentsSheet(
    entries: List<ReaderTocEntry>,
    bookmarks: List<ReadingAnnotation>,
    highlights: List<ReadingAnnotation>,
    initialTab: Int = 0,
    onSelectEntry: (ReaderTocEntry) -> Unit,
    onSelectAnnotation: (ReadingAnnotation) -> Unit,
    onDeleteAnnotation: (ReadingAnnotation) -> Unit,
    onBookmarkEntry: ((ReaderTocEntry) -> Unit)? = null,
    onAddNoteToEntry: ((ReaderTocEntry) -> Unit)? = null,
    modifier: Modifier = Modifier,
    /** Closes the sheet: the tick its sibling sheets have beside their titles. */
    onDone: (() -> Unit)? = null,
    /** Where in the work a chapter starts, as a whole percent (iOS `chapterStartPercent`). */
    startPercent: (ReaderTocEntry) -> Int? = { null }
) {
    val tokens = LocalKudosTokens.current
    var selectedTab by remember { mutableIntStateOf(initialTab.coerceIn(0, 2)) }
    val tabs = listOf("Contents", "Bookmarks", "Highlights")

    Column(
        modifier = modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .padding(bottom = 16.dp)
    ) {
        // A title and Done, as this reader's other sheets (Find in Work, Display & Themes) and
        // as iOS. This one opened on a bare row of tabs.
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("Contents", color = tokens.primaryInk, fontSize = 17.sp, fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f))
            if (onDone != null) {
                ToolbarCircleButton(onClick = onDone, accessibilityName = "Done") {
                    Icon(Icons.Filled.Check, contentDescription = null, tint = tokens.accentInk)
                }
            }
        }
        // The app's segmented control, as iOS draws it and as every other choice of this kind
        // in the app. It was Material's row of tabs, on a strip of another colour.
        SubjectSegmentedControl(
            options = tabs.indices.toList(),
            selected = selectedTab,
            onSelect = { selectedTab = it },
            title = { tabs[it] },
            contentDescription = "Section",
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
        )

        when (selectedTab) {
            0 -> {
                // Chapters
                if (entries.isEmpty()) {
                    SheetEmptyState(
                        icon = Icons.Filled.Bookmark,
                        title = "No Chapters",
                        message = "No chapters available."
                    )
                } else {
                    LazyColumn(
                        contentPadding = PaddingValues(bottom = 16.dp)
                    ) {
                        itemsIndexed(entries, key = { _, entry -> "${entry.depth}:${entry.href}:${entry.title}" }) { index, entry ->
                            val percent = startPercent(entry)
                            val actions = buildList {
                                add(SwipeAction("Go", Icons.AutoMirrored.Filled.ArrowForward, tokens.scopePalette.accent) {
                                    onSelectEntry(entry)
                                })
                                if (percent != null) {
                                    if (onBookmarkEntry != null) add(SwipeAction("Bookmark", Icons.Filled.Bookmark, Color(0xFFFF9500)) {
                                        onBookmarkEntry(entry)
                                    })
                                    if (onAddNoteToEntry != null) add(SwipeAction("Add Note", Icons.Filled.BorderColor, Color.Gray) {
                                        onAddNoteToEntry(entry)
                                    })
                                }
                            }
                            SwipeActionRow(leading = emptyList(), trailing = actions) {
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .background(tokens.background)
                                        .clickable { onSelectEntry(entry) }
                                        // TalkBack can't swipe a row open: the same actions are in its
                                        // actions menu, as iOS's swipe actions are in VoiceOver's rotor.
                                        .semantics {
                                            customActions = actions.map { CustomAccessibilityAction(it.label) { it.onClick(); true } }
                                        }
                                        .padding(
                                            start = (20 + entry.depth * 16).dp,
                                            end = 20.dp,
                                            top = 12.dp,
                                            bottom = 12.dp
                                        ),
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Text(
                                        text = entry.title,
                                        style = MaterialTheme.typography.bodyLarge,
                                        color = tokens.primaryInk,
                                        maxLines = if (isAccessibilityFontScale()) 5 else 2,
                                        overflow = TextOverflow.Ellipsis,
                                        modifier = Modifier.weight(1f)
                                    )
                                    if (percent != null) Text(
                                        text = "$percent%",
                                        style = MaterialTheme.typography.labelSmall,
                                        fontFamily = FontFamily.Monospace,
                                        color = tokens.secondaryInk
                                    )
                                }
                            }
                            if (index < entries.lastIndex) HorizontalDivider(Modifier.testTag("Contents separator").padding(start = 20.dp), thickness = 0.5.dp, color = tokens.separator)
                        }
                    }
                }
            }
            1 -> {
                // Bookmarks
                if (bookmarks.isEmpty()) {
                    SheetEmptyState(
                        icon = Icons.Filled.Bookmark,
                        title = "No Bookmarks Yet",
                        message = "Bookmarks you add while reading will appear here."
                    )
                } else {
                    LazyColumn(
                        contentPadding = PaddingValues(bottom = 16.dp)
                    ) {
                        items(bookmarks, key = { it.id }) { annotation ->
                            BookmarkRow(
                                annotation = annotation,
                                onSelect = { onSelectAnnotation(annotation) },
                                onDelete = { onDeleteAnnotation(annotation) }
                            )
                        }
                    }
                }
            }
            2 -> {
                // Highlights
                if (highlights.isEmpty()) {
                    SheetEmptyState(
                        icon = Icons.Filled.BorderColor,
                        title = "No Highlights Yet",
                        message = "Highlights and notes you add while reading will appear here. Swipe a row to delete, or tap to edit."
                    )
                } else {
                    LazyColumn(
                        contentPadding = PaddingValues(bottom = 16.dp)
                    ) {
                        items(highlights, key = { it.id }) { annotation ->
                            HighlightRow(
                                annotation = annotation,
                                onSelect = { onSelectAnnotation(annotation) },
                                onDelete = { onDeleteAnnotation(annotation) }
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun BookmarkRow(
    annotation: ReadingAnnotation,
    onSelect: () -> Unit,
    onDelete: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    val title = annotation.chapterTitle.ifBlank { "In this work" }
    val percent = (annotation.progression * 100).roundToInt()

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onSelect)
            .padding(horizontal = 20.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(title, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge,
                    color = tokens.primaryInk, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text("$percent%", style = MaterialTheme.typography.labelSmall,
                    fontFamily = FontFamily.Monospace, color = tokens.secondaryInk)
            }
            if (annotation.selectedText.isNotBlank()) Text(annotation.selectedText,
                style = MaterialTheme.typography.bodyMedium, color = tokens.primaryInk, maxLines = 3,
                overflow = TextOverflow.Ellipsis)
            if (annotation.note.isNotBlank()) Text(annotation.note,
                style = MaterialTheme.typography.bodySmall, color = tokens.secondaryInk, maxLines = 3,
                overflow = TextOverflow.Ellipsis)
        }
        TextButton(onClick = onDelete) {
            Text("Delete", color = MaterialTheme.colorScheme.error)
        }
    }
}

@Composable
private fun HighlightRow(
    annotation: ReadingAnnotation,
    onSelect: () -> Unit,
    onDelete: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    val title = annotation.chapterTitle.ifBlank { "In this work" }
    val percent = (annotation.progression * 100).roundToInt()
    val swatchColor = ReadingAnnotationColor.fromRaw(annotation.colorRaw).color

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onSelect)
            .padding(horizontal = 20.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.Top
    ) {
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            // Chapter title caption + progress
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.labelMedium,
                    color = tokens.secondaryInk,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )
                Text(
                    text = "$percent%",
                    style = MaterialTheme.typography.labelSmall,
                    fontFamily = FontFamily.Monospace,
                    color = tokens.secondaryInk
                )
            }

            // Quoted text with highlight color quote bar
            if (annotation.selectedText.isNotBlank()) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        modifier = Modifier
                            .width(3.dp)
                            .height(28.dp)
                            .clip(RoundedCornerShape(1.5.dp))
                            .background(swatchColor)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = annotation.selectedText,
                        style = MaterialTheme.typography.bodyMedium,
                        color = tokens.primaryInk,
                        maxLines = 3,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }

            // User note if present
            if (annotation.note.isNotBlank()) {
                Text(
                    text = annotation.note,
                    style = MaterialTheme.typography.bodySmall,
                    color = tokens.secondaryInk,
                    maxLines = 3,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }

        IconButton(onClick = onDelete) {
            Icon(
                imageVector = Icons.Filled.Delete,
                contentDescription = "Delete",
                tint = tokens.secondaryInk,
                modifier = Modifier.size(20.dp)
            )
        }
    }
}

@Composable
private fun SheetEmptyState(
    icon: ImageVector,
    title: String,
    message: String
) {
    val tokens = LocalKudosTokens.current

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 32.dp, vertical = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = tokens.secondaryInk,
            modifier = Modifier.size(44.dp)
        )
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            color = tokens.primaryInk,
            textAlign = TextAlign.Center
        )
        Text(
            text = message,
            style = MaterialTheme.typography.bodyMedium,
            color = tokens.secondaryInk,
            textAlign = TextAlign.Center
        )
    }
}
