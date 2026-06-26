package io.github.cidy02.kudos.backup

import java.time.Instant
import java.time.OffsetDateTime
import java.time.format.DateTimeParseException
import kotlinx.serialization.SerializationException
import kotlinx.serialization.decodeFromString

object BackupValidator {
    private val readerModes = setOf("scroll", "paged")
    private val readerThemes = setOf("light", "sepia", "dark")
    private val appThemes = setOf("light", "sepia", "dark", "system")
    private val matureModes = setOf("obscure", "hide")
    private val builtInFontIds = setOf(
        "system",
        "nyserif",
        "georgia",
        "palatino",
        "times",
        "helvetica",
        "avenir",
        "menlo"
    )
    private val accentPattern = Regex("^#[0-9A-Fa-f]{6}$")

    fun decodeManifest(bytes: ByteArray): KudosBackupManifest {
        if (bytes.size > BackupLimits.MAX_MANIFEST_BYTES) {
            throw BackupError.EntryTooLarge(BackupPaths.MANIFEST)
        }

        val json = bytes.toString(Charsets.UTF_8)
        val manifest = try {
            BackupJson.decodeFromString<KudosBackupManifest>(json)
        } catch (error: SerializationException) {
            throw BackupError.InvalidJson(error)
        } catch (error: IllegalArgumentException) {
            throw BackupError.InvalidJson(error)
        }

        return validateManifest(manifest)
    }

    fun validateManifest(manifest: KudosBackupManifest): KudosBackupManifest {
        if (manifest.version !in BackupVersion.supported) {
            throw BackupError.UnsupportedVersion(manifest.version)
        }
        parseInstant(manifest.exportedAt, "exportedAt")

        val workIds = mutableSetOf<String>()
        val works = manifest.works.mapIndexed { index, work ->
            val id = BackupPaths.canonicalUuid(work.id, "works[$index].id")
            if (!workIds.add(id)) throw BackupError.InvalidPackage("Duplicate work id: $id")
            parseInstant(work.dateAdded, "works[$index].dateAdded")
            work.lastReadDate?.let { parseInstant(it, "works[$index].lastReadDate") }
            work.lastUpdateCheck?.let { parseInstant(it, "works[$index].lastUpdateCheck") }
            if (work.lastSpineIndex < 0) {
                throw BackupError.InvalidPackage("lastSpineIndex must be non-negative for work $id.")
            }
            if (work.lastScrollFraction !in 0.0..1.0) {
                throw BackupError.InvalidPackage("lastScrollFraction must be between 0 and 1 for work $id.")
            }
            if (work.wordCount < 0 || work.kudos < 0 || work.seriesPosition < 0) {
                throw BackupError.InvalidPackage("Work counters must be non-negative for work $id.")
            }
            if ((work.comments ?: 0) < 0 || (work.hits ?: 0) < 0 || (work.knownChapterCount ?: 0) < 0) {
                throw BackupError.InvalidPackage("v2 work counters must be non-negative for work $id.")
            }

            work.copy(
                id = id,
                collectionIDs = work.collectionIDs.mapIndexed { collectionIndex, collectionId ->
                    BackupPaths.canonicalUuid(collectionId, "works[$index].collectionIDs[$collectionIndex]")
                }
            )
        }

        val bookmarks = manifest.bookmarks.mapIndexed { index, bookmark ->
            if (bookmark.urlString.isBlank()) {
                throw BackupError.InvalidPackage("Bookmark urlString must not be blank.")
            }
            parseInstant(bookmark.dateAdded, "bookmarks[$index].dateAdded")
            bookmark
        }

        val fontNames = mutableSetOf<String>()
        val fonts = manifest.fonts.mapIndexed { index, font ->
            BackupPaths.requireSafeFontFileName(font.fileName)
            if (!fontNames.add(font.fileName)) {
                throw BackupError.InvalidPackage("Duplicate font file name: ${font.fileName}")
            }
            parseInstant(font.dateAdded, "fonts[$index].dateAdded")
            font
        }

        val collectionIds = mutableSetOf<String>()
        val collections = manifest.collections.mapIndexed { index, collection ->
            val id = BackupPaths.canonicalUuid(collection.id, "collections[$index].id")
            if (!collectionIds.add(id)) {
                throw BackupError.InvalidPackage("Duplicate collection id: $id")
            }
            parseInstant(collection.dateAdded, "collections[$index].dateAdded")
            collection.copy(
                id = id,
                workIDs = collection.workIDs.mapIndexed { workIndex, workId ->
                    BackupPaths.canonicalUuid(workId, "collections[$index].workIDs[$workIndex]")
                }
            )
        }

        val savedSearchIds = mutableSetOf<String>()
        val savedSearches = manifest.savedSearches.mapIndexed { index, savedSearch ->
            val id = BackupPaths.canonicalUuid(savedSearch.id, "savedSearches[$index].id")
            if (!savedSearchIds.add(id)) {
                throw BackupError.InvalidPackage("Duplicate saved search id: $id")
            }
            parseInstant(savedSearch.dateAdded, "savedSearches[$index].dateAdded")
            savedSearch.copy(id = id)
        }

        return manifest.copy(
            works = works,
            bookmarks = bookmarks,
            fonts = fonts,
            collections = collections,
            savedSearches = savedSearches
        )
    }

