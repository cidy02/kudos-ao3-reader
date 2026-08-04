package io.github.cidy02.kudos.reader

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ChatBubbleOutline
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.TextFields
import androidx.compose.material3.AlertDialog
import io.github.cidy02.kudos.ui.components.DestructiveConfirmation
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Snackbar
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import io.github.cidy02.kudos.core.model.ReaderFontCatalog
import io.github.cidy02.kudos.core.model.ReadingAnnotation
import io.github.cidy02.kudos.reader.readium.ReadiumNavigatorController
import io.github.cidy02.kudos.reader.readium.ReadiumNavigatorHost
import io.github.cidy02.kudos.reader.readium.ReadiumOpenResult
import io.github.cidy02.kudos.reader.readium.ReadiumProgressAdapter
import io.github.cidy02.kudos.reader.readium.ReadiumPublicationOpener
import io.github.cidy02.kudos.reader.readium.ReadiumSettingsAdapter
import io.github.cidy02.kudos.reader.readium.ReadiumTocAdapter
import io.github.cidy02.kudos.reader.settings.ReaderColorTheme
import io.github.cidy02.kudos.reader.settings.ReaderPreferences
import io.github.cidy02.kudos.reader.settings.ReaderSettingsMapper
import io.github.cidy02.kudos.reader.settings.backgroundColor
import io.github.cidy02.kudos.reader.speech.ReaderSpeechController
import io.github.cidy02.kudos.reader.speech.SpeechStatus
import io.github.cidy02.kudos.ui.components.ReaderPageSkeleton
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.VolumeUp
import kotlin.math.roundToInt
import kotlinx.coroutines.launch
import org.readium.r2.shared.publication.Locator

/**
 * Real reader entry point. Resolves the work (via [ReaderViewModel]/repository),
 * opens the EPUB with Readium, restores progress, hosts the navigator, and
 * persists progress on close. Shows loading/error states; never crashes on a
 * missing/corrupt EPUB.
 *
 * Epic 3 chrome: immersive top/bottom bars (tap content to toggle), TOC sheet,
 * display sheet (font size + theme), and live progress label.
 *
 * Initial font/theme come from [ReaderUiState.Reading.preferences] (open →
 * DataStore snapshot). The display sheet only mutates that in-session state;
 * persistence of sheet changes is deferred 3a — until then, re-open reloads
 * whatever is already stored in settings (defaults or backup restore).
 */
