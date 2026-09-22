import SwiftUI

// MARK: - Pills, groups, copy

/// All / Updated. They narrow the loaded page.
///
/// AO3's subscriptions index can also scope Works / Series / Authors with
/// `type=`. This screen does not. A series link and a user link are not work
/// rows, and that scope is its own fetch. Works is what the list already asks
/// for (`subscriptionsURL` sends `type=works`).
enum AO3SubscriptionsFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case updated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .updated: "Updated"
        }
    }
}

/// Which run a row belongs to on the All pill.
enum AO3SubscriptionsGroup: String, Sendable {
    case updatedSinceYouLooked
    case everythingElse

    var title: String {
        switch self {
        case .updatedSinceYouLooked: "Updated since you looked"
        case .everythingElse: "Everything else"
        }
    }
}

struct AO3SubscriptionsSection<Element>: Identifiable {
    let group: AO3SubscriptionsGroup
    var items: [Element]
    /// All names each run. The Updated pill already is that name, so a second
    /// header would repeat it.
    var showsHeader: Bool

    var id: AO3SubscriptionsGroup { group }
}

/// "Updated" is chapters posted since this list was last looked at — the same
/// count `SubscriptionWatermarks` already computes, on the subscriptions key.
/// A missing watermark is not updated: the first sight baselines.
enum AO3SubscriptionsClassification {
    /// `SubscriptionWatermarks` is main-actor because it reads `UserDefaults`
    /// there. This comparison calls that function, so it stays on the same actor.
    @MainActor
    static func isUpdated(
        work: AO3WorkSummary,
        watermarks: [Int: SubscriptionWatermark]
    ) -> Bool {
        SubscriptionWatermarks.newChapterCount(for: work, watermarks: watermarks) > 0
    }
}

enum AO3SubscriptionsGrouping {
    /// All keeps the two runs, in page order inside each, and drops a run that
    /// has nothing in it. Updated does not keep that split: the pill already
    /// is the updated run, so it is one flat list.
    static func sections<Element>(
        _ items: [Element],
        filter: AO3SubscriptionsFilter,
        isUpdated: (Element) -> Bool
    ) -> [AO3SubscriptionsSection<Element>] {
        switch filter {
        case .all:
            return [
                section(.updatedSinceYouLooked, items.filter(isUpdated), showsHeader: true),
                section(.everythingElse, items.filter { !isUpdated($0) }, showsHeader: true)
            ].compactMap { $0 }
        case .updated:
            return [
                section(.updatedSinceYouLooked, items.filter(isUpdated), showsHeader: false)
            ].compactMap { $0 }
        }
    }

    private static func section<Element>(
        _ group: AO3SubscriptionsGroup,
        _ items: [Element],
        showsHeader: Bool
    ) -> AO3SubscriptionsSection<Element>? {
        guard !items.isEmpty else { return nil }
        return AO3SubscriptionsSection(group: group, items: items, showsHeader: showsHeader)
    }
}

/// Which chapters were posted since the watermark.
///
/// The old total is `SubscriptionWatermark.postedChapterCount`. The current
/// total is `SavedWork.postedChapterCount(from:)` — the number before the
/// slash in AO3's "14/20", not the planned total. The range is the chapters
/// strictly after the old total, through the current one. A count that did
/// not grow has no line: a deleted chapter is not "new", and a missing
/// watermark is not a range (first sight baselines instead).
enum AO3SubscriptionsChapterRange {
    static func label(seenPosted: Int, currentPosted: Int) -> String? {
        guard currentPosted > seenPosted else { return nil }
        let first = seenPosted + 1
        if first == currentPosted {
            return "Chapter \(first) new"
        }
        return "Chapters \(first)-\(currentPosted) new"
    }

    /// Nil when this work has no watermark, or its `chapters` string does not
    /// name a higher posted count. The subscriptions index leaves that string
    /// empty. The caller passes the work-page summary once enrichment has one.
    @MainActor
    static func label(
        work: AO3WorkSummary,
        watermarks: [Int: SubscriptionWatermark]
    ) -> String? {
        guard let seen = watermarks[work.id] else { return nil }
        return label(
            seenPosted: seen.postedChapterCount,
            currentPosted: SavedWork.postedChapterCount(from: work.chapters)
        )
    }
}

