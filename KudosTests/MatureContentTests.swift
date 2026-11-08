import Foundation
import Testing
@testable import Kudos

struct MatureContentTests {
    @Test func ratingAdultnessFailsClosedAndNormalizesCaseAndWhitespace() {
        let cases: [(rating: String?, isAdult: Bool)] = [
            ("General Audiences", false),
            ("  GENERAL   AUDIENCES\n", false),
            ("Teen And Up Audiences", false),
            ("\tteen and up audiences  ", false),
            ("Mature", true),
            (" explicit ", true),
            ("Not Rated", true),
            (nil, true),
            ("", true),
            (" \n\t ", true),
            ("Everyone", true)
        ]

        for testCase in cases {
            #expect(MatureContentRating.isAdult(testCase.rating) == testCase.isAdult)
        }
    }

    @MainActor
    @Test func savedAndRemoteWorksUseTheSharedRatingDecision() {
        let ratings = [
            "General Audiences", "Teen And Up Audiences", "Mature", "Explicit", "Not Rated", ""
        ]
        for rating in ratings {
            let saved = SavedWork(title: "Local", author: "Writer")
            saved.rating = rating
            var remote = AO3WorkSummary.subscription(id: 1, title: "Remote", authors: ["Writer"])
            remote.rating = rating

            #expect(saved.isAdult == MatureContentRating.isAdult(rating))
            #expect(remote.isAdult == saved.isAdult)
        }
    }

    @MainActor
    @Test func remoteHideDecisionPreservesDisabledBlurAndHideSemantics() {
        var remote = AO3WorkSummary.subscription(id: 1, title: "Remote", authors: ["Writer"])
        remote.rating = "Mature"
        let gate = PrivacyGate()

        #expect(!gate.isHidden(remote, enabled: false, mode: .hide))
        #expect(!gate.isHidden(remote, enabled: true, mode: .obscure))
        #expect(gate.isHidden(remote, enabled: true, mode: .hide))
    }

    /// Sign-out and a different username both drop `revealAll` and the two id
    /// sets. Repeating the same username does not — that is a session refresh,
    /// not an account change.
    @MainActor
    @Test func signOutAndAccountChangeClearBothRevealSets() {
        withoutBiometricGate {
            let gate = PrivacyGate()
            gate.noteSignedInAccount("alice")
            let local = SavedWork(title: "Local", author: "Writer")
            var remote = AO3WorkSummary.subscription(id: 42, title: "Remote", authors: ["Writer"])
            remote.rating = "Explicit"
            let onlyViaRevealAll = SavedWork(title: "Only via reveal all", author: "Writer")

            gate.reveal(local)
            gate.reveal(remote)
            gate.toggleRevealAll()
            #expect(gate.revealAll)
            #expect(gate.revealedIDs.contains(local.id))
            #expect(gate.isRevealed(local))
            #expect(gate.isRevealed(remote))
            #expect(gate.isRevealed(onlyViaRevealAll))

            gate.noteSignedInAccount("alice")
            #expect(gate.revealAll)
            #expect(gate.isRevealed(local))
            #expect(gate.isRevealed(remote))

            gate.noteSignedInAccount(nil)
            #expect(!gate.revealAll)
            #expect(gate.revealedIDs.isEmpty)
            #expect(!gate.isRevealed(local))
            #expect(!gate.isRevealed(remote))
            #expect(!gate.isRevealed(onlyViaRevealAll))

            gate.noteSignedInAccount("alice")
            gate.reveal(local)
            gate.reveal(remote)
            gate.toggleRevealAll()
            gate.noteSignedInAccount("bob")
            #expect(!gate.revealAll)
            #expect(gate.revealedIDs.isEmpty)
            #expect(!gate.isRevealed(local))
            #expect(!gate.isRevealed(remote))
        }
    }

    /// Reveal-all, then the same control again, returns both works to hidden
    /// and still allows a later single-work reveal.
    @MainActor
    @Test func revealAllThenRehideClearsLocalAndRemoteReveals() {
        withoutBiometricGate {
            let gate = PrivacyGate()
            let local = SavedWork(title: "Local", author: "Writer")
            var remote = AO3WorkSummary.subscription(id: 7, title: "Remote", authors: ["Writer"])
            remote.rating = "Mature"
            local.rating = "Mature"

            gate.reveal(local)
            gate.reveal(remote)
            gate.toggleRevealAll()
            #expect(gate.revealAll)
            #expect(gate.isRevealed(local))
            #expect(gate.isRevealed(remote))

            gate.toggleRevealAll()
            #expect(!gate.revealAll)
            #expect(gate.revealedIDs.isEmpty)
            #expect(!gate.isRevealed(local))
            #expect(!gate.isRevealed(remote))
            #expect(gate.isHidden(local, enabled: true, mode: .hide))
            #expect(gate.isHidden(remote, enabled: true, mode: .hide))

            gate.reveal(local)
            #expect(gate.isRevealed(local))
            #expect(!gate.isRevealed(remote))
            #expect(!gate.revealAll)
        }
    }
}

/// `PrivacyGate.reveal` consults this UserDefaults flag and would otherwise
/// present a system auth prompt. Tests force it off and put the previous value back.
@MainActor
private func withoutBiometricGate(_ body: () -> Void) {
    let key = "requireBiometricToReveal"
    let previous = UserDefaults.standard.object(forKey: key)
    UserDefaults.standard.set(false, forKey: key)
    defer {
        if let previous {
            UserDefaults.standard.set(previous, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
    body()
}
