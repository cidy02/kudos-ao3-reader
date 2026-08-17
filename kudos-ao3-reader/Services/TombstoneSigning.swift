import CryptoKit
import Foundation
import Security
import SwiftData

/// Ed25519 signatures for `SyncTombstone` rows. Payload is the Phase 2 contract:
/// UTF-8 fields joined by `\n` with no trailing newline.
enum TombstoneSigning {
    static let migrationCompleteKey = "tombstoneMigrationComplete"

    /// Tests replace this to pin `createdAt` / `deletedAt`.
    static var now: () -> Date = Date.init
    /// Tests replace this to avoid the device Keychain.
    static var keyOverride: Curve25519.Signing.PrivateKey?

    private static let lock = NSLock()
    private static var cachedDeviceKey: Curve25519.Signing.PrivateKey?
    static let keychainService = (Bundle.main.bundleIdentifier ?? "Kudos") + ".tombstone-signing"
    private static let keychainAccount = "ed25519-signing-key"

    private static let deletedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter
    }()

    static func makePrivateKey() -> Curve25519.Signing.PrivateKey {
        Curve25519.Signing.PrivateKey()
    }

    static func publicKeyHex(of key: Curve25519.Signing.PrivateKey) -> String {
        hexString(key.publicKey.rawRepresentation)
    }

    static func publicKeyHex() -> String {
        publicKeyHex(of: devicePrivateKey())
    }

    static func deletedAtString(from date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return deletedAtFormatter.string(from: date)
    }

    static func payload(
        recordType: String,
        ao3WorkID: Int?,
        canonicalSourceURL: String,
        recordID: UUID,
        deletedAt: Date,
        signerPublicKey: String
    ) -> Data {
        let fields = [
            recordType,
            ao3WorkID.map(String.init) ?? "",
            canonicalSourceURL,
            recordID.uuidString.lowercased(),
            deletedAtString(from: deletedAt),
            signerPublicKey
        ]
        return Data(fields.joined(separator: "\n").utf8)
    }

    static func payload(for tombstone: SyncTombstone, signerPublicKey: String) -> Data {
        payload(
            recordType: tombstone.recordTypeRaw,
            ao3WorkID: tombstone.ao3WorkID,
            canonicalSourceURL: WorkTags.canonicalAO3WorkURL(from: tombstone.sourceURL) ?? "",
            recordID: tombstone.recordID,
            deletedAt: tombstone.createdAt,
            signerPublicKey: signerPublicKey
        )
    }

    static func payload(for archived: KudosBackupTombstone) -> Data {
        payload(
            recordType: archived.recordTypeRaw,
            ao3WorkID: archived.ao3WorkID,
            canonicalSourceURL: WorkTags.canonicalAO3WorkURL(from: archived.sourceURL) ?? "",
            recordID: archived.recordID,
            deletedAt: archived.createdAt,
            signerPublicKey: archived.signerPublicKey
        )
    }

    static func sign(
        _ tombstone: SyncTombstone,
        key: Curve25519.Signing.PrivateKey? = nil,
        defaults: UserDefaults = .standard
    ) {
        let privateKey = key ?? devicePrivateKey()
        let pub = publicKeyHex(of: privateKey)
        let body = payload(for: tombstone, signerPublicKey: pub)
        guard let signature = try? privateKey.signature(for: body) else { return }
        tombstone.signerPublicKey = pub
        tombstone.signature = hexString(signature)
        if key == nil {
            TombstoneTrustStore.add(pub, defaults: defaults)
        }
    }

    static func verify(
        payload: Data,
        publicKeyHex: String,
        signatureHex: String
    ) -> Bool {
        guard let publicKeyData = data(fromHex: publicKeyHex), publicKeyData.count == 32 else { return false }
        guard let signature = data(fromHex: signatureHex), signature.count == 64 else { return false }
        guard let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData) else {
            return false
        }
        return publicKey.isValidSignature(signature, for: payload)
    }

    static func verify(_ archived: KudosBackupTombstone) -> Bool {
        verify(
            payload: payload(for: archived),
            publicKeyHex: archived.signerPublicKey,
            signatureHex: archived.signature
        )
    }

    /// Phase 1 still drops unsigned. Phase 2 adopts only a verified signature
    /// from a key already in the local trust store. A file never adds a key.
    static func shouldAdopt(_ archived: KudosBackupTombstone, defaults: UserDefaults = .standard) -> Bool {
        guard !archived.signature.isEmpty, !archived.signerPublicKey.isEmpty else { return false }
        guard verify(archived) else { return false }
        return TombstoneTrustStore.isTrusted(archived.signerPublicKey, defaults: defaults)
    }

    static func resignLocalUnsignedIfNeeded(
        in context: ModelContext,
        defaults: UserDefaults = .standard
    ) {
        guard !defaults.bool(forKey: migrationCompleteKey) else { return }
        let tombstones = (try? context.fetch(FetchDescriptor<SyncTombstone>())) ?? []
        var changed = false
        for tombstone in tombstones where tombstone.signature.isEmpty {
            sign(tombstone, defaults: defaults)
            changed = true
        }
        if changed {
            try? context.save()
        }
        defaults.set(true, forKey: migrationCompleteKey)
    }

    static func devicePrivateKey() -> Curve25519.Signing.PrivateKey {
        lock.lock()
        defer { lock.unlock() }
        if let keyOverride { return keyOverride }
        if let cachedDeviceKey { return cachedDeviceKey }
        if let loaded = loadDeviceKey() {
            cachedDeviceKey = loaded
            return loaded
        }
        let created = Curve25519.Signing.PrivateKey()
        persistDeviceKey(created)
        cachedDeviceKey = created
        return created
    }

    private static func loadDeviceKey() -> Curve25519.Signing.PrivateKey? {
        if let data = loadKeychainData(),
           let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) {
            return key
        }
        if let data = try? Data(contentsOf: fallbackKeyURL()),
           let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) {
            return key
        }
        return nil
    }

    private static func persistDeviceKey(_ key: Curve25519.Signing.PrivateKey) {
        let data = key.rawRepresentation
        let status = saveKeychainData(data)
        if status == errSecMissingEntitlement || status == errSecNotAvailable {
            try? persistFallbackKey(data)
        }
    }

    private static func loadKeychainData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    private static func saveKeychainData(_ data: Data) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            return SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
        return status
    }

    private static func persistFallbackKey(_ data: Data) throws {
        let url = fallbackKeyURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }

    private static func fallbackKeyURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kudos", isDirectory: true)
            .appendingPathComponent("tombstone-ed25519.key")
    }

    static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func data(fromHex hex: String) -> Data? {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard cleaned.count.isMultiple(of: 2), !cleaned.isEmpty else { return nil }
        var data = Data()
        data.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }
}

