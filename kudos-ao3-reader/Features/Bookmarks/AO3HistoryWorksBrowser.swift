import SwiftUI

/// History's own list inside `AO3AccountWorksList`: the shared account header
/// with History's title and tally, the progress pills, and source-ordered
/// visit groups. Other account lists do not come through here.
struct AO3HistoryWorksBrowser: View {
    let entries: [CanonicalWork]
    let readings: [Int: AO3ReadingEntry]
    let displayMode: WorkListDisplayMode
    let expandAll: Bool
    let palette: SubjectPalette
    let kicker: String
    let subtitle: String
    let showPagination: Bool
    let currentPage: Int
    let totalPages: Int
    let isLoading: Bool
    @Binding var filter: AO3HistoryProgressFilter
    let onPage: (Int) -> Void
    let onDelete: (CanonicalWork) -> Void

    private var groups: [AO3HistoryVisitGroup<CanonicalWork>] {
        AO3HistoryVisitGrouping.groups(entries) { entry in
            guard let id = entry.ao3WorkID else { return "" }
            return readings[id]?.lastVisited ?? ""
        }
    }

    var body: some View {
        Group {
            if displayMode == .compact {
                compactBody
            } else {
                detailedBody
            }
        }
    }

    private var compactBody: some View {
        ScrollView {
            VStack(spacing: 12) {
                header.padding(.top, 20)
                AO3HistoryFilterRail(selection: $filter, palette: palette)
                if showPagination { paginationBar.padding(.horizontal, CardListMetrics.sideMargin) }
                if entries.isEmpty {
                    filterEmpty
                } else {
                    ForEach(groups) { group in
                        SectionRuleHeader(title: group.bucket.title, count: group.items.count)
                        AccountWorksCompactGrid(entries: group.items)
                    }
                }
                if showPagination { paginationBar.padding(.horizontal, CardListMetrics.sideMargin) }
            }
            .padding(.vertical, 8)
        }
        .subjectScreenWash(palette: palette)
    }

    private var detailedBody: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets(top: 20, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                AO3HistoryFilterRail(selection: $filter, palette: palette)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if showPagination {
                Section { paginationBar.bareListRow() }
            }
            if entries.isEmpty {
                Section { filterEmpty.bareListRow() }
            } else {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.items) { entry in
                            detailedRow(entry)
                        }
                    } header: {
                        SectionRuleHeader(title: group.bucket.title, count: group.items.count)
                            .textCase(nil)
                            .listRowInsets(EdgeInsets())
                            .padding(.bottom, 10)
                    }
                }
            }
            if showPagination {
                Section { paginationBar.bareListRow() }
            }
        }
        .cardList()
        .subjectScreenWash(palette: palette)
    }

    private var header: some View {
        SubjectHeaderBlock(
            kicker: kicker,
            title: "History",
            subtitle: subtitle,
            palette: palette,
            gutter: SubjectMetrics.accountGutter
        )
    }

    private var paginationBar: some View {
        SearchPaginationBar(
            currentPage: currentPage,
            totalPages: totalPages,
            isLoading: isLoading
        ) { page in
            onPage(page)
        }
    }

    private var filterEmpty: some View {
        ContentUnavailableView {
            Label("No matching works", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("No works on this page are \(filter.title.lowercased()).")
        } actions: {
            Button("Reset") { filter = .everything }
        }
    }

    private func detailedRow(_ entry: CanonicalWork) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            historyRowBody(entry)
            if let reading = reading(for: entry) {
                AO3HistoryReadingFootnote(
                    reading: reading,
                    localProgress: localProgress(for: entry)
                )
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canDelete(entry) {
                Button(role: .destructive) {
                    onDelete(entry)
                } label: {
                    Label("Delete from History", systemImage: "trash")
                }
            }
        }
        .cardRow(tintHue: hue(for: entry))
    }

    @ViewBuilder
    private func historyRowBody(_ entry: CanonicalWork) -> some View {
        if let work = entry.local {
            SensitiveWorkRow(
                work: work,
                expandAll: expandAll,
                presentation: displayMode == .ledger ? .ledger : .standard
            )
        } else if let remote = entry.remote {
            EnrichingAO3WorkRow(
                work: remote,
                expandAll: expandAll,
                presentation: displayMode == .ledger ? .searchLedger : .standard
            )
        }
    }

    private func reading(for entry: CanonicalWork) -> AO3ReadingEntry? {
        guard let id = entry.ao3WorkID else { return nil }
        return readings[id]
    }

    private func canDelete(_ entry: CanonicalWork) -> Bool {
        reading(for: entry)?.readingID != nil
    }

    private func localProgress(for entry: CanonicalWork) -> String? {
        guard let work = entry.local else { return nil }
        return AO3HistoryLocalProgress.label(
            isFinished: work.isFinished,
            lastSpineIndex: work.lastSpineIndex,
            chapters: work.chapters,
            readingProgress: work.readingProgress
        )
    }

    private func hue(for entry: CanonicalWork) -> Double {
        if let work = entry.local {
            return CoverArt.workHue(fandoms: work.workFandoms, title: work.title)
        }
        if let remote = entry.remote {
            return CoverArt.workHue(fandoms: remote.fandoms, title: remote.title)
        }
        return 0
    }
}

/// The same pill row Library uses for a quick filter, including the quieter Reset.
struct AO3HistoryFilterRail: View {
    @Binding var selection: AO3HistoryProgressFilter
    let palette: SubjectPalette

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AO3HistoryProgressFilter.allCases) { option in
                    Button {
                        selection = option
                    } label: {
                        SubjectChip(
                            text: option.title,
                            style: .pill(isSelected: selection == option),
                            palette: palette
                        )
                    }
                    .buttonStyle(.plain)
                    .minimumHitTarget(28)
                }
                Button {
                    selection = .everything
                } label: {
                    SubjectChip(
                        text: "Reset",
                        style: .pill(isSelected: false),
                        systemImage: "xmark"
                    )
                    .opacity(selection == .everything ? 0.45 : 0.7)
                }
                .buttonStyle(.plain)
                .minimumHitTarget(28)
                .accessibilityLabel("Reset filters")
            }
            .padding(.horizontal, 16)
        }
    }
}

/// Visit count, local progress, version, and last-visited on one line, with
/// the Marked-for-Later / Flagged-to-skip chips under it. A missing fact is
/// dropped rather than printed as a blank.
struct AO3HistoryReadingFootnote: View {
    let reading: AO3ReadingEntry
    var localProgress: String?

    var body: some View {
        let facts = [
            reading.visitCountDisplay,
            localProgress,
            reading.versionDisplay,
            reading.lastVisitedDisplay
        ].compactMap(\.self)
        VStack(alignment: .leading, spacing: 4) {
            if !facts.isEmpty {
                Text(facts.joined(separator: " · "))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if reading.isMarkedForLater || reading.isFlaggedToSkip {
                HStack(spacing: 6) {
                    if reading.isMarkedForLater {
                        Label("Marked for later", systemImage: "clock.badge")
                    }
                    if reading.isFlaggedToSkip {
                        Label("Flagged to skip", systemImage: "eye.slash")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }
}
