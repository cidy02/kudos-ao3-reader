import Testing
@testable import Kudos

struct AO3InvitationRequestTests {
    @Test func createAccountUsesAO3InvitationRequest() {
        #expect(
            AO3InvitationRequest.url.absoluteString
                == "https://archiveofourown.org/invite_requests"
        )
    }
}
