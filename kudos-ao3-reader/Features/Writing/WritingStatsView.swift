import SwiftUI

/// AO3's own stats page, without locally inferred trends or reader analytics.
struct WritingStatsView: View {
    @Environment(AO3AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(ThemeManager.self) private var theme

    @State private var stats: AO3UserStats?
    @State private var selectedYear: Int?
    @State private var grouping: AO3UserStats.Grouping = .byFandom
    @State private var sort: AO3UserStats.Sort = .kudos
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var reloadToken = 0
    @State private var activeRequestID: UUID?

    var body: some View {
        List {
            controlsSection
            totalsSection
            worksSections
        }
        .cardList()
        .environment(\.defaultMinListRowHeight, 0)
        .navigationTitle("Stats")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .hidesFloatingTabBar()
        .subjectScreenWash(palette: theme.scopePalette)
        .task(id: loadKey) { await load() }
    }

    private var controlsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    yearMenu
                    Spacer(minLength: 12)
                    SubjectSegmentedControl(
                        options: AO3UserStats.Grouping.allCases,
                        title: \.rawValue,
                        selection: $grouping
                    )
                    .frame(maxWidth: 190)
                    .accessibilityLabel("Group works")
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(AO3UserStats.Sort.allCases, id: \.self) { option in
                            sortButton(option)
                        }
                    }
                }
                .horizontalScrollViewport()
            }
            .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
        }
    }

    private var yearMenu: some View {
        Menu {
            Button("All Years") { selectedYear = nil }
            ForEach(stats?.availableYears ?? [], id: \.self) { year in
                Button(String(year)) { selectedYear = year }
            }
        } label: {
            HStack(spacing: 5) {
                Text(selectedYear.map(String.init) ?? "All Years")
                Image(systemName: "chevron.down")
                    .font(.caption.bold())
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.accentInk)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(theme.appTheme.glassFill(0.09), in: Capsule())
            .overlay(Capsule().stroke(theme.appTheme.glassStroke(0.13), lineWidth: 0.5))
        }
        .accessibilityLabel("Year")
        .accessibilityValue(selectedYear.map(String.init) ?? "All Years")
    }

    private func sortButton(_ option: AO3UserStats.Sort) -> some View {
        let isSelected = sort == option
        return Button { sort = option } label: {
            Text(option.rawValue)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        Capsule().fill(.accentFill)
                    } else {
                        Capsule().fill(theme.appTheme.glassFill(0.09))
                            .overlay(Capsule().stroke(theme.appTheme.glassStroke(0.13), lineWidth: 0.5))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var totalsSection: some View {
        if let stats, !stats.isEmpty {
            Section {
                WritingStatsTotalsPanel(stats: stats)
                    .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
            } header: {
                SectionRuleHeader(
                    title: "Totals",
                    countText: selectedYear.map(String.init) ?? "All Years"
                )
                .pageBodyRow(top: 18, gutter: 0)
            }
        }
    }

    @ViewBuilder
    private var worksSections: some View {
        if isLoading {
            Section {
                ProgressView("Loading stats…")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardRow()
            }
        } else if let errorMessage {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Try Again") { reloadToken += 1 }
                }
                .cardRow()
            }
        } else if let stats, stats.isEmpty {
            Section {
                ContentUnavailableView(
                    "No stats for this year",
                    systemImage: "chart.bar",
                    description: Text("AO3 has no posted-work statistics for this selection.")
                )
                .cardRow()
            }
        } else if let stats {
            let sections = stats.sections(grouping: grouping, sortedBy: sort)
            let chartMaximum = maximum(for: sort, in: sections.flatMap(\.works))
            ForEach(sections) { section in
                Section {
                    VStack(spacing: 0) {
                        ForEach(Array(section.works.enumerated()), id: \.element.id) { index, work in
                            if index > 0 { SubjectRowSeparator() }
                            WritingStatsWorkRow(
                                work: work,
                                sort: sort,
                                maximum: chartMaximum
                            ) {
                                router.open(AO3Client.workURL(workID: work.id))
                            }
                        }
                    }
                    .subjectPanel()
                    .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
                } header: {
                    SectionRuleHeader(
                        title: grouping == .flat ? "Works" : section.name,
                        countText: "\(section.works.count) \(section.works.count == 1 ? "work" : "works")"
                    )
                    .pageBodyRow(top: 18, gutter: 0)
                }
            }
        }
    }

    private func maximum(for sort: AO3UserStats.Sort, in works: [AO3UserStats.Work]) -> Int? {
        guard sort != .date else { return nil }
        return works.compactMap { sort.value(for: $0) }.max()
    }

    private var loadKey: String {
        "\(auth.sessionGeneration)|\(auth.username ?? "")|\(selectedYear.map(String.init) ?? "all")|\(reloadToken)"
    }

    private func load() async {
        let requestID = UUID()
        activeRequestID = requestID
        isLoading = true
        errorMessage = nil
        stats = nil
        defer {
            if activeRequestID == requestID { isLoading = false }
        }
        do {
            let loaded = try await auth.loadUserStats(year: selectedYear)
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            stats = loaded
        } catch is CancellationError {
            return
        } catch {
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            errorMessage = UserFacingError.message(for: error)
        }
    }
}

