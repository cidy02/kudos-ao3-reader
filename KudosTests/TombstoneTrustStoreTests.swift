import Foundation
import Testing
@testable import Kudos

/// Uses `TombstoneTrustStore.keychainOverride`, not the real device Keychain:
/// unsigned test builds (`CODE_SIGNING_ALLOWED=NO`) get `errSecMissingEntitlement`
/// (-34018) from `SecItemAdd`/`SecItemCopyMatching` for this app's keychain-access
/// group — confirmed by instrumenting the actual OSStatus, not assumed. The rest of
/// this test target avoids the real Keychain the same way `TombstoneSigning` tests
/// avoid it via `keyOverride`.
@Suite(.serialized)
struct TombstoneTrustStoreTests {

    init() {
        TombstoneTrustStore.keychainOverride = []
        UserDefaults.standard.removeObject(forKey: TombstoneTrustStore.localKeysKey)
    }

    @Test func testRoundTripAddRemove() {
        let testPub = String(repeating: "1", count: 64)

        #expect(!TombstoneTrustStore.isTrusted(testPub))

        #expect(TombstoneTrustStore.add(testPub))
        #expect(TombstoneTrustStore.isTrusted(testPub))
        #expect(TombstoneTrustStore.trustedPublicKeys().contains(testPub))

        #expect(TombstoneTrustStore.remove(testPub))
        #expect(!TombstoneTrustStore.isTrusted(testPub))
        #expect(!TombstoneTrustStore.trustedPublicKeys().contains(testPub))

        #expect(!TombstoneTrustStore.remove(testPub))
    }

    @Test func testOwnDeviceAlwaysTrusted() {
        let ownDevicePub = TombstoneSigning.publicKeyHex()
        #expect(TombstoneTrustStore.isTrusted(ownDevicePub))
    }

    @Test func testMigrationFromUserDefaults() {
        let legacyPub1 = String(repeating: "a", count: 64)
        let legacyPub2 = String(repeating: "b", count: 64)

        UserDefaults.standard.set([legacyPub1, legacyPub2], forKey: TombstoneTrustStore.localKeysKey)

        let trusted = TombstoneTrustStore.trustedPublicKeys()
        #expect(trusted.contains(legacyPub1))
        #expect(trusted.contains(legacyPub2))

        #expect(UserDefaults.standard.array(forKey: TombstoneTrustStore.localKeysKey) == nil)

        let newPub = String(repeating: "c", count: 64)
        TombstoneTrustStore.add(newPub)
        let trustedAfter = TombstoneTrustStore.trustedPublicKeys()
        #expect(trustedAfter.contains(legacyPub1))
        #expect(trustedAfter.contains(legacyPub2))
        #expect(trustedAfter.contains(newPub))
    }

    /// A write that did not go through `add` — the override standing in for "another
    /// process wrote the Keychain item directly" — must still be visible to a read.
    @Test func testOutOfBandWriteIsReflected() {
        let injectedPub = String(repeating: "e", count: 64)
        TombstoneTrustStore.keychainOverride = [injectedPub]

        #expect(TombstoneTrustStore.isTrusted(injectedPub))
        #expect(TombstoneTrustStore.trustedPublicKeys().contains(injectedPub))
    }
}
