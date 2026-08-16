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

/// Local trusted Ed25519 public keys. Own device pub is always trusted.
/// `NSUbiquitousKeyValueStore` publishes pubs for the same Apple ID only.
/// A `.kudosbackup` must never write this store.
enum TombstoneTrustStore {
    static let localKeysKey = "trustedTombstonePublicKeys"
    static let iCloudKeysKey = "tombstoneTrustedPublicKeys"

    /// `nil` by default, not `NSUbiquitousKeyValueStore.default`: constructing that
    /// store without the `com.apple.developer.ubiquity-kvstore-identifier`
    /// entitlement (which this build does not have) doesn't just no-op — Security
    /// logs "BUG IN CLIENT OF KVS: Trying to initialize NSUbiquitousKeyValueStore
    /// without a store identifier", and every `SecItemAdd`/`SecItemCopyMatching`
    /// call in the same process afterward starts failing (reproduced consistently:
    /// the trust-store Keychain item round-trips fine until anything in-process
    /// entitlement (which this build does not have, and per the design decision
    /// in D9(b) must not get one until its own activation checklist is met).
    /// Nothing currently sets this back to `.default`; that happens once the
    /// entitlement is actually added.
    static var iCloudStore: NSUbiquitousKeyValueStore?

    private static let lock = NSLock()
    private static var didRegisterObserver = false
    private static let keychainAccount = "trusted-tombstone-pubs"

    /// Tests set this to bypass the real Keychain, mirroring
    /// `TombstoneSigning.keyOverride`. Necessary, not optional: unsigned test
    /// builds (`CODE_SIGNING_ALLOWED=NO`) get `errSecMissingEntitlement` (-34018)
    /// from `SecItemAdd`/`SecItemCopyMatching` for this app's keychain-access
    /// group, the same status `TombstoneSigning.persistDeviceKey` already
    /// anticipates for the private key. A production, properly signed build has
    /// the group Xcode provisions automatically and does not need this — but a
    /// production fallback (writing trust to a file if Keychain fails, the way
    /// the private key does) would silently reopen the exact vulnerability
    /// D9(a) exists to close, since a file is exactly as writable by an
    /// unsandboxed same-user process as the `UserDefaults` plist this replaced.
    /// So the override is test-only, in-memory, and `nil` means "use the real
    /// Keychain" — never a disk fallback.
    static var keychainOverride: Set<String>?

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
        var keys = trustedPublicKeys(defaults: defaults)
        if keys.insert(normalized).inserted {
            saveKeys(keys, defaults: defaults)
            publishToiCloud(keys, defaults: defaults)
        }
        return true
    }

    @discardableResult
    static func remove(_ publicKeyHex: String, defaults: UserDefaults = .standard) -> Bool {
        guard let normalized = normalizedPublicKey(publicKeyHex) else { return false }
        var keys = trustedPublicKeys(defaults: defaults)
        if keys.remove(normalized) != nil {
            saveKeys(keys, defaults: defaults)
            removeFromiCloud(normalized, defaults: defaults)
            return true
        }
        return false
    }

    private static func loadKeychainKeys() -> Set<String>? {
        if let keychainOverride { return keychainOverride }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: TombstoneSigning.keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        guard let array = try? JSONDecoder().decode([String].self, from: data) else { return nil }
        return Set(array)
    }

    private static func saveKeychainKeys(_ keys: Set<String>) {
        if keychainOverride != nil {
            keychainOverride = keys
            return
        }
        guard let data = try? JSONEncoder().encode(Array(keys).sorted()) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: TombstoneSigning.keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
    }

    private static func loadKeys(defaults: UserDefaults) -> Set<String> {
        if defaults !== UserDefaults.standard {
            let stored = defaults.stringArray(forKey: localKeysKey) ?? []
            return Set(stored.compactMap(normalizedPublicKey))
        }

        if let legacy = defaults.stringArray(forKey: localKeysKey) {
            var keys = loadKeychainKeys() ?? []
            keys.formUnion(legacy.compactMap(normalizedPublicKey))
            saveKeychainKeys(keys)
            defaults.removeObject(forKey: localKeysKey)
            return keys
        }

        return loadKeychainKeys() ?? []
    }

    private static func saveKeys(_ keys: Set<String>, defaults: UserDefaults) {
        if defaults !== UserDefaults.standard {
            defaults.set(Array(keys).sorted(), forKey: localKeysKey)
            return
        }
        saveKeychainKeys(keys)
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

    static func mergeFromiCloud(defaults: UserDefaults = .standard) {
        guard defaults === UserDefaults.standard, let store = iCloudStore else { return }
        let remote = store.array(forKey: iCloudKeysKey) as? [String] ?? []
        guard !remote.isEmpty else { return }
        var keys = loadKeys(defaults: defaults)
        var changed = false
        for hex in remote {
            if let normalized = normalizedPublicKey(hex), keys.insert(normalized).inserted {
                changed = true
            }
        }
        if changed {
            saveKeys(keys, defaults: defaults)
        }
    }

    private static func publishToiCloud(_ keys: Set<String>, defaults: UserDefaults) {
        guard defaults === UserDefaults.standard, let store = iCloudStore else { return }
        var published = Set((store.array(forKey: iCloudKeysKey) as? [String] ?? []).compactMap(normalizedPublicKey))
        published.formUnion(keys)
        if let own = TombstoneSigning.normalizedPublicKey(TombstoneSigning.publicKeyHex()) {
            published.insert(own)
        }
        store.set(published.sorted(), forKey: iCloudKeysKey)
        store.synchronize()
    }

    private static func removeFromiCloud(_ normalized: String, defaults: UserDefaults) {
        guard defaults === UserDefaults.standard, let store = iCloudStore else { return }
        var published = Set((store.array(forKey: iCloudKeysKey) as? [String] ?? []).compactMap(normalizedPublicKey))
        published.remove(normalized)
        store.set(published.sorted(), forKey: iCloudKeysKey)
        store.synchronize()
    }

    private static func registerObserverIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !didRegisterObserver else { return }
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
