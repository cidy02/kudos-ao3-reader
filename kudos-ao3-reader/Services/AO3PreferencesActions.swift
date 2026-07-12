import Foundation
import SwiftSoup

extension AO3AuthService {
    /// Loads the signed-in user's AO3 Preferences form (authenticated GET).
    func loadPreferences() async throws -> AO3PreferencesSnapshot {
        guard isLoggedIn, let username else { throw AO3WriteError.notSignedIn }
        guard let url = AO3Client.preferencesURL(username: username) else {
            throw AO3WriteError.rejected("Couldn't build the preferences URL.")
        }
        let request = try authenticatedRequest(for: url)
        let html = try await AO3Client.shared.authenticatedPageHTML(for: request)
        return try AO3Client.parsePreferencesForm(from: html)
    }

    /// Fetches a public AO3 `/help/…` page and returns its modal content for
    /// in-app display. Help pages are not authenticated.
    func loadPreferenceHelp(_ ref: AO3PreferenceHelpRef) async throws -> AO3PreferenceHelpContent {
        let html = try await AO3Client.shared.getHTML(ref.url)
        return try AO3Client.parseHelpPage(from: html, sourceURL: ref.url)
    }

    /// Saves edited preferences with a single authenticated POST (Rails `_method`
    /// when present). Never retried — same write policy as kudos/comments.
    @discardableResult
    func savePreferences(_ snapshot: AO3PreferencesSnapshot) async throws -> String {
        guard isLoggedIn else { throw AO3WriteError.notSignedIn }

        var params: [(String, String)] = [
            ("authenticity_token", snapshot.csrfToken)
        ]
        if let method = snapshot.httpMethodOverride, !method.isEmpty {
            params.append(("_method", method))
        }
        params.append(contentsOf: snapshot.preferenceParameters())

        let body = Self.formEncoded(params)
        let request = try writeRequest(
            to: snapshot.actionURL,
            body: body,
            csrf: snapshot.csrfToken,
            referer: snapshot.actionURL,
            ajax: false
        )
        let (status, responseBody) = try await AO3Client.shared.submitWrite(request)

        if let error = AO3Client.writeErrorMessage(in: responseBody) {
            throw AO3WriteError.rejected(error)
        }
        // Success is typically a 302 to the user dashboard with a flash notice,
        // or a re-rendered preferences page without error lists.
        if (200 ... 399).contains(status) {
            if let notice = Self.flashNotice(in: responseBody) {
                return notice
            }
            return "Preferences updated."
        }
        throw AO3WriteError.rejected("AO3 didn't accept the preference changes.")
    }

    /// AO3 flash notice (`.flash.notice` / `.notice`) when present after save.
    private static func flashNotice(in html: String) -> String? {
        guard let doc = try? SwiftSoup.parse(html) else { return nil }
        let text = try? doc.select(".flash.notice, .notice, #main .flash").first()?.text()
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
