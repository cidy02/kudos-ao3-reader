import SwiftData
import SwiftUI

/// A smart queue's page: the computed matches, flat, with no add, remove, or
/// reorder. Sections belong to stored memberships (T-528) and do not apply.
struct SmartQueueWorksPage<FilterRail: View>: View {
    let queue: ReadingQueue
    let works: [SavedWork]
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
        .overlay {
            if visibleWorks.isEmpty, !works.isEmpty {
                ContentUnavailableView {
                    Label("No matching works", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Your filters don't match any works in this queue.")
                } actions: {
                    Button("Clear Filters", action: onClearFilters)
                }
            }
        }
    }

    private var smartList: some View {
        List {
            Group {
            Section {
                QueuePageHeader(
                    queue: queue,
                    works: works,
                    preservedIDs: preservedIDs,
                    palette: palette,
                    onAddTag: onAddTag,
                    onFindMore: { _ in },
                    filterRail: filterRail
                )
                .bareListRow()
                .padding(.horizontal, SubjectMetrics.gutter)
            }
            Section {
                ForEach(visibleWorks) { work in
                    SensitiveWorkRow(work: work)
                }
            }
            }
            .appThemedRows()
        }
        .cardList()
        .environment(\.defaultMinListRowHeight, 0)
    }

    private var smartGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                QueuePageHeader(
                    queue: queue,
                    works: works,
                    preservedIDs: preservedIDs,
                    palette: palette,
                    onAddTag: onAddTag,
                    onFindMore: { _ in },
                    filterRail: filterRail
                )
                .padding(.horizontal, SubjectMetrics.gutter)
                .padding(.top, 12)
                if !isNarrowed || !visibleWorks.isEmpty {
                    CarouselCardGrid {
                        ForEach(visibleWorks) { work in
                            NavigationLink(value: LocalWorkDestination.reader(work)) {
                                SensitiveWorkCoverCard(work: work)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(work.title)
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
