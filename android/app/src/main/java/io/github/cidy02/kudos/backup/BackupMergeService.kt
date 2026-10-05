package io.github.cidy02.kudos.backup

import io.github.cidy02.kudos.core.model.Bookmark
import io.github.cidy02.kudos.core.model.CustomFont
import io.github.cidy02.kudos.core.model.ReadingAnnotation
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.ReadingQueueKind
import io.github.cidy02.kudos.core.model.ReadingQueueMembership
import io.github.cidy02.kudos.core.model.SavedSearch
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.SyncTombstone
import io.github.cidy02.kudos.core.model.SyncTombstoneRecordType
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.core.model.canonicalizeCollectionMembershipRecordId
import io.github.cidy02.kudos.core.model.collectionMembershipRecordId
import io.github.cidy02.kudos.core.model.readiumProgress
import io.github.cidy02.kudos.core.model.totalProgressionIn
import io.github.cidy02.kudos.data.local.entity.FandomReadWatermarkEntity
import io.github.cidy02.kudos.data.local.entity.ReadingFavoriteEntity
import io.github.cidy02.kudos.data.local.entity.ReadingSessionEntity
import io.github.cidy02.kudos.reader.ReaderProgressGate
import io.github.cidy02.kudos.works.EpubImportMetadata
import io.github.cidy02.kudos.works.WorkIdentityIndex
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.works.WorkTags
import java.time.Duration
import java.time.Instant
import kotlin.math.abs

/**
 * Restore semantics aligned with Apple `KudosBackup` + `SyncMerge`:
 * - [BackupImportMode.RECONCILE] (default / folder sync): LWW on work metadata
 *   via [lastModifiedAt] and progress via [progressModifiedAt] / [lastReadDate]
 * - [BackupImportMode.MERGE] (file Merge): add-only; keep existing overlap
 * - Local Room tombstones suppress resurrection. Incoming unsigned tombstones
 *   still drop (Phase 1). Incoming signed tombstones are adopted only when the
 *   signature verifies and the signer public key is already trusted.
 * - Queues, memberships, annotations stored and restored by id (LWW)
 */
object BackupMergeService {
    fun merge(
        current: BackupLibrarySnapshot,
        backup: KudosBackupPackage,
        mode: BackupImportMode = BackupImportMode.RECONCILE,
        now: Instant = Instant.now(),
        trustedPublicKeys: Set<String> = emptySet(),
        /**
         * False for every batch of a sync but its last. The batches are one restore: iOS
         * selects every asset, restores once, and marks queued works preserved at the end.
         * Marked after an earlier batch, a queued work's old EPUB was protected from the
         * corrected one a later batch carried.
         */
        normalizeQueuePreservation: Boolean = true,
        /** Apply-only identity decisions from capture; does not rewrite archive record IDs. */
        workIdRemapForApply: Map<String, String> = emptyMap()
    ): BackupMergeResult {
        val manifest = BackupValidator.validateManifest(backup.manifest, now)
        val exportedAt = parseOptionalInstant(manifest.exportedAt)
        val epubFilesById = backup.epubFilesByWorkId.normalizedWorkFileMap()
        val currentEpubIds = current.epubWorkIds.map(BackupPaths::normalizeIdForComparison).toSet()

        var summary = BackupRestoreSummary()
        val epubFilesToWrite = linkedMapOf<String, ByteArray>()

        // Phase 1: unsigned incoming still drop. Phase 2: verify + already-trusted
        // signer → adopt into the local store and this batch's TombstoneIndex.
        // A file never writes the trust store. Replace still does not mint
        // tombstones for omitted works, and still ignores pre-existing local
        // suppressors so the snapshot can load.
        val tombstonesById = current.tombstones
            .associateByTo(linkedMapOf()) { BackupPaths.normalizeIdForComparison(it.id) }
        val adoptedIncoming = ArrayList<SyncTombstone>()
        // Count-only unknown-signer badge source (D9b Android pairing UI): ids
        // whose signature verified but whose signer isn't trusted yet. Not
        // persisted here — BackupRepository.mergePackage feeds this into
        // SettingsRepository.recordUnknownSignerTombstoneIds after the merge.
        val unknownSignerIds = linkedSetOf<String>()
        manifest.tombstones.forEach { archived ->
            // Only createdAt is inside the signed payload. lastModifiedAt
            // decides suppression, so never let an unsigned wire field set it.
            // Then min(createdAt, exportedAt) so a pinned tombstone still
            // cannot outrank the snapshot that carries it (iOS G5 clamp).
            val incoming = archived.toSyncTombstone(exportedAt)
                .let { it.copy(lastModifiedAt = it.createdAt) }
                .let { pinned ->
                    if (exportedAt != null && pinned.lastModifiedAt.isAfter(exportedAt)) {
                        pinned.copy(lastModifiedAt = exportedAt)
                    } else {
                        pinned
                    }
                }
            if (!TombstoneSigning.verify(incoming)) return@forEach
            if (!TombstoneSigning.isTrustedSigner(incoming.signerPublicKey, trustedPublicKeys)) {
                unknownSignerIds += BackupPaths.normalizeIdForComparison(incoming.id)
                return@forEach
            }
            val incomingKey = BackupPaths.normalizeIdForComparison(incoming.id)
            // `id` is not in the signed payload — a trusted signature must never
            // overwrite a local tombstone row (spec §2: local deletes still suppress).
            //
            // One exception, iOS `NewestTombstoneWinsTests`: the same record, deleted
            // again later. `lastModifiedAt` is the suppression key, so keeping the
            // earlier row keeps the narrower window, and a snapshot dated between
            // the two deletions walks through it and brings the record back. It
            // only ever widens what the row already suppresses.
            val held = tombstonesById[incomingKey]
            if (held != null) {
                val sameRecordDeletedLater = held.recordTypeRaw == incoming.recordTypeRaw &&
                    BackupPaths.normalizeIdForComparison(held.recordID) ==
                    BackupPaths.normalizeIdForComparison(incoming.recordID) &&
                    // iOS `KudosBackupService.restore` replaces the signed identity too.
                    // Keep all suppressors here: matching an unsigned row id alone cannot
                    // justify removing a local deletion's AO3/URL identity (see Brief 5c F6).
                    held.ao3WorkID == incoming.ao3WorkID &&
                    held.sourceURL.trim().equals(incoming.sourceURL.trim(), ignoreCase = true) &&
                    incoming.lastModifiedAt.isAfter(held.lastModifiedAt)
                if (!sameRecordDeletedLater) return@forEach
            }
            tombstonesById[incomingKey] = incoming
            adoptedIncoming += incoming
        }
        // Replace ignores every suppressor (local or adopted) so the snapshot
        // can load. Adopted trusted rows still write back via tombstonesById.
        val tombstoneIndex = TombstoneIndex(
            tombstones = if (mode == BackupImportMode.REPLACE_LIBRARY) {
                emptyList()
            } else {
                tombstonesById.values.toList()
            },
            exportedAt = exportedAt,
            now = now
        )
        // Provenance before any Replace omission mints a deletion. Captured and
        // adopted records must never be cancelled by an apply-time keep decision.
        val tombstoneIdsBeforeOmissions = tombstonesById.keys.toSet()

        val worksById = current.works
            .associateByTo(linkedMapOf()) { BackupPaths.normalizeIdForComparison(it.id) }
        val userTagsByWorkId = current.userTagsByWorkId
            .mapKeys { BackupPaths.normalizeIdForComparison(it.key) }
            .mapValues { it.value.normalizedNames() }
            .toMutableMap()
        val identity = WorkIdentityIndex.snapshot(current.works)
        // Archived work UUID → local row UUID after ao3 / canonical-URL rematch.
        val workIdRemap = linkedMapOf<String, String>()

        manifest.works.forEach { archived ->
            val archivedId = BackupPaths.canonicalUuid(archived.id, "work.id")
            val existing = workIdRemapForApply[archivedId]?.let { worksById[it] } ?: identity.existingWork(
                ao3WorkId = archived.ao3WorkID?.toLong(),
                sourceUrl = archived.sourceURL,
                recordId = archivedId
            )
            val targetId = existing?.let { BackupPaths.normalizeIdForComparison(it.id) } ?: archivedId

            if (existing == null && tombstoneIndex.suppressesWorkResurrection(archived)) {
                summary = summary.copy(worksSuppressed = summary.worksSuppressed + 1)
                return@forEach
            }
            workIdRemap[archivedId] = targetId

            val incomingModifiedAt = resolveIncomingLastModifiedAt(
                lastModifiedAt = archived.lastModifiedAt,
                dateAdded = archived.dateAdded,
                exportedAt = exportedAt,
                now = now
            )

            // Whether the archive's EPUB may be written over this work's (iOS
            // `KudosBackupService.restore`, around `mayReplaceEPUB`).
            //
            // The file on disk decides, not the `hasEpub` flag: a flag with no file
            // has nothing to protect, and "a work with no local file can always be
            // filled in" (iOS marks such a work `.missingFile` at launch).
            val existingHasFile = targetId in currentEpubIds
            val mayReplace = if (mode == BackupImportMode.MERGE && existing != null && !existing.isDeleted) {
                // File Merge leaves an active overlap alone and only fills a gap
                // (iOS `mergeRefillsAnEPUBThatWentMissingLocally`).
                !existingHasFile
            } else {
                mayReplaceEpub(
                    hasLocalFile = existingHasFile,
                    isPreserved = existing?.epubPreservationStatusRaw == "preserved",
                    // Replace treats the snapshot as this device's library, so a file
                    // that actually carries the EPUB wins even when clocks are equal.
                    isNewRecord = existing == null || mode == BackupImportMode.REPLACE_LIBRARY,
                    // Only replace a local EPUB when the archive's copy is genuinely
                    // the newer one. Writing it whenever the archive carried a file
                    // means folder sync *destroys* a locally changed EPUB rather than
                    // merely failing to propagate it: sync-down runs before sync-up,
                    // so the stale remote copy is restored over the fresh local file
                    // and then exported back out.
                    //
                    // iOS `KudosBackupService.mayReplaceEPUB` uses shouldApplyIncoming
                    // (>=). A prior asset batch already merged this record's clock;
                    // rejecting equality would discard its later batch's corrected EPUB.
                    incomingIsNewer = existing != null && SyncMerge.shouldApplyIncoming(
                        existing.effectiveLastModifiedAt, incomingModifiedAt
                    )
                )
            }
            // Check only what would be written, and never let bytes that are not a
            // readable EPUB replace a file or claim one. iOS stages and inspects the
            // asset the same way and skips an invalid one, leaving the existing
            // file, `hasEPUB` and preservation as they were.
            val incomingEpub = (epubFilesById[archivedId] ?: epubFilesById[targetId])
                ?.takeIf { mayReplace && EpubImportMetadata.isReadablePackage(it) }
            val existingHasEpub = existingHasFile || existing?.hasEpub == true
            val restoredHasEpub = incomingEpub != null || existingHasEpub

            val restoredBase = archived.toSavedWork(hasEpub = restoredHasEpub, exportedAt = exportedAt)
            val restored = restoredBase.copy(
                id = existing?.id ?: restoredBase.id,
                lastModifiedAt = incomingModifiedAt ?: restoredBase.dateAdded
            )
            worksById[targetId] = if (existing == null) {
                summary = summary.copy(worksCreated = summary.worksCreated + 1)
                // iOS `SavedWork.init` names the file `<UUID>.epub` and `apply`
                // keeps that non-empty local identifier. A custom archived name
                // does not survive a restore onto an empty library.
                restored.copy(assetIdentifier = BackupPaths.iosEpubAssetIdentifier(restored.id))
            } else if (mode == BackupImportMode.MERGE && existing.isDeleted) {
                // Recently Deleted is not in the active library. File Merge
                // adds it back without planting a tombstone, matching iOS.
                summary = summary.copy(worksUpdated = summary.worksUpdated + 1)
                restored.copy(
                    id = existing.id,
                    isDeleted = false,
                    deletedAt = null,
                    permanentDeletionScheduledAt = null
                )
            } else if (mode == BackupImportMode.MERGE) {
                existing.copy(downloadedAt = existing.downloadedAt ?: restored.downloadedAt)
            } else if (mode == BackupImportMode.REPLACE_LIBRARY) {
                summary = summary.copy(worksUpdated = summary.worksUpdated + 1)
                applyReplaceWork(existing, restored)
            } else {
                summary = summary.copy(worksUpdated = summary.worksUpdated + 1)
                mergeWork(existing, restored, archived, incomingModifiedAt, exportedAt)
            }
            // Asset state is device-local and follows disk, independently of which
            // metadata snapshot won (including add-only File Merge).
            val merged = worksById.getValue(targetId)
            worksById[targetId] = merged.copy(
                hasEpub = incomingEpub != null || existingHasFile,
                remoteEpubPending = when {
                    incomingEpub != null -> false
                    archived.hasEPUB && !existingHasFile -> true
                    else -> existing?.remoteEpubPending ?: false
                }
            )
            identity.index(worksById.getValue(targetId))

            if (incomingEpub != null) epubFilesToWrite[targetId] = incomingEpub

            val mergedTags = if (mode == BackupImportMode.REPLACE_LIBRARY) {
                archived.userTags.normalizedNames()
            } else if (mode == BackupImportMode.MERGE && existing != null && !existing.isDeleted) {
                userTagsByWorkId[targetId].orEmpty()
            } else {
                (userTagsByWorkId[targetId].orEmpty() + archived.userTags).normalizedNames()
            }
            if (mergedTags.isNotEmpty()) {
                userTagsByWorkId[targetId] = mergedTags
            } else if (mode == BackupImportMode.REPLACE_LIBRARY) {
                userTagsByWorkId.remove(targetId)
            }
        }

        if (mode == BackupImportMode.REPLACE_LIBRARY) {
            val keptWorkIds = workIdRemap.values.toSet()
            worksById.keys.toList().forEach { id ->
                if (id in keptWorkIds) return@forEach
                val existing = worksById[id] ?: return@forEach
                if (existing.isDeleted) return@forEach
                // Recently Deleted, no SyncTombstone. Keep the EPUB and tags.
                worksById[id] = existing.copy(
                    isDeleted = true,
                    deletedAt = now,
                    permanentDeletionScheduledAt = now.plus(WorkRepository.RECOVERY_WINDOW)
                )
                summary = summary.copy(worksRemoved = summary.worksRemoved + 1)
            }
        }

        val bookmarks = mergeBookmarks(
            current.bookmarks,
            manifest.bookmarks,
            tombstoneIndex = tombstoneIndex,
            mode = mode,
            exportedAt = exportedAt,
            now = now,
            tombstonesById = tombstonesById
        ).also {
            summary = summary.copy(
                bookmarksCreated = it.created,
                bookmarksUpdated = it.updated
            )
        }.items

        val fontMerge = mergeFonts(
            currentFonts = current.fonts,
            currentFontFiles = current.fontFilesByFileName,
            manifestFonts = manifest.fonts,
            backupFontFiles = backup.fontFilesByFileName,
            exportedAt = exportedAt
        )
        summary = summary.copy(
            fontsCreated = fontMerge.created,
            fontsUpdated = fontMerge.updated
        )

        val collections = if (mode == BackupImportMode.REPLACE_LIBRARY) {
            replaceCollections(current.collections, manifest.collections, workIdRemap, exportedAt).also {
                summary = summary.copy(
                    collectionsCreated = it.created,
                    collectionsUpdated = it.updated
                )
            }.items
        } else {
            mergeCollections(
                current.collections,
                manifest.collections,
                tombstoneIndex,
                mode,
                exportedAt,
                now,
                workIdRemap
            ).also {
                summary = summary.copy(
                    collectionsCreated = it.created,
                    collectionsUpdated = it.updated
                )
            }.items
        }

        val savedSearches = mergeSavedSearches(
            current.savedSearches,
            manifest.savedSearches,
            tombstoneIndex = tombstoneIndex,
            mode = mode,
            exportedAt = exportedAt,
            now = now,
            tombstonesById = tombstonesById
        ).also {
            summary = summary.copy(
                savedSearchesCreated = it.created,
                savedSearchesUpdated = it.updated
            )
        }.items

        val queueMerge = mergeQueues(
            currentQueues = current.readingQueues,
            currentMemberships = current.readingQueueMemberships,
            currentQueueTagNames = current.queueTagNamesByQueueId,
            incomingQueues = manifest.readingQueues,
            incomingMemberships = manifest.readingQueueMemberships,
            worksById = worksById,
            tombstoneIndex = tombstoneIndex,
            mode = mode,
            exportedAt = exportedAt,
            now = now,
            workIdRemap = workIdRemap
        )
        summary = summary.copy(
            queuesCreated = queueMerge.queuesCreated,
            queuesUpdated = queueMerge.queuesUpdated,
            membershipsCreated = queueMerge.membershipsCreated,
            membershipsUpdated = queueMerge.membershipsUpdated,
            membershipsSuppressed = queueMerge.membershipsSuppressed
        )
        val restoredEpubIds = (currentEpubIds + epubFilesToWrite.keys)
            .map(BackupPaths::normalizeIdForComparison)
            .toSet()
        // iOS `ReadingQueueService.normalize` runs at the end of restore.
        // Port the queued-work half: membership implies isQueuedForLater, a
        // queued file is preserved, and unknown metadata that still needs an
        // AO3 refresh becomes pending. Unqueued preservation stays pass-through
        // (BackupEpubPreservationPassThroughTest): Android must not invent
        // `notPreserved` for a work the archive did not queue.
        normalizeQueuedWorks(
            worksById = worksById,
            memberships = queueMerge.memberships,
            epubIds = restoredEpubIds,
            now = now,
            reconcilePreservation = normalizeQueuePreservation
        )
        // Replace's absence cleanup never changes the omitted system queue.
        val finishedQueues = finishRestoredQueues(queueMerge.queues, queueMerge.memberships).map { queue ->
            if (mode == BackupImportMode.REPLACE_LIBRARY && queue.kindRaw == ReadingQueueKind.SAVED_FOR_LATER &&
                manifest.readingQueues.none { it.kindRaw == ReadingQueueKind.SAVED_FOR_LATER }
            ) {
                current.readingQueues.firstOrNull { it.id == queue.id } ?: queue
            } else queue
        }

        val readingSessions = mergeReadingSessions(
            current = current.readingSessions,
            incoming = manifest.readingSessions,
            tombstoneIndex = tombstoneIndex,
            mode = mode,
            exportedAt = exportedAt,
            workIdRemap = workIdRemap,
            now = now,
            tombstonesById = tombstonesById
        )
        val readingFavorites = mergeReadingFavorites(
            current = current.readingFavorites,
            incoming = manifest.readingFavorites,
            tombstoneIndex = tombstoneIndex,
            mode = mode,
            exportedAt = exportedAt,
            workIdRemap = workIdRemap,
            now = now,
            tombstonesById = tombstonesById
        )
        val fandomReadWatermarks = mergeFandomReadWatermarks(
            current = current.fandomReadWatermarks,
            incoming = manifest.fandomReadWatermarks,
            tombstoneIndex = tombstoneIndex,
            mode = mode,
            exportedAt = exportedAt,
            now = now,
            tombstonesById = tombstonesById
        )

        val annotationMerge = mergeAnnotations(
            current = current.annotations,
            incoming = manifest.annotations,
            worksById = worksById,
            tombstoneIndex = tombstoneIndex,
            mode = mode,
            exportedAt = exportedAt,
            now = now,
            workIdRemap = workIdRemap
        )
        summary = summary.copy(
            annotationsCreated = annotationMerge.created,
            annotationsUpdated = annotationMerge.updated,
            annotationsSuppressed = annotationMerge.suppressed
        )

        val settings = if (mode == BackupImportMode.REPLACE_LIBRARY) {
            current.settings
        } else {
            val settingsPayload = manifest.settings.retargetRenamedFont(fontMerge.renamedFonts)
            BackupValidator
                .normalizeSettings(settingsPayload, fontMerge.items.map { it.fileName }.toSet())
                .toCoreBackupSettings()
        }

        return BackupMergeResult(
            snapshot = BackupLibrarySnapshot(
                works = worksById.values.sortedByDescending { it.dateAdded },
                userTagsByWorkId = userTagsByWorkId,
                bookmarks = bookmarks,
                fonts = fontMerge.items,
                collections = collections,
                savedSearches = savedSearches,
                settings = settings,
                epubWorkIds = currentEpubIds + epubFilesToWrite.keys,
                fontFilesByFileName = current.fontFilesByFileName + fontMerge.filesToWrite,
                tombstones = tombstonesById.values.sortedBy { it.id },
                readingQueues = finishedQueues,
                readingQueueMemberships = queueMerge.memberships,
                annotations = annotationMerge.items,
                readingSessions = readingSessions,
                readingFavorites = readingFavorites,
                fandomReadWatermarks = fandomReadWatermarks,
                queueTagNamesByQueueId = queueMerge.queueTagNamesByQueueId
            ),
            summary = summary,
            capturedSnapshot = current,
            sourceManifest = manifest,
            mergedAt = now,
            normalizeQueuePreservationForApply = normalizeQueuePreservation,
            replaceOmissionTombstoneIds = tombstonesById.keys - tombstoneIdsBeforeOmissions,
            epubFilesToWriteByWorkId = epubFilesToWrite,
            fontFilesToWriteByFileName = fontMerge.filesToWrite,
            mode = mode,
            unknownSignerTombstoneIds = unknownSignerIds,
            adoptedIncomingTombstoneIds = adoptedIncoming
                .map { BackupPaths.normalizeIdForComparison(it.id) }
                .toSet(),
            removedSavedSearches = current.savedSearches.filter { local ->
                savedSearches.none { merged ->
                    BackupPaths.normalizeIdForComparison(merged.id) ==
                        BackupPaths.normalizeIdForComparison(local.id)
                }
            },
            removedBookmarks = current.bookmarks.filter { local ->
                bookmarks.none { it.urlString == local.urlString }
            },
            removedCollections = current.collections.filter { local ->
                collections.none {
                    BackupPaths.normalizeIdForComparison(it.id) == BackupPaths.normalizeIdForComparison(local.id)
                }
            },
            removedReadingQueues = current.readingQueues.filter { local ->
                finishedQueues.none {
                    BackupPaths.normalizeIdForComparison(it.id) == BackupPaths.normalizeIdForComparison(local.id)
                }
            },
            removedAnnotations = current.annotations.filter { local ->
                annotationMerge.items.none {
                    BackupPaths.normalizeIdForComparison(it.id) == BackupPaths.normalizeIdForComparison(local.id)
                }
            },
            removedReadingSessions = current.readingSessions.filter { local ->
                readingSessions.none { it.id == local.id }
            },
            removedReadingFavorites = current.readingFavorites.filter { local ->
                readingFavorites.none { it.id == local.id }
            },
            removedFandomReadWatermarks = current.fandomReadWatermarks.filter { local ->
                fandomReadWatermarks.none { it.id == local.id }
            },
            workIdRemap = workIdRemap
        )
    }

