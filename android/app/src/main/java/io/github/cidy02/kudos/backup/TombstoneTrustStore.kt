package io.github.cidy02.kudos.backup

import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.data.preferences.TrustedDeviceRecord
import java.time.Duration
import java.time.Instant

/** Why the user is removing a trusted key — drives whether it is denylisted. */
enum class KeyRevocationReason {
    STOLEN_OR_COMPROMISED,
    RETIRED_OR_SOLD
}

/** One paired device as the UI shows it — local label, never a wire-supplied name. */
data class TrustedDevice(
    val publicKeyHex: String,
    val label: String,
    val trustedAt: Instant
)

/**
 * Device-local set of trusted Ed25519 public keys (64-char lowercase hex).
 *
 * Own device pub is always trusted. A `.kudosbackup` / ZIP / sync folder must
 * never write this store — [trust] is only ever called from the pairing UI's
 * "Trust" button (manual paste, gated by a checkbox) or QR acceptance, both
 * local user actions with a human in the loop.
 */
class TombstoneTrustStore(
    private val settingsRepository: SettingsRepository,
    private val clock: () -> Instant = { Instant.now() }
) {
    /** Default 24h window for [undoTrust]. */
    val undoWindow: Duration = Duration.ofHours(24)

    /**
     * Trusts [hex]. Fails (returns false) for an unparseable key, the device's
     * own key (already implicitly trusted), or a key on the revoked denylist
     * (a key revoked as "Stolen or compromised" can never be silently
     * re-added by re-pasting it — see [revoke]).
     */
    suspend fun trust(hex: String, label: String = ""): Boolean {
        val normalized = TombstoneSigning.normalizePublicKeyHex(hex) ?: return false
        if (TombstoneSigning.isOwnPublicKey(normalized)) return false
        if (normalized in settingsRepository.revokedTombstonePublicKeysSnapshot()) return false
        settingsRepository.trustTombstonePublicKey(normalized)
        settingsRepository.upsertTrustedTombstoneDeviceRecord(
            TrustedDeviceRecord(
                publicKeyHex = normalized,
                label = label,
                trustedAtEpochMs = clock().toEpochMilli()
            )
        )
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

    /** Paired devices for the "Trusted Devices" list, newest-trusted first. */
    suspend fun trustedDevices(): List<TrustedDevice> {
        return settingsRepository.trustedTombstoneDeviceRecordsSnapshot()
            .map {
                TrustedDevice(
                    publicKeyHex = it.publicKeyHex,
                    label = it.label,
                    trustedAt = Instant.ofEpochMilli(it.trustedAtEpochMs)
                )
            }
            .sortedByDescending { it.trustedAt }
    }

    /** User names a device locally, after trusting it. Never fed a wire-supplied name. */
    suspend fun rename(hex: String, label: String) {
        val normalized = TombstoneSigning.normalizePublicKeyHex(hex) ?: return
        settingsRepository.renameTrustedTombstoneDevice(normalized, label)
    }

    /**
     * Removes trust. [reason] STOLEN_OR_COMPROMISED also denylists the key so
     * it cannot be re-trusted later (D9(a)-equivalent revoke-denylist —
     * Android's Phase 1/2 trust store had no revoke path before this unit).
     * RETIRED_OR_SOLD removes trust without denylisting; the same key could
     * be re-paired later (e.g. the device was reset and given away).
     */
    suspend fun revoke(hex: String, reason: KeyRevocationReason): Boolean {
        val normalized = TombstoneSigning.normalizePublicKeyHex(hex) ?: return false
        if (TombstoneSigning.isOwnPublicKey(normalized)) return false
        settingsRepository.untrustTombstonePublicKey(normalized)
        settingsRepository.removeTrustedTombstoneDeviceRecord(normalized)
        if (reason == KeyRevocationReason.STOLEN_OR_COMPROMISED) {
            settingsRepository.addRevokedTombstonePublicKey(normalized)
        }
        return true
    }

    /**
     * Reverts a just-trusted key back to untrusted, only within [undoWindow]
     * of the moment it was trusted. Does not denylist — this is "I made a
     * mistake," not "this key is hostile."
     */
    suspend fun undoTrust(hex: String, now: Instant = clock(), window: Duration = undoWindow): Boolean {
        val normalized = TombstoneSigning.normalizePublicKeyHex(hex) ?: return false
        val record = settingsRepository.trustedTombstoneDeviceRecordsSnapshot()
            .firstOrNull { it.publicKeyHex == normalized } ?: return false
        val trustedAt = Instant.ofEpochMilli(record.trustedAtEpochMs)
        if (Duration.between(trustedAt, now) > window) return false
        settingsRepository.untrustTombstonePublicKey(normalized)
        settingsRepository.removeTrustedTombstoneDeviceRecord(normalized)
        return true
    }

    /** Count-only unknown-signer badge source — see [SettingsRepository.unknownSignerTombstoneIds]. */
    suspend fun unknownSignerCount(): Int {
        return settingsRepository.unknownSignerTombstoneIdsSnapshot().size
    }
}
