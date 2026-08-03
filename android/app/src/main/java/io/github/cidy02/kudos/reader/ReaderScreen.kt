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
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ChatBubbleOutline
import androidx.compose.material.icons.filled.TextFields
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import io.github.cidy02.kudos.reader.readium.ReadiumNavigatorController
import io.github.cidy02.kudos.reader.readium.ReadiumNavigatorHost
import io.github.cidy02.kudos.reader.readium.ReadiumOpenResult
import io.github.cidy02.kudos.reader.readium.ReadiumProgressAdapter
import io.github.cidy02.kudos.reader.readium.ReadiumPublicationOpener
import io.github.cidy02.kudos.reader.readium.ReadiumSettingsAdapter
import io.github.cidy02.kudos.reader.readium.ReadiumTocAdapter
import io.github.cidy02.kudos.reader.settings.ReaderColorTheme
import io.github.cidy02.kudos.reader.settings.ReaderPreferences
import io.github.cidy02.kudos.reader.settings.backgroundColor
import io.github.cidy02.kudos.reader.settings.ReaderSettingsMapper
import io.github.cidy02.kudos.ui.components.ReaderPageSkeleton
import kotlinx.coroutines.launch

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
    onOpenWorkDetail: (Long) -> Unit
) {
    val uiState by viewModel.state.collectAsState()
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
            is ReaderUiState.Reading -> ReaderReading(state, viewModel, onBack, onOpenComments, onOpenWorkDetail)
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
    onOpenWorkDetail: (Long) -> Unit
) {
    val context = LocalContext.current
    val opener = remember { ReadiumPublicationOpener(context) }
    val linkHandler = remember { ReaderLinkHandler() }
    val navigatorController = remember { ReadiumNavigatorController() }
    var attempt by remember { mutableIntStateOf(0) }
    // Start visible so first-open controls are discoverable; tap content to hide.
    var chromeVisible by remember { mutableStateOf(true) }
    var showTocSheet by remember { mutableStateOf(false) }
    var showDisplaySheet by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

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

            Box(modifier = Modifier.fillMaxSize()) {
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
                            is ReaderLinkDestination.WorkDetail -> onOpenWorkDetail(destination.workId)
                            is ReaderLinkDestination.External -> openExternal(context, destination.url)
                            is ReaderLinkDestination.TagSearch -> openExternal(context, url)
                            ReaderLinkDestination.Unhandled -> Unit
                        }
                    },
                    fontDeclarations = state.preferences.fontDeclarations
                )

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
                        commentsWorkId = state.endOfWork.workId.takeIf { state.endOfWork.commentsAvailable },
                        onBack = onBack,
                        onOpenComments = onOpenComments,
                        onMarkFinished = viewModel::markFinished,
                        onOpenToc = { showTocSheet = true },
                        onOpenDisplay = { showDisplaySheet = true }
                    )
                }

                AnimatedVisibility(
                    visible = chromeVisible && progressLabel.isNotEmpty(),
                    enter = fadeIn() + slideInVertically { it },
                    exit = fadeOut() + slideOutVertically { it },
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .fillMaxWidth()
                ) {
                    ReaderBottomProgress(label = progressLabel)
                }
            }

            if (showTocSheet) {
                val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)
                ModalBottomSheet(
                    onDismissRequest = { showTocSheet = false },
                    sheetState = sheetState
                ) {
                    ReaderTocSheet(
                        entries = tocEntries,
                        onSelect = { entry ->
                            val link = ReadiumTocAdapter.resolveLink(publication, entry)
                            if (link != null) {
                                navigatorController.go(link, animated = true)
                            }
                            scope.launch {
                                sheetState.hide()
                                showTocSheet = false
                            }
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
                        onThemeChange = viewModel::setColorTheme
                    )
                }
            }
        }
    }
}

@Composable
private fun ReaderTopBar(
    title: String,
    author: String,
    finished: Boolean,
    commentsWorkId: Long?,
    onBack: () -> Unit,
    onOpenComments: (Long) -> Unit,
    onMarkFinished: () -> Unit,
    onOpenToc: () -> Unit,
    onOpenDisplay: () -> Unit
) {
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
            Column(modifier = Modifier.weight(1f)) {
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
            IconButton(onClick = onOpenToc) {
                Icon(Icons.AutoMirrored.Filled.List, contentDescription = "Chapters")
            }
            IconButton(onClick = onOpenDisplay) {
                Icon(Icons.Filled.TextFields, contentDescription = "Display")
            }
            commentsWorkId?.let { workId ->
                IconButton(onClick = { onOpenComments(workId) }) {
                    Icon(Icons.Filled.ChatBubbleOutline, contentDescription = "Comments")
                }
            }
            IconButton(onClick = onMarkFinished, enabled = !finished) {
                Icon(
                    Icons.Filled.Check,
                    contentDescription = if (finished) "Finished" else "Mark finished"
                )
            }
        }
    }
}

@Composable
private fun ReaderBottomProgress(label: String) {
    Surface(
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.96f),
        tonalElevation = 3.dp,
        shadowElevation = 2.dp
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = 16.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically
        ) {
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
    onSelect: (ReaderTocEntry) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .padding(bottom = 16.dp)
    ) {
        Text(
            text = "Chapters",
            style = MaterialTheme.typography.titleLarge,
            modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp)
        )
        if (entries.isEmpty()) {
            Text(
                text = "No chapters available.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 24.dp, vertical = 16.dp)
            )
        } else {
            LazyColumn(
                contentPadding = PaddingValues(bottom = 8.dp)
            ) {
                items(entries, key = { "${it.depth}:${it.href}:${it.title}" }) { entry ->
                    Text(
                        text = entry.title,
                        style = MaterialTheme.typography.bodyLarge,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onSelect(entry) }
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
}

@Composable
private fun ReaderDisplaySheet(
    preferences: ReaderPreferences,
    onFontSizeChange: (Int) -> Unit,
    onThemeChange: (ReaderColorTheme) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .padding(horizontal = 24.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text(
            text = "Display",
            style = MaterialTheme.typography.titleLarge
        )

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

        Text(
            text = "Theme",
            style = MaterialTheme.typography.titleSmall
        )
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

        Spacer(modifier = Modifier.height(16.dp))
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