struct WritingStatsTotalsPanel: View {
    let stats: AO3UserStats

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: heroColumns, alignment: .leading, spacing: 10) {
                ForEach(heroFigures, id: \.label) { figure in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(figure.value.formatted())
                            .font(.title.bold())
                            .monospacedDigit()
                        Text(figure.label)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !secondaryFigures.isEmpty {
                Divider()
                LazyVGrid(columns: secondaryColumns, alignment: .leading, spacing: 10) {
                    ForEach(secondaryFigures, id: \.label) { figure in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(figure.value.formatted())
                                .font(.headline.bold())
                                .monospacedDigit()
                            Text(figure.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(14)
        .subjectPanel()
        .accessibilityElement(children: .contain)
    }

    private var heroColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), alignment: .leading),
            count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
        )
    }

    private var secondaryColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), alignment: .leading),
            count: dynamicTypeSize.isAccessibilitySize ? 2 : 3
        )
    }

    private var heroFigures: [Figure] {
        [
            stats.hits.map { Figure(value: $0, label: "Hits") },
            stats.kudos.map { Figure(value: $0, label: "Kudos") }
        ].compactMap { $0 }
    }

    private var secondaryFigures: [Figure] {
        [
            stats.commentThreads.map { Figure(value: $0, label: "Comment Threads") },
            stats.bookmarks.map { Figure(value: $0, label: "Bookmarks") },
            stats.subscriptions.map { Figure(value: $0, label: "Subscriptions") },
            stats.userSubscriptions.map { Figure(value: $0, label: "User Subscriptions") },
            stats.wordCount.map { Figure(value: $0, label: "Word Count") }
        ].compactMap { $0 }
    }

    private struct Figure {
        let value: Int
        let label: String
    }
}

private struct WritingStatsWorkRow: View {
    let work: AO3UserStats.Work
    let sort: AO3UserStats.Sort
    let maximum: Int?
    let action: () -> Void

    @Environment(\.accentFill) private var accentFill
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(work.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(work.fandoms.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if let kudos = work.kudos {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(kudos.formatted())
                                .font(.subheadline.bold())
                                .monospacedDigit()
                                .foregroundStyle(.accentInk)
                            Text("Kudos")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let maximum, maximum > 0, let value = selectedValue {
                    ProgressView(value: Double(value), total: Double(maximum))
                        .tint(accentFill)
                        .accessibilityLabel("\(sort.rawValue), \(value.formatted()) of \(maximum.formatted())")
                }

                LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 6) {
                    ForEach(metrics, id: \.label) { metric in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(metric.value.formatted())
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                            Text(metric.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var selectedValue: Int? {
        sort.value(for: work)
    }

    private var metricColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), alignment: .leading),
            count: dynamicTypeSize.isAccessibilitySize ? 2 : 5
        )
    }

    private var metrics: [Metric] {
        [
            work.wordCount.map { Metric(value: $0, label: "Words") },
            work.hits.map { Metric(value: $0, label: "Hits") },
            work.commentThreads.map { Metric(value: $0, label: "Threads") },
            work.bookmarks.map { Metric(value: $0, label: "Bookmarks") },
            Metric(value: work.subscriptions, label: "Subs")
        ].compactMap { $0 }
    }

    private var accessibilityLabel: String {
        var parts = [work.title]
        if let kudos = work.kudos { parts.append("\(kudos.formatted()) Kudos") }
        parts += metrics.map { "\($0.value.formatted()) \($0.label)" }
        return parts.joined(separator: ", ")
    }

    private struct Metric {
        let value: Int
        let label: String
    }
}
