#if os(iOS)

import Foundation

private func connectGmailMailbox(_ saved: MailCredentials) async throws -> any MailboxProtocol {
    try await connect(
        credentials: Credentials(
            host: "imap.gmail.com",
            port: 993,
            user: saved.address,
            password: saved.appPassword
        )
    )
}

enum MailSubscriptionDriverError: LocalizedError {
    case invalidAddress
    case emptyAppPassword
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "Enter the address for your Google mail account."
        case .emptyAppPassword:
            return "Enter a Google app password."
        case let .connectionFailed(message):
            return message
        }
    }
}

@MainActor
@Observable
final class MailSubscriptionDriver {
    typealias MailboxConnector = (MailCredentials) async throws -> any MailboxProtocol

    nonisolated static let refreshThrottle: TimeInterval = 5 * 60
    nonisolated static let defaultBatchLimit = 5

    private(set) var state = SubscriptionUpdateState()
    private(set) var isConnected = false
    private(set) var isRefreshing = false
    private(set) var hasMoreWaiting = false
    private(set) var errorMessage: String?

    var updates: [SubscriptionUpdate] { state.updates }
    var decisions: [SubscriptionDecision] { state.decisions }
    var unverifiedCount: UInt64 { state.counts.unverified }
    var since: Date? { state.since }

    /// Records Save or Not for me. The write lands before `state` changes, so a
    /// failed save leaves the card in the deck.
    func recordDecision(_ action: SubscriptionDecision.Action, workID: UInt64) throws {
        let previous = state
        var next = state
        next.decisions.removeAll { $0.workID == workID }
        next.decisions.append(SubscriptionDecision(workID: workID, action: action))
        next = next.capped()
        do {
            try store.saveState(next)
            state = next
        } catch {
            state = previous
            errorMessage = Self.message(for: error)
            throw error
        }
    }

    private let credentialsVault: any MailCredentialsPersisting
    private let store: any SubscriptionUpdateStoring
    private let connector: MailboxConnector
    private let now: () -> Date
    private let batchLimit: Int

