import SwiftUI

// MARK: - Pills, groups, copy

/// 1o's All / Updated / Downloaded pills. They narrow the loaded page.
/// AO3's Marked for Later URL has no such query.
enum AO3MarkedForLaterFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case updated
    case downloaded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .updated: "Updated"
        case .downloaded: "Downloaded"
        }
    }
}

/// Which run a row belongs to on the All pill, and the layout that run uses.
enum AO3MarkedForLaterGroup: String, Sendable {
    case updatedSinceYouLooked
    case everythingElse

    var title: String {
        switch self {
        case .updatedSinceYouLooked: "Updated since you looked"
        case .everythingElse: "Everything else"
        }
    }
}

enum AO3MarkedForLaterRowLayout: Equatable, Sendable {
    /// Cover cards. The updated run on All, and the whole list on Updated.
    case covers
    /// Ledger rows. Everything else on All, and the whole list on Downloaded
    /// so a downloaded file can carry its size under the row.
    case ledger
}

struct AO3MarkedForLaterSection<Element>: Identifiable {
    let group: AO3MarkedForLaterGroup
    var items: [Element]
    /// All names each run. A narrowed pill already is that name, so a second
    /// header would repeat it.
    var showsHeader: Bool
    var layout: AO3MarkedForLaterRowLayout

    var id: AO3MarkedForLaterGroup { group }
}

/// "Updated" is chapters posted since this list was last looked at — the same
/// count `SubscriptionWatermarks` already computes. A missing watermark is not
/// updated: the first sight baselines, or a brand-new Marked for Later list
/// would open with every row in the cover group.
enum AO3MarkedForLaterClassification {
    /// `SubscriptionWatermarks` is main-actor because it reads `UserDefaults`
    /// there. This comparison itself does not, but it calls that function, so
    /// it stays on the same actor rather than growing a second copy of the rule.
    @MainActor
    static func isUpdated(
        work: AO3WorkSummary,
        watermarks: [Int: SubscriptionWatermark]
    ) -> Bool {
        SubscriptionWatermarks.newChapterCount(for: work, watermarks: watermarks) > 0
    }

    /// Downloaded is the local copy's `hasEPUB`. A remote-only row has no copy.
    static func isDownloaded(hasEPUB: Bool?) -> Bool {
        hasEPUB == true
    }
}

enum AO3MarkedForLaterGrouping {
    /// All keeps the artboard's two runs, in page order inside each, and drops
    /// a run that has nothing in it.
    ///
    /// Updated and Downloaded do not keep that split. The artboard has one
    /// frame, and on it the Updated chip is painted selected while the body is
    /// still 3 + 9 = 12 — the All composition. There is no second frame to
    /// copy. History's own pills narrow first and then keep whatever groups
    /// still have rows; here the two groups *are* the Updated split, so a
    /// narrowed pill is one flat list. Downloaded is ledger rather than covers
    /// so the size line has a row to sit under.
    static func sections<Element>(
        _ items: [Element],
        filter: AO3MarkedForLaterFilter,
        isUpdated: (Element) -> Bool,
        isDownloaded: (Element) -> Bool
    ) -> [AO3MarkedForLaterSection<Element>] {
        switch filter {
        case .all:
            return [
                section(
                    .updatedSinceYouLooked,
                    items.filter(isUpdated),
                    showsHeader: true,
                    layout: .covers
                ),
                section(
                    .everythingElse,
                    items.filter { !isUpdated($0) },
                    showsHeader: true,
                    layout: .ledger
                )
            ].compactMap { $0 }
        case .updated:
            return [
                section(
                    .updatedSinceYouLooked,
                    items.filter(isUpdated),
                    showsHeader: false,
                    layout: .covers
                )
            ].compactMap { $0 }
        case .downloaded:
            return [
                section(
                    .everythingElse,
                    items.filter(isDownloaded),
                    showsHeader: false,
                    layout: .ledger
                )
            ].compactMap { $0 }
        }
    }

    private static func section<Element>(
        _ group: AO3MarkedForLaterGroup,
        _ items: [Element],
        showsHeader: Bool,
        layout: AO3MarkedForLaterRowLayout
    ) -> AO3MarkedForLaterSection<Element>? {
        guard !items.isEmpty else { return nil }
        return AO3MarkedForLaterSection(
            group: group,
            items: items,
            showsHeader: showsHeader,
            layout: layout
        )
    }
}

