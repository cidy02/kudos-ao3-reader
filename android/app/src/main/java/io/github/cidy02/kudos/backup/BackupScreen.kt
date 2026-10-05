package io.github.cidy02.kudos.backup

import android.net.Uri
import android.os.Environment
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.FileDownload
import androidx.compose.material.icons.outlined.FileUpload
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.settings.SettingsActionRow
import io.github.cidy02.kudos.settings.SettingsFootnote
import io.github.cidy02.kudos.settings.SettingsPage
import io.github.cidy02.kudos.settings.SettingsSection
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.SubjectToggle
import io.github.cidy02.kudos.works.WorkRepository
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardOpenOption
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun BackupScreen(
    repository: BackupRepository,
    settingsRepository: SettingsRepository,
    database: KudosDatabase,
    workRepository: WorkRepository
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    var statusMessage by remember { mutableStateOf<String?>(null) }
    var statusIsError by remember { mutableStateOf(false) }
    var pendingImport by remember { mutableStateOf<PendingBackupImport?>(null) }

    val exportLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.CreateDocument("application/zip")
    ) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            busy = true
            statusMessage = null
            try {
                val bytes = repository.exportV2ZipBytes()
                withContext(Dispatchers.IO) {
                    context.contentResolver.openOutputStream(uri)?.use { out ->
                        out.write(bytes)
                        out.flush()
                    } ?: error("Could not open the chosen location for writing.")
                }
                statusIsError = false
                statusMessage =
                    "Exported ${bytes.size / 1024} KB as a v${BackupVersion.CURRENT} .kudosbackup ZIP."
            } catch (error: Exception) {
                statusIsError = true
                statusMessage = userFacingError("Export failed", error)
            } finally {
                busy = false
            }
        }
    }

    val importLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            busy = true
            statusMessage = null
            try {
                val bytes = withContext(Dispatchers.IO) {
                    context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                        ?: error("Could not read the selected file.")
                }
                val pack = withContext(Dispatchers.IO) { BackupImporter.importV2Zip(bytes) }
                val preview = repository.previewImport(pack)
                val syncEnabled = settingsRepository.settings.first().sync.isEnabled
                pendingImport = PendingBackupImport(
                    bytes = bytes,
                    preview = preview,
                    manifest = pack.manifest,
                    syncEnabled = syncEnabled
                )
            } catch (error: Exception) {
                statusIsError = true
                statusMessage = userFacingError("Import failed", error)
            } finally {
                busy = false
            }
        }
    }

    fun clearPendingImport() {
        pendingImport = null
    }

    fun runImport(mode: BackupImportMode, pauseSync: Boolean) {
        val pending = pendingImport
        clearPendingImport()
        if (pending == null) return
        scope.launch {
            busy = true
            statusMessage = null
            try {
                var safetyName: String? = null
                if (mode == BackupImportMode.REPLACE_LIBRARY) {
                    val docs = context.getExternalFilesDir(Environment.DIRECTORY_DOCUMENTS)
                        ?: File(context.filesDir, "Documents").also { it.mkdirs() }
                    docs.mkdirs()
                    val file = File(docs, repository.suggestedSafetyBackupFileName())
                    val safetyBytes = repository.exportV2ZipBytes()
                    withContext(Dispatchers.IO) {
                        // Never overwrite the only copy that can undo an earlier Replace.
                        Files.write(
                            file.toPath(), safetyBytes,
                            StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE
                        )
                    }
                    safetyName = file.name
                    if (pauseSync && pending.syncEnabled) {
                        settingsRepository.updateSyncIsEnabled(false)
                    }
                }
                val summary = repository.importV2ZipBytes(pending.bytes, mode)
                statusIsError = false
                statusMessage = buildString {
                    append(summary.toUserMessage())
                    if (safetyName != null) {
                        append(" Current library saved as ")
                        append(safetyName)
                        append(" first.")
                    }
                    if (pauseSync && pending.syncEnabled) {
                        append(" Sync paused on this device.")
                    }
                }
            } catch (error: Exception) {
                statusIsError = true
                statusMessage = userFacingError("Import failed", error)
            } finally {
                busy = false
            }
        }
    }

    val tokens = LocalKudosTokens.current
    SettingsPage(title = "Backup") {
        item {
            SettingsSection(
                footnote = "Your backup file includes your Library, Reading Queues, downloaded copies, " +
                    "User Tags, saved links, custom fonts, imported original files, and app " +
                    "settings. Importing adds anything you don't have without removing what is " +
                    "already here. Your AO3 sign-in and password are never included."
            ) {
                SettingsActionRow(
                    label = "Export Backup…",
                    icon = Icons.Outlined.FileUpload,
                    enabled = !busy,
                    onClick = {
                        exportLauncher.launch(repository.suggestedExportFileName())
                    }
                )
                SubjectRowSeparator()
                SettingsActionRow(
                    label = "Import Backup…",
                    icon = Icons.Outlined.FileDownload,
                    enabled = !busy,
                    onClick = {
                        importLauncher.launch(
                            arrayOf(
                                "application/zip",
                                "application/octet-stream",
                                "*/*"
                            )
                        )
                    }
                )
                if (busy) {
                    LinearProgressIndicator(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 13.dp),
                        color = tokens.accent,
                        trackColor = tokens.glassFill(0.12)
                    )
                    Text(
                        text = "Working…",
                        color = tokens.secondaryInk,
                        fontSize = 13.sp,
                        modifier = Modifier.padding(horizontal = 13.dp, vertical = 8.dp)
                    )
                }
                statusMessage?.let { message ->
                    Text(
                        text = message,
                        color = if (statusIsError) MaterialTheme.colorScheme.error else tokens.secondaryInk,
                        fontSize = 13.sp,
                        modifier = Modifier.padding(horizontal = 13.dp, vertical = 12.dp)
                    )
                }
            }
            // Keep Android's existing compatibility and trust-boundary warnings visible.
            SettingsFootnote(
                "Export writes ZIP packages at manifest v${BackupVersion.CURRENT} (Apple-compatible).\n" +
                    "Import accepts Apple/Android .kudosbackup ZIP versions ${BackupVersion.APPLE_V1}–${BackupVersion.CURRENT}.\n" +
                    "Merge adds works that are not already here. Replace Library makes this device match the file.\n" +
                    "Unsigned deletion claims in a backup or sync folder are ignored. Signed tombstones apply only from devices you already trust."
            )
            SettingsFootnote(
                "AO3 passwords are never stored.\n" +
                    "AO3 cookies, CSRF tokens, and session files are excluded from backups.\n" +
                    "Backup import treats ZIP paths and filenames as untrusted input."
            )
        }
        item {
            PairingCard(
                settingsRepository = settingsRepository,
                database = database,
                workRepository = workRepository
            )
        }
    }

    pendingImport?.let { pending ->
        ImportBackupDialog(
            pending = pending,
            onDismiss = { clearPendingImport() },
            onMerge = { runImport(BackupImportMode.MERGE, pauseSync = false) },
            onReplace = { pauseSync ->
                runImport(BackupImportMode.REPLACE_LIBRARY, pauseSync = pauseSync)
            }
        )
    }
}

