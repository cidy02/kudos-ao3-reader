import Testing
import Foundation
@testable import Kudos

@Suite("AO3SessionVault M16 Tests")
struct AO3SessionVaultM16Tests {
    @Test("SecItemUpdate re-asserts AfterFirstUnlockThisDeviceOnly")
    func keychainUpdateAttributesReassertAccessibility() throws {
        let data = Data("session-blob".utf8)
        let attributes = KeychainAO3SessionVault.updateItemAttributes(data: data)

        let accessible = attributes[kSecAttrAccessible as String] as? String
        #expect(
            accessible == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String),
            "SecItemUpdate omitted kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly"
        )
        #expect(attributes[kSecValueData as String] as? Data == data)

        // Also drive save() when the Simulator Keychain is entitled. Missing
        // entitlement is the unsigned/Simulator fallback, not a pass.
        let service = "org.archiveofourown.session.test.\(UUID().uuidString)"
        let vault = KeychainAO3SessionVault(service: service)
        try? vault.delete()
        defer { try? vault.delete() }

        let session = AO3Session(username: "testuser", cookies: [], savedAt: Date())
        do {
            try vault.save(session)
            try vault.save(session)

            var item: CFTypeRef?
            let checkQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecReturnAttributes as String: true
            ]
            let status = SecItemCopyMatching(checkQuery as CFDictionary, &item)
            #expect(status == errSecSuccess, "Could not read back the saved Keychain item: \(status)")
            let attributes = try #require(item as? NSDictionary)
            let accessible = attributes[kSecAttrAccessible] as? String
                ?? attributes[kSecAttrAccessible as String] as? String
            #expect(
                accessible == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String),
                "Saved Keychain item did not re-assert AfterFirstUnlockThisDeviceOnly"
            )
        } catch let error as AO3SessionVaultError where error.isMissingEntitlement {
            // Simulator / unsigned: the update-dictionary assertion above is
            // the load-bearing check. Do not treat this as success of save().
        }
    }
}
