import Foundation
import Security

struct MailCredentials: Codable, Equatable, Sendable {
    let address: String
    let appPassword: String
}

protocol MailCredentialsPersisting {
    func load() throws -> MailCredentials?
    func save(_ credentials: MailCredentials) throws
    func delete() throws
}

enum MailCredentialsVaultError: LocalizedError {
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
            return "The saved mail connection could not be read."
        }
    }
}

/// Device-only Keychain storage for the Gmail address and app password.
struct KeychainMailCredentialsVault: MailCredentialsPersisting {
    private let service: String
    private let account = "gmail-imap"

    nonisolated init(service: String = (Bundle.main.bundleIdentifier ?? "Kudos") + ".mail-authentication") {
        self.service = service
    }

    func load() throws -> MailCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw MailCredentialsVaultError.keychain(status) }
        guard let data = result as? Data,
              let credentials = try? JSONDecoder().decode(MailCredentials.self, from: data)
        else { throw MailCredentialsVaultError.invalidData }
        return credentials
    }

    func save(_ credentials: MailCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw MailCredentialsVaultError.keychain(updateStatus)
            }
        } else if status != errSecSuccess {
            throw MailCredentialsVaultError.keychain(status)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MailCredentialsVaultError.keychain(status)
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
