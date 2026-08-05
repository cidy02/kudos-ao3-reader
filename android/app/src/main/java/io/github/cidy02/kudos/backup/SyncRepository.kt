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
import io.github.cidy02.kudos.files.FontFileStore
import java.nio.file.Files
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext

private const val SYNC_WORK_NAME = "FolderSyncWorker"
private val SYNC_INTERVAL = 6L to TimeUnit.HOURS

class SyncRepository(
    private val context: Context,
    private val settingsRepository: SettingsRepository,
    private val backupRepository: BackupRepository,
    private val workFileStore: WorkFileStore,
    private val fontFileStore: FontFileStore,
    private val persistenceGate: PersistenceGate,
    private val clock: () -> Instant = { Instant.now() }
) {
    suspend fun isSyncEnabled(): Boolean {
        return settingsRepository.settings.first().sync.isEnabled
    }

    suspend fun getSyncFolderUri(): Uri? {
        return settingsRepository.settings.first().sync.folderUri?.let { Uri.parse(it) }
    }

    suspend fun connect(uri: Uri) {
        context.contentResolver.takePersistableUriPermission(
            uri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        )
        settingsRepository.updateSyncFolderUri(uri.toString())
        settingsRepository.updateSyncIsEnabled(true)
        scheduleWorker()
    }

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

    suspend fun runSync(): SyncResult = withContext(Dispatchers.IO) {
        val uri = getSyncFolderUri() ?: return@withContext SyncResult.Error("No sync folder selected.")
        val root = DocumentFile.fromTreeUri(context, uri) ?: return@withContext SyncResult.Error("Could not access sync folder.")
        
        try {
            var syncDir = root.findFile("KudosLibrary")
            if (syncDir == null) {
                syncDir = root.createDirectory("KudosLibrary")
            }
            if (syncDir == null) return@withContext SyncResult.Error("Could not create KudosLibrary directory.")

            // 1. Import first, folding in any conflict copies.
            //
            // A SAF provider that loses a write race leaves "manifest (1).json"
            // beside the real one. iOS's foldConflictContents restores *every*
            // unresolved version rather than picking a winner, so nothing a user
            // did on either device is dropped; we do the same, then delete the
            // folded copies.
            val manifestFilesToRead = mutableListOf<DocumentFile>()
            val manifestFile = syncDir.findFile("manifest.json")
            if (manifestFile != null) manifestFilesToRead.add(manifestFile)
            
            val conflicts = syncDir.listFiles().filter { it.name?.startsWith("manifest") == true && it.name?.endsWith(".json") == true && it.name != "manifest.json" }
            manifestFilesToRead.addAll(conflicts)
            
            if (manifestFilesToRead.isNotEmpty()) {
                manifestFilesToRead.forEach { mFile ->
                    context.contentResolver.openInputStream(mFile.uri)?.use { input ->
                        val bytes = input.readBytes()
                        if (bytes.isNotEmpty()) {
                            val manifest = BackupValidator.decodeManifest(bytes)
                            val epubFiles = mutableMapOf<String, ByteArray>()
                            val fontFiles = mutableMapOf<String, ByteArray>()
                            
                            syncDir.findFile("Works")?.let { worksDir ->
                                manifest.works.forEach { work ->
                                    val epubName = "${BackupPaths.canonicalUuid(work.id, "work.id")}.epub"
                                    worksDir.findFile(epubName)?.let { file ->
                                        context.contentResolver.openInputStream(file.uri)?.use { epubFiles[work.id] = it.readBytes() }
                                    }
                                }
                            }
                            syncDir.findFile("Fonts")?.let { fontsDir ->
                                manifest.fonts.forEach { font ->
                                    fontsDir.findFile(font.fileName)?.let { file ->
                                        context.contentResolver.openInputStream(file.uri)?.use { fontFiles[font.fileName] = it.readBytes() }
                                    }
                                }
                            }
                            
                            val pack = KudosBackupPackage(manifest, epubFiles, fontFiles)
                            backupRepository.importPackage(pack)
                        }
                    }
                    if (mFile.name != "manifest.json") {
                        mFile.delete()
                    }
                }
            } else {
                root.findFile("Kudos.kudosbackup")?.let { remoteBackup ->
                    context.contentResolver.openInputStream(remoteBackup.uri)?.use { input ->
                        val bytes = input.readBytes()
                        if (bytes.isNotEmpty()) {
                            backupRepository.importV2ZipBytes(bytes)
                        }
                    }
                }
            }

            // 2. Export incrementally
            persistenceGate.withLock {
                val snapshot = backupRepository.captureLibrarySnapshot()
                val manifestOut = snapshot.toV2Manifest(exportedAt = clock(), appVersion = "0.1.0")
                
                var worksDir = syncDir.findFile("Works")
                if (worksDir == null) worksDir = syncDir.createDirectory("Works")
                
                var fontsDir = syncDir.findFile("Fonts")
                if (fontsDir == null) fontsDir = syncDir.createDirectory("Fonts")

                val expectedWorks = mutableSetOf<String>()
                val expectedFonts = mutableSetOf<String>()

                // Write works
                if (worksDir != null) {
                    snapshot.works.filter { it.hasEpub }.forEach { work ->
                        val localPath = workFileStore.workEpubPath(work.id)
                        if (Files.isRegularFile(localPath)) {
                            val epubName = "${BackupPaths.canonicalUuid(work.id, "work.id")}.epub"
                            expectedWorks.add(epubName)
                            val bytes = Files.readAllBytes(localPath)
                            writeIfChanged(worksDir, epubName, "application/epub+zip", bytes)
                        }
                    }
                    // Orphan pruning
                    worksDir.listFiles().forEach { file ->
                        if (file.name != null && !expectedWorks.contains(file.name)) {
                            file.delete()
                        }
                    }
                }

                // Write fonts
                if (fontsDir != null) {
                    snapshot.fonts.forEach { font ->
                        val bytes = fontFileStore.readFont(font.fileName)
                        if (bytes != null && bytes.isNotEmpty()) {
                            expectedFonts.add(font.fileName)
                            writeIfChanged(fontsDir, font.fileName, "application/octet-stream", bytes)
                        }
                    }
                    // Orphan pruning
                    fontsDir.listFiles().forEach { file ->
                        if (file.name != null && !expectedFonts.contains(file.name)) {
                            file.delete()
                        }
                    }
                }

                // Write manifest.json
                val manifestBytes = BackupJson.encodeToString(manifestOut).toByteArray(Charsets.UTF_8)
                var manifestDoc = syncDir.findFile("manifest.json")
                if (manifestDoc == null) manifestDoc = syncDir.createFile("application/json", "manifest.json")
                if (manifestDoc != null) {
                    context.contentResolver.openOutputStream(manifestDoc.uri, "wt")?.use { it.write(manifestBytes) }
                }
            }

            settingsRepository.updateSyncLastSyncAt(clock())
            settingsRepository.updateSyncHasPendingChanges(false)
            SyncResult.Success
        } catch (e: Exception) {
            SyncResult.Error(e.message ?: "Sync failed.")
        }
    }
    
    private fun writeIfChanged(dir: DocumentFile, fileName: String, mimeType: String, data: ByteArray) {
        var file = dir.findFile(fileName)
        if (file != null && file.length() == data.size.toLong()) {
            return
        }
        if (file == null) {
            file = dir.createFile(mimeType, fileName)
        }
        if (file != null) {
            context.contentResolver.openOutputStream(file.uri, "wt")?.use { it.write(data) }
        }
    }
}

sealed interface SyncResult {
    data object Success : SyncResult
    data class Error(val message: String) : SyncResult
}