    /**
     * Called with the database locked by apply. Reuse the original archive (not the
     * already-merged rows, which contain stale local values) for clocked conflicts.
     * Replace becomes reconcile only for changed rows; unchanged rows still replace.
     */
    internal fun refreshForApply(result: BackupMergeResult, stored: BackupLibrarySnapshot): BackupMergeResult {
        val captured = result.capturedSnapshot
        val fresh = stored.copy(
            settings = captured.settings,
            epubWorkIds = captured.epubWorkIds + result.epubFilesToWriteByWorkId.keys,
            fontFilesByFileName = captured.fontFilesByFileName
        )
        val conflicts = mutableSetOf<String>()
        val deferred = mutableSetOf<String>()
        // Assets have already been planned. This pass only resolves database rows;
        // it neither installs bytes nor creates another restored-font identity.
        val remerged by lazy {
            merge(
                current = fresh.copy(tombstones = if (result.mode == BackupImportMode.REPLACE_LIBRARY) {
                    emptyList()
                } else result.snapshot.tombstones),
                backup = KudosBackupPackage(result.sourceManifest.copy(fonts = emptyList(), tombstones = emptyList())),
                mode = if (result.mode == BackupImportMode.MERGE) result.mode else BackupImportMode.RECONCILE,
                now = result.mergedAt,
                normalizeQueuePreservation = result.normalizeQueuePreservationForApply,
                workIdRemapForApply = result.workIdRemap
            ).snapshot
        }
        fun <T> retain(
            kind: String, originals: List<T>, merged: List<T>, held: List<T>,
            id: (T) -> String, resolve: (T) -> T = { it }
        ): List<T> {
            val before = originals.associateBy { BackupPaths.normalizeIdForComparison(id(it)) }
            val current = held.associateBy { BackupPaths.normalizeIdForComparison(id(it)) }
            return merged.mapNotNull { row ->
                val key = BackupPaths.normalizeIdForComparison(id(row))
                val original = before[key]
                val live = current[key]
                when {
                    live == original -> row
                    live == null -> null // Deleted since capture: do not resurrect it.
                    else -> {
                        conflicts += "$kind:$key"
                        if (kind in setOf("bookmark", "search", "font", "tombstone")) deferred += "$kind:$key"
                        if (original == null) live else resolve(live)
                    }
                }
            }
        }
        fun <T> unchanged(kind: String, removed: List<T>, held: List<T>, id: (T) -> String): List<T> {
            val current = held.associateBy { BackupPaths.normalizeIdForComparison(id(it)) }
            return removed.filter {
                val key = BackupPaths.normalizeIdForComparison(id(it))
                val live = current[key]
                if (live != null && live != it) conflicts += "$kind:$key"
                live == it
            }
        }
        fun <T> resolved(
            kind: String, rows: List<T>, live: T, id: (T) -> String,
            clock: (T) -> Instant?, onTie: () -> T = { live }
        ): T {
            val candidate = rows.firstOrNull {
                BackupPaths.normalizeIdForComparison(id(it)) == BackupPaths.normalizeIdForComparison(id(live))
            } ?: live
            // The existing >= rule is right for an unchanged row, but an edit made
            // during this import owns an equal clock tick. Retain existing fills.
            if (clock(live) != null && clock(candidate) == clock(live)) {
                val kept = onTie()
                if (kept != candidate) deferred += "$kind:${BackupPaths.normalizeIdForComparison(id(live))}"
                return kept
            }
            return candidate
        }

        val snapshot = result.snapshot.copy(
            works = retain("work", captured.works, result.snapshot.works, fresh.works, { it.id }) { live ->
                var merged = remerged.works.firstOrNull {
                    BackupPaths.normalizeIdForComparison(it.id) == BackupPaths.normalizeIdForComparison(live.id)
                } ?: live
                val original = captured.works.firstOrNull {
                    BackupPaths.normalizeIdForComparison(it.id) == BackupPaths.normalizeIdForComparison(live.id)
                }
                val archived = result.sourceManifest.works.firstOrNull {
                    result.workIdRemap[BackupPaths.normalizeIdForComparison(it.id)] ==
                        BackupPaths.normalizeIdForComparison(live.id)
                }
                if (original != null && archived != null && live.copy(
                    progressModifiedAt = original.progressModifiedAt, lastReadDate = original.lastReadDate,
                    readiumLocator = original.readiumLocator, lastSpineIndex = original.lastSpineIndex,
                    lastScrollFraction = original.lastScrollFraction, legacyReaderProgress = original.legacyReaderProgress
                ) != original && resolveIncomingLastModifiedAt(archived.lastModifiedAt, archived.dateAdded,
                    parseOptionalInstant(result.sourceManifest.exportedAt), result.mergedAt) == live.effectiveLastModifiedAt
                ) {
                    val kept = mergeWork(live, merged, archived, incomingModifiedAtOverride = null,
                        exportedAt = parseOptionalInstant(result.sourceManifest.exportedAt))
                    if (kept != merged) deferred += "work:${BackupPaths.normalizeIdForComparison(live.id)}"
                    merged = kept
                }
                // Progress saves can leave lastModifiedAt alone, or share a clock tick.
                // A position saved during this import must never move back, in any mode.
                if (original != null && (live.progressModifiedAt != original.progressModifiedAt ||
                    live.lastReadDate != original.lastReadDate || live.readiumLocator != original.readiumLocator ||
                    live.lastSpineIndex != original.lastSpineIndex || live.lastScrollFraction != original.lastScrollFraction ||
                    live.legacyReaderProgress != original.legacyReaderProgress)
                ) {
                    if (merged.progressModifiedAt != live.progressModifiedAt || merged.lastReadDate != live.lastReadDate ||
                        merged.readiumLocator != live.readiumLocator || merged.lastSpineIndex != live.lastSpineIndex ||
                        merged.lastScrollFraction != live.lastScrollFraction || merged.legacyReaderProgress != live.legacyReaderProgress
                    ) deferred += "work:${BackupPaths.normalizeIdForComparison(live.id)}"
                    merged.copy(
                        progressModifiedAt = live.progressModifiedAt, lastReadDate = live.lastReadDate,
                        readiumLocator = live.readiumLocator, lastSpineIndex = live.lastSpineIndex,
                        lastScrollFraction = live.lastScrollFraction, legacyReaderProgress = live.legacyReaderProgress
                    )
                } else merged
            },
            bookmarks = retain("bookmark", captured.bookmarks, result.snapshot.bookmarks, fresh.bookmarks, { it.id }),
            fonts = retain("font", captured.fonts, result.snapshot.fonts, fresh.fonts, { it.id }),
            savedSearches = retain("search", captured.savedSearches, result.snapshot.savedSearches, fresh.savedSearches, { it.id }),
            collections = retain("collection", captured.collections, result.snapshot.collections, fresh.collections, { it.id }) {
                val live = it
                resolved("collection", remerged.collections, live, { row -> row.id }, { row -> row.lastModifiedAt ?: row.dateAdded }) {
                    result.sourceManifest.collections.firstOrNull { archived ->
                        BackupPaths.normalizeIdForComparison(archived.id) == BackupPaths.normalizeIdForComparison(live.id)
                    }?.let { archived -> fillCollectionFields(live, archived, incomingWins = false,
                        exportedAt = parseOptionalInstant(result.sourceManifest.exportedAt)) } ?: live
                }
            },
            readingQueues = retain("queue", captured.readingQueues, result.snapshot.readingQueues, fresh.readingQueues, { it.id }) {
                val live = it
                resolved("queue", remerged.readingQueues, live, { row -> row.id }, { row ->
                    SyncMerge.effectiveQueueModifiedAt(row.dateUpdated, row.lastMembershipChangedAt,
                        fresh.readingQueueMemberships.filter { member -> member.queueID == row.id }
                            .map { member -> member.lastModifiedAt ?: member.queuedAt })
                }) {
                    result.sourceManifest.readingQueues.firstOrNull { archived ->
                        BackupPaths.normalizeIdForComparison(archived.id) == BackupPaths.normalizeIdForComparison(live.id) ||
                            (live.kindRaw == ReadingQueueKind.SAVED_FOR_LATER && archived.kindRaw == live.kindRaw)
                    }?.let { archived -> fillQueueFields(live, archived, incomingWins = false) } ?: live
                }
            },
            readingQueueMemberships = retain("membership", captured.readingQueueMemberships,
                result.snapshot.readingQueueMemberships, fresh.readingQueueMemberships, { it.id }) {
                resolved("membership", remerged.readingQueueMemberships, it, { row -> row.id }, { row -> row.lastModifiedAt ?: row.queuedAt })
            },
            annotations = retain("annotation", captured.annotations, result.snapshot.annotations, fresh.annotations, { it.id }) {
                resolved("annotation", remerged.annotations, it, { row -> row.id }, { row -> row.effectiveLastModifiedAt })
            },
            readingSessions = retain("session", captured.readingSessions, result.snapshot.readingSessions, fresh.readingSessions, { it.id }) {
                resolved("session", remerged.readingSessions, it, { row -> row.id }, { row -> row.lastModifiedAt })
            },
            readingFavorites = retain("favorite", captured.readingFavorites, result.snapshot.readingFavorites, fresh.readingFavorites, { it.id }) {
                resolved("favorite", remerged.readingFavorites, it, { row -> row.id }, { row -> row.lastModifiedAt })
            },
            fandomReadWatermarks = retain("watermark", captured.fandomReadWatermarks,
                result.snapshot.fandomReadWatermarks, fresh.fandomReadWatermarks, { it.id }) {
                resolved("watermark", remerged.fandomReadWatermarks, it, { row -> row.id }, { row -> row.lastModifiedAt })
            },
            // Adopted archive deletions are not local apply conflicts to cancel.
            tombstones = retain("tombstone", captured.tombstones, result.snapshot.tombstones.filterNot {
                BackupPaths.normalizeIdForComparison(it.id) in result.adoptedIncomingTombstoneIds
            }, fresh.tombstones, { it.id }) + result.snapshot.tombstones.filter {
                BackupPaths.normalizeIdForComparison(it.id) in result.adoptedIncomingTombstoneIds
            },
            userTagsByWorkId = result.snapshot.userTagsByWorkId.mapValues { (id, names) ->
                val before = captured.userTagsByWorkId[id].orEmpty()
                val live = fresh.userTagsByWorkId[id].orEmpty()
                if (before == live) names else (live + (names - before.toSet())).normalizedNames()
            },
            queueTagNamesByQueueId = result.snapshot.queueTagNamesByQueueId.mapValues { (id, names) ->
                val before = captured.queueTagNamesByQueueId[id].orEmpty()
                val live = fresh.queueTagNamesByQueueId[id].orEmpty()
                if (before == live) names else (live + (names - before.toSet())).normalizedNames()
            }
        )
        val refreshed = result.copy(
            snapshot = snapshot,
            removedBookmarks = unchanged("bookmark", result.removedBookmarks, fresh.bookmarks) { it.id },
            removedSavedSearches = unchanged("search", result.removedSavedSearches, fresh.savedSearches) { it.id },
            removedCollections = unchanged("collection", result.removedCollections, fresh.collections) { it.id },
            removedReadingQueues = unchanged("queue", result.removedReadingQueues, fresh.readingQueues) { it.id },
            removedAnnotations = unchanged("annotation", result.removedAnnotations, fresh.annotations) { it.id },
            removedReadingSessions = unchanged("session", result.removedReadingSessions, fresh.readingSessions) { it.id },
            removedReadingFavorites = unchanged("favorite", result.removedReadingFavorites, fresh.readingFavorites) { it.id },
            removedFandomReadWatermarks = unchanged("watermark", result.removedFandomReadWatermarks, fresh.fandomReadWatermarks) { it.id }
        )
        val omissionKinds = mapOf(
            SyncTombstoneRecordType.BOOKMARK to "bookmark",
            SyncTombstoneRecordType.SAVED_SEARCH to "search",
            SyncTombstoneRecordType.READING_SESSION to "session",
            SyncTombstoneRecordType.READING_FAVORITE to "favorite",
            SyncTombstoneRecordType.FANDOM_READ_WATERMARK to "watermark"
        )
        val keptTombstones = refreshed.snapshot.tombstones.filterNot { tombstone ->
            val id = BackupPaths.normalizeIdForComparison(tombstone.id)
            val recordId = BackupPaths.normalizeIdForComparison(tombstone.recordID)
            // Only this merge's own omission records. An archive or another device's
            // deletion for the very same row remains intact, including its signature.
            id in result.replaceOmissionTombstoneIds &&
                "${omissionKinds[tombstone.recordTypeRaw]}:$recordId" in conflicts
        }
        return refreshed.copy(
            snapshot = refreshed.snapshot.copy(tombstones = keptTombstones),
            summary = result.summary.copy(
                concurrentRowsChanged = conflicts.size, concurrentRowsDeferred = deferred.size
            )
        )
    }

