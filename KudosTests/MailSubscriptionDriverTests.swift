import Foundation
import Testing
@testable import Kudos

struct MailPersistenceTests {
    private let when = Date(timeIntervalSince1970: 1_762_000_000)

    @Test func credentialVaultRoundTripsAndDeletes() throws {
        let credentials = MailCredentials(address: "reader@gmail.com", appPassword: "app-password")
        let memory = MemoryMailCredentialsVault()
        try memory.save(credentials)
        #expect(try memory.load() == credentials)
        try memory.delete()
        #expect(try memory.load() == nil)

        let keychain = KeychainMailCredentialsVault(
            service: "KudosTests.mail.\(UUID().uuidString)"
        )
        defer { try? keychain.delete() }
        do {
            try keychain.save(credentials)
            #expect(try keychain.load() == credentials)
            try keychain.delete()
            #expect(try keychain.load() == nil)
        } catch let error as MailCredentialsVaultError where error.isMissingEntitlement {
            // Unsigned test hosts use the protocol-backed in-memory round trip above.
        }
    }

    @Test func updateStoreRoundTripsCapsAndDeletes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kudos-mail-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileSubscriptionUpdateStore(directoryURL: directory)
        let updates = (0 ..< 501).map { offset in
            makeUpdate(uid: UInt32(offset + 1), at: when.addingTimeInterval(Double(offset)))
        }
        let state = SubscriptionUpdateState(
            updates: updates,
            counts: MailImportCounts(refused: 1, otherAO3Mail: 2, tooLarge: 3, swiftRefused: 4),
            since: when,
            lastRefreshAt: when
        )
        let cursor = MailCursor(uidValidity: 7, lastUID: 501)

        try store.saveState(state)
        try store.saveCursor(cursor)

        let loaded = try store.loadState()
        #expect(loaded.updates.count == 500)
        #expect(loaded.updates.first?.uid == 501)
        #expect(loaded.counts == state.counts)
        #expect(try store.loadCursor() == cursor)

        try store.delete()
        #expect(try store.loadState() == .init())
        #expect(try store.loadCursor() == nil)
    }

    private func makeUpdate(uid: UInt32, at: Date) -> SubscriptionUpdate {
        SubscriptionUpdate(
            uid: uid,
            workID: UInt64(uid),
            chapterID: UInt64(uid),
            chapterNumber: Int(uid),
            isNewWork: false,
            isContested: false,
            isAnchoredToWork: true,
            workTitle: "Work \(uid)",
            author: "Author",
            at: at,
            source: .work
        )
    }
}

#if os(iOS)
@MainActor
struct MailSubscriptionDriverTests {
    private let when = Date(timeIntervalSince1970: 1_762_000_000)
    private let credentials = MailCredentials(
        address: "reader@gmail.com",
        appPassword: "app-password"
    )

    @Test func deduplicatesByUIDAndSavesCursorAfterUpdates() async {
        let vault = MemoryMailCredentialsVault(credentials: credentials)
        let store = MemorySubscriptionUpdateStore()
        let mailbox = FakeMailbox(harvests: [
            harvest(readings: [reading(uid: 1)], lastUID: 1, moreWaiting: true),
            harvest(readings: [reading(uid: 1)], lastUID: 1)
        ])
        let driver = makeDriver(vault: vault, store: store, mailbox: mailbox)

        await driver.refresh()

        #expect(driver.updates.count == 1)
        #expect(driver.updates.first?.uid == 1)
        #expect(store.events.starts(with: [.state, .cursor]))
        let readCount = await mailbox.readCount
        #expect(readCount == 2)
    }

    @Test func capsMoreWaitingBatchesPerRefresh() async {
        let vault = MemoryMailCredentialsVault(credentials: credentials)
        let store = MemorySubscriptionUpdateStore()
        let mailbox = FakeMailbox(harvests: [
            harvest(readings: [reading(uid: 1)], lastUID: 1, moreWaiting: true),
            harvest(readings: [reading(uid: 2)], lastUID: 2, moreWaiting: true),
            harvest(readings: [reading(uid: 3)], lastUID: 3, moreWaiting: true)
        ])
        let driver = makeDriver(vault: vault, store: store, mailbox: mailbox, batchLimit: 2)

        await driver.refresh()

        let readCount = await mailbox.readCount
        #expect(readCount == 2)
        #expect(driver.updates.map(\.uid).sorted() == [1, 2])
        #expect(driver.hasMoreWaiting)
    }

    @Test func closesMailboxWhenReadThrows() async {
        let vault = MemoryMailCredentialsVault(credentials: credentials)
        let store = MemorySubscriptionUpdateStore()
        let mailbox = FakeMailbox(throwsOnRead: true)
        let driver = makeDriver(vault: vault, store: store, mailbox: mailbox)

        await driver.refresh()

        let closeCount = await mailbox.closeCount
        #expect(closeCount == 1)
        #expect(driver.errorMessage != nil)
    }