    fun parseInstant(value: String, field: String): Instant {
        return try {
            Instant.parse(value)
        } catch (_: DateTimeParseException) {
            try {
                OffsetDateTime.parse(value).toInstant()
            } catch (_: DateTimeParseException) {
                throw BackupError.InvalidDate(field, value)
            }
        }
    }

    fun parseNullableInstant(value: String?, field: String): Instant? {
        return value?.let { parseInstant(it, field) }
    }

    fun formatInstant(instant: Instant): String = instant.toString()

    fun normalizeSettings(
        settings: BackupSettingsPayload,
        availableFontFileNames: Set<String>
    ): BackupSettingsPayload {
        val defaults = BackupSettingsPayload()
        return settings.copy(
            readerFontID = normalizeReaderFontId(settings.readerFontID, availableFontFileNames),
            readerMode = settings.readerMode.takeIf { it in readerModes } ?: defaults.readerMode,
            readerFontPt = settings.readerFontPt.takeIfFiniteIn(12.0, 34.0) ?: defaults.readerFontPt,
            readerLineHeight = settings.readerLineHeight.takeIfFiniteIn(1.2, 2.4)
                ?: defaults.readerLineHeight,
            readerLetterSpacing = settings.readerLetterSpacing.takeIfFiniteIn(-0.03, 0.12)
                ?: defaults.readerLetterSpacing,
            readerWordSpacing = settings.readerWordSpacing.takeIfFiniteIn(0.0, 0.6)
                ?: defaults.readerWordSpacing,
            readerMargin = settings.readerMargin.takeIfFiniteIn(8.0, 64.0) ?: defaults.readerMargin,
            matureContentMode = settings.matureContentMode.takeIf { it in matureModes }
                ?: defaults.matureContentMode,
            appTheme = settings.appTheme.takeIf { it in appThemes } ?: defaults.appTheme,
            readerTheme = settings.readerTheme.takeIf { it in readerThemes } ?: defaults.readerTheme,
            accentColorHex = settings.accentColorHex.takeIf { accentPattern.matches(it) }
                ?: defaults.accentColorHex
        )
    }

    private fun normalizeReaderFontId(
        readerFontId: String,
        availableFontFileNames: Set<String>
    ): String {
        if (readerFontId in builtInFontIds) return readerFontId
        if (!readerFontId.startsWith("custom:")) return "system"

        val fileName = readerFontId.removePrefix("custom:")
        return if (
            BackupPaths.isSafeFontFileName(fileName) &&
            fileName in availableFontFileNames
        ) {
            readerFontId
        } else {
            "system"
        }
    }

    private fun Double.takeIfFiniteIn(start: Double, endInclusive: Double): Double? {
        return takeIf { it.isFinite() && it >= start && it <= endInclusive }
    }
}
