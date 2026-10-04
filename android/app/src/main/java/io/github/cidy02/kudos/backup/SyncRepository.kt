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
import java.nio.file.Path
import java.text.Normalizer
import java.time.Instant
import java.util.Locale
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject

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
        settingsRepository.updateSyncLastError(null)
        settingsRepository.updateSyncLastManifestDigest(null)
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
        settingsRepository.updateSyncLastError(null)
        settingsRepository.updateSyncLastManifestDigest(null)
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
            val result = try {
                runSyncLocked()
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                SyncResult.Error(error.message ?: "Sync failed.")
            }
            when (result) {
                is SyncResult.Error -> settingsRepository.updateSyncLastError(result.message)
                is SyncResult.Success -> settingsRepository.updateSyncLastError(null)
                SyncResult.SkippedAlreadyRunning -> Unit
            }
            return@withContext result
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
            // did on either device is dropped; we do the same, and delete the
            // folded copies once this run's own manifest, which now lists what
            // they held, is in the folder. Deleted before that, as they used to
            // be, a run that then failed left their records in no index at all.
            val conflicts = syncDir.listFiles().filter { file ->
                val name = file.name ?: return@filter false
                name.startsWith("manifest") && name.endsWith(".json") &&
                    name != BackupPaths.MANIFEST &&
                    name != BackupPaths.MANIFEST_BACKUP &&
                    !name.startsWith(BackupPaths.MANIFEST_TEMP)
            }
            val manifestBytesAtRead = readLiveManifest(syncDir)
            val decodedLive = manifestBytesAtRead?.let { bytes ->
                runCatching { BackupValidator.decodeManifest(bytes) }.getOrNull()
            }
            // Whole JSON this build cannot read was written by a version of Kudos that knows
            // more than this one, or lists more than this one allows. It is not damage, and
            // writing over it would drop what that version listed. A manifest cut short by an
            // interrupted write is damage: no device can read it, and this run repairs it.
            if (decodedLive == null && manifestBytesAtRead != null && isWholeJsonObject(manifestBytesAtRead)) {
                throw IOException("This version of Kudos cannot read the sync folder's manifest. Its files were kept.")
            }
            val backupManifest = syncDir.findFile(BackupPaths.MANIFEST_BACKUP)
            val foldedConflicts = mutableListOf<DocumentFile>()
            // Fonts in the folder that this run could not take: unreadable, or over a limit.
            // This device has no row for them, so its own manifest would stop listing them
            // and the next device to prune would delete another device's font. They go back
            // into the manifest as they were found.
            val pendingFonts = linkedMapOf<String, BackupFont>()
            // Pruning needs a current and complete view of the folder (iOS `performSyncUp`,
            // `viewIsCurrent`): this run read the live manifest, took what it lists, and left
            // no conflict copy unfolded. Without that view the run still publishes, and only
            // never deletes. Refusing to publish instead would leave a folder whose manifest
            // was lost or cut short unable to sync again, and an interrupted first sync is
            // enough to leave one: files in the folder and no manifest yet.
            var folderViewIsCurrent = false

            if (manifestBytesAtRead != null || backupManifest != null || conflicts.isNotEmpty()) {
                // The .bak is the previous manifest: enough to recover this device's records
                // when the live one is missing or damaged, never proof of what the folder
                // lists now. A run that read only the .bak prunes nothing.
                // iOS skips the restore when the manifest is the one this device last wrote or
                // restored, by its date (`lastRestoredRemoteStampKey`). A date is not a safe
                // signal on a provider, so this compares a digest of the bytes. Nothing in such
                // a manifest is news. Merged again every time, as it was, it brought back a
                // download the reader had just removed: this device's own last manifest still
                // said the work had one.
                val ownManifest = decodedLive != null && BackupPaths.sha256(manifestBytesAtRead!!) ==
                    settingsRepository.settings.first().sync.lastManifestDigest
                if (ownManifest) {
                    folderViewIsCurrent = true
                    // Files can land in the folder after the manifest that lists their work.
                    importOriginals(syncDir, decodedLive!!)
                } else {
                    (decodedLive ?: decodeManifestOrNull(backupManifest))?.let { manifest ->
                        val outcome = importManifest(syncDir, manifest)
                        pendingFonts += outcome.pendingFonts
                        folderViewIsCurrent = decodedLive != null && outcome.complete
                    }
                }

                conflicts.forEach { file ->
                    val outcome = decodeManifestOrNull(file)?.let { importManifest(syncDir, it) }
                    if (outcome != null) pendingFonts += outcome.pendingFonts
                    if (outcome?.complete == true) {
                        foldedConflicts += file
                    } else {
                        // Unreadable, or a file it lists could not be read yet (iOS
                        // `foldConflictVersions` leaves such a version unresolved). It stays
                        // where it is, and nothing is pruned while it is there: deleting it
                        // would discard what the other device wrote.
                        folderViewIsCurrent = false
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
                // A folder with nothing in it is a first write, and has nothing to prune.
                // One that holds files and no manifest is not: see above.
                folderViewIsCurrent = syncDir.listFiles().isEmpty()
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
                            // iOS's name: the UUID in capitals.
                            val epubName = BackupPaths.iosEpubAssetIdentifier(work.id)
                            val bytes = Files.readAllBytes(localPath)
                            // The digest of the bytes this device uploads (iOS
                            // `Storage.fileDigest`). Android keeps none of its own, and the
                            // one it carries from another device's manifest can describe an
                            // older copy: a sync-down that trusted it would skip a changed book.
                            epubDigests[BackupPaths.normalizeIdForComparison(work.id)] = BackupPaths.sha256(bytes)
                            writeIfChanged(
                                worksDir, epubName, "application/epub+zip", bytes,
                                existing = remoteWorks[epubName.lowercase(Locale.ROOT)],
                                recase = true
                            )
                        }
                    }
                }

                if (fontsDir != null) {
                    // As iOS: every font the manifest lists is kept.
                    manifestOut.fonts.forEach { expectedFonts.add(it.fileName) }
                    pendingFonts.values.forEach { expectedFonts.add(it.fileName) }
                    val remoteFonts = fontsDir.listFiles()
                    snapshot.fonts.forEach { font ->
                        val bytes = fontFileStore.readFont(font.fileName)
                        if (bytes != null && bytes.isNotEmpty()) {
                            writeIfChanged(
                                fontsDir, font.fileName, "application/octet-stream", bytes,
                                existing = remoteFonts.fontNamed(font.fileName)
                            )
                        }
                    }
                }

                // The original of each converted import, and the record of its conversion,
                // under iOS's names (`writeSyncDirectoryContents`).
                var originalsDir = syncDir.findFile(BackupPaths.ORIGINALS_DIRECTORY)
                if (originalsDir == null) originalsDir = syncDir.createDirectory(BackupPaths.ORIGINALS_DIRECTORY)
                if (originalsDir != null) {
                    val remoteOriginals = originalsDir.childrenByLowercaseName()
                    snapshot.works.forEach { work ->
                        val local = workFileStore.originalFile(work.id) ?: return@forEach
                        val name = BackupPaths.iosOriginalFileName(
                            work.id,
                            local.fileName.toString().substringAfterLast('.', "")
                        )
                        copyIfSizeDiffers(originalsDir, name, local, remoteOriginals[name.lowercase(Locale.ROOT)])
                        workFileStore.readConversionRecord(work.id)?.let { record ->
                            val recordName = BackupPaths.iosConversionRecordFileName(work.id)
                            writeIfChanged(
                                originalsDir, recordName, "application/octet-stream", record,
                                existing = remoteOriginals[recordName.lowercase(Locale.ROOT)]
                            )
                        }
                    }
                }

                // iOS `performSyncUp` needs a current index. A provider's dates can be
                // absent, coarse, or the time of a download, so compare the bytes: if another
                // device wrote the manifest after this run read it, the manifest about to be
                // written does not know what that one lists. Writing it would drop those
                // records from the folder's only index. This run stops, and the next reads
                // the new manifest first.
                if (!readLiveManifest(syncDir).contentEquals(manifestBytesAtRead)) {
                    throw IOException("Sync folder changed during sync. Try syncing again.")
                }

                // The commit point.
                val localFontKeys = manifestOut.fonts.mapTo(HashSet()) { BackupPaths.fontFileNameKey(it.fileName) }
                val manifestJson = BackupJson.encodeToJsonElement(
                    KudosBackupManifest.serializer(),
                    manifestOut.copy(
                        works = manifestOut.works.map { work ->
                            epubDigests[BackupPaths.normalizeIdForComparison(work.id)]
                                ?.let { work.copy(epubDigest = it) } ?: work
                        },
                        fonts = manifestOut.fonts + pendingFonts.values.filter {
                            BackupPaths.fontFileNameKey(it.fileName) !in localFontKeys
                        }
                    )
                ).jsonObject
                // What the folder's manifest held that this build does not know (iOS's
                // pronunciation corrections, and whatever a later version adds) stays in the
                // manifest this build writes. Dropped, as it was, a device that joined the
                // folder after an Android sync never received it. It is the manifest this
                // run replaces, read moments ago, so nothing stale is carried.
                val unknown = if (decodedLive == null) emptyMap() else runCatching {
                    Json.parseToJsonElement(manifestBytesAtRead!!.toString(Charsets.UTF_8)).jsonObject
                        .filterKeys { it !in knownManifestKeys }
                }.getOrDefault(emptyMap())
                val manifestBytes = BackupJson
                    .encodeToString(JsonObject.serializer(), JsonObject(manifestJson + unknown))
                    .toByteArray(Charsets.UTF_8)
                writeManifest(syncDir, manifestBytes, backup = manifestBytesAtRead.takeIf { decodedLive != null })
                foldedConflicts.forEach { it.delete() }
                // Remembered only when nothing is outstanding (iOS withholds its stamp the same
                // way): a work still owed an EPUB, or one whose file has gone missing from this
                // device, is looked for again by the next sync.
                val settled = folderViewIsCurrent && snapshot.works.none { work ->
                    work.remoteEpubPending ||
                        (work.hasEpub && BackupPaths.normalizeIdForComparison(work.id) !in snapshot.epubWorkIds)
                }
                settingsRepository.updateSyncLastManifestDigest(
                    if (settled) BackupPaths.sha256(manifestBytes) else null
                )

                // Only now drop asset files that no manifest record references any
                // more. Pruning *before* the commit point, as this used to, means a
                // crash in between leaves assets deleted while the manifest still
                // lists them — iOS prunes after its own commit for exactly this
                // reason.
                if (folderViewIsCurrent) {
                    worksDir?.let { removeOrphans(it, expectedWorks) }
                    fontsDir?.let { removeOrphans(it, expectedFonts) }
                    originalsDir?.let { directory ->
                        removeOrphanedOriginals(
                            directory,
                            manifestOut.works.mapTo(HashSet()) { BackupPaths.normalizeIdForComparison(it.id) }
                        )
                    }
                }
            }

            settingsRepository.updateSyncLastSyncAt(clock())
            settingsRepository.updateSyncHasPendingChanges(false)
            return SyncResult.Success(foldedConflicts.size)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            return SyncResult.Error(e.message ?: "Sync failed.")
        }
    }
    
    private fun writeIfChanged(
        dir: DocumentFile,
        fileName: String,
        mimeType: String,
        data: ByteArray,
        existing: DocumentFile? = dir.findFile(fileName),
        recase: Boolean = false
    ) {
        var file = existing
        // An EPUB an older Android build named in lowercase is replaced by one under iOS's
        // name, not kept: a released iOS build looks for the exact name, and neither reads nor
        // keeps another. Deleted and written again, not renamed: a phone's shared storage
        // ignores letter case, and a rename that changes only the case is refused there or
        // lands on a "name (1)" copy. If the write then fails the folder is without the file
        // until the next sync; this device holds the bytes, and the run fails loudly.
        if (recase && file != null && file.name != fileName) {
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
        val target = file ?: throw IOException("Could not create $fileName.")
        val output = context.contentResolver.openOutputStream(target.uri, "wt")
            ?: throw IOException("Could not write $fileName.")
        output.use { it.write(data) }
    }

    /** Decodes a manifest document, or null if it is absent, empty or unreadable. */
    private fun decodeManifestOrNull(file: DocumentFile?): KudosBackupManifest? {
        if (file == null) return null
        return runCatching {
            context.contentResolver.openInputStream(file.uri)?.use { input ->
                BackupValidator.decodeManifest(
                    input.readLimitedBytes(BackupPaths.MANIFEST, BackupLimits.MAX_MANIFEST_BYTES)
                )
            }
        }.getOrNull()
    }

    /**
     * The live manifest's bytes, null when the folder has none. A manifest that is there and
     * cannot be read (a provider that is offline, a file over the limit) throws: it is not a
     * missing one, and what was not read is not written over.
     */
    private fun readLiveManifest(syncDir: DocumentFile): ByteArray? {
        val file = syncDir.findFile(BackupPaths.MANIFEST) ?: return null
        return try {
            (context.contentResolver.openInputStream(file.uri) ?: throw IOException()).use {
                it.readLimitedBytes(BackupPaths.MANIFEST, BackupLimits.MAX_MANIFEST_BYTES)
            }
        } catch (error: Exception) {
            throw IOException("The sync folder's manifest could not be read. Its files were kept.")
        }
    }

    /** Every top-level key this build's manifest has, those it leaves out when null included. */
    private val knownManifestKeys: Set<String> by lazy {
        Json { encodeDefaults = true }.encodeToJsonElement(
            KudosBackupManifest.serializer(),
            KudosBackupManifest(version = 0, exportedAt = "")
        ).jsonObject.keys
    }

    // Strict JSON, not `BackupJson`: that one is lenient, and reads a bare word as a value.
    private fun isWholeJsonObject(bytes: ByteArray): Boolean =
        runCatching { Json.parseToJsonElement(bytes.toString(Charsets.UTF_8)) is JsonObject }.getOrDefault(false)

    /** What importing one manifest left in the folder untaken. */
    private class ImportOutcome(
        /** False when a file the manifest lists is in the folder and could not be taken. */
        val complete: Boolean,
        /** The fonts among those, by file name. */
        val pendingFonts: Map<String, BackupFont>
    )

    /**
     * Merges [manifest] and the files it lists that are in the folder. A file the manifest
     * lists and the folder does not hold is nothing to fetch, as on iOS
     * (`readChangedRemoteAssets`): it may arrive later or be gone for good, and counting it as
     * outstanding would hold every later sync back for a file that never comes.
     */
    private suspend fun importManifest(syncDir: DocumentFile, manifest: KudosBackupManifest): ImportOutcome {
        val fontFiles = mutableMapOf<String, ByteArray>()
        val pendingFonts = linkedMapOf<String, BackupFont>()
        var totalFontBytes = 0L
        var complete = true

        val remoteFonts = syncDir.findFile(BackupPaths.FONTS_DIRECTORY)?.listFiles().orEmpty()
        manifest.fonts.forEach { font ->
            val file = remoteFonts.fontNamed(font.fileName) ?: return@forEach
            val path = "${BackupPaths.FONTS_DIRECTORY}/${font.fileName}"
            // iOS `readChangedRemoteAssets`: a font over the per-file limit, or one that
            // cannot be read, is left out of this pass and must not block the rest of the
            // manifest. Throwing here, as this used to, failed the whole sync every time
            // the folder held such a font.
            val bytes = runCatching {
                context.contentResolver.openInputStream(file.uri)?.use { it.readFontBytes(path) }
            }.getOrNull()
            if (bytes == null) {
                pendingFonts[font.fileName] = font
                return@forEach
            }
            // A font this device already holds byte for byte is not offered to the merge at
            // all (iOS leaves it out of the incoming set): the restore validator caps the
            // whole set it is given, so counting settled fonts against it meant a library
            // larger than one pass's allowance never finished arriving. One that would take
            // the pass over the allowance waits for the next sync.
            if (fontFileStore.readFont(font.fileName)?.contentEquals(bytes) == true) return@forEach
            if (totalFontBytes + bytes.size > maxFontPassBytes) {
                pendingFonts[font.fileName] = font
                return@forEach
            }
            totalFontBytes += bytes.size
            fontFiles[font.fileName] = bytes
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
                if (!work.hasEPUB) continue
                val file = remoteWorks[BackupPaths.iosEpubAssetIdentifier(work.id).lowercase(Locale.ROOT)]
                    ?: continue
                if (isUnchangedLocally(work, file)) continue
                // There and not readable, or larger than an archive entry may be: outstanding,
                // as on iOS. Read whole and unbounded, as this used to be, one oversized file
                // named like an EPUB ended the app.
                val bytes = runCatching {
                    context.contentResolver.openInputStream(file.uri)?.use {
                        it.readLimitedBytes(file.name.orEmpty(), BackupLimits.MAX_ENTRY_BYTES)
                    }
                }.getOrNull()
                if (bytes == null) {
                    complete = false
                    continue
                }
                epubFiles[work.id] = bytes
                batchBytes += bytes.size
            }
            // The batches are one restore; only the last marks queued works preserved
            // (see `BackupMergeService.merge`).
            backupRepository.importPackage(
                KudosBackupPackage(manifest, epubFiles, fontFiles),
                normalizeQueuePreservation = next >= manifest.works.size
            )
            // Fonts are restored once per manifest, with the first batch (iOS
            // `readChangedRemoteAssets`). Offered again with each batch, a font whose name
            // collides with a local one gained another suffixed copy every time.
            fontFiles.clear()
        } while (next < manifest.works.size)

        importOriginals(syncDir, manifest)
        return ImportOutcome(complete && pendingFonts.isEmpty(), pendingFonts)
    }

    /**
     * What this device lacks from the folder's `Originals`, for the works [manifest] lists: an
     * original, when it holds none (iOS `readChangedRemoteAssets`, its last loop), and a
     * conversion record, when it holds the original without one. A cloud folder delivers files
     * in any order, so a record can arrive a sync after its original; taken only together with
     * its original, as it was, it was then never taken.
     *
     * The restore attaches a late record only if the folder's original is the same file as the
     * local one, so that original is read again for the comparison, and only when its size
     * already matches. An original this device does not take is not at risk: the prune keeps
     * every listed work's originals, held here or not.
     */
    private suspend fun importOriginals(syncDir: DocumentFile, manifest: KudosBackupManifest) {
        val directory = syncDir.findFile(BackupPaths.ORIGINALS_DIRECTORY) ?: return
        val listed = manifest.works.mapTo(HashSet()) { BackupPaths.normalizeIdForComparison(it.id) }
        val inFolder = linkedMapOf<String, MutableList<DocumentFile>>()
        directory.listFiles().forEach { file ->
            val name = file.name ?: return@forEach
            if (name.startsWith(".")) return@forEach
            val (workId, _) = BackupPaths.parseOriginalFileName(name) ?: return@forEach
            if (workId in listed) inFolder.getOrPut(workId) { mutableListOf() }.add(file)
        }
        val wanted = inFolder.filter { (workId, files) ->
            val local = workFileStore.originalFile(workId) ?: return@filter true
            if (workFileStore.conversionRecordExists(workId)) return@filter false
            val isRecord = { file: DocumentFile -> BackupPaths.parseOriginalFileName(file.name!!)?.second == true }
            files.any(isRecord) && files.any { !isRecord(it) && it.length() == Files.size(local) }
        }

        var batch = mutableMapOf<String, ByteArray>()
        var batchBytes = 0L
        suspend fun flush() {
            if (batch.isEmpty()) return
            backupRepository.importOriginalFiles(manifest, batch)
            batch = mutableMapOf()
            batchBytes = 0L
        }
        wanted.values.forEach { files ->
            files.forEach { file ->
                // The size a provider reports can be zero or unknown, so the stream is limited
                // too (iOS `KudosBackupContents` limits the bytes it reads); the reported size
                // still saves reading 128 MB of a file that says it is larger.
                if (file.length() > BackupLimits.MAX_ENTRY_BYTES) return@forEach
                val bytes = runCatching {
                    context.contentResolver.openInputStream(file.uri)?.use {
                        it.readLimitedBytes(file.name.orEmpty(), BackupLimits.MAX_ENTRY_BYTES)
                    }
                }.getOrNull() ?: return@forEach
                batch[file.name!!] = bytes
                batchBytes += bytes.size
            }
            if (batchBytes >= maxEpubBatchBytes) flush()
        }
        flush()
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

    private fun InputStream.readFontBytes(path: String): ByteArray =
        readLimitedBytes(path, BackupLimits.MAX_FONT_ENTRY_BYTES)

    internal fun InputStream.readLimitedBytes(path: String, limit: Long): ByteArray {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var total = 0L
        while (true) {
            val count = read(buffer)
            if (count < 0) break
            total += count
            if (total > limit) {
                throw BackupError.EntryTooLarge(path)
            }
            output.write(buffer, 0, count)
        }
        return output.toByteArray()
    }

    /**
     * Writes the manifest over the one that is there, and never takes it away first.
     *
     * This used to demote the live manifest to `.bak` and rename a temp into its place, which
     * left the folder with no `manifest.json` in between. iOS reads a folder with files and no
     * manifest as a first write: it publishes its own library and prunes every file that
     * library does not list. A manifest that is cut short instead cannot be read by either
     * app, and neither prunes by what it could not read; the next run repairs it. So the
     * manifest this run read goes to `.bak` as a copy ([backup], null when it was unreadable),
     * and the live file is then written in place.
     *
     * A folder with no manifest yet still gets a temp renamed into place: there is nothing to
     * take away, and a first manifest is then never seen half-written.
     */
    private fun writeManifest(syncDir: DocumentFile, bytes: ByteArray, backup: ByteArray?) {
        val live = syncDir.findFile(BackupPaths.MANIFEST)
        if (live != null) {
            if (backup != null) {
                val copy = syncDir.findFile(BackupPaths.MANIFEST_BACKUP)
                    ?: syncDir.createFile("application/octet-stream", BackupPaths.MANIFEST_BACKUP)
                    ?: throw IOException("Could not create the manifest's backup copy.")
                writeDurably(copy, backup)
            }
            writeDurably(live, bytes)
            return
        }

        // A first write that died leaves a temp behind. It is never authoritative, so drop
        // it rather than let it look like a conflict copy.
        syncDir.listFiles().forEach { file ->
            if (file.name?.startsWith(BackupPaths.MANIFEST_TEMP) == true) file.delete()
        }
        // createDocument may append its own extension for the MIME type, so the
        // temp is never looked up by name again — we keep the handle we were given.
        val temp = syncDir.createFile("application/json", BackupPaths.MANIFEST_TEMP)
            ?: throw IOException("Could not create a temporary manifest.")
        try {
            writeDurably(temp, bytes)
        } catch (error: Exception) {
            temp.delete()
            throw error
        }
        DocumentsContract.renameDocument(context.contentResolver, temp.uri, BackupPaths.MANIFEST)
    }

    /** Writes [bytes] as the whole of [file], and has them on disk before returning. */
    private fun writeDurably(file: DocumentFile, bytes: ByteArray) {
        val descriptor = context.contentResolver.openFileDescriptor(file.uri, "wt")
            ?: throw IOException("Could not open ${file.name} for writing.")
        ParcelFileDescriptor.AutoCloseOutputStream(descriptor).use { output ->
            output.write(bytes)
            output.flush()
            descriptor.fileDescriptor.sync()
        }
    }

    /**
     * Copies [local] into [dir] as [fileName] unless a file of that name and size is already
     * there, without holding it in memory: an original can be a large PDF.
     */
    private fun copyIfSizeDiffers(dir: DocumentFile, fileName: String, local: Path, existing: DocumentFile?) {
        var file = existing
        // ponytail: size is the change signal. An original is written once and replaced only by
        // a re-import; one re-imported at exactly the same size is not uploaded again. Compare
        // a digest if that ever matters.
        if (file != null && file.length() == Files.size(local)) return
        if (file == null) file = dir.createFile("application/octet-stream", fileName)
        val target = file ?: throw IOException("Could not create $fileName.")
        val output = context.contentResolver.openOutputStream(target.uri, "wt")
            ?: throw IOException("Could not write $fileName.")
        output.use { Files.newInputStream(local).use { input -> input.copyTo(it) } }
    }

    /**
     * iOS `removeOrphanedOriginals`: by the work a file belongs to, since a work can have two
     * files here and the extension is whatever was imported. Anything not shaped like one of
     * ours is left strictly alone.
     */
    private fun removeOrphanedOriginals(directory: DocumentFile, keepingWorkIds: Set<String>) {
        directory.listFiles().forEach { file ->
            val name = file.name ?: return@forEach
            if (name.startsWith(".")) return@forEach
            val (workId, _) = BackupPaths.parseOriginalFileName(name) ?: return@forEach
            if (workId !in keepingWorkIds) file.delete()
        }
    }

    /**
     * The font in a folder listing called [name]: as written, else by its composed form (iOS
     * compares names so). Letter case is not folded: two fonts can differ only by it.
     */
    private fun Array<out DocumentFile>.fontNamed(name: String): DocumentFile? {
        firstOrNull { it.name == name }?.let { return it }
        val composed = Normalizer.normalize(name, Normalizer.Form.NFC)
        return firstOrNull { file -> file.name?.let { Normalizer.normalize(it, Normalizer.Form.NFC) } == composed }
    }

    private fun removeOrphans(directory: DocumentFile, expected: Set<String>) {
        // An expected file under another case is still that file.
        val keep = expected.mapTo(HashSet()) { BackupPaths.fontFileNameKey(it) }
        directory.listFiles().forEach { file ->
            val name = file.name ?: return@forEach
            if (name.startsWith(".")) return@forEach // hidden and system files, as iOS skips them
            if (BackupPaths.fontFileNameKey(name) !in keep) file.delete()
        }
    }

    /**
     * One listing of a folder, by lowercase name: a `findFile` per work lists it every time.
     * Storage that tells letter case apart can hold an old lowercase EPUB beside iOS's; the
     * one in capitals sorts first and is the one taken, as it is the one iOS reads.
     */
    private fun DocumentFile.childrenByLowercaseName(): Map<String, DocumentFile> =
        listFiles().filter { it.name != null }.sortedByDescending { it.name }
            .associateBy { BackupPaths.fontFileNameKey(it.name!!) }
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
