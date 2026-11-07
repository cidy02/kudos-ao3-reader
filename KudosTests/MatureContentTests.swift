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
}
