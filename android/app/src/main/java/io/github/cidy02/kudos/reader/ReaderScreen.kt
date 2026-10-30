package io.github.cidy02.kudos.reader

import io.github.cidy02.kudos.ui.theme.SheetSystemBars
import io.github.cidy02.kudos.ui.subject.LocalSettingsFormGround
import io.github.cidy02.kudos.app.DebugShotEffect
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
import org.readium.r2.shared.publication.services.positionsByReadingOrder
import org.readium.r2.shared.publication.Locator
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsIgnoringVisibility
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
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
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalView
import io.github.cidy02.kudos.ui.theme.setLightSystemBars
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import io.github.cidy02.kudos.core.model.ReaderFontCatalog
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
import io.github.cidy02.kudos.reader.speech.ReaderSpeechSeekSession
import io.github.cidy02.kudos.reader.speech.SpeechStatus
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
@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
fun ReaderScreen(
    viewModel: ReaderViewModel,
    onBack: () -> Unit,
    onOpenComments: (Long, Int?) -> Unit,
    /** Local library work id (not AO3 id) — opens Work Detail over the reader stack. */
    onOpenWorkDetail: (String) -> Unit,
    settingsRepository: io.github.cidy02.kudos.data.preferences.SettingsRepository? = null,
    /** An AO3 work, tag or author link tapped in the text: opened in the app, as iOS. */
    onOpenAo3Link: (ReaderLinkDestination) -> Unit = {},
    customFontRepository: io.github.cidy02.kudos.files.CustomFontRepository? = null
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
            // Keep the navigator's viewport and floating controls fixed when bars hide/reappear.
            .windowInsetsPadding(WindowInsets.systemBarsIgnoringVisibility.only(WindowInsetsSides.Vertical)),
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
            is ReaderUiState.Reading -> ReaderReading(
                state, viewModel, onBack, onOpenComments, onOpenWorkDetail, settings,
                onOpenAo3Link, settingsRepository, customFontRepository
            )
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
    settings: io.github.cidy02.kudos.core.model.KudosSettings,
    onOpenAo3Link: (ReaderLinkDestination) -> Unit,
    settingsRepository: io.github.cidy02.kudos.data.preferences.SettingsRepository?,
    customFontRepository: io.github.cidy02.kudos.files.CustomFontRepository?
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
    var staleConversion by remember(state.work.id) { mutableStateOf(false) }
    var rebuildingOriginal by remember { mutableStateOf(false) }
    LaunchedEffect(state.work.id, state.work.lastModifiedAt) {
        staleConversion = viewModel.readerWorkImporter?.conversionIsStale(state.work) == true
    }
    if (rebuildingOriginal) viewModel.readerWorkImporter?.let { importer ->
        io.github.cidy02.kudos.works.RebuildOriginalDialog(
            work = state.work, importer = importer,
            onRebuilt = { viewModel.reloadAfterRebuild() },
            onDismiss = { rebuildingOriginal = false }
        )
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
    var settingsSheet by remember { mutableStateOf<ReaderSettingsSheet?>(null) }
    var showSearchSheet by remember { mutableStateOf(false) }
    var confirmVoicePack by remember { mutableStateOf(false) }
    val annotationPreferences = remember(context) { context.getSharedPreferences("reader-annotations", Context.MODE_PRIVATE) }
    var lastHighlightColor by remember { mutableStateOf(ReadingAnnotationColor.fromRaw(
        annotationPreferences.getString("lastHighlightColor", ReadingAnnotationColor.YELLOW.raw).orEmpty()).raw) }
    fun rememberHighlightColor(color: String) {
        lastHighlightColor = color
        annotationPreferences.edit().putString("lastHighlightColor", color).apply()
    }
    var isOrientationLocked by remember { mutableStateOf(false) }
    var showTtsControls by remember { mutableStateOf(false) }
    val pronunciationStore = remember(context) { io.github.cidy02.kudos.reader.speech.KokoroPronunciationStore(context.applicationContext.filesDir) }
    var pronunciationTarget by remember { mutableStateOf<Pair<String, String>?>(null) }

    ReaderSystemBars(
        chromeVisible = chromeVisible,
        overlayVisible = showTocSheet || settingsSheet != null || showSearchSheet ||
            state.editingAnnotationId != null || confirmVoicePack || pronunciationTarget != null || rebuildingOriginal
    )

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
    val tokens = KudosTokens.of(readerTheme)

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

    LaunchedEffect(state.preferences, state.work.title, state.work.workFandoms, state.work.sourceUrl) {
        speechController.setPronunciationScope(state.work.workFandoms.firstOrNull(),
            io.github.cidy02.kudos.works.WorkIdentityIndex.ao3WorkId(state.work)?.toString())
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


    pronunciationTarget?.let { target ->
        CompositionLocalProvider(LocalKudosTokens provides tokens) {
            io.github.cidy02.kudos.settings.PronunciationEditor(target.first, target.second, pronunciationStore,
                onDismiss = { pronunciationTarget = null })
        }
    }

    if (confirmVoicePack) CompositionLocalProvider(LocalKudosTokens provides tokens) {
        AlertDialog(
            onDismissRequest = { confirmVoicePack = false }, title = { Text("Download Kokoro Voice Pack?") },
            text = { Text("This downloads about 45 MB. Read Aloud can use your device's voice while you wait.") },
            confirmButton = { TextButton(onClick = { confirmVoicePack = false; speechController.enqueueDownload() }) { Text("Download") } },
            dismissButton = { TextButton(onClick = { confirmVoicePack = false }) { Text("Cancel") } }
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
            DebugShotEffect("reader", ready = state.liveProgress != null) { name ->
                when (name) {
                    "readercontents" -> showTocSheet = true
                    "readerfind" -> showSearchSheet = true
                    "readerdisplay" -> settingsSheet = ReaderSettingsSheet.Display
                    "readerspeech" -> settingsSheet = ReaderSettingsSheet.Speech
                    "readernote" -> {
                        val progress = state.liveProgress ?: return@DebugShotEffect
                        val locator = ReadiumNavigatorController.locatorFromJson(progress.locatorJson.orEmpty())
                            ?: return@DebugShotEffect
                        val quote = when (sections.getOrNull(progress.spineIndex)?.kind) {
                            ReaderSectionKind.PREFACE -> "A lantern marks the start of this original practice journey."
                            ReaderSectionKind.AFTERWORD -> "The lantern is put away."
                            else -> "The keeper checks the clock and records the weather."
                        }
                        viewModel.annotateSelection(locator.copy(text = Locator.Text(highlight = quote)).toJSON().toString(),
                            quote, lastHighlightColor, progress.totalProgression ?: progress.scrollFraction,
                            progress.spineIndex, withNote = true)
                    }
                    else -> Unit
                }
            }

            val progressLabel = ReaderProgressDisplay.label(state.liveProgress, sections, state.work.chapters)
            var positions by remember(publication) { mutableStateOf<List<List<Locator>>>(emptyList()) }
            val speechSeek = remember(publication, speechController, navigatorController) {
                ReaderSpeechSeekSession(
                    onStart = speechController::beginSeeking,
                    navigate = { navigatorController.go(it, animated = false) },
                    reanchor = { locator ->
                        scope.launch {
                            speechController.endSeeking(ReaderContentText.source(
                                publication, locator, viewModel.readsAuthorNotes()
                            ))
                        }
                    }
                )
            }
            fun bookmarkChapter(entry: ReaderTocEntry, editNote: Boolean = false) {
                val locator = ReadiumTocAdapter.chapterStartLocator(positions, entry.href) ?: return
                val progress = ReadiumProgressAdapter.toReaderProgress(publication, locator)
                viewModel.addBookmarkAtProgress(progress, progress.locatorJson.orEmpty(), entry.title, editNote)
            }
            var scrubOriginLocator by remember(publication) { mutableStateOf<Locator?>(null) }
            var scrubViewport by remember(publication) { mutableStateOf<ReaderViewport?>(null) }
            var scrubValue by remember(publication) { mutableStateOf<Float?>(null) }
            var lastScrubPage by remember(publication) { mutableStateOf<Int?>(null) }
            val viewport = scrubViewport ?: state.viewport
            val pageCount = viewport?.pageCount ?: 0
            val page = scrubValue?.let { ReaderProgressDisplay.scrubPage(it, pageCount) } ?: viewport?.page ?: 0
            val currentProgress = scrubValue ?: if (pageCount > 0) ReaderProgressDisplay.sliderValue(page, pageCount) else 0f
            val skipChapter by androidx.compose.runtime.rememberUpdatedState<(Boolean) -> Unit> { forward ->
                val spine = state.viewport?.spineIndex ?: state.liveProgress?.spineIndex
                val target = spine?.let {
                    io.github.cidy02.kudos.reader.speech.ReaderSpeechSkip.target(
                        positions, it, state.viewport?.page ?: 1, forward
                    )
                }
                if (target != null && navigatorController.go(target, animated = false)) {
                    speechController.beginSeeking()
                    scope.launch {
                        speechController.endSeeking(ReaderContentText.source(
                            publication, target, viewModel.readsAuthorNotes()
                        ))
                    }
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                }
            }
            DisposableEffect(speechController, publication) {
                speechController.onSkipNext = { skipChapter(true) }
                speechController.onSkipPrevious = { skipChapter(false) }
                onDispose {
                    speechController.onSkipNext = {}
                    speechController.onSkipPrevious = {}
                }
            }
            val chapterPositions = positions.getOrNull(viewport?.spineIndex ?: -1)
            val chapterRemainingMinutes = chapterPositions?.takeIf { it.isNotEmpty() && pageCount > 0 }?.let {
                ReaderProgressDisplay.minutesForPositions(
                    ReaderProgressDisplay.chapterRemainingPositions(page, pageCount, it.size)
                )
            }
            val liveLocator = state.liveProgress?.locatorJson?.let(ReadiumNavigatorController::locatorFromJson)
            val totalPositions = positions.sumOf { it.size }
            LaunchedEffect(totalPositions, liveLocator?.locations?.position) {
                speechController.updateReadingPosition(totalPositions, liveLocator?.locations?.position)
            }
            val workRemainingMinutes = liveLocator?.locations?.position?.takeIf { positions.isNotEmpty() }?.let {
                ReaderProgressDisplay.minutesForPositions((positions.sumOf { chapter -> chapter.size } - it).coerceAtLeast(0))
            }
            val bottomLabel = if (workRemainingMinutes != null) {
                "$progressLabel · ${ReaderProgressDisplay.durationLabel(workRemainingMinutes)} left"
            } else progressLabel

            // Keep the released preview until the navigator settles, as iOS
            // does; clearing it on release snapped the thumb to an older page.
            LaunchedEffect(state.viewport) {
                if (scrubOriginLocator == null) {
                    scrubValue = null
                    lastScrubPage = null
                }
            }

            fun seekInChapter(value: Float, commit: Boolean = false) {
                if (pageCount <= 1) return
                val origin = scrubOriginLocator ?: liveLocator ?: return
                if (scrubOriginLocator == null) {
                    scrubOriginLocator = origin
                    scrubViewport = state.viewport
                    lastScrubPage = viewport?.page
                    viewModel.setScrubbing(true)
                }
                scrubValue = value
                val targetPage = ReaderProgressDisplay.scrubPage(value, pageCount)
                if (commit || targetPage != lastScrubPage) {
                    lastScrubPage = targetPage
                    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    val target = ReadiumProgressAdapter.chapterSeekTarget(
                        origin, ReaderProgressDisplay.sliderValue(targetPage, pageCount).toDouble()
                    )
                    scope.launch { navigatorController.scrubTo(target) }
                }
            }

            LaunchedEffect(publication) {
                viewModel.setSpineCount(publication.readingOrder.size)
                positions = publication.positionsByReadingOrder()
            }

            fun annotateSelection(asNote: Boolean, onComplete: () -> Unit = {}) {
                scope.launch {
                    try {
                        val selection = navigatorController.currentSelection() ?: return@launch
                        val locator = selection.locator
                        viewModel.annotateSelection(
                            locatorString = locator.toJSON().toString(),
                            selectedText = locator.text.highlight.orEmpty(),
                            color = lastHighlightColor,
                            progression = locator.locations.totalProgression
                                ?: locator.locations.progression ?: 0.0,
                            spineIndex = state.liveProgress?.spineIndex ?: 0,
                            withNote = asNote
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
                        onFixPronunciationSelection = { complete ->
                            scope.launch {
                                try {
                                    val selection = navigatorController.currentSelection() ?: return@launch
                                    val word = io.github.cidy02.kudos.reader.speech.pronunciationSelectionWord(
                                        selection.locator.text.highlight.orEmpty())
                                    if (word.isEmpty()) return@launch
                                    val existing = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                                        runCatching { pronunciationStore.load().global[word].orEmpty() }.getOrDefault("")
                                    }
                                    pronunciationTarget = word to existing
                                    navigatorController.clearSelection()
                                } finally { complete() }
                            }
                        },
                        onHighlightTap = viewModel::openHighlight,
                        onViewportChanged = viewModel::onViewport,
                        onContentTap = {
                            if (fanMenuOpen) {
                                fanMenuOpen = false
                            } else {
                                viewModel.dismissHighlightColorBar()
                                chromeVisible = !chromeVisible
                            }
                        },
                        onLocatorChanged = { locator ->
                            viewModel.onProgress(
                                ReadiumProgressAdapter.toReaderProgress(publication, locator)
                            )
                        },
                        onExternalLink = { url ->
                            // A work, tag or author on AO3 opens in the app (iOS's `openAO3Link`);
                            // they went to the phone's browser, which in the demo reached AO3.
                            when (val destination = linkHandler.classify(url)) {
                                is ReaderLinkDestination.External -> openExternal(context, destination.url)
                                ReaderLinkDestination.Unhandled -> Unit
                                else -> onOpenAo3Link(destination)
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
                            onSettings = { settingsSheet = ReaderSettingsSheet.Display },
                            onRebuild = if (staleConversion) ({ rebuildingOriginal = true }) else null
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
                                readerReadAloudAction(
                                    active = speechActive,
                                    enabled = ReaderContentText.isAvailable(publication),
                                    onSettings = { settingsSheet = it },
                                    onToggle = {
                                        if (speechActive) {
                                            speechController.stop()
                                            showTtsControls = false
                                        } else if (speechStatus == SpeechStatus.MODEL_NOT_DOWNLOADED) {
                                            showTtsControls = true
                                        } else {
                                            scope.launch {
                                                val from = state.liveProgress?.locatorJson
                                                    ?.let { ReadiumNavigatorController.locatorFromJson(it) }
                                                speechController.startReading(ReaderContentText.source(
                                                    publication, from, viewModel.readsAuthorNotes()
                                                ))
                                            }
                                        }
                                    }
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

                    // The colour bar clears the position card without a fixed-height offset (iOS).
                    Column(
                        Modifier.align(Alignment.BottomCenter).fillMaxWidth(),
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        state.highlights.firstOrNull { it.id == state.colorBarAnnotationId }?.let { annotation ->
                            ReaderHighlightColorBar(
                                selected = ReadingAnnotationColor.fromRaw(annotation.colorRaw),
                                onSelect = { color ->
                                    rememberHighlightColor(color)
                                    viewModel.recolorHighlight(annotation.id, color)
                                    viewModel.dismissHighlightColorBar()
                                },
                                onDismiss = viewModel::dismissHighlightColorBar,
                                modifier = Modifier.padding(bottom = if (chromeVisible) 0.dp else 8.dp)
                            )
                        }

                        val downloadProgress by speechController.downloadProgress.collectAsState()
                        val showsMiniPlayer = speechStatus == SpeechStatus.PLAYING ||
                            speechStatus == SpeechStatus.PAUSED ||
                            (showTtsControls && speechStatus == SpeechStatus.MODEL_NOT_DOWNLOADED)
                        // Chrome down + speech: the same transport in its own surface, without progress.
                        AnimatedVisibility(
                            visible = chromeVisible || showsMiniPlayer,
                            enter = fadeIn() + slideInVertically { it },
                            exit = fadeOut() + slideOutVertically { it },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            ReaderPositionCard(
                                page = page,
                                pageCount = pageCount,
                                chapterRemainingMinutes = chapterRemainingMinutes,
                                workLine = bottomLabel,
                                sliderValue = currentProgress,
                                sliderEnabled = pageCount > 1 && liveLocator != null,
                                onSeek = { seekInChapter(it) },
                                onSeekEnd = {
                                    scrubValue?.let { seekInChapter(it, commit = true) }
                                    scrubOriginLocator = null
                                    scrubViewport = null
                                    viewModel.setScrubbing(false)
                                },
                                showsMiniPlayer = showsMiniPlayer,
                                showsPosition = chromeVisible,
                                onPlayerBackgroundTap = if (chromeVisible) null else ({ chromeVisible = true }),
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
                                            speechController.startReading(ReaderContentText.source(
                                                publication, from, viewModel.readsAuthorNotes()
                                            ).withFallback(buildList {
                                                if (state.work.title.isNotBlank()) add(state.work.title)
                                                tocEntries.forEach { if (it.title.isNotBlank()) add(it.title) }
                                            }.ifEmpty { listOf(state.work.title.ifBlank { "No text available." }) }))
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
                                onSeekSpeech = { delta ->
                                    if (speechSeek.step(positions, page, pageCount, delta)) {
                                        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                    }
                                },
                                onSpeechSeekStart = {
                                    speechSeek.begin(navigatorController.currentLocator ?: liveLocator ?: initialLocator)
                                },
                                onSpeechSeekEnd = speechSeek::end,
                                onDownloadVoiceModel = { confirmVoicePack = true }
                            )
                        }

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
                        val locator = ReadiumProgressAdapter.resolvedPositionLocator(hit.locator, positions.flatten())
                        val key = ReaderSectionBuilder.hrefKey(locator.href.toString())
                        val section = sections.firstOrNull { ReaderSectionBuilder.hrefKey(it.href) == key }
                        val progress = ReadiumProgressAdapter.toReaderProgress(publication, locator)
                            .copy(spineIndex = section?.spineIndex ?: 0)
                        viewModel.addBookmarkAtProgress(
                            progress = progress,
                            locatorString = progress.locatorJson.orEmpty(),
                            chapterTitle = section?.title ?: hit.chapterTitle
                        )
                    }
                )
            }

            (state.highlights + state.bookmarks).firstOrNull { it.id == state.editingAnnotationId }?.let { annotation ->
                // A swatch writes straight to the highlight so the page shows it at once.
                // Cancel takes that back (audit A12-6). Dismissing the sheet keeps the colour
                // and a typed note, as iOS's swipe does (3dz): only Cancel throws work away.
                val colourOnOpen = remember(annotation.id) { annotation.colorRaw }
                val cancelNote = {
                    if (annotation.colorRaw != colourOnOpen) viewModel.recolorHighlight(annotation.id, colourOnOpen)
                    viewModel.closeNoteEditor()
                }
                ModalBottomSheet(
                    onDismissRequest = { viewModel.closeNoteEditor() },
                    sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
                    containerColor = tokens.background,
                    contentColor = tokens.primaryInk,
                    dragHandle = { BottomSheetDefaults.DragHandle(color = tokens.secondaryInk) }
                ) {
                    SheetSystemBars(tokens)
                    CompositionLocalProvider(LocalKudosTokens provides tokens) {
                        ReaderNoteEditor(
                            annotation = annotation,
                            onCancel = cancelNote,
                            onDone = { note ->
                                viewModel.updateNote(annotation.id, note)
                                viewModel.closeNoteEditor()
                            },
                            onColorChange = { color -> rememberHighlightColor(color); viewModel.recolorHighlight(annotation.id, color) },
                            onKeep = { note -> viewModel.updateNote(annotation.id, note) },
                            onDelete = {
                                viewModel.closeNoteEditor()
                                viewModel.deleteAnnotation(annotation.id)
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
                    SheetSystemBars(tokens)
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
                                viewModel.deleteAnnotation(annotation.id)
                            },
                            onBookmarkEntry = { bookmarkChapter(it) },
                            onAddNoteToEntry = { entry ->
                                scope.launch {
                                    sheetState.hide()
                                    showTocSheet = false
                                    bookmarkChapter(entry, editNote = true)
                                }
                            },
                            onDone = {
                                scope.launch {
                                    sheetState.hide()
                                    showTocSheet = false
                                }
                            },
                            startPercent = { entry ->
                                ReadiumTocAdapter.chapterStartLocator(positions, entry.href)
                                    ?.locations?.totalProgression?.let { (it * 100).roundToInt() }
                            }
                        )
                    }
                }
            }

            if (settingsSheet == ReaderSettingsSheet.Speech) {
                CompositionLocalProvider(LocalKudosTokens provides tokens) {
                    ReaderSpeechSettingsSheet(
                        repository = settingsRepository ?: viewModel.readerSettingsRepository,
                        onDismiss = { speech ->
                            speechController.configure(speech.applyTo(state.preferences), state.work.title)
                            settingsSheet = null
                        }
                    )
                }
            }

            if (settingsSheet == ReaderSettingsSheet.Display) {
                val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
                // The sheet takes the reader's theme, as iOS's does, not the app's.
                ModalBottomSheet(
                    onDismissRequest = { settingsSheet = null },
                    sheetState = sheetState,
                    containerColor = tokens.background
                ) {
                    SheetSystemBars(tokens)
                    CompositionLocalProvider(
                        LocalKudosTokens provides tokens,
                        LocalContentColor provides tokens.primaryInk
                    ) {
                        ReaderDisplaySheet(
                            preferences = state.preferences,
                            settingsRepository = settingsRepository ?: viewModel.readerSettingsRepository,
                            customFontRepository = customFontRepository,
                            keepScreenAwake = keepScreenAwake,
                            onDone = { settingsSheet = null },
                            onFontSizeChange = viewModel::setFontSizePercent,
                            onThemeChange = viewModel::setColorTheme,
                            onScrollModeChange = viewModel::setScrollMode,
                            onTwoPageChange = viewModel::setTwoPage,
                            onKeepScreenAwakeChange = viewModel::setKeepScreenAwake,
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
internal fun ReaderDisplaySheet(
    preferences: ReaderPreferences,
    settingsRepository: io.github.cidy02.kudos.data.preferences.SettingsRepository,
    customFontRepository: io.github.cidy02.kudos.files.CustomFontRepository? = null,
    keepScreenAwake: Boolean,
    onDone: () -> Unit = {},
    onFontSizeChange: (Int) -> Unit,
    onThemeChange: (ReaderColorTheme) -> Unit,
    onScrollModeChange: (Boolean) -> Unit = {},
    onTwoPageChange: (Boolean) -> Unit = {},
    onKeepScreenAwakeChange: (Boolean) -> Unit = {},
    onFontFamilyChange: (String?) -> Unit = {},
    listeningContent: @Composable (@Composable (@Composable () -> Unit) -> Unit) -> Unit = { frame ->
        io.github.cidy02.kudos.settings.SettingsListeningContent(settingsRepository, frame)
    }
) {
    var showCustomizeTheme by remember { mutableStateOf(false) }
    if (showCustomizeTheme) {
        CustomizeThemeSheet(settingsRepository, customFontRepository, onDismiss = { showCustomizeTheme = false })
    }
    val tokens = LocalKudosTokens.current
    val controlInk = tokens.accentInk
    val twoPage = !preferences.scroll && preferences.columnCount >= 2
    // iOS offers the two-page spread on iPad and Mac, never on a phone. It also shows here while
    // it is on, so a phone that has it on can turn it off.
    val wide = LocalConfiguration.current.screenWidthDp >= 600
    val currentFontId = preferences.fontFamily ?: "system"
    CompositionLocalProvider(LocalSettingsFormGround provides (tokens.theme != ReaderTheme.Light)) {
    listeningContent { speechContent ->
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
                    // Use the actual reader tint, including Sepia's fixed warm brown.
                    Icon(Icons.Filled.Check, contentDescription = null, tint = controlInk)
                }
            }

            SettingsGroupLabel("Appearance", Modifier.padding(top = 14.dp))
            SettingsPanel {
                CompositionLocalProvider(LocalSettingsFormGround provides true) {
                    SubjectSegmentedControl(
                        options = ReaderColorTheme.entries,
                        selected = preferences.theme,
                        onSelect = onThemeChange,
                        title = { if (it == ReaderColorTheme.Oled) "OLED" else it.name },
                        contentDescription = "Theme",
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 10.dp)
                    )
                }
                SubjectRowSeparator()
                SettingsActionRow(
                    label = "Customize Theme…",
                    tint = controlInk,
                    icon = Icons.Outlined.Tune,
                    onClick = { showCustomizeTheme = true }
                )
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
                CompositionLocalProvider(LocalSettingsFormGround provides true) {
                    SubjectSegmentedControl(
                        options = listOf(true, false),
                        selected = preferences.scroll,
                        onSelect = onScrollModeChange,
                        title = { scroll -> if (scroll) "Scrolled" else "Paged" },
                        contentDescription = "Layout",
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 10.dp)
                    )
                }
                if (wide || twoPage) {
                    SubjectRowSeparator()
                    SubjectFormRow(
                        "Two-page spread",
                        trailing = {
                            SubjectToggle(
                                checked = twoPage,
                                onCheckedChange = onTwoPageChange,
                                enabled = !preferences.scroll, contentDescription = "Two-page spread"
                            )
                        }
                    )
                }
                SubjectRowSeparator()
                SubjectFormRow(
                    "Keep screen awake",
                    trailing = { SubjectToggle(checked = keepScreenAwake, onCheckedChange = onKeepScreenAwakeChange, contentDescription = "Keep screen awake") }
                )
            }

            speechContent()

            if (customFontRepository != null) {
                io.github.cidy02.kudos.settings.ReaderFontSection(currentFontId, customFontRepository) { id ->
                    onFontFamilyChange(if (id == "system") null else id)
                }
            } else {
                SettingsGroupLabel("Font", Modifier.padding(top = 22.dp))
                SettingsPanel {
                    ReaderFontCatalog.builtIns.forEachIndexed { index, option ->
                        if (index > 0) SubjectRowSeparator()
                        SubjectFormRow(
                            label = option.name,
                            onClick = { onFontFamilyChange(if (option.id == "system") null else option.id) },
                            trailing = {
                                if (currentFontId == option.id) {
                                    Icon(Icons.Filled.Check, contentDescription = "Selected", tint = tokens.accentInk)
                                }
                            }
                        )
                    }
                }
            }
        }
    }
    }
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
