#if os(iOS)

import Foundation
import Testing
@testable import Kudos

/// Opt-in live check of the whole mail path: Swift → UniFFI → Rust → Gmail IMAP.
/// Skipped unless KUDOS_LIVE_MAIL_ADDRESS and KUDOS_LIVE_MAIL_PASSWORD are set
/// (for xcodebuild, prefix each with TEST_RUNNER_). Never commit either value.
@MainActor
struct MailLiveTests {
    private static let env = ProcessInfo.processInfo.environment

    @Test(.enabled(if: env["KUDOS_LIVE_MAIL_ADDRESS"] != nil && env["KUDOS_LIVE_MAIL_PASSWORD"] != nil))
    func liveGmailYieldsVerifiedUpdates() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailLiveTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let driver = MailSubscriptionDriver(
            credentialsVault: InMemoryVault(),
            store: FileSubscriptionUpdateStore(directoryURL: directory)
        )

        try await driver.connect(
            address: Self.env["KUDOS_LIVE_MAIL_ADDRESS"] ?? "",
            appPassword: Self.env["KUDOS_LIVE_MAIL_PASSWORD"] ?? ""
        )

        #expect(driver.isConnected)
        #expect(!driver.updates.isEmpty)
        // Counts only: titles and authors come from the account's real mail.
        print("live mail: \(driver.updates.count) updates, \(driver.unverifiedCount) unverified, more waiting: \(driver.hasMoreWaiting)")
    }
}

/// Keeps live credentials out of the simulator's Keychain.
private final class InMemoryVault: MailCredentialsPersisting {
    private var credentials: MailCredentials?
    func load() throws -> MailCredentials? { credentials }
    func save(_ credentials: MailCredentials) throws { self.credentials = credentials }
    func delete() throws { credentials = nil }
}

#endif
