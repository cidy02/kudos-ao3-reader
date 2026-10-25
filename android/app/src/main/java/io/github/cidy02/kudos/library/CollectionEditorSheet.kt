package io.github.cidy02.kudos.library

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.LocalSettingsFormGround
import io.github.cidy02.kudos.settings.settingsPanelGround
import io.github.cidy02.kudos.ui.subject.ReaderTheme
import io.github.cidy02.kudos.ui.subject.SubjectFieldLabel
import io.github.cidy02.kudos.ui.subject.SubjectHueSwatchRow
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.SubjectPaletteTheme
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.SubjectToggle
import io.github.cidy02.kudos.ui.subject.parseStoredColor
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import io.github.cidy02.kudos.ui.components.coverHue
import io.github.cidy02.kudos.works.DownloadQueue
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.works.WorkTags
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.withLock

/**
 * Artboard **1bk** — New Collection and Edit Collection / Details are one sheet,
 * like the queue sheet (T-335). The wash follows the colour the reader is picking (T-350).
 */
@Composable
fun CollectionEditorSheet(
    workRepository: WorkRepository,
    existing: WorkCollection?,
    onDismiss: () -> Unit,
    onSaved: (WorkCollection) -> Unit,
    downloadQueue: DownloadQueue? = null
) {
    val tokens = LocalKudosTokens.current
    val scope = rememberCoroutineScope()
    val editing = existing != null

    var name by remember(existing?.id) { mutableStateOf(existing?.name.orEmpty()) }
    var description by remember(existing?.id) { mutableStateOf(existing?.description.orEmpty()) }
    var hue by remember(existing?.id) { mutableStateOf(existing?.hue) }
    var colorHex by remember(existing?.id) { mutableStateOf(existing?.colorHex) }
    var keepsWorksOffline by remember(existing?.id) { mutableStateOf(existing?.keepsWorksOffline ?: false) }
    var showsOnHome by remember(existing?.id) { mutableStateOf(existing?.showsOnHome ?: false) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    val palette = collectionDraftPalette(tokens.theme, tokens.scopePalette, hue, colorHex)
    val canSave = name.isNotBlank() && !saving

    val editMutex = remember { kotlinx.coroutines.sync.Mutex() }
    var revision by remember { androidx.compose.runtime.mutableIntStateOf(0) }
    fun save(close: Boolean) {
        if (name.isBlank() && !editing) return
        val name = name.ifBlank { existing?.name.orEmpty() }
        val description = description
        val hue = hue
        val colorHex = colorHex
        val keepsWorksOffline = keepsWorksOffline
        val showsOnHome = showsOnHome
        val editRevision = ++revision
        saving = true
        // Admit every field change before the sheet can leave; queued writes keep their order.
        scope.launch(start = kotlinx.coroutines.CoroutineStart.UNDISPATCHED) {
            kotlinx.coroutines.withContext(kotlinx.coroutines.NonCancellable) {
                editMutex.withLock {
                    val saved = runCatching {
                        if (editing) {
                            val wasKeptOffline = workRepository.getCollection(existing!!.id)?.keepsWorksOffline == true
                            val updated = workRepository.updateCollection(
                                collectionId = existing.id,
                                name = name,
                                description = description,
                                hue = hue,
                                colorHex = colorHex,
                                clearColor = hue == null && colorHex == null,
                                keepsWorksOffline = keepsWorksOffline,
                                showsOnHome = showsOnHome
                            )
                            if (updated != null) {
                                if (!wasKeptOffline && keepsWorksOffline && downloadQueue != null) {
                                    val works = workRepository.worksForCollection(existing.id)
                                    for (work in works) {
                                        if (!work.hasEpub) {
                                            val ao3Id = WorkTags.ao3WorkIdFromUrl(work.sourceUrl)
                                            if (ao3Id != null) {
                                                downloadQueue.enqueueLocal(
                                                    ao3WorkId = ao3Id,
                                                    title = work.title,
                                                    sourceUrl = work.sourceUrl,
                                                    force = false
                                                )
                                            }
                                        }
                                    }
                                }
                                updated
                            } else {
                                error("Could not update collection.")
                            }
                        } else {
                            workRepository.createCollection(
                                name = name,
                                hue = hue,
                                colorHex = colorHex,
                                description = description,
                                keepsWorksOffline = keepsWorksOffline,
                                showsOnHome = showsOnHome
                            )
                        }
                    }
                    if (editRevision == revision) {
                        saving = false
                        error = saved.exceptionOrNull()?.message
                    }
                    if (close) saved.getOrNull()?.let(onSaved)
                }
            }
        }
    }

    SubjectPaletteTheme(palette) {
    Dialog(
        onDismissRequest = { if (editing) save(close = true) else if (!saving) onDismiss() },
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .then(if (editing) Modifier.background(tokens.formSheetGround) else Modifier.subjectScreenWash(palette))
                .windowInsetsPadding(WindowInsets.safeDrawing)
                .windowInsetsPadding(WindowInsets.ime)
        ) {
            CollectionEditorHeader(if (editing) name else "New collection", editing, saving, canSave,
                onDismiss = onDismiss, onSave = { save(close = true) })

            CollectionEditorContent(
                editing = editing,
                name = name,
                onNameChange = { name = it },
                description = description,
                onDescriptionChange = { description = it; if (editing) save(close = false) },
                hue = hue,
                colorHex = colorHex,
                onColorChange = { nextHue, nextHex ->
                    hue = nextHue
                    colorHex = nextHex
                    if (editing) save(close = false)
                },
                keepsWorksOffline = keepsWorksOffline,
                onKeepsWorksOfflineChange = { keepsWorksOffline = it; if (editing) save(close = false) },
                showsOnHome = showsOnHome,
                onShowsOnHomeChange = { showsOnHome = it; if (editing) save(close = false) },
                palette = palette
            )
        }
    }

    if (error != null) {
        AlertDialog(
            onDismissRequest = { error = null },
            title = { Text("Could not save") },
            text = { Text(error.orEmpty()) },
            confirmButton = { TextButton(onClick = { error = null }) { Text("OK") } }
        )
    }
    }
}