/// The exact surface `TombstoneTrustStore` needs from `NSUbiquitousKeyValueStore`
/// — real key-value sync cannot be exercised in a unit test (there is no
/// signed-in-iCloud simulator), so tests substitute `InMemoryKeyValueStore`
/// against this protocol instead of the real class.
protocol KeyValueStoring: AnyObject {
    var dictionaryRepresentation: [String: Any] { get }
    func array(forKey defaultName: String) -> [Any]?
    func set(_ value: Any?, forKey defaultName: String)
    func removeObject(forKey defaultName: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: KeyValueStoring {}

#if DEBUG
/// Test-only in-memory stand-in for `NSUbiquitousKeyValueStore`. Compiled out
/// of Release, same rationale as `TombstoneTrustStore.KeychainOverride`. Does
/// not post `didChangeExternallyNotification` — nothing in this file's tests
/// depends on that notification firing, only on `mergeFromiCloud` being
/// called directly, which is how every existing call site already tests it.
final class InMemoryKeyValueStore: KeyValueStoring {
    private var storage: [String: Any] = [:]
    var dictionaryRepresentation: [String: Any] { storage }
    func array(forKey defaultName: String) -> [Any]? { storage[defaultName] as? [Any] }
    func set(_ value: Any?, forKey defaultName: String) { storage[defaultName] = value }
    func removeObject(forKey defaultName: String) { storage.removeValue(forKey: defaultName) }
    func synchronize() -> Bool { true }
}
#endif

/// Why a device's key is being revoked — the reason picks the default so the
/// lazy path is the safe one. Stolen purges the key from the trust store and
/// the KVS-published trust set, and denylists it so a stale republish from a
/// still-running attacker cannot re-import it. Retired/sold just untrusts —
/// the device isn't hostile, there is nothing to defend against re-publishing.
enum TombstoneRevokeReason {
    case stolenOrCompromised
    case retiredOrSold
}

/// Local trusted Ed25519 public keys. Own device pub is always trusted.
///
/// KVS schema (D9(b)): each device publishes ONLY its own pub, under its own
/// top-level key `"pub.<deviceID>"` — never the whole local trusted set as one
/// blob. `NSUbiquitousKeyValueStore` resolves concurrent writes to DIFFERENT
/// keys independently, so two devices publishing at once cannot race each
/// other the way a shared-array "last writer wins" scheme would (this was a
/// real defect in the pre-D9(b) `publishToiCloud`, never shipped active since
/// the entitlement stayed off). The full remote trusted set is the union of
/// every `"pub.*"` entry in `store.dictionaryRepresentation`, computed on
/// read — there is no single "the trusted array" KVS value anymore.
///
/// Revocation is a second, separate KVS record (`iCloudRevokedKey`, a
/// union-only array) so a revoke made on one device reaches every other
/// device on the same Apple ID, not just the one that clicked Revoke.
///
/// A `.kudosbackup` must never write this store — see `KudosBackup.swift`'s
/// restore/apply paths, which only ever call `isTrusted`/`shouldAdopt`.
enum TombstoneTrustStore {
    static let localKeysKey = "trustedTombstonePublicKeys"
    /// Legacy whole-set KVS key from the pre-D9(b) design. No longer written.
    /// Still read once, defensively, in case an entitlement was briefly
    /// active on some build between D9(a) and D9(b) landing — see `mergeFromiCloud`.
    static let iCloudKeysKey = "tombstoneTrustedPublicKeys"
    /// Stolen/compromised revocations — merging this denylists the key.
    private static let iCloudRevokedKey = "tombstoneRevokedPublicKeys"
    /// Retired/sold revocations — merging this untrusts the key WITHOUT
    /// denylisting it. A separate KVS record, not a shared one with a reason
    /// flag inside it, because `array(forKey:)` gives back `[Any]`/`[String]`
    /// cheaply; a reason-tagged shape would need a dictionary array and more
    /// validation surface for the same result.
    private static let iCloudUntrustedKey = "tombstoneUntrustedPublicKeys"
    private static let localRevokedKeysKey = "tombstoneRevokedPublicKeysDenylist"

    private static func iCloudPubKey(forDevice deviceID: String) -> String { "pub.\(deviceID)" }

    /// `nil` by default, not `.default`. Constructing the real store without
    /// `com.apple.developer.ubiquity-kvstore-identifier` (unsigned test builds
    /// do not have it — see `Kudos-iOS.entitlements` for the production
    /// entitlement) logs "BUG IN CLIENT OF KVS" and, in this process, makes
    /// subsequent `SecItemAdd`/`SecItemCopyMatching` fail. `KudosApplication`
    /// assigns `.default` once at launch in production; tests assign a
    /// `KeyValueStoring` fake instead.
    static var iCloudStore: (any KeyValueStoring)?

    private static let lock = NSRecursiveLock()
    private static var didRegisterObserver = false
    private static let keychainAccount = "trusted-tombstone-pubs"

    #if DEBUG
    /// Test-only Keychain stand-in. Compiled out of Release (same rationale as
    /// `Storage.fontsDirectoryOverride`): a mutable global that redirects who
    /// this device trusts must not exist in a shipping binary.
    ///
    /// Unsigned test builds (`CODE_SIGNING_ALLOWED=NO`) get
    /// `errSecMissingEntitlement` (-34018) from `SecItemAdd`/`SecItemCopyMatching`
    /// for this app's keychain-access group. A production file fallback would
    /// reopen the UserDefaults write-vector D9(a) closes, so tests use this
    /// in-memory seam instead. `nil` means use the real Keychain.
    enum KeychainOverride: Equatable {
        /// No Keychain item (`errSecItemNotFound`). The next successful save
        /// plants `.stored`.
        case absent
        /// An existing item containing these keys (empty set is still an item).
        case stored(Set<String>)
        /// Keychain calls fail. Load must not wipe UserDefaults or import it.
        case unavailable
    }

    static var keychainOverride: KeychainOverride?
    #endif

    static func isTrusted(_ publicKeyHex: String, defaults: UserDefaults = .standard) -> Bool {
        guard let normalized = normalizedPublicKey(publicKeyHex) else { return false }
        if normalized == TombstoneSigning.publicKeyHex() { return true }
        return trustedPublicKeys(defaults: defaults).contains(normalized)
    }

    static func trustedPublicKeys(defaults: UserDefaults = .standard) -> Set<String> {
        refreshFromiCloudIfNeeded(defaults: defaults)
        return loadKeys(defaults: defaults)
    }

    @discardableResult
    static func add(_ publicKeyHex: String, defaults: UserDefaults = .standard) -> Bool {
        guard let normalized = normalizedPublicKey(publicKeyHex) else { return false }
        lock.lock()
        defer { lock.unlock() }
        // A denylisted (revoked-as-stolen) key must never be re-trusted by a
        // local add — including this device's own re-publish of its trusted
        // set, and including a stale QR/paste of a key someone already
        // marked stolen on another device.
        guard !isDenylisted(normalized, defaults: defaults) else { return false }
        var keys = trustedPublicKeys(defaults: defaults)
        if keys.insert(normalized).inserted {
            saveKeys(keys, defaults: defaults)
            publishOwnPubToiCloud(defaults: defaults)
            // A prior "retired" revocation of THIS key must not keep
            // re-untrusting it on every future merge now that someone
            // legitimately re-trusted it (new owner re-pairs, or the
            // original owner un-retires it) — unlike the denylist, which is
            // intentionally permanent, this record has nothing else that
            // would ever clear it. Stolen revocations are not cleared here:
            // `isDenylisted` above already refuses the add outright for those.
            clearFromRemoteUntrusted(normalized, defaults: defaults)
        }
        return true
    }

    /// - Parameter reason: Picks the default so the lazy path is the safe
    ///   one. `.stolenOrCompromised` denylists the key (never re-importable
    ///   from KVS, even from a stale republish) and publishes the revoke so
    ///   every other device on the same Apple ID also drops it, not just this
    ///   one. `.retiredOrSold` only removes local trust — the device is not
    ///   assumed hostile, so there is nothing to defend a republish against.
    @discardableResult
    static func remove(
        _ publicKeyHex: String,
        reason: TombstoneRevokeReason = .stolenOrCompromised,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard let normalized = normalizedPublicKey(publicKeyHex) else { return false }
        lock.lock()
        defer { lock.unlock() }
        var keys = trustedPublicKeys(defaults: defaults)
        let removed = keys.remove(normalized) != nil
        if removed {
            saveKeys(keys, defaults: defaults)
        }
        switch reason {
        case .stolenOrCompromised:
            addToDenylist(normalized, defaults: defaults)
        case .retiredOrSold:
            break
        }
        // The reason must survive the round-trip through KVS, or a later
        // mergeFromiCloud reading this device's own just-published record
        // back would denylist a retired-not-stolen key: two records, not one
        // flat set, so a merging device can tell which happened.
        publishRevocationToiCloud(normalized, reason: reason, defaults: defaults)
        return removed
    }

    /// The denylist: keys revoked as stolen, which must never be re-imported
    /// from KVS or a local `add`, however they arrive. Local `UserDefaults`,
    /// not Keychain — this is a "don't re-add" marker, not the authorization
    /// list itself (that stays Keychain-protected, per D9(a)). Worst case if
    /// an unsandboxed process clears this marker is the pre-D9(b) status quo
    /// (the key could be re-imported), not a new hole.
    static func isDenylisted(_ publicKeyHex: String, defaults: UserDefaults = .standard) -> Bool {
        guard let normalized = normalizedPublicKey(publicKeyHex) else { return false }
        return denylistedKeys(defaults: defaults).contains(normalized)
    }

    private static func denylistedKeys(defaults: UserDefaults) -> Set<String> {
        Set((defaults.stringArray(forKey: localRevokedKeysKey) ?? []).compactMap(normalizedPublicKey))
    }

    private static func addToDenylist(_ normalized: String, defaults: UserDefaults) {
        var denylist = denylistedKeys(defaults: defaults)
        guard denylist.insert(normalized).inserted else { return }
        defaults.set(denylist.sorted(), forKey: localRevokedKeysKey)
    }

    private enum KeychainRead {
        case found(Set<String>)
        case notFound
        case unavailable
    }

    private static func loadKeychainKeys() -> KeychainRead {
        #if DEBUG
        if let keychainOverride {
            switch keychainOverride {
            case .absent:
                return .notFound
            case .stored(let keys):
                return .found(Set(keys.compactMap(normalizedPublicKey)))
            case .unavailable:
                return .unavailable
            }
        }
        #endif
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: TombstoneSigning.keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return .notFound }
        guard status == errSecSuccess, let data = result as? Data else { return .unavailable }
        guard let array = try? JSONDecoder().decode([String].self, from: data) else {
            // Corrupt item: do not treat as missing (that would re-import the
            // UserDefaults plist — the original write-vector). Fail closed.
            return .found([])
        }
        return .found(Set(array.compactMap(normalizedPublicKey)))
    }

    @discardableResult
    private static func saveKeychainKeys(_ keys: Set<String>) -> Bool {
        #if DEBUG
        if let override = keychainOverride {
            switch override {
            case .absent, .stored:
                keychainOverride = .stored(keys)
                return true
            case .unavailable:
                return false
            }
        }
        #endif
        guard let data = try? JSONEncoder().encode(Array(keys).sorted()) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: TombstoneSigning.keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecSuccess { return true }
        if status == errSecDuplicateItem {
            return SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
                == errSecSuccess
        }
        return false
    }

    private static func loadKeys(defaults: UserDefaults) -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        if defaults !== UserDefaults.standard {
            let stored = defaults.stringArray(forKey: localKeysKey) ?? []
            return Set(stored.compactMap(normalizedPublicKey))
        }

        switch loadKeychainKeys() {
        case .found(let keys):
            // Item exists (even if empty) — never import UserDefaults again.
            // An unsandboxed same-user process can still write the plist; a
            // union-on-every-launch migration would re-open that write-vector.
            if defaults.object(forKey: localKeysKey) != nil {
                defaults.removeObject(forKey: localKeysKey)
            }
            return keys
        case .notFound:
            let legacy = Set(
                (defaults.stringArray(forKey: localKeysKey) ?? []).compactMap(normalizedPublicKey)
            )
            // Persist even an empty set so a later plist write cannot be
            // imported as a "first" migration.
            if saveKeychainKeys(legacy) {
                defaults.removeObject(forKey: localKeysKey)
            }
            return legacy
        case .unavailable:
            // Fail closed. Leave UserDefaults so a later launch can retry the
            // real one-time migration. Do not treat this as "no item".
            return []
        }
    }

