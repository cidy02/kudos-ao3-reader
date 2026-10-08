package io.github.cidy02.kudos.writing

import android.content.ComponentCallbacks2
import android.content.res.Configuration
import android.os.SystemClock
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Redo
import androidx.compose.material.icons.automirrored.outlined.Undo
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.network.ao3.writing.recovery.WritingTextRecovery
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.ToolbarCircleButton
import io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import java.text.DateFormat
import java.text.NumberFormat
import java.util.Date

/** One string. Deliberately has no client, auth service, work form or chapter actions. */
@Composable
fun WritingTextEditorScreen(
    text: String,
    title: String,
    account: String,
    target: String,
    field: String,
    onDone: (String) -> Unit,
    onBack: () -> Unit,
    ruleTitle: String? = null,
    onCheckpoint: (String) -> Unit = {},
) {
    val context = LocalContext.current
    val updatedCheckpoint by rememberUpdatedState(onCheckpoint)
    val session = remember(account, target, field) {
        WritingEditorSession(WritingNativeTextField(context, text), text,
            WritingTextRecovery.inFilesDir(context.filesDir.toPath()), account, target, field,
            CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate), SystemClock::uptimeMillis,
            onCheckpoint = { updatedCheckpoint(it) })
    }
    WritingTextEditorContent(session, title, ruleTitle, onDone, onBack)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun WritingTextEditorContent(
    session: WritingEditorSession,
    title: String,
    ruleTitle: String?,
    onDone: (String) -> Unit,
    onBack: () -> Unit,
) {
    val tokens = LocalKudosTokens.current
    val palette = tokens.scopePalette
    val density = LocalDensity.current
    val context = LocalContext.current.applicationContext
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var more by remember { mutableStateOf(false) }
    var showLink by remember { mutableStateOf(false) }
    var link by remember { mutableStateOf("https://") }
    val leave = { session.editor.commitComposition(); session.scheduler.fireNow(); onBack() }
    BackHandler(enabled = session.recoveries.isEmpty() && !showLink && session.error == null, onBack = leave)
    ProvidePushedShellChrome(hasSubjectHeader = true, hideTabBar = true, onBack = {
        if (session.recoveries.isEmpty()) leave()
    }, trailingContent = {
        EditorToolbarButton(if (session.isPreviewing) "Edit" else "Preview",
            if (session.isPreviewing) Icons.Outlined.Code else Icons.Outlined.Visibility,
            action = session::togglePreview)
        EditorToolbarButton("Undo", Icons.AutoMirrored.Outlined.Undo, !session.isPreviewing, session.editor::undo)
        EditorToolbarButton("Redo", Icons.AutoMirrored.Outlined.Redo, !session.isPreviewing, session.editor::redo)
        Box {
            EditorToolbarButton("More", Icons.Outlined.MoreHoriz) { more = true }
            DropdownMenu(expanded = more, onDismissRequest = { more = false }, containerColor = tokens.cardFill) {
                DropdownMenuItem(text = { Text("Paste as plain text", color = tokens.primaryInk, lineHeight = 22.sp) },
                    onClick = { more = false; session.editor.pastePlainText() })
            }
        }
        EditorToolbarButton("Done", Icons.Outlined.Check) { onDone(session.done()) }
    })

    SideEffect { session.editor.setAppearance(tokens.primaryInk.toArgb(), with(density) { 15.5.sp.toPx() }) }
    DisposableEffect(session, lifecycle, context) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_PAUSE || event == Lifecycle.Event.ON_STOP) session.scheduler.fireNow()
        }
        val memory = object : ComponentCallbacks2 {
            override fun onConfigurationChanged(newConfig: Configuration) = Unit
            override fun onLowMemory() { session.scheduler.fireNow() }
            override fun onTrimMemory(level: Int) {
                if (level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW) session.scheduler.fireNow()
            }
        }
        lifecycle.addObserver(observer)
        context.registerComponentCallbacks(memory)
        onDispose {
            lifecycle.removeObserver(observer)
            context.unregisterComponentCallbacks(memory)
            session.finish()
        }
    }

    Column(Modifier.fillMaxSize().subjectScreenWash(palette).imePadding().navigationBarsPadding()) {
        Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
        Spacer(Modifier.height(76.dp))
        Text(title, color = tokens.primaryInk, fontSize = 22.sp, lineHeight = 29.sp,
            fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(horizontal = 16.dp))
        val words = session.wordCount?.let { "${NumberFormat.getIntegerInstance().format(it)} ${if (it == 1) "word" else "words"}" }
        // At accessibility size the figure gets its own line; don't clip the shared header's one-line count.
        val accessibility = isAccessibilityFontScale()
        SectionRuleHeader(ruleTitle ?: title, countText = if (accessibility) null else words,
            modifier = Modifier.padding(top = 8.dp))
        if (accessibility && words != null) Text(words, color = tokens.tertiaryInk, fontSize = 11.sp,
            lineHeight = 16.sp, fontFamily = FontFamily.Monospace, modifier = Modifier.padding(horizontal = 16.dp))
        Box(Modifier.weight(1f).fillMaxWidth()) {
            AndroidView(factory = { session.editor.view }, modifier = Modifier.fillMaxSize(),
                update = { session.editor.showEditing(!session.isPreviewing) })
            if (session.isPreviewing) EditorPreview(session.previewState)
        }
        Text("Recovery copy on this device · Save from the work form", color = tokens.secondaryInk,
            fontSize = 11.5.sp, lineHeight = 17.sp,
            modifier = Modifier.align(Alignment.End).padding(horizontal = 16.dp, vertical = 4.dp))
        Box(Modifier.fillMaxWidth().height(0.5.dp).background(tokens.glassStroke(0.12)))
        Column(Modifier.fillMaxWidth().background(tokens.glassFill(0.09)).padding(horizontal = 14.dp, vertical = 11.dp),
            verticalArrangement = Arrangement.spacedBy(9.dp)) {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                WritingMarkup.tags.forEach { tag ->
                    val shape = RoundedCornerShape(9.dp)
                    Column(Modifier.heightIn(min = 48.dp).background(tokens.glassFill(0.09), shape).border(0.5.dp, tokens.glassStroke(0.13), shape)
                        .clickable(enabled = !session.isPreviewing) {
                            if (tag.element == "a") showLink = true else session.editor.insert(tag.element)
                        }.semantics { contentDescription = tag.name }
                        .padding(horizontal = 11.dp, vertical = 7.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("<${tag.tagLabel}>", fontSize = 13.sp, lineHeight = 18.sp, fontFamily = FontFamily.Monospace,
                            fontWeight = FontWeight.SemiBold, color = tokens.primaryInk)
                        Text(tag.name.lowercase(), fontSize = 8.5.sp, lineHeight = 12.sp, color = tokens.secondaryInk)
                    }
                }
            }
            Text("AO3 supports only certain formatting. The toolbar adds formatting that AO3 can keep when you post.",
                fontSize = 10.5.sp, lineHeight = 15.sp, color = tokens.secondaryInk)
        }
    }

    session.error?.let { message ->
        AlertDialog(onDismissRequest = { session.error = null }, containerColor = tokens.cardFill,
            titleContentColor = tokens.primaryInk, textContentColor = tokens.secondaryInk,
            title = { Text("Editor error", lineHeight = 28.sp) }, text = { Text(message, lineHeight = 22.sp) },
            confirmButton = { TextButton(onClick = { session.error = null }) {
                Text("OK", color = palette.accent, lineHeight = 20.sp)
            } })
    }
    if (showLink) AlertDialog(onDismissRequest = { showLink = false }, containerColor = tokens.cardFill,
        titleContentColor = tokens.primaryInk,
        title = { Text("Insert link", lineHeight = 28.sp) },
        text = {
            BasicTextField(link, onValueChange = { link = it }, singleLine = true,
                cursorBrush = SolidColor(tokens.primaryInk),
                textStyle = TextStyle(color = tokens.primaryInk, fontSize = 16.sp, lineHeight = 22.sp),
                modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Link URL" },
                decorationBox = { input ->
                    Box { if (link.isEmpty()) Text("https://example.com", color = tokens.secondaryInk, lineHeight = 22.sp); input() }
                })
        },
        confirmButton = { TextButton(onClick = {
            showLink = false
            if (WritingMarkup.safeLink(link)) session.editor.insert("a", link)
            else session.error = "Enter an HTTP, HTTPS, or mailto link."
        }) { Text("Insert", color = palette.accent, lineHeight = 20.sp) } },
        dismissButton = { TextButton(onClick = { showLink = false }) { Text("Cancel", color = palette.accent, lineHeight = 20.sp) } })

    if (session.recoveries.isNotEmpty()) {
        val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true,
            confirmValueChange = { it != SheetValue.Hidden })
        ModalBottomSheet(onDismissRequest = {}, sheetState = sheet, containerColor = tokens.cardFill,
            contentColor = tokens.primaryInk, scrimColor = tokens.primaryInk.copy(alpha = 0.32f), dragHandle = null) {
            Column(Modifier.fillMaxWidth().fillMaxHeight(0.85f).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Text("Recover unfinished text?", fontSize = 18.sp, lineHeight = 25.sp, fontWeight = FontWeight.SemiBold)
                val copy = session.selectedRecovery
                if (copy != null) {
                    if (session.recoveries.size > 1) Column {
                        Text("Local copy", color = tokens.secondaryInk, fontSize = 12.sp, lineHeight = 18.sp)
                        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            session.recoveries.forEach { item ->
                                TextButton(onClick = { session.selectRecovery(item) }) {
                                    Text(recoveryDate(item.entry.savedAt), color = palette.accent, lineHeight = 20.sp,
                                        fontWeight = if (item == copy) FontWeight.Bold else FontWeight.Normal)
                                }
                            }
                        }
                    }
                    Text("A recovery copy was saved on this device ${recoveryDate(copy.entry.savedAt)}.", lineHeight = 22.sp)
                    if (session.recoveryFormChanged) Text(
                        "The text on the form has changed since this copy began. Review the copy before restoring it.",
                        color = tokens.secondaryInk, lineHeight = 22.sp)
                    // A line at a time: one Text holding a whole chapter froze the sheet for seconds.
                    val lines = remember(copy) { copy.entry.text.lines() }
                    SelectionContainer {
                        LazyColumn(Modifier.heightIn(max = 240.dp)) {
                            items(lines) { Text(it, fontFamily = FontFamily.Monospace, fontSize = 14.sp, lineHeight = 20.sp) }
                        }
                    }
                    // Always visible beneath the independently scrolling copy.
                    Column {
                        EditorSheetAction("Restore local copy", session::restore)
                        EditorSheetAction("Keep form text", session::keepFormText)
                        EditorSheetAction("Delete this local copy", { session.deleteSelectedCopy() }, destructive = true)
                    }
                }
            }
        }
    }
}