@Composable
fun ReaderScreen(
    viewModel: ReaderViewModel,
    onBack: () -> Unit,
    onOpenComments: (Long) -> Unit,
    /** Local library work id (not AO3 id) — opens Work Detail over the reader stack. */
    onOpenWorkDetail: (String) -> Unit,
    settingsRepository: io.github.cidy02.kudos.data.preferences.SettingsRepository? = null
) {
    val uiState by viewModel.state.collectAsState()
    val settingsState = settingsRepository?.settings?.collectAsState(initial = io.github.cidy02.kudos.core.model.KudosSettings.Defaults)
    val settings = settingsState?.value ?: io.github.cidy02.kudos.core.model.KudosSettings.Defaults
    // Once reading, use the reader's own selected theme, not the app theme — the two
    // can diverge (matchAppReaderTheme = false), and using the app's background here
    // caused a visible flash against the Readium navigator's correctly-reader-themed
    // content. Loading/Error have no reader preferences yet, so they keep the app
    // background — a brief loading flash if the two differ, not fixed in this pass.
    val backgroundColor = (uiState as? ReaderUiState.Reading)
        ?.preferences?.theme?.backgroundColor()
        ?: MaterialTheme.colorScheme.background
    Surface(modifier = Modifier.fillMaxSize(), color = backgroundColor) {
        when (val state = uiState) {
            // Skeleton-only open path (hig-review): no centered spinner flash.
            ReaderUiState.Loading -> ReaderPageSkeleton(message = "Opening…")
            is ReaderUiState.Error -> ReaderErrorView(
                error = state.error,
                onBack = onBack,
                onRetry = { viewModel.load() },
                onRemoveOfflineCopy = if (state.error is ReaderError.FileMissing) {
                    { viewModel.markEpubMissing(); onBack() }
                } else {
                    null
                }
            )
            is ReaderUiState.Reading -> ReaderReading(state, viewModel, onBack, onOpenComments, onOpenWorkDetail, settings)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReaderReading(
    state: ReaderUiState.Reading,
    viewModel: ReaderViewModel,
    onBack: () -> Unit,
    onOpenComments: (Long) -> Unit,
    onOpenWorkDetail: (String) -> Unit,
    settings: io.github.cidy02.kudos.core.model.KudosSettings
) {
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current
    val opener = remember { ReadiumPublicationOpener(context) }
    val linkHandler = remember { ReaderLinkHandler() }
    val navigatorController = remember { ReadiumNavigatorController() }
    var attempt by remember { mutableIntStateOf(0) }
    // Start visible so first-open controls are discoverable; tap content to hide.
    var chromeVisible by remember { mutableStateOf(true) }
    var showTocSheet by remember { mutableStateOf(false) }
    var showDisplaySheet by remember { mutableStateOf(false) }
    var showTtsControls by remember { mutableStateOf(false) }
    var showSearchSheet by remember { mutableStateOf(false) }
    var searchQuery by remember { mutableStateOf("") }
    var dismissOffsetY by remember { mutableFloatStateOf(0f) }
    var annotateDialog by remember { mutableStateOf<AnnotateDialogState?>(null) }
    var noteEditor by remember { mutableStateOf<ReadingAnnotation?>(null) }
    var showDeleteNoteConfirm by remember { mutableStateOf<ReadingAnnotation?>(null) }
    val scope = rememberCoroutineScope()

    val speechController = remember(context) { ReaderSpeechController(context) }
    val speechStatus by speechController.status.collectAsState()
    val writeMessage by viewModel.writeMessage.collectAsState()
    val searchHits by viewModel.searchHits.collectAsState()
    val searchLoading by viewModel.searchLoading.collectAsState()

    DisposableEffect(speechController) {
        onDispose { speechController.shutdown() }
    }

    LaunchedEffect(state.preferences, state.work.title) {
        speechController.configure(state.preferences, state.work.title)
    }

    LaunchedEffect(state.highlights) {
        navigatorController.applyHighlightDecorations(state.highlights)
    }

    LaunchedEffect(writeMessage) {
        if (writeMessage != null) {
            kotlinx.coroutines.delay(3500)
            viewModel.clearWriteMessage()
        }
    }

    // Persist any pending progress when leaving the reader (route change / activity destroy)…
    DisposableEffect(Unit) {
        onDispose { viewModel.flushProgress() }
    }
    // …and when the app is merely backgrounded, so an OS process kill cannot drop
    // the last debounce window of reading position.
    LifecycleEventEffect(Lifecycle.Event.ON_STOP) { viewModel.flushProgress() }

    val opening by produceState<ReadiumOpenResult?>(initialValue = null, state.epubPath, attempt) {
        value = null
        value = opener.open(state.epubPath.toFile())
    }

    DestructiveConfirmation(
        show = showDeleteNoteConfirm != null,
        title = "Delete annotation?",
        text = "This will permanently remove this bookmark or highlight.",
        confirmBeforeDelete = settings.app.confirmBeforeDelete,
        onConfirm = {
            val id = showDeleteNoteConfirm?.id ?: return@DestructiveConfirmation
            showDeleteNoteConfirm = null
            viewModel.deleteAnnotation(id)
        },
        onDismissRequest = { showDeleteNoteConfirm = null }
    )

    when (val result = opening) {
        null -> ReaderPageSkeleton(
            message = "Opening “${state.work.title}”…",
            backgroundColor = state.preferences.theme.backgroundColor()
        )
        is ReadiumOpenResult.Failure -> ReaderErrorView(
            error = result.error,
            onBack = onBack,
            onRetry = { attempt++ },
            onRemoveOfflineCopy = if (result.error is ReaderError.FileMissing) {
                { viewModel.markEpubMissing(); onBack() }
            } else {
                null
            }
        )
        is ReadiumOpenResult.Success -> {
            val publication = result.publication
            val epubPreferences = remember(state.preferences) {
                ReadiumSettingsAdapter.toEpubPreferences(state.preferences)
            }
            val initialLocator = remember(publication, state.restoreTarget) {
                ReadiumProgressAdapter.initialLocator(state.restoreTarget, publication)
            }
            val tocEntries = remember(publication) { ReadiumTocAdapter.entries(publication) }
            val sections = remember(publication) { ReadiumTocAdapter.sections(publication) }
            val progressLabel = ReaderProgressDisplay.label(state.liveProgress, sections)
            val minutesRemaining = ReaderProgressDisplay.minutesRemaining(
                state.liveProgress,
                wordCount = state.work.wordCount
            )
            val bottomLabel = if (minutesRemaining != null) {
                "$progressLabel · ~$minutesRemaining min left"
            } else {
                progressLabel
            }

            LaunchedEffect(publication) {
                viewModel.setSpineCount(publication.readingOrder.size)
            }

            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .offset { IntOffset(0, dismissOffsetY.roundToInt()) }
            ) {
                ReadiumNavigatorHost(
                    modifier = Modifier.fillMaxSize(),
                    publication = publication,
                    initialLocator = initialLocator,
                    preferences = epubPreferences,
                    controller = navigatorController,
                    onContentTap = { chromeVisible = !chromeVisible },
                    onLocatorChanged = { locator ->
                        viewModel.onProgress(
                            ReadiumProgressAdapter.toReaderProgress(publication, locator)
                        )
                    },
                    onExternalLink = { url ->
                        when (val destination = linkHandler.classify(url)) {
                            // In-book AO3 work links open remote detail; title chrome uses local id.
                            is ReaderLinkDestination.WorkDetail -> openExternal(
                                context,
                                "https://archiveofourown.org/works/${destination.workId}"
                            )
                            is ReaderLinkDestination.External -> openExternal(context, destination.url)
                            is ReaderLinkDestination.TagSearch -> openExternal(context, url)
                            ReaderLinkDestination.Unhandled -> Unit
                        }
                    },
                    fontDeclarations = state.preferences.fontDeclarations,
                    onNavigatorReady = {
                        scope.launch {
                            navigatorController.applyHighlightDecorations(state.highlights)
                        }
                    }
                )

                // Swipe-down-to-dismiss only on the top chrome edge so scroll-mode
                // reading is not stolen by a full-screen drag detector.
                if (chromeVisible) {
                    Box(
                        modifier = Modifier
                            .align(Alignment.TopCenter)
                            .fillMaxWidth()
                            .height(72.dp)
                            .pointerInput(Unit) {
                                detectVerticalDragGestures(
                                    onDragEnd = {
                                        if (dismissOffsetY > 180f) onBack()
                                        else dismissOffsetY = 0f
                                    },
                                    onDragCancel = { dismissOffsetY = 0f },
                                    onVerticalDrag = { change, dragAmount ->
                                        if (dragAmount > 0 || dismissOffsetY > 0) {
                                            change.consume()
                                            dismissOffsetY =
                                                (dismissOffsetY + dragAmount).coerceAtLeast(0f)
                                        }
                                    }
                                )
                            }
                    )
                }

                AnimatedVisibility(
                    visible = chromeVisible,
                    enter = fadeIn() + slideInVertically { -it },
                    exit = fadeOut() + slideOutVertically { -it },
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .fillMaxWidth()
                ) {
                    ReaderTopBar(
                        title = state.work.title,
                        author = state.work.author,
                        finished = state.finished,
                        localWorkId = state.work.id,
                        commentsWorkId = state.endOfWork.workId.takeIf { state.endOfWork.commentsAvailable },
                        canKudos = state.endOfWork.workId != null,
                        onBack = onBack,
                        onOpenComments = onOpenComments,
                        onMarkFinished = viewModel::markFinished,
                        onOpenToc = { showTocSheet = true },
                        onOpenDisplay = { showDisplaySheet = true },
                        onOpenWorkDetail = onOpenWorkDetail,
                        onToggleTts = { showTtsControls = !showTtsControls },
                        onOpenSearch = { showSearchSheet = true },
                        onGiveKudos = { viewModel.giveKudos() },
                        onBookmarkPosition = {
                            val progress = state.liveProgress ?: return@ReaderTopBar
                            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                            viewModel.toggleBookmarkAtProgress(
                                progress = progress,
                                locatorString = progress.locatorJson.orEmpty(),
                                chapterTitle = progressLabel
                            )
                        },
                        onHighlightSelection = {
                            scope.launch {
                                val selection = navigatorController.currentSelection()
                                if (selection == null) {
                                    viewModel.clearWriteMessage()
                                    // Reuse write message channel for soft UI feedback.
                                    annotateDialog = null
                                } else {
                                    val locator = selection.locator
                                    val text = locator.text.highlight.orEmpty()
                                    annotateDialog = AnnotateDialogState(
                                        locatorJson = locator.toJSON().toString(),
                                        selectedText = text,
                                        progression = locator.locations.totalProgression
                                            ?: locator.locations.progression
                                            ?: 0.0,
                                        spineIndex = state.liveProgress?.spineIndex ?: 0,
                                        asNote = false
                                    )
                                    navigatorController.clearSelection()
                                }
                            }
                        },
                        onNoteSelection = {
                            scope.launch {
                                val selection = navigatorController.currentSelection()
                                if (selection != null) {
                                    val locator = selection.locator
                                    annotateDialog = AnnotateDialogState(
                                        locatorJson = locator.toJSON().toString(),
                                        selectedText = locator.text.highlight.orEmpty(),
                                        progression = locator.locations.totalProgression
                                            ?: locator.locations.progression
                                            ?: 0.0,
                                        spineIndex = state.liveProgress?.spineIndex ?: 0,
                                        asNote = true
                                    )
                                    navigatorController.clearSelection()
                                }
                            }
                        }
                    )
                }

                AnimatedVisibility(
                    visible = chromeVisible && bottomLabel.isNotEmpty() && !showTtsControls,
                    enter = fadeIn() + slideInVertically { it },
                    exit = fadeOut() + slideOutVertically { it },
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .fillMaxWidth()
                ) {
                    val currentProgress = state.liveProgress?.totalProgression?.toFloat()
                        ?: ReaderProgressDisplay.percent(
                            state.liveProgress,
                            publication.readingOrder.size
                        )?.div(100f) ?: 0f
                    ReaderBottomProgress(
                        label = bottomLabel,
                        progress = currentProgress.coerceIn(0f, 1f),
                        onSeek = { progression ->
                            haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            val spineCount = publication.readingOrder.size
                            if (spineCount > 0) {
                                val targetIndex = (progression * spineCount).toInt()
                                    .coerceIn(0, spineCount - 1)
                                val fraction = (progression * spineCount) - targetIndex
                                val target = ReaderRestoreTarget.Fallback(
                                    targetIndex,
                                    fraction.toDouble()
                                )
                                val loc = ReadiumProgressAdapter.initialLocator(target, publication)
                                if (loc != null) {
                                    navigatorController.go(loc, animated = false)
                                }
                            }
                        }
                    )
                }

                AnimatedVisibility(
                    visible = chromeVisible && showTtsControls,
                    enter = fadeIn() + slideInVertically { it },
                    exit = fadeOut() + slideOutVertically { it },
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .fillMaxWidth()
                ) {
                    ReaderTtsControls(
                        status = speechStatus,
                        onPlay = {
                            if (speechStatus == SpeechStatus.PAUSED) {
                                speechController.resume()
                            } else {
                                scope.launch {
                                    val from = state.liveProgress?.locatorJson
                                        ?.let { ReadiumNavigatorController.locatorFromJson(it) }
                                    val paragraphs = ReaderContentText.paragraphs(publication, from)
                                        .ifEmpty {
                                            buildList {
                                                if (state.work.title.isNotBlank()) add(state.work.title)
                                                tocEntries.forEach { e ->
                                                    if (e.title.isNotBlank()) add(e.title)
                                                }
                                            }
                                        }
                                        .ifEmpty {
                                            listOf(state.work.title.ifBlank { "No text available." })
                                        }
                                    speechController.startReading(paragraphs)
                                }
                            }
                        },
                        onPause = { speechController.pause() },
                        onStop = {
                            speechController.stop()
                            showTtsControls = false
                        },
                        onSkipNext = { speechController.skipForward() },
                        onSkipPrevious = { speechController.skipBackward() }
                    )
                }

                writeMessage?.let { message ->
                    Snackbar(
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .padding(16.dp)
                            .navigationBarsPadding(),
                        action = {
                            TextButton(onClick = viewModel::clearWriteMessage) {
                                Text("OK")
                            }
                        }
                    ) { Text(message) }
                }
            }

            if (showSearchSheet) {
                val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
                ModalBottomSheet(
                    onDismissRequest = {
                        showSearchSheet = false
                        viewModel.clearSearch()
                    },
                    sheetState = sheetState
                ) {
                    ReaderSearchSheet(
                        query = searchQuery,
                        onQueryChange = { searchQuery = it },
                        loading = searchLoading,
                        hits = searchHits,
                        onSearch = { viewModel.runSearch(publication, searchQuery) },
                        onSelectHit = { hit ->
                            navigatorController.go(hit.locator, animated = true)
                            scope.launch {
                                sheetState.hide()
                                showSearchSheet = false
                            }
                        }
                    )
                }
            }

            annotateDialog?.let { dialog ->
                AnnotateDialog(
                    state = dialog,
                    onDismiss = { annotateDialog = null },
                    onConfirm = { color, note ->
                        viewModel.addHighlight(
                            locatorString = dialog.locatorJson,
                            selectedText = dialog.selectedText,
                            color = color,
                            note = note,
                            progression = dialog.progression,
                            spineIndex = dialog.spineIndex,
                            asNote = dialog.asNote
                        )
                        annotateDialog = null
                    }
                )
            }

            noteEditor?.let { annotation ->
                var editNote by remember(annotation.id) { mutableStateOf(annotation.note) }
                AlertDialog(
                    onDismissRequest = { noteEditor = null },
                    title = { Text("Edit note") },
                    text = {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            if (annotation.selectedText.isNotBlank()) {
                                Text(
                                    annotation.selectedText,
                                    style = MaterialTheme.typography.bodyMedium,
                                    maxLines = 4,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                            OutlinedTextField(
                                value = editNote,
                                onValueChange = { editNote = it },
                                label = { Text("Note") },
                                modifier = Modifier.fillMaxWidth(),
                                minLines = 3
                            )
                        }
                    },
                    confirmButton = {
                        TextButton(
                            onClick = {
                                viewModel.updateNote(annotation.id, editNote)
                                noteEditor = null
                            }
                        ) { Text("Save") }
                    },
                    dismissButton = {
                        Row {
                            TextButton(
                                onClick = {
                                    val annotationToDelete = annotation
                                    noteEditor = null
                                    showDeleteNoteConfirm = annotationToDelete
                                }
                            ) { Text("Delete") }
                            TextButton(onClick = { noteEditor = null }) { Text("Cancel") }
                        }
                    }
                )
            }

            if (showTocSheet) {
                val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)
                ModalBottomSheet(
                    onDismissRequest = { showTocSheet = false },
                    sheetState = sheetState
                ) {
                    ReaderTocSheet(
                        entries = tocEntries,
                        bookmarks = state.bookmarks,
                        highlights = state.highlights,
                        onSelectEntry = { entry ->
                            val link = ReadiumTocAdapter.resolveLink(publication, entry)
                            if (link != null) {
                                navigatorController.go(link, animated = true)
                            }
                            scope.launch {
                                sheetState.hide()
                                showTocSheet = false
                            }
                        },
                        onSelectAnnotation = { annotation ->
                            val locator = ReadiumNavigatorController.locatorFromJson(
                                annotation.locatorString
                            )
                            if (locator != null) {
                                navigatorController.go(locator, animated = true)
                            }
                            if (annotation.kindRaw.equals("note", ignoreCase = true) ||
                                annotation.note.isNotBlank()
                            ) {
                                noteEditor = annotation
                            }
                            scope.launch {
                                sheetState.hide()
                                showTocSheet = false
                            }
                        },
                        onDeleteAnnotation = { annotation ->
                            showDeleteNoteConfirm = annotation
                        }
                    )
                }
            }

            if (showDisplaySheet) {
                val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
                ModalBottomSheet(
                    onDismissRequest = { showDisplaySheet = false },
                    sheetState = sheetState
                ) {
                    ReaderDisplaySheet(
                        preferences = state.preferences,
                        onFontSizeChange = viewModel::setFontSizePercent,
                        onThemeChange = viewModel::setColorTheme,
                        onScrollModeChange = viewModel::setScrollMode,
                        onTwoPageChange = viewModel::setTwoPage,
                        onBoldChange = viewModel::setBold,
                        onLetterSpacingChange = viewModel::setLetterSpacing,
                        onWordSpacingChange = viewModel::setWordSpacing,
                        onSpeechRateChange = viewModel::setSpeechRate,
                        onSpeechPitchChange = viewModel::setSpeechPitch,
                        onFontFamilyChange = viewModel::setFontFamily
                    )
                }
            }
        }
    }
}


@Composable
private fun ReaderFontSection(
    currentFontId: String?,
    onFontFamilyChange: (String?) -> Unit
) {
    val options = ReaderFontCatalog.builtIns
    val currentId = currentFontId ?: "system"

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(text = "Font", style = MaterialTheme.typography.titleSmall)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            options.forEach { option ->
                FilterChip(
                    selected = currentId == option.id,
                    onClick = { onFontFamilyChange(if (option.id == "system") null else option.id) },
                    label = { Text(option.name) }
                )
            }
        }
    }
}


