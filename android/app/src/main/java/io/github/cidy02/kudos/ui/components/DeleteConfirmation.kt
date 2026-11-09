package io.github.cidy02.kudos.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AlertDialogDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.files.ImportedFileFormat
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.library.LibraryPrivacy
import io.github.cidy02.kudos.library.LibraryPrivacyVisibility
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.works.WorkConversionRecord
import java.net.URI
import java.nio.file.Files
import java.nio.file.Path
import java.util.UUID

enum class WorkOrigin(
    val displayName: String,
    val hostPatterns: List<String>,
    val supportsLiveLookup: Boolean = false
) {
    ARCHIVE_OF_OUR_OWN("Archive of Our Own", listOf("archiveofourown.org", "ao3.org"), supportsLiveLookup = true),
    FANFICTION_NET("FanFiction.net", listOf("fanfiction.net")),
    FICTION_PRESS("FictionPress", listOf("fictionpress.com")),
    WATTPAD("Wattpad", listOf("wattpad.com")),
    ROYAL_ROAD("Royal Road", listOf("royalroad.com")),
    SPACE_BATTLES("SpaceBattles", listOf("forums.spacebattles.com", "spacebattles.com")),
    SUFFICIENT_VELOCITY("Sufficient Velocity", listOf("forums.sufficientvelocity.com", "sufficientvelocity.com")),
    SQUIDGE_WORLD("SquidgeWorld", listOf("squidgeworld.org")),
    TUMBLR("Tumblr", listOf("tumblr.com")),
    LIVE_JOURNAL("LiveJournal", listOf("livejournal.com")),
    ARCHIVE_OF_OUR_OWN_MIRROR("AO3 mirror", listOf("ao3.satr.dev", "archive.org")),
    IMPORTED_FILE("Imported file", emptyList()),
    UNKNOWN("Other site", emptyList());

    companion object {
        fun detect(sourceUrl: String): WorkOrigin {
            val trimmed = sourceUrl.trim()
            if (trimmed.isEmpty()) return IMPORTED_FILE
            val host = runCatching { URI(trimmed).host?.lowercase() }.getOrNull()
                ?.takeIf { it.isNotEmpty() }
                ?: trimmed.lowercase()
            for (candidate in entries) {
                if (candidate.hostPatterns.any { host.contains(it) }) return candidate
            }
            return UNKNOWN
        }

        fun of(work: SavedWork): WorkOrigin {
            if (work.ao3WorkID != null) return ARCHIVE_OF_OUR_OWN
            return detect(work.sourceUrl)
        }
    }
}

data class OriginalFileExport(
    val path: Path,
    val suggestedName: String
)

sealed class WorkRedownloadability {
    data object CanRedownload : WorkRedownloadability()
    data object NoLongerOnAO3 : WorkRedownloadability()
    data class Imported(
        val formatDisplayName: String?,
        val origin: WorkOrigin
    ) : WorkRedownloadability()

    val canRedownload: Boolean
        get() = this is CanRedownload

    fun shouldConfirmDelete(settingOn: Boolean): Boolean =
        settingOn || !canRedownload

    val rowTitle: String?
        get() = when (this) {
            CanRedownload -> null
            NoLongerOnAO3 -> "No longer on AO3."
            is Imported -> "Imported ${importedLead(formatDisplayName, origin)}."
        }

    val rowBody: String?
        get() = when (this) {
            CanRedownload -> null
            NoLongerOnAO3 -> "The author removed it or made it private, so Kudos can't download it again."
            is Imported -> "Kudos can only download from AO3, so this copy is the only one."
        }

    val importSourcePhrase: String?
        get() = when (this) {
            is Imported -> importedSourcePhrase(formatDisplayName, origin)
            CanRedownload, NoLongerOnAO3 -> null
        }

