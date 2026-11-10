import Foundation
import SwiftSoup

/// One row of AO3's works-filter sidebar: a tag, how many of the matching works
/// carry it, and AO3's id for it.
nonisolated struct AO3FacetEntry: Equatable, Hashable, Sendable, Identifiable {
    let name: String
    let count: Int
    let id: Int
}

/// The three include-facet lists the Insights row shows, in AO3's page order.
nonisolated struct AO3SearchFacets: Equatable, Sendable {
    var relationships: [AO3FacetEntry] = []
    var characters: [AO3FacetEntry] = []
    var freeforms: [AO3FacetEntry] = []

    var isEmpty: Bool { relationships.isEmpty && characters.isEmpty && freeforms.isEmpty }

    enum Kind: CaseIterable, Sendable {
        case relationships, characters, freeforms

        /// The `<tag_type>` in `dd#include_<tag_type>_tags`.
        var tagType: String {
            switch self {
            case .relationships: "relationship"
            case .characters: "character"
            case .freeforms: "freeform"
            }
        }

        var title: String {
            switch self {
            case .relationships: "Relationships"
            case .characters: "Characters"
            case .freeforms: "Tags"
            }
        }
    }

    func entries(_ kind: Kind) -> [AO3FacetEntry] {
        switch kind {
        case .relationships: relationships
        case .characters: characters
        case .freeforms: freeforms
        }
    }
}

extension AO3Client {
    /// The include lists of `works/_filters.html.erb` (otwcode/otwarchive 452391b6),
    /// which the works index renders when it has `@facets`. No sidebar, no facets.
    static func parseFacets(in doc: Document) -> AO3SearchFacets {
        func entries(_ kind: AO3SearchFacets.Kind) -> [AO3FacetEntry] {
            let items = (try? doc.select("dd#include_\(kind.tagType)_tags li label").array()) ?? []
            return items.compactMap { label in
                guard let text = try? label.text(),
                      let parsed = parseFacetLabel(text),
                      let value = try? label.select("input[value]").first()?.attr("value"),
                      let id = Int(value) else { return nil }
                return AO3FacetEntry(name: parsed.name, count: parsed.count, id: id)
            }
        }
        return AO3SearchFacets(
            relationships: entries(.relationships),
            characters: entries(.characters),
            freeforms: entries(.freeforms)
        )
    }

    /// `label_for_filter` writes `name + " (#{count})"`, and a tag name can itself
    /// end in brackets ("Doctor Who (2005)"), so only the final ` (digits)` is the count.
    static func parseFacetLabel(_ text: String) -> (name: String, count: Int)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: #" \((\d+)\)$"#, options: .regularExpression),
              let count = Int(trimmed[range].filter(\.isNumber)) else { return nil }
        let name = trimmed[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : (name, count)
    }
}

extension AO3SearchFilters {
    /// A tapped Insights chip as the include filter the Filters sheet would set:
    /// AO3 matches these by tag name, comma-separated.
    func including(_ entry: AO3FacetEntry, as kind: AO3SearchFacets.Kind) -> AO3SearchFilters {
        var copy = self
        let keyPath: WritableKeyPath<AO3SearchFilters, String> = switch kind {
        case .relationships: \.relationships
        case .characters: \.characters
        case .freeforms: \.additionalTags
        }
        let existing = copy[keyPath: keyPath].split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !existing.contains(where: { $0.caseInsensitiveCompare(entry.name) == .orderedSame }) else {
            return self
        }
        copy[keyPath: keyPath] = (existing + [entry.name]).joined(separator: ", ")
        return copy
    }
}

/// "14.2k" for a chip (truncated, not rounded); the exact figure stays in the accessibility label.
nonisolated enum InsightsCountFormat {
    static func short(_ count: Int) -> String {
        func scaled(_ unit: Int, _ suffix: String) -> String {
            let tenths = count / (unit / 10)
            return tenths % 10 == 0 ? "\(tenths / 10)\(suffix)" : "\(tenths / 10).\(tenths % 10)\(suffix)"
        }
        if count >= 1_000_000 { return scaled(1_000_000, "M") }
        return count >= 1000 ? scaled(1000, "k") : String(count)
    }
}