@Composable
private fun ReaderTopBar(
    title: String,
    author: String,
    finished: Boolean,
    localWorkId: String,
    commentsWorkId: Long?,
    canKudos: Boolean,
    onBack: () -> Unit,
    onOpenComments: (Long) -> Unit,
    onOpenWorkDetail: (String) -> Unit,
    onMarkFinished: () -> Unit,
    onOpenToc: () -> Unit,
    onOpenDisplay: () -> Unit,
    onToggleTts: () -> Unit,
    onOpenSearch: () -> Unit,
    onGiveKudos: () -> Unit,
    onBookmarkPosition: () -> Unit = {},
    onHighlightSelection: () -> Unit = {},
    onNoteSelection: () -> Unit = {}
) {
    val context = LocalContext.current
    var showOverflow by remember { mutableStateOf(false) }
    var isOrientationLocked by remember { mutableStateOf(false) }

    DisposableEffect(Unit) {
        onDispose {
            // Restore free rotation when leaving the reader (session-only lock).
            val activity = context as? android.app.Activity
            activity?.requestedOrientation =
                android.content.pm.ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        }
    }

    Surface(
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.96f),
        tonalElevation = 3.dp,
        shadowElevation = 2.dp
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .padding(horizontal = 4.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
            }
            Column(
                modifier = Modifier
                    .weight(1f)
                    .clickable { onOpenWorkDetail(localWorkId) }
            ) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleMedium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                if (author.isNotBlank()) {
                    Text(
                        text = author,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
            IconButton(onClick = onOpenSearch) {
                Icon(Icons.Filled.Search, contentDescription = "Find in work")
            }
            IconButton(onClick = onOpenToc) {
                Icon(Icons.AutoMirrored.Filled.List, contentDescription = "Contents")
            }
            IconButton(onClick = onOpenDisplay) {
                Icon(Icons.Filled.TextFields, contentDescription = "Display")
            }
            IconButton(onClick = onToggleTts) {
                Icon(Icons.Filled.VolumeUp, contentDescription = "Text to Speech")
            }
            Box {
                IconButton(onClick = { showOverflow = true }) {
                    Icon(Icons.Filled.MoreVert, contentDescription = "More actions")
                }
                androidx.compose.material3.DropdownMenu(
                    expanded = showOverflow,
                    onDismissRequest = { showOverflow = false }
                ) {
                    if (canKudos) {
                        androidx.compose.material3.DropdownMenuItem(
                            text = { Text("Give kudos") },
                            onClick = {
                                showOverflow = false
                                onGiveKudos()
                            }
                        )
                    }
                    commentsWorkId?.let { workId ->
                        androidx.compose.material3.DropdownMenuItem(
                            text = { Text("Comments") },
                            onClick = {
                                showOverflow = false
                                onOpenComments(workId)
                            }
                        )
                        androidx.compose.material3.DropdownMenuItem(
                            text = { Text("Share work") },
                            onClick = {
                                showOverflow = false
                                val sendIntent = Intent(Intent.ACTION_SEND).apply {
                                    putExtra(
                                        Intent.EXTRA_TEXT,
                                        "https://archiveofourown.org/works/$workId"
                                    )
                                    type = "text/plain"
                                }
                                context.startActivity(
                                    Intent.createChooser(sendIntent, "Share work link")
                                )
                            }
                        )
                    }
                    androidx.compose.material3.DropdownMenuItem(
                        text = { Text("Toggle bookmark") },
                        onClick = {
                            showOverflow = false
                            onBookmarkPosition()
                        }
                    )
                    androidx.compose.material3.DropdownMenuItem(
                        text = { Text("Highlight selection") },
                        onClick = {
                            showOverflow = false
                            onHighlightSelection()
                        }
                    )
                    androidx.compose.material3.DropdownMenuItem(
                        text = { Text("Add note to selection") },
                        onClick = {
                            showOverflow = false
                            onNoteSelection()
                        }
                    )
                    androidx.compose.material3.DropdownMenuItem(
                        text = { Text(if (finished) "Finished" else "Mark finished") },
                        enabled = !finished,
                        onClick = {
                            showOverflow = false
                            onMarkFinished()
                        }
                    )
                    androidx.compose.material3.DropdownMenuItem(
                        text = {
                            Text(
                                if (isOrientationLocked) "Unlock orientation" else "Lock portrait"
                            )
                        },
                        onClick = {
                            showOverflow = false
                            isOrientationLocked = !isOrientationLocked
                            val activity = context as? android.app.Activity
                            activity?.requestedOrientation = if (isOrientationLocked) {
                                android.content.pm.ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                            } else {
                                android.content.pm.ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                            }
                        }
                    )
                }
            }
        }
    }
}

