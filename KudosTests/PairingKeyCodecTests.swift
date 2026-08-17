import Foundation
import Testing
@testable import Kudos

@Suite
struct PairingKeyCodecTests {
    private let hex = String(repeating: "ab", count: 32)

    @Test func testEncodeAddsTheKudosPubV1Prefix() {
        #expect(PairingKeyCodec.encode(hex) == "kudos-pub-v1:\(hex)")
    }

    @Test func testDecodeRoundTripsThePrefixedForm() {
        #expect(PairingKeyCodec.decode(PairingKeyCodec.encode(hex)) == hex)
    }

    @Test func testDecodeAcceptsBareHexAsATypedFingerprintFallback() {
        #expect(PairingKeyCodec.decode(hex) == hex)
    }

    @Test func testDecodeIsCaseInsensitiveOnPrefixAndHex() {
        #expect(PairingKeyCodec.decode("KUDOS-PUB-V1:" + hex.uppercased()) == hex)
    }

    @Test func testDecodeTrimsWhitespace() {
        #expect(PairingKeyCodec.decode("  \(PairingKeyCodec.encode(hex))  ") == hex)
    }

    @Test func testDecodeRejectsGarbage() {
        #expect(PairingKeyCodec.decode("not a key") == nil)
        #expect(PairingKeyCodec.decode("") == nil)
        #expect(PairingKeyCodec.decode("kudos-pub-v1:tooshort") == nil)
        // Right length, non-hex characters.
        #expect(PairingKeyCodec.decode("kudos-pub-v1:" + String(repeating: "zz", count: 32)) == nil)
    }

    /// A hostile paste can't smuggle extra trusted data past the codec —
    /// anything beyond a bare 64-hex key (prefixed or not) is rejected, not
    /// silently truncated into a valid key.
    @Test func testDecodeRejectsAWireSuppliedNameRidingAlongInTheSameField() {
        #expect(PairingKeyCodec.decode("kudos-pub-v1:\(hex);name=Attacker") == nil)
    }

    // MARK: - PairingTrustGate: the checkbox-gates-trust guard

    @Test func testCanTrustRequiresBothAValidKeyAndTheOwnDeviceCheckbox() {
        let validPasted = PairingKeyCodec.encode(hex)
        #expect(PairingTrustGate.canTrust(pastedText: validPasted, confirmedFromOwnDevice: true))
    }

    @Test func testCanTrustIsFalseWhenCheckboxIsUncheckedEvenWithAValidKey() {
        let validPasted = PairingKeyCodec.encode(hex)
        #expect(!PairingTrustGate.canTrust(pastedText: validPasted, confirmedFromOwnDevice: false))
    }

    @Test func testCanTrustIsFalseWhenTheKeyIsInvalidEvenWithTheCheckboxChecked() {
        #expect(!PairingTrustGate.canTrust(pastedText: "garbage", confirmedFromOwnDevice: true))
    }

    @Test func testCanTrustIsFalseWithNeitherAValidKeyNorTheCheckbox() {
        #expect(!PairingTrustGate.canTrust(pastedText: "garbage", confirmedFromOwnDevice: false))
    }
}
