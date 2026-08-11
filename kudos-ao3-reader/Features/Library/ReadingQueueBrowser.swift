import SwiftData
import SwiftUI

/// The browsing layer above `ReadingQueueDetailView` — a fast, chrome-light way to
/// switch between reading queues and glance/open their works. Modeled on Safari's
/// iOS tab-group switcher: a bottom queue-name pill reveals the full queue list
/// (not a top chip strip — a top strip fights the same swipe gesture space and reads
/// as "yet another segmented control" rather than a group switcher). Filters,
/// drag-reorder, the display-mode toggle, and rename/delete all stay on
/// `ReadingQueueDetailView`, reached from here via "Manage Queue" — this view never
/// duplicates them.
struct ReadingQueueBrowserView: View {
    /// Which queue to land on. `nil` falls back to the last-selected queue, or the
    /// first queue (Saved for Later) if there's no prior selection.
    var initialQueueID: UUID?

    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(ThemeManager.self) private var themeManager
    @Query(filter: #Predicate<ReadingQueue> { !$0.isPendingDeletion }, sort: \ReadingQueue.sortOrder)
    private var allQueues: [ReadingQueue]

    /// Persists the last-open queue across visits to this screen, independent of
    /// which queue a Library carousel tap pre-selected this time.
    @AppStorage("library.readingQueueBrowser.lastSelectedID") private var lastSelectedIDRaw = ""
    @State private var selectedQueueID: UUID?
    @State private var showingSwitcher = false
    @State private var showingNewQueue = false
    @State private var newQueueName = ""
    var cardSize = ScaledCarouselCardSize()

    /// Saved for Later first (it's always present, even with zero custom queues),
    /// then customs by `sortOrder` — the same ordering `AddToQueueView` already uses.
    private var orderedQueues: [ReadingQueue] {
        allQueues.sorted {
            if $0.kind != $1.kind { return $0.kind == .savedForLater }
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.displayName < $1.displayName
        }
    }

    private var selectedQueue: ReadingQueue? {
        guard let selectedQueueID else { return orderedQueues.first }
        return orderedQueues.first { $0.id == selectedQueueID } ?? orderedQueues.first
    }

    private var works: [SavedWork] {
        selectedQueue.map(ReadingQueueService.orderedWorks(in:)) ?? []
    }

    private var gridColumns: [GridItem] {
        CarouselCardMetrics.adaptiveCardColumns(minimum: cardSize.width)
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .background((themeManager.appTheme.appBaseBackground ?? Color.clear).ignoresSafeArea())
        .navigationTitle(
            horizontalSizeClass == .regular
                ? "Reading Queues"
                : (selectedQueue?.displayName ?? "Reading Queues")
        )
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .onAppear(perform: resolveInitialSelection)
            .alert("New Queue", isPresented: $showingNewQueue) {
                TextField("Name", text: $newQueueName)
                Button("Add", action: createQueue)
                Button("Cancel", role: .cancel) { newQueueName = "" }
            }
    }

    // MARK: - Compact (iPhone): bottom switcher pill

    private var compactLayout: some View {
        pageContent
            .safeAreaInset(edge: .bottom) { switcherBar }
            .toolbar {
                ToolbarItem(placement: .primaryAction) { manageButton }
            }
            // The switcher bar is this screen's own bottom chrome — the app's tab bar
            // (and floating search glass) underneath it is redundant and doubles up
            // the bottom edge. Same pattern LibraryView's selection mode already uses.
            #if os(iOS)
            .toolbar(.hidden, for: .tabBar)
            #endif
    }

    // Three independently-floating glass elements with gaps between them (matching
    // Safari's own tab-group bar, and this app's existing ReaderChromeTopBar
    // convention) — not one flat, edge-to-edge toolbar strip. Each button gets its
    // own .glassEffect() rather than a shared .background(.bar).
    private var switcherBar: some View {
        HStack(spacing: 10) {
            Button { showingSwitcher = true } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .accessibilityLabel("All Queues")

            Button { showingSwitcher = true } label: {
                HStack(spacing: 6) {
                    queueGlyph(selectedQueue)
                    Text(selectedQueue?.displayName ?? "Reading Queues")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.up")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
            .contentShape(.capsule)
            .accessibilityLabel("Switch Reading Queue")
            .accessibilityValue(selectedQueue?.displayName ?? "No queue selected")

            Button {
                newQueueName = ""
                showingNewQueue = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .accessibilityLabel("New Queue")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .popover(isPresented: $showingSwitcher, arrowEdge: .bottom) {
            switcherList
                .presentationCompactAdaptation(.sheet)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Regular (iPad/Mac): persistent leading sidebar

    private var regularLayout: some View {
        HStack(spacing: 0) {
            List {
                ForEach(orderedQueues) { queue in
                    queueRow(queue)
                }
                .appThemedRows()
                Button {
                    newQueueName = ""
                    showingNewQueue = true
                } label: {
                    Label("New Queue", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .appThemedRows()
            }
            .listStyle(.sidebar)
            .appThemedScroll()
            .frame(width: 240)

            Divider()

            VStack(spacing: 0) {
                HStack {
                    Text(selectedQueue?.displayName ?? "Reading Queues")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    manageButton
                }
                .padding([.horizontal, .top], 20)
                .padding(.bottom, 8)
                pageContent
            }
        }
    }

    // MARK: - Shared: queue switcher list + queue row

    private var switcherList: some View {
        List {
            ForEach(orderedQueues) { queue in
                queueRow(queue)
            }
            .appThemedRows()
        }
        .listStyle(.plain)
        .appThemedScroll()
    }

    private func queueRow(_ queue: ReadingQueue) -> some View {
        let workCount = ReadingQueueService.orderedWorks(in: queue).count
        let isSelected = queue.id == selectedQueue?.id
        return Button { select(queue) } label: {
            HStack(spacing: 10) {
                queueGlyph(queue)
                Text(queue.displayName)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(workCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue("\(workCount) work\(workCount == 1 ? "" : "s")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func queueGlyph(_ queue: ReadingQueue?) -> some View {
        if let queue, queue.kind != .savedForLater {
            Circle()
                .fill(themeManager.appTheme.carouselQueueTint(hue: CoverArt.hue(for: queue.displayName)))
                .frame(width: 10, height: 10)
        } else {
            Image(systemName: "bookmark.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Shared: active queue page (native work-card grid)

    private var pageContent: some View {
        Group {
            if let selectedQueue, works.isEmpty {
                ContentUnavailableView {
                    Label(
                        selectedQueue.displayName,
                        systemImage: selectedQueue.kind == .savedForLater
                            ? "bookmark"
                            : "list.bullet.rectangle"
                    )
                } description: {
                    Text("Works you add to this queue will keep a local EPUB for offline reading.")
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 16) {
                        ForEach(works) { work in
                            pageCard(work)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func pageCard(_ work: SavedWork) -> some View {
        let membershipCount = work.queueMemberships.filter { membership in
            guard let queue = membership.queue else { return false }
            return !membership.isPendingDeletion && !queue.isPendingDeletion
        }.count
        return NavigationLink(value: LocalWorkDestination.reader(work)) {
            ZStack(alignment: .topTrailing) {
                SensitiveWorkCoverCard(work: work)
                if membershipCount > 1 {
                    Text("In \(membershipCount)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.regularMaterial, in: Capsule())
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
        .localWorkContextMenu(work: work)
    }

    // MARK: - Manage Queue

    @ViewBuilder
    private var manageButton: some View {
        if let selectedQueue {
            NavigationLink(value: selectedQueue) {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Manage Queue")
        }
    }

    // MARK: - Actions

    private func resolveInitialSelection() {
        ReadingQueueService.ensureSavedForLaterQueue(in: context)
        guard selectedQueueID == nil else { return }
        if let initialQueueID {
            selectedQueueID = initialQueueID
            lastSelectedIDRaw = initialQueueID.uuidString
        } else {
            if let saved = UUID(uuidString: lastSelectedIDRaw), orderedQueues.contains(where: { $0.id == saved }) {
                selectedQueueID = saved
            } else {
                selectedQueueID = orderedQueues.first?.id
            }
        }
    }

    private func select(_ queue: ReadingQueue) {
        selectedQueueID = queue.id
        lastSelectedIDRaw = queue.id.uuidString
        showingSwitcher = false
    }

    private func createQueue() {
        let trimmed = newQueueName.trimmingCharacters(in: .whitespacesAndNewlines)
        newQueueName = ""
        guard !trimmed.isEmpty else { return }
        let queue = ReadingQueueService.createQueue(named: trimmed, in: context)
        select(queue)
    }
}
