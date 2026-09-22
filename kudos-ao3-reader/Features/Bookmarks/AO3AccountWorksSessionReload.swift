import Foundation

/// What restarts the account-list load.
///
/// `isLoggedIn` alone treats every signed-in account as the same account.
/// `sessionGeneration` changes when the session does, including a login that
/// starts while another account is still signed in, and including
/// `verifySession`, which stays signed in the whole time.
///
/// The flag stays in the id as well. `AO3AuthService.accept` bumps the
/// generation while status is still `.signingIn`. `finishAccepting` is what
/// sets `.signedIn`, and it does not bump again. A task that watched only the
/// generation would run during sign-in, see a signed-out flag, and never run
/// again when that flag became true.
struct AO3AccountWorksLoadID: Equatable, Sendable {
    var sessionGeneration: Int
    var isLoggedIn: Bool
}

/// Whether the rows on screen belong to this generation, and what is left
/// when they do not.
enum AO3AccountWorksSessionReload {
    /// Loaded account rows, emptied. Device watermarks are not here. They
    /// record "last looked", not the account's list, and a launch restore
    /// bumps the generation too. The write flags go false here. A finish
    /// from the generation that just ended must not set them again:
    /// `shouldApplyCapturedGeneration` is that guard.
    struct ClearedAccount: Equatable {
        var works: [AO3WorkSummary] = []
        var currentPage = 1
        var totalPages = 1
        var readingEntries: [Int: AO3ReadingEntry] = [:]
        var bookmarkDetails: [Int: AO3AuthorBookmark] = [:]
        var unsubscribePaths: [Int: String] = [:]
        var enrichedSubscriptionSummaries: [Int: AO3WorkSummary] = [:]
        var markedForLaterSeenThisVisit: [Int: AO3WorkSummary] = [:]
        var lastSyncedAt: Date?
        var confirmClearHistory = false
        var historyWriteError: String?
        var historyWriteInFlight = false
        var subscriptionWriteError: String?
        var subscriptionWriteInFlight = false
    }

    static let cleared = ClearedAccount()

    /// True when `sessionGeneration` is not the one these rows were loaded
    /// for. Nil is the first run. An equal generation is a reappearance, or
    /// the signed-in flag catching up after `accept`'s bump, and must not
    /// drop a page that is already on screen.
    static func shouldClear(boundGeneration: Int?, sessionGeneration: Int) -> Bool {
        boundGeneration != sessionGeneration
    }

    /// Whether a write or a page enrichment that started under
    /// `capturedGeneration` may still change this screen.
    ///
    /// The in-flight flag, the write error, the removed row, and a
    /// subscription chapter count all belong to that generation.
    /// `clearLoadedAccount` runs when the generation changes and sets the
    /// flag false before the next account can start a write. A stale finish
    /// must not clear the flag or store the error: the new generation's
    /// write may already have set the flag true, and the old failure is not
    /// this account's. The same generation still applies, so a retry on
    /// this account can run once the flag drops.
    static func shouldApplyCapturedGeneration(
        _ capturedGeneration: Int,
        sessionGeneration: Int
    ) -> Bool {
        capturedGeneration == sessionGeneration
    }
}