@Composable
private fun ReaderBottomProgress(
    label: String,
    progress: Float,
    onSeek: (Float) -> Unit
) {
    Surface(
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.96f),
        tonalElevation = 3.dp,
        shadowElevation = 2.dp
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Slider(
                value = progress,
                onValueChange = onSeek,
                modifier = Modifier.fillMaxWidth()
            )
            Text(
                text = label,
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun ReaderTocSheet(
    entries: List<ReaderTocEntry>,
    bookmarks: List<ReadingAnnotation>,
    highlights: List<ReadingAnnotation>,
    onSelectEntry: (ReaderTocEntry) -> Unit,
    onSelectAnnotation: (ReadingAnnotation) -> Unit,
    onDeleteAnnotation: (ReadingAnnotation) -> Unit = {}
) {
    var selectedTab by remember { mutableIntStateOf(0) }
    val tabs = listOf("Contents", "Bookmarks", "Highlights")

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .padding(bottom = 16.dp)
    ) {
        androidx.compose.material3.TabRow(selectedTabIndex = selectedTab) {
            tabs.forEachIndexed { index, title ->
                androidx.compose.material3.Tab(
                    selected = selectedTab == index,
                    onClick = { selectedTab = index },
                    text = { Text(title) }
                )
            }
        }

        when (selectedTab) {
            0 -> {
                if (entries.isEmpty()) {
                    Text(
                        text = "No chapters available.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 24.dp, vertical = 16.dp)
                    )
                } else {
                    LazyColumn(contentPadding = PaddingValues(bottom = 8.dp)) {
                        items(entries, key = { "${it.depth}:${it.href}:${it.title}" }) { entry ->
                            Text(
                                text = entry.title,
                                style = MaterialTheme.typography.bodyLarge,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable { onSelectEntry(entry) }
                                    .padding(
                                        start = (24 + entry.depth * 16).dp,
                                        end = 24.dp,
                                        top = 12.dp,
                                        bottom = 12.dp
                                    )
                            )
                        }
                    }
                }
            }
            1 -> AnnotationList(
                emptyMessage = "No bookmarks.",
                items = bookmarks,
                onSelect = onSelectAnnotation,
                onDelete = onDeleteAnnotation
            )
            2 -> AnnotationList(
                emptyMessage = "No highlights.",
                items = highlights,
                onSelect = onSelectAnnotation,
                onDelete = onDeleteAnnotation
            )
        }
    }
}

@Composable
private fun AnnotationList(
    emptyMessage: String,
    items: List<ReadingAnnotation>,
    onSelect: (ReadingAnnotation) -> Unit,
    onDelete: (ReadingAnnotation) -> Unit
) {
    if (items.isEmpty()) {
        Text(
            text = emptyMessage,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 24.dp, vertical = 16.dp)
        )
    } else {
        LazyColumn(contentPadding = PaddingValues(bottom = 8.dp)) {
            items(items, key = { it.id }) { annotation ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onSelect(annotation) }
                        .padding(horizontal = 24.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        val title = annotation.chapterTitle.ifBlank {
                            annotation.selectedText.ifBlank { "Annotation" }
                        }
                        Text(
                            text = title,
                            style = MaterialTheme.typography.bodyLarge,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis
                        )
                        if (annotation.note.isNotBlank()) {
                            Text(
                                text = annotation.note,
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis
                            )
                        }
                    }
                    TextButton(onClick = { onDelete(annotation) }) {
                        Text("Delete")
                    }
                }
            }
        }
    }
}

