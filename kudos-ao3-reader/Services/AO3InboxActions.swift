import Foundation

/// Native writes for AO3's Inbox mass-edit form. The form itself is scraped from
/// the page just displayed, including its CSRF token, Rails method override,
/// checkbox values, and submit field names; this extension never reconstructs
/// those details or retries a write.
extension AO3AuthService {

    /// Submits one of AO3's exact Inbox mass-edit actions for the selected rows.
    /// The write is deliberately a single `submitWrite` call; after success the
    /// caller invalidates and reloads its cached Inbox page.
    @discardableResult
    func performInboxBulkAction(
        _ action: AO3InboxBulkAction,
        form: AO3InboxBulkForm,
        items: [AO3InboxItem],
        referer: URL
    ) async throws -> String {
        guard isLoggedIn else { throw AO3WriteError.notSignedIn }
        guard form.htmlMethod == "post" else {
            throw AO3WriteError.rejected("AO3's Inbox form no longer supports this native action.")
        }
        guard let parameters = form.parameters(for: items, action: action) else {
            throw AO3WriteError.rejected("Couldn't prepare AO3's Inbox action. Reload and try again.")
        }

        let request = try writeRequest(
            to: form.actionURL,
            body: Self.formEncoded(parameters),
            csrf: form.csrfToken,
            referer: referer,
            ajax: false
        )
        let (status, responseBody) = try await AO3Client.shared.submitWrite(request)
        // otwarchive's inbox update redirects with `flash[:notice]` on success and
        // sets `flash[:caution]` on its failure branch (`inbox_controller.rb`), so
        // the shared verdict reads both honestly; a page with neither is
        // `unconfirmed`, not success (CAA-2).
        return try commentWriteResult(
            status: status, body: responseBody,
            onSuccess: action.successMessage,
            rejectionFallback: "AO3 couldn't update your Inbox."
        )
    }
}