    fun preview(
        current: BackupLibrarySnapshot,
        backup: KudosBackupPackage
    ): BackupImportPreview {
        val localActive = current.works.filterNot { it.isDeleted }
        val index = WorkIdentityIndex.snapshot(localActive)
        val fileIds = backup.manifest.works
            .map { BackupPaths.canonicalUuid(it.id, "work.id") }
            .toSet()
        val matchedLocalIds = mutableSetOf<String>()
        var willAdd = 0
        backup.manifest.works.forEach { archived ->
            val match = index.existingWork(
                ao3WorkId = archived.ao3WorkID?.toLong(),
                sourceUrl = archived.sourceURL,
                recordId = BackupPaths.canonicalUuid(archived.id, "work.id")
            )
            if (match != null) {
                matchedLocalIds += BackupPaths.normalizeIdForComparison(match.id)
            } else {
                willAdd += 1
            }
        }
        return BackupImportPreview(
            localWorkCount = localActive.size,
            fileWorkCount = fileIds.size,
            willAdd = willAdd,
            willRemove = localActive.count {
                BackupPaths.normalizeIdForComparison(it.id) !in matchedLocalIds
            },
            inBoth = matchedLocalIds.size
        )
    }

    /**
     * Apple-aligned work merge: metadata/flags LWW on lastModifiedAt; progress LWW
     * on progressModifiedAt (fallback lastReadDate). Tags are unioned.
     */
    internal fun mergeWork(
        existing: SavedWork,
        restored: SavedWork,
        archived: BackupWork,
        incomingModifiedAtOverride: Instant? = null,
        exportedAt: Instant? = null
    ): SavedWork {
        // Null means the archive clock was missing or rejected as future skew.
        val incomingModifiedAt = incomingModifiedAtOverride
        val localModifiedAt = existing.effectiveLastModifiedAt
        val incomingWins = SyncMerge.shouldApplyIncoming(localModifiedAt, incomingModifiedAt)

        val base = if (incomingWins) {
            restored.copy(
                id = existing.id,
                // Never lose a local EPUB just because the archive lacked one.
                hasEpub = existing.hasEpub || restored.hasEpub,
                // No hasEpub coercion: an EPUB on disk is what `isQueuedForLater`
                // already protects, and promoting it to `isSaved` silently
                // converted every queue-only work into a library work on merge.
                // iOS `apply`: the winning snapshot's kept flag, so a work un-kept on one
                // device is un-kept here. ORed, as it was, the flag could never turn off.
                isSaved = restored.isSaved,
                // ORed on iOS too, where membership then decides it; see `normalizeQueuedWorks`.
                isQueuedForLater = restored.isQueuedForLater || existing.isQueuedForLater,
                permanentDeletionScheduledAt = keptDeletionSchedule(
                    restored.permanentDeletionScheduledAt,
                    existing.isDeleted,
                    existing.permanentDeletionScheduledAt
                ),
                dateAdded = minInstant(existing.dateAdded, restored.dateAdded),
                createdAt = minNullableInstant(existing.createdAt, restored.createdAt),
                lastModifiedAt = maxInstant(existing.lastModifiedAt, incomingModifiedAt)
                    ?: incomingModifiedAt,
                comments = archived.comments ?: existing.comments,
                hits = archived.hits ?: existing.hits,
                knownChapterCount = archived.knownChapterCount ?: existing.knownChapterCount,
                lastUpdateCheck = restored.lastUpdateCheck ?: existing.lastUpdateCheck,
                hasGivenKudos = existing.hasGivenKudos || restored.hasGivenKudos,
                freedAt = existing.freedAt,
                authorIdentitiesJSON = existing.authorIdentitiesJSON,
                keepInProgressOverride = archived.keepInProgressOverride ?: existing.keepInProgressOverride,
                hiddenFromHistoryAt = if (archived.hiddenFromHistoryAt != null) restored.hiddenFromHistoryAt else existing.hiddenFromHistoryAt,
                datePublished = restored.datePublished.ifBlank { existing.datePublished },
                dateUpdated = restored.dateUpdated.ifBlank { existing.dateUpdated },
                epubDigest = restored.epubDigest.ifBlank { existing.epubDigest },
                assetIdentifier = restored.assetIdentifier.ifBlank { existing.assetIdentifier },
                bookmarks = archived.bookmarks ?: existing.bookmarks,
                ao3SeriesID = archived.ao3SeriesID ?: existing.ao3SeriesID,
                ao3WorkID = archived.ao3WorkID ?: existing.ao3WorkID
            )
        } else {
            // Keep local flags/metadata; still absorb non-destructive fills.
            existing.copy(
                hasEpub = existing.hasEpub || restored.hasEpub,
                isQueuedForLater = existing.isQueuedForLater || restored.isQueuedForLater,
                title = existing.title.ifBlank { restored.title },
                author = existing.author.ifBlank { restored.author },
                summary = existing.summary.ifBlank { restored.summary },
                sourceUrl = existing.sourceUrl.ifBlank { restored.sourceUrl },
                createdAt = minNullableInstant(existing.createdAt, restored.createdAt),
                comments = existing.comments ?: archived.comments,
                hits = existing.hits ?: archived.hits,
                knownChapterCount = existing.knownChapterCount ?: archived.knownChapterCount,
                lastUpdateCheck = existing.lastUpdateCheck ?: restored.lastUpdateCheck,
                workWarnings = mergeStringLists(existing.workWarnings, restored.workWarnings),
                workCategories = mergeStringLists(existing.workCategories, restored.workCategories),
                workTags = mergeStringLists(existing.workTags, restored.workTags),
                workFandoms = mergeStringLists(existing.workFandoms, restored.workFandoms),
                workCharacters = mergeStringLists(existing.workCharacters, restored.workCharacters),
                workRelationships = mergeStringLists(
                    existing.workRelationships,
                    restored.workRelationships
                ),
                workFreeforms = mergeStringLists(existing.workFreeforms, restored.workFreeforms),
                workTagsFetched = existing.workTagsFetched || restored.workTagsFetched,
                lastModifiedAt = maxInstant(existing.lastModifiedAt, incomingModifiedAt)
                    ?: existing.effectiveLastModifiedAt,
                hasGivenKudos = existing.hasGivenKudos || restored.hasGivenKudos,
                datePublished = existing.datePublished.ifBlank { restored.datePublished },
                dateUpdated = existing.dateUpdated.ifBlank { restored.dateUpdated },
                epubDigest = existing.epubDigest.ifBlank { restored.epubDigest },
                assetIdentifier = existing.assetIdentifier.ifBlank { restored.assetIdentifier },
                bookmarks = existing.bookmarks ?: archived.bookmarks,
                ao3SeriesID = existing.ao3SeriesID ?: archived.ao3SeriesID,
                ao3WorkID = existing.ao3WorkID ?: archived.ao3WorkID
            )
        }

        // Preservation trio: store/re-emit only. Never invent a status. Prefer the
        // non-null side when one is absent so a local-wins merge does not wipe
        // values that only arrived on the archive (and vice versa).
        val withPreservation = base.copy(
            downloadedAt = if (archived.downloadedAt != null &&
                (incomingWins || existing.downloadedAt == null)
            ) {
                restored.downloadedAt
            } else {
                existing.downloadedAt
            },
            epubPreservationStatusRaw = if (incomingWins) {
                restored.epubPreservationStatusRaw ?: existing.epubPreservationStatusRaw
            } else {
                existing.epubPreservationStatusRaw ?: restored.epubPreservationStatusRaw
            },
            metadataSyncStatusRaw = if (incomingWins) {
                restored.metadataSyncStatusRaw ?: existing.metadataSyncStatusRaw
            } else {
                existing.metadataSyncStatusRaw ?: restored.metadataSyncStatusRaw
            },
            preservedAt = maxInstant(existing.preservedAt, restored.preservedAt),
            lastPreservationAttemptAt = maxInstant(
                existing.lastPreservationAttemptAt,
                restored.lastPreservationAttemptAt
            )
        )

        return applyProgressLww(withPreservation, existing, restored, archived, exportedAt)
    }