    @Test func countsEveryRefusalAndNeverShowsSenderOnlyMail() async {
        let vault = MemoryMailCredentialsVault(credentials: credentials)
        let store = MemorySubscriptionUpdateStore()
        let mailbox = FakeMailbox(harvests: [
            harvest(
                readings: [reading(uid: 1), reading(uid: 2, verdict: .senderOnly)],
                lastUID: 2,
                refused: 2,
                otherAO3Mail: 3,
                tooLarge: 4
            )
        ])
        let driver = makeDriver(vault: vault, store: store, mailbox: mailbox)

        await driver.refresh()

        #expect(driver.updates.map(\.uid) == [1])
        #expect(driver.state.counts.refused == 2)
        #expect(driver.state.counts.otherAO3Mail == 3)
        #expect(driver.state.counts.tooLarge == 4)
        #expect(driver.state.counts.swiftRefused == 1)
        #expect(driver.unverifiedCount == 10)
    }

    @Test func changedUIDValidityReplacesRowsFromTheOldGeneration() async {
        let vault = MemoryMailCredentialsVault(credentials: credentials)
        let old = update(uid: 90, workID: 90)
        let store = MemorySubscriptionUpdateStore(
            state: SubscriptionUpdateState(updates: [old], since: when),
            cursor: MailCursor(uidValidity: 7, lastUID: 90)
        )
        let mailbox = FakeMailbox(harvests: [
            harvest(readings: [reading(uid: 1)], uidValidity: 8, lastUID: 1)
        ])
        let driver = makeDriver(vault: vault, store: store, mailbox: mailbox)

        await driver.refresh()

        #expect(driver.updates.map(\.uid) == [1])
        #expect(store.cursor == MailCursor(uidValidity: 8, lastUID: 1))
    }

    @Test func refreshOnAppearIsThrottledForFiveMinutes() async {
        let vault = MemoryMailCredentialsVault(credentials: credentials)
        let now = when.addingTimeInterval(299)
        let store = MemorySubscriptionUpdateStore(
            state: SubscriptionUpdateState(lastRefreshAt: when)
        )
        let mailbox = FakeMailbox(harvests: [harvest()])
        let driver = makeDriver(vault: vault, store: store, mailbox: mailbox, now: { now })

        await driver.refreshIfNeeded()

        let readCount = await mailbox.readCount
        #expect(readCount == 0)
    }

    @Test func failedConnectStoresNoCredentialsOrUpdatesAndCloses() async {
        let vault = MemoryMailCredentialsVault()
        let store = MemorySubscriptionUpdateStore()
        let mailbox = FakeMailbox(throwsOnRead: true)
        let driver = makeDriver(vault: vault, store: store, mailbox: mailbox)

        await #expect(throws: MailSubscriptionDriverError.self) {
            try await driver.connect(address: credentials.address, appPassword: credentials.appPassword)
        }

