import Foundation
import Testing
@testable import Kudos

@Suite("AO3SessionVault M13 Tests")
struct AO3SessionVaultM13Tests {
    /// Production `FileAO3SessionVault.save` must set `isExcludedFromBackup` on
    /// the session file. Skipping `excludeFromBackup` after the atomic write
    /// makes this assertion fail (nil/false).
    @Test func fileVaultExcludesSessionFileFromBackup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kudos-ao3-session-m13-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("ao3-session.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let vault = FileAO3SessionVault(fileURL: url)
        let session = AO3Session(
            username: "reader",
            cookies: [AO3StoredCookie(name: "_otwarchive_session", value: "session")]
        )
        try vault.save(session)
        // Second save: atomic replace must re-apply the exclude flag.
        try vault.save(session)

        let fileValues = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(fileValues.isExcludedFromBackup == true)
        let directoryValues = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(directoryValues.isExcludedFromBackup == true)
    }
}
