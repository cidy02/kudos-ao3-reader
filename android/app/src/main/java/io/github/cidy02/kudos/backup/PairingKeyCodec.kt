package io.github.cidy02.kudos.backup

/**
 * Wire format for the QR / Copy Key / manual-paste pairing text: this
 * device's full 64-hex Ed25519 public key, prefixed so iOS's QR scanner (a
 * sibling unit) can recognize a Kudos pairing code among other QR content.
 */
object PairingKeyCodec {
    private const val PREFIX = "kudos-pub-v1:"

    fun encode(publicKeyHex: String): String = PREFIX + publicKeyHex

    /**
     * Accepts the prefixed form (QR / Copy Key output) or bare 64-hex (a
     * typed-fingerprint fallback). Returns null for anything that doesn't
     * normalize to a valid key — callers must not trust a partial match.
     */
    fun decode(text: String): String? {
        val trimmed = text.trim()
        val hex = if (trimmed.startsWith(PREFIX, ignoreCase = true)) {
            trimmed.substring(PREFIX.length)
        } else {
            trimmed
        }
        return TombstoneSigning.normalizePublicKeyHex(hex)
    }
}

/**
 * Pure gating logic for the "Advanced" manual-paste trust flow, kept outside
 * Compose so it's unit-testable without a Compose/Robolectric harness. The
 * Trust button must stay disabled until the user has both pasted a
 * recognizable key AND explicitly confirmed they got it from their other
 * device — a file/wire source must never satisfy this on its own.
 */
object PairingTrustGate {
    fun canTrust(pastedText: String, confirmedFromOwnDevice: Boolean): Boolean {
        return confirmedFromOwnDevice && PairingKeyCodec.decode(pastedText) != null
    }
}
