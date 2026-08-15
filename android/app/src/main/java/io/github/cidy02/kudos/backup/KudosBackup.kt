package io.github.cidy02.kudos.backup

import io.github.cidy02.kudos.core.model.BackupSettings as CoreBackupSettings
import io.github.cidy02.kudos.core.model.Bookmark
import io.github.cidy02.kudos.core.model.CustomFont
import io.github.cidy02.kudos.core.model.ReadingAnnotation
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.ReadingQueueMembership
import io.github.cidy02.kudos.core.model.SavedSearch
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.SyncTombstone
import io.github.cidy02.kudos.core.model.WorkCollection

data class KudosBackupPackage(
    val manifest: KudosBackupManifest,
    val epubFilesByWorkId: Map<String, ByteArray> = emptyMap(),
    val fontFilesByFileName: Map<String, ByteArray> = emptyMap()
)

data class BackupLibrarySnapshot(
    val works: List<SavedWork> = emptyList(),
    val userTagsByWorkId: Map<String, List<String>> = emptyMap(),
    val bookmarks: List<Bookmark> = emptyList(),
    val fonts: List<CustomFont> = emptyList(),
    val collections: List<WorkCollection> = emptyList(),
    val savedSearches: List<SavedSearch> = emptyList(),
    val settings: CoreBackupSettings = CoreBackupSettings(),
    val epubWorkIds: Set<String> = works
        .filter { it.hasEpub }
        .map { BackupPaths.normalizeIdForComparison(it.id) }
        .toSet(),
    val fontFilesByFileName: Map<String, ByteArray> = emptyMap(),
    val tombstones: List<SyncTombstone> = emptyList(),
    val readingQueues: List<ReadingQueue> = emptyList(),
    val readingQueueMemberships: List<ReadingQueueMembership> = emptyList(),
    val annotations: List<ReadingAnnotation> = emptyList()
)

enum class BackupImportMode {
    /** Add works not already present. Keep local overlap. Do not adopt unsigned tombstones. */
    MERGE,

    /**
     * This device's library becomes the snapshot. Fonts, appearance, and login stay.
     * Does not persist the file's unsigned tombstones or mint new ones for removals.
     */
    REPLACE_LIBRARY
}

data class BackupImportPreview(
    val localWorkCount: Int,
    val fileWorkCount: Int,
    val willAdd: Int,
    val willRemove: Int,
    val inBoth: Int
) {
    val isLibraryEmpty: Boolean get() = localWorkCount == 0
    val isMuchSmallerThanLibrary: Boolean
        get() = willRemove > 0 && fileWorkCount * 2 < localWorkCount
}

data class BackupRestoreSummary(
    val worksCreated: Int = 0,
    val worksUpdated: Int = 0,
    val worksSuppressed: Int = 0,
    val worksRemoved: Int = 0,
    val bookmarksCreated: Int = 0,
    val bookmarksUpdated: Int = 0,
    val fontsCreated: Int = 0,
    val fontsUpdated: Int = 0,
    val collectionsCreated: Int = 0,
    val collectionsUpdated: Int = 0,
    val savedSearchesCreated: Int = 0,
    val savedSearchesUpdated: Int = 0,
    val queuesCreated: Int = 0,
    val queuesUpdated: Int = 0,
    val membershipsCreated: Int = 0,
    val membershipsUpdated: Int = 0,
    val membershipsSuppressed: Int = 0,
    val annotationsCreated: Int = 0,
    val annotationsUpdated: Int = 0,
    val annotationsSuppressed: Int = 0
)

data class BackupMergeResult(
    val snapshot: BackupLibrarySnapshot,
    val summary: BackupRestoreSummary,
    val epubFilesToWriteByWorkId: Map<String, ByteArray> = emptyMap(),
    val fontFilesToWriteByFileName: Map<String, ByteArray> = emptyMap(),
    val mode: BackupImportMode = BackupImportMode.MERGE
)
