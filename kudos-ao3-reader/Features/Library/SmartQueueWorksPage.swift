import SwiftData
import SwiftUI

/// A smart queue's page: the computed matches, flat, with no add, remove, or
/// reorder. Sections belong to stored memberships (T-528) and do not apply.
struct SmartQueueWorksPage<FilterRail: View>: View {
    let queue: ReadingQueue
    let works: [SavedWork]
    /// What the header counts: the visible list before quick filters.
    let headerWorks: [SavedWork]
    let visibleWorks: [SavedWork]
    let preservedIDs: Set<UUID>
    let palette: SubjectPalette
    let arrangement: WorkListArrangement
    let isNarrowed: Bool
    let onClearFilters: () -> Void
    let onEditRules: () -> Void
    let onAddTag: () -> Void
    @ViewBuilder var filterRail: () -> FilterRail

    @Environment(\.modelContext) private var context
    @Environment(AO3AuthService.self) private var auth
    @Environment(PrivacyGate.self) private var gate
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        Group {
            if works.isEmpty {
                ContentUnavailableView {
                    Label(queue.displayName, systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text(
                        "This queue fills itself from your library. "
                            + "A work appears when it matches, and leaves when it stops."
                    )
                } actions: {
                    Button("Edit Rules", action: onEditRules)
                        .accessibilityLabel("Edit Rules")
                }
            } else if arrangement == .grid {
                smartGrid
            } else {
                smartList
            }
        }
        .refreshable {
            let task = Task { _ = await WorkMetadataRefresh.refresh(visibleWorks, in: context, auth: auth) }
            refreshTask = task
            await task.value
        }
        .cancelRefreshOnTabChange($refreshTask)
    }

    @ViewBuilder
    private var emptyVisibleState: some View {
        if isNarrowed {
            ContentUnavailableView {
                Label("No matching works", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Your filters don't match any works in this queue.")
            } actions: {
                Button("Clear Filters", action: onClearFilters)
            }
        } else {
            ContentUnavailableView {
                Label("Mature works are hidden", systemImage: "eye.slash")
            } description: {
                Text("Hide Mature is hiding the works in this queue.")
            } actions: {
                MatureRevealToggle()
            }
        }
    }

    private var smartList: some View {
        List {
            Section {
                QueuePageHeader(
                    queue: queue,
                    works: headerWorks,
                    preservedIDs: preservedIDs,
                    palette: palette,
                    onAddTag: onAddTag,
                    onOpenSource: { _ in },
                    onManageSources: {},
                    onRemoveSource: { _ in },
                    filterRail: filterRail
                )
                .bareListRow()
                .padding(.horizontal, SubjectMetrics.gutter)
                .padding(.top, 16)
                .padding(.bottom, 8)
            }
            Section {
                if visibleWorks.isEmpty {
                    emptyVisibleState
                        .bareListRow()
                } else {
                    ForEach(visibleWorks) { work in
                        SensitiveWorkRow(
                            work: work,
                            openMode: .reader,
                            presentation: .ledger,
                            showsFavoriteStar: true,
                            showsFullLedgerStats: true,
                            showsSummary: false
                        )
                        .cardRow(isSelected: false, chrome: .plain)
                    }
                }
            }
        }
        .cardList()
        .environment(\.defaultMinListRowHeight, 0)
    }

    private var smartGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                QueuePageHeader(
                    queue: queue,
                    works: headerWorks,
                    preservedIDs: preservedIDs,
                    palette: palette,
                    onAddTag: onAddTag,
                    onOpenSource: { _ in },
                    onManageSources: {},
                    onRemoveSource: { _ in },
                    filterRail: filterRail
                )
                .padding(.horizontal, SubjectMetrics.gutter)
                .padding(.top, 16)
                .padding(.bottom, 8)
                if visibleWorks.isEmpty {
                    emptyVisibleState
                        .padding(.top, 16)
                } else {
                    CarouselCardGrid {
                        ForEach(visibleWorks) { work in
                            if gate.isBlurred(work, enabled: hideMature, mode: matureMode) {
                                SensitiveWorkCoverCard(work: work)
                            } else {
                                NavigationLink(value: LocalWorkDestination.reader(work)) {
                                    SensitiveWorkCoverCard(work: work)
                                }
                                .buttonStyle(.plain)
                                .localWorkContextMenu(work: work)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                }
            }
            .padding(.bottom, 16)
        }
        .appThemedScroll()
    }
}
