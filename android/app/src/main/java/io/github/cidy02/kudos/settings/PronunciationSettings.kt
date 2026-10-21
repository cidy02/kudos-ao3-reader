package io.github.cidy02.kudos.settings

import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.reader.speech.KokoroInlinePronunciation
import io.github.cidy02.kudos.reader.speech.KokoroPronunciationStore
import io.github.cidy02.kudos.reader.speech.PronunciationCorrections
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Both Listening and the reader use the same global list, as iOS does. */
@Composable
fun PronunciationsRow() {
    val context = LocalContext.current.applicationContext
    val store = remember(context) { KokoroPronunciationStore(context.filesDir) }
    var showing by remember { mutableStateOf(false) }
    var count by remember { mutableStateOf("None") }
    LaunchedEffect(showing) {
        count = withContext(Dispatchers.IO) {
            runCatching { store.load().global.size.let { if (it == 0) "None" else "$it" } }
                .getOrDefault("Unavailable")
        }
    }
    SubjectFormRow("Pronunciations", value = count, showsDisclosure = true, onClick = { showing = true })
    if (showing) PronunciationSettingsSheet(store, onDismiss = { showing = false })
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PronunciationSettingsSheet(store: KokoroPronunciationStore, onDismiss: () -> Unit) {
    val tokens = LocalKudosTokens.current
    val scope = rememberCoroutineScope()
    val clipboard = LocalClipboardManager.current
    var entries by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    var editing by remember { mutableStateOf<Pair<String, String>?>(null) }
    var message by remember { mutableStateOf<String?>(null) }
    suspend fun reload() {
        try {
            entries = withContext(Dispatchers.IO) { store.load().global.entries.sortedWith(compareBy<Map.Entry<String, String>> {
                it.key.lowercase(java.util.Locale.ROOT) }.thenBy { it.key }).associate { it.key to it.value } }
        } catch (error: CancellationException) { throw error
        } catch (_: Exception) { message = "Could not read corrections. Your saved file has been kept." }
    }
    LaunchedEffect(store) { reload() }
    val target = editing
    if (target != null) {
        PronunciationEditor(target.first, target.second, store, onDismiss = {
            editing = null
            scope.launch { reload() }
        })
        return
    }
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = tokens.background,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        LazyColumn(Modifier.fillMaxHeight(0.9f).padding(bottom = 24.dp)) {
            item { SubjectFormRow("Pronunciations", trailing = { TextButton(onClick = onDismiss) { Text("Done") } }) }
            item {
                SettingsSection(label = if (entries.isEmpty()) "No corrections yet" else "Corrections",
                    footnote = if (entries.isEmpty()) "Add a word here to fix how Read Aloud says it. Corrections apply to every work."
                        else "Read Aloud checks these before its own dictionary, so a correction here always wins.") {
                    entries.forEach { (word, ipa) ->
                        SubjectFormRow(word, value = ipa, valueMaxLines = 3, onClick = { editing = word to ipa })
                        SettingsActionRow("Delete $word", destructive = true, onClick = {
                            scope.launch {
                                try {
                                    withContext(Dispatchers.IO) { store.removeOverride(word) }
                                    reload()
                                } catch (error: CancellationException) { throw error
                                } catch (_: Exception) { message = "Could not delete correction. Try again." }
                            }
                        })
                        SubjectRowSeparator()
                    }
                    SettingsActionRow("Add Pronunciation", onClick = { editing = "" to "" })
                    SubjectRowSeparator()
                    SettingsActionRow("Paste Corrections", onClick = {
                        val text = clipboard.getText()?.text.orEmpty()
                        val parsed = KokoroInlinePronunciation.entries(text)
                        if (parsed.isEmpty()) {
                            message = if (text.isEmpty()) "The clipboard is empty."
                                else "No corrections found. The format is [word](/phonemes/)."
                        } else scope.launch {
                            try {
                                withContext(Dispatchers.IO) { store.apply(PronunciationCorrections(global = parsed.toMap())) }
                                reload()
                                message = if (parsed.size == 1) "Added 1 correction." else "Added ${parsed.size} corrections."
                            } catch (error: CancellationException) { throw error
                            } catch (_: Exception) { message = "Could not save corrections. Try again." }
                        }
                    })
                    SubjectRowSeparator()
                    SettingsActionRow("Copy All", enabled = entries.isNotEmpty(), onClick = {
                        clipboard.setText(AnnotatedString(KokoroInlinePronunciation.text(entries)))
                        message = if (entries.size == 1) "Copied 1 correction." else "Copied ${entries.size} corrections."
                    })
                }
            }
            item { SettingsFootnote(PRONUNCIATION_ENGINE_LIMIT) }
            message?.let { item { SettingsFootnote(it) } }
        }
    }
}

// sherpa-onnx v1.13.6's v0.19 frontend ignores lexicon; Android TextToSpeech accepts no IPA override.
internal const val PRONUNCIATION_ENGINE_LIMIT = "Corrections are saved and included in backups and sync. " +
    "The current Android Kokoro Voice Pack and device voice cannot apply them yet."

/** Same Word → Pronunciation → Cancel/Save order and global key semantics as iOS's editor. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PronunciationEditor(word: String, ipa: String, store: KokoroPronunciationStore, onDismiss: () -> Unit) {
    val tokens = LocalKudosTokens.current
    val scope = rememberCoroutineScope()
    var editedWord by remember(word) { mutableStateOf(word) }
    var pronunciation by remember(word, ipa) { mutableStateOf(ipa) }
    var error by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }
    ModalBottomSheet(onDismissRequest = { if (!saving) onDismiss() }, containerColor = tokens.background,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.fillMaxWidth().imePadding().verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            SubjectFormRow(if (word.isEmpty()) "Add Pronunciation" else word)
            SettingsSection(label = "Word", footnote = null) {
                SubjectTextFieldRow("Word", editedWord, "Word", { editedWord = it }, autocorrect = false)
            }
            SettingsSection(label = "Pronunciation", footnote = "Enter phonemes such as hɜɹmˈIəni. " +
                "This Android voice engine cannot convert syllables such as her-MY-oh-nee to phonemes.") {
                SubjectTextFieldRow("Pronunciation", pronunciation, "her-MY-oh-nee", { pronunciation = it },
                    autocorrect = false, stackedLabel = true)
            }
            SettingsFootnote(PRONUNCIATION_ENGINE_LIMIT)
            error?.let { SettingsFootnote(it) }
            Row(Modifier.fillMaxWidth().padding(horizontal = 13.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                TextButton(onClick = onDismiss, enabled = !saving) { Text("Cancel") }
                TextButton(enabled = !saving && editedWord.isNotBlank() && pronunciation.isNotBlank(), onClick = {
                    saving = true
                    scope.launch {
                        try {
                            withContext(Dispatchers.IO) {
                                store.setOverride(editedWord.trim(), pronunciation.trim(), word.takeIf { it.isNotEmpty() })
                            }
                            onDismiss()
                        } catch (cancelled: CancellationException) { throw cancelled
                        } catch (_: Exception) { error = "Could not save correction. Try again."
                        } finally { saving = false }
                    }
                }) { Text("Save") }
            }
        }
    }
}