        #expect(vault.credentials == nil)
        #expect(store.state.updates.isEmpty)
        let closeCount = await mailbox.closeCount
        #expect(closeCount == 1)
    }

    /// The sheet's Cancel lands while the IMAP await is suspended, and that
    /// await still returns; nothing may be saved after it, and the store goes
    /// back to what it held before.
    @Test func cancelledConnectStoresNoCredentialsAndRestoresTheStore() async {
        let vault = MemoryMailCredentialsVault()
        let previous = SubscriptionUpdateState(updates: [update(uid: 1, workID: 1)], since: when)
        let store = MemorySubscriptionUpdateStore(state: previous, cursor: MailCursor(uidValidity: 7, lastUID: 1))
        let mailbox = FakeMailbox(harvests: [harvest(readings: [reading(uid: 2)], lastUID: 2)])
        let driver = makeDriver(vault: vault, store: store, mailbox: mailbox)

        let task = Task {
            try await driver.connect(address: credentials.address, appPassword: credentials.appPassword)
        }
        mailbox.onRead = { task.cancel() }
        await #expect(throws: CancellationError.self) { try await task.value }

        #expect(vault.credentials == nil)
        #expect(!driver.isConnected)
        #expect(store.cursor == MailCursor(uidValidity: 7, lastUID: 1))
        #expect(store.state.updates == previous.updates)
        #expect(driver.updates == previous.updates)
    }

    @Test func disconnectDeletesCredentialsAndStoredUpdates() throws {
        let vault = MemoryMailCredentialsVault(credentials: credentials)
        let store = MemorySubscriptionUpdateStore(
            state: SubscriptionUpdateState(updates: [update(uid: 1, workID: 1)], since: when),
            cursor: MailCursor(uidValidity: 7, lastUID: 1)
        )
        let mailbox = FakeMailbox(harvests: [])
        let driver = makeDriver(vault: vault, store: store, mailbox: mailbox)

        try driver.disconnect()

        #expect(vault.credentials == nil)
        #expect(store.state == .init())
        #expect(store.cursor == nil)
        #expect(!driver.isConnected)
        #expect(driver.updates.isEmpty)
    }

    private func makeDriver(
        vault: MemoryMailCredentialsVault,
        store: MemorySubscriptionUpdateStore,
        mailbox: FakeMailbox,
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_762_000_000) },
        batchLimit: Int = MailSubscriptionDriver.defaultBatchLimit
    ) -> MailSubscriptionDriver {
        MailSubscriptionDriver(
            credentialsVault: vault,
            store: store,
            connector: { _ in mailbox },
            now: now,
            batchLimit: batchLimit
        )
    }

    private func harvest(
        readings: [Reading] = [],
        uidValidity: UInt32 = 7,
        lastUID: UInt32 = 0,
        refused: UInt64 = 0,
        otherAO3Mail: UInt64 = 0,
        tooLarge: UInt64 = 0,
        moreWaiting: Bool = false
    ) -> Harvest {
        Harvest(
            readings: readings,
            cursor: Cursor(uidValidity: uidValidity, lastUid: lastUID),
            otherAo3Mail: otherAO3Mail,
            refused: refused,
            tooLarge: tooLarge,
            moreWaiting: moreWaiting
        )
    }

    private func reading(uid: UInt32, verdict: Verdict = .trusted) -> Reading {
        Reading(
            uid: uid,
            event: Ao3Event(
                identity: .work,
                kind: .newChapter(number: 1),
                at: Int64(when.timeIntervalSince1970) + Int64(uid),
                workId: UInt64(uid),
                chapterId: UInt64(uid),
                workTitle: "Work \(uid)",
                author: "Author",
                via: .work(id: UInt64(uid), name: nil),
                chaptersPosted: 1,
                chaptersTotal: nil,
                words: nil,
                chapterTitle: nil,
                chapterWords: nil,
                rating: nil,
                warnings: [],
                fandoms: [],
                relationships: [],
                characters: [],
                additionalTags: [],
                series: nil,
                summary: nil,
                extraCreations: 0
            ),
            verdict: verdict
        )
    }

    private func update(uid: UInt32, workID: UInt64) -> SubscriptionUpdate {
        SubscriptionUpdate(
            uid: uid,
            workID: workID,
            chapterID: workID,
            chapterNumber: 1,
            isNewWork: false,
            isContested: false,
            isAnchoredToWork: true,
            workTitle: "Old work",
            author: "Author",
            at: when,
            source: .work
        )
    }
}

private final class FakeMailbox: MailboxProtocol {
    private var harvests: [Harvest]
    private let throwsOnRead: Bool
    private(set) var readCount = 0
    private(set) var closeCount = 0

    init(harvests: [Harvest] = [], throwsOnRead: Bool = false) {
        self.harvests = harvests
        self.throwsOnRead = throwsOnRead
    }

    /// Runs inside the read, as if Cancel arrived during the IMAP await.
    var onRead: (() -> Void)?

    func readNew(cursor: Cursor?, authservId: String?) async throws -> Harvest {
        readCount += 1
        onRead?()
        if throwsOnRead { throw FakeMailboxError.read }
        guard !harvests.isEmpty else { throw FakeMailboxError.read }
        return harvests.removeFirst()
    }

    func close() async throws {
        closeCount += 1
    }
}

private enum FakeMailboxError: Error {
    case read
}
#endif

private final class MemoryMailCredentialsVault: MailCredentialsPersisting {
    var credentials: MailCredentials?

    init(credentials: MailCredentials? = nil) {
        self.credentials = credentials
    }

    func load() throws -> MailCredentials? { credentials }
    func save(_ credentials: MailCredentials) throws { self.credentials = credentials }
    func delete() throws { credentials = nil }
}

private final class MemorySubscriptionUpdateStore: SubscriptionUpdateStoring {
    enum Event: Equatable {
        case state
        case cursor
    }

    var state: SubscriptionUpdateState
    var cursor: MailCursor?
    var events: [Event] = []

    init(
        state: SubscriptionUpdateState = .init(),
        cursor: MailCursor? = nil
    ) {
        self.state = state
        self.cursor = cursor
    }

    func loadState() throws -> SubscriptionUpdateState { state }

    func saveState(_ state: SubscriptionUpdateState) throws {
        events.append(.state)
        self.state = state.capped()
    }

    func loadCursor() throws -> MailCursor? { cursor }

    func saveCursor(_ cursor: MailCursor?) throws {
        events.append(.cursor)
        self.cursor = cursor
    }

    func delete() throws {
        state = .init()
        cursor = nil
    }
}