    companion object {
        fun of(
            origin: WorkOrigin,
            ao3Unavailable: Boolean,
            importFormatDisplayName: String? = null
        ): WorkRedownloadability {
            if (origin.supportsLiveLookup) {
                return if (ao3Unavailable) NoLongerOnAO3 else CanRedownload
            }
            return Imported(formatDisplayName = cleanedFormat(importFormatDisplayName), origin = origin)
        }

        fun of(work: SavedWork, fileStore: WorkFileStore? = null): WorkRedownloadability {
            val origin = WorkOrigin.of(work)
            val formatName = if (origin.supportsLiveLookup) null else importFormatDisplayName(work.id, fileStore)
            return of(origin = origin, ao3Unavailable = work.ao3Unavailable, importFormatDisplayName = formatName)
        }

        fun importFormatDisplayName(workId: String, fileStore: WorkFileStore?): String? {
            val store = fileStore ?: return null
            val recordBytes = runCatching {
                val path = store.conversionRecordPath(workId)
                if (Files.exists(path)) Files.readAllBytes(path) else null
            }.getOrNull()
            val record = WorkConversionRecord.decode(recordBytes)
            if (record != null) {
                formatDisplayName(record.format)?.let { return it }
            }
            val originalPath = store.originalFile(workId) ?: return null
            val bytes = runCatching { Files.readAllBytes(originalPath) }.getOrNull() ?: return null
            val format = ImportedFileFormat.sniff(bytes, originalPath.fileName?.toString().orEmpty())
            return formatDisplayName(format)
        }

        fun originalFile(workId: String, fileStore: WorkFileStore?): OriginalFileExport? {
            val store = fileStore ?: return null
            val path = store.originalFile(workId) ?: return null
            val recordBytes = runCatching {
                val recordPath = store.conversionRecordPath(workId)
                if (Files.exists(recordPath)) Files.readAllBytes(recordPath) else null
            }.getOrNull()
            val recorded = WorkConversionRecord.decode(recordBytes)?.originalFileName?.trim().orEmpty()
            val baseName = recorded.substringAfterLast('/').substringAfterLast('\\')
            val stem = baseName.substringBeforeLast('.', missingDelimiterValue = baseName)
            val isUuidNamed = runCatching { UUID.fromString(stem) }.isSuccess
            if (baseName.isNotEmpty() && !isUuidNamed) {
                return OriginalFileExport(path = path, suggestedName = baseName)
            }
            val fileName = path.fileName?.toString().orEmpty()
            val ext = fileName.substringAfterLast('.', missingDelimiterValue = "")
            val fallback = if (ext.isEmpty()) "Original" else "Original.$ext"
            return OriginalFileExport(path = path, suggestedName = fallback)
        }

        internal fun formatDisplayName(rawFormat: String): String? = when (rawFormat) {
            "epub" -> "EPUB"
            "html" -> "HTML"
            "plainText" -> "plain text"
            "zip" -> "ZIP archive"
            "docx" -> "Word document"
            "odt" -> "OpenDocument text"
            "pdf" -> "PDF"
            "rtf" -> "RTF"
            "mobi" -> "Kindle book"
            "rar" -> "RAR archive"
            "sevenZip" -> "7-Zip archive"
            else -> null
        }

        internal fun formatDisplayName(format: ImportedFileFormat): String? = when (format) {
            ImportedFileFormat.EPUB -> "EPUB"
            ImportedFileFormat.HTML -> "HTML"
            ImportedFileFormat.TEXT -> "plain text"
            ImportedFileFormat.ZIP -> "ZIP archive"
            ImportedFileFormat.DOCX -> "Word document"
            ImportedFileFormat.ODT -> "OpenDocument text"
            ImportedFileFormat.PDF -> "PDF"
            ImportedFileFormat.RTF -> "RTF"
            ImportedFileFormat.MOBI -> "Kindle book"
            ImportedFileFormat.RAR -> "RAR archive"
            ImportedFileFormat.SEVEN_ZIP -> "7-Zip archive"
            ImportedFileFormat.UNKNOWN -> null
        }

        private fun cleanedFormat(name: String?): String? =
            name?.trim()?.takeIf { it.isNotEmpty() }

        private fun siteName(origin: WorkOrigin): String? = when (origin) {
            WorkOrigin.IMPORTED_FILE -> null
            WorkOrigin.UNKNOWN -> "another site"
            else -> origin.displayName
        }

        private fun importedLead(format: String?, origin: WorkOrigin): String {
            val fmt = cleanedFormat(format)
            val site = siteName(origin)
            return when {
                fmt != null && site != null -> "$fmt from $site"
                fmt != null -> fmt
                site != null -> "from $site"
                else -> "file"
            }
        }

        private fun importedSourcePhrase(format: String?, origin: WorkOrigin): String {
            val fmt = cleanedFormat(format)
            val site = siteName(origin)
            return when {
                fmt != null && site != null -> "${article(fmt)} from $site"
                fmt != null -> article(fmt)
                site != null -> site
                else -> "a file"
            }
        }

        private fun article(format: String): String {
            val first = format.firstOrNull() ?: return "a $format"
            val spelledOut = format.all { it.isUpperCase() || it.isDigit() }
            val an = if (spelledOut) {
                first in "AEFHILMNORSX"
            } else {
                first.lowercaseChar() in "aeiou"
            }
            return if (an) "an $format" else "a $format"
        }
    }
}

