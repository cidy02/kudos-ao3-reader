import SwiftUI

/// Filters › Sort By (T-473, board "Search filters › Sort By"): Ways to Find, the
/// column AO3 loads by, then — on Search, which passes `ranking` — the rank Kudos
/// computes over the works already loaded, its options, and one Order.
///
/// Everything above Ranking is an AO3 parameter and takes effect when the panel
/// runs the search. The ranking is applied as it is tapped: it costs no request.
struct SearchSortByView: View {
    @Binding var filters: AO3SearchFilters
    /// Nil on a surface with no computed ranking (Browse): those sections hide.
    var ranking: Binding<LoadedWorksRanking>?
    var allowsRelevanceSort = true

    var body: some View {
        Form {
            Group {
                waysToFindSection
                loadSection
                if let ranking {
                    rankSection(ranking)
                    rankingOptionsSection(ranking)
                } else {
                    Section { minimumHitsPicker }
                }
                orderSection
            }
            .appThemedRows()
        }
        .formStyle(.grouped)
        .appThemedScroll()
        .navigationTitle("Sort By")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Sections

    private var waysToFindSection: some View {
        Section {
            ForEach(SearchWaysToFind.allCases) { preset in
                checkRow(preset.title, subtitle: preset.subtitle, isOn: preset.isApplied(in: filters)) {
                    SearchWaysToFind.toggle(preset, in: &filters, defaultSort: defaultSort)
                }
            }
        } header: {
            SubjectFieldLabel(text: "Ways to Find", style: .formGroup)
        }
    }

    private var loadSection: some View {
        Section {
            ForEach(columns) { column in
                checkRow(column.title, isOn: filters.sort == column) {
                    guard filters.sort != column else { return }
                    filters.sort = column
                    // A rank owns the Order control; AO3 then loads in the column's
                    // natural direction (see `LoadedWorksRanking.select`).
                    filters.sortDirection = column.naturalDirection
                }
            }
        } header: {
            SubjectFieldLabel(text: "Load from AO3 by", style: .formGroup)
        } footer: {
            if let preset = SearchWaysToFind.applied(in: filters) {
                Text("\(preset.title) adds “\(preset.queryNote)” to the search AO3 runs.")
            }
        }
    }

    private func rankSection(_ ranking: Binding<LoadedWorksRanking>) -> some View {
        Section {
            ForEach(LoadedWorksRank.allCases) { rank in
                checkRow(rank.title, subtitle: rank.subtitle, isOn: ranking.wrappedValue.rank == rank) {
                    ranking.wrappedValue.select(rank, filters: &filters)
                }
            }
        } header: {
            SubjectFieldLabel(text: "Then Rank Loaded Works by", style: .formGroup)
        } footer: {
            // Not yet the spec's "or up to 100 at once with Rank Top 100": the owner
            // has approved it in principle (2026-10-29), but how to load several
            // pages respectfully (docs/AO3_NETWORKING_POLICY.md) is its own task.
            Text("Ranks only the works already loaded from AO3. Kudos never loads extra pages to rank.")
        }
    }

    private func rankingOptionsSection(_ ranking: Binding<LoadedWorksRanking>) -> some View {
        let isRanked = ranking.wrappedValue.isActive
        return Section {
            Toggle(isOn: ranking.ranksCautiously) {
                titled("Rank cautiously", "Works with few readers need more kudos to rank high")
            }
            .accentFill()
            .disabled(!isRanked)
            Toggle(isOn: ranking.setsAsideUnusual) {
                titled("Set aside unusual stats", "More kudos than hits, or thousands of kudos and almost no bookmarks")
            }
            .accentFill()
            .disabled(!isRanked)
            minimumHitsPicker
            Toggle("Show the signal on each result", isOn: ranking.showsSignal)
                .accentFill()
                .disabled(!isRanked)
        } header: {
            SubjectFieldLabel(text: "Ranking", style: .formGroup)
        }
    }

    /// AO3's own `work_search[hits]` lower bound — the same field as the Hits slider.
    private var minimumHitsPicker: some View {
        Picker(selection: $filters.hitsFrom) {
            ForEach(SearchWaysToFind.minimumHitsOptions(including: filters.hitsFrom), id: \.self) { value in
                Text(SearchWaysToFind.minimumHitsTitle(value)).tag(value)
            }
        } label: {
            titled("Leave out works under", "Sent to AO3 with the search, so pages stay full")
        }
    }

    /// One Order: the rank's when Kudos is ranking, otherwise AO3's direction for
    /// the column. Best Match has no direction (AO3 orders by score).
    @ViewBuilder
    private var orderSection: some View {
        if let ranking, ranking.wrappedValue.isActive {
            Section {
                Picker("Order", selection: ranking.order) {
                    ForEach(LoadedWorksRankOrder.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accentFill()
            }
        } else if filters.sort != .relevance {
            Section {
                Picker("Order", selection: $filters.sortDirection) {
                    ForEach(Self.directions(for: filters.sort)) { direction in
                        Text(Self.directionTitle(direction, for: filters.sort)).tag(direction)
                    }
                }
                .pickerStyle(.segmented)
                .accentFill()
            }
        }
    }

    // MARK: - Rows

    private func checkRow(
        _ title: String,
        subtitle: String? = nil,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                titled(title, subtitle)
                Spacer(minLength: 0)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func titled(_ title: String, _ subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Columns

    private var columns: [AO3SearchFilters.Sort] {
        allowsRelevanceSort
            ? AO3SearchFilters.Sort.allCases
            : AO3SearchFilters.Sort.allCases.filter { $0 != .relevance }
    }

    private var defaultSort: AO3SearchFilters.Sort {
        allowsRelevanceSort ? .relevance : .dateUpdated
    }

    /// The column's natural direction first, so the left segment is the usual one.
    static func directions(for sort: AO3SearchFilters.Sort) -> [AO3SearchFilters.SortDirection] {
        sort.naturalDirection == .ascending ? [.ascending, .descending] : [.descending, .ascending]
    }

    static func directionTitle(_ direction: AO3SearchFilters.SortDirection, for sort: AO3SearchFilters.Sort) -> String {
        switch sort {
        case .creator, .workTitle: direction == .ascending ? "A to Z" : "Z to A"
        case .dateUpdated, .datePosted: direction == .descending ? "Newest First" : "Oldest First"
        default: direction == .descending ? "Highest First" : "Lowest First"
        }
    }
}

/// The Filters panel's Sort by row: the rank when Kudos is ranking, else the Way
/// to Find that is on, else AO3's column.
enum SearchSortBySummary {
    static func value(filters: AO3SearchFilters, ranking: LoadedWorksRanking?) -> String {
        if let ranking, ranking.isActive { return ranking.rank.title }
        if let preset = SearchWaysToFind.applied(in: filters) { return preset.title }
        return filters.sort.title
    }
}