/// Which summary Updated and the chapter range should read.
///
/// The index row is what the list fetched. Its `chapters` is empty, so it
/// never counts as updated. A work-page enrichment is preferred once it
/// names a posted count. Anything else — a failed enrichment, a summary
/// that still has no chapters — leaves the index row in place.
enum AO3SubscriptionsChapterSource {
    static func summary(
        remote: AO3WorkSummary,
        enrichedSummaries: [Int: AO3WorkSummary]
    ) -> AO3WorkSummary {
        guard let enriched = enrichedSummaries[remote.id],
              SubscriptionWatermarks.hasKnownPostedChapterCount(enriched.chapters)
        else { return remote }
        return enriched
    }
}

enum AO3SubscriptionsCopy {
    /// "12 works · 2 with new chapters · page 2 of 4". The new-chapters clause
    /// is the updated run on All. The Updated pill is already that run, so the
    /// clause would repeat the pill. No page clause on a single page.
    static func subtitle(
        shownCount: Int,
        updatedCount: Int,
        filter: AO3SubscriptionsFilter,
        currentPage: Int,
        totalPages: Int
    ) -> String {
        var line = shownCount == 1 ? "1 work" : "\(shownCount) works"
        if filter == .all, updatedCount == 1 {
            line += " · 1 with new chapters"
        } else if filter == .all, updatedCount > 1 {
            line += " · \(updatedCount) with new chapters"
        }
        if totalPages > 1 {
            line += " · page \(currentPage) of \(totalPages)"
        }
        return line
    }

    /// Page numbers are the pagination bar's, clamped the way
    /// `AO3MarkedForLaterCopy.footer` clamps them.
    static func footer(currentPage: Int, totalPages: Int) -> String {
        let pages = max(totalPages, 1)
        let page = min(max(currentPage, 1), pages)
        let noun = pages == 1 ? "page" : "pages"
        return "Subscriptions live on AO3 — unsubscribing here unsubscribes there. "
            + "Pagination follows the list: \(page) of \(pages) \(noun)."
    }
}

// MARK: - Screen

/// Subscriptions' own list inside `AO3AccountWorksList`. Other account lists
/// do not come through here.
///
/// Rows stay in a list, rather than Marked for Later's cover grid. The chapter
/// range sits under the row, and the unsubscribe swipe attaches to a row.
/// `AccountWorksCompactGrid` can do neither: it is not a list row, and it has
/// no place for a per-work line.
struct AO3SubscriptionsWorksBrowser: View {
    let entries: [CanonicalWork]
    let watermarks: [Int: SubscriptionWatermark]
    let unsubscribePaths: [Int: String]
    /// Work-page summaries keyed by work id. Empty until a row's enrichment
    /// reports one. Grouping reads these in preference to `entry.remote`.
    let enrichedSummaries: [Int: AO3WorkSummary]
    let expandAll: Bool
    let palette: SubjectPalette
    let kicker: String
    let showPagination: Bool
    let currentPage: Int
    let totalPages: Int
    let isLoading: Bool
    @Binding var filter: AO3SubscriptionsFilter
    let onPage: (Int) -> Void
    let onUnsubscribe: (CanonicalWork) -> Void
    let onEnriched: (AO3WorkSummary) -> Void

    private var sections: [AO3SubscriptionsSection<CanonicalWork>] {
        AO3SubscriptionsGrouping.sections(entries, filter: filter, isUpdated: isUpdated(_:))
    }

    private var shownCount: Int {
        sections.reduce(0) { $0 + $1.items.count }
    }

    private var updatedCount: Int {
        entries.filter(isUpdated(_:)).count
    }

