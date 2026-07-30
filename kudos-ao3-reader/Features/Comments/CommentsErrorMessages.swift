import Foundation

/// Error classification and user-facing messages for the Comments screens.
///
/// Extracted verbatim from `CommentsModel` so its class body fits the
/// `type_body_length` limit (it was three lines over, which SwiftLint reports as
/// an *error*, so `Scripts/verify.sh` could not pass). Pure code movement: no
/// behavior change, no signature change, and `isOfflineError` deliberately stayed
/// behind because it is `private` and called from within that file.
extension CommentsModel {
    /// True when the POST may have reached AO3 even though no confirmation came
    /// back — the only situations where a duplicate is possible and verification
    /// (not retry) must decide. Two shapes: the response never arrived (timeout /
    /// dropped connection), or a final-200 page arrived carrying neither a
    /// recognized error flash nor a recognized success flash
    /// (`AO3WriteError.unconfirmed` — maintenance page, interstitial; CAA-2).
    static func isAmbiguousSubmitError(_ error: Error) -> Bool {
        if case AO3WriteError.unconfirmed = error { return true }
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .networkConnectionLost:
            return true
        default:
            return false
        }
    }

    /// The banner text for an ambiguous submit, honest about which of the two
    /// ambiguity shapes happened.
    static func ambiguousSubmitMessage(for error: Error) -> String {
        if case AO3WriteError.unconfirmed = error {
            return "AO3 answered but didn't confirm the comment posted. "
                + "Checking whether it went through…"
        }
        return "The connection dropped while posting. Checking whether the comment went through…"
    }

    static func message(for error: Error) -> String {
        switch error {
        case AO3Error.rateLimited:
            return "AO3 is asking for a pause. Please try again in a moment."
        case AO3Error.authenticationRequired, AO3WriteError.notSignedIn:
            return "Log in to AO3 to do that."
        case let AO3WriteError.rejected(reason):
            return reason
        case AO3Error.notFound:
            return "AO3 couldn't find these comments — the work may be hidden or deleted."
        case AO3Error.forbidden:
            return "AO3 declined the request. The work may be restricted to logged-in users."
        case let error as URLError where error.code == .notConnectedToInternet:
            return "You're offline. Comments will load when you're back online."
        default:
            return (error as? LocalizedError)?.errorDescription
                ?? "Something went wrong talking to AO3."
        }
    }
}
