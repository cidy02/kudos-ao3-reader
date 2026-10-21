package io.github.cidy02.kudos.backup

/**
 * The pairing screen's Revoke step. iOS `RevokeDeviceSheet` only removes the
 * key. It does not put works that key deleted back into the library.
 */
class KeyRevocationService(
    private val trustStore: TombstoneTrustStore
) {
    suspend fun revoke(publicKeyHex: String, reason: KeyRevocationReason): Boolean {
        return trustStore.revoke(publicKeyHex, reason)
    }
}