@Composable
private fun ReaderDisplaySheet(
    preferences: ReaderPreferences,
    onFontSizeChange: (Int) -> Unit,
    onThemeChange: (ReaderColorTheme) -> Unit,
    onScrollModeChange: (Boolean) -> Unit = {},
    onTwoPageChange: (Boolean) -> Unit = {},
    onBoldChange: (Boolean) -> Unit = {},
    onLetterSpacingChange: (Double) -> Unit = {},
    onWordSpacingChange: (Double) -> Unit = {},
    onSpeechRateChange: (Float) -> Unit = {},
    onSpeechPitchChange: (Float) -> Unit = {},
    onFontFamilyChange: (String?) -> Unit = {}
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .padding(horizontal = 24.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text(text = "Display", style = MaterialTheme.typography.titleLarge)

        Text(
            text = "Text size · ${preferences.fontSizePercent}%",
            style = MaterialTheme.typography.titleSmall
        )
        Slider(
            value = preferences.fontSizePercent.toFloat(),
            onValueChange = { onFontSizeChange(it.toInt()) },
            valueRange = ReaderSettingsMapper.MIN_FONT_PERCENT.toFloat()..
                ReaderSettingsMapper.MAX_FONT_PERCENT.toFloat(),
            steps = 19
        )

        Text(text = "Theme", style = MaterialTheme.typography.titleSmall)
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.fillMaxWidth()
        ) {
            ReaderColorTheme.entries.forEach { theme ->
                FilterChip(
                    selected = preferences.theme == theme,
                    onClick = { onThemeChange(theme) },
                    label = { Text(theme.name) }
                )
            }
        }

        Text(text = "Reading mode", style = MaterialTheme.typography.titleSmall)
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState())
        ) {
            FilterChip(
                selected = preferences.scroll,
                onClick = { onScrollModeChange(true) },
                label = { Text("Scroll") }
            )
            FilterChip(
                selected = !preferences.scroll,
                onClick = { onScrollModeChange(false) },
                label = { Text("Paged") }
            )
            FilterChip(
                selected = !preferences.scroll && preferences.columnCount >= 2,
                onClick = { onTwoPageChange(true) },
                label = { Text("Two-page") }
            )
        }

        ReaderFontSection(
            currentFontId = preferences.fontFamily,
            onFontFamilyChange = onFontFamilyChange
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("Bold text", style = MaterialTheme.typography.titleSmall)
            Switch(checked = preferences.bold, onCheckedChange = onBoldChange)
        }

        Text(
            text = "Letter spacing · ${"%.2f".format(preferences.letterSpacingEm)} em",
            style = MaterialTheme.typography.titleSmall
        )
        Slider(
            value = preferences.letterSpacingEm.toFloat(),
            onValueChange = { onLetterSpacingChange(it.toDouble()) },
            valueRange = 0f..0.5f
        )

        Text(
            text = "Word spacing · ${"%.2f".format(preferences.wordSpacingEm)} em",
            style = MaterialTheme.typography.titleSmall
        )
        Slider(
            value = preferences.wordSpacingEm.toFloat(),
            onValueChange = { onWordSpacingChange(it.toDouble()) },
            valueRange = 0f..1f
        )

        Text(text = "Read aloud", style = MaterialTheme.typography.titleMedium)
        Text(
            text = "Speed · ${"%.1f".format(preferences.speechRate)}×",
            style = MaterialTheme.typography.titleSmall
        )
        Slider(
            value = preferences.speechRate,
            onValueChange = onSpeechRateChange,
            valueRange = 0.5f..2.0f
        )
        Text(
            text = "Pitch · ${"%.1f".format(preferences.speechPitch)}",
            style = MaterialTheme.typography.titleSmall
        )
        Slider(
            value = preferences.speechPitch,
            onValueChange = onSpeechPitchChange,
            valueRange = 0.5f..2.0f
        )

        Spacer(modifier = Modifier.height(16.dp))
    }
}

