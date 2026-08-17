package io.github.cidy02.kudos.backup

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PairingKeyCodecTest {
    private val hex = "ab".repeat(32)

    @Test
    fun encodeAddsTheKudosPubV1Prefix() {
        assertEquals("kudos-pub-v1:$hex", PairingKeyCodec.encode(hex))
    }

    @Test
    fun decodeRoundTripsThePrefixedForm() {
        assertEquals(hex, PairingKeyCodec.decode(PairingKeyCodec.encode(hex)))
    }

    @Test
    fun decodeAcceptsBareHexAsATypedFingerprintFallback() {
        assertEquals(hex, PairingKeyCodec.decode(hex))
    }

    @Test
    fun decodeIsCaseInsensitiveOnPrefixAndHex() {
        assertEquals(hex, PairingKeyCodec.decode("KUDOS-PUB-V1:" + hex.uppercase()))
    }

    @Test
    fun decodeTrimsWhitespace() {
        assertEquals(hex, PairingKeyCodec.decode("  ${PairingKeyCodec.encode(hex)}  "))
    }

    @Test
    fun decodeRejectsGarbage() {
        assertNull(PairingKeyCodec.decode("not a key"))
        assertNull(PairingKeyCodec.decode(""))
        assertNull(PairingKeyCodec.decode("kudos-pub-v1:tooshort"))
        // Right length, non-hex characters.
        assertNull(PairingKeyCodec.decode("kudos-pub-v1:" + "zz".repeat(32)))
    }

    @Test
    fun decodeRejectsAWireSuppliedNameRidingAlongInTheSameField() {
        // A hostile paste can't smuggle extra trusted data past the codec —
        // anything beyond a bare 64-hex key (prefixed or not) is rejected,
        // not silently truncated into a valid key.
        assertNull(PairingKeyCodec.decode("kudos-pub-v1:$hex;name=Attacker"))
    }

    // --- PairingTrustGate: the checkbox-gates-trust guard ---
    // This is the mutation-test target documented in FIXES-CLAUDE-D9B-KEYSYNC-ANDROID.md.

    @Test
    fun canTrustRequiresBothAValidKeyAndTheOwnDeviceCheckbox() {
        val validPasted = PairingKeyCodec.encode(hex)
        assertTrue(PairingTrustGate.canTrust(validPasted, confirmedFromOwnDevice = true))
    }

    @Test
    fun canTrustIsFalseWhenCheckboxIsUncheckedEvenWithAValidKey() {
        val validPasted = PairingKeyCodec.encode(hex)
        assertFalse(PairingTrustGate.canTrust(validPasted, confirmedFromOwnDevice = false))
    }

    @Test
    fun canTrustIsFalseWhenTheKeyIsInvalidEvenWithTheCheckboxChecked() {
        assertFalse(PairingTrustGate.canTrust("garbage", confirmedFromOwnDevice = true))
    }

    @Test
    fun canTrustIsFalseWithNeitherAValidKeyNorTheCheckbox() {
        assertFalse(PairingTrustGate.canTrust("garbage", confirmedFromOwnDevice = false))
    }
}
