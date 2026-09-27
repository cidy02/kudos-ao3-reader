import Foundation

// Challenge screen models kept apart from AO3ChallengeModels.swift, which
// holds the challenge's own objects and forms.

/// fieldset#match_settings on the gift-exchange form (otwarchive Q9,
/// potential_match_settings/_potential_match_settings_form): the minimum match
/// AO3's matcher needs, per request and per tag type, and whether optional tags
/// count. Posted whole, with the record's id, so a save never clears a box the
/// app did not show. `all` (-1) is AO3's "All".
nonisolated struct AO3PotentialMatchSettings: Hashable, Sendable {
    static let all = -1
    /// AO3's seven tag types, pluralised as the field names are.
    static let tagTypes = [
        "fandoms", "characters", "relationships", "freeforms", "categories", "ratings", "archive_warnings"
    ]
    /// `REQUIRED_MATCH_OPTIONS`; the request count drops 0 ("at least one must match").
    static let requestOptions = [all, 1, 2, 3, 4, 5]
    static let tagOptions = [all, 0, 1, 2, 3, 4, 5]

    var id: String = ""
    var numRequiredPrompts: Int = 1
    var numRequired: [String: Int] = [:]
    var includeOptional: [String: Bool] = [:]

    static func label(_ type: String) -> String {
        switch type {
        case "freeforms": "Additional tags"
        case "archive_warnings": "Warnings"
        default: type.prefix(1).uppercased() + type.dropFirst()
        }
    }

    static func optionTitle(_ value: Int) -> String { value == all ? "All" : String(value) }

    /// The spec's "Match on": the types a match needs at least one of.
    var matchOn: [String] {
        Self.tagTypes.filter { (numRequired[$0] ?? 0) != 0 }
    }
}

/// The four tag types a sign-up prompt edits here (ratings, warnings and
/// categories are AO3 checkboxes the app does not offer).
nonisolated enum AO3PromptTagType: String, CaseIterable, Hashable, Sendable {
    case fandom, character, relationship, freeform

    var plural: String {
        switch self {
        case .fandom: "fandoms"
        case .character: "characters"
        case .relationship: "relationships"
        case .freeform: "additional tags"
        }
    }

    var tags: KeyPath<AO3ChallengePrompt, [String]> {
        switch self {
        case .fandom: \.fandoms
        case .character: \.characters
        case .relationship: \.relationships
        case .freeform: \.freeforms
        }
    }

    var any: KeyPath<AO3ChallengePrompt, Bool> {
        switch self {
        case .fandom: \.anyFandom
        case .character: \.anyCharacter
        case .relationship: \.anyRelationship
        case .freeform: \.anyFreeform
        }
    }
}

/// One row of 1cb's Pinch hits: a defaulted assignment still waiting for a
/// pinch hitter ("open", AO3's Defaulted list) or one a pinch hitter has taken
/// ("claimed", AO3's Pinch Hits list). AO3's maintainer rows carry no posted
/// date or fandom, so neither is drawn.
nonisolated struct AO3PinchHitRow: Hashable, Sendable, Identifiable {
    var number: Int
    var assignment: AO3ChallengeAssignment
    var isOpen: Bool

    var id: String { "\(isOpen ? "open" : "claimed")-\(assignment.id)" }

    /// Open first (the ones a maintainer acts on), numbered in AO3's order.
    static func rows(open: [AO3ChallengeAssignment], claimed: [AO3ChallengeAssignment]) -> [AO3PinchHitRow] {
        (open.map { ($0, true) } + claimed.map { ($0, false) }).enumerated().map { index, pair in
            AO3PinchHitRow(number: index + 1, assignment: pair.0, isOpen: pair.1)
        }
    }

    func detail(dueText: String?) -> String {
        let recipient = assignment.requestPseud.isEmpty ? "an anonymous sign-up" : assignment.requestPseud
        guard !isOpen else { return "Requested by \(recipient)" }
        let hitter = assignment.pinchHitterPseud.isEmpty ? assignment.offerPseud : assignment.pinchHitterPseud
        return (["Claimed by \(hitter) for \(recipient)"] + [dueText.map { "due \($0)" }].compactMap { $0 })
            .joined(separator: " · ")
    }
}

/// Rows behind a "Load more" button (1bz). A page counts only once it has loaded,
/// so a failed page leaves `rows` and `loadedPages` alone: Load more stays and
/// retries that page rather than skipping it.
nonisolated struct AO3LoadMorePages<Row: Sendable>: Sendable {
    private(set) var rows: [Row] = []
    private(set) var loadedPages = 0
    private(set) var totalPages = 1

    var hasMore: Bool { loadedPages < totalPages }

    mutating func loadNext(_ fetch: (Int) async throws -> (rows: [Row], totalPages: Int)) async throws {
        let page = loadedPages + 1
        let result = try await fetch(page)
        rows += result.rows
        loadedPages = page
        totalPages = result.totalPages
    }
}