enum AO3MarkedForLaterCopy {
    /// "12 works · synced 2 min ago". No sync stamp yet — the first fetch has
    /// not landed — so the line is the count alone.
    static func subtitle(workCount: Int, syncedAt: Date?, now: Date = Date()) -> String {
        let works = workCount == 1 ? "1 work" : "\(workCount) works"
        guard let syncedAt else { return works }
        return "\(works) · synced \(relativeSyncPhrase(from: syncedAt, to: now))"
    }

    /// Short, stable, and independent of the device locale. Foundation's
    /// relative format is what the account header uses for "4 min ago", and it
    /// moves with the locale; this screen's artboard is a fixed English phrase,
    /// so the tests pin the phrase rather than a formatter.
    static func relativeSyncPhrase(from syncedAt: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(syncedAt)))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 {
            return minutes == 1 ? "1 min ago" : "\(minutes) min ago"
        }
        let hours = minutes / 60
        if hours < 24 {
            return hours == 1 ? "1 hr ago" : "\(hours) hr ago"
        }
        let days = hours / 24
        return days == 1 ? "1 day ago" : "\(days) days ago"
    }

    /// The artboard's "12 of 4 pages" is its own illustration. The numbers here
    /// are the page the pagination bar is already on.
    static func footer(currentPage: Int, totalPages: Int) -> String {
        let pages = max(totalPages, 1)
        let page = min(max(currentPage, 1), pages)
        let noun = pages == 1 ? "page" : "pages"
        return "Marked for Later lives on AO3 — unmarking here unmarks there. "
            + "Pagination follows the ledger: \(page) of \(pages) \(noun)."
    }
}

/// "Downloaded · 1.4 MB", or nothing. The byte string comes from the existing
/// per-file label (`WorkDetailPresentation.fileSizeLabel`); this only decides
/// whether the line exists and how it reads. A `hasEPUB` flag with no readable
/// file does not invent a size.
enum AO3MarkedForLaterDownloadLine {
    static func text(hasEPUB: Bool, byteLabel: String?) -> String? {
        guard hasEPUB, let byteLabel, !byteLabel.isEmpty else { return nil }
        return "Downloaded · \(byteLabel)"
    }
}

// MARK: - Screen

/// Marked for Later's own list inside `AO3AccountWorksList`. Other account
/// lists do not come through here.
struct AO3MarkedForLaterWorksBrowser: View {
    let entries: [CanonicalWork]
    let watermarks: [Int: SubscriptionWatermark]
    let expandAll: Bool
    let palette: SubjectPalette
    let kicker: String
    let syncedAt: Date?
    let showPagination: Bool
    let currentPage: Int
    let totalPages: Int
    let isLoading: Bool
    @Binding var filter: AO3MarkedForLaterFilter
    let onPage: (Int) -> Void

    @Environment(ThemeManager.self) private var theme

    private var sections: [AO3MarkedForLaterSection<CanonicalWork>] {
        AO3MarkedForLaterGrouping.sections(
            entries,
            filter: filter,
            isUpdated: isUpdated(_:),
            isDownloaded: isDownloaded(_:)
        )
    }