    /**
     * Prefer newer progress. When the archive lacks progress timestamps, keep
     * local progress if local [lastReadDate] is later (non-destructive default).
     */
    private fun applyProgressLww(
        base: SavedWork,
        existing: SavedWork,
        restored: SavedWork,
        archived: BackupWork,
        exportedAt: Instant? = null
    ): SavedWork {
        val incomingHasProgress = restored.lastReadDate != null ||
            restored.lastSpineIndex > 0 ||
            restored.lastScrollFraction > 0.0 ||
            !restored.readiumLocator.isNullOrBlank()
        if (!incomingHasProgress) {
            return base.copy(
                lastSpineIndex = existing.lastSpineIndex,
                lastScrollFraction = existing.lastScrollFraction,
                lastReadDate = existing.lastReadDate,
                readiumLocator = existing.readiumLocator ?: restored.readiumLocator,
                legacyReaderProgress = existing.legacyReaderProgress,
                progressModifiedAt = existing.progressModifiedAt
            )
        }

        val localProgressAt = existing.effectiveProgressModifiedAt
        val incomingProgressAt = parseOptionalInstant(archived.progressModifiedAt, exportedAt)
            ?: restored.lastReadDate

        if (existing.hasStartedReading) {
            // Archive without any progress clock + local has later lastReadDate → keep local.
            if (incomingProgressAt == null && localProgressAt != null) {
                return base.copy(
                    lastSpineIndex = existing.lastSpineIndex,
                    lastScrollFraction = existing.lastScrollFraction,
                    lastReadDate = existing.lastReadDate,
                    readiumLocator = existing.readiumLocator ?: restored.readiumLocator,
                    legacyReaderProgress = existing.legacyReaderProgress,
                    progressModifiedAt = existing.progressModifiedAt
                )
            }
            if (!SyncMerge.shouldApplyIncoming(localProgressAt, incomingProgressAt)) {
                return base.copy(
                    lastSpineIndex = existing.lastSpineIndex,
                    lastScrollFraction = existing.lastScrollFraction,
                    lastReadDate = existing.lastReadDate,
                    readiumLocator = existing.readiumLocator ?: restored.readiumLocator,
                    legacyReaderProgress = existing.legacyReaderProgress,
                    progressModifiedAt = existing.progressModifiedAt
                )
            }
        }

        return base.copy(
            lastSpineIndex = restored.lastSpineIndex,
            lastScrollFraction = restored.lastScrollFraction,
            lastReadDate = restored.lastReadDate,
            readiumLocator = restored.readiumLocator ?: existing.readiumLocator,
            // The macOS reader's percent travels with the progress, not with the
            // metadata (iOS `SyncMerge.applyProgress`). The key present is a percent or
            // an explicit null from a device that read past it. No key at all (an
            // older build) is not a clear, unless the locator actually moved: the
            // card prefers the percent, and must not stay on a stale one.
            legacyReaderProgress = when {
                archived.legacyReaderProgress != null -> restored.legacyReaderProgress
                keylessLocatorMoved(
                    restored.readiumLocator,
                    existing.readiumProgress ?: existing.legacyReaderProgress
                ) -> null
                else -> existing.legacyReaderProgress
            },
            progressModifiedAt = incomingProgressAt ?: restored.lastReadDate
        )
    }

    /** iOS `keylessLocatorMoved`: by at least the reader's own delta from this device's place. */
    private fun keylessLocatorMoved(locator: String?, local: Double?): Boolean {
        val incoming = totalProgressionIn(locator) ?: return false
        return local != null && abs(incoming - local) >= ReaderProgressGate.MIN_DELTA
    }

    private fun mergeBookmarks(
        current: List<Bookmark>,
        incoming: List<BackupBookmark>,
        tombstoneIndex: TombstoneIndex,
        mode: BackupImportMode = BackupImportMode.RECONCILE,
        exportedAt: Instant? = null,
        now: Instant = Instant.now(),
        tombstonesById: MutableMap<String, SyncTombstone>
    ): MergeItems<Bookmark> {
        val byUrl = current.associateByTo(linkedMapOf()) { it.urlString }
        var created = 0
        var updated = 0
        incoming.forEach { archived ->
            val archivedId = archived.id?.takeIf { it.isNotBlank() }?.let {
                BackupPaths.canonicalUuid(it, "bookmark.id")
            }
            if (mode != BackupImportMode.REPLACE_LIBRARY && archivedId != null) {
                val incomingModified = BackupValidator.parseInstant(
                    archived.dateAdded,
                    "bookmark.dateAdded",
                    exportedAt
                )
                if (tombstoneIndex.bookmarkResolution(archivedId, incomingModified) ==
                    TombstoneResolution.SUPPRESS_STALE
                ) {
                    return@forEach
                }
            }
            val existing = byUrl[archived.urlString]
            byUrl[archived.urlString] = if (existing == null) {
                created += 1
                archived.toBookmark(exportedAt)
            } else {
                updated += 1
                existing.copy(
                    title = archived.title,
                    dateAdded = BackupValidator.parseInstant(
                        archived.dateAdded,
                        "bookmark.dateAdded",
                        exportedAt
                    )
                )
            }
        }
        if (mode == BackupImportMode.REPLACE_LIBRARY) {
            val incomingUrls = incoming.mapTo(mutableSetOf()) { it.urlString }
            byUrl.keys.toList().forEach { url ->
                if (url !in incomingUrls) {
                    val omitted = byUrl.remove(url) ?: return@forEach
                    mintImmediateTombstone(
                        recordId = omitted.id,
                        recordType = SyncTombstoneRecordType.BOOKMARK,
                        deletionReason = "bookmarkDeleted",
                        now = now,
                        tombstonesById = tombstonesById
                    )
                }
            }
        }
        return MergeItems(byUrl.values.sortedByDescending { it.dateAdded }, created, updated)
    }

    private fun mergeFonts(
        currentFonts: List<CustomFont>,
        currentFontFiles: Map<String, ByteArray>,
        manifestFonts: List<BackupFont>,
        backupFontFiles: Map<String, ByteArray>,
        exportedAt: Instant? = null
    ): FontMerge {
        val fontsByName = currentFonts.associateByTo(linkedMapOf()) { it.fileName }
        val fontNamesByFoldedName = currentFonts.groupByTo(
            linkedMapOf(),
            { BackupPaths.fontFileNameKey(it.fileName) },
            { it.fileName }
        ).mapValuesTo(linkedMapOf()) { (_, names) -> names.toMutableList() }
        val currentFilesByFoldedName = currentFontFiles.entries.groupBy {
            BackupPaths.fontFileNameKey(it.key)
        }
        val filesToWrite = linkedMapOf<String, ByteArray>()
        val renamedFonts = mutableMapOf<String, String>()
        var created = 0
        var updated = 0

        fun restoreWithSuffix(archived: BackupFont, incomingBytes: ByteArray) {
            val reusableName = (currentFontFiles + filesToWrite).entries.firstOrNull { (name, bytes) ->
                BackupPaths.isRestoredFontFileName(name, archived.fileName) &&
                    bytes.size == incomingBytes.size && bytes.isNotEmpty() &&
                    BackupPaths.sha256(bytes) == BackupPaths.sha256(incomingBytes)
            }?.key
            if (reusableName != null) {
                val existing = fontsByName[reusableName]
                fontsByName[reusableName] = if (existing == null) {
                    created += 1
                    archived.toCustomFont(fileNameOverride = reusableName, exportedAt = exportedAt)
                } else {
                    updated += 1
                    existing.copy(name = archived.name, dateAdded = BackupValidator.parseInstant(
                        archived.dateAdded, "font.dateAdded", exportedAt
                    ))
                }
                val names = fontNamesByFoldedName.getOrPut(BackupPaths.fontFileNameKey(reusableName)) { mutableListOf() }
                if (reusableName !in names) names.add(reusableName)
                renamedFonts[archived.fileName] = reusableName
                return
            }
            val newFileName = BackupPaths.uniqueSuffixedFontFileName(
                archived.fileName,
                fontsByName.keys + currentFontFiles.keys + filesToWrite.keys
            )
            fontsByName[newFileName] = archived.toCustomFont(
                fileNameOverride = newFileName,
                exportedAt = exportedAt
            )
            fontNamesByFoldedName.getOrPut(BackupPaths.fontFileNameKey(newFileName)) {
                mutableListOf()
            }.add(newFileName)
            filesToWrite[newFileName] = incomingBytes
            renamedFonts[archived.fileName] = newFileName
            created += 1
        }

        manifestFonts.forEach { archived ->
            val incomingBytes = backupFontFiles[archived.fileName] ?: return@forEach
            val foldedName = BackupPaths.fontFileNameKey(archived.fileName)
            val existingNames = fontNamesByFoldedName[foldedName].orEmpty()
            val existingName = existingNames.singleOrNull()
            val existing = existingName?.let(fontsByName::get)
            val matchingFiles = currentFilesByFoldedName[foldedName].orEmpty()

            // Multiple local DB rows that differ only by case are already
            // ambiguous. Preserve every row and file, and give the archive its
            // own unoccupied name instead of selecting an arbitrary winner.
            if (existingNames.size > 1) {
                restoreWithSuffix(archived, incomingBytes)
                return@forEach
            }

            if (existing == null) {
                val reusableFile = matchingFiles.singleOrNull()
                if (reusableFile != null && reusableFile.value.size == incomingBytes.size && reusableFile.value.isNotEmpty() &&
                    BackupPaths.sha256(reusableFile.value) == BackupPaths.sha256(incomingBytes)
                ) {
                    val localFileName = reusableFile.key
                    fontsByName[localFileName] = archived.toCustomFont(
                        fileNameOverride = localFileName,
                        exportedAt = exportedAt
                    )
                    fontNamesByFoldedName.getOrPut(foldedName) { mutableListOf() }.add(localFileName)
                    if (localFileName != archived.fileName) {
                        renamedFonts[archived.fileName] = localFileName
                    }
                    created += 1
                    return@forEach
                }

                if (matchingFiles.isNotEmpty()) {
                    restoreWithSuffix(archived, incomingBytes)
                    return@forEach
                }

                val font = archived.toCustomFont(exportedAt = exportedAt)
                fontsByName[font.fileName] = font
                fontNamesByFoldedName.getOrPut(foldedName) { mutableListOf() }.add(font.fileName)
                filesToWrite[font.fileName] = incomingBytes
                created += 1
                return@forEach
            }

            val canonicalExistingName = requireNotNull(existingName)
            val exactExistingBytes = currentFontFiles[canonicalExistingName]
            if (exactExistingBytes == null) {
                if (matchingFiles.isEmpty()) {
                    // The DB row exists and no case-variant file occupies its
                    // name. Repair the missing file without changing its selector.
                    fontsByName[canonicalExistingName] = existing.copy(
                        name = archived.name,
                        dateAdded = BackupValidator.parseInstant(
                            archived.dateAdded,
                            "font.dateAdded",
                            exportedAt
                        )
                    )
                    filesToWrite[canonicalExistingName] = incomingBytes
                    if (canonicalExistingName != archived.fileName) {
                        renamedFonts[archived.fileName] = canonicalExistingName
                    }
                    updated += 1
                } else {
                    // A differently-cased file occupies the folded name. Do not
                    // copy it over the DB row's exact filename or retarget the row;
                    // either action can destroy bytes or break the local selector.
                    restoreWithSuffix(archived, incomingBytes)
                }
                return@forEach
            }

            if (
                exactExistingBytes.size == incomingBytes.size && exactExistingBytes.isNotEmpty() &&
                BackupPaths.sha256(exactExistingBytes) == BackupPaths.sha256(incomingBytes)
            ) {
                fontsByName[canonicalExistingName] = existing.copy(
                    name = archived.name,
                    dateAdded = BackupValidator.parseInstant(
                        archived.dateAdded,
                        "font.dateAdded",
                        exportedAt
                    )
                )
                if (canonicalExistingName != archived.fileName) {
                    renamedFonts[archived.fileName] = canonicalExistingName
                }
                updated += 1
            } else {
                restoreWithSuffix(archived, incomingBytes)
            }
        }

        return FontMerge(
            items = fontsByName.values.sortedBy { it.fileName },
            filesToWrite = filesToWrite,
            renamedFonts = renamedFonts,
            created = created,
            updated = updated
        )
    }