    var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets(top: 20, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                AO3SubscriptionsFilterRail(selection: $filter, palette: palette)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if showPagination {
                Section { paginationBar.bareListRow() }
            }
            if sections.isEmpty {
                Section { filterEmpty.bareListRow() }
            } else {
                ForEach(sections) { section in
                    sectionBlock(section)
                }
            }
            Section { footer.bareListRow() }
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
            title: "Subscriptions",
            subtitle: AO3SubscriptionsCopy.subtitle(
                shownCount: shownCount,
                updatedCount: updatedCount,
                filter: filter,
                currentPage: currentPage,
                totalPages: totalPages
            ),
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

    private var footer: some View {
        Text(AO3SubscriptionsCopy.footer(currentPage: currentPage, totalPages: totalPages))
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
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
    private func sectionBlock(_ section: AO3SubscriptionsSection<CanonicalWork>) -> some View {
        if section.showsHeader {
            Section {
                ForEach(section.items) { entry in
                    row(entry)
                }
            } header: {
                SectionRuleHeader(title: section.group.title, count: section.items.count)
                    .textCase(nil)
                    .listRowInsets(EdgeInsets())
                    .padding(.bottom, 10)
            }
        } else {
            Section {
                ForEach(section.items) { entry in
                    row(entry)
                }
            }
        }
    }

    private func row(_ entry: CanonicalWork) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            rowBody(entry)
            if let label = chapterLabel(for: entry) {
                AO3SubscriptionsChapterFootnote(text: label)
            }
        }
        // A saved work renders `SensitiveWorkRow`, not `EnrichingAO3WorkRow`,
        // so the shared row never reports a chapter count for it. The index
        // blurb is still sparse. Ask for the work page the same way.
        .task(id: savedRowEnrichmentID(entry)) {
            await enrichSavedRow(entry)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canUnsubscribe(entry) {
                Button(role: .destructive) {
                    onUnsubscribe(entry)
                } label: {
                    Label("Unsubscribe", systemImage: "bell.slash")
                }
            }
        }
        .cardRow(tintHue: hue(for: entry))
    }

    @ViewBuilder
    private func rowBody(_ entry: CanonicalWork) -> some View {
        if let work = entry.local {
            SensitiveWorkRow(work: work, expandAll: expandAll, presentation: .ledger)
        } else if let remote = entry.remote {
            EnrichingAO3WorkRow(
                work: remote,
                expandAll: expandAll,
                presentation: .searchLedger,
                onEnriched: onEnriched
            )
        }
    }

    /// Nil for a remote-only row: `EnrichingAO3WorkRow` already reports those.
    /// A stable nil id means this task runs once and returns.
    private func savedRowEnrichmentID(_ entry: CanonicalWork) -> Int? {
        guard entry.local != nil else { return nil }
        return entry.ao3WorkID
    }

    private func enrichSavedRow(_ entry: CanonicalWork) async {
        guard entry.local != nil, let remote = entry.remote else { return }
        guard let enriched = await AO3SparseWorkEnricher.shared.enrich(remote) else { return }
        onEnriched(enriched)
    }

    private func isUpdated(_ entry: CanonicalWork) -> Bool {
        guard let work = classifyingWork(entry) else { return false }
        return AO3SubscriptionsClassification.isUpdated(work: work, watermarks: watermarks)
    }

    private func chapterLabel(for entry: CanonicalWork) -> String? {
        guard let work = classifyingWork(entry) else { return nil }
        return AO3SubscriptionsChapterRange.label(work: work, watermarks: watermarks)
    }

    private func classifyingWork(_ entry: CanonicalWork) -> AO3WorkSummary? {
        guard let remote = entry.remote else { return nil }
        return AO3SubscriptionsChapterSource.summary(
            remote: remote, enrichedSummaries: enrichedSummaries
        )
    }

    private func canUnsubscribe(_ entry: CanonicalWork) -> Bool {
        guard let id = entry.ao3WorkID else { return false }
        guard let path = unsubscribePaths[id] else { return false }
        return !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

/// The same pill row Marked for Later uses, including the quieter Reset.
struct AO3SubscriptionsFilterRail: View {
    @Binding var selection: AO3SubscriptionsFilter
    let palette: SubjectPalette

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AO3SubscriptionsFilter.allCases) { option in
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

/// Sits under an updated row, the way History's visit line does. Not part of
/// `WorkRow`: that row is every ledger in the app.
struct AO3SubscriptionsChapterFootnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
            .accessibilityLabel(text)
    }
}
