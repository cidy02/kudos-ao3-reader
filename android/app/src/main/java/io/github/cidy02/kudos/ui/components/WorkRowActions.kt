package io.github.cidy02.kudos.ui.components

import androidx.compose.foundation.layout.Box
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.List
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import io.github.cidy02.kudos.app.PrivacyGate
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.library.*
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.works.*
import io.github.cidy02.kudos.network.ao3.displayMessage
import io.github.cidy02.kudos.ui.subject.SwipeAction
import io.github.cidy02.kudos.ui.subject.SwipeActionRow
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/** Shared dependencies and one identity index for remote cards across pushed destinations. */
internal class WorkRowEnvironment(
    val repository: WorkRepository,
    val queues: ReadingQueueRepository,
    val downloads: DownloadQueue,
    val importer: WorkImporter,
    val loaded: Boolean,
    val index: WorkIdentityIndexInstance,
    val visibility: (SavedWork) -> LibraryPrivacyVisibility,
    val reveal: (String) -> Unit,
    val confirmBeforeDelete: Boolean,
    val hideMature: Boolean,
    val revealAll: Boolean,
    val toggleRevealAll: () -> Unit,
    val openDetails: (String) -> Unit,
    val openReader: (String) -> Unit,
    val openComments: (Long) -> Unit
)

internal val LocalWorkRowEnvironment = compositionLocalOf<WorkRowEnvironment?> { null }

@Composable
internal fun ProvideWorkRowActions(
    repository: WorkRepository,
    queues: ReadingQueueRepository,
    downloads: DownloadQueue,
    importer: WorkImporter,
    settingsRepository: SettingsRepository,
    privacyGate: PrivacyGate,
    openDetails: (String) -> Unit,
    openReader: (String) -> Unit,
    openComments: (Long) -> Unit,
    content: @Composable () -> Unit
) {
    val works by remember(repository) { repository.observeLibraryWorks() }.collectAsState(initial = null)
    val settings by settingsRepository.settings.collectAsState(initial = null)
    val currentSettings = settings ?: KudosSettings()
    val reveal by privacyGate.state.collectAsState()
    val activity = LocalContext.current as? androidx.fragment.app.FragmentActivity
    // Hide mode deliberately leaves a remote listing unmatched, as on iOS.
    val index = remember(works, currentSettings.privacy, reveal) {
        WorkIdentityIndexInstance(LibraryPrivacy.withoutHidden(works.orEmpty(), currentSettings.privacy, reveal))
    }
    CompositionLocalProvider(LocalWorkRowEnvironment provides WorkRowEnvironment(
        repository, queues, downloads, importer, works != null && settings != null, index,
        { LibraryPrivacy.visibility(it, currentSettings.privacy, reveal) },
        { privacyGate.reveal(it, activity) }, currentSettings.app.confirmBeforeDelete,
        currentSettings.privacy.hideMatureContent, reveal.revealAll, { privacyGate.toggleRevealAll(activity) },
        openDetails, openReader, openComments
    ), content = content)
}

@Composable
internal fun MatureWorkMenuItem(onDismiss: () -> Unit) {
    val environment = LocalWorkRowEnvironment.current ?: return
    if (environment.loaded && environment.hideMature) DropdownMenuItem(
        text = { Text(if (environment.revealAll) "Hide mature" else "Show mature") },
        onClick = { onDismiss(); environment.toggleRevealAll() })
}

@Composable
internal fun workRowActions(environment: WorkRowEnvironment, onSelect: (String) -> Unit = {}): LibraryCardActions =
    scopedWorkActions(
        environment.repository, environment.queues, environment.downloads, environment.importer,
        environment.confirmBeforeDelete, environment.openDetails, environment.openReader,
        environment.openComments, onSelect, environment.reveal, onChanged = {}
    )

/** A local match keeps the Library's privacy boundary, reader route and work menu. */
@Composable
internal fun LocalActionableWorkRow(
    work: SavedWork,
    environment: WorkRowEnvironment,
    expandAll: Boolean = false,
    ledger: Boolean = false,
    onSelect: ((String) -> Unit)? = null,
    footer: (@Composable () -> Unit)? = null
) {
    val actions = workRowActions(environment, onSelect ?: {})
    val obscured = environment.visibility(work) == LibraryPrivacyVisibility.Obscured
    var menu by remember(work.id) { mutableStateOf(false) }
    val row: @Composable () -> Unit = {
        SensitiveWorkRow(work = work, expandAll = expandAll, ledger = ledger, obscured = obscured,
            onReveal = { environment.reveal(work.id) }, onOpenWork = actions.onOpenReader,
            onLongClick = { if (!obscured) menu = true }, footer = footer)
    }
    Box {
        if (obscured) row() else SwipeActionRow(
            leadingSwipeActions(work, LibrarySectionKind.Downloaded, actions),
            trailing = listOf(SwipeAction("Delete", Icons.Outlined.Delete, MaterialTheme.colorScheme.error) {
                actions.onRemove(work.id)
            }), content = row)
        LibraryWorkMenu(expanded = menu && !obscured, onDismiss = { menu = false },
            work = work, actions = actions, showSelect = onSelect != null)
    }
}