    private static func saveKeys(_ keys: Set<String>, defaults: UserDefaults) {
        lock.lock()
        defer { lock.unlock() }
        if defaults !== UserDefaults.standard {
            defaults.set(Array(keys).sorted(), forKey: localKeysKey)
            return
        }
        _ = saveKeychainKeys(keys)
    }

    static func normalizedPublicKey(_ hex: String) -> String? {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard cleaned.count == 64, TombstoneSigning.data(fromHex: cleaned)?.count == 32 else {
            return nil
        }
        return cleaned
    }

    private static func refreshFromiCloudIfNeeded(defaults: UserDefaults) {
        registerObserverIfNeeded()
        guard defaults === UserDefaults.standard, let store = iCloudStore else { return }
        store.synchronize()
        mergeFromiCloud(defaults: defaults)
    }

    /// Union of every `"pub.*"` entry in the store, plus (defensively) the
    /// legacy whole-set key from before D9(b), minus whatever this device has
    /// denylisted. Never removes a locally-trusted key just because its
    /// `"pub.*"` entry disappeared — only an explicit entry in the revoked
    /// record does that. `store.dictionaryRepresentation` is a local,
    /// already-synchronized snapshot; this performs no network I/O itself.
    private static func remotePublishedPubs(from store: any KeyValueStoring) -> Set<String> {
        var pubs = Set<String>()
        for (key, value) in store.dictionaryRepresentation where key.hasPrefix("pub.") {
            if let hex = value as? String, let normalized = normalizedPublicKey(hex) {
                pubs.insert(normalized)
            }
        }
        for hex in (store.array(forKey: iCloudKeysKey) as? [String] ?? []) {
            if let normalized = normalizedPublicKey(hex) {
                pubs.insert(normalized)
            }
        }
        return pubs
    }