@Composable
private fun EditorToolbarButton(name: String, icon: ImageVector, enabled: Boolean = true, action: () -> Unit) {
    ToolbarCircleButton(onClick = { if (enabled) action() }, accessibilityName = name,
        modifier = Modifier.alpha(if (enabled) 1f else 0.4f).semantics { if (!enabled) disabled() },
        palette = LocalKudosTokens.current.scopePalette) { Icon(icon, contentDescription = null) }
}

@Composable
private fun EditorSheetAction(text: String, action: () -> Unit, destructive: Boolean = false) {
    val tokens = LocalKudosTokens.current
    TextButton(onClick = action) {
        Text(text, lineHeight = 22.sp, color = if (destructive) SubjectPalette.fromHue(0.0, tokens.theme).accent else tokens.scopePalette.accent)
    }
}

internal fun recoveryDate(seconds: Double): String = DateFormat.getDateTimeInstance().format(
    Date(((seconds + 978_307_200) * 1_000).toLong()))

@Composable
internal fun EditorPreview(state: WritingBufferPreview.State?) {
    val tokens = LocalKudosTokens.current
    when (state) {
        null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(color = tokens.scopePalette.accent)
        }
        WritingBufferPreview.State.Failed -> Column(Modifier.fillMaxSize().padding(16.dp),
            verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(Icons.Outlined.WarningAmber, contentDescription = null, tint = tokens.secondaryInk, modifier = Modifier.size(48.dp))
            Text("Couldn't render this HTML", fontSize = 20.sp, lineHeight = 27.sp, color = tokens.primaryInk)
            Text("Your text is unchanged. Tap Edit to go back to it.", lineHeight = 22.sp, color = tokens.secondaryInk)
        }
        // Lazy: a full-length chapter is over a thousand paragraphs.
        is WritingBufferPreview.State.Rendered -> LazyColumn(
            Modifier.fillMaxSize().semantics { contentDescription = "Preview" },
            contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
            items(state.blocks) { block ->
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (block.listItem) Text("•", fontSize = 15.5.sp, lineHeight = 25.sp, color = tokens.primaryInk)
                    // AO3RichTextView's own default .body overrides the editor's outer font modifier.
                    Text(buildAnnotatedString {
                        block.runs.forEach { run ->
                            withStyle(SpanStyle(fontWeight = if (run.isBold) FontWeight.Bold else FontWeight.Normal,
                                fontStyle = if (run.isItalic) FontStyle.Italic else FontStyle.Normal,
                                color = if (run.link != null) tokens.scopePalette.accent else tokens.primaryInk,
                                textDecoration = if (run.link != null) TextDecoration.Underline else null)) { append(run.text) }
                        }
                    }, fontFamily = FontFamily.Default, fontSize = 17.sp, lineHeight = 24.sp)
                }
            }
        }
    }
}
