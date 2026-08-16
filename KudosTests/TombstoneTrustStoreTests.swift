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
    /// Clears the process-wide override after each test so later suites that
    /// touch `UserDefaults.standard` cannot inherit a leftover in-memory store.
    private let reset = KeychainOverrideReset()

    init() {
        TombstoneTrustStore.keychainOverride = .stored([])
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
        TombstoneTrustStore.keychainOverride = .absent
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
        TombstoneTrustStore.keychainOverride = .stored([injectedPub])

        #expect(TombstoneTrustStore.isTrusted(injectedPub))
        #expect(TombstoneTrustStore.trustedPublicKeys().contains(injectedPub))
    }

    /// After the Keychain item exists, a later write to the UserDefaults plist
    /// must not be imported. That was the original same-user write-vector;
    /// union-on-every-launch "migration" would reopen it.
    @Test func testUserDefaultsWriteAfterKeychainItemExistsIsIgnored() {
        let attacker = String(repeating: "d", count: 64)
        UserDefaults.standard.set([attacker], forKey: TombstoneTrustStore.localKeysKey)

        #expect(!TombstoneTrustStore.isTrusted(attacker))
        #expect(!TombstoneTrustStore.trustedPublicKeys().contains(attacker))
        #expect(UserDefaults.standard.array(forKey: TombstoneTrustStore.localKeysKey) == nil)
    }

    /// First launch with no Keychain item and no UserDefaults must plant an
    /// empty item so a subsequent plist write cannot be imported as a migration.
    @Test func testEmptyFirstLaunchPlantsSentinelAndIgnoresLaterUserDefaults() {
        TombstoneTrustStore.keychainOverride = .absent
        #expect(TombstoneTrustStore.trustedPublicKeys().isEmpty)

        let attacker = String(repeating: "d", count: 64)
        UserDefaults.standard.set([attacker], forKey: TombstoneTrustStore.localKeysKey)
        #expect(!TombstoneTrustStore.isTrusted(attacker))
        #expect(UserDefaults.standard.array(forKey: TombstoneTrustStore.localKeysKey) == nil)
    }

    /// Keychain unavailable must fail closed and must not wipe the legacy
    /// UserDefaults value — a later launch can still do the real one-time
    /// migration once Keychain works.
    @Test func testUnavailableKeychainDoesNotWipeUserDefaults() {
        TombstoneTrustStore.keychainOverride = .unavailable
        let legacy = String(repeating: "f", count: 64)
        UserDefaults.standard.set([legacy], forKey: TombstoneTrustStore.localKeysKey)

        #expect(!TombstoneTrustStore.isTrusted(legacy))
        #expect(
            UserDefaults.standard.stringArray(forKey: TombstoneTrustStore.localKeysKey) == [legacy]
        )
    }

    @Test func testNormalizedPublicKeyAppliedOnEveryPath() {
        #expect(!TombstoneTrustStore.add("not-a-key"))
        #expect(!TombstoneTrustStore.remove("gg"))

        let upper = String(repeating: "A", count: 64)
        let lower = String(repeating: "a", count: 64)
        TombstoneTrustStore.keychainOverride = .stored(["NOT-HEX", upper])

        let keys = TombstoneTrustStore.trustedPublicKeys()
        #expect(!keys.contains("NOT-HEX"))
        #expect(keys.contains(lower))
        #expect(TombstoneTrustStore.isTrusted(upper))
    }
}

private final class KeychainOverrideReset {
    deinit {
        TombstoneTrustStore.keychainOverride = nil
        UserDefaults.standard.removeObject(forKey: TombstoneTrustStore.localKeysKey)
    }
}