private data class PendingBackupImport(
    val bytes: ByteArray,
    val preview: BackupImportPreview,
    val manifest: KudosBackupManifest,
    val syncEnabled: Boolean
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ImportBackupDialog(
    pending: PendingBackupImport,
    onDismiss: () -> Unit,
    onMerge: () -> Unit,
    onReplace: (pauseSync: Boolean) -> Unit
) {
    val preview = pending.preview
    val tokens = LocalKudosTokens.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var reviewingReplace by remember { mutableStateOf(false) }
    var acknowledgeRemoval by remember { mutableStateOf(false) }
    var pauseSync by remember { mutableStateOf(true) }
    var replaceArmed by remember { mutableStateOf(false) }
    // Each review/re-check gets its own full delay; leaving review cancels the wait.
    LaunchedEffect(reviewingReplace, acknowledgeRemoval, preview.willRemove) {
        replaceArmed = false
        if (reviewingReplace && acknowledgeRemoval) {
            delay(1_500)
            replaceArmed = true
        }
    }
    val replaceEnabled = replaceArmed && acknowledgeRemoval

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = tokens.background,
        contentColor = tokens.primaryInk
    ) {
        Column(Modifier.fillMaxHeight(0.9f)) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = SubjectMetrics.accountGutter),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = if (reviewingReplace) "Replace Library" else "Import Backup",
                    color = tokens.primaryInk,
                    fontSize = 20.sp,
                    modifier = Modifier.weight(1f)
                )
                if (reviewingReplace) {
                    TextButton(
                        onClick = {
                            reviewingReplace = false
                            acknowledgeRemoval = false
                        },
                        colors = ButtonDefaults.textButtonColors(contentColor = tokens.accent)
                    ) { Text("Back") }
                }
                TextButton(
                    onClick = onDismiss,
                    colors = ButtonDefaults.textButtonColors(contentColor = tokens.accent)
                ) { Text("Cancel") }
            }
            Column(
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .padding(bottom = 24.dp)
            ) {
                SettingsSection(label = "This backup", footnote = null) {
                    if (reviewingReplace) {
                        SubjectFormRow("Works in your library", value = "${preview.localWorkCount}")
                        SubjectRowSeparator()
                        SubjectFormRow("Works in this backup", value = "${preview.fileWorkCount}")
                        SubjectRowSeparator()
                        SubjectFormRow("Will be added", value = "${preview.willAdd}")
                        SubjectRowSeparator()
                        SubjectFormRow("Will be removed", value = "${preview.willRemove}")
                        SubjectRowSeparator()
                        SubjectFormRow("In both", value = "${preview.inBoth}")
                    } else {
                        SubjectFormRow("Library records", value = "${pending.manifest.works.size}")
                        SubjectRowSeparator()
                        SubjectFormRow("Saved links", value = "${pending.manifest.bookmarks.size}")
                        SubjectRowSeparator()
                        SubjectFormRow("Reading queues", value = "${pending.manifest.readingQueues.size}")
                        SubjectRowSeparator()
                        SubjectFormRow("Collections", value = "${pending.manifest.collections.size}")
                        SubjectRowSeparator()
                        SubjectFormRow("Custom fonts", value = "${pending.manifest.fonts.size}")
                    }
                }
                // Preserve the warning in the choice step too, before either import action.
                if (!preview.isLibraryEmpty && preview.isMuchSmallerThanLibrary) {
                    Text(
                        text = "This backup has far fewer works than your current library.",
                        color = MaterialTheme.colorScheme.tertiary,
                        fontSize = 13.sp,
                        lineHeight = 18.sp,
                        modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 16.dp)
                    )
                }
                if (reviewingReplace) {
                    SettingsSection(
                        footnote = "Replace only changes this device. Removed works go to Recently Deleted and " +
                            "can return through Merge; saved links, saved searches, reading history, stars, " +
                            "and fandom visits are deleted completely and remembered as deleted, so Merge " +
                            "will not bring them back. To restore everything, import the saved copy and " +
                            "choose Replace."
                    ) {
                        // iOS asks for acknowledgement even when the removal count is zero.
                        SubjectFormRow(
                            label = "Remove ${preview.willRemove} works that are not in this backup",
                            trailing = {
                                SubjectToggle(
                                    checked = acknowledgeRemoval,
                                    onCheckedChange = { acknowledgeRemoval = it },
                                    contentDescription = "Remove ${preview.willRemove} works that are not in this backup"
                                )
                            }
                        )
                        if (pending.syncEnabled) {
                            SubjectRowSeparator()
                            SubjectFormRow(
                                label = "Pause Library Sync on this device",
                                trailing = {
                                    SubjectToggle(
                                        checked = pauseSync,
                                        onCheckedChange = { pauseSync = it },
                                        contentDescription = "Pause Library Sync on this device"
                                    )
                                }
                            )
                            Text(
                                text = "If you leave Library Sync on, it will add the removed works back. " +
                                    "Pause it on this device?",
                                color = tokens.secondaryInk,
                                fontSize = 13.sp,
                                lineHeight = 18.sp,
                                modifier = Modifier.padding(horizontal = 13.dp, vertical = 8.dp)
                            )
                            Text(
                                text = "Pause sync (recommended). The sync folder is not wiped.",
                                color = tokens.secondaryInk,
                                fontSize = 13.sp,
                                lineHeight = 18.sp,
                                modifier = Modifier.padding(horizontal = 13.dp).padding(bottom = 8.dp)
                            )
                        }
                        Text(
                            text = "Kudos saves a copy of your current library before replacing it. " +
                                "If the copy cannot be saved, your library will not be replaced.",
                            color = tokens.secondaryInk,
                            fontSize = 13.sp,
                            lineHeight = 18.sp,
                            modifier = Modifier.padding(horizontal = 13.dp, vertical = 12.dp)
                        )
                        SubjectRowSeparator()
                        SettingsActionRow(
                            label = "Replace Library",
                            destructive = true,
                            enabled = replaceEnabled,
                            onClick = { onReplace(pending.syncEnabled && pauseSync) }
                        )
                    }
                } else {
                    if (preview.isLibraryEmpty) {
                        SettingsSection(
                            footnote = "This library is empty. Restore ${preview.fileWorkCount} work(s) from the selected backup."
                        ) {
                            SettingsActionRow(label = "Restore from Backup", onClick = onMerge)
                        }
                    } else {
                        SettingsSection(
                            footnote = "Merge keeps everything already on this device and adds anything you don't " +
                                "have from the backup. It removes nothing."
                        ) {
                            SettingsActionRow(label = "Merge", onClick = onMerge)
                        }
                        SettingsFootnote(
                            "Merge adds works that are not already here. It does not delete local works " +
                                "or apply unsigned deletion claims from the file."
                        )
                        SettingsSection(
                            footnote = "Replace makes this device match the backup. Your works, reading positions, " +
                                "notes, collections, and queues change to match it, and anything missing from " +
                                "the backup is removed. You will confirm before it starts, and Kudos saves a " +
                                "copy of your current library first."
                        ) {
                            SettingsActionRow(
                                label = "Replace Library…",
                                destructive = true,
                                onClick = { reviewingReplace = true }
                            )
                        }
                    }
                }
            }
        }
    }
}

private fun userFacingError(prefix: String, error: Throwable): String {
    val detail = when (error) {
        is BackupError -> error.message
        else -> error.message
    }?.takeIf { it.isNotBlank() } ?: error::class.simpleName ?: "Unknown error"
    return "$prefix: $detail"
}
