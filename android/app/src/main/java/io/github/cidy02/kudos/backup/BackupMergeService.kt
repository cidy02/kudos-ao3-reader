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
import java.time.Instant

/**
 * Merge-only restore semantics aligned with Apple `KudosBackup` + `SyncMerge`:
 * - LWW on work metadata via [lastModifiedAt]
 * - LWW on reading progress via [progressModifiedAt] / [lastReadDate]
 * - Tombstones suppress resurrection of deleted records
 * - Queues, memberships, annotations stored and restored by id (LWW)
 */
object BackupMergeService {
    fun merge(
        current: BackupLibrarySnapshot,
        backup: KudosBackupPackage
    ): BackupMergeResult {
        val manifest = BackupValidator.validateManifest(backup.manifest)
        val epubFilesById = backup.epubFilesByWorkId.normalizedWorkFileMap()
        val currentEpubIds = current.epubWorkIds.map(BackupPaths::normalizeIdForComparison).toSet()

        var summary = BackupRestoreSummary()
        val epubFilesToWrite = linkedMapOf<String, ByteArray>()

        // Merge archive tombstones into local set (id-keyed; newest lastModified wins).
        val tombstonesById = current.tombstones
            .associateByTo(linkedMapOf()) { BackupPaths.normalizeIdForComparison(it.id) }
        manifest.tombstones.forEach { archived ->
            val id = BackupPaths.canonicalUuid(archived.id, "tombstone.id")
            val restored = archived.toSyncTombstone()
            val existing = tombstonesById[id]
            if (existing == null || restored.lastModifiedAt >= existing.lastModifiedAt) {
                tombstonesById[id] = restored
            }
        }
        val tombstoneIndex = TombstoneIndex(tombstonesById.values.toList())

        val worksById = current.works
            .associateByTo(linkedMapOf()) { BackupPaths.normalizeIdForComparison(it.id) }
        val userTagsByWorkId = current.userTagsByWorkId
            .mapKeys { BackupPaths.normalizeIdForComparison(it.key) }
            .mapValues { it.value.normalizedNames() }
            .toMutableMap()

        manifest.works.forEach { archived ->
            val id = BackupPaths.canonicalUuid(archived.id, "work.id")
            val existing = worksById[id]

            if (existing == null && tombstoneIndex.suppressesWorkResurrection(archived)) {
                summary = summary.copy(worksSuppressed = summary.worksSuppressed + 1)
                return@forEach
            }

            val incomingEpub = epubFilesById[id]
            val existingHasEpub = id in currentEpubIds || existing?.hasEpub == true
            val restoredHasEpub = incomingEpub != null || existingHasEpub

            val restored = archived.toSavedWork(hasEpub = restoredHasEpub)
            worksById[id] = if (existing == null) {
                summary = summary.copy(worksCreated = summary.worksCreated + 1)
                restored
            } else {
                summary = summary.copy(worksUpdated = summary.worksUpdated + 1)
                mergeWork(existing, restored, archived)
            }

            if (incomingEpub != null) {
                epubFilesToWrite[id] = incomingEpub
            }

            val mergedTags = (userTagsByWorkId[id].orEmpty() + archived.userTags).normalizedNames()
            if (mergedTags.isNotEmpty()) userTagsByWorkId[id] = mergedTags
        }

        val bookmarks = mergeBookmarks(current.bookmarks, manifest.bookmarks).also {
            summary = summary.copy(
                bookmarksCreated = it.created,
                bookmarksUpdated = it.updated
            )
        }.items

        val fontMerge = mergeFonts(
            currentFonts = current.fonts,
            currentFontFiles = current.fontFilesByFileName,
            manifestFonts = manifest.fonts,
            backupFontFiles = backup.fontFilesByFileName
        )
        summary = summary.copy(
            fontsCreated = fontMerge.created,
            fontsUpdated = fontMerge.updated
        )

        val collections = mergeCollections(
            current.collections,
            manifest.collections,
            tombstoneIndex
        ).also {
            summary = summary.copy(
                collectionsCreated = it.created,
                collectionsUpdated = it.updated
            )
        }.items

        val savedSearches = mergeSavedSearches(current.savedSearches, manifest.savedSearches).also {
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
            tombstoneIndex = tombstoneIndex
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
            tombstoneIndex = tombstoneIndex
        )
        summary = summary.copy(
            annotationsCreated = annotationMerge.created,
            annotationsUpdated = annotationMerge.updated,
            annotationsSuppressed = annotationMerge.suppressed
        )

        val settingsPayload = manifest.settings.retargetRenamedFont(fontMerge.renamedFonts)
        val settings = BackupValidator
            .normalizeSettings(settingsPayload, fontMerge.items.map { it.fileName }.toSet())
            .toCoreBackupSettings()

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
            fontFilesToWriteByFileName = fontMerge.filesToWrite
        )
    }

    /**
     * Apple-aligned work merge: metadata/flags LWW on lastModifiedAt; progress LWW
     * on progressModifiedAt (fallback lastReadDate). Tags are unioned.
     */
    internal fun mergeWork(
        existing: SavedWork,
        restored: SavedWork,
        archived: BackupWork
    ): SavedWork {
        val incomingModifiedAt = parseOptionalInstant(archived.lastModifiedAt)
            ?: restored.dateAdded
        val localModifiedAt = existing.effectiveLastModifiedAt
        val incomingWins = SyncMerge.shouldApplyIncoming(localModifiedAt, incomingModifiedAt)

        val base = if (incomingWins) {
            restored.copy(
                // Never lose a local EPUB just because the archive lacked one.
                hasEpub = existing.hasEpub || restored.hasEpub,
                isSaved = restored.isSaved || existing.isSaved || (existing.hasEpub || restored.hasEpub),
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

        return applyProgressLww(base, existing, restored, archived)
    }

    /**
     * Prefer newer progress. When the archive lacks progress timestamps, keep
     * local progress if local [lastReadDate] is later (non-destructive default).
     */
    private fun applyProgressLww(
        base: SavedWork,
        existing: SavedWork,
        restored: SavedWork,
        archived: BackupWork
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
        val incomingProgressAt = parseOptionalInstant(archived.progressModifiedAt)
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
        incoming: List<BackupBookmark>
    ): MergeItems<Bookmark> {
        val byUrl = current.associateByTo(linkedMapOf()) { it.urlString }
        var created = 0
        var updated = 0
        incoming.forEach { archived ->
            val existing = byUrl[archived.urlString]
            byUrl[archived.urlString] = if (existing == null) {
                created += 1
                archived.toBookmark()
            } else {
                updated += 1
                existing.copy(
                    title = archived.title,
                    dateAdded = BackupValidator.parseInstant(archived.dateAdded, "bookmark.dateAdded")
                )
            }
        }
        return MergeItems(byUrl.values.sortedByDescending { it.dateAdded }, created, updated)
    }

    private fun mergeFonts(
        currentFonts: List<CustomFont>,
        currentFontFiles: Map<String, ByteArray>,
        manifestFonts: List<BackupFont>,
        backupFontFiles: Map<String, ByteArray>
    ): FontMerge {
        val fontsByName = currentFonts.associateByTo(linkedMapOf()) { it.fileName }
        val filesToWrite = linkedMapOf<String, ByteArray>()
        val renamedFonts = mutableMapOf<String, String>()
        var created = 0
        var updated = 0

        manifestFonts.forEach { archived ->
            val incomingBytes = backupFontFiles[archived.fileName] ?: return@forEach
            val existing = fontsByName[archived.fileName]
            if (existing == null) {
                val font = archived.toCustomFont()
                fontsByName[font.fileName] = font
                filesToWrite[font.fileName] = incomingBytes
                created += 1
                return@forEach
            }

            val existingBytes = currentFontFiles[archived.fileName]
            if (existingBytes != null &&
                BackupPaths.sha256(existingBytes) == BackupPaths.sha256(incomingBytes)
            ) {
                fontsByName[archived.fileName] = existing.copy(
                    name = archived.name,
                    dateAdded = BackupValidator.parseInstant(archived.dateAdded, "font.dateAdded")
                )
                updated += 1
            } else {
                val newFileName = BackupPaths.uniqueSuffixedFontFileName(
                    archived.fileName,
                    fontsByName.keys + filesToWrite.keys
                )
                fontsByName[newFileName] = archived.toCustomFont(fileNameOverride = newFileName)
                filesToWrite[newFileName] = incomingBytes
                renamedFonts[archived.fileName] = newFileName
                created += 1
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
    private fun mergeCollections(
        current: List<WorkCollection>,
        incoming: List<BackupCollection>,
        tombstoneIndex: TombstoneIndex
    ): MergeItems<WorkCollection> {
        val collectionsById = current.associateByTo(linkedMapOf()) {
            BackupPaths.normalizeIdForComparison(it.id)
        }
        val names = current.filterNot { it.isDeleted }.mapTo(mutableSetOf()) { it.name }
        var created = 0
        var updated = 0

        incoming.forEach { archived ->
            val id = BackupPaths.canonicalUuid(archived.id, "collection.id")
            val incomingModified = parseOptionalInstant(archived.lastModifiedAt)
                ?: parseOptionalInstant(archived.dateAdded)
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
                val restored = archived.toWorkCollection(nameOverride = restoredName)
                collectionsById[id] = restored
                names += restoredName
                created += 1
            } else {
                val localModified = existing.lastModifiedAt ?: existing.dateAdded
                if (!SyncMerge.shouldApplyIncoming(localModified, incomingModified)) {
                    return@forEach
                }
                val archivedIsDeleted = archived.isDeleted == true
                val mergedWorkIds = (existing.workIds + archived.workIDs)
                    .map { BackupPaths.normalizeIdForComparison(it) }
                    .distinct()
                    // A work the user explicitly removed from this collection locally
                    // must not silently come back just because an older backup still
                    // lists it as a member.
                    .filterNot { workId ->
                        tombstoneIndex.collectionMembershipResolution(
                            "$id:$workId",
                            incomingModified
                        ) == TombstoneResolution.SUPPRESS_STALE
                    }
                collectionsById[id] = existing.copy(
                    name = if (archivedIsDeleted) existing.name else archived.name,
                    dateAdded = BackupValidator.parseInstant(archived.dateAdded, "collection.dateAdded"),
                    workIds = mergedWorkIds,
                    description = archived.description ?: existing.description,
                    sortOrder = archived.sortOrder ?: existing.sortOrder,
                    lastModifiedAt = incomingModified ?: existing.lastModifiedAt,
                    isDeleted = archivedIsDeleted,
                    deletedAt = if (archivedIsDeleted) {
                        parseOptionalInstant(archived.deletedAt) ?: incomingModified
                    } else {
                        null
                    },
                    permanentDeletionScheduledAt = if (archivedIsDeleted) {
                        parseOptionalInstant(archived.permanentDeletionScheduledAt)
                    } else {
                        null
                    }
                )
                if (!archivedIsDeleted) names += archived.name
                updated += 1
            }
        }

        return MergeItems(collectionsById.values.sortedBy { it.name.lowercase() }, created, updated)
    }

    private fun mergeSavedSearches(
        current: List<SavedSearch>,
        incoming: List<BackupSavedSearch>
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
                searchesById[id] = archived.toSavedSearch(nameOverride = restoredName)
                names += restoredName
                created += 1
            } else {
                searchesById[id] = existing.copy(
                    name = archived.name,
                    dateAdded = BackupValidator.parseInstant(archived.dateAdded, "savedSearch.dateAdded"),
                    filtersJson = archived.filters.toString()
                )
                names += archived.name
                updated += 1
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
        tombstoneIndex: TombstoneIndex
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
                    parseOptionalInstant(membership.lastModifiedAt)
                        ?: parseOptionalInstant(membership.queuedAt.takeIf { it.isNotBlank() })
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
                queueUpdatedAt = parseOptionalInstant(archived.dateUpdated.takeIf { it.isNotBlank() }),
                lastMembershipChangedAt = parseOptionalInstant(archived.lastMembershipChangedAt),
                membershipModifiedAts = incomingMembershipTimes[incomingId].orEmpty()
            ) ?: parseOptionalInstant(archived.dateCreated.takeIf { it.isNotBlank() })

            val existing = queuesById[id]
            if (existing == null) {
                when (tombstoneIndex.queueResolution(id, incomingModified)) {
                    TombstoneResolution.SUPPRESS_STALE -> return@forEach
                    TombstoneResolution.REVIVE_NEWER,
                    TombstoneResolution.PRESERVE_AMBIGUOUS,
                    TombstoneResolution.NO_TOMBSTONE -> Unit
                }
                queuesById[id] = archived.toReadingQueue()
                queuesCreated += 1
            } else {
                val localModified = SyncMerge.effectiveQueueModifiedAt(
                    queueUpdatedAt = existing.dateUpdated,
                    lastMembershipChangedAt = existing.lastMembershipChangedAt,
                    membershipModifiedAts = localMembershipTimes[id].orEmpty()
                )
                if (SyncMerge.shouldApplyIncoming(localModified, incomingModified)) {
                    val restored = archived.toReadingQueue()
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
                        isDeleted = !isSystemQueue && restored.isDeleted,
                        deletedAt = if (isSystemQueue) null else restored.deletedAt,
                        permanentDeletionScheduledAt = if (isSystemQueue) {
                            null
                        } else {
                            restored.permanentDeletionScheduledAt
                        },
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
            val workId = BackupPaths.canonicalUuid(archived.workID, "membership.workID")
            if (queueId !in queuesById) return@forEach
            if (workId !in worksById) return@forEach

            val incomingModified = parseOptionalInstant(archived.lastModifiedAt)
                ?: parseOptionalInstant(archived.queuedAt.takeIf { it.isNotBlank() })

            when (tombstoneIndex.membershipResolution(id, incomingModified)) {
                TombstoneResolution.SUPPRESS_STALE -> {
                    membershipsSuppressed += 1
                    return@forEach
                }
                else -> Unit
            }

            val existing = membershipsById[id]
            val restored = archived.toReadingQueueMembership()
                .let { if (queueId == incomingQueueId) it else it.copy(queueID = queueId) }
            if (existing == null) {
                membershipsById[id] = restored
                membershipsCreated += 1
            } else {
                val localModified = existing.lastModifiedAt ?: existing.queuedAt
                if (SyncMerge.shouldApplyIncoming(localModified, incomingModified)) {
                    membershipsById[id] = restored
                    membershipsUpdated += 1
                }
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
        tombstoneIndex: TombstoneIndex
    ): AnnotationMerge {
        val byId = current.associateByTo(linkedMapOf()) {
            BackupPaths.normalizeIdForComparison(it.id)
        }
        var created = 0
        var updated = 0
        var suppressed = 0

        incoming.forEach { archived ->
            val id = BackupPaths.canonicalUuid(archived.id, "annotation.id")
            val workId = BackupPaths.canonicalUuid(archived.workID, "annotation.workID")
            // Never orphan annotations without a work in this restore.
            if (workId !in worksById) return@forEach
            // A pending-deletion annotation is a *tombstone*, not noise: dropping it
            // here (as this used to) means a highlight deleted on iOS silently comes
            // back on Android. iOS assigns `isPendingDeletion` through instead, and
            // the LWW check below decides whether the deletion actually wins.

            val incomingModified = parseOptionalInstant(archived.lastModifiedAt)
                ?: parseOptionalInstant(archived.createdAt.takeIf { it.isNotBlank() })
                ?: Instant.EPOCH

            when (tombstoneIndex.annotationResolution(id, incomingModified)) {
                TombstoneResolution.SUPPRESS_STALE -> {
                    suppressed += 1
                    return@forEach
                }
                else -> Unit
            }

            val existing = byId[id]
            val restored = archived.toReadingAnnotation()
            if (existing == null) {
                byId[id] = restored
                created += 1
            } else {
                if (!SyncMerge.shouldApplyIncoming(
                        existing.effectiveLastModifiedAt,
                        incomingModified
                    )
                ) {
                    return@forEach
                }
                byId[id] = restored.copy(
                    createdAt = minInstant(existing.createdAt, restored.createdAt)
                )
                updated += 1
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

    private fun parseOptionalInstant(raw: String?): Instant? {
        val value = raw?.takeIf { it.isNotBlank() } ?: return null
        return runCatching { BackupValidator.parseInstant(value, "timestamp") }.getOrNull()
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
internal class TombstoneIndex(tombstones: List<SyncTombstone>) {
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
                    val url = tombstone.sourceURL.trim().lowercase()
                    if (url.isNotEmpty()) indexNewest(workBySourceUrl, url, tombstone)
                }
                SyncTombstoneRecordType.READING_QUEUE ->
                    indexNewest(queueById, recordId, tombstone)
                SyncTombstoneRecordType.READING_QUEUE_MEMBERSHIP ->
                    indexNewest(membershipById, recordId, tombstone)
                SyncTombstoneRecordType.READING_ANNOTATION ->
                    indexNewest(annotationById, recordId, tombstone)
                SyncTombstoneRecordType.WORK_COLLECTION ->
                    indexNewest(collectionById, recordId, tombstone)
                SyncTombstoneRecordType.WORK_COLLECTION_MEMBERSHIP ->
                    indexNewest(collectionMembershipById, recordId, tombstone)
                else -> Unit
            }
        }
    }

    fun suppressesWorkResurrection(archived: BackupWork): Boolean {
        val byAo3 = archived.ao3WorkID?.let { workByAo3Id[it] }
        val byUrl = archived.sourceURL.trim().lowercase().takeIf { it.isNotEmpty() }
            ?.let { workBySourceUrl[it] }
        val byId = workById[BackupPaths.normalizeIdForComparison(archived.id)]
        val tombstone = byAo3 ?: byUrl ?: byId ?: return false
        val archivedModified = runCatching {
            archived.lastModifiedAt?.takeIf { it.isNotBlank() }
                ?.let { BackupValidator.parseInstant(it, "work.lastModifiedAt") }
        }.getOrNull() ?: runCatching {
            if (archived.dateAdded.isNotBlank()) {
                BackupValidator.parseInstant(archived.dateAdded, "work.dateAdded")
            } else {
                null
            }
        }.getOrNull() ?: Instant.EPOCH
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

    /** [id] is a `"<collectionId>:<workId>"` pairing — see [io.github.cidy02.kudos.works.WorkRepository]. */
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
