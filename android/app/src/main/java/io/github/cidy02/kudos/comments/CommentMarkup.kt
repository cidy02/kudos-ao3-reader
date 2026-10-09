package io.github.cidy02.kudos.comments

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.FormatListBulleted
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.FormatBold
import androidx.compose.material.icons.outlined.FormatItalic
import androidx.compose.material.icons.outlined.FormatListNumbered
import androidx.compose.material.icons.outlined.FormatQuote
import androidx.compose.material.icons.outlined.FormatSize
import androidx.compose.material.icons.outlined.FormatStrikethrough
import androidx.compose.material.icons.outlined.FormatUnderlined
import androidx.compose.material.icons.outlined.HorizontalRule
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.outlined.Subscript
import androidx.compose.material.icons.outlined.Superscript
import androidx.compose.material.icons.outlined.Title
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectChip
import io.github.cidy02.kudos.ui.subject.SubjectChipStyle

/**
 * AO3 Comment Formatting tags — matching iOS `CommentMarkupTag` (CommentMarkup.swift:30).
 */
enum class CommentMarkupTag(
    val label: String,
    val element: String,
    val icon: ImageVector,
    val group: TagGroup,
    val openTag: String,
    val closeTag: String = "</$element>"
) {
    // Text
    Bold("Bold", "strong", Icons.Outlined.FormatBold, TagGroup.Text, "<strong>", "</strong>"),
    Italic("Italic", "em", Icons.Outlined.FormatItalic, TagGroup.Text, "<em>", "</em>"),
    Underline("Underline", "u", Icons.Outlined.FormatUnderlined, TagGroup.Text, "<u>", "</u>"),
    Strike("Strike", "s", Icons.Outlined.FormatStrikethrough, TagGroup.Text, "<s>", "</s>"),
    Superscript("Superscript", "sup", Icons.Outlined.Superscript, TagGroup.Text, "<sup>", "</sup>"),
    Subscript("Subscript", "sub", Icons.Outlined.Subscript, TagGroup.Text, "<sub>", "</sub>"),
    Small("Small", "small", Icons.Outlined.FormatSize, TagGroup.Text, "<small>", "</small>"),
    Code("Code", "code", Icons.Outlined.Code, TagGroup.Text, "<code>", "</code>"),

    // Blocks & links
    Quote("Quote", "blockquote", Icons.Outlined.FormatQuote, TagGroup.Blocks, "<blockquote>", "</blockquote>"),
    Bullets("Bullets", "ul", Icons.AutoMirrored.Outlined.FormatListBulleted, TagGroup.Blocks, "<ul>\n  <li>", "</li>\n</ul>"),
    Numbers("Numbers", "ol", Icons.Outlined.FormatListNumbered, TagGroup.Blocks, "<ol>\n  <li>", "</li>\n</ol>"),
    Heading("Heading", "h3", Icons.Outlined.Title, TagGroup.Blocks, "<h3>", "</h3>"),
    Divider("Divider", "hr", Icons.Outlined.HorizontalRule, TagGroup.Blocks, "<hr />\n", ""),
    Link("Link", "a", Icons.Outlined.Link, TagGroup.Blocks, "<a href=\"\">", "</a>"),
    Spoiler("Spoiler", "details", Icons.Outlined.VisibilityOff, TagGroup.Blocks, "<details><summary>Spoiler</summary>", "</details>");

    enum class TagGroup(val title: String) {
        Text("Text formatting"),
        Blocks("Blocks & elements")
    }

    companion object {
        val quickBar: List<CommentMarkupTag> = listOf(Bold, Italic, Underline, Strike, Link, Quote)
    }
}

object CommentMarkup {
    val headingLevels = 1..6
    const val defaultHeadingLevel = 3

    /**
     * Applies [tag] around the current selection of [value].
     */
    fun applyTag(tag: CommentMarkupTag, value: TextFieldValue, headingLevel: Int = defaultHeadingLevel): TextFieldValue {
        val text = value.text
        val selection = value.selection
        val min = minOf(selection.start, selection.end)
        val max = maxOf(selection.start, selection.end)

        var replaceStart = min
        var replaceEnd = max
        var bodyStart = min
        var bodyEnd = max
        if (tag == CommentMarkupTag.Heading) {
            // iOS re-levels the whole enclosing heading, even when only a word is selected.
            // TextFieldValue offsets and Kotlin substrings both use UTF-16 code units.
            for (existing in headingLevels) {
                val open = "<h$existing>"
                val close = "</h$existing>"
                val start = text.lastIndexOf(open, (min - 1).coerceAtLeast(0))
                if (start < 0 || start + open.length > min) continue
                val firstClose = text.indexOf(close, start + open.length)
                val end = text.indexOf(close, max)
                val selectionText = text.substring(min, max)
                if (firstClose < min || end < 0 || selectionText.contains(open) || selectionText.contains(close)) continue
                replaceStart = start
                replaceEnd = end + close.length
                bodyStart = start + open.length
                bodyEnd = end
                break
            }
        }
        val before = text.substring(0, replaceStart)
        val selected = text.substring(bodyStart, bodyEnd)
        val after = text.substring(replaceEnd)

        val level = headingLevel.takeIf { it in headingLevels } ?: defaultHeadingLevel
        val open = if (tag == CommentMarkupTag.Heading) "<h$level>" else tag.openTag
        val close = if (tag == CommentMarkupTag.Heading) "</h$level>" else tag.closeTag

        val newText = before + open + selected + close + after
        val newSelection = if (selected.isEmpty()) {
            if (tag == CommentMarkupTag.Link) {
                // Put caret inside href quotes
                TextRange(before.length + 9)
            } else if (close.isEmpty()) {
                TextRange(before.length + open.length)
            } else {
                TextRange(before.length + open.length)
            }
        } else {
            TextRange(before.length + open.length, before.length + open.length + selected.length)
        }

        return TextFieldValue(newText, newSelection)
    }
}

