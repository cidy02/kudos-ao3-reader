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
import io.github.cidy02.kudos.works.WorkIdentityIndex
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.works.WorkTags
import java.time.Duration
import java.time.Instant

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
        trustedPublicKeys: Set<String> = emptySet()
    ): BackupMergeResult {
        val manifest = BackupValidator.validateManifest(backup.manifest)
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
                return@forEach
            }
            val incomingKey = BackupPaths.normalizeIdForComparison(incoming.id)
            // `id` is not in the signed payload — a trusted signature must never
            // overwrite a local tombstone row (spec §2: local deletes still suppress).
            if (tombstonesById.containsKey(incomingKey)) return@forEach
            tombstonesById[incomingKey] = incoming
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
            val existing = identity.existingWork(
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

            val incomingEpub = epubFilesById[archivedId] ?: epubFilesById[targetId]
            val existingHasEpub = targetId in currentEpubIds || existing?.hasEpub == true
            val restoredHasEpub = incomingEpub != null || existingHasEpub

            val incomingModifiedAt = resolveIncomingLastModifiedAt(
                lastModifiedAt = archived.lastModifiedAt,
                dateAdded = archived.dateAdded,
                exportedAt = exportedAt,
                now = now
            )
            val restoredBase = archived.toSavedWork(hasEpub = restoredHasEpub, exportedAt = exportedAt)
            val restored = restoredBase.copy(
                id = existing?.id ?: restoredBase.id,
                lastModifiedAt = incomingModifiedAt ?: restoredBase.dateAdded
            )
            worksById[targetId] = if (existing == null) {
                summary = summary.copy(worksCreated = summary.worksCreated + 1)
                restored
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
                existing
            } else if (mode == BackupImportMode.REPLACE_LIBRARY) {
                summary = summary.copy(worksUpdated = summary.worksUpdated + 1)
                applyReplaceWork(existing, restored)
            } else {
                summary = summary.copy(worksUpdated = summary.worksUpdated + 1)
                mergeWork(existing, restored, archived, incomingModifiedAt, exportedAt)
            }
            identity.index(worksById.getValue(targetId))

            // Only replace a local EPUB when the archive's copy is genuinely the
            // newer one. Writing it whenever the archive carried a file — which is
            // what this used to do, ungated by the LWW result above — means folder
            // sync *destroys* a locally changed EPUB rather than merely failing to
            // propagate it: sync-down runs before sync-up, so the stale remote copy
            // is restored over the fresh local file and then exported back out.
            //
            // Strictly newer, not >=: when neither side's metadata moved, the two
            // clocks are equal and there is nothing to justify overwriting bytes
            // this device holds. The font merge already treats differing content as
            // something to preserve rather than clobber.
            // Replace treats the snapshot as this device's library, so a file that
            // actually carries the EPUB still wins even when clocks are equal.
            val incomingEpubWins = existing == null ||
                mode == BackupImportMode.REPLACE_LIBRARY ||
                (mode == BackupImportMode.MERGE && existing.isDeleted) ||
                (
                    mode != BackupImportMode.MERGE &&
                    incomingModifiedAt != null &&
                        existing.effectiveLastModifiedAt.isBefore(incomingModifiedAt)
                    )
            if (incomingEpub != null && (!existingHasEpub || incomingEpubWins)) {
                epubFilesToWrite[targetId] = incomingEpub
            }

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
            mode = mode,
            exportedAt = exportedAt
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
            mode = mode,
            exportedAt = exportedAt
        ).also {
            summary = summary.copy(
                savedSearchesCreated = it.created,
                savedSearchesUpdated = it.updated
            )
        }.items

        val queueMerge = mergeQueues(
            currentQueues = current.readingQueues,
            currentMemberships = current.readingQueueMemberships,
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
                readingQueues = queueMerge.queues,
                readingQueueMemberships = queueMerge.memberships,
                annotations = annotationMerge.items
            ),
            summary = summary,
            epubFilesToWriteByWorkId = epubFilesToWrite,
            fontFilesToWriteByFileName = fontMerge.filesToWrite,
            mode = mode
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
                isSaved = restored.isSaved || existing.isSaved,
                isQueuedForLater = restored.isQueuedForLater || existing.isQueuedForLater,
                dateAdded = minInstant(existing.dateAdded, restored.dateAdded),
                lastModifiedAt = maxInstant(existing.lastModifiedAt, incomingModifiedAt)
                    ?: incomingModifiedAt,
                comments = archived.comments ?: existing.comments,
                hits = archived.hits ?: existing.hits,
                knownChapterCount = archived.knownChapterCount ?: existing.knownChapterCount,
                lastUpdateCheck = restored.lastUpdateCheck ?: existing.lastUpdateCheck
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
                    ?: existing.effectiveLastModifiedAt
            )
        }

        // Preservation trio: store/re-emit only. Never invent a status. Prefer the
        // non-null side when one is absent so a local-wins merge does not wipe
        // values that only arrived on the archive (and vice versa).
        val withPreservation = base.copy(
            epubPreservationStatusRaw = if (incomingWins) {
                restored.epubPreservationStatusRaw ?: existing.epubPreservationStatusRaw
            } else {
                existing.epubPreservationStatusRaw ?: restored.epubPreservationStatusRaw
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
                    progressModifiedAt = existing.progressModifiedAt
                )
            }
            if (!SyncMerge.shouldApplyIncoming(localProgressAt, incomingProgressAt)) {
                return base.copy(
                    lastSpineIndex = existing.lastSpineIndex,
                    lastScrollFraction = existing.lastScrollFraction,
                    lastReadDate = existing.lastReadDate,
                    readiumLocator = existing.readiumLocator ?: restored.readiumLocator,
                    progressModifiedAt = existing.progressModifiedAt
                )
            }
        }

        return base.copy(
            lastSpineIndex = restored.lastSpineIndex,
            lastScrollFraction = restored.lastScrollFraction,
            lastReadDate = restored.lastReadDate,
            readiumLocator = restored.readiumLocator ?: existing.readiumLocator,
            progressModifiedAt = incomingProgressAt ?: restored.lastReadDate
        )
    }

    private fun mergeBookmarks(
        current: List<Bookmark>,
        incoming: List<BackupBookmark>,
        mode: BackupImportMode = BackupImportMode.RECONCILE,
        exportedAt: Instant? = null
    ): MergeItems<Bookmark> {
        val byUrl = current.associateByTo(linkedMapOf()) { it.urlString }
        var created = 0
        var updated = 0
        incoming.forEach { archived ->
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
                if (url !in incomingUrls) byUrl.remove(url)
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
                if (reusableFile != null && reusableFile.value.isNotEmpty() &&
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
                exactExistingBytes.isNotEmpty() &&
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
                if (added.isNotEmpty()) {
                    collectionsById[id] = existing.copy(workIds = existing.workIds + added)
                    updated += 1
                }
            } else {
                val localModified = existing.lastModifiedAt ?: existing.dateAdded
                if (!SyncMerge.shouldApplyIncoming(localModified, incomingModified)) {
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
                collectionsById[id] = existing.copy(
                    name = if (archivedIsDeleted) existing.name else archived.name,
                    dateAdded = BackupValidator.parseInstant(
                        archived.dateAdded,
                        "collection.dateAdded",
                        exportedAt
                    ),
                    workIds = mergedWorkIds,
                    description = archived.description ?: existing.description,
                    sortOrder = archived.sortOrder ?: existing.sortOrder,
                    lastModifiedAt = incomingModified ?: existing.lastModifiedAt,
                    isDeleted = deletionState.isDeleted,
                    deletedAt = if (deletionState.isDeleted) {
                        parseOptionalInstant(archived.deletedAt, exportedAt) ?: incomingModified
                    } else {
                        null
                    },
                    permanentDeletionScheduledAt = deletionState.permanentDeletionScheduledAt
                )
                if (!archivedIsDeleted) names += archived.name
                updated += 1
            }
        }

        return MergeItems(collectionsById.values.sortedBy { it.name.lowercase() }, created, updated)
    }

    private fun mergeSavedSearches(
        current: List<SavedSearch>,
        incoming: List<BackupSavedSearch>,
        mode: BackupImportMode = BackupImportMode.RECONCILE,
        exportedAt: Instant? = null
    ): MergeItems<SavedSearch> {
        val searchesById = current.associateByTo(linkedMapOf()) {
            BackupPaths.normalizeIdForComparison(it.id)
        }
        val names = current.mapTo(mutableSetOf()) { it.name }
        var created = 0
        var updated = 0

        incoming.forEach { archived ->
            val id = BackupPaths.canonicalUuid(archived.id, "savedSearch.id")
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

        if (mode == BackupImportMode.REPLACE_LIBRARY) {
            val incomingIds = incoming.mapTo(mutableSetOf()) {
                BackupPaths.canonicalUuid(it.id, "savedSearch.id")
            }
            searchesById.keys.toList().forEach { id ->
                if (id !in incomingIds) searchesById.remove(id)
            }
        }

        return MergeItems(searchesById.values.sortedBy { it.name.lowercase() }, created, updated)
    }

    private fun mergeQueues(
        currentQueues: List<ReadingQueue>,
        currentMemberships: List<ReadingQueueMembership>,
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
                queuesById[id] = archived.toReadingQueue(exportedAt)
                queuesCreated += 1
            } else if (mode == BackupImportMode.MERGE) {
                // Keep local queue name / fields. New memberships still insert below.
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
                    queuesById[id] = restored.copy(
                        // Keep the local identity: local memberships already point
                        // at it, and for the system queue the incoming id is a
                        // different platform's UUID entirely.
                        id = existing.id,
                        // iOS pins the system queue's name and kind rather than let
                        // a restore rename it, and nothing may soft-delete it —
                        // there is no UI that could ever bring it back.
                        name = if (isSystemQueue) ReadingQueueKind.SAVED_FOR_LATER_NAME else restored.name,
                        kindRaw = if (isSystemQueue) ReadingQueueKind.SAVED_FOR_LATER else restored.kindRaw,
                        isDeleted = deletionState.isDeleted,
                        deletedAt = if (deletionState.isDeleted) restored.deletedAt else null,
                        permanentDeletionScheduledAt = deletionState.permanentDeletionScheduledAt,
                        dateCreated = minInstant(existing.dateCreated, restored.dateCreated)
                    )
                    queuesUpdated += 1
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
            }
            val incomingMembershipIds = incomingMemberships.mapTo(mutableSetOf()) {
                BackupPaths.canonicalUuid(it.id, "membership.id")
            }
            membershipsById.keys.toList().forEach { id ->
                if (id !in incomingMembershipIds) membershipsById.remove(id)
            }
        }

        return QueueMerge(
            queues = queuesById.values.sortedBy { it.sortOrder },
            memberships = membershipsById.values.sortedBy { it.sortOrderInQueue },
            queuesCreated = queuesCreated,
            queuesUpdated = queuesUpdated,
            membershipsCreated = membershipsCreated,
            membershipsUpdated = membershipsUpdated,
            membershipsSuppressed = membershipsSuppressed
        )
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
}

/** Apple `SyncMerge` helpers used by backup restore. */
object SyncMerge {
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
