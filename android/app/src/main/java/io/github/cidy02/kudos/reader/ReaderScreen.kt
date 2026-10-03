package io.github.cidy02.kudos.reader

import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.offset
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.IntOffset
import kotlin.math.roundToInt
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.BookmarkBorder
import androidx.compose.material.icons.filled.BorderColor
import androidx.compose.material.icons.filled.ChatBubbleOutline
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.ScreenLockRotation
import androidx.compose.material.icons.filled.ScreenRotation
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.TextFields
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
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
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.style.TextOverflow
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
import io.github.cidy02.kudos.ui.components.DestructiveConfirmation
import io.github.cidy02.kudos.ui.components.ReaderPageSkeleton
import io.github.cidy02.kudos.ui.components.workCardZoomDestination
import io.github.cidy02.kudos.ui.subject.KudosTokens
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.ReaderTheme
import kotlinx.coroutines.launch

/**
 * Real reader entry point. Resolves the work (via [ReaderViewModel]/repository),
 * opens the EPUB with Readium, restores progress, hosts the navigator, and
 * persists progress on close. Shows loading/error states; never crashes on a
 * missing/corrupt EPUB.
 *
 * Chrome redesigned to match iOS ReadiumReaderView:
 * - Floating [ReaderChromeTopBar]: 44pt close button, centered title pill, clear spacer.
 * - Floating [ReaderFanMenu]: 44pt more button fanning out into pills and round actions.
 * - Floating [ReaderPositionCard]: 24dp continuous glass card, mini player strip,
 *   page progress, time left, custom scrub slider with origin tick (`|`), and summary line.
 * - [ReaderContentsSheet]: segmented into Contents, Bookmarks, and Highlights with swatches.
 */
