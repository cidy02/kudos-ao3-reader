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
import java.util.Locale
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
    private val clock: () -> Instant = { Instant.now() },
    /** How many bytes of EPUBs one sync-down pass holds in memory at once. */
    private val maxEpubBatchBytes: Long = 32L * 1024 * 1024,
    /** How many bytes of fonts one sync-down may install (iOS `maxTotalFontBytes`). */
    private val maxFontPassBytes: Long = BackupLimits.MAX_TOTAL_FONT_BYTES
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
            val manifestStampAtRead = liveManifest?.lastModified()
            val backupManifest = syncDir.findFile(BackupPaths.MANIFEST_BACKUP)
            var foldedConflicts = 0
            // iOS prunes only while its view of the folder is current. A manifest that is there
            // but could not be read means this run never saw what the folder lists, and pruning
            // by this device's view alone would delete other devices' files.
            var folderViewIsCurrent = liveManifest == null && backupManifest == null

            if (liveManifest != null || backupManifest != null || conflicts.isNotEmpty()) {
                // The live manifest, or the .bak kept beside it. That fallback is
                // what stops a half-written manifest from wedging the folder for
                // good: import runs before export, so a manifest that throws here
                // aborts the run at the catch below and the export that would have
                // rewritten it never happens — every later sync then fails the same
                // way, forever.
                val primary = decodeManifestOrNull(liveManifest)
                    ?: decodeManifestOrNull(backupManifest)
                primary?.let { folderViewIsCurrent = importManifest(syncDir, it) }

                conflicts.forEach { file ->
                    val manifest = decodeManifestOrNull(file)
                    if (manifest != null) {
                        if (!importManifest(syncDir, manifest)) folderViewIsCurrent = false
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
                val epubDigests = mutableMapOf<String, String>()

                // Assets first, manifest last: the manifest is the commit point, so
                // it can never reference an asset file that was not already written.
                if (worksDir != null) {
                    // iOS keeps the EPUB of every work the manifest lists, whether or not this
                    // device holds a copy, so one device can never discard an EPUB another
                    // preserved (`FolderSyncService`, after its commit point).
                    manifestOut.works.forEach { expectedWorks.add(BackupPaths.iosEpubAssetIdentifier(it.id)) }
                    val remoteWorks = worksDir.childrenByLowercaseName()
                    snapshot.works.filter { it.hasEpub }.forEach { work ->
                        val localPath = workFileStore.workEpubPath(work.id)
                        if (Files.isRegularFile(localPath)) {
                            // iOS's name: the UUID in capitals. iOS looks for exactly that, and
                            // prunes any other name as an orphan.
                            val epubName = BackupPaths.iosEpubAssetIdentifier(work.id)
                            val bytes = Files.readAllBytes(localPath)
                            // The digest of the bytes this device uploads (iOS
                            // `Storage.fileDigest`). Android keeps none of its own, and the
                            // one it carries from another device's manifest can describe an
                            // older copy: a sync-down that trusted it would skip a changed book.
                            epubDigests[BackupPaths.normalizeIdForComparison(work.id)] = BackupPaths.sha256(bytes)
                            writeIfChanged(
                                worksDir, epubName, "application/epub+zip", bytes,
                                existing = remoteWorks[epubName.lowercase(Locale.ROOT)]
                            )
                        }
                    }
                }

                if (fontsDir != null) {
                    // As iOS: every font the manifest lists is kept.
                    manifestOut.fonts.forEach { expectedFonts.add(it.fileName) }
                    snapshot.fonts.forEach { font ->
                        val bytes = fontFileStore.readFont(font.fileName)
                        if (bytes != null && bytes.isNotEmpty()) {
                            writeIfChanged(fontsDir, font.fileName, "application/octet-stream", bytes)
                        }
                    }
                }

                // iOS's `viewIsCurrent` (`performSyncUp`): if another device wrote the
                // manifest after this run read it, the manifest about to be written does
                // not know that device's new works, and pruning by it would delete their
                // EPUBs. Stale files simply remain; a later, informed sync clears them.
                if (syncDir.findFile(BackupPaths.MANIFEST)?.lastModified() != manifestStampAtRead) {
                    folderViewIsCurrent = false
                }

                // The commit point.
                val manifestBytes = BackupJson.encodeToString(
                    manifestOut.copy(
                        works = manifestOut.works.map { work ->
                            epubDigests[BackupPaths.normalizeIdForComparison(work.id)]
                                ?.let { work.copy(epubDigest = it) } ?: work
                        }
                    )
                ).toByteArray(Charsets.UTF_8)
                writeManifestAtomically(syncDir, manifestBytes)

                // Only now drop asset files that no manifest record references any
                // more. Pruning *before* the commit point, as this used to, means a
                // crash in between leaves assets deleted while the manifest still
                // lists them — iOS prunes after its own commit for exactly this
                // reason.
                if (folderViewIsCurrent) {
                    worksDir?.let { removeOrphans(it, expectedWorks) }
                    fontsDir?.let { removeOrphans(it, expectedFonts) }
                }
            }

            settingsRepository.updateSyncLastSyncAt(clock())
            settingsRepository.updateSyncHasPendingChanges(false)
            return SyncResult.Success(foldedConflicts)
        } catch (e: Exception) {
            return SyncResult.Error(e.message ?: "Sync failed.")
        }
    }
    
    private fun writeIfChanged(
        dir: DocumentFile,
        fileName: String,
        mimeType: String,
        data: ByteArray,
        existing: DocumentFile? = dir.findFile(fileName)
    ) {
        var file = existing
        // An older Android build named EPUBs in lowercase. Such a file is replaced, not renamed:
        // a phone's shared storage ignores letter case, and a rename that changes only the case
        // is refused there or lands on a "name (1)" copy, which the prune would then remove.
        if (file != null && file.name != fileName) {
            file.delete()
            file = null
        }
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

    /**
     * Merges [manifest] and the files it lists. False when a listed font was left for a later
     * pass: iOS counts that as an outstanding asset and does not prune while one is, because
     * the manifest this device writes next will not list a font it never installed.
     */
    private suspend fun importManifest(syncDir: DocumentFile, manifest: KudosBackupManifest): Boolean {
        val fontFiles = mutableMapOf<String, ByteArray>()
        var totalFontBytes = 0L
        var complete = true

        syncDir.findFile(BackupPaths.FONTS_DIRECTORY)?.let { fontsDir ->
            manifest.fonts.forEach { font ->
                val file = fontsDir.findFile(font.fileName) ?: return@forEach
                val path = "${BackupPaths.FONTS_DIRECTORY}/${font.fileName}"
                // iOS `readChangedRemoteAssets`: a font over the per-file limit, or one that
                // cannot be read, is left out of this pass and must not block the rest of the
                // manifest. Throwing here, as this used to, failed the whole sync every time
                // the folder held such a font.
                val bytes = runCatching {
                    context.contentResolver.openInputStream(file.uri)?.use { it.readFontBytes(path) }
                }.getOrNull()
                if (bytes == null) {
                    complete = false
                    return@forEach
                }
                // A font this device already holds byte for byte takes none of the pass's
                // allowance. One that would take the pass over it waits for the next sync,
                // when what this one installs no longer counts: a library larger than the
                // allowance arrives over several syncs instead of never.
                val settled = fontFileStore.readFont(font.fileName)?.contentEquals(bytes) == true
                if (!settled) {
                    if (totalFontBytes + bytes.size > maxFontPassBytes) {
                        complete = false
                        return@forEach
                    }
                    totalFontBytes += bytes.size
                }
                fontFiles[font.fileName] = bytes
            }
        }

        // iOS writes the UUID in capitals; older Android builds wrote it lowercase.
        val remoteWorks = syncDir.findFile(BackupPaths.WORKS_DIRECTORY)?.childrenByLowercaseName().orEmpty()
        // Only the EPUBs that differ from this device's copies are read (iOS
        // `readChangedRemoteAssets`), and only a batch at a time. Reading every listed EPUB into
        // one map, as this used to, held a whole library in memory at once on every sync. The
        // manifest is merged again with each batch: a merge that brings nothing new changes
        // nothing, and each work is offered once.
        var next = 0
        do {
            val epubFiles = mutableMapOf<String, ByteArray>()
            var batchBytes = 0L
            while (next < manifest.works.size && batchBytes < maxEpubBatchBytes) {
                val work = manifest.works[next++]
                val file = remoteWorks[BackupPaths.iosEpubAssetIdentifier(work.id).lowercase(Locale.ROOT)]
                    ?: continue
                if (isUnchangedLocally(work, file)) continue
                context.contentResolver.openInputStream(file.uri)?.use {
                    val bytes = it.readBytes()
                    epubFiles[work.id] = bytes
                    batchBytes += bytes.size
                }
            }
            backupRepository.importPackage(KudosBackupPackage(manifest, epubFiles, fontFiles))
        } while (next < manifest.works.size)
        return complete
    }

    /**
     * iOS `readChangedRemoteAssets`: size is the change signal, and when the sizes are equal the
     * manifest's digest settles it. A manifest with no digest was written before digests
     * existed, and the byte count is all there is.
     */
    private fun isUnchangedLocally(work: BackupWork, remote: DocumentFile): Boolean {
        val local = workFileStore.workEpubPath(work.id)
        if (!Files.isRegularFile(local) || Files.size(local) != remote.length()) return false
        val remoteDigest = work.epubDigest.orEmpty()
        return remoteDigest.isEmpty() || remoteDigest == BackupPaths.sha256(Files.readAllBytes(local))
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
        // An expected file under another case is still that file.
        val keep = expected.mapTo(HashSet()) { it.lowercase(Locale.ROOT) }
        directory.listFiles().forEach { file ->
            val name = file.name ?: return@forEach
            if (name.startsWith(".")) return@forEach // hidden and system files, as iOS skips them
            if (name.lowercase(Locale.ROOT) !in keep) file.delete()
        }
    }

    /** One listing of a folder, by lowercase name: a `findFile` per work lists it every time. */
    private fun DocumentFile.childrenByLowercaseName(): Map<String, DocumentFile> =
        listFiles().mapNotNull { file -> file.name?.let { it.lowercase(Locale.ROOT) to file } }.toMap()
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