    /**
     * LWW on `lastModifiedAt`, matching [mergeWork]/[mergeQueues]: an incoming
     * deletion or rename only applies if it's not older than the local copy, and a
     * new-to-this-device deleted collection is suppressed by its own tombstone
     * rather than silently recreated.
     */
    private fun applyReplaceWork(existing: SavedWork, restored: SavedWork): SavedWork {
        return restored.copy(
            id = existing.id,
            hasEpub = existing.hasEpub || restored.hasEpub,
            downloadedAt = restored.downloadedAt ?: existing.downloadedAt,
            dateAdded = minInstant(existing.dateAdded, restored.dateAdded)
        )
    }

    private fun remapWorkId(raw: String, workIdRemap: Map<String, String>): String {
        val id = BackupPaths.normalizeIdForComparison(raw)
        return workIdRemap[id] ?: id
    }

    private fun replaceCollections(
        current: List<WorkCollection>,
        incoming: List<BackupCollection>,
        workIdRemap: Map<String, String> = emptyMap(),
        exportedAt: Instant? = null
    ): MergeItems<WorkCollection> {
        val collectionsById = current.associateByTo(linkedMapOf()) {
            BackupPaths.normalizeIdForComparison(it.id)
        }
        var created = 0
        var updated = 0
        val incomingIds = mutableSetOf<String>()
        incoming.forEach { archived ->
            val id = BackupPaths.canonicalUuid(archived.id, "collection.id")
            incomingIds += id
            val existing = collectionsById[id]
            val restored = archived.toWorkCollection(exportedAt = exportedAt)
            collectionsById[id] = restored.copy(
                workIds = restored.workIds.map { remapWorkId(it, workIdRemap) }.distinct()
            )
            if (existing == null) created += 1 else updated += 1
        }
        collectionsById.keys.toList().forEach { id ->
            if (id !in incomingIds) collectionsById.remove(id)
        }
        return MergeItems(collectionsById.values.sortedBy { it.name.lowercase() }, created, updated)
    }

    private fun mergeCollections(
        current: List<WorkCollection>,
        incoming: List<BackupCollection>,
        tombstoneIndex: TombstoneIndex,
        mode: BackupImportMode = BackupImportMode.RECONCILE,
        exportedAt: Instant? = null,
        now: Instant = Instant.now(),
        workIdRemap: Map<String, String> = emptyMap()
    ): MergeItems<WorkCollection> {
        val collectionsById = current.associateByTo(linkedMapOf()) {
            BackupPaths.normalizeIdForComparison(it.id)
        }
        val names = current.filterNot { it.isDeleted }.mapTo(mutableSetOf()) { it.name }
        var created = 0
        var updated = 0

        incoming.forEach { archived ->
            val id = BackupPaths.canonicalUuid(archived.id, "collection.id")
            val incomingModified = sanitizeArchivedLastModifiedAt(
                archived.lastModifiedAt,
                exportedAt,
                now
            ) ?: parseOptionalInstant(archived.dateAdded, exportedAt)
            val existing = collectionsById[id]

            if (existing == null) {
                if (archived.isDeleted == true) return@forEach
                when (tombstoneIndex.collectionResolution(id, incomingModified)) {
                    TombstoneResolution.SUPPRESS_STALE -> return@forEach
                    TombstoneResolution.REVIVE_NEWER,
                    TombstoneResolution.PRESERVE_AMBIGUOUS,
                    TombstoneResolution.NO_TOMBSTONE -> Unit
                }
                val restoredName = archived.name.uniqueName(names)
                val restored = archived.toWorkCollection(
                    nameOverride = restoredName,
                    exportedAt = exportedAt
                )
                collectionsById[id] = restored
                names += restoredName
                created += 1
            } else if (mode == BackupImportMode.MERGE) {
                // Add-only: keep the local name/fields. Still attach incoming
                // work IDs so a newly added work is not orphaned.
                val incomingWorkIds = archived.workIDs
                    .map { remapWorkId(it, workIdRemap) }
                    .distinct()
                    .filterNot { workId ->
                        tombstoneIndex.collectionMembershipResolution(
                            collectionMembershipRecordId(id, workId),
                            incomingModified
                        ) == TombstoneResolution.SUPPRESS_STALE
                    }
                val existingIds = existing.workIds
                    .map { BackupPaths.normalizeIdForComparison(it) }
                    .toSet()
                val added = incomingWorkIds.filter { it !in existingIds }
                val filled = fillCollectionFields(
                    existing, archived, incomingWins = false, exportedAt = exportedAt
                )
                val target = if (added.isNotEmpty()) {
                    filled.copy(workIds = filled.workIds + added)
                } else {
                    filled
                }
                if (target != existing) {
                    collectionsById[id] = target
                    updated += 1
                }
            } else {
                val localModified = existing.lastModifiedAt ?: existing.dateAdded
                if (!SyncMerge.shouldApplyIncoming(localModified, incomingModified)) {
                    val filled = fillCollectionFields(
                        existing, archived, incomingWins = false, exportedAt = exportedAt
                    )
                    if (filled != existing) {
                        collectionsById[id] = filled
                        updated += 1
                    }
                    return@forEach
                }
                val archivedIsDeleted = archived.isDeleted == true
                val mergedWorkIds = (existing.workIds + archived.workIDs)
                    .map { remapWorkId(it, workIdRemap) }
                    .distinct()
                    // A work the user explicitly removed from this collection locally
                    // must not silently come back just because an older backup still
                    // lists it as a member.
                    .filterNot { workId ->
                        tombstoneIndex.collectionMembershipResolution(
                            collectionMembershipRecordId(id, workId),
                            incomingModified
                        ) == TombstoneResolution.SUPPRESS_STALE
                    }
                val deletionState = restoredDeletionState(archived.isDeleted)
                val base = existing.copy(
                    name = if (archivedIsDeleted) existing.name else archived.name,
                    dateAdded = BackupValidator.parseInstant(
                        archived.dateAdded,
                        "collection.dateAdded",
                        exportedAt
                    ),
                    createdAt = minNullableInstant(
                        existing.createdAt,
                        parseOptionalInstant(archived.createdAt, exportedAt)
                    ),
                    workIds = mergedWorkIds,
                    description = archived.description ?: existing.description,
                    sortOrder = archived.sortOrder ?: existing.sortOrder,
                    lastModifiedAt = incomingModified ?: existing.lastModifiedAt,
                    syncStatusRaw = archived.syncStatusRaw ?: existing.syncStatusRaw,
                    isDeleted = deletionState.isDeleted,
                    deletedAt = if (deletionState.isDeleted) {
                        parseOptionalInstant(archived.deletedAt, exportedAt) ?: incomingModified
                    } else {
                        null
                    },
                    permanentDeletionScheduledAt = keptDeletionSchedule(
                        deletionState.permanentDeletionScheduledAt,
                        existing.isDeleted,
                        existing.permanentDeletionScheduledAt
                    )
                )
                collectionsById[id] = fillCollectionFields(
                    base, archived, incomingWins = true, exportedAt = exportedAt
                )
                if (!archivedIsDeleted) names += archived.name
                updated += 1
            }
        }

        return MergeItems(collectionsById.values.sortedBy { it.name.lowercase() }, created, updated)
    }

    private fun fillCollectionFields(
        existing: WorkCollection,
        archived: BackupCollection,
        incomingWins: Boolean,
        exportedAt: Instant?
    ): WorkCollection {
        val (chosenHue, chosenHex) = SyncMerge.chosenColor(
            local = existing.hue to existing.colorHex,
            incoming = archived.hue to archived.colorHex,
            incomingWins = incomingWins
        )
        val keepsOffline = if (archived.keepsWorksOffline != null && (incomingWins || existing.keepsWorksOffline == null)) {
            archived.keepsWorksOffline
        } else {
            existing.keepsWorksOffline
        }
        val onHome = if (archived.showsOnHome != null && (incomingWins || !existing.showsOnHome)) {
            archived.showsOnHome
        } else {
            existing.showsOnHome
        }
        val orderRaw = if (!archived.workOrderRaw.isNullOrEmpty() && (incomingWins || existing.workOrderRaw.isEmpty())) {
            archived.workOrderRaw
        } else {
            existing.workOrderRaw
        }
        return existing.copy(
            createdAt = minNullableInstant(
                existing.createdAt,
                parseOptionalInstant(archived.createdAt, exportedAt)
            ),
            syncStatusRaw = if (incomingWins) {
                archived.syncStatusRaw ?: existing.syncStatusRaw
            } else {
                existing.syncStatusRaw ?: archived.syncStatusRaw
            },
            hue = chosenHue,
            colorHex = chosenHex,
            keepsWorksOffline = keepsOffline,
            showsOnHome = onHome,
            workOrderRaw = orderRaw
        )
    }

    private fun mergeSavedSearches(
        current: List<SavedSearch>,
        incoming: List<BackupSavedSearch>,
        tombstoneIndex: TombstoneIndex,
        mode: BackupImportMode = BackupImportMode.RECONCILE,
        exportedAt: Instant? = null,
        now: Instant = Instant.now(),
        tombstonesById: MutableMap<String, SyncTombstone>
    ): MergeItems<SavedSearch> {
        val searchesById = current.associateByTo(linkedMapOf()) {
            BackupPaths.normalizeIdForComparison(it.id)
        }
        val names = current.mapTo(mutableSetOf()) { it.name }
        var created = 0
        var updated = 0

        incoming.forEach { archived ->
            val id = BackupPaths.canonicalUuid(archived.id, "savedSearch.id")
            if (mode != BackupImportMode.REPLACE_LIBRARY) {
                val incomingModified = BackupValidator.parseInstant(
                    archived.dateAdded,
                    "savedSearch.dateAdded",
                    exportedAt
                )
                if (tombstoneIndex.savedSearchResolution(id, incomingModified) ==
                    TombstoneResolution.SUPPRESS_STALE
                ) {
                    return@forEach
                }
            }
            val existing = searchesById[id]
            if (existing == null) {
                val restoredName = archived.name.uniqueName(names)
                searchesById[id] = archived.toSavedSearch(
                    nameOverride = restoredName,
                    exportedAt = exportedAt
                )
                names += restoredName
                created += 1
            } else {
                searchesById[id] = existing.copy(
                    name = archived.name,
                    dateAdded = BackupValidator.parseInstant(
                        archived.dateAdded,
                        "savedSearch.dateAdded",
                        exportedAt
                    ),
                    filtersJson = archived.filters.toString()
                )
                names += archived.name
                updated += 1
            }
        }

        // A search this device still has that a trusted tombstone says was deleted
        // elsewhere (iOS `applyTombstonesToExisting`). The loop above only declines
        // to add one back: the copy already here stayed visible, and was published
        // again on the next export, so the deletion could never settle between two
        // devices. The reading-log merges below already make this pass. Never in
        // Replace, which is "make this device look like the archive".
        if (mode != BackupImportMode.REPLACE_LIBRARY) {
            searchesById.entries.removeAll { (id, search) ->
                tombstoneIndex.savedSearchResolution(id, search.dateAdded) ==
                    TombstoneResolution.SUPPRESS_STALE
            }
        }

        if (mode == BackupImportMode.REPLACE_LIBRARY) {
            val incomingIds = incoming.mapTo(mutableSetOf()) {
                BackupPaths.canonicalUuid(it.id, "savedSearch.id")
            }
            searchesById.keys.toList().forEach { id ->
                if (id !in incomingIds) {
                    val omitted = searchesById.remove(id) ?: return@forEach
                    mintImmediateTombstone(
                        recordId = omitted.id,
                        recordType = SyncTombstoneRecordType.SAVED_SEARCH,
                        deletionReason = "savedSearchDeleted",
                        now = now,
                        tombstonesById = tombstonesById
                    )
                }
            }
        }

        return MergeItems(searchesById.values.sortedBy { it.name.lowercase() }, created, updated)
    }

    private fun mintImmediateTombstone(
        recordId: String,
        recordType: String,
        deletionReason: String,
        now: Instant,
        tombstonesById: MutableMap<String, SyncTombstone>
    ) {
        val signed = TombstoneSigning.sign(
            SyncTombstone(
                recordID = BackupPaths.normalizeIdForComparison(recordId),
                recordTypeRaw = recordType,
                createdAt = now,
                lastModifiedAt = now,
                deletionReason = deletionReason
            )
        )
        tombstonesById[BackupPaths.normalizeIdForComparison(signed.id)] = signed
    }

