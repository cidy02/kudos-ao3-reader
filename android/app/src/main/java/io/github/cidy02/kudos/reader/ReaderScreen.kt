package io.github.cidy02.kudos.reader

import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material3.LocalContentColor
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.settings.SettingsActionRow
import io.github.cidy02.kudos.settings.SettingsGroupLabel
import io.github.cidy02.kudos.settings.SettingsPanel
import io.github.cidy02.kudos.settings.SettingsSection
import io.github.cidy02.kudos.settings.SubjectSliderRow
import io.github.cidy02.kudos.settings.TextSizeSlider
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.SubjectSegmentedControl
import io.github.cidy02.kudos.ui.subject.SubjectToggle
import io.github.cidy02.kudos.ui.subject.ToolbarCircleButton
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
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.BookmarkBorder
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ScreenLockRotation
import androidx.compose.material.icons.filled.ScreenRotation
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Snackbar
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalView
import io.github.cidy02.kudos.ui.theme.setLightSystemBars
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
import io.github.cidy02.kudos.reader.settings.ReaderSpeechPreferences
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

    // The reader owns the whole window, as on iOS: its page colour runs under the status and
    // navigation bars, and everything inside keeps clear of them once. The shell used to pad
    // the reader, so the app's ground showed in both strips, and the controls, which pad
    // themselves, sat a bar's height too far in (iOS had and fixed the same double inset).
    // The bars' icons follow the page while the reader is open; the app's theme takes them
    // back when it closes.
    val view = LocalView.current
    val lightPage = backgroundColor.luminance() > 0.5f
    val lightApp by rememberUpdatedState(!LocalKudosTokens.current.theme.isDarkFamily)
    if (!view.isInEditMode) {
        SideEffect { view.setLightSystemBars(lightPage) }
        DisposableEffect(view) { onDispose { view.setLightSystemBars(lightApp) } }
    }

    Surface(
        modifier = Modifier.fillMaxSize().background(backgroundColor)
            .windowInsetsPadding(WindowInsets.systemBars.only(WindowInsetsSides.Vertical)),
        color = backgroundColor
    ) {
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
    val workActions = remember(context) { ReaderWorkActions(context) }
    // Keyed on what decides the answer, not on the whole work: its reading position changes
    // with every page, and both answers look at the disk.
    val canShare = remember(state.work.id, state.work.isDeleted, state.work.hasEpub, readerShareUrl(state.work)) {
        workActions.shareIntent(state.work) != null
    }
    val hasOriginal = remember(state.work.id, state.work.isDeleted) {
        workActions.originalIntent(state.work) != null
    }
    val haptics = LocalHapticFeedback.current
    val opener = remember { ReadiumPublicationOpener(context) }
    val linkHandler = remember { ReaderLinkHandler() }
    val navigatorController = remember { ReadiumNavigatorController() }
    var attempt by remember { mutableIntStateOf(0) }

    // Floating chrome visibility state
    // iOS ReadiumBook.chromeHidden starts true: the reader opens immersive; a tap shows the chrome.
    var chromeVisible by remember { mutableStateOf(false) }
    var dismissOffsetY by remember { mutableFloatStateOf(0f) }
    val keepScreenAwake by viewModel.keepScreenAwake.collectAsState()
    val readerView = androidx.compose.ui.platform.LocalView.current
    androidx.compose.runtime.DisposableEffect(keepScreenAwake) {
        readerView.keepScreenOn = keepScreenAwake
        onDispose { readerView.keepScreenOn = false }
    }
    var fanMenuOpen by remember { mutableStateOf(false) }

    // Sheets
    var showTocSheet by remember { mutableStateOf(false) }
    var tocInitialTab by remember { mutableIntStateOf(0) }
    var showDisplaySheet by remember { mutableStateOf(false) }
    var showSearchSheet by remember { mutableStateOf(false) }
    var annotateDialog by remember { mutableStateOf<AnnotateDialogState?>(null) }
    var showDeleteNoteConfirm by remember { mutableStateOf<ReadingAnnotation?>(null) }
    var isOrientationLocked by remember { mutableStateOf(false) }
    var showTtsControls by remember { mutableStateOf(false) }

    val scope = rememberCoroutineScope()

    val speechController = remember(context) { ReaderSpeechController(context) }
    val speechStatus by speechController.status.collectAsState()
    val spokenText by speechController.spokenText.collectAsState()
    val writeMessage by viewModel.writeMessage.collectAsState()
    val kudosWorking by viewModel.kudosWorking.collectAsState()

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
    LaunchedEffect(Unit) { viewModel.startReadingSession() }
    DisposableEffect(Unit) {
        onDispose { viewModel.close() }
    }
    LifecycleEventEffect(Lifecycle.Event.ON_STOP) { viewModel.pauseReadingSession() }
    LifecycleEventEffect(Lifecycle.Event.ON_START) { viewModel.resumeReadingSession() }

    val opening by produceState<ReadiumOpenResult?>(initialValue = null, state.epubPath, attempt) {
        value = null
        value = opener.open(state.epubPath.toFile())
    }

    CompositionLocalProvider(LocalKudosTokens provides tokens) {
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
            onDismissRequest = { showDeleteNoteConfirm = null },
            palette = tokens.scopePalette
        )
    }

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

            fun annotateSelection(asNote: Boolean, onComplete: () -> Unit = {}) {
                scope.launch {
                    try {
                        val selection = navigatorController.currentSelection() ?: return@launch
                        val locator = selection.locator
                        annotateDialog = AnnotateDialogState(
                            locatorJson = locator.toJSON().toString(),
                            selectedText = locator.text.highlight.orEmpty(),
                            progression = locator.locations.totalProgression
                                ?: locator.locations.progression ?: 0.0,
                            spineIndex = state.liveProgress?.spineIndex ?: 0,
                            asNote = asNote
                        )
                        navigatorController.clearSelection()
                    } finally {
                        // Finishing the native mode earlier can erase the selected range
                        // before Readium's JavaScript selection read returns.
                        onComplete()
                    }
                }
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
                        onHighlightSelection = { complete -> annotateSelection(false, complete) },
                        onAddNoteSelection = { complete -> annotateSelection(true, complete) },
                        onHighlightTap = viewModel::openHighlight,
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
                        val isBookmarked = readerIsBookmarked(state.bookmarks, state.liveProgress)

                        val pills = readerFanPills(
                            percent = state.liveProgress?.totalProgression?.let { (it * 100).roundToInt() },
                            searchable = ReaderSearch.isAvailable(publication),
                            ao3WorkId = ao3Id,
                            commentsChapter = sections.commentsChapter(state.liveProgress?.spineIndex),
                            onContents = { tab ->
                                tocInitialTab = tab
                                showTocSheet = true
                            },
                            onFind = { showSearchSheet = true },
                            onComments = onOpenComments,
                            onSettings = { showDisplaySheet = true }
                        )

                        // Round Actions
                        val roundActions = buildList {
                            if (canShare) {
                                add(ReaderFanRoundAction(
                                    id = "share",
                                    icon = Icons.Filled.Share,
                                    accessibilityLabel = "Share",
                                    action = { viewModel.shareWork(context) }
                                ))
                            }
                            readerKudosAction(
                                ao3WorkId = ao3Id,
                                given = state.work.hasGivenKudos,
                                working = kudosWorking,
                                onKudos = viewModel::giveKudos
                            )?.let { add(it) }

                            readerOriginalAction(hasOriginal) { viewModel.openOriginal(context) }
                                ?.let { add(it) }

                            // Read Aloud
                            val speechActive = speechStatus == SpeechStatus.PLAYING || speechStatus == SpeechStatus.PAUSED
                            add(
                                ReaderFanRoundAction(
                                    id = "readAloud",
                                    icon = Icons.AutoMirrored.Filled.VolumeUp,
                                    accessibilityLabel = if (speechActive) "Stop reading aloud" else "Read aloud",
                                    isEnabled = ReaderContentText.isAvailable(publication),
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
                                                if (paragraphs.isNotEmpty()) speechController.startReading(paragraphs)
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
                                    isEnabled = readerHasBookmarkPosition(state.liveProgress),
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
                val currentLocator = state.liveProgress?.locatorJson
                    ?.let(ReadiumNavigatorController::locatorFromJson) ?: initialLocator
                // Match the live href against sections, exactly as grouping does.
                // A position-list index can drift when a spine item has no positions.
                val currentSpineIndex = currentLocator?.let { locator ->
                    val key = ReaderSectionBuilder.hrefKey(locator.href.toString())
                    sections.firstOrNull { ReaderSectionBuilder.hrefKey(it.href) == key }?.spineIndex
                }
                ReaderSearchSheet(
                    publication = publication,
                    sections = sections,
                    currentSpineIndex = currentSpineIndex,
                    tokens = tokens,
                    onDismiss = { showSearchSheet = false },
                    onSelectHit = { hit -> navigatorController.go(hit.locator, animated = true) },
                    onBookmarkHit = { hit ->
                        val key = ReaderSectionBuilder.hrefKey(hit.locator.href.toString())
                        val section = sections.firstOrNull { ReaderSectionBuilder.hrefKey(it.href) == key }
                        val progress = ReadiumProgressAdapter.toReaderProgress(publication, hit.locator)
                            .copy(spineIndex = section?.spineIndex ?: 0)
                        viewModel.addBookmarkAtProgress(
                            progress = progress,
                            locatorString = progress.locatorJson.orEmpty(),
                            chapterTitle = section?.title ?: hit.chapterTitle
                        )
                    }
                )
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

            state.highlights.firstOrNull { it.id == state.editingAnnotationId }?.let { annotation ->
                ModalBottomSheet(
                    onDismissRequest = viewModel::closeNoteEditor,
                    sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
                    containerColor = tokens.background,
                    contentColor = tokens.primaryInk,
                    dragHandle = { BottomSheetDefaults.DragHandle(color = tokens.secondaryInk) }
                ) {
                    CompositionLocalProvider(LocalKudosTokens provides tokens) {
                        ReaderNoteEditor(
                            annotation = annotation,
                            onCancel = viewModel::closeNoteEditor,
                            onDone = { note ->
                                viewModel.updateNote(annotation.id, note)
                                viewModel.closeNoteEditor()
                            },
                            onColorChange = { color -> viewModel.recolorHighlight(annotation.id, color) },
                            onDelete = {
                                viewModel.closeNoteEditor()
                                showDeleteNoteConfirm = annotation
                            }
                        )
                    }
                }
            }

            if (showTocSheet) {
                val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)
                // The reader's theme, as its other sheets. Left to itself the sheet took
                // Material's own lavender and its rows the app's colours.
                ModalBottomSheet(
                    onDismissRequest = { showTocSheet = false },
                    sheetState = sheetState,
                    containerColor = tokens.background,
                    contentColor = tokens.primaryInk,
                    dragHandle = { BottomSheetDefaults.DragHandle(color = tokens.secondaryInk) }
                ) {
                    CompositionLocalProvider(LocalKudosTokens provides tokens) {
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
                                scope.launch {
                                    sheetState.hide()
                                    showTocSheet = false
                                    viewModel.openHighlight(annotation.id)
                                }
                            },
                            onDeleteAnnotation = { annotation ->
                                showDeleteNoteConfirm = annotation
                            }
                        )
                    }
                }
            }

            if (showDisplaySheet) {
                val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
                val availableVoices by speechController.availableVoices.collectAsState()
                // The sheet takes the reader's theme, as iOS's does, not the app's.
                ModalBottomSheet(
                    onDismissRequest = { showDisplaySheet = false },
                    sheetState = sheetState,
                    containerColor = tokens.background
                ) {
                    CompositionLocalProvider(
                        LocalKudosTokens provides tokens,
                        LocalContentColor provides tokens.primaryInk
                    ) {
                        ReaderDisplaySheet(
                            preferences = state.preferences,
                            keepScreenAwake = keepScreenAwake,
                            availableVoices = availableVoices,
                            onDone = { showDisplaySheet = false },
                            onFontSizeChange = viewModel::setFontSizePercent,
                            onThemeChange = viewModel::setColorTheme,
                            onScrollModeChange = viewModel::setScrollMode,
                            onTwoPageChange = viewModel::setTwoPage,
                            onKeepScreenAwakeChange = viewModel::setKeepScreenAwake,
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
}

/**
 * iOS `ReaderOptionsForm`, titled "Display & Themes": Appearance, Text Size, Reading, Read Aloud,
 * Font, in that order. Every control writes through the reader's view model to the same settings
 * the Settings pages write, and the open book follows at once.
 */
@Composable
private fun ReaderDisplaySheet(
    preferences: ReaderPreferences,
    keepScreenAwake: Boolean,
    availableVoices: List<io.github.cidy02.kudos.reader.speech.TTSVoice> = emptyList(),
    onDone: () -> Unit = {},
    onFontSizeChange: (Int) -> Unit,
    onThemeChange: (ReaderColorTheme) -> Unit,
    onScrollModeChange: (Boolean) -> Unit = {},
    onTwoPageChange: (Boolean) -> Unit = {},
    onKeepScreenAwakeChange: (Boolean) -> Unit = {},
    onBoldChange: (Boolean) -> Unit = {},
    onLetterSpacingChange: (Double) -> Unit = {},
    onWordSpacingChange: (Double) -> Unit = {},
    onSpeechRateChange: (Float) -> Unit = {},
    onSpeechPitchChange: (Float) -> Unit = {},
    onSpeechVoiceChange: (String?) -> Unit = {},
    onFontFamilyChange: (String?) -> Unit = {}
) {
    val tokens = LocalKudosTokens.current
    var showCustomize by remember { mutableStateOf(false) }
    val twoPage = !preferences.scroll && preferences.columnCount >= 2
    // iOS offers the two-page spread on iPad and Mac, never on a phone. It also shows here while
    // it is on, so a phone that has it on can turn it off.
    val wide = LocalConfiguration.current.screenWidthDp >= 600
    val currentFontId = preferences.fontFamily ?: "system"
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .navigationBarsPadding()
            .padding(bottom = 24.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = SubjectMetrics.accountGutter),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Display & Themes",
                color = tokens.primaryInk,
                fontSize = 17.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f)
            )
            ToolbarCircleButton(onClick = onDone, accessibilityName = "Done") {
                Icon(Icons.Filled.Check, contentDescription = null)
            }
        }

        SettingsGroupLabel("Appearance", Modifier.padding(top = 14.dp))
        SettingsPanel {
            SubjectSegmentedControl(
                options = ReaderColorTheme.entries,
                selected = preferences.theme,
                onSelect = onThemeChange,
                title = { if (it == ReaderColorTheme.Oled) "OLED" else it.name },
                contentDescription = "Theme",
                modifier = Modifier.padding(horizontal = 10.dp, vertical = 10.dp)
            )
            SubjectRowSeparator()
            SettingsActionRow(
                label = "Customize Theme…",
                icon = Icons.Outlined.Tune,
                onClick = { showCustomize = !showCustomize }
            )
            if (showCustomize) {
                SubjectRowSeparator()
                SubjectFormRow(
                    "Bold Text",
                    trailing = { SubjectToggle(checked = preferences.bold, onCheckedChange = onBoldChange) }
                )
                SubjectRowSeparator()
                SubjectSliderRow(
                    label = "Letter spacing",
                    value = preferences.letterSpacingEm.toFloat(),
                    valueRange = 0f..0.5f,
                    steps = 0,
                    formatValue = { "%.2f em".format(it) },
                    onValueChangeFinished = { onLetterSpacingChange(it.toDouble()) }
                )
                SubjectRowSeparator()
                SubjectSliderRow(
                    label = "Word spacing",
                    value = preferences.wordSpacingEm.toFloat(),
                    valueRange = 0f..1f,
                    steps = 0,
                    formatValue = { "%.2f em".format(it) },
                    onValueChangeFinished = { onWordSpacingChange(it.toDouble()) }
                )
            }
        }

        SettingsGroupLabel("Text Size", Modifier.padding(top = 22.dp))
        SettingsPanel {
            TextSizeSlider(
                value = preferences.fontSizePercent.toFloat(),
                valueRange = ReaderSettingsMapper.MIN_FONT_PERCENT.toFloat()..
                    ReaderSettingsMapper.MAX_FONT_PERCENT.toFloat(),
                steps = 19,
                unit = "%",
                onValueChange = { onFontSizeChange(it.toInt()) },
                onValueChangeFinished = { onFontSizeChange(it.toInt()) }
            )
        }

        SettingsSection(
            label = "Reading",
            footnote = if (wide) {
                "On a wide screen, Paged mode can show two pages side by side."
            } else {
                "Choose whether you turn pages or scroll while reading."
            }
        ) {
            SubjectSegmentedControl(
                options = listOf(true, false),
                selected = preferences.scroll,
                onSelect = onScrollModeChange,
                title = { scroll -> if (scroll) "Scrolled" else "Paged" },
                contentDescription = "Layout",
                modifier = Modifier.padding(horizontal = 10.dp, vertical = 10.dp)
            )
            if (wide || twoPage) {
                SubjectRowSeparator()
                SubjectFormRow(
                    "Two-page spread",
                    trailing = {
                        SubjectToggle(
                            checked = twoPage,
                            onCheckedChange = onTwoPageChange,
                            enabled = !preferences.scroll
                        )
                    }
                )
            }
            SubjectRowSeparator()
            SubjectFormRow(
                "Keep screen awake",
                trailing = { SubjectToggle(checked = keepScreenAwake, onCheckedChange = onKeepScreenAwakeChange) }
            )
        }

        SettingsGroupLabel("Read Aloud", Modifier.padding(top = 22.dp))
        SettingsPanel {
            if (availableVoices.isNotEmpty()) {
                Text(
                    text = "Voice",
                    color = tokens.primaryInk,
                    fontSize = 16.sp,
                    modifier = Modifier.padding(start = 13.dp, top = 10.dp, end = 13.dp)
                )
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState())
                        .padding(horizontal = 13.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    FilterChip(
                        selected = preferences.speechVoiceIdentifier == null,
                        onClick = { onSpeechVoiceChange(null) },
                        label = { Text("Automatic (best available)", lineHeight = 20.sp) }
                    )
                    availableVoices.forEach { voice ->
                        FilterChip(
                            selected = preferences.speechVoiceIdentifier == voice.id,
                            onClick = { onSpeechVoiceChange(voice.id) },
                            label = { Text(voice.name) }
                        )
                    }
                }
                SubjectRowSeparator()
            }
            SubjectSliderRow(
                label = "Speed",
                value = preferences.speechRate,
                valueRange = ReaderSpeechPreferences.RATE_RANGE,
                steps = ReaderSpeechPreferences.RATE_STEPS,
                formatValue = { "%.1f×".format(it) },
                onValueChangeFinished = onSpeechRateChange
            )
            SubjectRowSeparator()
            SubjectSliderRow(
                label = "Pitch",
                value = preferences.speechPitch,
                valueRange = 0.5f..2.0f,
                steps = 0,
                formatValue = { "%.1f".format(it) },
                onValueChangeFinished = onSpeechPitchChange
            )
        }

        SettingsGroupLabel("Font", Modifier.padding(top = 22.dp))
        SettingsPanel {
            ReaderFontCatalog.builtIns.forEachIndexed { index, option ->
                if (index > 0) SubjectRowSeparator()
                SubjectFormRow(
                    label = option.name,
                    onClick = { onFontFamilyChange(if (option.id == "system") null else option.id) },
                    trailing = {
                        if (currentFontId == option.id) {
                            Icon(Icons.Filled.Check, contentDescription = "Selected", tint = tokens.accent)
                        }
                    }
                )
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