    init(
        credentialsVault: any MailCredentialsPersisting = KeychainMailCredentialsVault(),
        store: any SubscriptionUpdateStoring = FileSubscriptionUpdateStore(),
        connector: MailboxConnector? = nil,
        now: @escaping () -> Date = Date.init,
        batchLimit: Int = defaultBatchLimit
    ) {
        self.credentialsVault = credentialsVault
        self.store = store
        self.connector = connector ?? connectGmailMailbox
        self.now = now
        self.batchLimit = max(1, batchLimit)

        do {
            state = try store.loadState().capped()
        } catch {
            errorMessage = Self.message(for: error)
        }
        do {
            isConnected = try credentialsVault.load() != nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func connect(address rawAddress: String, appPassword rawPassword: String) async throws {
        let address = rawAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.contains("@"), !address.contains(where: \.isWhitespace) else {
            throw MailSubscriptionDriverError.invalidAddress
        }
        let password = rawPassword.filter { !$0.isWhitespace }
        guard !password.isEmpty else { throw MailSubscriptionDriverError.emptyAppPassword }
        guard !isRefreshing else { return }

        let previousState = state
        let previousCursor = try store.loadCursor()
        let credentials = MailCredentials(address: address, appPassword: password)
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }

        do {
            try await synchronize(using: credentials)
            // The IMAP await finishes even after the sheet's Cancel, so check
            // before saving: a cancelled connect must not store the password.
            try Task.checkCancellation()
            try credentialsVault.save(credentials)
            isConnected = true
        } catch {
            // Cursor first: if it can't be put back, keep the rows that match it
            // rather than leave a cursor ahead of its rows (those UIDs would be lost).
            if (try? store.saveCursor(previousCursor)) != nil,
               (try? store.saveState(previousState)) != nil {
                state = previousState
            }
            if error is CancellationError { throw error }
            let message = Self.message(for: error)
            errorMessage = message
            throw MailSubscriptionDriverError.connectionFailed(message)
        }
    }

    func disconnect() throws {
        var firstError: Error?
        var deletedCredentials = false
        var deletedUpdates = false

        do {
            try credentialsVault.delete()
            deletedCredentials = true
        } catch {
            firstError = error
        }
        do {
            try store.delete()
            deletedUpdates = true
        } catch {
            if firstError == nil { firstError = error }
        }

        if deletedCredentials { isConnected = false }
        if deletedUpdates {
            state = .init()
            hasMoreWaiting = false
        }
        if let firstError {
            errorMessage = Self.message(for: firstError)
            throw firstError
        }
        errorMessage = nil
    }

    func refreshIfNeeded() async {
        guard isConnected else { return }
        if let lastRefreshAt = state.lastRefreshAt,
           now().timeIntervalSince(lastRefreshAt) < Self.refreshThrottle {
            return
        }
        await refresh()
    }

    func refresh() async {
        guard isConnected, !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }

        do {
            guard let credentials = try credentialsVault.load() else {
                isConnected = false
                return
            }
            try await synchronize(using: credentials)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private func synchronize(using credentials: MailCredentials) async throws {
        try await withMailbox(credentials) { mailbox in
            var cursor = try store.loadCursor()
            var moreWaiting = true
            var batches = 0

            while moreWaiting, batches < batchLimit {
                let harvest = try await mailbox.readNew(
                    cursor: cursor.map { Cursor(uidValidity: $0.uidValidity, lastUid: $0.lastUID) },
                    authservId: "mx.google.com"
                )
                let returnedCursor = harvest.cursor.map {
                    MailCursor(uidValidity: $0.uidValidity, lastUID: $0.lastUid)
                }
                var nextState = stateForHarvest(returnedCursor: returnedCursor, currentCursor: cursor)
                let mapped = harvest.readings.compactMap(SubscriptionUpdate.init(reading:))

                nextState.updates = merge(nextState.updates, with: mapped)
                nextState.counts.refused = adding(nextState.counts.refused, harvest.refused)
                nextState.counts.otherAO3Mail = adding(
                    nextState.counts.otherAO3Mail,
                    harvest.otherAo3Mail
                )
                nextState.counts.tooLarge = adding(nextState.counts.tooLarge, harvest.tooLarge)
                nextState.counts.swiftRefused = adding(
                    nextState.counts.swiftRefused,
                    UInt64(harvest.readings.count - mapped.count)
                )
                if nextState.since == nil {
                    nextState.since = mapped.map(\.at).min() ?? now()
                }
                nextState = nextState.capped()

                // If this write fails, the old cursor remains and the same UIDs
                // are safely offered again; merge-by-UID makes that retry idempotent.
                try store.saveState(nextState)
                try store.saveCursor(returnedCursor)
                state = nextState
                cursor = returnedCursor
                moreWaiting = harvest.moreWaiting
                batches += 1

                // The crate cannot resume without UIDVALIDITY, so another read on
                // this connection would only return the same first batch.
                if moreWaiting, returnedCursor == nil { break }
            }

            hasMoreWaiting = moreWaiting
            state.lastRefreshAt = now()
            try store.saveState(state)
        }
    }

    private func withMailbox<T>(
        _ credentials: MailCredentials,
        operation: (any MailboxProtocol) async throws -> T
    ) async throws -> T {
        let mailbox = try await connector(credentials)
        do {
            let result = try await operation(mailbox)
            try? await mailbox.close()
            return result
        } catch {
            try? await mailbox.close()
            throw error
        }
    }

    private func stateForHarvest(
        returnedCursor: MailCursor?,
        currentCursor: MailCursor?
    ) -> SubscriptionUpdateState {
        let generationChanged: Bool
        if let currentCursor {
            generationChanged = returnedCursor?.uidValidity != currentCursor.uidValidity
        } else {
            generationChanged = !state.updates.isEmpty
        }
        // A new mailbox generation replaces the rows. Decisions are about works,
        // not UIDs, so Not for me / Save stay.
        guard generationChanged else { return state }
        return SubscriptionUpdateState(decisions: state.decisions)
    }

    private func merge(
        _ existing: [SubscriptionUpdate],
        with incoming: [SubscriptionUpdate]
    ) -> [SubscriptionUpdate] {
        var byUID = Dictionary(uniqueKeysWithValues: existing.map { ($0.uid, $0) })
        for update in incoming {
            byUID[update.uid] = update
        }
        return Array(byUID.values)
    }

    private func adding(_ left: UInt64, _ right: UInt64) -> UInt64 {
        let (sum, overflow) = left.addingReportingOverflow(right)
        return overflow ? .max : sum
    }

    private static func message(for error: Error) -> String {
        if let mailError = error as? MailError {
            switch mailError {
            case .Connect: return "Kudos couldn't reach Gmail. Check your connection and try again."
            case .BadHost: return "The Gmail server address is invalid."
            case .SignIn: return "Gmail rejected that address or app password."
            case .Protocol: return "Gmail refused a mailbox request. Try again later."
            case .TimedOut: return "Gmail did not respond in time. Try again."
            case .Closed: return "The mail connection closed before the check finished."
            case .Internal: return "Kudos couldn't start the mail connection."
            }
        }
        return error.localizedDescription
    }
}

#endif
