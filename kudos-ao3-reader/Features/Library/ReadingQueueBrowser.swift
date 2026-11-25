import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Single Reading Queue screen: Safari-style queue switcher + the full manage
/// surface (filters, reorder, select, display mode, rename/delete) for the
/// active queue. There is no separate "Manage Queue" page — that used to live
/// in `ReadingQueueDetailView`, which is now a thin redirect here.
struct ReadingQueueBrowserView: View {
    /// Which queue to land on. `nil` falls back to the last-selected queue, or the
    /// first queue (Saved for Later) if there's no prior selection.
    var initialQueueID: UUID?
    /// The tab this was opened from, for the kicker: Home's stack passes "Home",
    /// the way `LibrarySectionRoute` carries its origin.
    var originKicker = "Library"

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accentInk) private var accentInk
    @Environment(\.accentFill) private var accentFill
    @Environment(\.duoLayout) private var duoLayout
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure
    @Environment(PrivacyGate.self) private var gate
    @Environment(ThemeManager.self) var themeManager
    @Environment(AO3AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<ReadingQueue> { !$0.isPendingDeletion }, sort: \ReadingQueue.sortOrder)
    private var allQueues: [ReadingQueue]
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion })
    private var libraryWorks: [SavedWork]
    @Query private var tagAliases: [TagAlias]

    /// Persists the last-open queue across visits to this screen, independent of
    /// which queue a Library carousel tap pre-selected this time.
    @AppStorage("library.readingQueueBrowser.lastSelectedID") private var lastSelectedIDRaw = ""
    @State private var selectedQueueID: UUID?
    @State var showingNewQueue = false
    @State var newQueueName = ""
    /// 1j's colour swatch for the queue being created. `nil` keeps the
    /// name-derived hue.
    @State var newQueueHue: Double?

    // MARK: Manage-surface state (formerly ReadingQueueDetailView)

    @State private var showingEdit = false
    @State private var confirmDelete = false
    /// A row's Remove from Queue waits here for the same confirmation a
    /// collection row and the queue's bulk Remove already ask.
    @State private var pendingRemoval: SavedWork?
    /// Pushes artboard 1h's "Queue details" screen — a restyle of what this
    /// screen's own overflow menu already does (rename, delete, see what's
    /// preserved), not a new destination's worth of new data.
    @State private var showingQueueDetails = false
    @State private var filters = LibraryFilters()
    @State private var showingFilters = false
    /// 1h's All · Unread · Offline · WIP, applied before `filters`.
    @State private var quickFilter: QueueQuickFilter = .all
    @State private var showingQueueTags = false
    /// 1h's "+": the Library picker (`AddLibraryWorksSheet`).
    @State private var showingAddWorks = false
    /// List is the default. A stored Compact on this queue becomes Grid.
    /// `ReadingQueue` has no field for it, so it lives in UserDefaults under
    /// the queue's id, loaded when the selected queue changes.
    @State private var arrangement: WorkListArrangement = .list

    @State private var isReordering = false
    @State private var refreshTask: Task<Void, Never>?
    @State private var sourcePages: [UUID: QueueSourceFetchedPage] = [:]
    @State private var sourceCheckTask: Task<Void, Never>?
    @State private var sourceCheckQueueID: UUID?
    @State private var sourceOpeningTab: AppTab?
    @State private var isPageVisible = false
    @State private var showingSources = false
    @State private var pendingSourceToOpen: QueueSavedSearchLink?
    @State private var openedAuthorSource: OpenedQueueAuthorSource?
    @State private var openedSeriesSource: OpenedQueueSeriesSource?
    @State private var openedTagSource: OpenedQueueTagSource?
    @State private var draggedWorkID: UUID?
    @State private var pendingCompactOrder: [UUID]?
    @State private var isSelecting = false
    @State private var selection = Set<UUID>()
    /// `Finished` starts collapsed on queue load and queue switch (`T-528`).
    @State private var isFinishedExpanded = false
    /// Start and Read Aloud on the Up next Resume card push the reader.
    @State private var readerDestination: LocalWorkDestination?
    /// T-529: the New section's Sort opens Sort New over the queue page.
    @State private var sortNewRequest: QueueSortNewRequest?

    /// Saved for Later first, then user queues (list and smart) by `sortOrder`.
    static func orderedQueues(from queues: [ReadingQueue]) -> [ReadingQueue] {
        queues.sorted {
            if $0.isUserQueue != $1.isUserQueue { return !$0.isUserQueue }
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.displayName < $1.displayName
        }
    }

    /// Saved for Later first, then user queues (list and smart) by `sortOrder`.
    var orderedQueues: [ReadingQueue] {
        Self.orderedQueues(from: allQueues)
    }

    /// Falls through to `initialQueueID` before `orderedQueues.first`: `selectedQueueID`
    /// itself isn't written until `resolveInitialSelection()` runs on `.onAppear`, which
    /// is after the first body evaluation. Without this fallback, a push straight into a
    /// specific queue (e.g. tapping a queue card on Home) rendered "Saved for Later" (or
    /// whatever sorts first) for the view's first frame, then swapped to the real target
    /// a beat later — a full ContentUnavailableView/grid + title structural change lands
    /// mid-push-transition, competing with the tab bar's own hide animation for the main
    /// thread. That's what was surfacing as the tab bar lingering after the switcher pill
    /// had already settled, independent of how the switcher pill itself is positioned.
    var selectedQueue: ReadingQueue? {
        let targetID = selectedQueueID ?? initialQueueID
        guard let targetID else { return orderedQueues.first }
        return orderedQueues.first { $0.id == targetID } ?? orderedQueues.first
    }

    private var orderedMemberships: [ReadingQueueMembership] {
        selectedQueue.map(ReadingQueueService.orderedMemberships(in:)) ?? []
    }

    private var needsSmartSnapshot: Bool {
        selectedQueue?.kind == .smart
            || (horizontalSizeClass == .regular && allQueues.contains { $0.kind == .smart })
    }

    private func makeSmartSnapshot() -> ReadingQueueService.SmartLibrarySnapshot? {
        guard needsSmartSnapshot else { return nil }
        return ReadingQueueService.SmartLibrarySnapshot(
            works: libraryWorks,
            aliases: TagAliasResolver(models: tagAliases)
        )
    }

    private func resolvedWorks(snapshot: ReadingQueueService.SmartLibrarySnapshot?) -> [SavedWork] {
        guard let selectedQueue else { return [] }
        if selectedQueue.kind == .smart {
            return snapshot?.matching(selectedQueue) ?? []
        }
        return orderedMemberships.compactMap(\.work)
    }

    /// Applies Hide Mature before `limit` on smart queues so hidden mature works
    /// cannot consume limit slots and drop visible matches.
    private func resolvedSmartUnfilteredVisible(
        allMatched: [SavedWork],
        snapshot: ReadingQueueService.SmartLibrarySnapshot?
    ) -> [SavedWork] {
        guard let selectedQueue, selectedQueue.kind == .smart else { return [] }
        guard hideMature, matureMode == .hide, let snapshot else { return allMatched }
        return snapshot.matching(selectedQueue) {
            !gate.isHidden($0, enabled: hideMature, mode: matureMode)
        }
    }

    private func resolvedSmartVisible(unfilteredVisible: [SavedWork]) -> [SavedWork] {
        guard quickFilter != .all || filters.hasActiveFilters else { return unfilteredVisible }
        // From the visible list: a downloaded visible work that hidden matches
        // pushed past the unfiltered limit is still offline.
        let preservedIDs = Set(
            unfilteredVisible
                .filter { $0.hasEPUB && FileManager.default.fileExists(atPath: $0.fileURL.path) }
                .map(\.id)
        )
        let quick = quickFilter.apply(to: unfilteredVisible, preservedIDs: preservedIDs)
        return filters.hasActiveFilters ? filters.apply(to: quick) : quick
    }

    private var works: [SavedWork] {
        resolvedWorks(snapshot: makeSmartSnapshot())
    }

    /// Hide mode drops Mature/Explicit works here, as every other works list
    /// does — the row wrappers only blur, they never remove.
    private var visibleMemberships: [ReadingQueueMembership] {
        let shown = orderedMemberships.filter { membership in
            guard let work = membership.work else { return false }
            return !gate.isHidden(work, enabled: hideMature, mode: matureMode)
        }
        guard quickFilter != .all || filters.hasActiveFilters else { return shown }
        let shownWorks = shown.compactMap(\.work)
        let quick = quickFilter.apply(to: shownWorks, preservedIDs: Set(preservedWorks.map(\.id)))
        let filtered = filters.hasActiveFilters ? filters.apply(to: quick) : quick
        let allowedIDs = Set(filtered.map(\.id))
        return shown.filter { membership in
            membership.work.map { allowedIDs.contains($0.id) } ?? false
        }
    }

    private var visibleWorks: [SavedWork] {
        if selectedQueue?.kind == .smart {
            let shown = works.filter { !gate.isHidden($0, enabled: hideMature, mode: matureMode) }
            guard quickFilter != .all || filters.hasActiveFilters else { return shown }
            let quick = quickFilter.apply(to: shown, preservedIDs: Set(preservedWorks.map(\.id)))
            return filters.hasActiveFilters ? filters.apply(to: quick) : quick
        }
        return visibleMemberships.compactMap(\.work)
    }

    private var wholePartition: ReadingQueueSectionPartition {
        ReadingQueueFacts.partition(memberships: orderedMemberships)
    }

    private var visiblePartition: ReadingQueueSectionPartition {
        ReadingQueueFacts.partition(memberships: visibleMemberships)
    }

    private var reorderedInLineWorks: [SavedWork] {
        wholePartition.inLineAll.map(\.work)
    }

    private var trailingReorderIDs: [UUID] {
        (wholePartition.new + wholePartition.waiting + wholePartition.finished).map(\.work.id)
    }

    /// Reorder needs the whole queue in order, so any narrowing blocks it.
    private var isNarrowed: Bool {
        filters.hasActiveFilters || quickFilter != .all
    }

    /// Reorder draws every work in the queue; while Hide mode is keeping some
    /// out of sight, it would put them back on screen.
    private var hidesMatureWorks: Bool {
        works.contains { gate.isHidden($0, enabled: hideMature, mode: matureMode) }
    }

    /// 1bg: selecting keeps the drag handle live, so select and reorder are
    /// no longer exclusive states. See `ReadingQueueFacts.isDragLive`.
    /// Hidden mature works count as narrowing: the drag maps visible rows onto
    /// the full order, so with any work hidden it would move the wrong one and
    /// its preview would show the hidden ones (L3 B2 #2).
    private var isDragLive: Bool {
        ReadingQueueFacts.isDragLive(
            isReordering: isReordering,
            isSelecting: isSelecting,
            isNarrowed: isNarrowed || hidesMatureWorks
        )
    }

    /// While reordering, filters step aside — move/drag operate on `In line` only
    /// (`T-528`: New sorts into line via action; Waiting and Finished are derived).
    private var displayedWorks: [SavedWork] {
        (isReordering && !isSelecting) ? reorderedInLineWorks : visibleWorks
    }

    private var compactInLineWorks: [SavedWork] {
        guard let pendingCompactOrder else { return reorderedInLineWorks }
        let byID = Dictionary(reorderedInLineWorks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return pendingCompactOrder.compactMap { byID[$0] }
    }

    /// Selection acts on what is on screen: Select hides the filter rail, so a
    /// filtered-out or hidden work must never be removed, moved, tagged or
    /// downloaded unseen (L3 B2 #1).
    private var selectedWorks: [SavedWork] {
        displayedWorks.filter { selection.contains($0.id) }
    }

    private var allSelected: Bool {
        let ids = Set(displayedWorks.map(\.id))
        return !ids.isEmpty && ids.isSubset(of: selection)
    }

    // MARK: - Subject language (artboard 1h)

    /// A queue's identity colour, matching `queueGlyph`'s dot and
    /// `ReadingQueueCard`'s carousel tint: `ReadingQueue` has no stored colour
    /// field, so the app already derives one consistently from the name via
    /// `CoverArt.hue` — that derived hue *is* this queue's "stored colour" for
    /// every purpose the app has one today, and is what artboard 1h's palette
    /// comes from.
    private var subjectPalette: SubjectPalette {
        guard let selectedQueue else { return themeManager.scopePalette }
        return themeManager.appTheme.subjectPalette(hue: selectedQueue.displayHue, pickedHex: selectedQueue.colorHex)
    }

    private var preservedWorks: [SavedWork] {
        works.filter { $0.hasEPUB && FileManager.default.fileExists(atPath: $0.fileURL.path) }
    }

    private var preservedByteCount: Int64 {
        preservedWorks.reduce(0) { $0 + queueWorkFileSize($1.fileURL) }
    }

    /// The Library's active-filter labels, drawn only while `LibraryFilters` is
    /// narrowing the queue — 1h's own quick filters (`QueueQuickFilter`) are
    /// the everyday rail, and the toolbar's Filter button opens the panel.
    private var filterChipRail: some View {
        SubjectFilterRail {
            if quickFilter != .all {
                Button {
                    quickFilter = .all
                } label: {
                    SubjectChip(
                        text: quickFilter.title,
                        style: .tinted,
                        systemImage: "xmark",
                        palette: subjectPalette
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(quickFilter.title) filter")
            }
            ForEach(filters.summaryLabels(), id: \.self) { label in
                SubjectChip(
                    text: label.text,
                    style: .tinted,
                    systemImage: label.symbol,
                    palette: subjectPalette
                )
            }
        }
    }

    /// Spec 1h splits a queue into "Up next" and "In line" (everything else,
    /// in the queue's own `sortOrderInQueue` order). Up next is Home's card
    /// face too: `ReadingQueueFacts.upNext`, the first work not yet finished.
    /// Both use `visibleWorks` (filters applied) rather than `displayedWorks`,
    /// since that split only ever renders while `!isReordering`.
    private var upNextEntry: ReadingQueueSectionEntry? {
        visiblePartition.upNext
    }

    private var upNextWork: SavedWork? { upNextEntry?.work }

    private var inLineEntries: [ReadingQueueSectionEntry] {
        visiblePartition.inLineRest
    }

    /// 1h's numbered In line rows: the work's place within `In line`, so filtering
    /// narrows the list without renumbering it.
    private func queuePosition(of work: SavedWork) -> Int? {
        wholePartition.inLineAll.firstIndex { $0.id == work.id }.map { $0 + 1 }
    }

    /// The Resume card's next variant. Start opens the reader. A tap on the
    /// rest of the card does too: the list uses `cardNavigation`, the same
    /// call the old Up next row used, and the compact grid (a scroll view,
    /// where that background link never fires) uses a `NavigationLink` to the
    /// same destination. A blurred mature work keeps its reveal tap only.
    /// While selecting, neither link is there: the tap only toggles, and
    /// VoiceOver is not offered an "open".
    @ViewBuilder
    private func upNextLinked(_ entry: ReadingQueueSectionEntry) -> some View {
        let work = entry.work
        VStack(alignment: .leading, spacing: 6) {
            if isSelecting || gate.isBlurred(work, enabled: hideMature, mode: matureMode) {
                upNextResume(entry)
            } else {
                upNextResume(entry)
                    .cardNavigation(
                        to: LocalWorkDestination.reader(work),
                        accessibilityLabel: work.title
                    )
            }
            if !gate.isBlurred(work, enabled: hideMature, mode: matureMode),
               entry.hasNewChapter || entry.originDisplayLine != nil {
                queueAnnotationLine(
                    hasNewChapter: entry.hasNewChapter,
                    originLine: entry.originDisplayLine
                )
                .padding(.horizontal, SubjectMetrics.gutter)
            }
        }
    }

    @ViewBuilder
    private func upNextCompact(_ entry: ReadingQueueSectionEntry) -> some View {
        let work = entry.work
        let card = VStack(alignment: .leading, spacing: 6) {
            upNextResume(entry)
            if !gate.isBlurred(work, enabled: hideMature, mode: matureMode),
               entry.hasNewChapter || entry.originDisplayLine != nil {
                queueAnnotationLine(
                    hasNewChapter: entry.hasNewChapter,
                    originLine: entry.originDisplayLine
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, Self.afterRule)
        if isSelecting || gate.isBlurred(work, enabled: hideMature, mode: matureMode) {
            card
        } else {
            NavigationLink(value: LocalWorkDestination.reader(work)) {
                card
            }
            .buttonStyle(.plain)
        }
    }

    /// The Resume card's next variant. Start opens the reader.
    /// Remove, move and the rest of the row menu stay on the card.
    private func upNextResume(_ entry: ReadingQueueSectionEntry) -> some View {
        let work = entry.work
        return HomeResumeHero(
            work: work,
            variant: .next,
            isSelecting: isSelecting,
            isSelected: selection.contains(work.id),
            onToggleSelection: { toggleSelection(work) },
            onPrimary: { readerDestination = .reader(work) },
            onReadAloud: { readerDestination = .readerReadAloud(work) },
            scopedRemoval: ScopedRemoval(title: "Remove from Queue") {
                pendingRemoval = work
            },
            queueMenu: queueMenu(for: entry),
            showsVariantLabel: false
        )
    }

    /// Ledger row for any section (`New`, `In line`, `Waiting`, `Finished`).
    /// Keeps full AO3 metadata intact while adding `"New chapter"` and `"From <label>"`
    /// beneath the row when present and unblurred.
    private func ledgerRow(
        _ entry: ReadingQueueSectionEntry,
        position: Int? = nil,
        presentation: WorkRow.Presentation? = nil
    ) -> some View {
        let work = entry.work
        let isBlurred = gate.isBlurred(work, enabled: hideMature, mode: matureMode)
        let hasFootnote = !isBlurred && (entry.hasNewChapter || entry.originDisplayLine != nil)
        return VStack(alignment: .leading, spacing: 0) {
            SensitiveWorkRow(
                work: work,
                openMode: .reader,
                isSelecting: isSelecting,
                isSelected: selection.contains(work.id),
                onToggleSelection: { toggleSelection(work) },
                presentation: presentation ?? .ledger,
                showsFavoriteStar: true,
                showsFullLedgerStats: true,
                showsSummary: false,
                showsSeparator: !hasFootnote,
                queueMenu: queueMenu(for: entry)
            )
            if hasFootnote {
                queueAnnotationLine(
                    hasNewChapter: entry.hasNewChapter,
                    originLine: entry.originDisplayLine
                )
                .padding(.horizontal, WorkRowMetrics.horizontalPadding)
                .padding(.bottom, 10)
                WorkRowSeparator(
                    inset: WorkRow.separatorInset(isSelecting: isSelecting),
                    selecting: isSelecting
                )
            }
        }
        .swipeActions(edge: .leading) {
            if !isSelecting {
                if entry.section == .new, let queue = selectedQueue {
                    Button {
                        Haptics.selection()
                        ReadingQueueService.sortIntoLine(entry.membership, in: queue, context: context)
                    } label: {
                        Label("Sort into line", systemImage: "text.insert")
                    }
                    .tint(accentFill)
                } else if entry.section == .inLine {
                    Button {
                        moveWork(work, toIndex: 0, requireDragLive: false)
                    } label: {
                        Label("Read Next", systemImage: "arrow.up.to.line")
                    }
                    .tint(.accentColor)
                }
            }
        }
        .swipeActions(edge: .trailing) {
            if !isSelecting {
                Button(role: .destructive) {
                    pendingRemoval = work
                } label: {
                    Label("Remove", systemImage: "minus.circle")
                }
            }
        }
        .modifier(SortIntoLineAccessibilityModifier(
            enabled: !isSelecting && !isReordering && entry.section == .new
        ) {
            guard let queue = selectedQueue else { return }
            Haptics.selection()
            ReadingQueueService.sortIntoLine(entry.membership, in: queue, context: context)
        })
        .cardRow(
            isSelected: isSelecting && selection.contains(work.id),
            leadingNumber: position,
            chrome: .plain
        )
        // The number is drawn in the row's background, outside the card.
        .accessibilityValue(position.map { "Position \($0)" } ?? "")
    }

    @ViewBuilder
    private func queueAnnotationLine(hasNewChapter: Bool, originLine: String?) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                if hasNewChapter {
                    UpdateMarker(text: "New chapter", spokenLabel: "New chapter", wraps: true)
                }
                if let originLine {
                    Text(originLine)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if hasNewChapter {
                    UpdateMarker(text: "New chapter", spokenLabel: "New chapter", wraps: true)
                }
                if let originLine {
                    Text(originLine)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var queueInlineTitle: String {
        #if os(macOS)
        if horizontalSizeClass == .regular { return "Reading Queues" }
        #endif
        return selectedQueue?.displayName ?? "Reading Queues"
    }

    private func queueOverrideInlineTitle(worksEmpty: Bool) -> String? {
        if isSelecting { return "\(selectedWorks.count) selected" }
        if isReordering || worksEmpty { return queueInlineTitle }
        return nil
    }

    // MARK: - Body

    var body: some View {
        let snapshot = makeSmartSnapshot()
        let currentWorks = resolvedWorks(snapshot: snapshot)
        let smartUnfilteredVisible = resolvedSmartUnfilteredVisible(
            allMatched: currentWorks,
            snapshot: snapshot
        )
        let smartVisible = resolvedSmartVisible(unfilteredVisible: smartUnfilteredVisible)
        let showsOwnHeading = !currentWorks.isEmpty || (selectedQueue?.hasVisibleSources == true)
        Group {
            if horizontalSizeClass == .regular {
                regularLayout(
                    snapshot: snapshot,
                    works: currentWorks,
                    smartVisible: smartVisible,
                    smartHeader: smartUnfilteredVisible
                )
            } else {
                compactLayout(works: currentWorks, smartVisible: smartVisible, smartHeader: smartUnfilteredVisible)
            }
        }
        .background((themeManager.appTheme.appBaseBackground ?? Color.clear).ignoresSafeArea())
        .subjectOwnHeadingChrome(
            title: queueInlineTitle,
            overrideInlineTitle: queueOverrideInlineTitle(worksEmpty: !showsOwnHeading),
            isActive: showsOwnHeading && !isReordering
        )
            .onAppear {
                isPageVisible = true
                resolveInitialSelection()
                sourceOpeningTab = router.selection
                startSourceCheck()
                #if DEBUG
                if DebugLaunchRoute.opensQueueDetails { showingQueueDetails = true }
                if DebugLaunchRoute.takeSheet("editqueue") { showingEdit = true }
                if DebugLaunchRoute.takeSheet("queuesources") { showingSources = true }
                if DebugLaunchRoute.takeSheet("addworks") { showingAddWorks = true }
                if DebugLaunchRoute.takeSheet("sortnew"), let queue = selectedQueue {
                    // The demo queues hold no New works, so the shot sorts every
                    // visible work in the queue; a real launch only ever sorts New.
                    let new = visiblePartition.new.map(\.membership.id)
                    sortNewRequest = QueueSortNewRequest(
                        queueID: queue.id,
                        membershipIDs: new.isEmpty ? visibleMemberships.map(\.id) : new,
                        requiresNewState: !new.isEmpty
                    )
                }
                #endif
            }
            .onChange(of: selectedQueue?.id) { _, _ in
                sourcePages = [:]
                startSourceCheck()
            }
            .onChange(of: router.selection) { _, tab in
                if tab != sourceOpeningTab {
                    sourceCheckTask?.cancel()
                    sourceCheckQueueID = nil
                } else {
                    startSourceCheck()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    sourceCheckTask?.cancel()
                    sourceCheckQueueID = nil
                } else {
                    startSourceCheck()
                }
            }
            .onDisappear {
                isPageVisible = false
                sourceCheckTask?.cancel()
                sourceCheckQueueID = nil
            }
            // Per-queue List / Grid. A missing key is List. Compact stored on the
            // old key becomes Grid, once, and that old key stays.
            .onChange(of: selectedQueue?.id, initial: true) { _, id in
                guard let id else { return }
                arrangement = WorkListLayoutMigration.resolve(
                    arrangementKey: WorkListKeys.queueArrangement(id),
                    legacyDisplayModeKey: WorkListKeys.queueDisplayMode(id)
                )
            }
            .onChange(of: arrangement) { _, arrangement in
                guard let id = selectedQueue?.id else { return }
                UserDefaults.standard.set(arrangement.rawValue, forKey: WorkListKeys.queueArrangement(id))
            }
            .sheet(isPresented: $showingNewQueue) { newQueueSheet }
            .sheet(isPresented: $showingQueueTags) {
                if let selectedQueue { QueueTagSheet(queue: selectedQueue) }
            }
            .sheet(isPresented: $showingAddWorks) {
                addWorksSheet
                #if os(iOS)
                    .modifier(ScopeSurfaceAccent())
                #endif
            }
            #if os(iOS)
            .fullScreenCover(item: $sortNewRequest) { request in
                sortNewView(request)
                    .modifier(ScopeSurfaceAccent())
            }
            #else
            .sheet(item: $sortNewRequest) { request in
                sortNewView(request)
                    .frame(minWidth: 420, minHeight: 640)
            }
            #endif
            .navigationDestination(item: $readerDestination) { destination in
                LocalWorkDestinationView(destination: destination)
            }
            .navigationDestination(isPresented: $showingQueueDetails) {
                if let selectedQueue {
                    ReadingQueueSettingsView(
                        queue: selectedQueue,
                        originKicker: originKicker,
                        // 1bh: "closes the sheet and filters the queue".
                        onShowOnlyTag: { tag in
                            filters.userTags = [tag.name]
                            showingQueueDetails = false
                        }
                    )
                }
            }
            .filterPanelPresentation(isPresented: $showingFilters) {
                LibraryFilterPanel(
                    filters: $filters,
                    works: selectedQueue?.kind == .smart ? smartUnfilteredVisible : currentWorks,
                    userTagNames: allTags.map(\.name)
                )
                .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
            }
            .toolbar { manageToolbar(worksEmpty: currentWorks.isEmpty) }
            .sheet(isPresented: $showingEdit) {
                if let selectedQueue {
                    EditReadingQueueSheet(queue: selectedQueue)
                }
            }
            .modifier(sourcePresentationsModifier(works: currentWorks))
            .confirmationDialog(
                "Delete “\(selectedQueue?.displayName ?? "Queue")”?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { deleteSelectedQueue() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Kudos will move this queue to Recently Deleted for "
                        + "\(PreservedWorkService.recoveryWindowText). Its list of works stays with it, "
                        + "and the works stay in Kudos."
                )
            }
            .destructiveConfirmation(
                for: $pendingRemoval,
                title: "Remove this work?",
                confirmLabel: "Remove",
                message: { work in
                    "“\(work.title)” will no longer be in “\(selectedQueue?.displayName ?? "this queue")”. "
                        + "The work itself stays in your Library."
                },
                perform: { work in
                    if let queue = selectedQueue {
                        ReadingQueueService.removeFromQueue(work, from: queue, in: context)
                    }
                }
            )
    }

    // MARK: - Compact (iPhone)

    /// The tab bar shows, as on the queue list; the select bulk bar takes the
    /// bottom only while selecting.
    private func compactLayout(works: [SavedWork], smartVisible: [SavedWork], smartHeader: [SavedWork]) -> some View {
        pageContent(works: works, smartVisible: smartVisible, smartHeader: smartHeader)
            #if os(iOS)
            .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
            #endif
    }

    // MARK: - Regular (iPad/Mac)

    private func regularLayout(
        snapshot: ReadingQueueService.SmartLibrarySnapshot?,
        works: [SavedWork],
        smartVisible: [SavedWork],
        smartHeader: [SavedWork]
    ) -> some View {
        HStack(spacing: 0) {
            List {
                ForEach(orderedQueues) { queue in
                    queueRow(queue, snapshot: snapshot) { !gate.isHidden($0, enabled: hideMature, mode: matureMode) }
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
            .disabled(isSelecting || isReordering)

            Divider()

            // `pageContent`'s own heading names the selected queue, so the split
            // view does not add a separate title row above it.
            pageContent(works: works, smartVisible: smartVisible, smartHeader: smartHeader)
        }
        #if os(iOS)
        // No phone-style tab bar here to begin with; hidden for the sidebar.
        .toolbar(.hidden, for: .tabBar)
        #endif
    }
}

// Split from the struct above purely to keep each declaration's own body under
// this repo's type-body-length gate — SwiftLint measures a `struct`/`extension`
// block's length individually, so this line is otherwise inert: every member
// below still reads and writes the same `@State`/`@Query` properties declared
// above, exactly as if this were one uninterrupted body.
extension ReadingQueueBrowserView {
    // MARK: - Active queue content

    @ViewBuilder
    /// `smartHeader` is the queue's visible list before quick filters (Hide Mature
    /// applied before the limit), so the header never counts, times or shows
    /// covers of works the reader cannot see. `works` still tells an empty
    /// queue from an all-hidden one.
    private func pageContent(works: [SavedWork], smartVisible: [SavedWork], smartHeader: [SavedWork]) -> some View {
        if let selectedQueue, selectedQueue.kind == .smart {
            let smartPreservedIDs = Set(
                smartHeader
                    .filter { $0.hasEPUB && FileManager.default.fileExists(atPath: $0.fileURL.path) }
                    .map(\.id)
            )
            SmartQueueWorksPage(
                queue: selectedQueue,
                works: works,
                headerWorks: smartHeader,
                visibleWorks: smartVisible,
                preservedIDs: smartPreservedIDs,
                palette: subjectPalette,
                arrangement: arrangement,
                isNarrowed: quickFilter != .all || filters.hasActiveFilters,
                onClearFilters: {
                    filters = LibraryFilters()
                    quickFilter = .all
                },
                onEditRules: { showingEdit = true },
                onAddTag: { showingQueueTags = true },
                filterRail: {
                    if filters.hasActiveFilters || quickFilter != .all {
                        filterChipRail
                    }
                }
            )
        } else if let selectedQueue, works.isEmpty {
            if selectedQueue.hasVisibleSources {
                List {
                    subjectHeaderSection
                    Section {
                        ContentUnavailableView {
                            Label("No works yet", systemImage: "list.bullet.rectangle")
                        } description: {
                            Text(KeepOffline.queueKeeps(selectedQueue.keepsWorksOffline)
                                ? "Works you add here are downloaded and kept for offline reading."
                                : "Add works to choose what to read next. This queue doesn't keep downloads for you.")
                        } actions: {
                            Button {
                                showingAddWorks = true
                            } label: {
                                Label("Add Works", systemImage: "plus")
                            }
                        }
                        .bareListRow()
                    }
                }
                .cardList()
                .environment(\.defaultMinListRowHeight, 0)
            } else {
                ContentUnavailableView {
                    Label(
                        selectedQueue.displayName,
                        systemImage: selectedQueue.kind == .savedForLater
                            ? WorkActionLabels.savedForLaterEmptySymbol
                            : "list.bullet.rectangle"
                    )
                } description: {
                    Text(KeepOffline.queueKeeps(selectedQueue.keepsWorksOffline)
                        ? "Works you add here are downloaded and kept for offline reading."
                        : "Add works to choose what to read next. This queue doesn't keep downloads for you.")
                } actions: {
                    Button {
                        showingAddWorks = true
                    } label: {
                        Label("Add Works", systemImage: "plus")
                    }
                    Button {
                        showingSources = true
                    } label: {
                        Label("Add Sources", systemImage: "square.stack.3d.up")
                    }
                }
            }
        } else {
            Group {
                // 1bg: Select is the numbered ledger even when the page is a grid.
                if arrangement != .grid || isSelecting {
                    detailedList
                } else {
                    compactGrid
                }
            }
            .refreshable {
                let task = Task { _ = await WorkMetadataRefresh.refresh(visibleWorks, in: context, auth: auth) }
                refreshTask = task
                await task.value
            }
            .cancelRefreshOnTabChange($refreshTask)
            .overlay {
                if visibleWorks.isEmpty, !works.isEmpty, !isReordering {
                    ContentUnavailableView {
                        Label("No matching works", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("Your filters don't match any works in this queue.")
                    } actions: {
                        Button("Clear Filters") {
                            filters = LibraryFilters()
                            quickFilter = .all
                        }
                    }
                }
            }
        }
    }

    private var detailedList: some View {
        List {
            if isReordering && !isSelecting {
                // Reorder operates over `In line` as a single flat `ForEach` so
                // `.onMove` promotes any item into Up next cleanly.
                if !wholePartition.new.isEmpty {
                    newSectionHeader(wholePartition.new)
                        .bareListRow()
                    ForEach(wholePartition.new) { entry in
                        ledgerRow(entry, position: nil)
                    }
                }
                if !wholePartition.inLineAll.isEmpty {
                    queueSectionHeader("In line")
                        .bareListRow()
                    ForEach(wholePartition.inLineAll) { entry in
                        ledgerRow(entry, position: queuePosition(of: entry.work))
                            .environment(\.ledgerPositionNumber, queuePosition(of: entry.work))
                    }
                    .onMove(perform: moveAction)
                }
                if !wholePartition.waiting.isEmpty {
                    waitingSectionHeader()
                        .bareListRow()
                    ForEach(wholePartition.waiting) { entry in
                        ledgerRow(entry, position: nil)
                    }
                }
                if !wholePartition.finished.isEmpty {
                    finishedSectionHeader(count: wholePartition.finished.count)
                        .bareListRow()
                    if isFinishedExpanded {
                        ForEach(wholePartition.finished) { entry in
                            ledgerRow(entry, position: nil)
                        }
                    }
                }
            } else if isSelecting {
                subjectHeaderSection
                if !visiblePartition.new.isEmpty {
                    newSectionHeader(visiblePartition.new)
                        .bareListRow()
                    ForEach(visiblePartition.new) { entry in
                        ledgerRow(entry, position: nil)
                    }
                }
                if !visiblePartition.inLineAll.isEmpty {
                    queueSectionHeader("In line")
                        .bareListRow()
                    ForEach(visiblePartition.inLineAll) { entry in
                        ledgerRow(entry, position: queuePosition(of: entry.work))
                            .environment(\.ledgerPositionNumber, queuePosition(of: entry.work))
                    }
                    .onMove(perform: moveAction)
                }
                if !visiblePartition.waiting.isEmpty {
                    waitingSectionHeader()
                        .bareListRow()
                    ForEach(visiblePartition.waiting) { entry in
                        ledgerRow(entry, position: nil)
                    }
                }
                if !visiblePartition.finished.isEmpty {
                    finishedSectionHeader(count: visiblePartition.finished.count)
                        .bareListRow()
                    if isFinishedExpanded {
                        ForEach(visiblePartition.finished) { entry in
                            ledgerRow(entry, position: nil)
                        }
                    }
                }
            } else {
                subjectHeaderSection
                if !visiblePartition.new.isEmpty {
                    newSectionHeader(visiblePartition.new)
                        .bareListRow()
                    ForEach(visiblePartition.new) { entry in
                        ledgerRow(entry, position: nil)
                    }
                }
                if let upNextEntry {
                    // No card-row padding on the header: it sits on its card, as on the board.
                    queueSectionHeader("Up next")
                        .bareListRow(verticalPadding: 0, interCardSpacing: 0)
                    upNextLinked(upNextEntry)
                        .bareListRow()
                        .padding(.bottom, inLineEntries.isEmpty ? 16 : 8)
                        .swipeActions(edge: .trailing) {
                            if !isSelecting {
                                Button(role: .destructive) {
                                    pendingRemoval = upNextEntry.work
                                } label: {
                                    Label("Remove", systemImage: "minus.circle")
                                }
                            }
                        }
                }
                if !inLineEntries.isEmpty {
                    queueSectionHeader("In line")
                        .bareListRow()
                    ForEach(inLineEntries) { entry in
                        ledgerRow(entry, position: queuePosition(of: entry.work))
                            .environment(\.ledgerPositionNumber, queuePosition(of: entry.work))
                    }
                }
                if !visiblePartition.waiting.isEmpty {
                    waitingSectionHeader()
                        .bareListRow()
                    ForEach(visiblePartition.waiting) { entry in
                        ledgerRow(entry, position: nil)
                    }
                }
                if !visiblePartition.finished.isEmpty {
                    finishedSectionHeader(count: visiblePartition.finished.count)
                        .bareListRow()
                    if isFinishedExpanded {
                        ForEach(visiblePartition.finished) { entry in
                            ledgerRow(entry, position: nil)
                        }
                    }
                }
            }
        }
        .cardList()
        // A one-line rule row is shorter than the default 44pt minimum, which
        // padded it top and bottom and put ~10pt more round each rule than
        // Compact draws.
        .environment(\.defaultMinListRowHeight, 0)
        #if os(iOS)
            .environment(\.editMode, dragEditMode)
        #endif
    }

    /// The header block and details as `detailedList`'s first rows.
    private var subjectHeaderSection: some View {
        Section {
            if !isSelecting {
                if let selectedQueue {
                    QueuePageHeader(
                        queue: selectedQueue,
                        works: works,
                        preservedIDs: Set(preservedWorks.map(\.id)),
                        palette: subjectPalette,
                        onAddTag: { showingQueueTags = true },
                        onOpenSource: { openSource($0, in: selectedQueue) },
                        onManageSources: { showingSources = true },
                        onRemoveSource: {
                            ReadingQueueService.removeSource($0, from: selectedQueue, in: context)
                        },
                        filterRail: {
                            if filters.hasActiveFilters || quickFilter != .all {
                                filterChipRail
                            }
                        }
                    )
                    .bareListRow()
                    .padding(.horizontal, SubjectMetrics.gutter)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                }
            } else {
                selectionStatusRow
                    .bareListRow()
                    .padding(.horizontal, SubjectMetrics.gutter)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
            }
        }
    }

    private func queueSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SubjectMetrics.gutter)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func newSectionHeader(_ entries: [ReadingQueueSectionEntry]) -> some View {
        let subtitle = entries.count == 1 ? "1 work · not sorted yet" : "\(entries.count) works · not sorted yet"
        let canSort = !isSelecting && !isReordering && selectedQueue != nil
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("New")
                            .font(.title3.bold())
                            .foregroundStyle(.primary)
                            .accessibilityAddTraits(.isHeader)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondaryInk)
                    }
                    if canSort {
                        sortNewButton(entries)
                        sortAllIntoLineButton(entries)
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("New")
                            .font(.title3.bold())
                            .foregroundStyle(.primary)
                            .accessibilityAddTraits(.isHeader)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondaryInk)
                    }
                    Spacer(minLength: 8)
                    if canSort {
                        // Both fit beside the title at large text; when they do
                        // not, Sort into line folds into the pair under Sort.
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .center, spacing: 12) {
                                sortAllIntoLineButton(entries)
                                sortNewButton(entries)
                            }
                            VStack(alignment: .trailing, spacing: 4) {
                                sortNewButton(entries)
                                sortAllIntoLineButton(entries)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SubjectMetrics.gutter)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func sortNewView(_ request: QueueSortNewRequest) -> some View {
        Group {
            if let queue = allQueues.first(where: { $0.id == request.queueID }) {
                QueueSortNewView(queue: queue, request: request)
            } else {
                Color.clear.onAppear { sortNewRequest = nil }
            }
        }
        .onChange(of: allQueues.map(\.id)) { _, ids in
            if !ids.contains(request.queueID) {
                sortNewRequest = nil
            }
        }
    }

    private func sortNewButton(_ entries: [ReadingQueueSectionEntry]) -> some View {
        QueueSortNewButton(count: entries.count) {
            guard let queue = selectedQueue else { return }
            sortNewRequest = QueueSortNewRequest(queueID: queue.id, membershipIDs: entries.map(\.membership.id))
        }
    }

    private func sortAllIntoLineButton(_ entries: [ReadingQueueSectionEntry]) -> some View {
        Button {
            guard let queue = selectedQueue else { return }
            Haptics.selection()
            ReadingQueueService.sortIntoLine(entries.map(\.membership), in: queue, context: context)
        } label: {
            Label("Sort into line", systemImage: "text.insert")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accentInk)
        }
        .buttonStyle(.plain)
        .minimumHitTarget()
    }

    private func waitingSectionHeader() -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Waiting")
                .font(.title3.bold())
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            if let subtitle = ReadingQueueSectionKind.waiting.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SubjectMetrics.gutter)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func finishedSectionHeader(count: Int) -> some View {
        let countText = count == 1 ? "1 work" : "\(count) works"
        return Button {
            Haptics.selection()
            isFinishedExpanded.toggle()
        } label: {
            HStack(spacing: 8) {
                Text("Finished")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(countText)
                    .font(.subheadline)
                    .foregroundStyle(.secondaryInk)
                Image(systemName: isFinishedExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondaryInk)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, SubjectMetrics.gutter)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("Finished, \(countText)")
        .accessibilityValue(isFinishedExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(isFinishedExpanded ? "Double-tap to collapse." : "Double-tap to expand.")
    }

    private var selectionStatusRow: some View {
        QueueSelectionStatusRow(
            queueName: selectedQueue?.displayName ?? "Queue",
            selectedCount: selectedWorks.count,
            total: displayedWorks.count
        )
    }

    /// 1h's grid: the front of the queue is a plain ledger row and In line is
    /// the cover grid.
    private var compactGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !isReordering && !isSelecting {
                    if let selectedQueue {
                        QueuePageHeader(
                            queue: selectedQueue,
                            works: works,
                            preservedIDs: Set(preservedWorks.map(\.id)),
                            palette: subjectPalette,
                            onAddTag: { showingQueueTags = true },
                            onOpenSource: { openSource($0, in: selectedQueue) },
                            onManageSources: { showingSources = true },
                            onRemoveSource: {
                                ReadingQueueService.removeSource($0, from: selectedQueue, in: context)
                            },
                            filterRail: {
                                if filters.hasActiveFilters || quickFilter != .all {
                                    filterChipRail
                                }
                            }
                        )
                        .padding(.horizontal, SubjectMetrics.gutter)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                    }
                } else if isSelecting {
                    selectionStatusRow
                        .padding(.horizontal, SubjectMetrics.gutter)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                }
                if isReordering {
                    if !wholePartition.new.isEmpty {
                        newSectionHeader(wholePartition.new)
                            .padding(.top, Self.ruleTop)
                        coverGrid(wholePartition.new, allowReorder: false)
                            .padding(.top, Self.afterRule)
                    }
                    if !compactInLineEntries.isEmpty {
                        queueSectionHeader("In line")
                            .padding(.top, Self.ruleTop)
                        coverGrid(compactInLineEntries, allowReorder: true)
                            .padding(.top, Self.afterRule)
                    }
                    if !wholePartition.waiting.isEmpty {
                        waitingSectionHeader()
                            .padding(.top, Self.ruleTop)
                        coverGrid(wholePartition.waiting, allowReorder: false)
                            .padding(.top, Self.afterRule)
                    }
                    if !wholePartition.finished.isEmpty {
                        finishedSectionHeader(count: wholePartition.finished.count)
                            .padding(.top, Self.ruleTop)
                        if isFinishedExpanded {
                            coverGrid(wholePartition.finished, allowReorder: false)
                                .padding(.top, Self.afterRule)
                        }
                    }
                } else {
                    if !visiblePartition.new.isEmpty {
                        newSectionHeader(visiblePartition.new)
                            .padding(.top, Self.ruleTop)
                        coverGrid(visiblePartition.new, allowReorder: false)
                            .padding(.top, Self.afterRule)
                    }
                    if let upNextEntry {
                        queueSectionHeader("Up next")
                            .padding(.top, Self.ruleTop)
                        upNextCompact(upNextEntry)
                    }
                    if !inLineEntries.isEmpty {
                        queueSectionHeader("In line")
                            .padding(.top, Self.ruleTop)
                        coverGrid(inLineEntries, allowReorder: false).padding(.top, Self.afterRule)
                    }
                    if !visiblePartition.waiting.isEmpty {
                        waitingSectionHeader()
                            .padding(.top, Self.ruleTop)
                        coverGrid(visiblePartition.waiting, allowReorder: false)
                            .padding(.top, Self.afterRule)
                    }
                    if !visiblePartition.finished.isEmpty {
                        finishedSectionHeader(count: visiblePartition.finished.count)
                            .padding(.top, Self.ruleTop)
                        if isFinishedExpanded {
                            coverGrid(visiblePartition.finished, allowReorder: false)
                                .padding(.top, Self.afterRule)
                        }
                    }
                }
            }
            .padding(.bottom, 16)
        }
    }

    /// 1h.1: 18 between blocks, 10 from a section rule to what it heads. Both
    /// layouts draw these; the list gets part of each from its card rows.
    private static let ruleTop: CGFloat = 18
    private static let afterRule: CGFloat = 10
    private static let halfCardGap: CGFloat = CardListMetrics.interCardSpacing / 2
    /// A card row's card starts `halfCardGap` below the row, so the rule row
    /// adds the rest of `afterRule`.
    private static let listRuleBottom: CGFloat = afterRule - halfCardGap

    private var compactInLineEntries: [ReadingQueueSectionEntry] {
        let byID = Dictionary(
            wholePartition.inLineAll.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return compactInLineWorks.compactMap { byID[$0.id] }
    }

    private func coverGrid(_ entries: [ReadingQueueSectionEntry], allowReorder: Bool) -> some View {
        CarouselCardGrid {
            ForEach(entries) { entry in
                compactCard(entry, allowReorder: allowReorder)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func compactCard(_ entry: ReadingQueueSectionEntry, allowReorder: Bool) -> some View {
        let work = entry.work
        let isBlurred = gate.isBlurred(work, enabled: hideMature, mode: matureMode)
        let hasAnnotation = !isBlurred && (entry.hasNewChapter || entry.originDisplayLine != nil)
        if isReordering, allowReorder, let queue = selectedQueue {
            VStack(alignment: .leading, spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    SensitiveWorkCoverCard(work: work)
                        .allowsHitTesting(false)
                        .opacity(draggedWorkID == work.id ? 0.4 : 1)
                    if isDragLive {
                        dragHandle(for: work)
                    }
                }
                if hasAnnotation {
                    queueAnnotationLine(
                        hasNewChapter: entry.hasNewChapter,
                        originLine: entry.originDisplayLine
                    )
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .onDrop(of: [.text], delegate: WorkReorderDropDelegate(
                target: work,
                works: reorderedInLineWorks,
                trailingIDs: trailingReorderIDs,
                draggedWorkID: $draggedWorkID,
                pendingOrder: $pendingCompactOrder,
                queue: queue,
                context: context
            ))
            .accessibilityActions {
                if isDragLive {
                    Button("Move Up") { moveWork(work, toIndex: currentIndex(of: work) - 1) }
                    Button("Move Down") { moveWork(work, toIndex: currentIndex(of: work) + 1) }
                    Button("Move to Top") { moveWork(work, toIndex: 0) }
                    Button("Move to Bottom") { moveWork(work, toIndex: reorderedInLineWorks.count - 1) }
                }
            }
        } else if isReordering {
            VStack(alignment: .leading, spacing: 4) {
                SensitiveWorkCoverCard(work: work)
                    .allowsHitTesting(false)
                if hasAnnotation {
                    queueAnnotationLine(
                        hasNewChapter: entry.hasNewChapter,
                        originLine: entry.originDisplayLine
                    )
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            NavigationLink(value: LocalWorkDestination.reader(work)) {
                VStack(alignment: .leading, spacing: 4) {
                    SensitiveWorkCoverCard(work: work)
                    if hasAnnotation {
                        queueAnnotationLine(
                            hasNewChapter: entry.hasNewChapter,
                            originLine: entry.originDisplayLine
                        )
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .buttonStyle(.plain)
            .localWorkContextMenu(
                work: work,
                scopedRemoval: ScopedRemoval(title: "Remove from Queue") { pendingRemoval = work },
                queueMenu: queueMenu(for: entry)
            )
            .modifier(SortIntoLineAccessibilityModifier(enabled: entry.section == .new) {
                guard let queue = selectedQueue else { return }
                Haptics.selection()
                ReadingQueueService.sortIntoLine(entry.membership, in: queue, context: context)
            })
        }
    }

    private func dragHandle(for work: SavedWork) -> some View {
        ReorderHandleView()
            .padding(6)
            .onDrag {
                draggedWorkID = work.id
                return NSItemProvider(object: work.id.uuidString as NSString)
            }
            .minimumHitTarget(28)
    }

    // MARK: - Toolbar (manage surface)

    @ToolbarContentBuilder
    private func manageToolbar(worksEmpty: Bool) -> some ToolbarContent {
        if selectedQueue?.kind == .smart {
            smartManageToolbar(worksEmpty: worksEmpty)
        } else if !worksEmpty {
            if isReordering {
                // The word, as the organizer ends its reorder (pass2-13).
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { setReordering(false) }
                }
            } else if isSelecting {
                ToolbarItem(placement: .confirmationAction) {
                    SelectAllButton(allSelected: allSelected, action: toggleSelectAll)
                }
                #if os(iOS)
                ToolbarItemGroup(placement: .bottomBar) { bulkActionBar }
                #else
                ToolbarItemGroup(placement: .primaryAction) { bulkActionBar }
                #endif
            } else {
                // Board 04: filter on its own, then + and ••• as one pill (adjacent items in
                // one placement share a glass pill; the spacer keeps the filter out of it).
                ToolbarItem(placement: .primaryAction) {
                    FilterButton(
                        filtersActive: filters.hasActiveFilters,
                        showingFilters: $showingFilters,
                        filterHelp: "Filter the works in this queue",
                        onClearFilters: { filters = LibraryFilters() }
                    )
                    .labelStyle(.iconOnly)
                }
                if !duoLayout.usesSingleRailActionGroup {
                    ToolbarSpacer(.fixed, placement: .primaryAction)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    addWorksButton.labelStyle(.iconOnly)
                    WorkListMoreMenu {
                        if hideMature {
                            MatureRevealToggle()
                        }
                        Button {
                            isSelecting = true
                        } label: {
                            Label("Select", systemImage: "checklist")
                        }
                        // The reason is the label: `.help` never shows on iPhone.
                        Button {
                            setReordering(true)
                        } label: {
                            Label(
                                isNarrowed ? "Clear Filters to Reorder"
                                    : hidesMatureWorks ? "Show Mature to Reorder" : "Reorder",
                                systemImage: "arrow.up.arrow.down"
                            )
                        }
                        .disabled(isNarrowed || hidesMatureWorks || reorderedInLineWorks.count < 2)
                        ListGridMenuPicker(arrangement: $arrangement)
                        Divider()
                        Picker("Filter", selection: $quickFilter) {
                            ForEach(QueueQuickFilter.allCases) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }
                        Divider()
                        queueMenuItems
                    }
                    .labelStyle(.iconOnly)
                }
            }
        } else if selectedQueue != nil {
            // Empty queue: still allow adding works, seeing its details, and
            // (custom only) renaming/deleting it, from the toolbar.
            ActionToolbar(items: [
                AnyView(addWorksButton),
                AnyView(WorkListMoreMenu { queueMenuItems })
            ])
        }

    }

    @ToolbarContentBuilder
    private func smartManageToolbar(worksEmpty: Bool) -> some ToolbarContent {
        if worksEmpty {
            ToolbarItem(placement: .primaryAction) {
                WorkListMoreMenu { queueMenuItems }
                    .labelStyle(.iconOnly)
            }
        } else {
            ToolbarItem(placement: .primaryAction) {
                FilterButton(
                    filtersActive: filters.hasActiveFilters,
                    showingFilters: $showingFilters,
                    filterHelp: "Filter the works in this queue",
                    onClearFilters: { filters = LibraryFilters() }
                )
                .labelStyle(.iconOnly)
            }
            if !duoLayout.usesSingleRailActionGroup {
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }
            ToolbarItem(placement: .primaryAction) {
                WorkListMoreMenu {
                    if hideMature {
                        MatureRevealToggle()
                    }
                    ListGridMenuPicker(arrangement: $arrangement)
                    Divider()
                    Picker("Filter", selection: $quickFilter) {
                        ForEach(QueueQuickFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    Divider()
                    queueMenuItems
                }
                .labelStyle(.iconOnly)
            }
        }
    }

    @ViewBuilder
    private var addWorksSheet: some View {
        if let queue = selectedQueue {
            AddLibraryWorksSheet(
                destinationName: queue.displayName,
                scopeName: "queue",
                candidates: { ReadingQueueService.appendCandidates(from: $0, notIn: queue) },
                onAdd: {
                    ReadingQueueService.append(
                        $0,
                        to: queue,
                        state: .new,
                        origin: ReadingQueueMembershipOrigin(kind: .manual),
                        in: context
                    )
                }
            )
        }
    }

    /// Untinted toolbar '+' control matching the rest of the queue toolbar (board 04).
    private var addWorksButton: some View {
        Button {
            showingAddWorks = true
        } label: {
            Label("Add Works", systemImage: "plus")
        }
        .help("Add works from your library")
    }

    private var bulkActionBar: some View {
        ScopedRemovalBulkActionBar(
            selectedWorks: selectedWorks,
            removeLabel: "Remove from Queue",
            scopeName: "queue",
            onRemove: bulkRemove,
            onDone: exitSelectMode,
            showsQueueActions: true
        )
    }

    /// Queue Details, and Edit Queue / Delete for a custom queue — the same items
    /// whether or not the queue has works.
    @ViewBuilder
    private var queueMenuItems: some View {
        if let queue = selectedQueue, queue.kind != .smart {
            Button {
                showingSources = true
            } label: {
                Label("Sources", systemImage: "square.stack.3d.up")
            }
        }
        Button {
            showingQueueDetails = true
        } label: {
            Label("Queue Details", systemImage: "info.circle")
        }
        if let queue = selectedQueue, queue.isUserQueue {
            Button {
                showingEdit = true
            } label: {
                Label(queue.kind == .smart ? "Edit Rules" : "Edit Queue", systemImage: "pencil")
            }
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("Delete Queue", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    private func startSourceCheck() {
        guard let selectedQueueID,
              let selectedQueue = orderedQueues.first(where: { $0.id == selectedQueueID })
        else { return }
        guard QueueSourceChecks.shouldCheckOnOpen(
            isPageVisible: isPageVisible,
            isAppActive: scenePhase == .active,
            isSelectedTab: router.selection == sourceOpeningTab,
            isSmartQueue: selectedQueue.kind == .smart,
            hasVisibleSources: selectedQueue.hasVisibleSources
        ) else {
            sourceCheckTask?.cancel()
            sourceCheckTask = nil
            sourceCheckQueueID = nil
            return
        }
        guard sourceCheckQueueID != selectedQueueID else { return }
        let previous = sourceCheckTask
        previous?.cancel()
        sourceCheckQueueID = selectedQueueID
        sourceCheckTask = Task {
            await previous?.value
            // The queue may have been deleted or left while the previous pass wound down.
            guard !Task.isCancelled, !selectedQueue.isDeleted, selectedQueue.modelContext != nil,
                  self.selectedQueueID == selectedQueue.id else { return }
            await checkSources(in: selectedQueue)
        }
    }

    private func checkSources(in queue: ReadingQueue) async {
        let queueID = queue.id
        await QueueSourceChecks.runFetched(
            sources: queue.countableSources,
            checkedAt: { $0.lastCheckedAt },
            now: Date.init,
            sleep: { try await Task.sleep(for: .seconds($0)) },
            isCurrent: { link in
                // A removed row (or a deleted queue) must not be fetched or written.
                !link.isDeleted && link.modelContext != nil && link.queue?.id == queueID
                    && !queue.isDeleted && queue.modelContext != nil && selectedQueueID == queueID
            },
            attempt: { link, date in
                link.lastCheckedAt = date
                FolderSyncService.markDirty()
                return context.saveBestEffort(reason: "Saving queue source check failed")
            },
            fetch: { link in
                guard let url = link.listingURL else {
                    throw AO3Error.network("Bad queue source URL.")
                }
                return try await AO3Client.shared.queueSourceFetch(url)
            },
            received: { link, fetched in
                sourcePages[link.id] = fetched
                link.newResultCount = QueueSourceChecks.count(
                    fetched.page,
                    since: link.effectiveLastOpenedAt
                )
                FolderSyncService.markDirty()
                _ = context.saveBestEffort(reason: "Saving queue source count failed")
            }
        )
    }

    private func openSource(_ link: QueueSavedSearchLink, in queue: ReadingQueue) {
        guard let kind = link.knownSourceKind else { return }
        router.currentQueueID = queue.id
        switch kind {
        case .savedSearch:
            guard let search = link.search else { return }
            defer { sourcePages.removeValue(forKey: link.id) }
            let cachedPage = QueueSourceChecks.cachedFetchForFindMore(
                sourcePages[link.id],
                listingURL: link.listingURL,
                isSignedOut: auth.status == .signedOut
            )?.page
            router.pendingQueueSearch = QueueSearchRoute(
                searchID: search.id,
                queueID: queue.id,
                page: cachedPage
            )
            router.selection = .search
        case .author:
            guard let route = link.authorRoute else { return }
            openedAuthorSource = OpenedQueueAuthorSource(
                linkID: link.id,
                route: route,
                label: link.effectiveDisplayName
            )
        case .series:
            guard let series = link.seriesSummary else { return }
            openedSeriesSource = OpenedQueueSeriesSource(
                linkID: link.id,
                series: series,
                label: link.effectiveDisplayName
            )
        case .tag:
            guard let request = link.tagWorksRequest else { return }
            openedTagSource = OpenedQueueTagSource(
                linkID: link.id,
                request: request,
                label: link.effectiveDisplayName
            )
        }
    }

    private func recordSourceOpen(linkID: UUID) {
        // The counted page is spent once Find More has used it.
        sourcePages.removeValue(forKey: linkID)
        guard let link = allQueues.flatMap(\.searchLinks).first(where: { $0.id == linkID }) else { return }
        ReadingQueueService.recordSourceOpen(link, in: context)
    }

    private func sourcePresentationsModifier(works currentWorks: [SavedWork]) -> QueueSourcePresentationsModifier {
        QueueSourcePresentationsModifier(
            showingSources: $showingSources,
            openedAuthorSource: $openedAuthorSource,
            openedSeriesSource: $openedSeriesSource,
            openedTagSource: $openedTagSource,
            selectedQueue: selectedQueue,
            works: currentWorks,
            preservedCount: preservedWorks.count,
            isSignedOut: auth.status == .signedOut,
            sourcePages: sourcePages,
            onQueueOpenSource: { pendingSourceToOpen = $0 },
            onDismissSources: {
                let link = pendingSourceToOpen
                pendingSourceToOpen = nil
                if let link, let queue = selectedQueue { openSource(link, in: queue) }
            },
            onRecordOpen: { recordSourceOpen(linkID: $0) }
        )
    }

    private func resolveInitialSelection() {
        ReadingQueueService.ensureSavedForLaterQueue(in: context)
        guard selectedQueueID == nil else { return }
        if let initialQueueID {
            selectedQueueID = initialQueueID
            lastSelectedIDRaw = initialQueueID.uuidString
        } else if let saved = UUID(uuidString: lastSelectedIDRaw),
                  orderedQueues.contains(where: { $0.id == saved }) {
            selectedQueueID = saved
        } else {
            selectedQueueID = orderedQueues.first?.id
        }
    }

    func select(_ queue: ReadingQueue) {
        // Leaving mid-select/reorder on another queue would leave dangling state.
        exitSelectMode()
        setReordering(false)
        isFinishedExpanded = false
        filters = LibraryFilters()
        quickFilter = .all
        selectedQueueID = queue.id
        lastSelectedIDRaw = queue.id.uuidString
    }

    /// False keeps the sheet open: the queue did not save (`NewReadingQueueSheet` says so).
    func createQueue(_ options: NewQueueOptions) -> Bool {
        let trimmed = newQueueName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let queue = ReadingQueueService.createQueue(
            id: options.draftID,
            named: trimmed,
            hue: newQueueHue,
            colorHex: options.colorHex,
            keepsWorksOffline: options.keepsWorksOffline,
            seededFrom: options.seed,
            tagNames: options.tagNames,
            seedWorkIDs: options.seedWorkIDs,
            smartRulesJSON: options.isSmart ? options.smartRulesJSON : nil,
            in: context
        )
        // As Home's and the organizer's: unsaved, the half-made queue is dropped and the
        // sheet stays.
        guard context.saveBestEffort(reason: "Saving reading queue failed") else {
            context.rollback()
            return false
        }
        newQueueName = ""
        newQueueHue = nil
        showingNewQueue = false
        select(queue)
        return true
    }

    private func setReordering(_ active: Bool) {
        isReordering = active
        draggedWorkID = nil
        pendingCompactOrder = nil
    }

    /// Nil while no drag is live, so the list offers no handles.
    private var moveAction: ((IndexSet, Int) -> Void)? {
        guard isDragLive else { return nil }
        return { moveWorks(from: $0, to: $1) }
    }

    #if os(iOS)
    /// Derived, not stored: edit mode is exactly "a drag is live", which
    /// select mode now turns on too (1bg).
    private var dragEditMode: Binding<EditMode> {
        .constant(isDragLive ? .active : .inactive)
    }
    #endif

    /// The row menu's leading queue actions. To Top and To Bottom use the same
    /// reorder as the drag handles; they are not gated on a drag being live,
    /// or the menu would do nothing most of the time.
    private func queueMenu(for entry: ReadingQueueSectionEntry) -> QueueItemMenuActions {
        let work = entry.work
        return QueueItemMenuActions(
            sortIntoLine: entry.section == .new
                ? {
                    guard let queue = selectedQueue else { return }
                    Haptics.selection()
                    ReadingQueueService.sortIntoLine(entry.membership, in: queue, context: context)
                }
                : nil,
            moveToTop: entry.section == .inLine
                ? { moveWork(work, toIndex: 0, requireDragLive: false) }
                : nil,
            moveToBottom: entry.section == .inLine
                ? { moveWork(work, toIndex: reorderedInLineWorks.count - 1, requireDragLive: false) }
                : nil,
            shareURL: WorkShareLink.url(for: work)
        )
    }

    private func moveWorks(from source: IndexSet, to destination: Int) {
        guard isDragLive, let queue = selectedQueue else { return }
        var ids = reorderedInLineWorks.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        ReadingQueueService.reorder(ids + trailingReorderIDs, in: queue, context: context)
    }

    private func currentIndex(of work: SavedWork) -> Int {
        reorderedInLineWorks.firstIndex(where: { $0.id == work.id }) ?? 0
    }

    private func moveWork(_ work: SavedWork, toIndex newIndex: Int, requireDragLive: Bool = true) {
        guard !requireDragLive || isDragLive,
              let queue = selectedQueue,
              let (from, to) = ReadingQueueService.moveOffsets(
                  currentIndex: currentIndex(of: work),
                  requestedIndex: newIndex,
                  count: reorderedInLineWorks.count
              )
        else { return }
        var ids = reorderedInLineWorks.map(\.id)
        ids.move(fromOffsets: from, toOffset: to)
        ReadingQueueService.reorder(ids + trailingReorderIDs, in: queue, context: context)
    }

    private func deleteSelectedQueue() {
        guard let queue = selectedQueue else { return }
        PreservedWorkService.softDelete(queue, in: context)
        exitSelectMode()
        setReordering(false)
        // Prefer staying on the browser if other queues remain.
        if let next = orderedQueues.first(where: { $0.id != queue.id }) {
            select(next)
        } else {
            dismiss()
        }
    }

    private func toggleSelectAll() {
        if allSelected {
            selection = []
        } else {
            if !visiblePartition.finished.isEmpty {
                isFinishedExpanded = true
            }
            selection = Set(displayedWorks.map(\.id))
        }
    }

    private func toggleSelection(_ work: SavedWork) {
        if selection.contains(work.id) {
            selection.remove(work.id)
        } else {
            selection.insert(work.id)
        }
    }

    private func exitSelectMode() {
        isSelecting = false
        selection = []
        draggedWorkID = nil
        pendingCompactOrder = nil
    }

    private func bulkRemove() {
        guard let queue = selectedQueue else { return }
        for work in selectedWorks {
            ReadingQueueService.removeFromQueue(work, from: queue, in: context)
        }
    }
}

// MARK: - Shared byte helpers (artboards 1h, 1i)

/// One work's EPUB size on disk, 0 if the file is missing. `ReadingQueueStorageView`
/// (`ReadingQueues.swift`) has its own private copy of this same lookup scoped to
/// every queued work across every queue; this one is scoped to a single queue
/// (here) or every queue's own row (the 1i organizer), so it stays a free function
/// rather than a method either screen would have to reach across files for.
func queueWorkFileSize(_ url: URL) -> Int64 {
    let values = try? url.resourceValues(forKeys: [.fileSizeKey])
    return Int64(values?.fileSize ?? 0)
}

func queueByteCountString(_ bytes: Int64) -> String {
    LocalStorageFootprint.formatted(bytes: bytes)
}

private struct SortIntoLineAccessibilityModifier: ViewModifier {
    let enabled: Bool
    let action: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.accessibilityAction(named: "Sort into line", action)
        } else {
            content
        }
    }
}
