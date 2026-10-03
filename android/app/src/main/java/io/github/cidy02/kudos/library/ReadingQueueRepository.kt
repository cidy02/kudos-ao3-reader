package io.github.cidy02.kudos.library

import androidx.room.withTransaction
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.ReadingQueueKind
import io.github.cidy02.kudos.core.model.ReadingQueueMembership
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.Tag
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.backup.TombstoneSigning
import io.github.cidy02.kudos.core.model.SyncTombstone
import io.github.cidy02.kudos.core.model.SyncTombstoneRecordType
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.works.DownloadQueueItem
import io.github.cidy02.kudos.works.WorkTags
import io.github.cidy02.kudos.data.local.entity.QueueTagCrossRef
import io.github.cidy02.kudos.data.local.entity.TagEntity
import io.github.cidy02.kudos.data.local.entity.WorkTagCrossRef
import io.github.cidy02.kudos.data.local.entity.toDomain
import io.github.cidy02.kudos.data.local.entity.toEntity
import io.github.cidy02.kudos.works.WorkRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.isActive
import kotlinx.coroutines.delay
import kotlin.math.max
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.series.AO3SeriesRepository
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.works.WorkImporter
import io.github.cidy02.kudos.works.WorkImportResult
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import java.time.Instant
import java.util.UUID

/**
 * Local reading-queue membership API (Apple ReadingQueueService subset).
 * Uses existing [io.github.cidy02.kudos.data.local.dao.ReadingQueueDao] + WorkDao.
 */