    private static func remoteHexSet(from store: any KeyValueStoring, key: String) -> Set<String> {
        Set((store.array(forKey: key) as? [String] ?? []).compactMap(normalizedPublicKey))
    }

    static func mergeFromiCloud(defaults: UserDefaults = .standard) {
        guard defaults === UserDefaults.standard, let store = iCloudStore else { return }
        lock.lock()
        defer { lock.unlock() }

        // Revocations first, both kinds, before considering what to add — a
        // key revoked and (by a race, or a hostile republish) still present
        // in "pub.*" this same pass must not be imported a moment after
        // being dropped.
        applyRemoteRevocations(
            remoteHexSet(from: store, key: iCloudRevokedKey), denylist: true, defaults: defaults
        )
        applyRemoteRevocations(
            remoteHexSet(from: store, key: iCloudUntrustedKey), denylist: false, defaults: defaults
        )

        let remote = remotePublishedPubs(from: store)
        guard !remote.isEmpty else { return }
        let denylist = denylistedKeys(defaults: defaults)
        var keys = loadKeys(defaults: defaults)
        var changed = false
        for hex in remote where !denylist.contains(hex) {
            if keys.insert(hex).inserted {
                changed = true
            }
        }
        if changed {
            saveKeys(keys, defaults: defaults)
        }
    }