@Composable
private fun ReaderSearchSheet(
    query: String,
    onQueryChange: (String) -> Unit,
    loading: Boolean,
    hits: List<ReaderSearchHit>,
    onSearch: () -> Unit,
    onSelectHit: (ReaderSearchHit) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("Find in work", style = MaterialTheme.typography.titleLarge)
        OutlinedTextField(
            value = query,
            onValueChange = onQueryChange,
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            label = { Text("Search") },
            trailingIcon = {
                TextButton(onClick = onSearch, enabled = query.isNotBlank() && !loading) {
                    Text(if (loading) "…" else "Search")
                }
            }
        )
        if (loading) {
            Text("Searching…", color = MaterialTheme.colorScheme.onSurfaceVariant)
        } else if (hits.isEmpty() && query.isNotBlank()) {
            Text("No matches.", color = MaterialTheme.colorScheme.onSurfaceVariant)
        } else {
            LazyColumn(
                modifier = Modifier.height(360.dp),
                contentPadding = PaddingValues(bottom = 16.dp)
            ) {
                items(hits, key = { "${it.locator.href}-${it.snippet.hashCode()}" }) { hit ->
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onSelectHit(hit) }
                            .padding(vertical = 10.dp)
                    ) {
                        if (hit.chapterTitle.isNotBlank()) {
                            Text(
                                hit.chapterTitle,
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.primary
                            )
                        }
                        Text(hit.snippet, style = MaterialTheme.typography.bodyMedium, maxLines = 3)
                    }
                }
            }
        }
    }
}

