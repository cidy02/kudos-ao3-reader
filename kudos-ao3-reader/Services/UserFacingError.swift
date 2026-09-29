import Foundation

/// The one sentence an AO3-facing screen shows for an error.
///
/// `error.localizedDescription` on a transport failure is Foundation's own
/// "The operation couldn't be completed. (NSURLErrorDomain error -1009.)" —
/// what Browse printed offline (LOOP-v3). Connection failures get a plain
/// sentence here; AO3's own errors keep their messages; anything else falls
/// back to its description.
enum UserFacingError {
    static func message(for error: Error) -> String {
        if let urlError = error as? URLError {
            return message(for: urlError.code)
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return message(for: URLError.Code(rawValue: nsError.code))
        }
        if let ao3 = error as? AO3Error {
            // `.network` carries Foundation's raw transport text.
            if case .network = ao3 { return unreachable }
            return ao3.errorDescription ?? fallback
        }
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    static func message(for code: URLError.Code) -> String {
        switch code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
            "You're offline. Connect to the internet and try again."
        case .timedOut:
            "AO3 took too long to answer. Try again."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .networkConnectionLost:
            unreachable
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected:
            "Couldn't make a secure connection to AO3."
        case .cancelled:
            "The request was cancelled."
        default:
            fallback
        }
    }

    private static let unreachable = "Couldn't reach AO3. Check your connection and try again."
    private static let fallback = "Something went wrong talking to AO3. Try again."
}
