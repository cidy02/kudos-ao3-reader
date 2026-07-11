import Foundation

/// Persists the user's non-secret "Posting As" preference independently for
/// each AO3 account. Cookie/session refreshes therefore cannot erase the choice,
/// and switching accounts cannot expose or reuse another account's pseud.
protocol AO3PostingPseudPersisting {
    func pseudName(for username: String) -> String?
    func setPseudName(_ pseudName: String?, for username: String)
}

struct UserDefaultsAO3PostingPseudStore: AO3PostingPseudPersisting {
    private static let key = "ao3PostingPseudByUsername"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func pseudName(for username: String) -> String? {
        values[normalized(username)]
    }

    func setPseudName(_ pseudName: String?, for username: String) {
        let username = normalized(username)
        guard !username.isEmpty else { return }
        var next = values
        if let pseudName {
            let trimmed = pseudName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                next.removeValue(forKey: username)
            } else {
                next[username] = trimmed
            }
        } else {
            next.removeValue(forKey: username)
        }
        defaults.set(next, forKey: Self.key)
    }

    private var values: [String: String] {
        defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
    }

    private func normalized(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