private data class AnnotateDialogState(
    val locatorJson: String,
    val selectedText: String,
    val progression: Double,
    val spineIndex: Int,
    val asNote: Boolean
)

@Composable
private fun AnnotateDialog(
    state: AnnotateDialogState,
    onDismiss: () -> Unit,
    onConfirm: (color: String, note: String) -> Unit
) {
    var color by remember { mutableStateOf("yellow") }
    var note by remember { mutableStateOf("") }
    val colors = listOf("yellow", "green", "pink", "purple", "blue")
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (state.asNote) "Add note" else "Highlight") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (state.selectedText.isNotBlank()) {
                    Text(
                        state.selectedText,
                        style = MaterialTheme.typography.bodyMedium,
                        maxLines = 4,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                Text("Color", style = MaterialTheme.typography.labelLarge)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    colors.forEach { c ->
                        FilterChip(
                            selected = color == c,
                            onClick = { color = c },
                            label = { Text(c.replaceFirstChar { it.uppercase() }) }
                        )
                    }
                }
                if (state.asNote) {
                    OutlinedTextField(
                        value = note,
                        onValueChange = { note = it },
                        label = { Text("Note") },
                        modifier = Modifier.fillMaxWidth(),
                        minLines = 2
                    )
                }
            }
        },
        confirmButton = {
            TextButton(onClick = { onConfirm(color, note) }) {
                Text(if (state.asNote) "Save note" else "Highlight")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        }
    )
}

