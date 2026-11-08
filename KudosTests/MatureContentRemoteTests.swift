import Foundation
import Testing
@testable import Kudos

@MainActor
@Suite("MatureContentRemoteTests", .serialized)
struct MatureContentRemoteTests {
    private func makeSummary(
        id: Int = 1,
        rating: String = "General Audiences",
        summary: String = ""
    ) -> AO3WorkSummary {
        AO3WorkSummary(
            id: id,
            title: "Test Work",
            authors: ["Author"],
            authorIdentities: [],
            fandoms: ["Fandom"],
            rating: rating,
            warnings: [],
            categories: [],
            isComplete: true,
            dateUpdated: "2026-01-01",
            tags: [],
            summary: summary,
            language: "English",
            words: 1000,
            chapters: "1/1",
            comments: 10,
            kudos: 20,
            hits: 100,
            seriesTitle: nil,
            seriesURL: nil,
            seriesPosition: nil
        )
    }

    @Test func adultRatingClassification() {
        #expect(makeSummary(rating: "Explicit").isAdult)
        #expect(makeSummary(rating: "Mature").isAdult)
        #expect(!makeSummary(rating: "Teen And Up Audiences").isAdult)
        #expect(!makeSummary(rating: "General Audiences").isAdult)
        // AO3 flags Not Rated adult (otwarchive ensure_required_tags.rb).
        #expect(makeSummary(rating: "Not Rated").isAdult)
        #expect(!makeSummary(rating: "").isAdult)
    }

    @Test func remoteRevealStateTransitions() {
        let defaults = UserDefaults.standard
        let previousBiometricSetting = defaults.object(forKey: "requireBiometricToReveal")
        defaults.set(false, forKey: "requireBiometricToReveal")
        defer {
            if let previousBiometricSetting {
                defaults.set(previousBiometricSetting, forKey: "requireBiometricToReveal")
            } else {
                defaults.removeObject(forKey: "requireBiometricToReveal")
            }
        }

        let gate = PrivacyGate()
        let explicit = makeSummary(id: 42, rating: "Explicit")
        let mature = makeSummary(id: 43, rating: "Mature")
        let savedTwin = SavedWork(
            title: "Saved twin",
            author: "Author",
            sourceURL: "https://archiveofourown.org/works/42"
        )
        savedTwin.rating = "Explicit"

        #expect(!gate.isRevealed(explicit))
        #expect(!gate.isRevealed(remoteID: explicit.id))
        #expect(!gate.isRevealed(mature))

        gate.reveal(explicit)
        #expect(gate.isRevealed(explicit))
        #expect(gate.isRevealed(remoteID: 42))
        #expect(gate.isRevealed(savedTwin))
        #expect(!gate.isRevealed(mature))

        gate.reveal(remoteID: 43)
        #expect(gate.isRevealed(mature))

        gate.toggleRevealAll()
        #expect(gate.revealAll)
        let other = makeSummary(id: 99, rating: "Explicit")
        #expect(gate.isRevealed(other))

        gate.toggleRevealAll()
        #expect(!gate.revealAll)
        #expect(!gate.isRevealed(explicit))
        #expect(!gate.isRevealed(savedTwin))
        #expect(!gate.isRevealed(mature))
        #expect(!gate.isRevealed(other))
    }

    @Test func sparseRemoteStaysAnonymousUntilItsRatingIsKnown() {
        let gate = PrivacyGate()
        let sparse = makeSummary(id: 12, rating: "")

        #expect(gate.isPrivacyUndetermined(sparse, enabled: true))
        #expect(gate.isPrivacyUndetermined(makeSummary(rating: "   "), enabled: true))
        #expect(!gate.isPrivacyUndetermined(sparse, enabled: false))
        #expect(!gate.isPrivacyUndetermined(makeSummary(rating: "Not Rated"), enabled: true))
    }