@Composable
internal fun CollectionEditorContent(
    editing: Boolean,
    name: String,
    onNameChange: (String) -> Unit,
    description: String,
    onDescriptionChange: (String) -> Unit,
    hue: Double?,
    colorHex: String?,
    onColorChange: (Double?, String?) -> Unit,
    keepsWorksOffline: Boolean,
    onKeepsWorksOfflineChange: (Boolean) -> Unit,
    showsOnHome: Boolean,
    onShowsOnHomeChange: (Boolean) -> Unit,
    palette: SubjectPalette = LocalKudosTokens.current.scopePalette
) {
    val tokens = LocalKudosTokens.current
    CompositionLocalProvider(LocalSettingsFormGround provides (editing && tokens.theme != ReaderTheme.Light)) {
        Column(
            Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            if (!editing) {
                SubjectFieldLabel("Collection", Modifier.padding(top = 12.dp))
                Column(
                    Modifier
                        .fillMaxWidth()
                        .settingsPanelGround()
                        .testTag("Collection panel")
                ) {
                    Column(
                        Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        SubjectFieldLabel("Name")
                        OutlinedTextField(
                            value = name,
                            onValueChange = onNameChange,
                            modifier = Modifier.fillMaxWidth(),
                            placeholder = { Text("Comfort reads") },
                            singleLine = true
                        )
                    }
                    SubjectRowSeparator(modifier = Modifier.testTag("Collection panel separator"))
                    Column(
                        Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        SubjectFieldLabel("Description")
                        OutlinedTextField(
                            value = description,
                            onValueChange = onDescriptionChange,
                            modifier = Modifier.fillMaxWidth(),
                            placeholder = { Text("Optional") },
                            minLines = 2
                        )
                    }
                    SubjectRowSeparator(modifier = Modifier.testTag("Collection panel separator"))
                    SubjectHueSwatchRow(
                        hue = hue,
                        colorHex = colorHex,
                        onChange = onColorChange,
                        modifier = Modifier.padding(horizontal = 14.dp, vertical = 11.dp)
                    )
                }
            } else {
                SubjectFieldLabel("Colour", Modifier.padding(top = 10.dp))
                Column(
                    Modifier
                        .fillMaxWidth()
                        .settingsPanelGround()
                        .testTag("Collection colour panel")
                ) {
                    SubjectHueSwatchRow(
                        hue = hue,
                        colorHex = colorHex,
                        onChange = onColorChange,
                        modifier = Modifier.padding(horizontal = 14.dp, vertical = 11.dp)
                    )
                }
            }
            FormFootnote(
                if (hue == null && colorHex == null) {
                    "Kudos picks a colour from the collection name. Renaming it may change this colour."
                } else {
                    "Your chosen colour stays the same if you rename the collection."
                }
            )

            if (editing) {
                SubjectFieldLabel("Description", Modifier.padding(top = 10.dp))
                OutlinedTextField(
                    value = description,
                    onValueChange = onDescriptionChange,
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("Optional") },
                    minLines = 2
                )
            }

            SubjectFieldLabel("Behaviour", Modifier.padding(top = 16.dp))
            Column(
                Modifier
                    .fillMaxWidth()
                    .settingsPanelGround()
                    .testTag("Collection behaviour panel")
            ) {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "Keep downloads",
                        modifier = Modifier.weight(1f),
                        color = tokens.primaryInk,
                        fontSize = 15.sp
                    )
                    SubjectToggle(
                        checked = keepsWorksOffline,
                        onCheckedChange = onKeepsWorksOfflineChange,
                        accent = palette.tint,
                        contentDescription = "Keep downloads"
                    )
                }
                SubjectRowSeparator()
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "Show on Home",
                        modifier = Modifier.weight(1f),
                        color = tokens.primaryInk,
                        fontSize = 15.sp
                    )
                    SubjectToggle(
                        checked = showsOnHome,
                        onCheckedChange = onShowsOnHomeChange,
                        accent = palette.tint,
                        contentDescription = "Show on Home"
                    )
                }
            }
            FormFootnote(
                "Keep downloads keeps a downloaded copy of every work in this collection. " +
                    "Show on Home adds the collection above Recently Updated."
            )

            if (!editing) FormFootnote(
                "This collection stays on this device. AO3 doesn't see it, and it isn't shared with your other devices."
            )
        }
    }
}

