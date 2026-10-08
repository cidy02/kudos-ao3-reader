package io.github.cidy02.kudos.writing

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.BuildConfig
import io.github.cidy02.kudos.network.ao3.writing.recovery.WritingTextRecovery
import io.github.cidy02.kudos.network.ao3.writing.recovery.writingRecoveryIO
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.nio.file.Files
import java.util.UUID

/** Debug routes only, no demo authentication or AO3 dependency. */
@Composable
fun WritingEditorDemoScreen(fromFile: Boolean, onClose: () -> Unit) {
    if (!BuildConfig.DEBUG) return
    val context = LocalContext.current
    val tokens = LocalKudosTokens.current
    var initialText by remember(fromFile) { mutableStateOf<String?>(null) }
    var error by remember(fromFile) { mutableStateOf<String?>(null) }
    val target = if (fromFile) "work:editor-fixture" else "work:editor-demo"
    LaunchedEffect(fromFile) {
        try {
            initialText = withContext(Dispatchers.IO) {
                if (fromFile) {
                    val directory = requireNotNull(context.getExternalFilesDir(null)) { "External app files are unavailable." }
                    File(directory, "writing-editor-fixture.html").readText(Charsets.UTF_8)
                } else {
                    val text = "<p>The lantern keeper opened the blue gate.</p>\n\nA small boat waited beneath the bridge."
                    val store = WritingTextRecovery.inFilesDir(context.filesDir.toPath())
                    val key = store.fileURL("EditorDemo", target, "content")
                    val seed = store.sessionURL(key, UUID.fromString("00000000-0000-0000-0000-0000000003bd"))
                    withContext(writingRecoveryIO) {
                        if (!Files.exists(seed)) store.save(
                            "<p>The lantern keeper opened the blue gate.</p>\n\nA small boat waited beneath the bridge.\n<em>Its sail glowed amber.</em>",
                            text, seed)
                    }
                    text
                }
            }
        } catch (failure: Exception) {
            if (failure is CancellationException) throw failure
            error = failure.localizedMessage ?: "Couldn't open the editor fixture."
        }
    }
    val text = initialText
    if (text != null) WritingTextEditorScreen(text, "Chapter text", "EditorDemo", target, "content",
        onDone = { onClose() }, onBack = onClose, ruleTitle = "Chapter 13")
    else Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
        val failure = error
        if (failure != null) Text(failure, color = tokens.primaryInk, fontSize = 16.sp, lineHeight = 22.sp)
        else CircularProgressIndicator(color = tokens.scopePalette.accent)
    }
}
