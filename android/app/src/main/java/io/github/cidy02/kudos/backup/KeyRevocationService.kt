package io.github.cidy02.kudos.backup

import io.github.cidy02.kudos.core.model.SyncTombstoneRecordType
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.works.WorkRepository

/**
 * Orchestrates the "Revoke" step of the pairing UI: ask why, revoke, and for
 * "Stolen or compromised" offer to restore works this key's signature
 * deleted. [SyncTombstoneEntity.signerPublicKey] is the real per-record
 * "deleted by this key" provenance field already on the row (see
 * android/app/src/main/java/io/github/cidy02/kudos/core/model/SyncModels.kt) —
 * no new storage invented here.
 */
class KeyRevocationService(
    private val trustStore: TombstoneTrustStore,
    private val database: KudosDatabase,
    private val workRepository: WorkRepository
) {
    /** Count to show in "Restore N work(s) removed by this device?" before the user commits. */
    suspend fun worksDeletedByCount(publicKeyHex: String): Int {
        val normalized = TombstoneSigning.normalizePublicKeyHex(publicKeyHex) ?: return 0
        return database.syncTombstoneDao()
            .getBySigner(normalized, SyncTombstoneRecordType.SAVED_WORK)
            .size
    }

    suspend fun revoke(publicKeyHex: String, reason: KeyRevocationReason): Boolean {
        return trustStore.revoke(publicKeyHex, reason)
    }

    /**
     * Best-effort: a row already permanently swept out of Recently Deleted
     * (past its recovery window) can't be brought back — [WorkRepository]
     * has no trace of it left to restore. Returns how many actually came back.
     */
    suspend fun restoreWorksDeletedBy(publicKeyHex: String): Int {
        val normalized = TombstoneSigning.normalizePublicKeyHex(publicKeyHex) ?: return 0
        val rows = database.syncTombstoneDao()
            .getBySigner(normalized, SyncTombstoneRecordType.SAVED_WORK)
        var restored = 0
        rows.forEach { row ->
            if (workRepository.restoreFromRecentlyDeleted(row.recordID) != null) restored++
        }
        return restored
    }
}
