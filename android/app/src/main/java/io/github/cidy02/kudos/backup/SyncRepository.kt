package io.github.cidy02.kudos.backup

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.WorkFileStore
import java.nio.file.Files
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext

private const val SYNC_WORK_NAME = "FolderSyncWorker"
private val SYNC_INTERVAL = 6L to TimeUnit.HOURS

/**
 * Automates library backup/restore via a user-picked SAF folder.
 * Matches iOS shared-folder sync intent.
 */
class SyncRepository(
    private val context: Context,
    private val settingsRepository: SettingsRepository,
    private val backupRepository: BackupRepository,
    private val workFileStore: WorkFileStore,
    private val clock: () -> Instant = { Instant.now() }
) {
    suspend fun isSyncEnabled(): Boolean {
        return settingsRepository.settings.first().sync.isEnabled
    }

    suspend fun getSyncFolderUri(): Uri? {
        return settingsRepository.settings.first().sync.folderUri?.let { Uri.parse(it) }
    }

    /** Grants persisted access to [uri], enables sync, and schedules periodic background sync. */
    suspend fun connect(uri: Uri) {
        context.contentResolver.takePersistableUriPermission(
            uri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        )
        settingsRepository.updateSyncFolderUri(uri.toString())
        settingsRepository.updateSyncIsEnabled(true)
        scheduleWorker()
    }

    /** Releases the folder permission, disables sync, and cancels background sync. */
    suspend fun disconnect() {
        getSyncFolderUri()?.let { uri ->
            runCatching {
                context.contentResolver.releasePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
            }
        }
        settingsRepository.updateSyncIsEnabled(false)
        settingsRepository.updateSyncFolderUri(null)
        WorkManager.getInstance(context).cancelUniqueWork(SYNC_WORK_NAME)
    }

    private fun scheduleWorker() {
        val constraints = Constraints.Builder()
            .setRequiresBatteryNotLow(true)
            .build()
        val (amount, unit) = SYNC_INTERVAL
        val request = PeriodicWorkRequestBuilder<FolderSyncWorker>(amount, unit)
            .setConstraints(constraints)
            .build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            SYNC_WORK_NAME,
            ExistingPeriodicWorkPolicy.UPDATE,
            request
        )
    }

    /**
     * Performs a two-way sync cycle:
     * 1. Import/merge changes from Kudos.kudosbackup in the SAF folder if present.
     * 2. Export current merged library back to Kudos.kudosbackup.
     * 3. Copy any not-yet-present EPUBs into an epubs/ subdirectory.
     */
    suspend fun runSync(): SyncResult = withContext(Dispatchers.IO) {
        val uri = getSyncFolderUri() ?: return@withContext SyncResult.Error("No sync folder selected.")
        val root = DocumentFile.fromTreeUri(context, uri) ?: return@withContext SyncResult.Error("Could not access sync folder.")
        val fileName = "Kudos.kudosbackup"

        try {
            // 1. Import and merge remote changes first
            root.findFile(fileName)?.let { remoteBackup ->
                context.contentResolver.openInputStream(remoteBackup.uri)?.use { input ->
                    val bytes = input.readBytes()
                    if (bytes.isNotEmpty()) {
                        backupRepository.importV2ZipBytes(bytes)
                    }
                }
            }

            // 2. Export database
            val bytes = backupRepository.exportV2ZipBytes()
            var backupFile = root.findFile(fileName)
            if (backupFile == null) {
                backupFile = root.createFile("application/zip", fileName)
            }
            if (backupFile == null) return@withContext SyncResult.Error("Could not create backup file in folder.")
            
            context.contentResolver.openOutputStream(backupFile.uri, "wt")?.use { 
                it.write(bytes)
            }

            // 2. Sync EPUBs
            var epubsDir = root.findFile("epubs")
            if (epubsDir == null) {
                epubsDir = root.createDirectory("epubs")
            }
            if (epubsDir != null) {
                val snapshot = backupRepository.captureLibrarySnapshot()
                snapshot.works.filter { it.hasEpub }.forEach { work ->
                    val localPath = workFileStore.workEpubPath(work.id)
                    if (Files.isRegularFile(localPath)) {
                        val epubName = "${work.id}.epub"
                        if (epubsDir.findFile(epubName) == null) {
                            val remoteFile = epubsDir.createFile("application/epub+zip", epubName)
                            if (remoteFile != null) {
                                context.contentResolver.openOutputStream(remoteFile.uri)?.use { out ->
                                    Files.copy(localPath, out)
                                }
                            }
                        }
                    }
                }
            }
            
            settingsRepository.updateSyncLastSyncAt(clock())
            SyncResult.Success
        } catch (e: Exception) {
            SyncResult.Error(e.message ?: "Sync failed.")
        }
    }
}

sealed interface SyncResult {
    data object Success : SyncResult
    data class Error(val message: String) : SyncResult
}