/** The menu and picker state stay mounted when resolving a remote work creates a local match. */
@Composable
internal fun RemoteWorkActionFrame(
    summary: AO3WorkSummary,
    environment: WorkRowEnvironment,
    onOpenRemote: (AO3WorkSummary) -> Unit,
    content: @Composable (SavedWork?, Boolean, () -> Unit, () -> Unit) -> Unit
) {
    if (!environment.loaded) return
    val scope = rememberCoroutineScope()
    val local = environment.index.findMatch(summary)
    val obscured = local != null && environment.visibility(local) == LibraryPrivacyVisibility.Obscured
    val work = local ?: remember(summary) {
        WorkMetadataMerger(uuidFactory = { "remote_${summary.id}" }).merge(
            summary, null, null, markSaved = false, hasEpub = false)
    }
    val actions = workRowActions(environment)
    var menu by remember(summary.id) { mutableStateOf(false) }
    var busy by remember(summary.id) { mutableStateOf(false) }
    var error by remember(summary.id) { mutableStateOf<String?>(null) }
    fun run(action: suspend () -> Unit) {
        if (busy) return
        busy = true
        scope.launch {
            try { action() } catch (cancelled: CancellationException) { throw cancelled }
            catch (failure: Exception) { error = failure.message ?: "The action couldn't be completed." }
            finally { busy = false }
        }
    }
    fun resolve(action: (String) -> Unit) = run {
        when (val result = environment.importer.saveMetadataOnly(summary, markSaved = false, enrichMetadata = false)) {
            is WorkImportResult.Success -> action(result.work.id)
            is WorkImportResult.Failure -> error = result.error.displayMessage()
        }
    }
    val remoteActions = actions.copy(
        onOpenWork = { onOpenRemote(summary) },
        onOpenReader = { run {
            when (val result = environment.importer.prepareForReading(summary)) {
                is WorkImportResult.Success -> environment.openReader(result.work.id)
                is WorkImportResult.Failure -> error = result.error.displayMessage()
            }
        } },
        onToggleFinished = { resolve(actions.onToggleFinished) },
        onDownloadAction = { _, action ->
            if (local != null) actions.onDownloadAction(local.id, action) else run {
                val result = RemoteWorkBulkActions.saveToLibrary(listOf(summary), environment.importer)
                if (!result.allSucceeded) error = result.message
            }
        },
        onToggleSavedForLater = { _, _ -> resolve { actions.onToggleSavedForLater(it, false) } },
        onAddToQueue = { resolve(actions.onAddToQueue) },
        onAddToCollection = { resolve(actions.onAddToCollection) },
        isInSavedForLater = { local?.let { environment.queues.isInSavedForLater(it.id) } == true }
    )
    val effectiveActions = if (local != null) actions else remoteActions
    val click: () -> Unit = {
        if (!busy) {
            if (obscured) environment.reveal(work.id)
            else if (local != null) actions.onOpenReader(local.id)
            else onOpenRemote(summary)
        }
    }
    val row: @Composable () -> Unit = { content(local, obscured, click, { if (!obscured && !busy) menu = true }) }
    Box {
        if (obscured || busy) row() else {
            val download = leadingSwipeActions(work, LibrarySectionKind.Downloaded, effectiveActions)
                .filter { it.label == "Download" || it.label == "Remove Download" }
            val inLater = remember(work.id, work.isQueuedForLater) { mutableStateOf(false) }
            LaunchedEffect(work.id, work.isQueuedForLater) {
                inLater.value = local?.let { environment.queues.isInSavedForLater(it.id) } == true
            }
            SwipeActionRow(
                leading = download + SwipeAction(if (inLater.value) "Remove from Saved for Later" else "Save for Later",
                    Icons.Outlined.Schedule, MaterialTheme.colorScheme.primary) {
                    effectiveActions.onToggleSavedForLater(work.id, inLater.value)
                },
                trailing = buildList {
                    add(SwipeAction("Add to Queue", Icons.AutoMirrored.Outlined.List, MaterialTheme.colorScheme.tertiary) {
                        effectiveActions.onAddToQueue(work.id)
                    })
                    if (local != null) add(SwipeAction("Delete", Icons.Outlined.Delete, MaterialTheme.colorScheme.error) {
                        actions.onRemove(local.id)
                    })
                }, content = row)
        }
        LibraryWorkMenu(menu && !obscured && !busy, { menu = false }, work, effectiveActions,
            showSelect = false, remote = local == null, showDelete = local != null)
    }
    error?.let { message ->
        AlertDialog(onDismissRequest = { error = null }, title = { Text("Action Failed") },
            text = { Text(message) }, confirmButton = { TextButton(onClick = { error = null }) { Text("OK") } })
    }
}