fun shouldConfirmDelete(
    work: SavedWork,
    settingOn: Boolean,
    fileStore: WorkFileStore? = null
): Boolean = WorkRedownloadability.of(work, fileStore).shouldConfirmDelete(settingOn)

fun shouldConfirmDelete(
    works: List<SavedWork>,
    settingOn: Boolean,
    fileStore: WorkFileStore? = null
): Boolean = settingOn || works.any { !WorkRedownloadability.of(it, fileStore).canRedownload }

fun deleteConfirmationMessage(
    work: SavedWork,
    permanently: Boolean = false,
    fileStore: WorkFileStore? = null,
    visibility: LibraryPrivacyVisibility = LibraryPrivacyVisibility.Visible
): String = deleteConfirmationMessage(
    title = work.title,
    reason = WorkRedownloadability.of(work, fileStore),
    permanently = permanently,
    concealed = visibility != LibraryPrivacyVisibility.Visible
)

fun deleteConfirmationMessage(
    works: List<SavedWork>,
    permanently: Boolean = false,
    fileStore: WorkFileStore? = null,
    visibility: (SavedWork) -> LibraryPrivacyVisibility = { LibraryPrivacyVisibility.Visible }
): String {
    if (works.size == 1) {
        val work = works.first()
        return deleteConfirmationMessage(
            work = work,
            permanently = permanently,
            fileStore = fileStore,
            visibility = visibility(work)
        )
    }
    val irreplaceable = works.count { !WorkRedownloadability.of(it, fileStore).canRedownload }
    return deleteConfirmationMessage(
        itemCount = works.size,
        irreplaceableCount = irreplaceable,
        permanently = permanently
    )
}

fun deleteConfirmationMessage(
    itemCount: Int,
    irreplaceableCount: Int,
    permanently: Boolean = false
): String {
    if (itemCount == 1 && irreplaceableCount == 0) {
        return if (permanently) {
            "Kudos will permanently remove this item and any download, progress, or notes stored with it. " +
                "The work stays on AO3. You can't undo this."
        } else {
            "Kudos will move this work to Recently Deleted. You can restore it for the next 90 days."
        }
    }
    val base = if (permanently) {
        val ao3Clause = if (irreplaceableCount == 0) " The works stay on AO3." else ""
        "Kudos will permanently remove each item and any download, progress, or notes stored with it." +
            ao3Clause +
            " You can't undo this."
    } else {
        "Kudos will move the selected works to Recently Deleted. " +
            "You can restore them for the next 90 days."
    }
    if (irreplaceableCount <= 0 || itemCount <= 0) return base
    return "$base $irreplaceableCount of these $itemCount can't be downloaded again."
}

