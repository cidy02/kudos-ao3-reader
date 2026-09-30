import Foundation
import Testing
@testable import Kudos

/// A screen never prints Foundation's "(NSURLErrorDomain error -1009.)".
struct UserFacingErrorTests {
    @Test func transportFailuresReadAsSentences() {
        #expect(UserFacingError.message(for: URLError(.notConnectedToInternet))
            == "You're offline. Connect to the internet and try again.")
        #expect(UserFacingError.message(for: URLError(.timedOut)) == "AO3 took too long to answer. Try again.")
        let bridged = NSError(domain: NSURLErrorDomain, code: URLError.Code.cannotFindHost.rawValue)
        #expect(UserFacingError.message(for: bridged) == "Couldn't reach AO3. Check your connection and try again.")
        #expect(!UserFacingError.message(for: AO3Error.network("NSURLErrorDomain -1009")).contains("NSURLErrorDomain"))
    }

    @Test func ao3AndLocalErrorsKeepTheirOwnWords() {
        #expect(UserFacingError.message(for: AO3Error.notFound) == AO3Error.notFound.errorDescription)
        struct Local: LocalizedError { var errorDescription: String? { "The file is damaged." } }
        #expect(UserFacingError.message(for: Local()) == "The file is damaged.")
    }

    @Test func onlyConnectionFailuresUseTheOfflineSymbol() {
        #expect(UserFacingError.systemImage(for: URLError(.notConnectedToInternet)) == "wifi.slash")
        #expect(UserFacingError.systemImage(for: URLError(.cannotFindHost)) == "wifi.slash")
        #expect(UserFacingError.systemImage(for: AO3Error.network("transport")) == "wifi.slash")
        #expect(UserFacingError.systemImage(for: URLError(.timedOut)) == "exclamationmark.triangle")
        #expect(UserFacingError.systemImage(for: AO3Error.notFound) == "exclamationmark.triangle")
    }
}
