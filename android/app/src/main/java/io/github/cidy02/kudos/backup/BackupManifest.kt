package io.github.cidy02.kudos.backup

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject

@Serializable
data class KudosBackupManifest(
    val version: Int,
    val exportedAt: String,
    val works: List<BackupWork> = emptyList(),
    val bookmarks: List<BackupBookmark> = emptyList(),
    val fonts: List<BackupFont> = emptyList(),
    val settings: BackupSettingsPayload = BackupSettingsPayload(),
    val exportedBy: BackupExportedBy? = null,
    val collections: List<BackupCollection> = emptyList(),
    val savedSearches: List<BackupSavedSearch> = emptyList(),
    /** Apple v3+ reading queues — decoded and applied by [io.github.cidy02.kudos.backup.BackupMergeService]. */
    val readingQueues: List<BackupReadingQueue> = emptyList(),
    val readingQueueMemberships: List<BackupReadingQueueMembership> = emptyList(),
    /** Apple v8+ in-book annotations — decoded and applied by [io.github.cidy02.kudos.backup.BackupMergeService]. */
    val annotations: List<BackupAnnotation> = emptyList(),
    /** Apple sync tombstones — decoded so we do not fail on v5+ archives. */
    val tombstones: List<BackupTombstone> = emptyList()
)

@Serializable
data class BackupExportedBy(
    val app: String = "Kudos",
    val platform: String,
    val appVersion: String,
    val schemaVersion: Int = 1
)

@Serializable
data class BackupWork(
    val id: String,
    val title: String = "",
    val author: String = "",
    val summary: String = "",
    @SerialName("sourceURL") val sourceURL: String = "",
    val dateAdded: String = "",
    val isFavorite: Boolean = false,
    val isSaved: Boolean = false,
    val isFinished: Boolean = false,
    @SerialName("hasEPUB") val hasEPUB: Boolean = false,
    val isComplete: Boolean = false,
    val rating: String = "",
    val language: String = "",
    val wordCount: Int = 0,
    val chapters: String = "",
    val kudos: Int = 0,
    val workWarnings: List<String> = emptyList(),
    val workCategories: List<String> = emptyList(),
    val seriesTitle: String = "",
    val seriesPosition: Int = 0,
    @SerialName("seriesURL") val seriesURL: String = "",
    val lastSpineIndex: Int = 0,
    val lastScrollFraction: Double = 0.0,
    val workTags: List<String> = emptyList(),
    val workFandoms: List<String> = emptyList(),
    val workCharacters: List<String> = emptyList(),
    val workRelationships: List<String> = emptyList(),
    val workFreeforms: List<String> = emptyList(),
    val workTagsFetched: Boolean = false,
    val userTags: List<String> = emptyList(),
    val lastReadDate: String? = null,
    val readiumLocator: String? = null,
    val readiumLocatorPlatform: String? = null,
    val readiumLocatorEngine: String? = null,
    val readiumLocatorVersion: String? = null,
    val comments: Int? = null,
    val hits: Int? = null,
    val knownChapterCount: Int? = null,
    val lastUpdateCheck: String? = null,
    @SerialName("collectionIDs") val collectionIDs: List<String> = emptyList(),
    // Apple v5–v8 optional work fields (ignored for local model until ported).
    val createdAt: String? = null,
    val lastModifiedAt: String? = null,
    val deletedAt: String? = null,
    val isDeleted: Boolean? = null,
    val permanentDeletionScheduledAt: String? = null,
    val assetIdentifier: String? = null,
    val datePublished: String? = null,
    val dateUpdated: String? = null,
    val ao3SeriesID: Int? = null,
    val progressModifiedAt: String? = null,
    val ao3Unavailable: Boolean? = null,
    val isQueuedForLater: Boolean? = null,
    val epubPreservationStatusRaw: String? = null,
    val metadataSyncStatusRaw: String? = null,
    val preservedAt: String? = null,
    val lastPreservationAttemptAt: String? = null,
    val lastAvailabilityCheck: String? = null,
    val ao3WorkID: Int? = null
)

@Serializable
data class BackupBookmark(
    val title: String,
    val urlString: String,
    val dateAdded: String,
    val id: String? = null
)

@Serializable
data class BackupFont(
    val name: String,
    val fileName: String,
    val dateAdded: String
)

@Serializable
data class BackupCollection(
    val id: String,
    val name: String,
    val dateAdded: String,
    @SerialName("workIDs") val workIDs: List<String> = emptyList(),
    val description: String? = null,
    val sortOrder: Int? = null,
    val createdAt: String? = null,
    val lastModifiedAt: String? = null,
    val deletedAt: String? = null,
    val isDeleted: Boolean? = null,
    val permanentDeletionScheduledAt: String? = null,
    val syncStatusRaw: String? = null
)

@Serializable
data class BackupSavedSearch(
    val id: String,
    val name: String,
    val dateAdded: String,
    val filters: JsonObject = buildJsonObject {}
)

@Serializable
data class BackupReadingQueue(
    val id: String,
    val name: String = "",
    val kindRaw: String = "",
    val sortOrder: Int = 0,
    val dateCreated: String = "",
    val dateUpdated: String = "",
    val lastMembershipChangedAt: String? = null,
    val deletedAt: String? = null,
    val isDeleted: Boolean? = null,
    val permanentDeletionScheduledAt: String? = null
)

@Serializable
data class BackupReadingQueueMembership(
    val id: String,
    val queueID: String,
    val workID: String,
    val queuedAt: String = "",
    val lastModifiedAt: String? = null,
    val sortOrderInQueue: Int = 0,
    val note: String = ""
)

/** Apple v8 in-book annotation transport. */
@Serializable
data class BackupAnnotation(
    val id: String,
    val workID: String,
    val kindRaw: String = "bookmark",
    val colorRaw: String = "",
    val locatorString: String = "",
    val selectedText: String = "",
    val note: String = "",
    val progression: Double = 0.0,
    val spineIndex: Int = 0,
    val chapterTitle: String = "",
    val createdAt: String = "",
    val lastModifiedAt: String? = null,
    val deletedAt: String? = null,
    val isPendingDeletion: Boolean = false
)

@Serializable
data class BackupTombstone(
    val id: String,
    val recordID: String,
    val recordTypeRaw: String = "",
    val createdAt: String = "",
    val lastModifiedAt: String = "",
    val sourceURL: String = "",
    val ao3WorkID: Int? = null,
    val deletedOnDeviceID: String = "",
    val deletionReason: String = "",
    val signerPublicKey: String = "",
    val signature: String = ""
)

@Serializable
data class BackupSettingsPayload(
    val readerFontID: String = "system",
    val readerMode: String = "scroll",
    val readerTwoPage: Boolean = false,
    val readerCustomize: Boolean = false,
    val readerBoldText: Boolean = false,
    val readerFontPt: Double = 18.0,
    val readerLineHeight: Double = 1.65,
    val readerLetterSpacing: Double = 0.0,
    val readerWordSpacing: Double = 0.0,
    val readerMargin: Double = 28.0,
    val readerJustify: Boolean = false,
    val confirmBeforeDelete: Boolean = true,
    val hideMatureContent: Boolean = true,
    val matureContentMode: String = "obscure",
    val requireBiometricToReveal: Boolean = false,
    val appTheme: String = "light",
    val readerTheme: String = "light",
    val matchAppReaderTheme: Boolean = true,
    val accentColorHex: String = "#990000",
    val autoPreserveSmallSeriesOnSaveForLater: Boolean = false,
    val autoPreserveSeriesWorkThreshold: Int = 5
)
