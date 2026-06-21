import Foundation

/// Canonical external links for the project. Centralized so the welcome screen,
/// bug reporter, and About page can't drift to different URLs.
enum AppLinks {
    /// The public GitHub repository.
    static let repository = "https://github.com/cidy02/kudos-ao3-reader"

    /// The repository's issues list.
    static let issues = repository + "/issues"

    /// A prefilled "new issue" URL the user can review and submit themselves.
    /// Nothing is posted automatically — GitHub opens the compose page with this
    /// title/body, which the user edits and submits.
    static func newIssue(title: String, body: String) -> URL? {
        var components = URLComponents(string: repository + "/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "body", value: body)
        ]
        return components?.url
    }
}
