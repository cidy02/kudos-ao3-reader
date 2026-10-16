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
import io.github.cidy02.kudos.writing.WritingMarkup

/**
 * AO3 Comment Formatting tags — matching iOS `CommentMarkupTag` (CommentMarkup.swift:30).
 */
enum class CommentMarkupTag(
    val label: String,
    val element: String,
    val icon: ImageVector,
    val group: TagGroup
) {
    // Text
    Bold("Bold", "strong", Icons.Outlined.FormatBold, TagGroup.Text),
    Italic("Italic", "em", Icons.Outlined.FormatItalic, TagGroup.Text),
    Underline("Underline", "u", Icons.Outlined.FormatUnderlined, TagGroup.Text),
    Strike("Strike", "s", Icons.Outlined.FormatStrikethrough, TagGroup.Text),
    Superscript("Superscript", "sup", Icons.Outlined.Superscript, TagGroup.Text),
    Subscript("Subscript", "sub", Icons.Outlined.Subscript, TagGroup.Text),
    Small("Small", "small", Icons.Outlined.FormatSize, TagGroup.Text),
    Code("Code", "code", Icons.Outlined.Code, TagGroup.Text),

    // Blocks & links
    Quote("Quote", "blockquote", Icons.Outlined.FormatQuote, TagGroup.Blocks),
    Bullets("Bullets", "ul", Icons.AutoMirrored.Outlined.FormatListBulleted, TagGroup.Blocks),
    Numbers("Numbers", "ol", Icons.Outlined.FormatListNumbered, TagGroup.Blocks),
    Heading("Heading", "h3", Icons.Outlined.Title, TagGroup.Blocks),
    Divider("Divider", "hr", Icons.Outlined.HorizontalRule, TagGroup.Blocks),
    Link("Link", "a", Icons.Outlined.Link, TagGroup.Blocks),
    Spoiler("Spoiler", "details", Icons.Outlined.VisibilityOff, TagGroup.Blocks);

    /** What the tray prints under the name: Heading's range of levels, the link's attribute (iOS `tagLabel`). */
    val tagLabel: String
        get() = when (this) {
            Heading -> "h1–h6"
            Link -> "a href"
            else -> element
        }

    enum class TagGroup(val title: String) {
        // iOS's names for the two groups (`AO3Markup.Group`), as its design draws them.
        Text("Text"),
        Blocks("Blocks & links")
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
        // Every other tag is written as the chapter editor writes it, as iOS's `AO3Markup.splice`:
        // the divider after the words on its own line, one list item per line, the spoiler's
        // caret in its summary. The tray has nowhere to ask for a URL, so a link's caret goes
        // inside the empty href with the words as its text (A59).
        val insertion = when (tag) {
            CommentMarkupTag.Heading -> WritingMarkup.Insertion("<h$level>$selected</h$level>", "<h$level>".length, selected.length)
            CommentMarkupTag.Link -> WritingMarkup.Insertion("<a href=\"\">$selected</a>", "<a href=\"".length, 0)
            else -> WritingMarkup.insertion(tag.element, text, bodyStart, bodyEnd) ?: return value
        }
        val start = before.length + insertion.contentOffset
        return TextFieldValue(before + insertion.text + after, TextRange(start, start + insertion.contentLength))
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
                text = "Formatting",
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
                                            text = tag.tagLabel,
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