    /// Shared by both revocation records: untrust locally, and — only for the
    /// denylisting (stolen) record — add to the local denylist too.
    private static func applyRemoteRevocations(_ hexes: Set<String>, denylist: Bool, defaults: UserDefaults) {
        guard !hexes.isEmpty else { return }
        var keys = loadKeys(defaults: defaults)
        var denylisted = denylistedKeys(defaults: defaults)
        var keysChanged = false
        var denylistChanged = false
        for hex in hexes {
            if keys.remove(hex) != nil { keysChanged = true }
            if denylist, denylisted.insert(hex).inserted { denylistChanged = true }
        }
        if keysChanged { saveKeys(keys, defaults: defaults) }
        if denylistChanged { defaults.set(denylisted.sorted(), forKey: localRevokedKeysKey) }
    }

    /// Publishes only this device's own pub, under its own key — never the
    /// whole local trusted set. Called after a successful local `add`, so the
    /// set of devices that ever call this is exactly the set of devices that
    /// have trusted at least one peer (including the always-true "trust my
    /// own key" case handled by `SettingsView`'s `.onAppear`).
    private static func publishOwnPubToiCloud(defaults: UserDefaults) {
        guard defaults === UserDefaults.standard, let store = iCloudStore else { return }
        guard let own = TombstoneSigning.normalizedPublicKey(TombstoneSigning.publicKeyHex()) else { return }
        store.set(own, forKey: iCloudPubKey(forDevice: PersistenceDevice.currentID(defaults: defaults)))
        store.synchronize()
    }

