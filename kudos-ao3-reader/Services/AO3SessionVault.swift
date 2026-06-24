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
        if case .keychain(let status) = self {
            return status == errSecMissingEntitlement
        }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
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
