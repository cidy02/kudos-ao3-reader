package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.app.DebugShotEffect
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.sync.Mutex
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.Icons
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.TextStyle
import androidx.compose.foundation.text.BasicTextField
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectChip
import io.github.cidy02.kudos.ui.subject.SubjectChipStyle
import io.github.cidy02.kudos.ui.subject.SubjectFieldLabel
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectHueSwatches
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.SubjectToggle
import io.github.cidy02.kudos.ui.subject.subjectPanel
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant

@OptIn(ExperimentalLayoutApi::class)
@Suppress("UNUSED_PARAMETER")
@Composable
fun QueueSettingsScreen(
    queueId: String,
    repository: ReadingQueueRepository,
    settingsRepository: SettingsRepository? = null,
    epubBytes: (String) -> Long = { 0L },
    onOpenWork: (String) -> Unit = {},
    onShowOnlyTag: (String) -> Unit = {}
) {
    val tokens = LocalKudosTokens.current
    val scope = rememberCoroutineScope()
    var queue by remember(queueId) { mutableStateOf<ReadingQueue?>(null) }
    var works by remember(queueId) { mutableStateOf<List<SavedWork>>(emptyList()) }
    var tags by remember(queueId) { mutableStateOf<List<String>>(emptyList()) }
    var preserved by remember(queueId) { mutableIntStateOf(0) }
    var storedBytes by remember(queueId) { mutableStateOf(0L) }
    var vocabulary by remember(queueId) { mutableIntStateOf(0) }
    var notes by remember(queueId) { mutableStateOf("") }
    var notesFocused by remember { mutableStateOf(false) }
    val notesWrites = remember { Mutex() }
    var reload by remember(queueId) { mutableIntStateOf(0) }
    var colourMenu by remember { mutableStateOf(false) }
    var showTags by remember { mutableStateOf(false) }
    var managing by remember { mutableStateOf(false) }
    DebugShotEffect("queue-settings", ready = queue != null && tags.isNotEmpty()) { name ->
        if (name == "queuetag") showTags = true else managing = true
    }

    LaunchedEffect(queueId, reload) {
        val loaded = runCatching { repository.getQueue(queueId) }.getOrNull()
        queue = loaded
        val items = if (loaded == null) emptyList() else repository.listWorks(queueId).mapNotNull { it.work }
        works = items
        tags = if (loaded == null) emptyList() else repository.tagsForQueue(queueId).map { it.name }
        vocabulary = runCatching { repository.allTags().size }.getOrDefault(0)
        val sizes = withContext(Dispatchers.IO) {
            items.associate { work -> work.id to runCatching { epubBytes(work.id) }.getOrDefault(0L) }
        }
        val kept = items.filter { it.hasEpub && (sizes[it.id] ?: 0L) > 0 }
        preserved = kept.size
        storedBytes = kept.sumOf { sizes[it.id] ?: 0L }
        if (!notesFocused && loaded != null) notes = loaded.notes.orEmpty()
    }

    val current = queue ?: return
    val palette = queuePalette(tokens.theme, current)

    BackHandler(enabled = managing) {
        managing = false
        reload += 1
    }

    ProvidePushedShellChrome(
        hasSubjectHeader = true,
        onBack = if (managing) {
            {
                managing = false
                reload += 1
            }
        } else null,
        trailingContent = if (managing) {
            {
                TextButton(onClick = { managing = false; reload += 1 }) {
                    Text("Done", color = palette.accent)
                }
            }
        } else null
    )

    if (managing) {
        QueueTagManager(
            repository = repository,
            queue = current,
            palette = palette,
            workCount = works.size,
            onBack = { managing = false; reload += 1 },
            onShowOnlyTag = onShowOnlyTag
        )
        return
    }

    Column(
        Modifier
            .fillMaxSize()
            .subjectScreenWash(palette, washHeight = 620.dp)
            .verticalScroll(rememberScrollState())
            .padding(bottom = 28.dp)
    ) {
        Spacer(Modifier.height(WindowInsets.systemBars.asPaddingValues().calculateTopPadding() + 56.dp))
        SubjectHeaderBlock(
            kicker = ReadingQueueFacts.kicker("Home", isDetails = true),
            kickerMaxLines = if (io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale()) Int.MAX_VALUE else 1,
            title = current.displayName,
            subtitle = ReadingQueueFacts.subtitle(works.size, preserved, storedBytes),
            palette = palette,
            modifier = Modifier.padding(top = 12.dp)
        )
        if (works.isNotEmpty()) {
            Column(
                Modifier.padding(horizontal = 26.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(7.dp)
            ) {
                QueueProgressStrip(ReadingQueueFacts.progress(works), palette)
                Text(
                    text = ReadingQueueFacts.legend(ReadingQueueFacts.progress(works), preserved),
                    color = tokens.secondaryInk,
                    fontSize = 11.5.sp
                )
            }
        }
        SubjectFieldLabel("Description", Modifier.padding(start = 16.dp, top = 8.dp))
        // iOS's: the note itself in serif, edited in place, not a boxed field.
        BasicTextField(
            value = notes,
            // Written as it is typed, as iOS does. It was written only when the field lost
            // focus, and leaving the page is not that, so a description typed and then left
            // straight away was lost. Each write takes the latest text when it runs, so the
            // last one wins whatever order they finish in.
            // The screen's queue takes the text too, so a colour, Keep or tag written next does
            // not write the old description back over it (A49 F7). The write outlives the page
            // (started at once, not cancellable), so leaving mid-write keeps it (A49 F6).
            onValueChange = {
                notes = it
                queue = current.copy(notes = it)
                scope.launch(start = CoroutineStart.UNDISPATCHED) {
                    withContext(NonCancellable) {
                        notesWrites.withLock { writeQueue(repository, current, tags, notes = notes) }
                    }
                }
            },
            textStyle = TextStyle(color = tokens.primaryInk, fontSize = 16.sp, fontFamily = FontFamily.Serif),
            cursorBrush = SolidColor(palette.accent),
            decorationBox = { inner ->
                Box {
                    if (notes.isEmpty()) {
                        Text("Add a description", color = tokens.tertiaryInk, fontSize = 16.sp, fontFamily = FontFamily.Serif)
                    }
                    inner()
                }
            },
            modifier = Modifier
                .padding(horizontal = 16.dp, vertical = 6.dp)
                .fillMaxWidth()
                .semantics { contentDescription = "Description" }
                .onFocusChanged { notesFocused = it.isFocused }
        )
        SubjectFieldLabel("Tags", Modifier.padding(start = 16.dp, top = 16.dp))
        FlowRow(
            Modifier.padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            tags.forEach { name ->
                SubjectChip(
                    text = name,
                    style = SubjectChipStyle.Tinted,
                    trailingIcon = Icons.Outlined.Close,
                    palette = palette,
                    modifier = Modifier.semantics { contentDescription = "Remove $name" }.clickable {
                        scope.launch {
                            writeQueue(repository, current, tags.filterNot { it == name })
                            reload += 1
                        }
                    }
                )
            }
            SubjectChip(
                text = "Add tag",
                style = SubjectChipStyle.Dashed,
                leadingIcon = Icons.Outlined.Add,
                modifier = Modifier.clickable { showTags = true }
            )
        }
        SubjectFieldLabel("Details", Modifier.padding(start = 16.dp, top = 18.dp))
        Column(Modifier.padding(horizontal = 16.dp).fillMaxWidth().subjectPanel()) {
            Box {
                SubjectFormRow(
                    label = "Colour",
                    showsDisclosure = true,
                    onClick = { colourMenu = true },
                    trailing = {
                        Canvas(Modifier.size(22.dp).clip(CircleShape).background(palette.accent)) {}
                    }
                )
                DropdownMenu(expanded = colourMenu, onDismissRequest = { colourMenu = false }) {
                    SubjectHueSwatches.all.forEach { swatch ->
                        DropdownMenuItem(
                            text = { Text(swatch.name) },
                            onClick = {
                                colourMenu = false
                                scope.launch {
                                    writeQueue(repository, current, tags, hue = swatch.hue, colorHex = null)
                                    reload += 1
                                }
                            }
                        )
                    }
                    DropdownMenuItem(
                        text = { Text("From queue name") },
                        onClick = {
                            colourMenu = false
                            scope.launch {
                                writeQueue(repository, current, tags, hue = null, colorHex = null)
                                reload += 1
                            }
                        }
                    )
                }
            }
            SubjectRowSeparator()
            SubjectFormRow(
                label = "Keep works offline",
                trailing = {
                    SubjectToggle(
                        checked = current.keepsWorksOffline != false,
                        onCheckedChange = { on ->
                            scope.launch {
                                writeQueue(repository, current, tags, keep = on)
                                reload += 1
                            }
                        },
                        accent = palette.accent,
                        contentDescription = "Keep works offline"
                    )
                }
            )
            SubjectRowSeparator()
            SubjectFormRow(label = "Order", value = "Manual")
            SubjectRowSeparator()
            SubjectFormRow(label = "Last read", value = lastReadLabel(works))
        }
        FormFootnote(
            "When this is off, the queue keeps only your list. It doesn't download or keep copies, " +
                "so it uses no extra storage.",
            Modifier.padding(start = 16.dp, end = 16.dp, top = 6.dp)
        )
        SubjectFormRow(
            label = "Manage all tags",
            value = vocabulary.toString(),
            showsDisclosure = true,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp).subjectPanel(),
            onClick = { managing = true }
        )
    }

    if (showTags) {
        QueueTagSheet(
            repository = repository,
            queues = listOf(current),
            palette = palette,
            onDismiss = { showTags = false; reload += 1 }
        )
    }
}

private fun lastReadLabel(works: List<SavedWork>): String {
    val latest = ReadingQueueFacts.lastRead(works.map { it.lastReadDate }) ?: return "Never"
    return ReadingQueueFacts.relativeNamed(latest, Instant.now())
}

private suspend fun writeQueue(
    repository: ReadingQueueRepository,
    queue: ReadingQueue,
    tags: List<String>,
    notes: String? = queue.notes,
    hue: Double? = queue.hue,
    colorHex: String? = queue.colorHex,
    keep: Boolean = queue.keepsWorksOffline != false
) {
    repository.updateQueue(
        queue.id,
        QueueEdit(
            name = queue.name,
            hue = hue,
            colorHex = colorHex,
            keepsWorksOffline = keep,
            notes = notes,
            tagNames = tags
        )
    )
}
