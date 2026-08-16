package io.github.cidy02.kudos.backup

import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.entity.toDomain
import io.github.cidy02.kudos.data.local.entity.toEntity
import io.github.cidy02.kudos.data.preferences.SettingsRepository

/**
 * One-time re-sign of local Room tombstones that lack a Phase 2 signature.
 * Incoming unsigned tombstones still drop — this only touches rows already here.
 */
object TombstoneLocalMigration {
    suspend fun runIfNeeded(
        database: KudosDatabase,
        settingsRepository: SettingsRepository
    ) {
        if (settingsRepository.isTombstoneMigrationComplete()) return
        val dao = database.syncTombstoneDao()
        val unsigned = dao.getAll().filter { row ->
            row.signature.isBlank() || row.signerPublicKey.isBlank()
        }
        if (unsigned.isNotEmpty()) {
            dao.upsertAll(unsigned.map { TombstoneSigning.sign(it.toDomain()).toEntity() })
        }
        settingsRepository.setTombstoneMigrationComplete(true)
    }
}