/**
 * Quick formatting bar pinned right above the keyboard (artboard 1ba/1be).
 */
@Composable
fun CommentFormatBar(
    value: TextFieldValue,
    onValueChange: (TextFieldValue) -> Unit,
    onOpenTray: () -> Unit,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    Surface(
        modifier = modifier.fillMaxWidth(),
        color = tokens.background,
        tonalElevation = 1.dp
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState())
                .padding(horizontal = 12.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            for (tag in CommentMarkupTag.quickBar) {
                IconButton(
                    onClick = { onValueChange(CommentMarkup.applyTag(tag, value)) },
                    modifier = Modifier.size(36.dp)
                ) {
                    Icon(
                        imageVector = tag.icon,
                        contentDescription = tag.label,
                        tint = tokens.primaryInk,
                        modifier = Modifier.size(20.dp)
                    )
                }
            }
            Box(
                Modifier
                    .width(1.dp)
                    .height(20.dp)
                    .background(tokens.glassStroke(0.18))
            )
            IconButton(
                onClick = onOpenTray,
                modifier = Modifier.size(36.dp)
            ) {
                Icon(
                    imageVector = Icons.Outlined.MoreHoriz,
                    contentDescription = "More formatting options",
                    tint = tokens.secondaryInk,
                    modifier = Modifier.size(20.dp)
                )
            }
        }
    }
}

/**
 * Full formatting tray modal bottom sheet (artboard 1bf).
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun CommentFormattingTray(
    value: TextFieldValue,
    onValueChange: (TextFieldValue) -> Unit,
    onDismiss: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)
    val tokens = LocalKudosTokens.current

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = tokens.background
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .verticalScroll(rememberScrollState())
                .padding(bottom = 36.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            Text(
                text = "Format Comment",
                fontSize = 18.sp,
                lineHeight = 24.sp,
                fontWeight = FontWeight.Bold,
                color = tokens.primaryInk
            )

            for (group in CommentMarkupTag.TagGroup.entries) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        text = group.title.uppercase(),
                        fontSize = 11.sp,
                        lineHeight = 16.sp,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = 1.sp,
                        color = tokens.secondaryInk
                    )

                    FlowRow(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        for (tag in CommentMarkupTag.entries.filter { it.group == group }) {
                            Surface(
                                modifier = Modifier
                                    .clickable {
                                        onValueChange(CommentMarkup.applyTag(tag, value))
                                        if (tag != CommentMarkupTag.Heading) onDismiss()
                                    },
                                shape = RoundedCornerShape(10.dp),
                                color = tokens.glassFill(0.08)
                            ) {
                                Row(
                                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                                ) {
                                    Icon(
                                        imageVector = tag.icon,
                                        contentDescription = null,
                                        tint = tokens.primaryInk,
                                        modifier = Modifier.size(18.dp)
                                    )
                                    Column {
                                        Text(
                                            text = tag.label,
                                            fontSize = 13.sp,
                                            lineHeight = 18.sp,
                                            fontWeight = FontWeight.Medium,
                                            color = tokens.primaryInk
                                        )
                                        Text(
                                            text = tag.element,
                                            fontSize = 10.sp,
                                            lineHeight = 15.sp,
                                            fontFamily = FontFamily.Monospace,
                                            color = tokens.secondaryInk
                                        )
                                    }
                                }
                            }
                        }
                    }
                    if (group == CommentMarkupTag.TagGroup.Blocks) {
                        FlowRow(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            for (level in CommentMarkup.headingLevels) {
                                Box(
                                    modifier = Modifier.heightIn(min = 44.dp)
                                        .clickable {
                                            onValueChange(CommentMarkup.applyTag(CommentMarkupTag.Heading, value, level))
                                        }
                                        .semantics { contentDescription = "Heading $level" },
                                    contentAlignment = Alignment.Center
                                ) {
                                    SubjectChip("h$level", style = SubjectChipStyle.Neutral)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