    @Test func undeterminedRatingIsBlurredAndRevealsById() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "requireBiometricToReveal")
        defaults.set(false, forKey: "requireBiometricToReveal")
        defer {
            if let previous {
                defaults.set(previous, forKey: "requireBiometricToReveal")
            } else {
                defaults.removeObject(forKey: "requireBiometricToReveal")
            }
        }
        let gate = PrivacyGate()
        let sparse = makeSummary(id: 77, rating: "")

        // Blurred (so revealable), never omitted, in both modes; never in the clear.
        #expect(gate.isBlurred(sparse, enabled: true, mode: .obscure))
        #expect(gate.isBlurred(sparse, enabled: true, mode: .hide))
        #expect(!gate.isHidden(sparse, enabled: true, mode: .hide))
        #expect(gate.isConcealed(sparse, enabled: true))
        #expect(!gate.isBlurred(sparse, enabled: false, mode: .obscure))

        gate.reveal(remoteID: 77)
        #expect(!gate.isBlurred(sparse, enabled: true, mode: .hide))
        #expect(!gate.isConcealed(sparse, enabled: true))
        // Once enrichment supplies a rating the normal rules apply.
        #expect(!gate.isBlurred(makeSummary(id: 78, rating: "Teen And Up Audiences"), enabled: true, mode: .hide))
    }

    @Test func canonicalEntryIsBlurredWhenOnlyTheRemoteIsAdult() {
        let gate = PrivacyGate()
        let local = SavedWork(
            title: "Local work",
            author: "Author",
            sourceURL: "https://archiveofourown.org/works/31"
        )
        local.rating = ""
        let entry = CanonicalWork(local: local, remote: makeSummary(id: 31, rating: "Explicit"))

        #expect(!gate.isBlurred(local, enabled: true, mode: .obscure))
        #expect(gate.isBlurred(entry, enabled: true, mode: .obscure))
        #expect(gate.isConcealed(entry, enabled: true))
        #expect(gate.isHidden(entry, enabled: true, mode: .hide))

        // A rated, non-adult local twin is not blurred by a sparse remote.
        local.rating = "Teen And Up Audiences"
        let sparse = CanonicalWork(local: local, remote: makeSummary(id: 31, rating: ""))
        #expect(!gate.isBlurred(sparse, enabled: true, mode: .obscure))
    }

    @Test func bulkBarNamesNoConcealedWork() {
        let work = makeSummary(id: 5, rating: "Explicit")
        #expect(OwnWorksBulkBar.displayTitle(work, isConcealed: true) == "Hidden mature work")
        #expect(OwnWorksBulkBar.displayTitle(work, isConcealed: false) == "Test Work")
        #expect(OwnWorksBulkBar.deleteTitle([work], isConcealed: { _ in true }) == "Delete “Hidden mature work”?")
        #expect(!OwnWorksBulkBar.deleteMessage([work, work], isConcealed: { _ in true }).contains("Test Work"))
    }

    @Test func canonicalPrivacyUsesTheLocalTwinBeforeRenderingSparseRemoteData() {
        let gate = PrivacyGate()
        let local = SavedWork(
            title: "Local mature work",
            author: "Author",
            sourceURL: "https://archiveofourown.org/works/12"
        )
        local.rating = "Explicit"
        let entry = CanonicalWork(local: local, remote: makeSummary(id: 12, rating: ""))

        #expect(gate.isBlurred(entry, enabled: true, mode: .obscure))
        #expect(gate.isHidden(entry, enabled: true, mode: .hide))
        #expect(gate.isConcealed(entry, enabled: true))
    }

    @Test func remotePrivacyModeEvaluations() {
        let gate = PrivacyGate()
        let adult = makeSummary(id: 10, rating: "Explicit")
        let teen = makeSummary(id: 20, rating: "Teen And Up Audiences")

        // When disabled
        #expect(!gate.isBlurred(adult, enabled: false, mode: .obscure))
        #expect(!gate.isHidden(adult, enabled: false, mode: .hide))
        #expect(!gate.isConcealed(adult, enabled: false))

        // When enabled, obscure (blur) mode
        #expect(gate.isBlurred(adult, enabled: true, mode: .obscure))
        #expect(!gate.isHidden(adult, enabled: true, mode: .obscure))
        #expect(!gate.isBlurred(teen, enabled: true, mode: .obscure))
        #expect(!gate.isHidden(teen, enabled: true, mode: .obscure))

        // When enabled, hide mode
        #expect(!gate.isBlurred(adult, enabled: true, mode: .hide))
        #expect(gate.isHidden(adult, enabled: true, mode: .hide))
        #expect(!gate.isHidden(teen, enabled: true, mode: .hide))

        // When revealed, neither blurred nor hidden
        gate.reveal(adult)
        #expect(!gate.isBlurred(adult, enabled: true, mode: .obscure))
        #expect(!gate.isHidden(adult, enabled: true, mode: .hide))
        #expect(!gate.isConcealed(adult, enabled: true))
    }

    @Test func workRowExpandableCriteria() {
        let longSummary = String(repeating: "Summary text exceeding the one hundred and twenty character limit. ", count: 3)
        let withSummary = makeSummary(summary: longSummary)
        let shortSummary = makeSummary(summary: "A brief summary")
        let withoutSummary = makeSummary(summary: "")

        #expect(AO3WorkRow.isExpandable(for: withSummary, bookmark: nil, showsSummary: true))
        #expect(!AO3WorkRow.isExpandable(for: withSummary, bookmark: nil, showsSummary: false))
        #expect(!AO3WorkRow.isExpandable(for: shortSummary, bookmark: nil, showsSummary: true))
        #expect(!AO3WorkRow.isExpandable(for: withoutSummary, bookmark: nil, showsSummary: true))
        #expect(!AO3WorkRow.isExpandable(for: withoutSummary, bookmark: nil, showsSummary: false))

        var duplicateOnlyTag = withoutSummary
        duplicateOnlyTag.tags = [" fandom "]
        #expect(!AO3WorkRow.isExpandable(for: duplicateOnlyTag, bookmark: nil, showsSummary: false))

        var crossoverWork = withoutSummary
        crossoverWork.fandoms = ["Fandom 1", "Fandom 2"]
        let crossoverBookmark = AO3AuthorBookmark(
            id: 1,
            work: crossoverWork,
            notes: AO3RichText(),
            tags: [],
            collections: [],
            isRecommendation: false,
            isPrivate: false,
            date: "2026-01-01"
        )
        #expect(AO3WorkRow.isExpandable(for: crossoverWork, bookmark: crossoverBookmark, showsSummary: false))

        let singleFandomBookmark = AO3AuthorBookmark(
            id: 2,
            work: withoutSummary,
            notes: AO3RichText(),
            tags: [],
            collections: [],
            isRecommendation: false,
            isPrivate: false,
            date: "2026-01-01"
        )
        #expect(!AO3WorkRow.isExpandable(for: withoutSummary, bookmark: singleFandomBookmark, showsSummary: false))
    }
}
