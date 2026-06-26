package io.github.cidy02.kudos.backup

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject

@Serializable
data class KudosBackupManifest(
    val version: Int,
    val exportedAt: String,
    val works: List<BackupWork>,
    val bookmarks: List<BackupBookmark>,
    val fonts: List<BackupFont>,
    val settings: BackupSettingsPayload,
    val exportedBy: BackupExportedBy? = null,
    val collections: List<BackupCollection> = emptyList(),
    val savedSearches: List<BackupSavedSearch> = emptyList()
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
    val title: String,
    val author: String,
    val summary: String,
    @SerialName("sourceURL") val sourceURL: String,
    val dateAdded: String,
    val isFavorite: Boolean,
    val isSaved: Boolean,
    val isFinished: Boolean,
    @SerialName("hasEPUB") val hasEPUB: Boolean,
    val isComplete: Boolean,
    val rating: String,
    val language: String,
    val wordCount: Int,
    val chapters: String,
    val kudos: Int,
    val workWarnings: List<String>,
    val workCategories: List<String>,
    val seriesTitle: String,
    val seriesPosition: Int,
    @SerialName("seriesURL") val seriesURL: String,
    val lastSpineIndex: Int,
    val lastScrollFraction: Double,
    val workTags: List<String>,
    val workFandoms: List<String>,
    val workCharacters: List<String>,
    val workRelationships: List<String>,
    val workFreeforms: List<String>,
    val workTagsFetched: Boolean,
    val userTags: List<String>,
    val lastReadDate: String? = null,
    val readiumLocator: String? = null,
    val readiumLocatorPlatform: String? = null,
    val readiumLocatorEngine: String? = null,
    val readiumLocatorVersion: String? = null,
    val comments: Int? = null,
    val hits: Int? = null,
    val knownChapterCount: Int? = null,
    val lastUpdateCheck: String? = null,
    @SerialName("collectionIDs") val collectionIDs: List<String> = emptyList()
)

@Serializable
data class BackupBookmark(
    val title: String,
    val urlString: String,
    val dateAdded: String
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
    val sortOrder: Int? = null
)

@Serializable
data class BackupSavedSearch(
    val id: String,
    val name: String,
    val dateAdded: String,
    val filters: JsonObject = buildJsonObject {}
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
    val accentColorHex: String = "#990000"
)
