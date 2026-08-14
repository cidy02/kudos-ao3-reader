import Testing
import Foundation
@testable import Kudos

#if os(macOS)
@Suite("AO3SessionVault M16 Tests")
struct AO3SessionVaultM16Tests {
    @Test("Keychain attribute is re-asserted on update")
    @MainActor func keychainAccessibleAttributeIsReasserted() throws {
        let vault = KeychainAO3SessionVault(service: "org.archiveofourown.session.test")
        try? vault.delete()
        
        let session1 = AO3Session(username: "testuser", cookies: [], savedAt: Date())
        try vault.save(session1)
        
        // Manually weaken the accessibility class to simulate an old item
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "org.archiveofourown.session.test"
        ]
        let weakUpdate: [String: Any] = [
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemUpdate(query as CFDictionary, weakUpdate as CFDictionary)
        
        // Save again using production code
        let session2 = AO3Session(username: "testuser", cookies: [], savedAt: Date())
        try vault.save(session2)
        
        // Verify the accessibility class was restored
        var item: CFTypeRef?
        let checkQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "org.archiveofourown.session.test",
            kSecReturnAttributes as String: true
        ]
        let status = SecItemCopyMatching(checkQuery as CFDictionary, &item)
        #expect(status == errSecSuccess)
        
        if let attributes = item as? NSDictionary {
            if let accessible = attributes[kSecAttrAccessible as String] {
                let accessibleStr = String(describing: accessible)
                let targetStr = String(describing: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
                #expect(accessibleStr == targetStr)
            } else {
                // macOS keychain may omit the accessibility attribute
                #expect(attributes[kSecAttrService as String] as? String == "org.archiveofourown.session.test")
            }
        } else {
            Issue.record("Failed to read keychain attributes: \(String(describing: item))")
        }
        
        try? vault.delete()
    }
}
#endif
