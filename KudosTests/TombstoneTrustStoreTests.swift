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
        TombstoneTrustStore.iCloudStore = nil
        UserDefaults.standard.removeObject(forKey: TombstoneTrustStore.localKeysKey)
        UserDefaults.standard.removeObject(forKey: "tombstoneRevokedPublicKeysDenylist")
        UserDefaults.standard.removeObject(forKey: "persistenceSyncDeviceID")
        UserDefaults.standard.removeObject(forKey: "trustedTombstoneDeviceMetadata")
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

    // MARK: - D9(b) KVS activation

    /// `add` publishes only this device's own pub, under its own key — never
    /// the whole local trusted set as one blob. Two devices adding different
    /// peers at "the same time" (simulated: both writes land before either
    /// reads) must not stomp each other, because each writes a different key.
    @Test func testAddPublishesOnlyOwnPubUnderItsOwnKey() {
        let store = InMemoryKeyValueStore()
        TombstoneTrustStore.iCloudStore = store
        let ownPub = TombstoneSigning.publicKeyHex()
        let peerPub = String(repeating: "2", count: 64)

        #expect(TombstoneTrustStore.add(peerPub))

        let published = store.dictionaryRepresentation.filter { $0.key.hasPrefix("pub.") }
        #expect(published.count == 1)
        #expect(published.values.first as? String == ownPub)
        // The peer's own pub is never published by THIS device — publishing is
        // always self-attributed, never "publish whatever I now trust".
        #expect(!published.values.contains { ($0 as? String) == peerPub })
    }

    /// The remote trusted set is the union of every "pub.*" entry — a second
    /// device's own publish (simulated directly in the fake store, standing
    /// in for what a real peer device would have written) must be adopted on
    /// merge without this device ever calling `add` for it.
    @Test func testMergeAdoptsUnionOfAllPublishedDevicePubs() {
        let store = InMemoryKeyValueStore()
        let peerPub = String(repeating: "3", count: 64)
        store.set(peerPub, forKey: "pub.peer-device-1")
        TombstoneTrustStore.iCloudStore = store

        TombstoneTrustStore.mergeFromiCloud()

        #expect(TombstoneTrustStore.isTrusted(peerPub))
    }

    /// A peer's "pub.*" entry disappearing (device stopped publishing, KVS
    /// hiccup, first sync before it's propagated) must NEVER untrust a key
    /// this device already trusts. Only an explicit revoked-record entry may
    /// remove trust via KVS.
    @Test func testDisappearingPublishedPubDoesNotUntrust() {
        let store = InMemoryKeyValueStore()
        let peerPub = String(repeating: "4", count: 64)
        store.set(peerPub, forKey: "pub.peer-device-2")
        TombstoneTrustStore.iCloudStore = store
        TombstoneTrustStore.mergeFromiCloud()
        #expect(TombstoneTrustStore.isTrusted(peerPub))

        store.removeObject(forKey: "pub.peer-device-2")
        TombstoneTrustStore.mergeFromiCloud()

        #expect(TombstoneTrustStore.isTrusted(peerPub))
    }

    /// `.stolenOrCompromised` publishes a revocation record. A DIFFERENT
    /// device that already trusted the key, merging fresh, must drop it AND
    /// denylist it locally — not just fail to add it in the future.
    @Test func testStolenRevokePropagatesAndUntrustsOnOtherDevices() {
        let publisherStore = InMemoryKeyValueStore()
        TombstoneTrustStore.iCloudStore = publisherStore
        let stolenPub = String(repeating: "5", count: 64)
        publisherStore.set(stolenPub, forKey: "pub.peer-device-3")
        TombstoneTrustStore.mergeFromiCloud()
        #expect(TombstoneTrustStore.isTrusted(stolenPub))

        #expect(TombstoneTrustStore.remove(stolenPub, reason: .stolenOrCompromised))
        #expect(!TombstoneTrustStore.isTrusted(stolenPub))
        #expect(TombstoneTrustStore.isDenylisted(stolenPub))

        let revoked = publisherStore.array(forKey: "tombstoneRevokedPublicKeys") as? [String] ?? []
        #expect(revoked.contains(stolenPub))
        // Belt-and-suspenders cleanup: the stale "pub.*" entry is cleared too.
        #expect(!publisherStore.dictionaryRepresentation.keys.contains("pub.peer-device-3"))
    }

    /// The other half of the propagation: a device that never called `remove`
    /// itself, but merges a revoked record another device published, must
    /// drop the key and denylist it — this is what makes revoke reach every
    /// device on the Apple ID, not just the one that clicked Revoke.
    @Test func testMergingARemoteRevocationUntrustsAndDenylistsLocally() {
        let store = InMemoryKeyValueStore()
        let peerPub = String(repeating: "6", count: 64)
        TombstoneTrustStore.iCloudStore = store
        store.set(peerPub, forKey: "pub.peer-device-4")
        TombstoneTrustStore.mergeFromiCloud()
        #expect(TombstoneTrustStore.isTrusted(peerPub))

        store.set([peerPub], forKey: "tombstoneRevokedPublicKeys")
        TombstoneTrustStore.mergeFromiCloud()

        #expect(!TombstoneTrustStore.isTrusted(peerPub))
        #expect(TombstoneTrustStore.isDenylisted(peerPub))
    }

    /// A denylisted key must never be re-trusted, however it arrives — not by
    /// a local `add` (QR/paste of a key someone already marked stolen), and
    /// not by a later `mergeFromiCloud` that still sees a stale "pub.*" entry
    /// for it (e.g. a compromised device still running and republishing).
    @Test func testDenylistedKeyCannotBeReimportedByAddOrMerge() {
        let store = InMemoryKeyValueStore()
        TombstoneTrustStore.iCloudStore = store
        let stolenPub = String(repeating: "7", count: 64)
        #expect(TombstoneTrustStore.add(stolenPub))
        #expect(TombstoneTrustStore.remove(stolenPub, reason: .stolenOrCompromised))

        #expect(!TombstoneTrustStore.add(stolenPub))
        #expect(!TombstoneTrustStore.isTrusted(stolenPub))

        // A hostile republish after the revoke record already exists.
        store.set(stolenPub, forKey: "pub.attacker-republish")
        TombstoneTrustStore.mergeFromiCloud()
        #expect(!TombstoneTrustStore.isTrusted(stolenPub))
    }

    /// `.retiredOrSold` untrusts and still tells other devices (publishes the
    /// revocation), but does not denylist — a retired device republishing
    /// later (resold, factory reset undone) is not the threat this defends.
    @Test func testRetiredRevokeUntrustsAndPropagatesButDoesNotDenylist() {
        let store = InMemoryKeyValueStore()
        TombstoneTrustStore.iCloudStore = store
        let retiredPub = String(repeating: "8", count: 64)
        #expect(TombstoneTrustStore.add(retiredPub))

        #expect(TombstoneTrustStore.remove(retiredPub, reason: .retiredOrSold))

        #expect(!TombstoneTrustStore.isTrusted(retiredPub))
        #expect(!TombstoneTrustStore.isDenylisted(retiredPub))
        // Retired publishes to the separate "untrusted" record, not the
        // stolen/denylisting "revoked" one — that distinction is the whole
        // point (a merging device must be able to tell them apart).
        let stolenRecord = store.array(forKey: "tombstoneRevokedPublicKeys") as? [String] ?? []
        #expect(!stolenRecord.contains(retiredPub))
        let untrustedRecord = store.array(forKey: "tombstoneUntrustedPublicKeys") as? [String] ?? []
        #expect(untrustedRecord.contains(retiredPub))

        // Not denylisted, so a later legitimate re-add (new owner is a friend
        // who re-pairs, or the original owner un-retires it) works — and
        // clears the stale "untrusted" entry, or the very next merge would
        // immediately re-drop the key this add just restored.
        #expect(TombstoneTrustStore.add(retiredPub))
        #expect(TombstoneTrustStore.isTrusted(retiredPub))
        let untrustedAfterReadd = store.array(forKey: "tombstoneUntrustedPublicKeys") as? [String] ?? []
        #expect(!untrustedAfterReadd.contains(retiredPub))
    }

    /// Own device's pub is always trusted regardless of KVS state — first
    /// sync / no entitlement / empty remote must never gate this.
    @Test func testEmptyRemoteIsANoOpAndOwnKeyStaysTrusted() {
        let store = InMemoryKeyValueStore()
        TombstoneTrustStore.iCloudStore = store

        TombstoneTrustStore.mergeFromiCloud()

        #expect(TombstoneTrustStore.isTrusted(TombstoneSigning.publicKeyHex()))
        #expect(TombstoneTrustStore.trustedPublicKeys().isEmpty)
    }

    /// Garbage in a "pub.*" value or in the revoked array must not crash and
    /// must not be trusted — every KVS read goes through the same
    /// `normalizedPublicKey` validation as every other input path.
    @Test func testMalformedRemoteValuesAreRejectedNotCrashed() {
        let store = InMemoryKeyValueStore()
        store.set("not-hex-at-all", forKey: "pub.garbage-device")
        store.set(42, forKey: "pub.wrong-type-device")
        store.set(["also", "not", "a", "string"], forKey: "tombstoneRevokedPublicKeys")
        TombstoneTrustStore.iCloudStore = store

        TombstoneTrustStore.mergeFromiCloud()

        #expect(TombstoneTrustStore.trustedPublicKeys().isEmpty)
    }

    // MARK: - Per-device metadata

    /// A newly-added peer shows up in the Trusted Devices list with the
    /// label passed to `add`, but the own device never appears there — it's
    /// implicitly trusted, not something the user "paired."
    @Test func testTrustedDevicesListsOnlyPeersWithLabel() {
        let peerPub = String(repeating: "9", count: 64)
        #expect(TombstoneTrustStore.add(peerPub, label: "Sam's iPad"))

        let devices = TombstoneTrustStore.trustedDevices()
        #expect(devices.count == 1)
        #expect(devices.first?.publicKeyHex == peerPub)
        #expect(devices.first?.label == "Sam's iPad")
        #expect(!devices.contains { $0.publicKeyHex == TombstoneSigning.publicKeyHex() })
    }

    /// `rename` updates the label without touching trust or `trustedAt`, and
    /// fails for a key that was never trusted (nothing to rename).
    @Test func testRenameUpdatesLabelOnly() {
        let peerPub = String(repeating: "a1", count: 32)
        TombstoneTrustStore.add(peerPub)
        let before = TombstoneTrustStore.trustedDevices().first { $0.publicKeyHex == peerPub }

        #expect(TombstoneTrustStore.rename(peerPub, label: "New name"))
        let after = TombstoneTrustStore.trustedDevices().first { $0.publicKeyHex == peerPub }
        #expect(after?.label == "New name")
        #expect(after?.trustedAt == before?.trustedAt)

        #expect(!TombstoneTrustStore.rename(String(repeating: "b2", count: 32), label: "Ghost"))
    }

    /// Revoking a key removes its metadata too, so it drops out of the
    /// Trusted Devices list, not just the raw trusted-keys set.
    @Test func testRemoveClearsMetadata() {
        let peerPub = String(repeating: "c3", count: 32)
        TombstoneTrustStore.add(peerPub, label: "Old phone")
        #expect(TombstoneTrustStore.trustedDevices().count == 1)

        TombstoneTrustStore.remove(peerPub, reason: .retiredOrSold)
        #expect(TombstoneTrustStore.trustedDevices().isEmpty)
    }

    /// Undo Trust reverts a just-trusted key within the window, without
    /// denylisting it (same key can be re-trusted afterward) — and refuses
    /// once the window has passed.
    @Test func testUndoTrustRevertsWithinWindowButNotAfter() {
        let peerPub = String(repeating: "d4", count: 32)
        var now = Date(timeIntervalSince1970: 1_000_000)
        TombstoneSigning.now = { now }
        defer { TombstoneSigning.now = Date.init }

        TombstoneTrustStore.add(peerPub)
        #expect(TombstoneTrustStore.isTrusted(peerPub))

        now = now.addingTimeInterval(25 * 60 * 60)
        #expect(!TombstoneTrustStore.undoTrust(peerPub))
        #expect(TombstoneTrustStore.isTrusted(peerPub))

        now = now.addingTimeInterval(-24 * 60 * 60)
        #expect(TombstoneTrustStore.undoTrust(peerPub))
        #expect(!TombstoneTrustStore.isTrusted(peerPub))
        #expect(!TombstoneTrustStore.isDenylisted(peerPub))

        // Undo is not "stolen" — the key can be trusted again afterward.
        #expect(TombstoneTrustStore.add(peerPub))
    }

    /// A peer merged straight from KVS (same Apple ID, this device never
    /// called `add`) still gets a metadata record so it's visible in the
    /// Trusted Devices list, not trusted-but-invisible.
    @Test func testMergedPeerGetsMetadataToo() {
        let store = InMemoryKeyValueStore()
        let peerPub = String(repeating: "e5", count: 32)
        store.set(peerPub, forKey: "pub.peer-device-5")
        TombstoneTrustStore.iCloudStore = store

        TombstoneTrustStore.mergeFromiCloud()

        let devices = TombstoneTrustStore.trustedDevices()
        #expect(devices.contains { $0.publicKeyHex == peerPub })
    }

    /// A remote revocation merged from another device must also drop the
    /// peer out of THIS device's Trusted Devices list, not just its
    /// trusted-keys set.
    @Test func testRemoteRevocationClearsMetadataOnMerge() {
        let store = InMemoryKeyValueStore()
        let peerPub = String(repeating: "f6", count: 32)
        store.set(peerPub, forKey: "pub.peer-device-6")
        TombstoneTrustStore.iCloudStore = store
        TombstoneTrustStore.mergeFromiCloud()
        #expect(TombstoneTrustStore.trustedDevices().contains { $0.publicKeyHex == peerPub })

        store.set([peerPub], forKey: "tombstoneRevokedPublicKeys")
        TombstoneTrustStore.mergeFromiCloud()

        #expect(!TombstoneTrustStore.trustedDevices().contains { $0.publicKeyHex == peerPub })
    }

    /// Re-merging an already-trusted "pub.*" entry must not reset
    /// `trustedAt` (would silently reopen the Undo Trust window) or clobber
    /// a label the user already set.
    @Test func testReMergeDoesNotResetExistingMetadata() {
        let store = InMemoryKeyValueStore()
        let peerPub = String(repeating: "a7", count: 32)
        store.set(peerPub, forKey: "pub.peer-device-7")
        TombstoneTrustStore.iCloudStore = store
        TombstoneTrustStore.mergeFromiCloud()
        TombstoneTrustStore.rename(peerPub, label: "Renamed")
        let before = TombstoneTrustStore.trustedDevices().first { $0.publicKeyHex == peerPub }

        TombstoneTrustStore.mergeFromiCloud()

        let after = TombstoneTrustStore.trustedDevices().first { $0.publicKeyHex == peerPub }
        #expect(after?.label == "Renamed")
        #expect(after?.trustedAt == before?.trustedAt)
    }
}

private final class KeychainOverrideReset {
    deinit {
        TombstoneTrustStore.keychainOverride = nil
        UserDefaults.standard.removeObject(forKey: TombstoneTrustStore.localKeysKey)
        UserDefaults.standard.removeObject(forKey: "trustedTombstoneDeviceMetadata")
    }
}
