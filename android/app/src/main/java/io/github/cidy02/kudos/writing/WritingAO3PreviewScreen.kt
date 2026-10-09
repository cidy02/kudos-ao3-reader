package io.github.cidy02.kudos.writing

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.network.ao3.writing.AO3ChapterPreview
import io.github.cidy02.kudos.ui.subject.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private data class PreviewRow(val kind: AO3ChapterPreview.Kind, val text: String = "", val paragraph: WritingBufferPreview.Block? = null)

/** Work and chapter previews reuse one lazy, off-main paragraph path. Images never load. */
@Composable
internal fun WritingAO3PreviewScreen(preview: AO3ChapterPreview, subtitle: String, postTitle: String, busy: Boolean,
    error: String?, dismissError: () -> Unit, onBack: () -> Unit, onPost: () -> Unit,
    confirmation: String? = null, screenTag: String = "Writing chapter preview") {
    val tokens = LocalKudosTokens.current
    val palette = tokens.scopePalette
    var rows by remember(preview) { mutableStateOf<List<PreviewRow>?>(null) }
    var confirming by remember(preview) { mutableStateOf(false) }
    LaunchedEffect(preview) {
        rows = withContext(Dispatchers.Default) { preview.blocks.flatMap { block ->
            if (block.kind != AO3ChapterPreview.Kind.Html) listOf(PreviewRow(block.kind, block.text))
            else (WritingBufferPreview.state(block.text) as? WritingBufferPreview.State.Rendered)?.blocks.orEmpty()
                .map { PreviewRow(block.kind, paragraph = it) }
        } }
    }
    val back = { if (!busy) onBack() }
    BackHandler(onBack = back)
    ProvidePushedShellChrome(hasSubjectHeader = true, hideTabBar = true, onBack = back)
    error?.let { WritingErrorAlert("AO3 could not post this", it, dismissError) }
    if (confirming && confirmation != null) WorkPostAlert(confirmation, postTitle,
        onDismiss = { confirming = false }, onConfirm = { confirming = false; onPost() })
    LazyColumn(Modifier.fillMaxSize().subjectScreenWash(palette).testTag(screenTag),
        contentPadding = PaddingValues(bottom = 24.dp)) {
        item {
            Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
            Spacer(Modifier.height(76.dp))
            SubjectHeaderBlock(kicker = "AO3 Account", title = "Preview", subtitle = subtitle, palette = palette, gutter = SubjectMetrics.accountGutter)
            preview.notice?.let { WorkFormFootnote(it) }
        }
        val paragraphs = rows
        if (paragraphs == null) item { Box(Modifier.fillMaxWidth().padding(18.dp), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(color = palette.accent, trackColor = tokens.separator)
        } } else itemsIndexed(paragraphs) { _, row ->
            Column(Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 10.dp)) {
                val paragraph = row.paragraph
                if (paragraph != null) WritingPreviewParagraph(paragraph)
                else Text(row.text, color = if (row.kind == AO3ChapterPreview.Kind.Heading) tokens.primaryInk else tokens.secondaryInk,
                    fontSize = if (row.kind == AO3ChapterPreview.Kind.Heading) 18.sp else 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    lineHeight = if (row.kind == AO3ChapterPreview.Kind.Heading) 25.sp else 18.sp)
            }
        }
        item { WorkFormSection("Post") }
        item { WritingPanelRow(first = true, last = false) {
            WritingPostRow(postTitle, Icons.Filled.ArrowUpward, statusSuccessColor(tokens.theme), enabled = !busy && rows != null, busy = busy) {
                if (confirmation == null) onPost() else confirming = true
            }
        } }
        item { WritingPanelRow(first = false, last = true) {
            WritingPostRow("Edit", Icons.Filled.Edit, tokens.primaryInk, enabled = !busy, onClick = onBack)
        } }
    }
}

/** WorkEditView's icon/title action, no value column or fixed height at large text. */
/**
 * iOS `AppTheme.statusSuccessColor`, a green for each theme. The one fixed green the theme file has
 * is too dark to read on a dark panel ("Post work" was barely visible in Dark and OLED).
 */
internal fun statusSuccessColor(theme: io.github.cidy02.kudos.ui.subject.ReaderTheme): Color = when (theme) {
    io.github.cidy02.kudos.ui.subject.ReaderTheme.Light -> Color(0xFF338C40)
    io.github.cidy02.kudos.ui.subject.ReaderTheme.Sepia -> Color(0xFF598033)
    else -> Color(0xFF66C773)
}

@Composable
internal fun WritingPostRow(title: String, icon: ImageVector?, color: Color, enabled: Boolean = true,
    busy: Boolean = false, onClick: () -> Unit) {
    val tokens = LocalKudosTokens.current
    Row(Modifier.fillMaxWidth().clickable(enabled = enabled, onClick = onClick).padding(horizontal = 14.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        if (icon != null) Icon(icon, contentDescription = null,
            tint = if (enabled || busy) color else tokens.tertiaryInk, modifier = Modifier.size(20.dp))
        Text(title, color = if (enabled || busy) color else tokens.tertiaryInk, fontSize = 15.sp, lineHeight = 21.sp, modifier = Modifier.weight(1f))
        if (busy) CircularProgressIndicator(color = tokens.scopePalette.accent, trackColor = tokens.separator,
            strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
    }
}

@Composable
internal fun WorkPostAlert(message: String, confirmTitle: String, onDismiss: () -> Unit, onConfirm: () -> Unit) {
    val tokens = LocalKudosTokens.current
    AlertDialog(onDismissRequest = onDismiss, containerColor = tokens.cardFill,
        titleContentColor = tokens.primaryInk, textContentColor = tokens.secondaryInk,
        title = { Text("Post this work?", lineHeight = 28.sp) }, text = { Text(message, lineHeight = 22.sp) },
        confirmButton = { TextButton(onClick = onConfirm) { Text(confirmTitle, color = tokens.scopePalette.accent, lineHeight = 20.sp) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel", color = tokens.scopePalette.accent, lineHeight = 20.sp) } })
}