    private var shownCount: Int {
        sections.reduce(0) { $0 + $1.items.count }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header.padding(.top, 20)
                AO3MarkedForLaterFilterRail(selection: $filter, palette: palette)
                if showPagination { paginationBar }
                if sections.isEmpty {
                    filterEmpty
                } else {
                    ForEach(sections) { section in
                        sectionBlock(section)
                    }
                }
                footer
                if showPagination { paginationBar }
            }
            .padding(.vertical, 8)
        }
        .subjectScreenWash(palette: palette)
    }

    /// "synced 2 min ago" is a duration, not a fixed fact, and a
    /// screen the reader can leave open for a while would otherwise print a
    /// stale age forever — nothing else in this view invalidates on the
    /// clock alone. `SubjectHeaderBlock`'s `subtitle` is a plain `String`,
    /// shared by every redesigned page; re-evaluating the string here, once a
    /// minute, is cheaper and safer than teaching that component to take a
    /// live clock for one screen.
    private var header: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            SubjectHeaderBlock(
                kicker: kicker,
                title: "Marked for Later",
                subtitle: AO3MarkedForLaterCopy.subtitle(
                    workCount: shownCount, syncedAt: syncedAt, now: context.date
                ),
                palette: palette,
                gutter: SubjectMetrics.accountGutter
            )
        }
    }

    private var paginationBar: some View {
        SearchPaginationBar(
            currentPage: currentPage,
            totalPages: totalPages,
            isLoading: isLoading
        ) { page in
            onPage(page)
        }
        .padding(.horizontal, CardListMetrics.sideMargin)
    }

    private var footer: some View {
        Text(AO3MarkedForLaterCopy.footer(currentPage: currentPage, totalPages: totalPages))
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SubjectMetrics.gutter)
            .padding(.top, 4)
    }

    private var filterEmpty: some View {
        ContentUnavailableView {
            Label("No matching works", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("No works on this page are \(filter.title.lowercased()).")
        } actions: {
            Button("Reset") { filter = .all }
        }
    }

    @ViewBuilder
    private func sectionBlock(_ section: AO3MarkedForLaterSection<CanonicalWork>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if section.showsHeader {
                SectionRuleHeader(title: section.group.title, count: section.items.count)
            }
            switch section.layout {
            case .covers:
                AccountWorksCompactGrid(entries: section.items)
            case .ledger:
                VStack(spacing: 10) {
                    ForEach(section.items) { entry in
                        ledgerRow(entry)
                    }
                }
            }
        }
    }

    /// Ledger content draws no card of its own (`WorkLedgerRow.drawsBackground`
    /// is false inside `SensitiveWorkRow`). This screen is a `ScrollView`
    /// because the updated run is `AccountWorksCompactGrid`, which cannot live
    /// in a `List` cell, so the wash is `subjectCard` rather than `.cardRow`.
    private func ledgerRow(_ entry: CanonicalWork) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ledgerRowBody(entry)
            if let line = downloadLine(for: entry) {
                AO3MarkedForLaterDownloadFootnote(text: line)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .subjectCard(palette: theme.appTheme.subjectPalette(hue: hue(for: entry)))
        .padding(.horizontal, CardListMetrics.sideMargin)
    }

    @ViewBuilder
    private func ledgerRowBody(_ entry: CanonicalWork) -> some View {
        if let work = entry.local {
            SensitiveWorkRow(
                work: work,
                expandAll: expandAll,
                presentation: .ledger
            )
        } else if let remote = entry.remote {
            EnrichingAO3WorkRow(
                work: remote,
                expandAll: expandAll,
                presentation: .searchLedger
            )
        }
    }

    private func downloadLine(for entry: CanonicalWork) -> String? {
        guard let work = entry.local else { return nil }
        return AO3MarkedForLaterDownloadLine.text(
            hasEPUB: work.hasEPUB,
            byteLabel: WorkDetailPresentation.fileSizeLabel(forFileAt: work.fileURL)
        )
    }

    private func isUpdated(_ entry: CanonicalWork) -> Bool {
        guard let remote = entry.remote else { return false }
        return AO3MarkedForLaterClassification.isUpdated(work: remote, watermarks: watermarks)
    }

    private func isDownloaded(_ entry: CanonicalWork) -> Bool {
        AO3MarkedForLaterClassification.isDownloaded(hasEPUB: entry.local?.hasEPUB)
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

/// The same pill row History uses, including the quieter Reset.
struct AO3MarkedForLaterFilterRail: View {
    @Binding var selection: AO3MarkedForLaterFilter
    let palette: SubjectPalette

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AO3MarkedForLaterFilter.allCases) { option in
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
                    selection = .all
                } label: {
                    SubjectChip(
                        text: "Reset",
                        style: .pill(isSelected: false),
                        systemImage: "xmark"
                    )
                    .opacity(selection == .all ? 0.45 : 0.7)
                }
                .buttonStyle(.plain)
                .minimumHitTarget(28)
                .accessibilityLabel("Reset filters")
            }
            .padding(.horizontal, 16)
        }
    }
}

/// Sits under a ledger row, the way History's visit line does. Not part of
/// `WorkRow`: that row is every ledger in the app.
struct AO3MarkedForLaterDownloadFootnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(text)
    }
}
