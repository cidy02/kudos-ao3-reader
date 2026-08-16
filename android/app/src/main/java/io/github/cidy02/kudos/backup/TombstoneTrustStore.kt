package io.github.cidy02.kudos.backup

import io.github.cidy02.kudos.data.preferences.SettingsRepository

/**
 * Device-local set of trusted Ed25519 public keys (64-char lowercase hex).
 *
 * Own device pub is always trusted. A `.kudosbackup` / ZIP / sync folder must
 * never write this store.
 */
class TombstoneTrustStore(
    private val settingsRepository: SettingsRepository
) {
    suspend fun trust(hex: String): Boolean {
        val normalized = TombstoneSigning.normalizePublicKeyHex(hex) ?: return false
        settingsRepository.trustTombstonePublicKey(normalized)
        return true
    }

    suspend fun isTrusted(hex: String): Boolean {
        val normalized = TombstoneSigning.normalizePublicKeyHex(hex) ?: return false
        if (TombstoneSigning.isOwnPublicKey(normalized)) return true
        return normalized in settingsRepository.trustedTombstonePublicKeysSnapshot()
    }

    suspend fun trustedPublicKeys(): Set<String> {
        return settingsRepository.trustedTombstonePublicKeysSnapshot()
    }
}