fun deleteConfirmationMessage(
    title: String,
    reason: WorkRedownloadability,
    permanently: Boolean = false,
    concealed: Boolean = false
): String {
    val trimmed = title.trim()
    val named = if (concealed || trimmed.isEmpty() || trimmed == LibraryPrivacy.HIDDEN_WORK_TITLE) {
        "this work"
    } else {
        "“$trimmed”"
    }
    return when (reason) {
        WorkRedownloadability.CanRedownload -> {
            if (permanently) {
                "Kudos will permanently remove $named and any download, progress, or notes " +
                    "stored with it. The work stays on AO3. You can't undo this."
            } else {
                "Kudos will move $named to Recently Deleted. You can restore it for the next 90 days."
            }
        }
        WorkRedownloadability.NoLongerOnAO3 -> {
            if (permanently) {
                "$named is no longer on AO3, so Kudos can't download it again. You can't undo this."
            } else {
                "$named is no longer on AO3, so Kudos can't download it again. It stays in Recently " +
                    "Deleted for 90 days, then it's gone for good."
            }
        }
        is WorkRedownloadability.Imported -> {
            val source = reason.importSourcePhrase ?: "a file"
            if (permanently) {
                "$named was imported from $source. Kudos only downloads from AO3, so this " +
                    "is the only copy."
            } else {
                "$named was imported from $source. Kudos only downloads from AO3, so this is " +
                    "the only copy. It stays in Recently Deleted for 90 days, then it's gone for good."
            }
        }
    }
}

/** PreservedWorkService.deleteConfirmationMessage, including a batch's last AO3 or imported copy. */
fun workDeletionMessage(
    works: List<SavedWork>,
    permanently: Boolean = false,
    fileStore: WorkFileStore? = null,
    visibility: (SavedWork) -> LibraryPrivacyVisibility = { LibraryPrivacyVisibility.Visible }
): String = deleteConfirmationMessage(
    works = works,
    permanently = permanently,
    fileStore = fileStore,
    visibility = visibility
)

@Composable
fun DestructiveConfirmation(
    show: Boolean,
    title: String,
    text: String,
    confirmText: String = "Delete",
    dismissText: String = "Cancel",
    confirmBeforeDelete: Boolean,
    onConfirm: () -> Unit,
    onDismissRequest: () -> Unit,
    palette: SubjectPalette? = null,
    secondaryActionText: String? = null,
    onSecondaryAction: (() -> Unit)? = null
) {
    val tokens = LocalKudosTokens.current
    if (show) {
        if (!confirmBeforeDelete) {
            LaunchedEffect(Unit) {
                onConfirm()
            }
        } else {
            val actionInk = palette?.controlInk ?: MaterialTheme.colorScheme.primary
            AlertDialog(
                containerColor = if (palette != null) tokens.theme.cardSurface else AlertDialogDefaults.containerColor,
                titleContentColor = if (palette != null) tokens.primaryInk else AlertDialogDefaults.titleContentColor,
                textContentColor = if (palette != null) tokens.secondaryInk else AlertDialogDefaults.textContentColor,
                onDismissRequest = onDismissRequest,
                title = { Text(title) },
                text = { Text(text) },
                confirmButton = {
                    TextButton(onClick = onConfirm) {
                        Text(
                            text = confirmText,
                            color = tokens.destructive
                        )
                    }
                },
                dismissButton = {
                    if (secondaryActionText != null && onSecondaryAction != null) {
                        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            TextButton(onClick = onSecondaryAction) {
                                Text(secondaryActionText, color = actionInk)
                            }
                            TextButton(onClick = onDismissRequest) {
                                Text(dismissText, color = actionInk)
                            }
                        }
                    } else {
                        TextButton(onClick = onDismissRequest) {
                            Text(dismissText, color = actionInk)
                        }
                    }
                }
            )
        }
    }
}

/** iOS `logOutConfirmation`: Log Out asks first, the same way everywhere it is offered. */
@Composable
fun LogOutConfirmation(show: Boolean, onConfirm: () -> Unit, onDismissRequest: () -> Unit) {
    DestructiveConfirmation(
        show = show,
        title = "Log out of AO3?",
        text = "You will be signed out of AO3 on this device. Your Library, downloads, and queues stay.",
        confirmText = "Log Out",
        confirmBeforeDelete = true,
        onConfirm = onConfirm,
        onDismissRequest = onDismissRequest
    )
}
