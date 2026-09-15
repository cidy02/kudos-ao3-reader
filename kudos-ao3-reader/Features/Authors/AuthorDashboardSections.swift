import SwiftData
import SwiftUI

/// Artboard 1y's groups, all from the dashboard HTML already used for the header.
struct AO3DashboardSections: View {
    let header: AO3AuthorHeader
    let route: AO3AuthorRoute
    let expandAll: Bool
    let onSeeAll: (AO3AuthorProfileTab) -> Void

    @Environment(AO3AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(ThemeManager.self) private var theme
    @Environment(PrivacyGate.self) private var gate
    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }) private var localWorks: [SavedWork]
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure
    @State private var expandsFandoms = false

    var body: some View {
        fandoms
        recentWorks
        recentSeries
        recentBookmarks
    }

    private var fandoms: some View {
        Group {
            SectionRuleHeader(title: "Fandoms")
                .pageBodyRow(top: 18, gutter: 0)
            if header.fandoms.isEmpty {
                message("No fandoms listed on AO3.")
            } else {
                FlowLayout(spacing: 8, rowSpacing: 4) {
                    ForEach(expandsFandoms ? header.fandoms : Array(header.fandoms.prefix(5))) { fandom in
                        Button {
                            if let url = fandom.url { router.open(url) }
                        } label: {
                            // Fandom totals are not in the account counts cache.
                            SubjectChip(text: fandom.name, style: .pill(isSelected: false))
                                .minimumHitTarget()
                        }
                        .buttonStyle(.plain)
                        .disabled(fandom.url == nil)
                    }
                    if header.fandoms.count > 5 {
                        Button { expandsFandoms.toggle() } label: {
                            SubjectChip(text: expandsFandoms ? "Collapse" : "Expand", style: .dashed)
                                .minimumHitTarget()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
            }
        }
    }

    private var recentWorks: some View {
        Group {
            heading("Recent works", tab: .works)
            if let works = header.recentWorks {
                if works.isEmpty { message("No recent works visible on AO3.") }
                ForEach(CanonicalWorkMerge.remoteLed(remote: works, localLibrary: visibleLocalWorks)) { entry in
                    AO3AuthorWorkCard(
                        entry: entry,
                        expandAll: expandAll,
                        showsPerformance: auth.username?.localizedCaseInsensitiveCompare(route.username) == .orderedSame
                    )
                }
            } else {
                message("Couldn't read recent works. Open the full list to try again.")
            }
            seeAll(.works)
        }
    }

    private var recentSeries: some View {
        Group {
            heading("Recent series", tab: .series)
            if let series = header.recentSeries {
                if series.isEmpty { message("No recent series visible on AO3.") }
                ForEach(series) { item in
                    AO3SeriesRow(series: item, presentation: .ledger)
                        .cardNavigation(to: item, accessibilityLabel: item.title)
                        .cardRow(tintHue: CoverArt.workHue(fandoms: item.fandoms, title: item.title))
                }
            } else {
                message("Couldn't read recent series. Open the full list to try again.")
            }
            seeAll(.series)
        }
    }

    private var recentBookmarks: some View {
        Group {
            heading("Recent bookmarks", tab: .bookmarks)
            if let bookmarks = header.recentBookmarks {
                if bookmarks.isEmpty { message("No recent bookmarks visible on AO3.") }
                ForEach(bookmarks) { bookmark in
                    AO3AuthorBookmarkRow(bookmark: bookmark, expandAll: expandAll, presentation: .searchLedger)
                        .cardNavigation(to: bookmark.work, accessibilityLabel: bookmark.work.title)
                        .cardRow(tintHue: CoverArt.workHue(
                            fandoms: bookmark.work.fandoms, title: bookmark.work.title
                        ))
                }
            } else {
                message("Couldn't read recent bookmarks. Open the full list to try again.")
            }
            seeAll(.bookmarks)
        }
    }

    private var visibleLocalWorks: [SavedWork] {
        localWorks.filter { !gate.isHidden($0, enabled: hideMature, mode: matureMode) }
    }

    private func heading(_ title: String, tab: AO3AuthorProfileTab) -> some View {
        SectionRuleHeader(title: title, count: count(for: tab)?.exact, onSeeAll: { onSeeAll(tab) })
            .pageBodyRow(top: 18, gutter: 0)
    }

    private func seeAll(_ tab: AO3AuthorProfileTab) -> some View {
        let parts = ["See all", count(for: tab)?.displayText, tab.rawValue.lowercased()].compactMap { $0 }
        return Button(parts.joined(separator: " ")) { onSeeAll(tab) }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(theme.scopePalette.accent)
            .minimumHitTarget()
            .pageBodyRow(top: 0, gutter: SubjectMetrics.accountGutter)
    }

    private func count(for tab: AO3AuthorProfileTab) -> AO3AccountListCount? {
        guard auth.isLoggedIn, route.pseud == nil,
              auth.username?.localizedCaseInsensitiveCompare(route.username) == .orderedSame,
              let kind = Self.listKind(for: tab) else { return nil }
        return AO3AccountListCountsCache.shared.count(
            for: kind,
            authenticationScope: AO3AuthorProfileFetcher.sessionScopedCacheScope(for: auth)
        )
    }

    static func listKind(for tab: AO3AuthorProfileTab) -> AO3AccountListKind? {
        switch tab {
        case .works: .myWorks
        case .series: .series
        case .bookmarks: .bookmarks
        case .about: nil
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .subjectPanel(cornerRadius: 16)
            .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
    }
}

/// One card for both own Works and Dashboard; keeps local navigation and privacy.
struct AO3AuthorWorkCard: View {
    let entry: CanonicalWork
    let expandAll: Bool
    var usesLedger = true
    var showsPerformance = false

    @Environment(PrivacyGate.self) private var gate
    @AppStorage("hideMatureContent") private var hideMature = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let work = entry.local {
                // SensitiveWorkRow owns its link inside the privacy boundary.
                SensitiveWorkRow(work: work, expandAll: expandAll, presentation: usesLedger ? .ledger : .standard)
                if showsPerformance, let blurb = entry.remote,
                   !hideMature || !work.isAdult || gate.isRevealed(work) {
                    AO3AuthorPerformanceStrip(work: blurb)
                }
            } else if let work = entry.remote {
                AO3WorkRow(
                    work: work,
                    expandAll: expandAll,
                    presentation: usesLedger ? .searchLedger : .standard,
                    showsPerformance: showsPerformance
                )
                .cardNavigation(to: work, accessibilityLabel: work.title)
            }
        }
        .cardRow(tintHue: usesLedger ? entry.remote.map {
            CoverArt.workHue(fandoms: $0.fandoms, title: $0.title)
        } : nil)
    }
}

struct AO3AuthorPerformanceStrip: View {
    let work: AO3WorkSummary
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        let cells = Self.cells(for: work)
        if !cells.isEmpty {
            SubjectStatStrip(
                cells: cells,
                palette: theme.appTheme.subjectPalette(
                    hue: CoverArt.workHue(fandoms: work.fandoms, title: work.title)
                )
            )
        }
    }

    /// Missing AO3 fields stay absent, never a manufactured zero.
    static func cells(for work: AO3WorkSummary) -> [SubjectStatStrip.Cell] {
        [
            work.kudos.map { SubjectStatStrip.Cell(value: $0.formatted(), label: "Kudos") },
            work.comments.map { SubjectStatStrip.Cell(value: $0.formatted(), label: "Comments") },
            work.hits.map { SubjectStatStrip.Cell(value: $0.formatted(), label: "Hits") },
            work.bookmarks.map { SubjectStatStrip.Cell(value: $0.formatted(), label: "Bookmarks") }
        ].compactMap { $0 }
    }
}