@Composable
private fun ReaderErrorView(
    error: ReaderError,
    onBack: () -> Unit,
    onRetry: () -> Unit,
    onRemoveOfflineCopy: (() -> Unit)?
) {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            modifier = Modifier.padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text(
                text = "Couldn’t open this work",
                style = MaterialTheme.typography.headlineSmall
            )
            Text(
                text = error.message,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = onBack) { Text("Back") }
                Button(onClick = onRetry) { Text("Retry") }
            }
            if (onRemoveOfflineCopy != null) {
                TextButton(onClick = onRemoveOfflineCopy) { Text("Remove offline copy") }
            }
        }
    }
}

private fun openExternal(context: Context, url: String) {
    runCatching {
        context.startActivity(
            Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }
}

@Composable
private fun ReaderTtsControls(
    status: SpeechStatus,
    onPlay: () -> Unit,
    onPause: () -> Unit,
    onStop: () -> Unit,
    onSkipNext: () -> Unit = {},
    onSkipPrevious: () -> Unit = {}
) {
    Surface(
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.96f),
        tonalElevation = 3.dp,
        shadowElevation = 2.dp
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onSkipPrevious) {
                Icon(Icons.Filled.SkipPrevious, contentDescription = "Previous paragraph")
            }
            if (status == SpeechStatus.PLAYING) {
                IconButton(onClick = onPause) {
                    Icon(Icons.Filled.Pause, contentDescription = "Pause TTS")
                }
            } else {
                IconButton(onClick = onPlay) {
                    Icon(Icons.Filled.PlayArrow, contentDescription = "Play TTS")
                }
            }
            IconButton(onClick = onStop) {
                Icon(Icons.Filled.Stop, contentDescription = "Stop TTS")
            }
            IconButton(onClick = onSkipNext) {
                Icon(Icons.Filled.SkipNext, contentDescription = "Next paragraph")
            }
        }
    }
}
