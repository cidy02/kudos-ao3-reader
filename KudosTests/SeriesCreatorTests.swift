import Foundation
import Testing
@testable import Kudos

/// The gate on artboard 1br's Edit series. A byline is a pseud, so the tempting
/// comparison — displayed name against account name — is wrong in both
/// directions, and these pin that.
struct SeriesCreatorTests {
    @Test func matchesTheRegisteredUsernameEvenBehindAPseud() throws {
        let route = try #require(AO3AuthorRoute(username: "mirrorsalt", pseud: "saltandsilver"))
        let series = makeSeries(identities: [AO3AuthorIdentity(route: route)])
        // The byline reads "saltandsilver"; the account is "mirrorsalt".
        #expect(series.creatorNames == ["saltandsilver"])
        #expect(series.isCreator(username: "mirrorsalt"))
    }

    @Test func doesNotMatchAStrangerWhosePseudEqualsYourAccountName() throws {
        let route = try #require(AO3AuthorRoute(username: "someoneelse", pseud: "mirrorsalt"))
        let series = makeSeries(identities: [AO3AuthorIdentity(route: route)])
        #expect(!series.isCreator(username: "mirrorsalt"))
    }

    @Test func isCaseAndWhitespaceInsensitiveOnTheAccountName() throws {
        let route = try #require(AO3AuthorRoute(username: "MirrorSalt"))
        let series = makeSeries(identities: [AO3AuthorIdentity(route: route)])
        #expect(series.isCreator(username: "  mirrorsalt "))
    }

    /// An orphaned work's creator is a real, navigable account with a username —
    /// it just is not a person who can edit. The `.registered` requirement is what
    /// keeps "orphan_account" from unlocking Edit for anyone signed in as it.
    @Test func orphanedCreatorsNeverMatch() throws {
        let route = try #require(AO3AuthorRoute(username: "orphan_account"))
        let identity = AO3AuthorIdentity(route: route)
        #expect(identity.kind == .orphaned)
        #expect(!makeSeries(identities: [identity]).isCreator(username: "orphan_account"))
    }

    @Test func anonymousAndDeletedCreatorsNeverMatch() {
        for kind in [AO3AuthorIdentity.Kind.anonymous, .deleted] {
            let identity = AO3AuthorIdentity.nonNavigable("mirrorsalt", kind: kind)
            #expect(identity.username == nil)
            #expect(!makeSeries(identities: [identity]).isCreator(username: "mirrorsalt"),
                    "\(kind) must not match")
        }
    }

    @Test func signedOutOrEmptyNeverMatches() throws {
        let route = try #require(AO3AuthorRoute(username: "mirrorsalt"))
        let series = makeSeries(identities: [AO3AuthorIdentity(route: route)])
        #expect(!series.isCreator(username: nil))
        #expect(!series.isCreator(username: ""))
        #expect(!series.isCreator(username: "   "))
    }

    @Test func findsTheAccountAmongCoCreators() throws {
        let other = try #require(AO3AuthorRoute(username: "someoneelse"))
        let mine = try #require(AO3AuthorRoute(username: "mirrorsalt", pseud: "saltandsilver"))
        let series = makeSeries(identities: [
            AO3AuthorIdentity(route: other), AO3AuthorIdentity(route: mine)
        ])
        #expect(series.isCreator(username: "mirrorsalt"))
    }

    private func makeSeries(identities: [AO3AuthorIdentity]) -> AO3SeriesSummary {
        AO3SeriesSummary(
            id: 1,
            title: "Water",
            creatorNames: identities.map(\.displayName),
            creatorIdentities: identities,
            fandoms: [],
            summary: "",
            words: 118_600,
            workCount: 3,
            dateUpdated: "",
            isComplete: false,
            url: URL(string: "https://archiveofourown.org/series/1")!
        )
    }
}