    private fun mergeQueues(
        currentQueues: List<ReadingQueue>,
        currentMemberships: List<ReadingQueueMembership>,
        currentQueueTagNames: Map<String, List<String>>,
        incomingQueues: List<BackupReadingQueue>,
        incomingMemberships: List<BackupReadingQueueMembership>,
        worksById: Map<String, SavedWork>,
        tombstoneIndex: TombstoneIndex,
        mode: BackupImportMode = BackupImportMode.RECONCILE,
        exportedAt: Instant? = null,
        now: Instant = Instant.now(),
        workIdRemap: Map<String, String> = emptyMap()
    ): QueueMerge {
        val queuesById = currentQueues.associateByTo(linkedMapOf()) {
            BackupPaths.normalizeIdForComparison(it.id)
        }
        var queuesCreated = 0
        var queuesUpdated = 0

        // iOS folds each queue's *membership* timestamps into the conflict clock
        // (`ReadingQueue.effectiveModifiedAt(memberships:)`). Passing an empty list
        // here — which is what this used to do — makes a queue whose memberships
        // changed but whose `dateUpdated` did not pick a different winner on
        // Android than on iOS, from the very same file.
        val incomingMembershipTimes = incomingMemberships
            .groupBy { BackupPaths.normalizeIdForComparison(it.queueID) }
            .mapValues { (_, memberships) ->
                memberships.mapNotNull { membership ->
                    parseOptionalInstant(membership.lastModifiedAt, exportedAt)
                        ?: parseOptionalInstant(
                            membership.queuedAt.takeIf { it.isNotBlank() },
                            exportedAt
                        )
                }
            }
        val localMembershipTimes = currentMemberships
            .groupBy { BackupPaths.normalizeIdForComparison(it.queueID) }
            .mapValues { (_, memberships) -> memberships.map { it.lastModifiedAt ?: it.queuedAt } }

        // The system queue is matched by *kind*, never by id: each platform mints
        // its own UUID for it (`ReadingQueueRepository.ensureSystemQueue`), so
        // matching on id alone inserts a *second* "Saved for Later" — and since
        // system queues cannot be renamed or deleted, the user is left with a
        // permanently split shelf. iOS special-cases the same way.
        val localSystemQueueId = currentQueues
            .firstOrNull { it.kindRaw == ReadingQueueKind.SAVED_FOR_LATER }
            ?.let { BackupPaths.normalizeIdForComparison(it.id) }
        val queueIdRemap = mutableMapOf<String, String>()
        val queueTagNamesByQueueId = currentQueueTagNames
            .mapKeys { BackupPaths.normalizeIdForComparison(it.key) }
            .mapValuesTo(linkedMapOf()) { it.value.normalizedNames() }

        incomingQueues.forEach { archived ->
            val incomingId = BackupPaths.canonicalUuid(archived.id, "queue.id")
            val isSystemQueue = archived.kindRaw == ReadingQueueKind.SAVED_FOR_LATER
            val id = if (isSystemQueue && localSystemQueueId != null) localSystemQueueId else incomingId
            queueIdRemap[incomingId] = id

            val incomingModified = SyncMerge.effectiveQueueModifiedAt(
                queueUpdatedAt = parseOptionalInstant(
                    archived.dateUpdated.takeIf { it.isNotBlank() },
                    exportedAt
                ),
                lastMembershipChangedAt = parseOptionalInstant(
                    archived.lastMembershipChangedAt,
                    exportedAt
                ),
                membershipModifiedAts = incomingMembershipTimes[incomingId].orEmpty()
            ) ?: parseOptionalInstant(archived.dateCreated.takeIf { it.isNotBlank() }, exportedAt)

            val existing = queuesById[id]
            if (existing == null) {
                when (tombstoneIndex.queueResolution(id, incomingModified)) {
                    TombstoneResolution.SUPPRESS_STALE -> return@forEach
                    TombstoneResolution.REVIVE_NEWER,
                    TombstoneResolution.PRESERVE_AMBIGUOUS,
                    TombstoneResolution.NO_TOMBSTONE -> Unit
                }
                val created = archived.toReadingQueue(exportedAt)
                queuesById[id] = if (isSystemQueue) {
                    // iOS `ensureSavedForLaterQueue` creates the system queue at
                    // -1000 and does not copy an archived sort onto it.
                    created.copy(sortOrder = ReadingQueueKind.SAVED_FOR_LATER_SORT_ORDER)
                } else {
                    created
                }
                queuesCreated += 1
            } else if (mode == BackupImportMode.MERGE) {
                // Keep local queue name / fields. New memberships still insert below.
                val filled = fillQueueFields(existing, archived, incomingWins = false)
                if (filled != existing) {
                    queuesById[id] = filled
                    queuesUpdated += 1
                }
            } else {
                val localModified = SyncMerge.effectiveQueueModifiedAt(
                    queueUpdatedAt = existing.dateUpdated,
                    lastMembershipChangedAt = existing.lastMembershipChangedAt,
                    membershipModifiedAts = localMembershipTimes[id].orEmpty()
                )
                if (SyncMerge.shouldApplyIncoming(localModified, incomingModified)) {
                    val restored = archived.toReadingQueue(exportedAt)
                    val finalIsDeleted = !isSystemQueue && restored.isDeleted
                    val deletionState = restoredDeletionState(finalIsDeleted)
                    val base = restored.copy(
                        // Keep the local identity: local memberships already point
                        // at it, and for the system queue the incoming id is a
                        // different platform's UUID entirely.
                        id = existing.id,
                        // iOS pins the system queue's name and kind rather than let
                        // a restore rename it, and nothing may soft-delete it —
                        // there is no UI that could ever bring it back.
                        name = if (isSystemQueue) ReadingQueueKind.SAVED_FOR_LATER_NAME else restored.name,
                        kindRaw = if (isSystemQueue) ReadingQueueKind.SAVED_FOR_LATER else restored.kindRaw,
                        // Archived sort is not applied to Saved for Later. iOS
                        // keeps `min(local, -1000)` from ensure.
                        sortOrder = if (isSystemQueue) {
                            minOf(existing.sortOrder, ReadingQueueKind.SAVED_FOR_LATER_SORT_ORDER)
                        } else {
                            restored.sortOrder
                        },
                        isDeleted = deletionState.isDeleted,
                        deletedAt = if (deletionState.isDeleted) restored.deletedAt else null,
                        permanentDeletionScheduledAt = keptDeletionSchedule(
                            deletionState.permanentDeletionScheduledAt,
                            existing.isDeleted,
                            existing.permanentDeletionScheduledAt
                        ),
                        dateCreated = minInstant(existing.dateCreated, restored.dateCreated)
                    )
                    val filled = fillQueueFields(existing, archived, incomingWins = true)
                    queuesById[id] = base.copy(
                        hue = filled.hue,
                        colorHex = filled.colorHex,
                        isPinned = filled.isPinned,
                        keepsWorksOffline = filled.keepsWorksOffline,
                        notes = filled.notes
                    )
                    queuesUpdated += 1
                } else {
                    val filled = fillQueueFields(existing, archived, incomingWins = false)
                    if (filled != existing) {
                        queuesById[id] = filled
                        queuesUpdated += 1
                    }
                }
            }
            if (id in queuesById) {
                queueTagNamesByQueueId[id] = if (mode == BackupImportMode.REPLACE_LIBRARY) {
                    archived.tagNames.orEmpty().normalizedNames()
                } else {
                    (queueTagNamesByQueueId[id].orEmpty() + archived.tagNames.orEmpty())
                        .normalizedNames()
                }
            }
        }

        val membershipsById = currentMemberships.associateByTo(linkedMapOf()) {
            BackupPaths.normalizeIdForComparison(it.id)
        }
        var membershipsCreated = 0
        var membershipsUpdated = 0
        var membershipsSuppressed = 0

        incomingMemberships.forEach { archived ->
            val id = BackupPaths.canonicalUuid(archived.id, "membership.id")
            val incomingQueueId = BackupPaths.canonicalUuid(archived.queueID, "membership.queueID")
            // Follow the system-queue remap above, or these memberships would point
            // at the *other* platform's queue UUID and be dropped on the next line.
            val queueId = queueIdRemap[incomingQueueId] ?: incomingQueueId
            val workId = remapWorkId(
                BackupPaths.canonicalUuid(archived.workID, "membership.workID"),
                workIdRemap
            )
            if (queueId !in queuesById) return@forEach
            if (workId !in worksById) return@forEach

            val incomingModified = sanitizeArchivedLastModifiedAt(
                archived.lastModifiedAt,
                exportedAt,
                now
            ) ?: parseOptionalInstant(archived.queuedAt.takeIf { it.isNotBlank() }, exportedAt)

            when (tombstoneIndex.membershipResolution(id, incomingModified)) {
                TombstoneResolution.SUPPRESS_STALE -> {
                    membershipsSuppressed += 1
                    return@forEach
                }
                else -> Unit
            }

            val existing = membershipsById[id]
            val restored = archived.toReadingQueueMembership(exportedAt)
                .copy(queueID = queueId, workID = workId)
            if (existing == null) {
                membershipsById[id] = restored
                membershipsCreated += 1
            } else if (mode != BackupImportMode.MERGE &&
                SyncMerge.shouldApplyIncoming(existing.lastModifiedAt ?: existing.queuedAt, incomingModified)
            ) {
                membershipsById[id] = restored
                membershipsUpdated += 1
            }
        }

        if (mode == BackupImportMode.REPLACE_LIBRARY) {
            val incomingQueueIds = incomingQueues.mapTo(mutableSetOf()) { archived ->
                val incomingId = BackupPaths.canonicalUuid(archived.id, "queue.id")
                queueIdRemap[incomingId] ?: incomingId
            }
            queuesById.keys.toList().forEach { id ->
                if (id in incomingQueueIds) return@forEach
                val existing = queuesById[id] ?: return@forEach
                if (existing.kindRaw == ReadingQueueKind.SAVED_FOR_LATER) return@forEach
                queuesById.remove(id)
                queueTagNamesByQueueId.remove(id)
            }
            val incomingMembershipIds = incomingMemberships.mapTo(mutableSetOf()) {
                BackupPaths.canonicalUuid(it.id, "membership.id")
            }
            val systemQueueIds = queuesById.values
                .filter { it.kindRaw == ReadingQueueKind.SAVED_FOR_LATER }
                .mapTo(HashSet()) { BackupPaths.normalizeIdForComparison(it.id) }
            membershipsById.keys.toList().forEach { id ->
                val membership = membershipsById.getValue(id)
                if (id !in incomingMembershipIds &&
                    BackupPaths.normalizeIdForComparison(membership.queueID) !in systemQueueIds
                ) membershipsById.remove(id)
            }
        }

        return QueueMerge(
            queues = queuesById.values.sortedBy { it.sortOrder },
            memberships = membershipsById.values.sortedBy { it.sortOrderInQueue },
            queueTagNamesByQueueId = queueTagNamesByQueueId,
            queuesCreated = queuesCreated,
            queuesUpdated = queuesUpdated,
            membershipsCreated = membershipsCreated,
            membershipsUpdated = membershipsUpdated,
            membershipsSuppressed = membershipsSuppressed
        )
    }

    private fun fillQueueFields(
        existing: ReadingQueue,
        archived: BackupReadingQueue,
        incomingWins: Boolean
    ): ReadingQueue {
        val (chosenHue, chosenHex) = SyncMerge.chosenColor(
            local = existing.hue to existing.colorHex,
            incoming = archived.hue to archived.colorHex,
            incomingWins = incomingWins
        )
        val pinned = if (archived.isPinned != null && (incomingWins || !existing.isPinned)) {
            archived.isPinned
        } else {
            existing.isPinned
        }
        val keepsOffline = if (archived.keepsWorksOffline != null && (incomingWins || existing.keepsWorksOffline == null)) {
            archived.keepsWorksOffline
        } else {
            existing.keepsWorksOffline
        }
        val queueNotes = if (archived.notes != null && (incomingWins || existing.notes == null)) {
            archived.notes
        } else {
            existing.notes
        }
        return existing.copy(
            hue = chosenHue,
            colorHex = chosenHex,
            isPinned = pinned,
            keepsWorksOffline = keepsOffline,
            notes = queueNotes
        )
    }

    private fun mergeReadingSessions(
        current: List<ReadingSessionEntity>,
        incoming: List<BackupReadingSession>,
        tombstoneIndex: TombstoneIndex,
        mode: BackupImportMode,
        exportedAt: Instant?,
        workIdRemap: Map<String, String>,
        now: Instant,
        tombstonesById: MutableMap<String, SyncTombstone>
    ): List<ReadingSessionEntity> {
        val byId = current.associateByTo(linkedMapOf()) {
            BackupPaths.normalizeIdForComparison(it.id)
        }
        val resolvedLocalIds = mutableSetOf<String>()
        incoming.forEach { archived ->
            val id = BackupPaths.canonicalUuid(archived.id, "readingSession.id")
            val restored = archived.toReadingSession(exportedAt).let { session ->
                val archivedWorkId = BackupPaths.normalizeIdForComparison(session.workID)
                session.copy(workID = workIdRemap[archivedWorkId] ?: session.workID)
            }
            val incomingModified = parseOptionalInstant(archived.lastModifiedAt, exportedAt)
                ?: restored.lastModifiedAt
            if (mode != BackupImportMode.REPLACE_LIBRARY &&
                tombstoneIndex.readingSessionResolution(id, incomingModified) ==
                TombstoneResolution.SUPPRESS_STALE
            ) return@forEach

            val existing = byId[id]
            if (existing == null) {
                byId[id] = restored
                resolvedLocalIds += id
            } else {
                resolvedLocalIds += id
                if (mode != BackupImportMode.MERGE &&
                    SyncMerge.shouldApplyIncoming(existing.lastModifiedAt, incomingModified)
                ) byId[id] = restored.copy(id = existing.id)
            }
        }

        if (mode != BackupImportMode.REPLACE_LIBRARY) {
            byId.entries.removeAll { (id, session) ->
                tombstoneIndex.readingSessionResolution(id, session.lastModifiedAt) ==
                    TombstoneResolution.SUPPRESS_STALE
            }
        } else {
            current.forEach { session ->
                val id = BackupPaths.normalizeIdForComparison(session.id)
                if (id !in resolvedLocalIds) {
                    byId.remove(id)
                    mintImmediateTombstone(
                        session.id,
                        SyncTombstoneRecordType.READING_SESSION,
                        "readingSessionDeleted",
                        now,
                        tombstonesById
                    )
                }
            }
        }
        return byId.values.sortedByDescending { it.startedAt }
    }