@Composable
fun ReaderScreen(
    viewModel: ReaderViewModel,
    onBack: () -> Unit,
    onOpenComments: (Long, Int?) -> Unit,
    /** Local library work id (not AO3 id) — opens Work Detail over the reader stack. */
    onOpenWorkDetail: (String) -> Unit,
    settingsRepository: io.github.cidy02.kudos.data.preferences.SettingsRepository? = null
) {
    val uiState by viewModel.state.collectAsState()
    val settingsState = settingsRepository?.settings?.collectAsState(initial = io.github.cidy02.kudos.core.model.KudosSettings.Defaults)
    val settings = settingsState?.value ?: io.github.cidy02.kudos.core.model.KudosSettings.Defaults

    val backgroundColor = (uiState as? ReaderUiState.Reading)
        ?.preferences?.theme?.backgroundColor()
        ?: MaterialTheme.colorScheme.background

    Surface(modifier = Modifier.fillMaxSize(), color = backgroundColor) {
        when (val state = uiState) {
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
    onOpenComments: (Long, Int?) -> Unit,
    onOpenWorkDetail: (String) -> Unit,
    settings: io.github.cidy02.kudos.core.model.KudosSettings
) {
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current
    val opener = remember { ReadiumPublicationOpener(context) }
    val linkHandler = remember { ReaderLinkHandler() }
    val navigatorController = remember { ReadiumNavigatorController() }
    var attempt by remember { mutableIntStateOf(0) }

    // Floating chrome visibility state
    // iOS ReadiumBook.chromeHidden starts true: the reader opens immersive; a tap shows the chrome.
    var chromeVisible by remember { mutableStateOf(false) }
    var dismissOffsetY by remember { mutableFloatStateOf(0f) }
    var fanMenuOpen by remember { mutableStateOf(false) }

    // Sheets
    var showTocSheet by remember { mutableStateOf(false) }
    var tocInitialTab by remember { mutableIntStateOf(0) }
    var showDisplaySheet by remember { mutableStateOf(false) }
    var showSearchSheet by remember { mutableStateOf(false) }
    var searchQuery by remember { mutableStateOf("") }
    var annotateDialog by remember { mutableStateOf<AnnotateDialogState?>(null) }
    var noteEditor by remember { mutableStateOf<ReadingAnnotation?>(null) }
    var showDeleteNoteConfirm by remember { mutableStateOf<ReadingAnnotation?>(null) }
    var isOrientationLocked by remember { mutableStateOf(false) }
    var showTtsControls by remember { mutableStateOf(false) }

    val scope = rememberCoroutineScope()

    val speechController = remember(context) { ReaderSpeechController(context) }
    val speechStatus by speechController.status.collectAsState()
    val spokenText by speechController.spokenText.collectAsState()
    val writeMessage by viewModel.writeMessage.collectAsState()
    val searchHits by viewModel.searchHits.collectAsState()
    val searchLoading by viewModel.searchLoading.collectAsState()

    val readerTheme = when (state.preferences.theme) {
        ReaderColorTheme.Light -> ReaderTheme.Light
        ReaderColorTheme.Sepia -> ReaderTheme.Sepia
        ReaderColorTheme.Dark -> ReaderTheme.Dark
        ReaderColorTheme.Oled -> ReaderTheme.Oled
    }
    val currentAccent = LocalKudosTokens.current.accent
    val tokens = KudosTokens.of(readerTheme, currentAccent)

    DisposableEffect(speechController) {
        onDispose { speechController.shutdown() }
    }

    DisposableEffect(Unit) {
        onDispose {
            // Restore free rotation when leaving the reader (session-only lock).
            val activity = context as? android.app.Activity
            activity?.requestedOrientation =
                android.content.pm.ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        }
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

    // Persist any pending progress when leaving the reader…
    DisposableEffect(Unit) {
        onDispose { viewModel.close() }
    }
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

            val currentProgress = state.liveProgress?.totalProgression?.toFloat()
                ?: ReaderProgressDisplay.percent(
                    state.liveProgress,
                    publication.readingOrder.size
                )?.div(100f) ?: 0f

            val page = state.liveProgress?.spineIndex?.plus(1) ?: 1
            val pageCount = publication.readingOrder.size.coerceAtLeast(1)

            LaunchedEffect(publication) {
                viewModel.setSpineCount(publication.readingOrder.size)
            }

            CompositionLocalProvider(LocalKudosTokens provides tokens) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .let { base ->
                            val ao3Id = state.endOfWork.workId
                            if (ao3Id != null) base.workCardZoomDestination(ao3Id) else base
                        }
                        .offset { IntOffset(0, dismissOffsetY.roundToInt()) }
                ) {
                    // EPUB Navigator
                    ReadiumNavigatorHost(
                        modifier = Modifier.fillMaxSize(),
                        publication = publication,
                        initialLocator = initialLocator,
                        preferences = epubPreferences,
                        controller = navigatorController,
                        onContentTap = {
                            if (fanMenuOpen) {
                                fanMenuOpen = false
                            } else {
                                chromeVisible = !chromeVisible
                            }
                        },
                        onLocatorChanged = { locator ->
                            viewModel.onProgress(
                                ReadiumProgressAdapter.toReaderProgress(publication, locator)
                            )
                        },
                        onExternalLink = { url ->
                            when (val destination = linkHandler.classify(url)) {
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

                    // Swipe down from the top edge to dismiss, as iOS's reader peel
                    // (ReadiumReaderView dismissableReaderCard). Only the top edge, so
                    // scroll-mode reading isn't stolen by a full-screen drag detector.
                    if (chromeVisible && !fanMenuOpen) {
                        Box(
                            modifier = Modifier
                                .align(Alignment.TopCenter)
                                .fillMaxWidth()
                                .height(72.dp)
                                .pointerInput(Unit) {
                                    detectVerticalDragGestures(
                                        onDragEnd = {
                                            if (dismissOffsetY > 180f) onBack() else dismissOffsetY = 0f
                                        },
                                        onDragCancel = { dismissOffsetY = 0f },
                                        onVerticalDrag = { change, dragAmount ->
                                            if (dragAmount > 0 || dismissOffsetY > 0) {
                                                change.consume()
                                                dismissOffsetY = (dismissOffsetY + dragAmount).coerceAtLeast(0f)
                                            }
                                        }
                                    )
                                }
                        )
                    }

                    // Invisible backdrop that closes fan menu without hiding chrome
                    ReaderFanMenuDismissBackdrop(
                        isOpen = fanMenuOpen && chromeVisible,
                        onDismiss = { fanMenuOpen = false }
                    )

                    // Floating Top Bar
                    AnimatedVisibility(
                        visible = chromeVisible,
                        enter = fadeIn() + slideInVertically { -it },
                        exit = fadeOut() + slideOutVertically { -it },
                        modifier = Modifier
                            .align(Alignment.TopCenter)
                            .fillMaxWidth()
                    ) {
                        ReaderChromeTopBar(
                            title = state.work.title,
                            author = state.work.author,
                            titleHidden = fanMenuOpen,
                            onClose = onBack,
                            onOpenDetails = { onOpenWorkDetail(state.work.id) }
                        )
                    }

                    // Floating Fan Menu (More button -> pills & round actions)
                    AnimatedVisibility(
                        visible = chromeVisible,
                        enter = fadeIn(),
                        exit = fadeOut(),
                        modifier = Modifier.align(Alignment.TopEnd)
                    ) {
                        val ao3Id = state.endOfWork.workId
                        val isBookmarked = state.bookmarks.any {
                            it.spineIndex == (state.liveProgress?.spineIndex ?: -1)
                        }

                        // Pills
                        val pills = buildList {
                            val percent = (currentProgress * 100).toInt()
                            add(
                                ReaderFanMenuPill(
                                    id = "contents",
                                    title = if (percent > 0) "Contents · $percent%" else "Contents",
                                    icon = Icons.AutoMirrored.Filled.List,
                                    action = {
                                        tocInitialTab = 0
                                        showTocSheet = true
                                    }
                                )
                            )
                            add(
                                ReaderFanMenuPill(
                                    id = "bookmarks",
                                    title = "Bookmarks & Highlights",
                                    icon = Icons.Filled.Bookmark,
                                    action = {
                                        tocInitialTab = 1
                                        showTocSheet = true
                                    }
                                )
                            )
                            add(
                                ReaderFanMenuPill(
                                    id = "find",
                                    title = "Find in Work",
                                    icon = Icons.Filled.Search,
                                    action = { showSearchSheet = true }
                                )
                            )
                            if (ao3Id != null && state.endOfWork.commentsAvailable) {
                                add(
                                    ReaderFanMenuPill(
                                        id = "comments",
                                        title = "Comments",
                                        icon = Icons.Filled.ChatBubbleOutline,
                                        action = {
                                            onOpenComments(
                                                ao3Id,
                                                state.liveProgress?.spineIndex?.plus(1)
                                            )
                                        }
                                    )
                                )
                            }
                            add(
                                ReaderFanMenuPill(
                                    id = "settings",
                                    title = "Themes & Settings",
                                    icon = Icons.Filled.TextFields,
                                    action = { showDisplaySheet = true }
                                )
                            )
                            add(
                                ReaderFanMenuPill(
                                    id = "markFinished",
                                    title = if (state.finished) "Finished" else "Mark finished",
                                    icon = Icons.Filled.Check,
                                    isEnabled = !state.finished,
                                    action = { viewModel.markFinished() }
                                )
                            )
                            add(
                                ReaderFanMenuPill(
                                    id = "highlightSelection",
                                    title = "Highlight selection",
                                    icon = Icons.Filled.BorderColor,
                                    action = {
                                        scope.launch {
                                            val selection = navigatorController.currentSelection()
                                            if (selection == null) {
                                                viewModel.clearWriteMessage()
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
                                    }
                                )
                            )
                            add(
                                ReaderFanMenuPill(
                                    id = "noteSelection",
                                    title = "Add note to selection",
                                    icon = Icons.Filled.Edit,
                                    action = {
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
                            )
                        }

                        // Round Actions
                        val roundActions = buildList {
                            // Share
                            add(
                                ReaderFanRoundAction(
                                    id = "share",
                                    icon = Icons.Filled.Share,
                                    accessibilityLabel = "Share",
                                    action = {
                                        val shareUrl = if (ao3Id != null) {
                                            "https://archiveofourown.org/works/$ao3Id"
                                        } else {
                                            state.work.title
                                        }
                                        val sendIntent = Intent(Intent.ACTION_SEND).apply {
                                            putExtra(Intent.EXTRA_TEXT, shareUrl)
                                            type = "text/plain"
                                        }
                                        context.startActivity(
                                            Intent.createChooser(sendIntent, "Share work link")
                                        )
                                    }
                                )
                            )

                            // Kudos
                            if (ao3Id != null) {
                                add(
                                    ReaderFanRoundAction(
                                        id = "kudos",
                                        icon = if (state.work.hasGivenKudos) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
                                        accessibilityLabel = if (state.work.hasGivenKudos) "Kudos given" else "Give kudos",
                                        isEnabled = !state.work.hasGivenKudos,
                                        isEmphasized = state.work.hasGivenKudos,
                                        action = { viewModel.giveKudos() }
                                    )
                                )
                            }

                            // Read Aloud
                            val speechActive = speechStatus == SpeechStatus.PLAYING || speechStatus == SpeechStatus.PAUSED
                            add(
                                ReaderFanRoundAction(
                                    id = "readAloud",
                                    icon = Icons.AutoMirrored.Filled.VolumeUp,
                                    accessibilityLabel = if (speechActive) "Stop reading aloud" else "Read aloud",
                                    isEnabled = true,
                                    isEmphasized = speechActive,
                                    action = {
                                        if (speechActive) {
                                            speechController.stop()
                                            showTtsControls = false
                                        } else if (speechStatus == SpeechStatus.MODEL_NOT_DOWNLOADED) {
                                            showTtsControls = true
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
                                    longPressAction = { showDisplaySheet = true }
                                )
                            )

                            // Lock Rotation
                            add(
                                ReaderFanRoundAction(
                                    id = "rotationLock",
                                    icon = if (isOrientationLocked) Icons.Filled.ScreenLockRotation else Icons.Filled.ScreenRotation,
                                    accessibilityLabel = if (isOrientationLocked) "Unlock rotation" else "Lock rotation",
                                    isEmphasized = isOrientationLocked,
                                    action = {
                                        isOrientationLocked = !isOrientationLocked
                                        val activity = context as? android.app.Activity
                                        activity?.requestedOrientation = if (isOrientationLocked) {
                                            android.content.pm.ActivityInfo.SCREEN_ORIENTATION_LOCKED
                                        } else {
                                            android.content.pm.ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                                        }
                                    }
                                )
                            )

                            // Bookmark
                            add(
                                ReaderFanRoundAction(
                                    id = "bookmark",
                                    icon = if (isBookmarked) Icons.Filled.Bookmark else Icons.Filled.BookmarkBorder,
                                    accessibilityLabel = if (isBookmarked) "Remove bookmark" else "Add bookmark",
                                    isEmphasized = isBookmarked,
                                    action = {
                                        val progress = state.liveProgress ?: return@ReaderFanRoundAction
                                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                        viewModel.toggleBookmarkAtProgress(
                                            progress = progress,
                                            locatorString = progress.locatorJson.orEmpty(),
                                            chapterTitle = progressLabel
                                        )
                                    }
                                )
                            )
                        }

                        ReaderFanMenu(
                            isOpen = fanMenuOpen,
                            onOpenChange = { fanMenuOpen = it },
                            pills = pills,
                            roundActions = roundActions
                        )
                    }

                    // Floating Position Card
                    AnimatedVisibility(
                        visible = chromeVisible,
                        enter = fadeIn() + slideInVertically { it },
                        exit = fadeOut() + slideOutVertically { it },
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .fillMaxWidth()
                    ) {
                        val downloadProgress by speechController.downloadProgress.collectAsState()
                        val showsMiniPlayer = speechStatus == SpeechStatus.PLAYING ||
                            speechStatus == SpeechStatus.PAUSED ||
                            (showTtsControls && speechStatus == SpeechStatus.MODEL_NOT_DOWNLOADED)

                        ReaderPositionCard(
                            page = page,
                            pageCount = pageCount,
                            chapterRemainingMinutes = minutesRemaining,
                            workLine = bottomLabel,
                            sliderValue = currentProgress,
                            sliderEnabled = publication.readingOrder.isNotEmpty(),
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
                            },
                            showsMiniPlayer = showsMiniPlayer,
                            speechStatus = speechStatus,
                            speechDownloadProgress = downloadProgress,
                            spokenText = spokenText,
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
                            onStopSpeech = {
                                speechController.stop()
                                showTtsControls = false
                            },
                            onSkipNext = { speechController.skipForward() },
                            onSkipPrevious = { speechController.skipBackward() },
                            onDownloadVoiceModel = { speechController.enqueueDownload() }
                        )
                    }

                    // Toast message
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
            }

            // Sheets & Dialogs
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
                    ReaderContentsSheet(
                        entries = tocEntries,
                        bookmarks = state.bookmarks,
                        highlights = state.highlights,
                        initialTab = tocInitialTab,
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
                val availableVoices by speechController.availableVoices.collectAsState()
                ModalBottomSheet(
                    onDismissRequest = { showDisplaySheet = false },
                    sheetState = sheetState
                ) {
                    ReaderDisplaySheet(
                        preferences = state.preferences,
                        availableVoices = availableVoices,
                        onFontSizeChange = viewModel::setFontSizePercent,
                        onThemeChange = viewModel::setColorTheme,
                        onScrollModeChange = viewModel::setScrollMode,
                        onTwoPageChange = viewModel::setTwoPage,
                        onBoldChange = viewModel::setBold,
                        onLetterSpacingChange = viewModel::setLetterSpacing,
                        onWordSpacingChange = viewModel::setWordSpacing,
                        onSpeechRateChange = viewModel::setSpeechRate,
                        onSpeechPitchChange = viewModel::setSpeechPitch,
                        onSpeechVoiceChange = viewModel::setSpeechVoiceIdentifier,
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
private fun ReaderDisplaySheet(
    preferences: ReaderPreferences,
    availableVoices: List<io.github.cidy02.kudos.reader.speech.TTSVoice> = emptyList(),
    onFontSizeChange: (Int) -> Unit,
    onThemeChange: (ReaderColorTheme) -> Unit,
    onScrollModeChange: (Boolean) -> Unit = {},
    onTwoPageChange: (Boolean) -> Unit = {},
    onBoldChange: (Boolean) -> Unit = {},
    onLetterSpacingChange: (Double) -> Unit = {},
    onWordSpacingChange: (Double) -> Unit = {},
    onSpeechRateChange: (Float) -> Unit = {},
    onSpeechPitchChange: (Float) -> Unit = {},
    onSpeechVoiceChange: (String?) -> Unit = {},
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
        if (availableVoices.isNotEmpty()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                availableVoices.forEach { voice ->
                    FilterChip(
                        selected = preferences.speechVoiceIdentifier == voice.id,
                        onClick = { onSpeechVoiceChange(voice.id) },
                        label = { Text(voice.name) }
                    )
                }
            }
        }
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
    var selectedColor by remember { mutableStateOf(ReadingAnnotationColor.YELLOW) }
    var note by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (state.asNote) "Add note" else "Highlight") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                if (state.selectedText.isNotBlank()) {
                    Text(
                        state.selectedText,
                        style = MaterialTheme.typography.bodyMedium,
                        maxLines = 4,
                        overflow = TextOverflow.Ellipsis
                    )
                }

                Text("Color", style = MaterialTheme.typography.labelLarge)
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    ReadingAnnotationColor.entries.forEach { swatch ->
                        val isSelected = selectedColor == swatch
                        Box(
                            modifier = Modifier
                                .size(32.dp)
                                .clip(CircleShape)
                                .background(swatch.color)
                                .then(
                                    if (isSelected) {
                                        Modifier.border(2.dp, MaterialTheme.colorScheme.primary, CircleShape)
                                    } else Modifier
                                )
                                .clickable { selectedColor = swatch },
                            contentAlignment = Alignment.Center
                        ) {
                            if (isSelected) {
                                Icon(
                                    imageVector = Icons.Filled.Check,
                                    contentDescription = swatch.displayName,
                                    tint = androidx.compose.ui.graphics.Color.Black,
                                    modifier = Modifier.size(16.dp)
                                )
                            }
                        }
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
            TextButton(onClick = { onConfirm(selectedColor.raw, note) }) {
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
