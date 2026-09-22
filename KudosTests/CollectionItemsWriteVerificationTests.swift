import Foundation
import Testing
@testable import Kudos

/// Two findings from the second Sol review, both pure decision seams: which
/// tab the collection-items screen opens on for a given scope, and whether a
/// collection write actually landed. Nothing here signs in or posts.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct CollectionItemsWriteVerificationTests {
    /// The account-wide page defaulted to "awaiting the collection" — the
    /// wrong queue for that page, and the one the tests in the prior commit
    /// (`AO3CollectionItemsScopeTests`) already proved the URL layer gets
    /// right. This is the screen's own starting state, which never asked it.
    @Test func accountWideDefaultsToAwaitingYou() {
        #expect(AO3CollectionItemsView.defaultTab(slug: nil) == .invited)
    }

    /// A single collection's own items page keeps AO3's real default.
    @Test func collectionScopedDefaultsToAwaitingCollection() {
        #expect(AO3CollectionItemsView.defaultTab(slug: "fest") == .unreviewed)
    }

    /// `AO3CollectionActions.collectionWriteVerdict` — the classification
    /// every collection member/item write shares (except
    /// `submitCollectionForm`, which already did this correctly and was the
    /// reference this was brought in line with). Mirrors
    /// `AO3WriteActions.readingsWriteResultRequiresPositiveEvidence`'s shape:
    /// the bug this pins against regressing is a silent 200 with neither
    /// flash reading as success.
    @Test func collectionWriteVerdictRequiresPositiveEvidence() {
        // An explicit success flash.
        #expect(
            AO3AuthService.collectionWriteVerdict(
                status: 200,
                body: "<div class=\"flash notice\">Member was successfully added.</div>",
                fallback: "Couldn't update."
            ) == nil
        )
        // A bare redirect with no rendered flash — the ordinary Rails shape.
        #expect(
            AO3AuthService.collectionWriteVerdict(status: 302, body: "", fallback: "Couldn't update.")
                == nil
        )
        // A recognized error flash always rejects, whatever the status.
        // `.flash.error` is one of the classes `AO3Client.writeErrorMessage`
        // actually selects; a bare `<p class="error">` (this test's first
        // draft) matches none of them — `.error p` wants an `.error`
        // ANCESTOR of a `<p>`, not the `<p>` itself — so it fell through
        // to `.unconfirmed` and this assertion failed for the right reason:
        // the test, not the implementation, was wrong.
        #expect(
            AO3AuthService.collectionWriteVerdict(
                status: 200,
                body: "<div class=\"flash error\">You can't do that.</div>",
                fallback: "Couldn't update."
            ) == .rejected("You can't do that.")
        )
        // The bug: a silent 200 with neither flash must not read as success.
        #expect(
            AO3AuthService.collectionWriteVerdict(
                status: 200, body: "<html><body>Under maintenance</body></html>",
                fallback: "Couldn't update."
            ) == .unconfirmed
        )
        // Outside 2xx/3xx entirely: a real rejection, using the fallback.
        #expect(
            AO3AuthService.collectionWriteVerdict(status: 500, body: "", fallback: "Couldn't update.")
                == .rejected("Couldn't update.")
        )
    }
}
}
