import Foundation
import SwiftData

/// One unfamiliar work the New to you deck can offer. The headline is only what
/// the subscription URL established. `claimedTitle` is the preface's title, shown
/// as a claim, never as the headline.
struct NewToYouCard: Equatable, Identifiable, Sendable {
    let workID: UInt64
    let headline: String
    let claimedTitle: String?
    let summary: AO3WorkSummary

    var id: Int { summary.id }

    /// The preface title, quoted and attributed. Nil when the preface had no title.
    var attribution: String? {
        guard let claimedTitle, !claimedTitle.isEmpty else { return nil }
        return "AO3's notification names \u{201C}\(claimedTitle)\u{201D}"
    }

    /// What the unsubscribe URL established. Nil for a work subscription or an
    /// unknown footer — those are not New to you cards.
    static func headline(for source: SubscriptionUpdate.Source) -> String? {
        switch source {
        case let .author(login):
            guard !login.isEmpty else { return nil }
            return "New from \(login)"
        case let .series(name):
            guard !name.isEmpty else { return nil }
            return "New in \(name)"
        case .work, .unknown:
            return nil
        }
    }
}

// An extension keeps the memberwise init that NewToYouDeck uses.
extension NewToYouCard {
    /// Fixture and preview cards. Production cards come from `NewToYouDeck`.
    init(preview summary: AO3WorkSummary, source: SubscriptionUpdate.Source) {
        workID = UInt64(max(summary.id, 0))
        headline = Self.headline(for: source) ?? "New from a follow"
        claimedTitle = summary.title.isEmpty ? nil : summary.title
        self.summary = summary
    }
}

/// Which stored updates become New to you cards.
@MainActor
enum NewToYouDeck {
    static func cards(
        from updates: [SubscriptionUpdate],
        library: WorkIdentityIndex,
        decidedWorkIDs: Set<UInt64>
    ) -> [NewToYouCard] {
        var newest: [UInt64: SubscriptionUpdate] = [:]
        for update in updates where isEligible(update, library: library, decidedWorkIDs: decidedWorkIDs) {
            if let current = newest[update.workID] {
                if isNewer(update, than: current) { newest[update.workID] = update }
            } else {
                newest[update.workID] = update
            }
        }
        return newest.values.sorted { isNewer($0, than: $1) }.compactMap(card(from:))
    }

    private static func isEligible(
        _ update: SubscriptionUpdate,
        library: WorkIdentityIndex,
        decidedWorkIDs: Set<UInt64>
    ) -> Bool {
        guard update.change == .newWork else { return false }
        guard NewToYouCard.headline(for: update.source) != nil else { return false }
        guard !decidedWorkIDs.contains(update.workID) else { return false }
        guard !library.containsAO3Work(update.workID) else { return false }
        return true
    }

    private static func isNewer(_ update: SubscriptionUpdate, than other: SubscriptionUpdate) -> Bool {
        if update.at == other.at { return update.uid > other.uid }
        return update.at > other.at
    }

    private static func card(from update: SubscriptionUpdate) -> NewToYouCard? {
        // shortcut: the library and the save path key AO3 works by Int, so a
        // UInt64 that does not fit can neither be matched nor saved.
        guard let headline = NewToYouCard.headline(for: update.source),
              let id = Int(exactly: update.workID) else { return nil }
        var summary = AO3WorkSummary.subscription(
            id: id,
            title: update.workTitle,
            authors: update.author.isEmpty ? [] : [update.author]
        )
        summary.fandoms = update.fandoms
        summary.rating = update.rating ?? ""
        summary.warnings = update.warnings
        summary.relationships = update.relationships
        summary.characters = update.characters
        summary.tags = update.additionalTags
        summary.summary = update.summary ?? ""
        summary.words = update.words.flatMap { Int(exactly: $0) }
        summary.chapters = chaptersText(posted: update.chaptersPosted, total: update.chaptersTotal)
        summary.seriesTitle = update.series
        return NewToYouCard(
            workID: update.workID,
            headline: headline,
            claimedTitle: update.workTitle.isEmpty ? nil : update.workTitle,
            summary: summary
        )
    }

    private static func chaptersText(posted: UInt32?, total: UInt32?) -> String {
        guard let posted else { return "" }
        return "\(posted)/\(total.map(String.init) ?? "?")"
    }
}

/// Save for a New to you card. The download runs before the existing
/// save-for-later path so `AO3Error.maintenance` (and any other download
/// failure) throws before a library row exists.
@MainActor
enum NewToYouLibrary {
    static func save(
        _ summary: AO3WorkSummary,
        in context: ModelContext,
        downloadEPUB: ((Int) async throws -> URL)? = nil
    ) async throws -> SavedWork {
        let download = downloadEPUB ?? { try await AO3Client.shared.downloadEPUB(workID: $0) }
        let file = try await download(summary.id)
        return try await ReadingQueueService.addToSavedForLater(
            summary,
            in: context,
            downloadEPUB: { _ in file }
        )
    }
}
