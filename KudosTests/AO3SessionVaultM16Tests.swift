import Testing
import Foundation
@testable import Kudos

@Suite("AO3SessionVault M16 Tests")
struct AO3SessionVaultM16Tests {
    @Test("Keychain attribute is re-asserted on update")
    func keychainAccessibleAttributeIsReasserted() throws {
        let vault = AO3SessionVault()
        try? vault.delete()
        
        let session1 = AO3Session(cookies: [], createdAt: Date())
        try vault.save(session1)
        
        // Manually weaken the accessibility class to simulate an old item
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "org.archiveofourown.session"
        ]
        let weakUpdate: [String: Any] = [
            kSecAttrAccessible as String: kSecAttrAccessibleAlways
        ]
        SecItemUpdate(query as CFDictionary, weakUpdate as CFDictionary)
        
        // Save again using production code
        let session2 = AO3Session(cookies: [], createdAt: Date())
        try vault.save(session2)
        
        // Verify the accessibility class was restored
        var item: CFTypeRef?
        let checkQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "org.archiveofourown.session",
            kSecReturnAttributes as String: true
        ]
        let status = SecItemCopyMatching(checkQuery as CFDictionary, &item)
        #expect(status == errSecSuccess)
        
        if let attributes = item as? [String: Any],
           let accessible = attributes[kSecAttrAccessible as String] as? String {
            #expect(accessible == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        } else {
            Issue.record("Failed to read keychain attributes")
        }
        
        try? vault.delete()
    }
}