    /// The inverse of publishing a "retired" revocation: called on a
    /// successful local `add`, so a stale "untrusted" record entry from a
    /// previous retirement cannot keep re-untrusting a key someone has since
    /// legitimately re-trusted. Never touches the denylist record — that one
    /// is intentionally not clearable this way.
    private static func clearFromRemoteUntrusted(_ normalized: String, defaults: UserDefaults) {
        guard defaults === UserDefaults.standard, let store = iCloudStore else { return }
        var untrusted = remoteHexSet(from: store, key: iCloudUntrustedKey)
        guard untrusted.remove(normalized) != nil else { return }
        store.set(untrusted.sorted(), forKey: iCloudUntrustedKey)
        store.synchronize()
    }

    /// Publishes a revocation so every device on the same Apple ID drops the
    /// key, not just this one — to whichever of the two records matches
    /// `reason`, so a device merging it back knows whether to denylist. Also
    /// best-effort clears a matching `"pub.*"` entry if one exists, so a
    /// fresh `mergeFromiCloud` elsewhere does not even see it as a candidate
    /// — the revoked-record check above is the actual enforcement point,
    /// this is belt-and-suspenders cleanup.
    private static func publishRevocationToiCloud(
        _ normalized: String,
        reason: TombstoneRevokeReason,
        defaults: UserDefaults
    ) {
        guard defaults === UserDefaults.standard, let store = iCloudStore else { return }
        let key = reason == .stolenOrCompromised ? iCloudRevokedKey : iCloudUntrustedKey
        var revoked = remoteHexSet(from: store, key: key)
        if revoked.insert(normalized).inserted {
            store.set(revoked.sorted(), forKey: key)
        }
        if let staleKey = store.dictionaryRepresentation.first(where: {
            $0.key.hasPrefix("pub.") && ($0.value as? String).flatMap(normalizedPublicKey) == normalized
        })?.key {
            store.removeObject(forKey: staleKey)
        }
        store.synchronize()
    }

    private static func registerObserverIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !didRegisterObserver else { return }
        // Do not latch the observer against a nil store: D9(b) will assign
        // `.default` later, and `object: nil` would observe every KVS.
        guard iCloudStore != nil else { return }
        didRegisterObserver = true
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: iCloudStore,
            queue: .main
        ) { _ in
            mergeFromiCloud()
        }
    }
}

private extension TombstoneSigning {
    static func normalizedPublicKey(_ hex: String) -> String? {
        TombstoneTrustStore.normalizedPublicKey(hex)
    }
}