class ReadingQueueRepository(
    private val database: KudosDatabase,
    private val clock: () -> Instant = { Instant.now() },
    private val uuidFactory: () -> String = { UUID.randomUUID().toString() },
    /** The EPUB file, not the hasEpub flag. Missing files are what Keep fetches. */
    private val epubOnDisk: suspend (String) -> Boolean = { false },
    /** Serial [io.github.cidy02.kudos.works.DownloadQueue]. Empty means no network. */
    private val enqueueDownloads: (List<DownloadQueueItem>) -> Unit = {}
) {
    private val queueDao = database.readingQueueDao()
    private val workDao = database.workDao()
    private val tagDao = database.tagDao()
    private val collectionDao = database.collectionDao()
    private val tombstoneDao = database.syncTombstoneDao()
    private val readingLogDao = database.readingLogDao()

    suspend fun listQueues(): List<ReadingQueue> {
        return queueDao.getActiveQueues().map { it.toDomain() }
    }

    suspend fun getQueue(queueId: String): ReadingQueue? {
        return queueDao.getQueueById(queueId)?.toDomain()
    }

    /** Active (non-deleted-queue) membership count for multi-queue "In N" badges. */
    suspend fun activeMembershipCountForWork(workId: String): Int {
        return queueDao.getActiveMembershipCountForWork(workId)
    }

    /**
     * Memberships for [queueId] joined with work titles from WorkDao, excluding
     * works currently soft-deleted (Recently Deleted) — same as Collections'
     * getActiveWorkIdsForCollection. The membership row itself is untouched, so a
     * restored work reappears here automatically. Works missing outright (hard
     * deleted/tombstoned) still appear with a fallback title.
     */
    suspend fun listWorks(queueId: String): List<QueueMembershipItem> {
        return queueDao.getMembershipsForQueue(queueId).mapNotNull { membershipEntity ->
            val membership = membershipEntity.toDomain()
            val work = workDao.getById(membership.workID)?.toDomain()
            if (work?.isDeleted == true) return@mapNotNull null
            QueueMembershipItem(
                membership = membership,
                work = work,
                title = work?.title?.takeIf { it.isNotBlank() } ?: "Missing work",
                author = work?.author.orEmpty()
            )
        }
    }

    suspend fun addWork(queueId: String, workId: String): ReadingQueueMembership {
        val queue = queueDao.getQueueById(queueId)
            ?: error("Queue not found: $queueId")
        require(!queue.isDeleted) { "Cannot add works to a deleted queue." }

        queueDao.getMembershipForWork(queueId, workId)?.let { return it.toDomain() }

        val now = clock()
        val nextOrder = queueDao.getMembershipsForQueue(queueId)
            .maxOfOrNull { it.sortOrderInQueue }
            ?.plus(1)
            ?: 0
        val membership = ReadingQueueMembership(
            id = uuidFactory(),
            queueID = queueId,
            workID = workId,
            queuedAt = now,
            lastModifiedAt = now,
            sortOrderInQueue = nextOrder
        )
        queueDao.upsertMembership(membership.toEntity())
        touchQueueMembershipChanged(queueId, now)

        // Queue-add localizes a not-yet-local work as queue-only (T-89), but a work
        // that was already local (e.g. reading history) needs the flag stamped here
        // too - this runs for every addWork caller, not just the ones that already
        // went through WorkDetailScreen's queue-add localize path.
        val workEntity = workDao.getById(workId)
        if (workEntity != null) {
            val keepsCopy = queue.keepsWorksOffline != false
            if (!workEntity.isQueuedForLater || (keepsCopy && workEntity.freedAt != null)) {
                workDao.upsert(
                    workEntity.copy(
                        isQueuedForLater = true,
                        freedAt = if (keepsCopy) null else workEntity.freedAt,
                        lastModifiedAt = now
                    )
                )
            }
        }

        if (KeepOffline.queueKeeps(queue.keepsWorksOffline)) {
            workDao.getById(workId)?.toDomain()?.let { enqueueMissing(listOf(it)) }
        }

        return membership
    }

    suspend fun removeWork(queueId: String, workId: String) {
        val existing = queueDao.getMembershipForWork(queueId, workId) ?: return
        val now = clock()

        queueDao.deleteMembershipById(existing.id)
        // Without a tombstone, restoring a backup that still lists this membership
        // silently resurrects it (mergeQueues/TombstoneIndex.membershipResolution
        // expect one to exist for every removed membership).
        upsertSignedTombstone(
            SyncTombstone(
                id = uuidFactory(),
                recordID = existing.id,
                recordTypeRaw = SyncTombstoneRecordType.READING_QUEUE_MEMBERSHIP,
                createdAt = now,
                lastModifiedAt = now,
                deletedOnDeviceID = "",
                deletionReason = "queueMembershipRemoved"
            )
        )
        touchQueueMembershipChanged(queueId, now)

        // iOS parity: removeFromQueueAndDeleteIfQueueOnly. Once a work loses its last
        // queue membership, clear the flag; if it was queue-only (never explicitly
        // saved or favorited), the user is abandoning it entirely - soft-delete it
        // the same way any other removal goes to Recently Deleted, rather than
        // leaving an orphaned, invisible row behind forever.
        //
        // Re-read the row here rather than reusing an entity fetched before the
        // membership delete above: this suspends across several DB writes
        // (tombstone insert, queue touch), a real window for something else -
        // a completed download setting hasEpub, a favorite toggle - to have
        // changed the row in the meantime. Deciding and writing from a stale
        // snapshot could soft-delete a work that just became protected, or
        // clobber a concurrent field change.
        val freshEntity = workDao.getById(workId)
        if (freshEntity != null) {
            val remainingCount = queueDao.getActiveMembershipCountForWork(workId)
            // Must read isQueueOnlyWork from the still-queued entity, before the
            // flag gets cleared below - isQueueOnlyWork is defined in terms of
            // isQueuedForLater, so checking it on the already-cleared copy would
            // always read false regardless of prior state.
            val wasQueueOnly = freshEntity.toDomain().isQueueOnlyWork
            if (remainingCount == 0 && freshEntity.isQueuedForLater) {
                val cleared = freshEntity.copy(isQueuedForLater = false, lastModifiedAt = now)
                if (wasQueueOnly) {
                    workDao.upsert(
                        cleared.copy(
                            isDeleted = true,
                            deletedAt = now,
                            permanentDeletionScheduledAt = now.plus(WorkRepository.RECOVERY_WINDOW)
                        )
                    )
                } else {
                    workDao.upsert(cleared)
                }
            }
        }
    }

    
    suspend fun removeFromAllQueuesAndDeleteIfQueueOnly(workId: String) {
        val memberships = queueDao.getMembershipsForWork(workId)
        for (membership in memberships) {
            removeWork(membership.queueID, workId)
        }
    }

    // Room serializes concurrent withTransaction calls against the same database (each
    // waits for the prior one to commit before its own body runs), so the second of two
    // racing callers sees the first caller's insert on its own check and returns that
    // row instead of inserting a duplicate. Multiple call sites (LibraryViewModel's
    // refresh() and refreshQueues(), plus this repository's own add()/preserve() paths)
    // could otherwise both pass the check-then-create race at once — confirmed via a
    // fresh install producing two "Saved for Later" rows before this fix.
    suspend fun ensureSavedForLaterQueue(): ReadingQueue = database.withTransaction {
        queueDao.getActiveQueueByKind(ReadingQueueKind.SAVED_FOR_LATER)?.let {
            return@withTransaction it.toDomain()
        }
        val now = clock()
        val queue = ReadingQueue(
            id = uuidFactory(),
            name = ReadingQueueKind.SAVED_FOR_LATER_NAME,
            kindRaw = ReadingQueueKind.SAVED_FOR_LATER,
            sortOrder = 0,
            dateCreated = now,
            dateUpdated = now
        )
        queueDao.upsertQueue(queue.toEntity())
        queue
    }

    /**
     * Creates a user-named custom queue (Library “+ New Queue”, Home's "+").
     * A case-insensitive name match returns the existing queue and does not
     * overwrite its hue, tags, or memberships.
     *
     * The New Queue sheet has asked, so [keepsWorksOffline] is the reader's
     * choice (`true` or `false`), not "never asked". [colorHex] is stored
     * exactly as picked. [tagNames] are looked up before they are created.
     * [seedFromSavedForLater] copies that queue's works and leaves them there.
     */
    suspend fun createQueue(
        name: String,
        hue: Double? = null,
        colorHex: String? = null,
        keepsWorksOffline: Boolean? = null,
        notes: String? = null,
        tagNames: List<String> = emptyList(),
        seedFromSavedForLater: Boolean = false
    ): ReadingQueue {
        val trimmed = name.trim()
        require(trimmed.isNotEmpty()) { "Queue name must not be blank." }
        val existing = queueDao.getActiveQueues().firstOrNull {
            it.name.equals(trimmed, ignoreCase = true) &&
                it.kindRaw == ReadingQueueKind.CUSTOM
        }
        if (existing != null) return existing.toDomain()

        val now = clock()
        val nextOrder = (queueDao.getActiveQueues().maxOfOrNull { it.sortOrder } ?: -1) + 1
        val queue = ReadingQueue(
            id = uuidFactory(),
            name = trimmed,
            kindRaw = ReadingQueueKind.CUSTOM,
            sortOrder = nextOrder,
            dateCreated = now,
            dateUpdated = now,
            hue = hue,
            colorHex = colorHex,
            keepsWorksOffline = keepsWorksOffline,
            notes = notes
        )
        queueDao.upsertQueue(queue.toEntity())
        if (tagNames.isNotEmpty()) replaceQueueTags(queue.id, tagNames)
        if (seedFromSavedForLater) {
            val source = queueDao.getActiveQueueByKind(ReadingQueueKind.SAVED_FOR_LATER)
            if (source != null) {
                for (item in listWorks(source.id)) {
                    val work = item.work ?: continue
                    addWork(queue.id, work.id)
                }
            }
        }
        return getQueue(queue.id) ?: queue
    }

    /**
     * Edit Queue: the New Queue sheet written onto an existing queue.
     * A blank name keeps the old one. Saved for Later cannot be renamed.
     * Offline is written only when the resolved keep changes, so a never-asked
     * queue stays never-asked. Tags not in [edit.tagNames] come off this queue
     * only. Returns true when Keep works offline was turned on.
     *
     * Stamps [ReadingQueue.dateUpdated]. Membership [ReadingQueueMembership.lastModifiedAt]
     * changes only when a membership itself moves (`updateSortOrder`).
     */
    suspend fun updateQueue(queueId: String, edit: QueueEdit): Boolean {
        val queue = queueDao.getQueueById(queueId) ?: return false
        require(!queue.isDeleted) { "Cannot edit a deleted queue." }
        var changed = false
        var name = queue.name
        val trimmed = edit.name.trim()
        if (trimmed.isNotEmpty() && trimmed != queue.name) {
            require(queue.kindRaw != ReadingQueueKind.SAVED_FOR_LATER) { "Cannot rename system queues." }
            name = trimmed
            changed = true
        }
        var hue = queue.hue
        var colorHex = queue.colorHex
        if (queue.hue != edit.hue || queue.colorHex != edit.colorHex) {
            hue = edit.hue
            colorHex = edit.colorHex
            changed = true
        }
        val wasKept = queue.keepsWorksOffline != false
        var keeps = queue.keepsWorksOffline
        if (edit.keepsWorksOffline != wasKept) {
            keeps = edit.keepsWorksOffline
            changed = true
        }
        var notes = queue.notes
        if ((edit.notes ?: "") != (queue.notes ?: "")) {
            notes = edit.notes
            changed = true
        }
        if (changed) {
            queueDao.upsertQueue(
                queue.copy(
                    name = name,
                    hue = hue,
                    colorHex = colorHex,
                    keepsWorksOffline = keeps,
                    notes = notes,
                    dateUpdated = clock()
                )
            )
        }
        replaceQueueTags(queueId, edit.tagNames)
        val turnedOn = edit.keepsWorksOffline && !wasKept
        if (turnedOn) {
            enqueueMissing(listWorks(queueId).mapNotNull { it.work })
        }
        return turnedOn
    }

    /**
     * Keep works offline just turned on, or a work was added to a queue that
     * keeps. Fetches AO3 works whose EPUB is not on disk. Does not delete files,
     * and a queue with Keep off never calls this.
     */
    private suspend fun enqueueMissing(works: List<SavedWork>) {
        val onDisk = works.associate { work ->
            work.id to runCatching { epubOnDisk(work.id) }.getOrDefault(false)
        }
        val items = KeepOffline.downloadItems(works) { work -> onDisk[work.id] == true }
        if (items.isNotEmpty()) enqueueDownloads(items)
    }

    /** Pin, unless every selected queue already is. A queue already there is left alone. */
    suspend fun setQueuesPinned(queueIds: List<String>, pinned: Boolean) {
        val now = clock()
        database.withTransaction {
            for (id in queueIds) {
                val queue = queueDao.getQueueById(id) ?: continue
                if (queue.isDeleted || queue.isPinned == pinned) continue
                queueDao.upsertQueue(queue.copy(isPinned = pinned, dateUpdated = now))
            }
        }
    }

    /** Rewrites custom-queue [ReadingQueue.sortOrder] to match [orderedIds]. */
    suspend fun reorderQueues(orderedIds: List<String>) {
        val now = clock()
        database.withTransaction {
            orderedIds.forEachIndexed { index, id ->
                val queue = queueDao.getQueueById(id) ?: return@forEachIndexed
                if (queue.kindRaw != ReadingQueueKind.CUSTOM || queue.sortOrder == index) return@forEachIndexed
                queueDao.upsertQueue(queue.copy(sortOrder = index, dateUpdated = now))
            }
        }
    }

    suspend fun tagsForQueue(queueId: String): List<Tag> {
        val tags = tagDao.getAll().associateBy { it.id }
        return readingLogDao.getQueueTags(queueId).mapNotNull { ref ->
            tags[ref.tagId]?.toDomain()
        }.sortedBy { it.name.lowercase() }
    }

    suspend fun tagsByQueue(): Map<String, List<Tag>> {
        val tags = tagDao.getAll().associateBy { it.id }
        return readingLogDao.getAllQueueTags().groupBy { it.queueId }.mapValues { (_, refs) ->
            refs.mapNotNull { tags[it.tagId]?.toDomain() }.sortedBy { it.name.lowercase() }
        }
    }

    suspend fun allTags(): List<Tag> = tagDao.getAll().map { it.toDomain() }

    /**
     * Replaces this queue's tags with [tagNames]. A name is looked up
     * case-insensitively before a tag is created. Tags that come off stay in
     * the shared vocabulary. Stamps [ReadingQueue.dateUpdated] when the set changes.
     */
    suspend fun replaceQueueTags(queueId: String, tagNames: List<String>) {
        val queue = queueDao.getQueueById(queueId) ?: return
        val desired = LinkedHashSet<String>()
        for (raw in tagNames) {
            val tag = findOrCreateTag(raw) ?: continue
            desired.add(tag.id)
        }
        val existing = readingLogDao.getQueueTags(queueId).map { it.tagId }.toSet()
        var changed = false
        for (tagId in existing) {
            if (tagId !in desired) {
                readingLogDao.deleteQueueTag(queueId, tagId)
                changed = true
            }
        }
        for (tagId in desired) {
            if (tagId !in existing) {
                readingLogDao.upsertQueueTag(QueueTagCrossRef(queueId = queueId, tagId = tagId))
                changed = true
            }
        }
        if (changed) {
            val fresh = queueDao.getQueueById(queueId) ?: queue
            queueDao.upsertQueue(fresh.copy(dateUpdated = clock()))
        }
    }

    /**
     * One tag across several queues. On every selected queue it comes off;
     * on some or none it goes on the rest. "Some" never clears.
     */
    suspend fun toggleSharedTag(queueIds: List<String>, tagName: String) {
        val tag = findOrCreateTag(tagName) ?: return
        val ids = queueIds.mapNotNull { id ->
            queueDao.getQueueById(id)?.takeIf { !it.isDeleted }?.id
        }
        if (ids.isEmpty()) return
        val tagged = ids.filter { id ->
            readingLogDao.getQueueTags(id).any { it.tagId == tag.id }
        }.toSet()
        val enable = tagged.size != ids.size
        val now = clock()
        for (id in ids) {
            val has = id in tagged
            if (enable && !has) {
                readingLogDao.upsertQueueTag(QueueTagCrossRef(queueId = id, tagId = tag.id))
                stampQueue(id, now)
            } else if (!enable && has) {
                readingLogDao.deleteQueueTag(id, tag.id)
                stampQueue(id, now)
            }
        }
    }

    suspend fun savedForLaterSeedCount(): Int {
        val queue = queueDao.getActiveQueueByKind(ReadingQueueKind.SAVED_FOR_LATER) ?: return 0
        return listWorks(queue.id).size
    }

    /** How many visible works in [queueId] carry each user tag. Recently Deleted is excluded. */
    suspend fun workTagCounts(queueId: String): Map<String, Int> {
        val counts = mutableMapOf<String, Int>()
        for (item in listWorks(queueId)) {
            val work = item.work ?: continue
            for (tag in tagDao.getTagsForWork(work.id)) {
                counts[tag.id] = (counts[tag.id] ?: 0) + 1
            }
        }
        return counts
    }

    /** User-tag names on each work, for "show only this tag". */
    suspend fun userTagNamesByWork(workIds: List<String>): Map<String, Set<String>> {
        return workIds.associateWith { id -> tagDao.getTagsForWork(id).map { it.name }.toSet() }
    }

    /** The other tag a rename would collide with, matched without regard to case. */
    suspend fun tagRenameConflict(tagId: String, proposed: String): Tag? {
        val trimmed = proposed.trim()
        if (trimmed.isEmpty()) return null
        val other = tagDao.getByNameCaseInsensitive(trimmed) ?: return null
        return if (other.id == tagId) null else other.toDomain()
    }

    /** Renames the shared tag. A colliding name is left untouched. */
    suspend fun renameUserTag(tagId: String, proposed: String) {
        if (tagRenameConflict(tagId, proposed) != null) return
        val current = tagDao.getById(tagId) ?: return
        val trimmed = proposed.trim()
        if (trimmed.isEmpty() || trimmed == current.name) return
        tagDao.upsert(current.copy(name = trimmed))
    }

    /**
     * Moves this queue's works from [fromTagId] onto [intoTagId], then takes
     * [fromTagId] off the queue. Works outside the queue keep [fromTagId].
     */
    suspend fun mergeQueueTag(queueId: String, fromTagId: String, intoTagId: String) {
        if (fromTagId == intoTagId) return
        for (item in listWorks(queueId)) {
            val work = item.work ?: continue
            val tags = tagDao.getTagsForWork(work.id)
            if (tags.none { it.id == fromTagId }) continue
            tagDao.removeFromWork(work.id, fromTagId)
            if (tags.none { it.id == intoTagId }) {
                tagDao.addToWork(WorkTagCrossRef(workId = work.id, tagId = intoTagId))
            }
        }
        readingLogDao.deleteQueueTag(queueId, fromTagId)
        if (readingLogDao.getQueueTags(queueId).none { it.tagId == intoTagId }) {
            readingLogDao.upsertQueueTag(QueueTagCrossRef(queueId = queueId, tagId = intoTagId))
        }
        stampQueue(queueId, clock())
    }

    /** Takes [tagId] off this queue's visible works and off the queue. The tag row stays. */
    suspend fun stripQueueTag(queueId: String, tagId: String) {
        for (item in listWorks(queueId)) {
            val work = item.work ?: continue
            tagDao.removeFromWork(work.id, tagId)
        }
        readingLogDao.deleteQueueTag(queueId, tagId)
        stampQueue(queueId, clock())
    }

    /** Puts an existing tag name on another queue. Lookup before create. */
    suspend fun copyTagToQueue(tagName: String, destinationQueueId: String) {
        val tag = findOrCreateTag(tagName) ?: return
        if (readingLogDao.getQueueTags(destinationQueueId).any { it.tagId == tag.id }) return
        readingLogDao.upsertQueueTag(QueueTagCrossRef(queueId = destinationQueueId, tagId = tag.id))
        stampQueue(destinationQueueId, clock())
    }

    /** Active library works that are not already in [queueId]. */
    suspend fun worksAvailableToAdd(queueId: String): List<SavedWork> {
        val memberIds = queueDao.getMembershipsForQueue(queueId).map { it.workID }.toSet()
        return workDao.getAll().map { it.toDomain() }.filter { work ->
            !work.isDeleted && work.id !in memberIds
        }.sortedBy { it.title.lowercase() }
    }

    private suspend fun findOrCreateTag(raw: String): TagEntity? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return null
        tagDao.getByNameCaseInsensitive(trimmed)?.let { return it }
        val created = Tag(name = trimmed, dateCreated = clock())
        tagDao.upsert(created.toEntity())
        return created.toEntity()
    }

    private suspend fun stampQueue(queueId: String, now: Instant) {
        val queue = queueDao.getQueueById(queueId) ?: return
        queueDao.upsertQueue(queue.copy(dateUpdated = now))
    }

    suspend fun addToSavedForLater(workId: String): ReadingQueueMembership {
        val queue = ensureSavedForLaterQueue()
        return addWork(queue.id, workId)
    }

    suspend fun isInSavedForLater(workId: String): Boolean {
        val queue = queueDao.getActiveQueueByKind(ReadingQueueKind.SAVED_FOR_LATER) ?: return false
        return queueDao.getMembershipForWork(queue.id, workId) != null
    }

    suspend fun removeFromSavedForLater(workId: String) {
        val queue = queueDao.getActiveQueueByKind(ReadingQueueKind.SAVED_FOR_LATER) ?: return
        removeWork(queue.id, workId)
    }

    suspend fun renameQueue(queueId: String, newName: String) {
        val trimmed = newName.trim()
        require(trimmed.isNotEmpty()) { "Queue name must not be blank." }
        val queue = queueDao.getQueueById(queueId) ?: return
        require(queue.kindRaw != ReadingQueueKind.SAVED_FOR_LATER) { "Cannot rename system queues." }
        queueDao.upsertQueue(
            queue.copy(
                name = trimmed,
                dateUpdated = clock()
            )
        )
    }

    suspend fun deleteQueue(queueId: String) {
        val queue = queueDao.getQueueById(queueId) ?: return
        require(queue.kindRaw != ReadingQueueKind.SAVED_FOR_LATER) { "Cannot delete system queues." }
        val now = clock()
        queueDao.upsertQueue(
            queue.copy(
                isDeleted = true,
                deletedAt = now,
                permanentDeletionScheduledAt = now.plus(WorkRepository.RECOVERY_WINDOW),
                dateUpdated = now
            )
        )
    }

    suspend fun updateSortOrder(queueId: String, workIds: List<String>) {
        val now = clock()
        database.withTransaction {
            workIds.forEachIndexed { index, workId ->
                queueDao.getMembershipForWork(queueId, workId)?.let { membership ->
                    queueDao.upsertMembership(
                        membership.copy(
                            sortOrderInQueue = index,
                            lastModifiedAt = now
                        )
                    )
                }
            }
        }
        touchQueueMembershipChanged(queueId, now)
    }

    suspend fun listRecentlyDeletedQueues(): List<ReadingQueue> {
        return queueDao.getAllQueues().filter { it.isDeleted }.map { it.toDomain() }
    }

    suspend fun restoreQueueFromRecentlyDeleted(queueId: String): ReadingQueue? {
        val queue = queueDao.getQueueById(queueId) ?: return null
        val now = clock()
        val restored = queue.copy(
            isDeleted = false,
            deletedAt = null,
            permanentDeletionScheduledAt = null,
            dateUpdated = now
        )
        queueDao.upsertQueue(restored)
        tombstoneDao.deleteByRecord(queueId, SyncTombstoneRecordType.READING_QUEUE)
        return restored.toDomain()
    }

    suspend fun hardDeleteQueue(queueId: String) {
        queueDao.deleteQueueById(queueId)
        // Membership rows cascade via FK in DB.
        val now = clock()
        upsertSignedTombstone(
            SyncTombstone(
                id = uuidFactory(),
                recordID = queueId,
                recordTypeRaw = SyncTombstoneRecordType.READING_QUEUE,
                createdAt = now,
                lastModifiedAt = now,
                deletedOnDeviceID = "",
                deletionReason = "queueDeleted"
            )
        )
    }

    suspend fun sweepExpiredQueueSoftDeletes(): Int {
        val now = clock()
        val expired = queueDao.getAllQueues().filter { 
            it.isDeleted && it.permanentDeletionScheduledAt != null && it.permanentDeletionScheduledAt!! <= now 
        }
        for (entity in expired) {
            hardDeleteQueue(entity.id)
        }
        return expired.size
    }

    fun observeAllUserTags(): Flow<List<Tag>> {
        return tagDao.observeAll().map { tags -> tags.map { it.toDomain() } }
    }

    fun observeAllCollections(): Flow<List<WorkCollection>> {
        return collectionDao.observeAllActive().map { entities ->
            entities.map { it.toDomain() }
        }
    }

    private suspend fun upsertSignedTombstone(tombstone: SyncTombstone) {
        tombstoneDao.upsert(TombstoneSigning.sign(tombstone).toEntity())
    }

    private suspend fun touchQueueMembershipChanged(queueId: String, now: Instant) {
        val queue = queueDao.getQueueById(queueId) ?: return
        queueDao.upsertQueue(
            queue.copy(
                dateUpdated = now,
                lastMembershipChangedAt = now
            )
        )
    }

    suspend fun preserveSeries(
        seriesUrl: String,
        targetQueues: List<ReadingQueue>?,
        seriesRepository: AO3SeriesRepository,
        workImporter: WorkImporter,
        pauseMillis: Long = 2000L,
        progress: ((SeriesPreservationResult) -> Unit)? = null,
        enqueueDownload: ((AO3WorkSummary) -> Unit)? = null
    ): SeriesPreservationResult {
        if (seriesUrl.isBlank()) return SeriesPreservationResult()

        val summaries = try {
            when (val result = seriesRepository.seriesWorks(seriesUrl)) {
                is AO3Result.Success -> result.value
                is AO3Result.Failure -> return SeriesPreservationResult(failed = 1)
            }
        } catch (e: kotlinx.coroutines.CancellationException) {
            return SeriesPreservationResult(cancelled = 1)
        } catch (e: Exception) {
            return SeriesPreservationResult(failed = 1)
        }

        return preserveSeries(
            summaries = summaries,
            targetQueues = targetQueues,
            workImporter = workImporter,
            pauseMillis = pauseMillis,
            progress = progress,
            enqueueDownload = enqueueDownload
        )
    }

    suspend fun preserveSeries(
        summaries: List<AO3WorkSummary>,
        targetQueues: List<ReadingQueue>?,
        workImporter: WorkImporter,
        pauseMillis: Long = 2000L,
        progress: ((SeriesPreservationResult) -> Unit)? = null,
        enqueueDownload: ((AO3WorkSummary) -> Unit)? = null
    ): SeriesPreservationResult {
        val result = SeriesPreservationResult(total = summaries.size)
        val queues = targetQueues ?: listOf(ensureSavedForLaterQueue())
        progress?.invoke(result.copy())

        for (summary in summaries) {
            if (!currentCoroutineContext().isActive) {
                result.cancelled += max(0, result.total - result.completed)
                progress?.invoke(result.copy())
                break
            }

            val existing = workDao.getBySourceUrl(summary.workUrl)?.toDomain()
                ?: workDao.getById(summary.id.toString())?.toDomain()

            if (existing != null) {
                if (existing.isDeleted) {
                    val now = clock()
                    val entity = workDao.getById(existing.id)
                    if (entity != null) {
                        workDao.upsert(entity.copy(
                            isDeleted = false,
                            deletedAt = null,
                            permanentDeletionScheduledAt = null,
                            lastModifiedAt = now
                        ))
                        val ao3Id = WorkTags.ao3WorkIdFromUrl(existing.sourceUrl)
                            ?.takeIf { it in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong() }
                            ?.toInt()
                        tombstoneDao.deleteSavedWorkByIdentity(
                            recordId = existing.id,
                            ao3WorkId = ao3Id,
                            canonicalSourceUrl = WorkTags.canonicalAO3WorkURL(existing.sourceUrl)
                                .orEmpty(),
                            sourceUrl = existing.sourceUrl,
                            recordType = SyncTombstoneRecordType.SAVED_WORK
                        )
                    }
                }

                val isInAllQueues = queues.all { q ->
                    queueDao.getMembershipForWork(q.id, existing.id) != null
                }

                if (existing.hasEpub && isInAllQueues) {
                    result.alreadyPreserved += 1
                    progress?.invoke(result.copy())
                    continue
                }

                if (existing.hasEpub) {
                    for (queue in queues) {
                        addWork(queue.id, existing.id)
                    }
                    result.alreadyPreserved += 1
                    progress?.invoke(result.copy())
                    continue
                }
            }

            if (queues.isEmpty()) {
                result.skipped += 1
                progress?.invoke(result.copy())
                continue
            }

            try {
                currentCoroutineContext().ensureActive()
                val importResult = workImporter.saveMetadataOnly(
                    summary,
                    markSaved = false,
                    isQueuedForLater = true
                )
                when (importResult) {
                    is WorkImportResult.Success -> {
                        val saved = importResult.work
                        for (queue in queues) {
                            addWork(queue.id, saved.id)
                        }
                        enqueueDownload?.invoke(summary)
                        result.preserved += 1
                    }
                    is WorkImportResult.Failure -> {
                        result.failed += 1
                    }
                }
            } catch (e: kotlinx.coroutines.CancellationException) {
                result.cancelled += max(1, result.total - result.completed)
                progress?.invoke(result.copy())
                break
            } catch (e: Exception) {
                result.failed += 1
            }
            progress?.invoke(result.copy())

            if (result.completed < result.total && pauseMillis > 0) {
                try {
                    delay(pauseMillis)
                } catch (e: kotlinx.coroutines.CancellationException) {
                    result.cancelled += max(0, result.total - result.completed)
                    progress?.invoke(result.copy())
                    break
                }
            }
        }
        return result
    }
}

data class QueueMembershipItem(
    val membership: ReadingQueueMembership,
    val work: SavedWork?,
    val title: String,
    val author: String
)

/** Fields the New Queue / Edit Queue sheet writes. Name and hue travel beside it. */
data class QueueEdit(
    val name: String,
    val hue: Double?,
    val colorHex: String?,
    val keepsWorksOffline: Boolean,
    val notes: String? = null,
    val tagNames: List<String> = emptyList()
)
