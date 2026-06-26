package io.github.cidy02.kudos.backup

import io.github.cidy02.kudos.core.model.BackupSettings as CoreBackupSettings
import io.github.cidy02.kudos.core.model.Bookmark
import io.github.cidy02.kudos.core.model.CustomFont
import io.github.cidy02.kudos.core.model.SavedSearch
import io.github.cidy02.kudos.core.model.SavedWork
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
    val fontFilesByFileName: Map<String, ByteArray> = emptyMap()
)

data class BackupRestoreSummary(
    val worksCreated: Int = 0,
    val worksUpdated: Int = 0,
    val bookmarksCreated: Int = 0,
    val bookmarksUpdated: Int = 0,
    val fontsCreated: Int = 0,
    val fontsUpdated: Int = 0,
    val collectionsCreated: Int = 0,
    val collectionsUpdated: Int = 0,
    val savedSearchesCreated: Int = 0,
    val savedSearchesUpdated: Int = 0
)

data class BackupMergeResult(
    val snapshot: BackupLibrarySnapshot,
    val summary: BackupRestoreSummary,
    val epubFilesToWriteByWorkId: Map<String, ByteArray> = emptyMap(),
    val fontFilesToWriteByFileName: Map<String, ByteArray> = emptyMap()
)