    private fun mergeReadingFavorites(
        current: List<ReadingFavoriteEntity>,
        incoming: List<BackupReadingFavorite>,
        tombstoneIndex: TombstoneIndex,
        mode: BackupImportMode,
        exportedAt: Instant?,
        workIdRemap: Map<String, String>,
        now: Instant,
        tombstonesById: MutableMap<String, SyncTombstone>
    ): List<ReadingFavoriteEntity> {
        val byId = current.associateByTo(linkedMapOf()) {
            BackupPaths.normalizeIdForComparison(it.id)
        }
        val byTarget = current.associateByTo(linkedMapOf()) { "${it.kindRaw}|${it.targetKey}" }
        val resolvedLocalIds = mutableSetOf<String>()
        incoming.forEach { archived ->
            val archivedId = BackupPaths.canonicalUuid(archived.id, "readingFavorite.id")
            val resolvedTarget = if (archived.kindRaw == "work") {
                runCatching { BackupPaths.canonicalUuid(archived.targetKey, "readingFavorite.targetKey") }
                    .getOrNull()
                    ?.let { workIdRemap[it] }
                    ?: archived.targetKey
            } else {
                archived.targetKey
            }
            val incomingFavorite = archived.toReadingFavorite(exportedAt)
                .copy(targetKey = resolvedTarget)
            val incomingModified = parseOptionalInstant(archived.lastModifiedAt, exportedAt)
                ?: incomingFavorite.lastModifiedAt
            if (mode != BackupImportMode.REPLACE_LIBRARY &&
                tombstoneIndex.readingFavoriteResolution(archivedId, incomingModified) ==
                TombstoneResolution.SUPPRESS_STALE
            ) return@forEach

            val targetKey = "${archived.kindRaw}|$resolvedTarget"
            val direct = byId[archivedId]
            val existing = direct ?: byTarget[targetKey]
            if (existing == null) {
                byId[archivedId] = incomingFavorite
                byTarget[targetKey] = incomingFavorite
                resolvedLocalIds += archivedId
            } else {
                val localId = BackupPaths.normalizeIdForComparison(existing.id)
                resolvedLocalIds += localId
                if ((mode != BackupImportMode.MERGE || direct == null) &&
                    SyncMerge.shouldApplyIncoming(existing.lastModifiedAt, incomingModified)
                ) {
                    val restored = incomingFavorite.copy(
                        id = existing.id,
                        kindRaw = archived.kindRaw,
                        targetKey = resolvedTarget,
                        createdAt = minInstant(existing.createdAt, incomingFavorite.createdAt)
                    )
                    byId[localId] = restored
                    byTarget[targetKey] = restored
                }
            }
        }

        if (mode != BackupImportMode.REPLACE_LIBRARY) {
            byId.entries.removeAll { (id, favorite) ->
                tombstoneIndex.readingFavoriteResolution(id, favorite.lastModifiedAt) ==
                    TombstoneResolution.SUPPRESS_STALE
            }
        } else {
            current.forEach { favorite ->
                val id = BackupPaths.normalizeIdForComparison(favorite.id)
                if (id !in resolvedLocalIds) {
                    byId.remove(id)
                    mintImmediateTombstone(
                        favorite.id,
                        SyncTombstoneRecordType.READING_FAVORITE,
                        "readingFavoriteDeleted",
                        now,
                        tombstonesById
                    )
                }
            }
        }
        return byId.values.sortedByDescending { it.createdAt }
    }

    private fun mergeFandomReadWatermarks(
        current: List<FandomReadWatermarkEntity>,
        incoming: List<BackupFandomReadWatermark>,
        tombstoneIndex: TombstoneIndex,
        mode: BackupImportMode,
        exportedAt: Instant?,
        now: Instant,
        tombstonesById: MutableMap<String, SyncTombstone>
    ): List<FandomReadWatermarkEntity> {
        val byId = current.associateByTo(linkedMapOf()) {
            BackupPaths.normalizeIdForComparison(it.id)
        }
        val byName = current.associateByTo(linkedMapOf()) { it.fandomName }
        val resolvedLocalIds = mutableSetOf<String>()
        incoming.forEach { archived ->
            val archivedId = BackupPaths.canonicalUuid(archived.id, "fandomReadWatermark.id")
            val incomingWatermark = archived.toFandomReadWatermark(exportedAt)
            val incomingModified = parseOptionalInstant(archived.lastModifiedAt, exportedAt)
                ?: incomingWatermark.lastModifiedAt
            if (mode != BackupImportMode.REPLACE_LIBRARY &&
                tombstoneIndex.fandomReadWatermarkResolution(archivedId, incomingModified) ==
                TombstoneResolution.SUPPRESS_STALE
            ) return@forEach

            val direct = byId[archivedId]
            val existing = direct ?: byName[archived.fandomName]
            if (existing == null) {
                byId[archivedId] = incomingWatermark
                byName[archived.fandomName] = incomingWatermark
                resolvedLocalIds += archivedId
            } else {
                val localId = BackupPaths.normalizeIdForComparison(existing.id)
                resolvedLocalIds += localId
                if ((mode != BackupImportMode.MERGE || direct == null) &&
                    SyncMerge.shouldApplyIncoming(existing.lastModifiedAt, incomingModified)
                ) {
                    val restored = incomingWatermark.copy(id = existing.id)
                    byId[localId] = restored
                    byName[archived.fandomName] = restored
                }
            }
        }

        if (mode != BackupImportMode.REPLACE_LIBRARY) {
            byId.entries.removeAll { (id, watermark) ->
                tombstoneIndex.fandomReadWatermarkResolution(id, watermark.lastModifiedAt) ==
                    TombstoneResolution.SUPPRESS_STALE
            }
        } else {
            current.forEach { watermark ->
                val id = BackupPaths.normalizeIdForComparison(watermark.id)
                if (id !in resolvedLocalIds) {
                    byId.remove(id)
                    mintImmediateTombstone(
                        watermark.id,
                        SyncTombstoneRecordType.FANDOM_READ_WATERMARK,
                        "fandomReadWatermarkDeleted",
                        now,
                        tombstonesById
                    )
                }
            }
        }
        return byId.values.sortedBy { it.fandomName }
    }

    private fun mergeAnnotations(
        current: List<ReadingAnnotation>,
        incoming: List<BackupAnnotation>,
        worksById: Map<String, SavedWork>,
        tombstoneIndex: TombstoneIndex,
        mode: BackupImportMode = BackupImportMode.RECONCILE,
        exportedAt: Instant? = null,
        now: Instant = Instant.now(),
        workIdRemap: Map<String, String> = emptyMap()
    ): AnnotationMerge {
        val byId = current.associateByTo(linkedMapOf()) {
            BackupPaths.normalizeIdForComparison(it.id)
        }
        var created = 0
        var updated = 0
        var suppressed = 0

        incoming.forEach { archived ->
            val id = BackupPaths.canonicalUuid(archived.id, "annotation.id")
            val workId = remapWorkId(
                BackupPaths.canonicalUuid(archived.workID, "annotation.workID"),
                workIdRemap
            )
            // Never orphan annotations without a work in this restore.
            if (workId !in worksById) return@forEach
            // A pending-deletion annotation is a *tombstone*, not noise: dropping it
            // here (as this used to) means a highlight deleted on iOS silently comes
            // back on Android. iOS assigns `isPendingDeletion` through instead, and
            // the LWW check below decides whether the deletion actually wins.

            val incomingModified = sanitizeArchivedLastModifiedAt(
                archived.lastModifiedAt,
                exportedAt,
                now
            ) ?: parseOptionalInstant(archived.createdAt.takeIf { it.isNotBlank() }, exportedAt)
                ?: Instant.EPOCH

            when (tombstoneIndex.annotationResolution(id, incomingModified)) {
                TombstoneResolution.SUPPRESS_STALE -> {
                    suppressed += 1
                    return@forEach
                }
                else -> Unit
            }

            val existing = byId[id]
            val restored = archived.toReadingAnnotation(exportedAt).copy(workID = workId)
            if (existing == null) {
                byId[id] = restored
                created += 1
            } else if (mode == BackupImportMode.MERGE) {
                // Keep local note / locator / color. New ids still insert above.
            } else if (mode == BackupImportMode.REPLACE_LIBRARY ||
                SyncMerge.shouldApplyIncoming(existing.effectiveLastModifiedAt, incomingModified)
            ) {
                byId[id] = restored.copy(
                    createdAt = minInstant(existing.createdAt, restored.createdAt)
                )
                updated += 1
            }
        }

        if (mode == BackupImportMode.REPLACE_LIBRARY) {
            val incomingIds = incoming.mapTo(mutableSetOf()) {
                BackupPaths.canonicalUuid(it.id, "annotation.id")
            }
            byId.keys.toList().forEach { id ->
                if (id !in incomingIds) byId.remove(id)
            }
        }

        return AnnotationMerge(
            items = byId.values.sortedBy { it.createdAt },
            created = created,
            updated = updated,
            suppressed = suppressed
        )
    }

    private fun Map<String, ByteArray>.normalizedWorkFileMap(): Map<String, ByteArray> {
        return mapKeys { BackupPaths.normalizeIdForComparison(it.key) }
    }

    private fun BackupSettingsPayload.retargetRenamedFont(
        renamedFonts: Map<String, String>
    ): BackupSettingsPayload {
        if (!readerFontID.startsWith("custom:")) return this
        val fileName = readerFontID.removePrefix("custom:")
        val newFileName = renamedFonts[fileName] ?: return this
        return copy(readerFontID = "custom:$newFileName")
    }

    private fun String.uniqueName(existingNames: Set<String>): String {
        if (this !in existingNames) return this
        var index = 1
        while (true) {
            val candidate = "$this (Restored${if (index == 1) "" else " $index"})"
            if (candidate !in existingNames) return candidate
            index += 1
        }
    }

    private fun mergeStringLists(a: List<String>, b: List<String>): List<String> {
        return (a + b).normalizedNames()
    }

    private fun parseOptionalInstant(raw: String?, exportedAt: Instant? = null): Instant? {
        val value = raw?.takeIf { it.isNotBlank() } ?: return null
        return runCatching { BackupValidator.parseInstant(value, "timestamp", exportedAt) }.getOrNull()
    }

    /**
     * Ledger companion: `min(value, exportedAt)`, and drop timestamps more than
     * 24h in the future so a forged clock cannot win LWW. [parseInstant] already
     * rejects `> now+24h` at the decode boundary; this remains a second filter
     * for callers that swallow [BackupError.InvalidDate].
     */
    internal fun sanitizeArchivedLastModifiedAt(
        raw: String?,
        exportedAt: Instant?,
        now: Instant
    ): Instant? {
        val value = parseOptionalInstant(raw, exportedAt) ?: return null
        if (value.isAfter(now.plus(FUTURE_CLOCK_SKEW))) return null
        return if (exportedAt != null && value.isAfter(exportedAt)) exportedAt else value
    }

    /**
     * Prefer a sanitized `lastModifiedAt`. A present-but-rejected future clock
     * does not fall back to `dateAdded` (that would still let the attacker win).
     * A missing `lastModifiedAt` falls back to `dateAdded` so existing archives
     * keep their previous LWW behaviour.
     */
    private fun resolveIncomingLastModifiedAt(
        lastModifiedAt: String?,
        dateAdded: String?,
        exportedAt: Instant?,
        now: Instant
    ): Instant? {
        if (!lastModifiedAt.isNullOrBlank()) {
            return sanitizeArchivedLastModifiedAt(lastModifiedAt, exportedAt, now)
        }
        return sanitizeArchivedLastModifiedAt(dateAdded, exportedAt, now)
            ?: parseOptionalInstant(dateAdded, exportedAt)
    }

    private fun minInstant(a: Instant, b: Instant): Instant = if (a.isBefore(b)) a else b

    private fun minNullableInstant(a: Instant?, b: Instant?): Instant? = when {
        a == null -> b
        b == null -> a
        else -> minInstant(a, b)
    }

    private fun maxInstant(a: Instant?, b: Instant?): Instant? {
        return when {
            a == null -> b
            b == null -> a
            a.isAfter(b) -> a
            else -> b
        }
    }

    private data class MergeItems<T>(
        val items: List<T>,
        val created: Int,
        val updated: Int
    )

    private data class FontMerge(
        val items: List<CustomFont>,
        val filesToWrite: Map<String, ByteArray>,
        val renamedFonts: Map<String, String>,
        val created: Int,
        val updated: Int
    )

    private data class QueueMerge(
        val queues: List<ReadingQueue>,
        val memberships: List<ReadingQueueMembership>,
        val queueTagNamesByQueueId: Map<String, List<String>>,
        val queuesCreated: Int,
        val queuesUpdated: Int,
        val membershipsCreated: Int,
        val membershipsUpdated: Int,
        val membershipsSuppressed: Int
    )

    private data class AnnotationMerge(
        val items: List<ReadingAnnotation>,
        val created: Int,
        val updated: Int,
        val suppressed: Int
    )

    private val FUTURE_CLOCK_SKEW: Duration = Duration.ofHours(24)

    /**
     * Queued-work half of Apple `ReadingQueueService.normalize`. A membership
     * sets `isQueuedForLater`. A queued work whose EPUB is in this restore
     * becomes `preserved` (and gains `preservedAt` only when the archive had
     * none). Unknown metadata that still needs an AO3 refresh becomes
     * `pending`. Works with no membership are left alone so a pass-through
     * preservation status is not rewritten to `notPreserved`.
     *
     * ponytail: iOS's second pass is not ported. iOS also clears the flag of a
     * work that claims it and is in no queue, so a work taken out of its last
     * queue on another device stops being queued. Older Android data holds
     * queued works that carry the flag and no membership at all
     * (`restoreKeepsAQueueOnlyWorkOutOfTheLibrary`); cleared, they would be in
     * neither the library nor a queue. Port it once those have memberships.
     */
    private fun normalizeQueuedWorks(
        worksById: MutableMap<String, SavedWork>,
        memberships: List<ReadingQueueMembership>,
        epubIds: Set<String>,
        now: Instant,
        reconcilePreservation: Boolean
    ) {
        val queuedIds = memberships.mapTo(mutableSetOf()) {
            BackupPaths.normalizeIdForComparison(it.workID)
        }
        for ((id, work) in worksById) {
            if (BackupPaths.normalizeIdForComparison(id) !in queuedIds) continue
            if (!reconcilePreservation) {
                worksById[id] = work.copy(isQueuedForLater = true)
                continue
            }
            val hasFile = work.hasEpub &&
                BackupPaths.normalizeIdForComparison(work.id) in epubIds
            var status = work.epubPreservationStatusRaw
            var preservedAt = work.preservedAt
            if (hasFile) {
                if (status != "preserving") status = "preserved"
                if (preservedAt == null) preservedAt = now
            } else if (status == null || status == "notPreserved") {
                status = "queued"
            }
            var metadata = work.metadataSyncStatusRaw
            if ((metadata == null || metadata == "unknown") && iosNeedsMetadataRefresh(work, now)) {
                metadata = "pending"
            }
            worksById[id] = work.copy(
                isQueuedForLater = true,
                epubPreservationStatusRaw = status,
                preservedAt = preservedAt,
                metadataSyncStatusRaw = metadata
            )
        }
    }

