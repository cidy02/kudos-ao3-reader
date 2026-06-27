package io.github.cidy02.kudos.reader

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import io.github.cidy02.kudos.reader.readium.ReadiumNavigatorHost
import io.github.cidy02.kudos.reader.readium.ReadiumOpenResult
import io.github.cidy02.kudos.reader.readium.ReadiumProgressAdapter
import io.github.cidy02.kudos.reader.readium.ReadiumPublicationOpener
import io.github.cidy02.kudos.reader.readium.ReadiumSettingsAdapter

/**
 * Real reader entry point. Resolves the work (via [ReaderViewModel]/repository),
 * opens the EPUB with Readium, restores progress, hosts the navigator, and
 * persists progress on close. Shows loading/error states; never crashes on a
 * missing/corrupt EPUB.
 */
@Composable
fun ReaderScreen(
    viewModel: ReaderViewModel,
    onBack: () -> Unit,
    onOpenWorkDetail: (Long) -> Unit
) {
    val uiState by viewModel.state.collectAsState()
    Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        when (val state = uiState) {
            ReaderUiState.Loading -> ReaderMessage("Opening…", showSpinner = true)
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
            is ReaderUiState.Reading -> ReaderReading(state, viewModel, onBack, onOpenWorkDetail)
        }
    }
}

@Composable
private fun ReaderReading(
    state: ReaderUiState.Reading,
    viewModel: ReaderViewModel,
    onBack: () -> Unit,
    onOpenWorkDetail: (Long) -> Unit
) {
    val context = LocalContext.current
    val opener = remember { ReadiumPublicationOpener(context) }
    val linkHandler = remember { ReaderLinkHandler() }
    var attempt by remember { mutableIntStateOf(0) }

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
        null -> ReaderMessage("Opening “${state.work.title}”…", showSpinner = true)
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
            Column(modifier = Modifier.fillMaxSize()) {
                ReaderTopBar(
                    title = state.work.title,
                    finished = state.finished,
                    onBack = onBack,
                    onMarkFinished = viewModel::markFinished
                )
                ReadiumNavigatorHost(
                    modifier = Modifier.fillMaxSize(),
                    publication = publication,
                    initialLocator = initialLocator,
                    preferences = epubPreferences,
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
                    }
                )
            }
        }
    }
}

@Composable
private fun ReaderTopBar(
    title: String,
    finished: Boolean,
    onBack: () -> Unit,
    onMarkFinished: () -> Unit
) {
    Surface(color = MaterialTheme.colorScheme.surface) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            TextButton(onClick = onBack) { Text("Back") }
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f)
            )
            TextButton(onClick = onMarkFinished, enabled = !finished) {
                Text(if (finished) "Finished" else "Mark Finished")
            }
        }
    }
}

@Composable
private fun ReaderMessage(message: String, showSpinner: Boolean = false) {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            if (showSpinner) CircularProgressIndicator()
            Text(text = message, style = MaterialTheme.typography.bodyLarge)
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
