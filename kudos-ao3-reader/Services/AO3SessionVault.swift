import Foundation
import Security
import WebKit

protocol AO3SessionPersisting {
    func load() throws -> AO3Session?
    func save(_ session: AO3Session) throws
    func delete() throws
}

enum AO3SessionVaultError: LocalizedError {
    case keychain(OSStatus)
    case invalidData

    var isMissingEntitlement: Bool {
        if case let .keychain(status) = self {
            return status == errSecMissingEntitlement
        }
        return false
    }

    var errorDescription: String? {
        switch self {
        case let .keychain(status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "Keychain error: \(detail)"
        case .invalidData:
            return "The saved AO3 session could not be read."
        }
    }
}

protocol AO3SessionHintPersisting {
    func loadUsername() -> String?
    func saveUsername(_ username: String)
    func deleteUsername()
}

/// Stores only a non-secret username hint. Authentication cookies remain in
/// Keychain or WebKit's app-scoped data store and are never written here.
struct UserDefaultsAO3SessionHintStore: AO3SessionHintPersisting {
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "AO3AuthenticatedUsername"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func loadUsername() -> String? {
        defaults.string(forKey: key)
    }

    func saveUsername(_ username: String) {
        defaults.set(username, forKey: key)
    }

    func deleteUsername() {
        defaults.removeObject(forKey: key)
    }
}

/// Stores the AO3 session as one device-only Keychain item. The session remains
/// available after the first device unlock so future background sync can reuse it,
/// but it is not migrated to another device or included in an unencrypted backup.
struct KeychainAO3SessionVault: AO3SessionPersisting {
    private let service: String
    private let account = "ao3-session"

    init(service: String = (Bundle.main.bundleIdentifier ?? "Kudos") + ".authentication") {
        self.service = service
    }

    func load() throws -> AO3Session? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw AO3SessionVaultError.keychain(status) }
        guard let data = result as? Data else { throw AO3SessionVaultError.invalidData }
        do {
            return try JSONDecoder().decode(AO3Session.self, from: data)
        } catch {
            throw AO3SessionVaultError.invalidData
        }
    }

    func save(_ session: AO3Session) throws {
        let data = try JSONEncoder().encode(session)
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw AO3SessionVaultError.keychain(updateStatus)
            }
        } else if status != errSecSuccess {
            throw AO3SessionVaultError.keychain(status)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AO3SessionVaultError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

/// App-container session file used when Keychain can't hold the session
/// (unsigned / Simulator `errSecMissingEntitlement` builds) and as a durable
/// backup that survives process death better than relying on WebKit cookie
/// capture alone. Wiped with the app; never migrates via iCloud backup of the
/// Keychain item.
struct FileAO3SessionVault: AO3SessionPersisting {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
            return
        }
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
            ?? FileManager.default.temporaryDirectory
        let directory = support.appendingPathComponent("KudosAuth", isDirectory: true)
        self.fileURL = directory.appendingPathComponent("ao3-session.json")
    }

    func load() throws -> AO3Session? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw AO3SessionVaultError.invalidData
        }
        do {
            return try JSONDecoder().decode(AO3Session.self, from: data)
        } catch {
            throw AO3SessionVaultError.invalidData
        }
    }

    func save(_ session: AO3Session) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(session)
        #if os(iOS)
        try data.write(
            to: fileURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        #else
        try data.write(to: fileURL, options: [.atomic])
        #endif
    }

    func delete() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}

/// Keychain-first session vault. On signed builds only Keychain is written.
/// When Keychain returns `errSecMissingEntitlement` (Simulator / unsigned),
/// falls back to an Application Support file so relaunch still restores.
struct CascadingAO3SessionVault: AO3SessionPersisting {
    private let keychain: KeychainAO3SessionVault
    private let file: FileAO3SessionVault

    init(
        keychain: KeychainAO3SessionVault = KeychainAO3SessionVault(),
        file: FileAO3SessionVault = FileAO3SessionVault()
    ) {
        self.keychain = keychain
        self.file = file
    }

    func load() throws -> AO3Session? {
        do {
            if let session = try keychain.load(), session.hasSessionCookie {
                return session
            }
        } catch {
            // Missing entitlement / transient Keychain errors: fall through to file.
            if !Self.isMissingEntitlement(error) {
                // Still try the file before surfacing a hard failure — an
                // overwrite install can leave Keychain unreadable while the
                // container file is intact.
                if let session = try? file.load(), session.hasSessionCookie {
                    return session
                }
                throw error
            }
        }
        return try file.load()
    }

    func save(_ session: AO3Session) throws {
        do {
            try keychain.save(session)
            // Keychain is the production store of record — do not dual-write
            // session cookies into Application Support on signed builds.
            try? file.delete()
            return
        } catch {
            // Simulator / unsigned builds: Keychain often returns
            // errSecMissingEntitlement. Only then persist to the app-container
            // file (cleared on logout / uninstall with the rest of the vault).
            guard Self.isMissingEntitlement(error) else { throw error }
            try file.save(session)
        }
    }

    func delete() throws {
        // Missing-entitlement Keychain failures are expected on unsigned /
        // Simulator builds — the file vault is what actually has the session.
        do {
            try keychain.delete()
        } catch {
            if !Self.isMissingEntitlement(error) { throw error }
        }
        try file.delete()
    }

    private static func isMissingEntitlement(_ error: Error) -> Bool {
        (error as? AO3SessionVaultError)?.isMissingEntitlement == true
    }
}

/// Keeps WebKit, URLSession, and the Keychain model in agreement. Browser and
/// fallback login views both use the default WebKit data store, so installing or
/// clearing cookies here updates every AO3 WebView in the app.
@MainActor
enum AO3CookieBridge {
    static func install(_ session: AO3Session) async {
        for stored in session.validCookies {
            guard let cookie = stored.httpCookie else { continue }
            await set(cookie, in: WKWebsiteDataStore.default().httpCookieStore)
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    static func clearAO3Cookies() async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let webCookies = await allCookies(in: store)
        for cookie in webCookies where AO3StoredCookie.isAO3Domain(cookie.domain) {
            await delete(cookie, from: store)
        }

        for cookie in HTTPCookieStorage.shared.cookies ?? []
            where AO3StoredCookie.isAO3Domain(cookie.domain) {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    static func captureAO3Cookies() async -> [AO3StoredCookie] {
        let cookies = await allCookies(in: WKWebsiteDataStore.default().httpCookieStore)
        return cookies
            .filter { AO3StoredCookie.isAO3Domain($0.domain) }
            .map(AO3StoredCookie.init)
    }

    private static func allCookies(in store: WKHTTPCookieStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
    }

    private static func set(_ cookie: HTTPCookie, in store: WKHTTPCookieStore) async {
        await withCheckedContinuation { continuation in
            store.setCookie(cookie) { continuation.resume() }
        }
    }

    private static func delete(_ cookie: HTTPCookie, from store: WKHTTPCookieStore) async {
        await withCheckedContinuation { continuation in
            store.delete(cookie) { continuation.resume() }
        }
    }
}
