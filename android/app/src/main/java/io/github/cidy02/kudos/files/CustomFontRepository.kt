package io.github.cidy02.kudos.files

import io.github.cidy02.kudos.backup.BackupPaths
import io.github.cidy02.kudos.backup.BackupError
import io.github.cidy02.kudos.backup.BackupFontValidator
import io.github.cidy02.kudos.backup.BackupLimits
import io.github.cidy02.kudos.core.model.CustomFont
import io.github.cidy02.kudos.data.local.dao.CustomFontDao
import io.github.cidy02.kudos.data.local.entity.toDomain
import io.github.cidy02.kudos.data.local.entity.toEntity
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import java.nio.file.Path
import java.nio.file.Files
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Imports, lists, and deletes user fonts under [FontFileStore], with Room metadata
 * matching the backup `fonts[]` / `readerFontID = custom:<fileName>` contract.
 */
class CustomFontRepository(
    private val customFontDao: CustomFontDao,
    private val fontFileStore: FontFileStore,
    private val settingsRepository: SettingsRepository
) {
    fun observeImported(): Flow<List<CustomFont>> {
        return customFontDao.observeAll().map { rows -> rows.map { it.toDomain() } }
    }

    suspend fun listImported(): List<CustomFont> {
        return customFontDao.getAll().map { it.toDomain() }
    }

    /**
     * Copy [bytes] into app-private font storage, record metadata, and select the font.
     * File names are UUID + extension (Apple import parity / backup-safe).
     */
    suspend fun importFont(
        displayName: String,
        originalFileName: String?,
        bytes: ByteArray
    ): Result<CustomFont> {
        val extension = resolveExtension(originalFileName)
            ?: return Result.failure(
                IllegalArgumentException("Only TrueType (.ttf) and OpenType (.otf) fonts can be backed up. " +
                    "Keeping it would stop your library backup from restoring.")
            )

        val fileName = "${UUID.randomUUID()}.$extension"
        BackupPaths.requireSafeFontFileName(fileName)

        val rejection = withContext(Dispatchers.IO) {
            try {
                BackupFontValidator.validate(mapOf(fileName to bytes))
            } catch (error: BackupError) {
                val reason = when (error) {
                    is BackupError.EntryTooLarge -> "It's bigger than the " +
                        "${BackupLimits.MAX_FONT_ENTRY_BYTES / (1024 * 1024)} MB a backup can carry for one font."
                    is BackupError.FontValidationUnavailable -> "That file couldn't be read."
                    else -> "The system can't read it as a font."
                }
                return@withContext reason + " Keeping it would stop your library backup from restoring."
            }
            val installed = listImported().sumOf { font ->
                runCatching { Files.size(fontPath(font)) }.getOrDefault(0L)
            }
            if (installed + bytes.size > BackupLimits.MAX_TOTAL_FONT_BYTES) {
                "Your fonts would go over the ${BackupLimits.MAX_TOTAL_FONT_BYTES / (1024 * 1024)} MB " +
                    "a backup can carry, which would stop your library backup from restoring."
            } else null
        }
        if (rejection != null) return Result.failure(IllegalArgumentException(rejection))

        when (val write = fontFileStore.writeFont(fileName, bytes)) {
            is FileWriteResult.Failure -> {
                return Result.failure(
                    write.cause ?: IllegalStateException(write.message)
                )
            }
            is FileWriteResult.Success -> Unit
        }

        val name = displayName.trim().ifBlank {
            originalFileName
                ?.substringAfterLast('/')
                ?.substringAfterLast('\\')
                ?.substringBeforeLast('.')
                ?.trim()
                .orEmpty()
                .ifBlank { "Imported font" }
        }

        val font = CustomFont(name = name, fileName = fileName)
        customFontDao.upsert(font.toEntity())
        settingsRepository.updateReaderFontId(font.selectionId)
        return Result.success(font)
    }

    /**
     * Remove an imported font file + DB row. Built-ins are not stored and cannot
     * be deleted. If the deleted font was selected, selection falls back to `system`.
     */
    suspend fun deleteImported(font: CustomFont) {
        val selectionId = font.selectionId
        fontFileStore.deleteFont(font.fileName)
        customFontDao.deleteById(font.id)
        // Also clear any stale row keyed only by file name (defensive).
        customFontDao.deleteByFileName(font.fileName)

        val current = settingsRepository.snapshot().reader.readerFontId
        if (current == selectionId) {
            settingsRepository.updateReaderFontId("system")
        }
    }

    fun fontPath(fileName: String): Path = fontFileStore.fontPath(fileName)

    fun fontPath(font: CustomFont): Path = fontFileStore.fontPath(font.fileName)

    suspend fun fontExists(fileName: String): Boolean = fontFileStore.fontExists(fileName)

    companion object {
        private val AllowedExtensions = setOf("ttf", "otf")

        fun resolveExtension(originalFileName: String?): String? {
            if (originalFileName.isNullOrBlank()) return null
            val last = originalFileName.substringAfterLast('/').substringAfterLast('\\')
            val ext = last.substringAfterLast('.', missingDelimiterValue = "")
                .lowercase(Locale.ROOT)
            return ext.takeIf { it in AllowedExtensions }
        }

        fun isSupportedFontFileName(fileName: String?): Boolean {
            return resolveExtension(fileName) != null
        }
    }
}