    /** Apple `SavedWork.needsAO3Refresh`, used only by [normalizeQueuedWorks]. */
    private fun iosNeedsMetadataRefresh(work: SavedWork, now: Instant): Boolean {
        if (work.ao3Unavailable) return false
        val attempt = work.lastTagRefreshAttemptAt
        if (attempt != null && Duration.between(attempt, now) < Duration.ofHours(24)) return false
        val hasCategorizedTags = work.workFandoms.isNotEmpty() ||
            work.workCharacters.isNotEmpty() ||
            work.workRelationships.isNotEmpty() ||
            work.workFreeforms.isNotEmpty()
        val missingCardStats = work.workWarnings.isEmpty() &&
            work.workCategories.isEmpty() &&
            work.language.isEmpty() &&
            work.wordCount == 0
        val source = work.sourceUrl.lowercase()
        val hasAo3Source = work.ao3WorkID != null ||
            source.contains("archiveofourown.org") ||
            source.contains("ao3.org")
        return !work.workTagsFetched ||
            !hasCategorizedTags ||
            missingCardStats ||
            work.chapters.isEmpty() ||
            (work.authorIdentitiesJSON.isEmpty() && hasAo3Source)
    }

    /**
     * Apple restore derives `lastMembershipChangedAt` from membership clocks
     * and pins Saved for Later at [ReadingQueueKind.SAVED_FOR_LATER_SORT_ORDER].
     */
    private fun finishRestoredQueues(
        queues: List<ReadingQueue>,
        memberships: List<ReadingQueueMembership>
    ): List<ReadingQueue> {
        val byQueue = memberships.groupBy { BackupPaths.normalizeIdForComparison(it.queueID) }
        return queues.map { queue ->
            val pinned = if (queue.kindRaw == ReadingQueueKind.SAVED_FOR_LATER) {
                val sort = minOf(queue.sortOrder, ReadingQueueKind.SAVED_FOR_LATER_SORT_ORDER)
                if (sort == queue.sortOrder) queue else queue.copy(sortOrder = sort)
            } else {
                queue
            }
            val times = byQueue[BackupPaths.normalizeIdForComparison(pinned.id)]
                .orEmpty()
                .map { it.lastModifiedAt ?: it.queuedAt }
            val bumped = (listOfNotNull(pinned.lastMembershipChangedAt) + times).maxOrNull()
            if (bumped != null && bumped != pinned.lastMembershipChangedAt) {
                pinned.copy(lastMembershipChangedAt = bumped)
            } else {
                pinned
            }
        }.sortedBy { it.sortOrder }
    }
}

/** Apple `SyncMerge` helpers used by backup restore. */
object SyncMerge {
    fun chosenColor(
        local: Pair<Double?, String?>,
        incoming: Pair<Double?, String?>,
        incomingWins: Boolean
    ): Pair<Double?, String?> {
        val incomingHue = incoming.first ?: return local
        if (!incomingWins && local.first != null) return local
        if (incoming.second == null && local.second != null && local.first != null &&
            kotlin.math.abs(local.first!! - incomingHue) < 0.01) return local
        return incomingHue to incoming.second
    }

    fun shouldApplyIncoming(localModifiedAt: Instant?, incomingModifiedAt: Instant?): Boolean {
        if (incomingModifiedAt == null) return false
        if (localModifiedAt == null) return true
        return !incomingModifiedAt.isBefore(localModifiedAt)
    }

    fun effectiveQueueModifiedAt(
        queueUpdatedAt: Instant?,
        lastMembershipChangedAt: Instant?,
        membershipModifiedAts: List<Instant>
    ): Instant? {
        return (listOfNotNull(queueUpdatedAt, lastMembershipChangedAt) + membershipModifiedAts)
            .maxOrNull()
    }

    fun tombstoneResolution(
        incomingModifiedAt: Instant?,
        tombstoneDeletedAt: Instant?
    ): TombstoneResolution {
        if (tombstoneDeletedAt == null) return TombstoneResolution.NO_TOMBSTONE
        if (incomingModifiedAt == null) return TombstoneResolution.PRESERVE_AMBIGUOUS
        return if (incomingModifiedAt.isAfter(tombstoneDeletedAt)) {
            TombstoneResolution.REVIVE_NEWER
        } else {
            TombstoneResolution.SUPPRESS_STALE
        }
    }
}

enum class TombstoneResolution {
    NO_TOMBSTONE,
    SUPPRESS_STALE,
    REVIVE_NEWER,
    PRESERVE_AMBIGUOUS
}

/**
 * Indexes local + archive tombstones for suppress/revive decisions.
 * Newest tombstone wins when several share an identity.
 */
internal class TombstoneIndex(
    tombstones: List<SyncTombstone>,
    private val exportedAt: Instant? = null,
    private val now: Instant = Instant.now()
) {
    private val workById = mutableMapOf<String, SyncTombstone>()
    private val workByAo3Id = mutableMapOf<Int, SyncTombstone>()
    private val workBySourceUrl = mutableMapOf<String, SyncTombstone>()
    private val queueById = mutableMapOf<String, SyncTombstone>()
    private val membershipById = mutableMapOf<String, SyncTombstone>()
    private val annotationById = mutableMapOf<String, SyncTombstone>()
    private val collectionById = mutableMapOf<String, SyncTombstone>()
    private val collectionMembershipById = mutableMapOf<String, SyncTombstone>()
    private val bookmarkById = mutableMapOf<String, SyncTombstone>()
    private val savedSearchById = mutableMapOf<String, SyncTombstone>()
    private val readingSessionById = mutableMapOf<String, SyncTombstone>()
    private val readingFavoriteById = mutableMapOf<String, SyncTombstone>()
    private val fandomReadWatermarkById = mutableMapOf<String, SyncTombstone>()

    init {
        tombstones.forEach { tombstone ->
            val type = tombstone.recordTypeRaw
            val recordId = BackupPaths.normalizeIdForComparison(tombstone.recordID)
            when (type) {
                SyncTombstoneRecordType.SAVED_WORK -> {
                    indexNewest(workById, recordId, tombstone)
                    tombstone.ao3WorkID?.let { indexNewest(workByAo3Id, it, tombstone) }
                    canonicalSourceUrl(tombstone.sourceURL)?.let { url ->
                        indexNewest(workBySourceUrl, url, tombstone)
                    }
                }
                SyncTombstoneRecordType.READING_QUEUE ->
                    indexNewest(queueById, recordId, tombstone)
                SyncTombstoneRecordType.READING_QUEUE_MEMBERSHIP ->
                    indexNewest(membershipById, recordId, tombstone)
                SyncTombstoneRecordType.READING_ANNOTATION ->
                    indexNewest(annotationById, recordId, tombstone)
                SyncTombstoneRecordType.WORK_COLLECTION ->
                    indexNewest(collectionById, recordId, tombstone)
                SyncTombstoneRecordType.WORK_COLLECTION_MEMBERSHIP -> {
                    // android-v0.2.1-alpha stored "$collectionId:$workId"; rewrite
                    // to the XOR-UUID key so legacy rows still suppress resurrection.
                    val membershipKey = try {
                        BackupPaths.normalizeIdForComparison(
                            canonicalizeCollectionMembershipRecordId(tombstone.recordID)
                        )
                    } catch (_: IllegalArgumentException) {
                        recordId
                    }
                    indexNewest(collectionMembershipById, membershipKey, tombstone)
                }
                SyncTombstoneRecordType.BOOKMARK ->
                    indexNewest(bookmarkById, recordId, tombstone)
                SyncTombstoneRecordType.SAVED_SEARCH ->
                    indexNewest(savedSearchById, recordId, tombstone)
                SyncTombstoneRecordType.READING_SESSION ->
                    indexNewest(readingSessionById, recordId, tombstone)
                SyncTombstoneRecordType.READING_FAVORITE ->
                    indexNewest(readingFavoriteById, recordId, tombstone)
                SyncTombstoneRecordType.FANDOM_READ_WATERMARK ->
                    indexNewest(fandomReadWatermarkById, recordId, tombstone)
                else -> Unit
            }
        }
    }

    fun suppressesWorkResurrection(archived: BackupWork): Boolean {
        val byAo3 = archived.ao3WorkID?.let { workByAo3Id[it] }
        val byUrl = canonicalSourceUrl(archived.sourceURL)?.let { workBySourceUrl[it] }
        val byId = workById[BackupPaths.normalizeIdForComparison(archived.id)]
        val tombstone = byAo3 ?: byUrl ?: byId ?: return false
        val archivedModified = if (!archived.lastModifiedAt.isNullOrBlank()) {
            BackupMergeService.sanitizeArchivedLastModifiedAt(
                archived.lastModifiedAt,
                exportedAt,
                now
            ) ?: Instant.EPOCH
        } else {
            BackupMergeService.sanitizeArchivedLastModifiedAt(
                archived.dateAdded,
                exportedAt,
                now
            ) ?: Instant.EPOCH
        }
        return !tombstone.lastModifiedAt.isBefore(archivedModified)
    }

    fun queueResolution(id: String, incomingModifiedAt: Instant?): TombstoneResolution {
        return SyncMerge.tombstoneResolution(
            incomingModifiedAt = incomingModifiedAt,
            tombstoneDeletedAt = queueById[BackupPaths.normalizeIdForComparison(id)]?.lastModifiedAt
        )
    }

    fun membershipResolution(id: String, incomingModifiedAt: Instant?): TombstoneResolution {
        return SyncMerge.tombstoneResolution(
            incomingModifiedAt = incomingModifiedAt,
            tombstoneDeletedAt = membershipById[BackupPaths.normalizeIdForComparison(id)]
                ?.lastModifiedAt
        )
    }

    fun annotationResolution(id: String, incomingModifiedAt: Instant?): TombstoneResolution {
        return SyncMerge.tombstoneResolution(
            incomingModifiedAt = incomingModifiedAt,
            tombstoneDeletedAt = annotationById[BackupPaths.normalizeIdForComparison(id)]
                ?.lastModifiedAt
        )
    }

    /**
     * [id] is the XOR-UUID membership id from [collectionMembershipRecordId]
     * (iOS `collectionMembershipID`). Legacy colon-form tombstones are rewritten
     * to this key when the index is built.
     */
    fun collectionMembershipResolution(id: String, incomingModifiedAt: Instant?): TombstoneResolution {
        return SyncMerge.tombstoneResolution(
            incomingModifiedAt = incomingModifiedAt,
            tombstoneDeletedAt = collectionMembershipById[BackupPaths.normalizeIdForComparison(id)]
                ?.lastModifiedAt
        )
    }

    fun collectionResolution(id: String, incomingModifiedAt: Instant?): TombstoneResolution {
        return SyncMerge.tombstoneResolution(
            incomingModifiedAt = incomingModifiedAt,
            tombstoneDeletedAt = collectionById[BackupPaths.normalizeIdForComparison(id)]
                ?.lastModifiedAt
        )
    }

    fun bookmarkResolution(id: String, incomingModifiedAt: Instant?): TombstoneResolution {
        return SyncMerge.tombstoneResolution(
            incomingModifiedAt = incomingModifiedAt,
            tombstoneDeletedAt = bookmarkById[BackupPaths.normalizeIdForComparison(id)]
                ?.lastModifiedAt
        )
    }

    fun savedSearchResolution(id: String, incomingModifiedAt: Instant?): TombstoneResolution {
        return SyncMerge.tombstoneResolution(
            incomingModifiedAt = incomingModifiedAt,
            tombstoneDeletedAt = savedSearchById[BackupPaths.normalizeIdForComparison(id)]
                ?.lastModifiedAt
        )
    }

    fun readingSessionResolution(id: String, incomingModifiedAt: Instant?): TombstoneResolution {
        return SyncMerge.tombstoneResolution(
            incomingModifiedAt,
            readingSessionById[BackupPaths.normalizeIdForComparison(id)]?.lastModifiedAt
        )
    }

    fun readingFavoriteResolution(id: String, incomingModifiedAt: Instant?): TombstoneResolution {
        return SyncMerge.tombstoneResolution(
            incomingModifiedAt,
            readingFavoriteById[BackupPaths.normalizeIdForComparison(id)]?.lastModifiedAt
        )
    }

    fun fandomReadWatermarkResolution(
        id: String,
        incomingModifiedAt: Instant?
    ): TombstoneResolution {
        return SyncMerge.tombstoneResolution(
            incomingModifiedAt,
            fandomReadWatermarkById[BackupPaths.normalizeIdForComparison(id)]?.lastModifiedAt
        )
    }

    private fun canonicalSourceUrl(raw: String): String? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return null
        return WorkTags.canonicalAO3WorkURL(trimmed) ?: trimmed.lowercase()
    }

    private fun <K> indexNewest(
        map: MutableMap<K, SyncTombstone>,
        key: K,
        tombstone: SyncTombstone
    ) {
        val existing = map[key]
        if (existing != null && !existing.lastModifiedAt.isBefore(tombstone.lastModifiedAt)) {
            return
        }
        map[key] = tombstone
    }
}

/**
 * iOS `KudosBackupService.mayReplaceEPUB`: whether a restore may overwrite a local work's EPUB
 * with an archived one. A new record has nothing to lose and a work with no file can always be
 * filled in. A preserved work that still has its file is never replaced: preservation is the
 * promise that this exact copy is kept, often of a work that no longer exists upstream.
 * Otherwise only a newer archive replaces it.
 */
internal fun mayReplaceEpub(
    hasLocalFile: Boolean,
    isPreserved: Boolean,
    isNewRecord: Boolean,
    incomingIsNewer: Boolean
): Boolean = isNewRecord || !hasLocalFile || (!isPreserved && incomingIsNewer)
