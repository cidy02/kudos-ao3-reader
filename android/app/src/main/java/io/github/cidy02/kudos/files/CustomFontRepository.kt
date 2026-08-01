package io.github.cidy02.kudos.files

import io.github.cidy02.kudos.backup.BackupPaths
import io.github.cidy02.kudos.core.model.CustomFont
import io.github.cidy02.kudos.data.local.dao.CustomFontDao
import io.github.cidy02.kudos.data.local.entity.toDomain
import io.github.cidy02.kudos.data.local.entity.toEntity
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

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
        if (bytes.isEmpty()) {
            return Result.failure(IllegalArgumentException("Font file was empty."))
        }

        val extension = resolveExtension(originalFileName)
            ?: return Result.failure(
                IllegalArgumentException("Only .ttf and .otf font files are supported.")
            )

        val fileName = "${UUID.randomUUID()}.$extension"
        BackupPaths.requireSafeFontFileName(fileName)

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
