import SwiftUI

/// Save Search sheet (`Search-Save` board): context header summarizing the search,
/// editable Name field, and "This search" filter chips before persisting.
struct SaveSearchSheet: View {
    let filters: AO3SearchFilters
    @Binding var name: String
    var totalWorks: Int? = nil
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var chips: [SaveSearchChip] {
        SaveSearchPresentation.chips(for: filters)
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    contextSection
                    nameSection
                    thisSearchSection
                }
                .appThemedRows()
            }
            .formStyle(.grouped)
            .appThemedScroll()
            .modifier(WorksFilterSheetGround())
            .navigationTitle("Save Search")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                    .buttonStyle(.kudosPrimary)
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
        .accentTint(theme.effectiveTint, on: theme.appTheme)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondaryInk)
            .textCase(nil)
    }

    private var contextSection: some View {
        let kicker = SaveSearchPresentation.contextKicker(totalWorks: totalWorks)
        let title = SaveSearchPresentation.contextTitle(for: filters)
        let meta = SaveSearchPresentation.contextMeta(for: filters)
        let spokenParts: [String?] = [kicker, title, meta]
        return Section {
            HStack(alignment: .center, spacing: 12) {
                SettingsIconTile(color: theme.effectiveTint, systemImage: "magnifyingglass")
                VStack(alignment: .leading, spacing: 2) {
                    Text(kicker)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.accentInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let meta {
                        Text(meta)
                            .font(.footnote)
                            .foregroundStyle(.secondaryInk)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 2)
            .combinedAccessibilityRow(spokenParts.compactMap { $0 }.joined(separator: ", "))
        }
    }

    private var nameSection: some View {
        Section {
            TextField("Name", text: $name)
                .font(.body)
                .accessibilityLabel("Search name")
        } header: {
            sectionHeader("Name")
        }
    }

    private var thisSearchSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Filters")
                    .font(.subheadline)
                    .foregroundStyle(.secondaryInk)
                if chips.isEmpty {
                    Text(SaveSearchPresentation.emptyFiltersText)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    FlowLayout(spacing: 6, rowSpacing: 6) {
                        ForEach(chips) { item in
                            SaveSearchSummaryChip(text: item.text, kind: item.kind)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        } header: {
            sectionHeader("This search")
        }
    }
}

// MARK: - Pure presentation helpers (`Search-Save` and `Search-Saved` boards)

struct SaveSearchChip: Identifiable, Equatable {
    enum Kind: Equatable {
        case included
        case excluded
        case facet
    }

    let id: String
    let text: String
    let kind: Kind
}

enum SaveSearchPresentation {
    static let emptyFiltersText = "No filters selected"

    static func contextKicker(totalWorks: Int?) -> String {
        guard let totalWorks else { return "AO3 search" }
        let noun = totalWorks == 1 ? "work" : "works"
        return "AO3 search · \(totalWorks.formatted()) \(noun)"
    }

    static func contextTitle(for filters: AO3SearchFilters) -> String {
        var parts: [String] = []
        let query = filters.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty { parts.append("“\(query)”") }
        for field in [filters.fandom, filters.relationships, filters.characters, filters.additionalTags] {
            parts.append(contentsOf: splitTags(field))
        }
        if !parts.isEmpty {
            return parts.prefix(3).joined(separator: " · ")
        }
        let title = filters.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        let creator = filters.creators.trimmingCharacters(in: .whitespacesAndNewlines)
        if !creator.isEmpty { return "By \(creator)" }
        return "AO3 Search"
    }

    static func contextMeta(for filters: AO3SearchFilters) -> String? {
        var parts = facetDescriptions(for: filters)
        if filters.sort != .relevance {
            parts.append("sorted by \(filters.sort.title.lowercased())")
        }
        guard !parts.isEmpty else { return nil }
        return capitalizeFirst(parts.joined(separator: " · "))
    }

    static func chips(for filters: AO3SearchFilters) -> [SaveSearchChip] {
        var items: [SaveSearchChip] = []
        let query = filters.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            items.append(SaveSearchChip(id: "query", text: "“\(query)”", kind: .included))
        }
        appendTagChips(for: filters, to: &items)
        appendFacetChips(for: filters, to: &items)
        if filters.sort != .relevance {
            items.append(SaveSearchChip(id: "sort", text: sortChipText(for: filters), kind: .facet))
        }
        return items
    }

    static func sortChipText(for filters: AO3SearchFilters) -> String {
        guard filters.sort != .relevance else { return filters.sort.title }
        let arrow = filters.sortDirection == .ascending ? "↑" : "↓"
        return "\(filters.sort.title) \(arrow)"
    }

    private static func appendTagChips(for filters: AO3SearchFilters, to items: inout [SaveSearchChip]) {
        let groups: [(String, String, String)] = [
            ("fandom", filters.fandom, filters.excludedFandoms),
            ("rel", filters.relationships, filters.excludedRelationships),
            ("char", filters.characters, filters.excludedCharacters),
            ("tag", filters.additionalTags, filters.excludedAdditionalTags),
        ]
        for (prefix, included, excluded) in groups {
            for tag in splitTags(included) {
                items.append(SaveSearchChip(id: "\(prefix)-\(tag)", text: tag, kind: .included))
            }
            for tag in splitTags(excluded) {
                items.append(SaveSearchChip(id: "\(prefix)-ex-\(tag)", text: tag, kind: .excluded))
            }
        }
    }

    private static func appendFacetChips(for filters: AO3SearchFilters, to items: inout [SaveSearchChip]) {
        let title = filters.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            items.append(SaveSearchChip(id: "title", text: "Title: \(title)", kind: .facet))
        }
        let creators = filters.creators.trimmingCharacters(in: .whitespacesAndNewlines)
        if !creators.isEmpty {
            items.append(SaveSearchChip(id: "creator", text: "Creator: \(creators)", kind: .facet))
        }
        if filters.rating != .any {
            let text = AO3FilterPanel.ratingActiveLabel(rating: filters.rating, match: filters.ratingMatch)
            items.append(SaveSearchChip(id: "rating", text: text, kind: .included))
        }
        if !filters.includeNotRated {
            items.append(SaveSearchChip(id: "noNotRated", text: "No Not Rated", kind: .facet))
        }
        for category in AO3SearchFilters.Category.allCases {
            if filters.categories.contains(category) {
                items.append(SaveSearchChip(id: "cat-\(category.rawValue)", text: category.title, kind: .included))
            } else if filters.excludedCategories.contains(category) {
                items.append(SaveSearchChip(id: "cat-ex-\(category.rawValue)", text: category.title, kind: .excluded))
            }
        }
        for warning in AO3SearchFilters.Warning.allCases {
            let label = AO3FilterPanel.warningChipTitle(warning)
            if filters.warnings.contains(warning) {
                items.append(SaveSearchChip(id: "warn-\(warning.rawValue)", text: label, kind: .included))
            } else if filters.excludedWarnings.contains(warning) {
                items.append(SaveSearchChip(id: "warn-ex-\(warning.rawValue)", text: label, kind: .excluded))
            }
        }
        appendRangeAndStatusChips(for: filters, to: &items)
    }

    private static func appendRangeAndStatusChips(
        for filters: AO3SearchFilters,
        to items: inout [SaveSearchChip]
    ) {
        if filters.crossover != .any {
            items.append(SaveSearchChip(id: "crossover", text: filters.crossover.title, kind: .facet))
        }
        if filters.completion != .any {
            let label = AO3FilterPanel.completionSegmentTitle(filters.completion)
            items.append(SaveSearchChip(id: "completion", text: label, kind: .facet))
        }
        if filters.chapterCount != .any {
            items.append(SaveSearchChip(id: "chapters", text: filters.chapterCount.title, kind: .facet))
        }
        if let words = AO3FilterPanel.wordsActiveLabel(from: filters.wordsFrom, to: filters.wordsTo) {
            items.append(SaveSearchChip(id: "words", text: words, kind: .facet))
        }
        if filters.updated != .any {
            items.append(SaveSearchChip(id: "updated", text: filters.updated.title, kind: .facet))
        }
        if let from = filters.dateFrom {
            let text = "After \(AO3SearchFilters.dateBoundFormatter.string(from: from))"
            items.append(SaveSearchChip(id: "dateFrom", text: text, kind: .facet))
        }
        if let to = filters.dateTo {
            let text = "Before \(AO3SearchFilters.dateBoundFormatter.string(from: to))"
            items.append(SaveSearchChip(id: "dateTo", text: text, kind: .facet))
        }
        if filters.language != .any {
            items.append(SaveSearchChip(id: "language", text: filters.language.title, kind: .facet))
        }
        for (name, from, to) in [
            ("kudos", filters.kudosFrom, filters.kudosTo),
            ("hits", filters.hitsFrom, filters.hitsTo),
            ("comments", filters.commentsFrom, filters.commentsTo),
            ("bookmarks", filters.bookmarksFrom, filters.bookmarksTo),
        ] {
            if let label = AO3FilterPanel.popularityActiveLabel(name: name, from: from, to: to) {
                items.append(SaveSearchChip(id: name, text: label, kind: .facet))
            }
        }
    }

    fileprivate static func facetDescriptions(for filters: AO3SearchFilters) -> [String] {
        var parts: [String] = []
        if filters.rating != .any {
            parts.append(ratingPhrase(rating: filters.rating, match: filters.ratingMatch))
        }
        if !filters.includeNotRated { parts.append("no Not Rated") }
        for category in AO3SearchFilters.Category.allCases where filters.categories.contains(category) {
            parts.append(category.title)
        }
        for warning in AO3SearchFilters.Warning.allCases where filters.warnings.contains(warning) {
            parts.append(AO3FilterPanel.warningChipTitle(warning))
        }
        if filters.crossover != .any { parts.append(filters.crossover.title) }
        if filters.completion == .complete { parts.append("complete only") }
        if filters.completion == .inProgress { parts.append("WIP only") }
        if filters.chapterCount != .any { parts.append(filters.chapterCount.title) }
        if let words = wordsPhrase(from: filters.wordsFrom, to: filters.wordsTo) {
            parts.append(words)
        }
        if filters.updated != .any { parts.append(filters.updated.title) }
        if filters.language != .any { parts.append(filters.language.title) }
        return parts
    }

    fileprivate static func ratingPhrase(
        rating: AO3SearchFilters.Rating,
        match: AO3SearchFilters.RatingMatch
    ) -> String {
        switch match {
        case .exact: rating.title
        case .orHigher: "\(rating.title) and up"
        case .orLower: "\(rating.title) and below"
        }
    }

    fileprivate static func wordsPhrase(from: String, to: String) -> String? {
        let lower = formatNumber(from)
        let upper = formatNumber(to)
        switch (lower, upper) {
        case let (low?, high?): return "\(low)–\(high) words"
        case let (low?, nil): return "\(low)+ words"
        case let (nil, high?): return "under \(high) words"
        case (nil, nil): return nil
        }
    }

    fileprivate static func splitTags(_ field: String) -> [String] {
        field.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    fileprivate static func capitalizeFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    private static func formatNumber(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let number = Int(trimmed) { return number.formatted() }
        return trimmed
    }
}

/// Row copy and icon rules for Saved Searches (`Search-Saved` board).
enum SavedSearchRowPresentation {
    static func symbol(for filters: AO3SearchFilters) -> String {
        let query = filters.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasTags = [
            filters.fandom, filters.characters, filters.relationships, filters.additionalTags,
            filters.excludedFandoms, filters.excludedCharacters,
            filters.excludedRelationships, filters.excludedAdditionalTags,
        ].contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return (!query.isEmpty && !hasTags) ? "magnifyingglass" : "tag"
    }

    static func countSubtitle(_ count: Int) -> String {
        "\(count.formatted()) \(count == 1 ? "search" : "searches")"
    }

    static func subtitle(for filters: AO3SearchFilters) -> String? {
        var parts: [String] = []
        let query = filters.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty { parts.append("“\(query)”") }
        for field in [filters.fandom, filters.relationships, filters.characters, filters.additionalTags] {
            parts.append(contentsOf: SaveSearchPresentation.splitTags(field))
        }
        parts.append(contentsOf: SaveSearchPresentation.facetDescriptions(for: filters))
        if filters.sort != .relevance {
            parts.append("sorted by \(filters.sort.title.lowercased())")
        }
        guard !parts.isEmpty else { return nil }
        return SaveSearchPresentation.capitalizeFirst(parts.joined(separator: " · "))
    }
}

private struct SaveSearchSummaryChip: View {
    let text: String
    let kind: SaveSearchChip.Kind

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 4) {
            if kind == .included {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            } else if kind == .excluded {
                Image(systemName: "minus")
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.footnote.weight(.semibold))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                .strikethrough(kind == .excluded, color: foreground)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(minHeight: 30)
        .foregroundStyle(foreground)
        .background(fill, in: SubjectMetrics.controlShape(dynamicTypeSize))
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch kind {
        case .included: "\(text), included"
        case .excluded: "\(text), excluded"
        case .facet: text
        }
    }

    private var foreground: Color {
        switch kind {
        case .included: theme.appTheme.includeColor
        case .excluded: theme.appTheme.excludeColor
        case .facet: .primary
        }
    }

    private var fill: Color {
        switch kind {
        case .included: theme.appTheme.includeColor.opacity(0.12)
        case .excluded: theme.appTheme.excludeColor.opacity(0.08)
        case .facet: theme.appTheme.glassFill(0.12)
        }
    }
}
