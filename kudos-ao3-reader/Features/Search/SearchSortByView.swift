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
    /// False when embedded inside the docked Duo Filters pane so it does not overwrite
    /// Search's outer navigation bar title.
    var showsNavigationTitle = true
    /// Works already loaded on screen, used to preview the top ranked figure on the active rank.
    var loadedWorks: [AO3WorkSummary] = []
    /// Momentum's baseline sightings from the current search session.
    var previousKudos: [Int: Int] = [:]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let content = Form {
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

        if showsNavigationTitle {
            content
                .navigationTitle("Sort By")
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
        } else {
            content
        }
    }

    // MARK: - Sections

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondaryInk)
            .textCase(nil)
    }

    private var waysToFindSection: some View {
        Section {
            ForEach(SearchWaysToFind.allCases) { preset in
                checkRow(
                    icon: iconTile(for: preset),
                    preset.title,
                    subtitle: preset.subtitle,
                    isOn: preset.isApplied(in: filters)
                ) {
                    SearchWaysToFind.toggle(preset, in: &filters, defaultSort: defaultSort)
                }
            }
        } header: {
            sectionHeader("Ways to Find")
        }
    }

    private var loadSection: some View {
        Section {
            ForEach(columns) { column in
                checkRow(
                    icon: iconTile(for: column),
                    column.title,
                    isOn: filters.sort == column
                ) {
                    guard filters.sort != column else { return }
                    filters.sort = column
                    // A rank owns the Order control; AO3 then loads in the column's
                    // natural direction (see `LoadedWorksRanking.select`).
                    filters.sortDirection = column.naturalDirection
                }
            }
        } header: {
            sectionHeader("Load from AO3 by")
        } footer: {
            if let preset = SearchWaysToFind.applied(in: filters) {
                Text("\(preset.title) adds “\(preset.queryNote)” to the search AO3 runs.")
            }
        }
    }

    private func rankSection(_ ranking: Binding<LoadedWorksRanking>) -> some View {
        Section {
            ForEach(LoadedWorksRank.allCases) { rank in
                let isSelected = ranking.wrappedValue.rank == rank
                let topMeta = isSelected
                    ? Self.topLoadedResultLine(
                        for: rank,
                        works: loadedWorks,
                        settings: ranking.wrappedValue,
                        previousKudos: previousKudos
                    )
                    : nil
                checkRow(
                    icon: iconTile(for: rank),
                    rank.title,
                    subtitle: rank.subtitle,
                    meta: topMeta,
                    isOn: isSelected
                ) {
                    ranking.wrappedValue.select(rank, filters: &filters)
                }
            }
        } header: {
            sectionHeader("Then Rank Loaded Works by")
        } footer: {
            Text(Self.rankingFooter())
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
                titled("Set aside unusual stats", ReaderResponseCopy.unusualStatsSubtitle)
            }
            .accentFill()
            .disabled(!isRanked)
            minimumHitsPicker
            Toggle("Show the signal on each result", isOn: ranking.showsSignal)
                .accentFill()
                .disabled(!isRanked)
        } header: {
            sectionHeader("Ranking")
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
                orderRow {
                    Picker("Order", selection: ranking.order) {
                        ForEach(LoadedWorksRankOrder.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accentFill()
                }
            }
        } else if filters.sort != .relevance {
            Section {
                orderRow {
                    Picker("Order", selection: $filters.sortDirection) {
                        ForEach(Self.directions(for: filters.sort)) { direction in
                            Text(Self.directionTitle(direction, for: filters.sort)).tag(direction)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accentFill()
                }
            }
        }
    }

    @ViewBuilder
    private func orderRow<Control: View>(@ViewBuilder control: () -> Control) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                Text("Order")
                    .foregroundStyle(.primary)
                control()
            }
        } else {
            HStack(spacing: 12) {
                Text("Order")
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                control()
                    .fixedSize()
            }
        }
    }

    // MARK: - Rows

    private func checkRow(
        icon: SettingsIconTile,
        _ title: String,
        subtitle: String? = nil,
        meta: String? = nil,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                icon
                titled(title, subtitle, meta: meta)
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

    private func titled(_ title: String, _ subtitle: String?, meta: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
            }
            if let meta {
                Text(meta)
                    .font(.footnote)
                    .foregroundStyle(themeManager.accentInk)
            }
        }
    }

    // MARK: - Icons

    private func iconTile(for preset: SearchWaysToFind) -> SettingsIconTile {
        switch preset {
        case .readerFavourites:
            SettingsIconTile(hex: "#821019", systemImage: "heart")
        case .newAndLoved:
            SettingsIconTile(hex: "#E07000", systemImage: "calendar")
        case .hiddenGems:
            SettingsIconTile(hex: "#5856D6", systemImage: "sparkles")
        case .activeWIPs:
            SettingsIconTile(hex: "#2F8F3A", systemImage: "clock")
        }
    }

    private func iconTile(for column: AO3SearchFilters.Sort) -> SettingsIconTile {
        switch column {
        case .relevance:
            SettingsIconTile(hex: "#1E63C8", systemImage: "sparkles")
        case .dateUpdated:
            SettingsIconTile(hex: "#E07000", systemImage: "clock.arrow.circlepath")
        case .datePosted:
            SettingsIconTile(hex: "#E07000", systemImage: "calendar")
        case .workTitle:
            SettingsIconTile(hex: "#6C6C70", systemImage: "textformat")
        case .creator:
            SettingsIconTile(hex: "#6C6C70", systemImage: "person")
        case .words:
            SettingsIconTile(hex: "#7B3FA0", systemImage: "text.alignleft")
        case .hits:
            SettingsIconTile(hex: "#5856D6", systemImage: "eye")
        case .kudos:
            SettingsIconTile(hex: "#821019", systemImage: "heart")
        case .comments:
            SettingsIconTile(hex: "#2F8F3A", systemImage: "bubble.left")
        case .bookmarks:
            SettingsIconTile(hex: "#C25E00", systemImage: "bookmark")
        }
    }

    private func iconTile(for rank: LoadedWorksRank) -> SettingsIconTile {
        switch rank {
        case .ao3Order:
            SettingsIconTile(hex: "#6C6C70", systemImage: "line.3.horizontal")
        case .kudosPerHitAdjusted:
            SettingsIconTile(hex: "#821019", systemImage: "heart")
        case .savesPerKudos:
            SettingsIconTile(hex: "#C25E00", systemImage: "bookmark")
        case .commentsPerKudos:
            SettingsIconTile(hex: "#2F8F3A", systemImage: "bubble.left")
        case .momentum:
            SettingsIconTile(hex: "#1E63C8", systemImage: "chart.line.uptrend.xyaxis")
        case .kudosPerThousandWords:
            SettingsIconTile(hex: "#7B3FA0", systemImage: "text.alignleft")
        }
    }

    // MARK: - Columns

    /// Search-Sort board column order: Best Match, Date Updated, Date Posted,
    /// Title, Creator, Word Count, Hits, Kudos, Comments, Bookmarks.
    static let boardColumnOrder: [AO3SearchFilters.Sort] = [
        .relevance, .dateUpdated, .datePosted, .workTitle, .creator,
        .words, .hits, .kudos, .comments, .bookmarks,
    ]

    static func displayedColumns(allowsRelevanceSort: Bool) -> [AO3SearchFilters.Sort] {
        allowsRelevanceSort ? boardColumnOrder : boardColumnOrder.filter { $0 != .relevance }
    }

    private var columns: [AO3SearchFilters.Sort] {
        Self.displayedColumns(allowsRelevanceSort: allowsRelevanceSort)
    }

    static func rankingFooter(rankTop100Enabled: Bool? = nil) -> String {
        if rankTop100Enabled ?? RankTop100Feature.isEnabled {
            return "Ranks the works already loaded, or up to 100 at once with Rank Top 100."
        }
        return "Ranks only the works already loaded from AO3. Kudos never loads extra pages to rank."
    }

    /// Accent meta line on the selected computed rank when results are already loaded.
    static func topLoadedResultLine(
        for rank: LoadedWorksRank,
        works: [AO3WorkSummary],
        settings: LoadedWorksRanking,
        previousKudos: [Int: Int] = [:],
        now: Date = Date()
    ) -> String? {
        guard rank != .ao3Order, !works.isEmpty else { return nil }
        var evaluation = settings
        evaluation.rank = rank
        let partition = LoadedWorksRanker.partition(
            works, by: evaluation, previousKudos: previousKudos, now: now
        )
        guard let top = partition.ranked.first else { return nil }
        let figures = LoadedWorksRanker.Figures(top.work, now: now)
        guard let detail = topLoadedResultDetail(
            for: rank, top: top, figures: figures, previousKudos: previousKudos
        ) else { return nil }
        return "Top loaded result: \(detail)"
    }

    private static func topLoadedResultDetail(
        for rank: LoadedWorksRank,
        top: RankedWork,
        figures: LoadedWorksRanker.Figures,
        previousKudos: [Int: Int]
    ) -> String? {
        switch rank {
        case .ao3Order:
            return nil
        case .kudosPerHitAdjusted:
            guard let raw = LoadedWorksRanker.rawFigure(.kudosPerHitAdjusted, figures),
                  let prior = top.prior, prior > 0 else { return nil }
            return "\(QualitySignalTones.decimal(raw / prior))× typical"
        case .savesPerKudos:
            guard let raw = LoadedWorksRanker.rawFigure(.savesPerKudos, figures) else { return nil }
            return "\(QualitySignalTones.decimal(raw * 100))% saved"
        case .commentsPerKudos:
            guard let raw = LoadedWorksRanker.rawFigure(.commentsPerKudos, figures) else { return nil }
            return "\(QualitySignalTones.decimal(raw * 100))% comments"
        case .momentum:
            guard let gain = LoadedWorksRanker.momentumGain(
                kudos: figures.kudos, previous: previousKudos[top.work.id]
            ), gain > 0 else { return nil }
            let gainText = gain.formatted(.number.precision(.fractionLength(0)))
            return "+\(gainText) kudos"
        case .kudosPerThousandWords:
            guard let raw = LoadedWorksRanker.rawFigure(.kudosPerThousandWords, figures) else { return nil }
            return "\(QualitySignalTones.decimal(raw)) kudos per 1,000 words"
        }
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
