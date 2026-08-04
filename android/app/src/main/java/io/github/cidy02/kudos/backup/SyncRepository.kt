package io.github.cidy02.kudos.backup

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.WorkFileStore
import java.nio.file.Files
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext

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

    /**
     * Performs a full sync cycle:
     * 1. Export current library to Kudos.kudosbackup in the SAF folder.
     * 2. (Future) Import/merge if remote is newer (requires last-modified tracking).
     * 3. (Future) Sync EPUBs directory.
     */
    suspend fun runSync(): SyncResult = withContext(Dispatchers.IO) {
        val uri = getSyncFolderUri() ?: return@withContext SyncResult.Error("No sync folder selected.")
        val root = DocumentFile.fromTreeUri(context, uri) ?: return@withContext SyncResult.Error("Could not access sync folder.")
        
        try {
            // 1. Export database
            val bytes = backupRepository.exportV2ZipBytes()
            val fileName = "Kudos.kudosbackup"
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
