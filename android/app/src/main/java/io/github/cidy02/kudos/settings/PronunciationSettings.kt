package io.github.cidy02.kudos.settings

import io.github.cidy02.kudos.app.DebugShotEffect
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.ui.Alignment
import androidx.compose.ui.text.style.TextAlign
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
    DebugShotEffect("pronunciations") { showing = true }

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
internal fun PronunciationSettingsSheet(store: KokoroPronunciationStore, onDismiss: () -> Unit) {
    val tokens = LocalKudosTokens.current
    val scope = rememberCoroutineScope()
    val clipboard = LocalClipboardManager.current
    var entries by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    var editing by remember { mutableStateOf<Pair<String, String>?>(null) }
    DebugShotEffect("pronunciation-list") { editing = "" to "" }

    var menuOpen by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var pastedResult by remember { mutableStateOf<String?>(null) }
    suspend fun reload() {
        try {
            entries = withContext(Dispatchers.IO) {
                val order = android.icu.text.Collator.getInstance() as android.icu.text.RuleBasedCollator
                order.numericCollation = true
                store.load().global.entries.sortedWith { a, b -> order.compare(a.key, b.key) }.associate { it.key to it.value }
            }
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
    pastedResult?.let { result ->
        androidx.compose.material3.AlertDialog(onDismissRequest = { pastedResult = null },
            title = { Text("Pasted Corrections") }, text = { Text(result) },
            confirmButton = { TextButton(onClick = { pastedResult = null }) { Text("OK") } })
    }
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = tokens.background,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.fillMaxHeight(0.9f).padding(bottom = 24.dp)) {
            SubjectFormRow("Pronunciations", trailing = {
                Box {
                    IconButton(onClick = { menuOpen = true }) { Icon(Icons.Default.MoreVert, contentDescription = "More") }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        DropdownMenuItem(text = { Text("Add Pronunciation") }, onClick = { menuOpen = false; editing = "" to "" })
                        DropdownMenuItem(text = { Text("Paste Corrections") }, onClick = {
                            menuOpen = false
                            val text = clipboard.getText()?.text.orEmpty()
                            val parsed = KokoroInlinePronunciation.entries(text)
                            if (parsed.isEmpty()) {
                                pastedResult = if (text.isEmpty()) "The clipboard is empty."
                                    else "No corrections found. The format is [word](/phonemes/)."
                            } else scope.launch {
                                try {
                                    withContext(Dispatchers.IO) { store.apply(PronunciationCorrections(global = parsed.toMap())) }
                                    reload()
                                    pastedResult = if (parsed.size == 1) "Added 1 correction." else "Added ${parsed.size} corrections."
                                } catch (error: CancellationException) { throw error
                                } catch (_: Exception) { message = "Could not save corrections. Try again." }
                            }
                        })
                        DropdownMenuItem(text = { Text("Copy All") }, enabled = entries.isNotEmpty(), onClick = {
                            menuOpen = false
                            clipboard.setText(AnnotatedString(KokoroInlinePronunciation.text(entries)))
                            pastedResult = if (entries.size == 1) "Copied 1 correction." else "Copied ${entries.size} corrections."
                        })
                    }
                }
                TextButton(onClick = onDismiss) { Text("Done") }
            })
            LazyColumn(Modifier.weight(1f)) {
                if (entries.isEmpty()) item {
                    Column(Modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 40.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text("No corrections yet", color = tokens.primaryInk, textAlign = TextAlign.Center)
                        Text("Add a word here to fix how Read Aloud says it. Corrections apply to every work.",
                            color = tokens.secondaryInk, textAlign = TextAlign.Center)
                    }
                } else item {
                    SettingsSection(label = "Corrections",
                        footnote = "Read Aloud checks these before its own dictionary, so a correction here always wins.") {
                        entries.toList().forEachIndexed { index, (word, ipa) ->
                            if (index > 0) SubjectRowSeparator()
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
                        }
                    }
                }
                item { SettingsFootnote(PRONUNCIATION_ENGINE_LIMIT) }
                message?.let { item { SettingsFootnote(it) } }
            }
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
            SubjectFormRow(if (editedWord.isEmpty()) "Add Pronunciation" else editedWord)
            SettingsSection(label = "Word", footnote = null) {
                SubjectTextFieldRow("Word", editedWord, "Word", { editedWord = it }, autocorrect = false, fieldOnly = true)
            }
            SettingsSection(label = "Pronunciation", footnote = "Enter phonemes such as hɜɹmˈIəni. " +
                "This Android voice engine cannot convert syllables such as her-MY-oh-nee to phonemes.") {
                SubjectTextFieldRow("Pronunciation", pronunciation, "her-MY-oh-nee", { pronunciation = it },
                    autocorrect = false, fieldOnly = true)
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
