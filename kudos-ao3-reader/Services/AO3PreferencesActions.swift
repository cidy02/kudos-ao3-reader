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
        // Do not claim success without a positive signal — a bare 200 can be a
        // login page or a soft failure without an error list.
        if let notice = Self.flashNotice(in: responseBody) {
            return notice
        }
        if responseBody.localizedCaseInsensitiveContains("successfully updated") {
            return "Your preferences were successfully updated."
        }
        if (300 ... 399).contains(status) {
            // Redirect away from the form (URLSession may surface this before follow).
            return "Preferences updated."
        }
        throw AO3WriteError.rejected(
            "AO3 didn't confirm the preference changes. Try again."
        )
    }

    /// AO3 flash notice (`.flash.notice`) when present after save.
    private static func flashNotice(in html: String) -> String? {
        guard let doc = try? SwiftSoup.parse(html) else { return nil }
        // Prefer the success flash only — `.notice` alone can match unrelated copy.
        let text = try? doc.select(".flash.notice, #main .flash.notice").first()?.text()
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
