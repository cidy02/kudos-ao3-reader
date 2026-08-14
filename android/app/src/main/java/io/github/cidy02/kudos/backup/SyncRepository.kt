package io.github.cidy02.kudos.backup

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import io.github.cidy02.kudos.BuildConfig
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.files.FontFileStore
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.nio.file.Files
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
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
    /**
     * Whole-run single-flight for [runSync]. [PersistenceGate] only serializes
     * the later import/export portions; without this, lifecycle 0→1 / 1→0 kicks
     * (or a rapid background-then-foreground) can overlap on manifest discovery
     * and directory creation at the start of the run.
     */
    private val runSyncMutex = Mutex()

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
        // Opportunistic best-effort: skip if another run is already in flight
        // (lifecycle + WorkManager + manual Sync Now can all race). Prefer
        // tryLock over await so callers are never stuck behind a long SAF run.
        if (!runSyncMutex.tryLock()) {
            return@withContext SyncResult.SkippedAlreadyRunning
        }
        try {
            return@withContext runSyncLocked()
        } finally {
            runSyncMutex.unlock()
        }
    }

    private suspend fun runSyncLocked(): SyncResult {
        val uri = getSyncFolderUri() ?: return SyncResult.Error("No sync folder selected.")
        val root = DocumentFile.fromTreeUri(context, uri)
            ?: return SyncResult.Error("Could not access sync folder.")

        try {
            var syncDir = root.findFile("KudosLibrary")
            if (syncDir == null) {
                syncDir = root.createDirectory("KudosLibrary")
            }
            if (syncDir == null) return SyncResult.Error("Could not create KudosLibrary directory.")

            // 1. Import first, folding in any conflict copies.
            //
            // A SAF provider that loses a write race leaves "manifest (1).json"
            // beside the real one. iOS's foldConflictContents restores *every*
            // unresolved version rather than picking a winner, so nothing a user
            // did on either device is dropped; we do the same, then delete the
            // folded copies.
            val conflicts = syncDir.listFiles().filter { file ->
                val name = file.name ?: return@filter false
                name.startsWith("manifest") && name.endsWith(".json") &&
                    name != BackupPaths.MANIFEST &&
                    name != BackupPaths.MANIFEST_BACKUP &&
                    !name.startsWith(BackupPaths.MANIFEST_TEMP)
            }
            val liveManifest = syncDir.findFile(BackupPaths.MANIFEST)
            val backupManifest = syncDir.findFile(BackupPaths.MANIFEST_BACKUP)
            var foldedConflicts = 0

            if (liveManifest != null || backupManifest != null || conflicts.isNotEmpty()) {
                // The live manifest, or the .bak kept beside it. That fallback is
                // what stops a half-written manifest from wedging the folder for
                // good: import runs before export, so a manifest that throws here
                // aborts the run at the catch below and the export that would have
                // rewritten it never happens — every later sync then fails the same
                // way, forever.
                val primary = decodeManifestOrNull(liveManifest)
                    ?: decodeManifestOrNull(backupManifest)
                primary?.let { importManifest(syncDir, it) }

                conflicts.forEach { file ->
                    val manifest = decodeManifestOrNull(file)
                    if (manifest != null) {
                        importManifest(syncDir, manifest)
                        file.delete()
                        foldedConflicts += 1
                    }
                    // An unreadable conflict copy is left where it is: deleting it
                    // would discard whatever the other device wrote, and throwing
                    // would wedge this folder exactly like the primary used to.
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
                // Same single-source rule as the User-Agent: a hardcoded version here
                // drifts silently and lands in every archive the user exports.
                val manifestOut = snapshot.toV2Manifest(
                    exportedAt = clock(),
                    appVersion = BuildConfig.VERSION_NAME
                )
                
                var worksDir = syncDir.findFile("Works")
                if (worksDir == null) worksDir = syncDir.createDirectory("Works")
                
                var fontsDir = syncDir.findFile("Fonts")
                if (fontsDir == null) fontsDir = syncDir.createDirectory("Fonts")

                val expectedWorks = mutableSetOf<String>()
                val expectedFonts = mutableSetOf<String>()

                // Assets first, manifest last: the manifest is the commit point, so
                // it can never reference an asset file that was not already written.
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
                }

                if (fontsDir != null) {
                    snapshot.fonts.forEach { font ->
                        val bytes = fontFileStore.readFont(font.fileName)
                        if (bytes != null && bytes.isNotEmpty()) {
                            expectedFonts.add(font.fileName)
                            writeIfChanged(fontsDir, font.fileName, "application/octet-stream", bytes)
                        }
                    }
                }

                // The commit point.
                val manifestBytes = BackupJson.encodeToString(manifestOut).toByteArray(Charsets.UTF_8)
                writeManifestAtomically(syncDir, manifestBytes)

                // Only now drop asset files that no manifest record references any
                // more. Pruning *before* the commit point, as this used to, means a
                // crash in between leaves assets deleted while the manifest still
                // lists them — iOS prunes after its own commit for exactly this
                // reason.
                worksDir?.let { removeOrphans(it, expectedWorks) }
                fontsDir?.let { removeOrphans(it, expectedFonts) }
            }

            settingsRepository.updateSyncLastSyncAt(clock())
            settingsRepository.updateSyncHasPendingChanges(false)
            return SyncResult.Success(foldedConflicts)
        } catch (e: Exception) {
            return SyncResult.Error(e.message ?: "Sync failed.")
        }
    }
    
    private fun writeIfChanged(dir: DocumentFile, fileName: String, mimeType: String, data: ByteArray) {
        var file = dir.findFile(fileName)
        if (file != null && file.length() == data.size.toLong()) {
            // Equal length is not equal content. Skipping on length alone means an
            // edit that happens to keep the byte count — a typo fix, a same-width
            // metadata tweak — never syncs at all. The length check is kept as the
            // cheap reject, so the read below only happens when it cannot already
            // prove a difference.
            val existing = runCatching {
                context.contentResolver.openInputStream(file.uri)?.use { it.readBytes() }
            }.getOrNull()
            if (existing != null && existing.contentEquals(data)) return
        }
        if (file == null) {
            file = dir.createFile(mimeType, fileName)
        }
        if (file != null) {
            context.contentResolver.openOutputStream(file.uri, "wt")?.use { it.write(data) }
        }
    }

    /** Decodes a manifest document, or null if it is absent, empty or unreadable. */
    private fun decodeManifestOrNull(file: DocumentFile?): KudosBackupManifest? {
        if (file == null) return null
        return runCatching {
            context.contentResolver.openInputStream(file.uri)?.use { input ->
                val bytes = input.readBytes()
                if (bytes.isEmpty()) null else BackupValidator.decodeManifest(bytes)
            }
        }.getOrNull()
    }

    private suspend fun importManifest(syncDir: DocumentFile, manifest: KudosBackupManifest) {
        val epubFiles = mutableMapOf<String, ByteArray>()
        val fontFiles = mutableMapOf<String, ByteArray>()
        var totalFontBytes = 0L

        syncDir.findFile(BackupPaths.WORKS_DIRECTORY)?.let { worksDir ->
            manifest.works.forEach { work ->
                val epubName = "${BackupPaths.canonicalUuid(work.id, "work.id")}.epub"
                worksDir.findFile(epubName)?.let { file ->
                    context.contentResolver.openInputStream(file.uri)?.use {
                        epubFiles[work.id] = it.readBytes()
                    }
                }
            }
        }
        syncDir.findFile(BackupPaths.FONTS_DIRECTORY)?.let { fontsDir ->
            manifest.fonts.forEach { font ->
                fontsDir.findFile(font.fileName)?.let { file ->
                    context.contentResolver.openInputStream(file.uri)?.use {
                        val path = "${BackupPaths.FONTS_DIRECTORY}/${font.fileName}"
                        val bytes = it.readFontBytes(path)
                        totalFontBytes += bytes.size.toLong()
                        if (totalFontBytes > BackupLimits.MAX_TOTAL_FONT_BYTES) {
                            throw BackupError.InvalidPackage("Total font size exceeds limit")
                        }
                        fontFiles[font.fileName] = bytes
                    }
                }
            }
        }

        backupRepository.importPackage(KudosBackupPackage(manifest, epubFiles, fontFiles))
    }

    private fun InputStream.readFontBytes(path: String): ByteArray {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var total = 0L
        while (true) {
            val count = read(buffer)
            if (count < 0) break
            total += count
            if (total > BackupLimits.MAX_FONT_ENTRY_BYTES) {
                throw BackupError.EntryTooLarge(path)
            }
            output.write(buffer, 0, count)
        }
        return output.toByteArray()
    }

    /**
     * SAF has no atomic-replace primitive, so this is the closest achievable
     * equivalent of iOS's `options: .atomic`: write a fresh temp document, fsync
     * it, demote the live manifest to `.bak`, then rename the temp into place.
     *
     * Opening the live manifest with `"wt"` — which is what this used to do —
     * truncates it to zero length for the whole write. A crash or a second device
     * reading in that window sees no index at all for a folder that still holds
     * every EPUB, and a *partially* written manifest is worse still: it throws on
     * the next import, before the export that would repair it ever runs.
     */
    private fun writeManifestAtomically(syncDir: DocumentFile, bytes: ByteArray) {
        val resolver = context.contentResolver

        // A run that died mid-write leaves a temp behind. It is never
        // authoritative, so drop it rather than let it look like a conflict copy.
        syncDir.listFiles().forEach { file ->
            if (file.name?.startsWith(BackupPaths.MANIFEST_TEMP) == true) file.delete()
        }

        // createDocument may append its own extension for the MIME type, so the
        // temp is never looked up by name again — we keep the handle we were given.
        val temp = syncDir.createFile("application/json", BackupPaths.MANIFEST_TEMP)
            ?: throw IOException("Could not create a temporary manifest.")
        try {
            val descriptor = resolver.openFileDescriptor(temp.uri, "w")
                ?: throw IOException("Could not open the temporary manifest for writing.")
            ParcelFileDescriptor.AutoCloseOutputStream(descriptor).use { output ->
                output.write(bytes)
                output.flush()
                // Durability before the rename: a rename that reaches the disk
                // ahead of its own data is precisely the corruption this prevents.
                descriptor.fileDescriptor.sync()
            }
        } catch (error: Exception) {
            temp.delete()
            throw error
        }

        val live = syncDir.findFile(BackupPaths.MANIFEST)
        if (live != null) {
            syncDir.findFile(BackupPaths.MANIFEST_BACKUP)?.delete()
            DocumentsContract.renameDocument(resolver, live.uri, BackupPaths.MANIFEST_BACKUP)
        }
        DocumentsContract.renameDocument(resolver, temp.uri, BackupPaths.MANIFEST)
    }

    private fun removeOrphans(directory: DocumentFile, expected: Set<String>) {
        directory.listFiles().forEach { file ->
            val name = file.name ?: return@forEach
            if (name !in expected) file.delete()
        }
    }
}

sealed interface SyncResult {
    /**
     * [foldedConflicts] counts the conflict manifests merged in on this run
     * (iOS `FolderSyncResult.foldedConflicts`). Two devices quietly colliding is
     * exactly the situation a user needs told about, and the fold is silent
     * otherwise — nothing else in the UI would ever hint it happened.
     */
    data class Success(val foldedConflicts: Int = 0) : SyncResult
    data class Error(val message: String) : SyncResult

    /**
     * A concurrent [SyncRepository.runSync] is already in flight; this call did
     * nothing. Treated as non-failure by lifecycle / WorkManager callers.
     */
    data object SkippedAlreadyRunning : SyncResult
}