fun collectionDraftPalette(
    name: String,
    hue: Double?,
    colorHex: String?,
    theme: ReaderTheme
): SubjectPalette {
    val picked = colorHex?.let(::parseStoredColor)
    if (picked != null) return SubjectPalette.fromColor(picked, theme)
    val effectiveHue = hue ?: ((coverHue(name).toDouble() / 360.0).coerceIn(0.0, 1.0))
    return SubjectPalette.fromHue(effectiveHue, theme)
}

fun collectionDraftPalette(
    theme: ReaderTheme,
    fallback: SubjectPalette,
    hue: Double?,
    colorHex: String?
): SubjectPalette {
    val picked = colorHex?.let(::parseStoredColor)
    if (picked != null) return SubjectPalette.fromColor(picked, theme)
    if (hue != null) return SubjectPalette.fromHue(hue, theme)
    return fallback
}

@Composable
internal fun CollectionEditorHeader(
    title: String, editing: Boolean, saving: Boolean, canSave: Boolean,
    onDismiss: () -> Unit, onSave: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically) {
        if (!editing) TextButton(onClick = onDismiss, enabled = !saving) { Text("Cancel") }
        Text(title, Modifier.weight(1f), color = tokens.primaryInk, fontSize = 17.sp,
            fontWeight = FontWeight.SemiBold)
        TextButton(onClick = onSave, enabled = canSave) {
            Text(if (editing) "Done" else "Create",
                color = if (canSave) tokens.theme.accentInk(tokens.scopePalette.tint) else tokens.tertiaryInk)
        }
    }
}
