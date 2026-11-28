import Foundation
import SwiftData
import SwiftUI

/// Artboard **1i**'s "Queues — organizer": the full list of every queue behind
/// Home's Queues carousel chevron. Was a `LibraryEntityGridView`
/// wrapping the carousel's own `ReadingQueueCard` — a 2-column grid with no
/// swipe actions, no reorder, and no per-queue detail beyond the title and a
/// work count. This restyles it into 1i's shape: a header stat strip across
/// every queue, then one reorderable row per queue with its own tally and
/// storage line.
///
/// **Built:** the "Search queues, tags and works" field (`queueSearchField`,
/// filtering through `matchesSearch` over names, tags and member works), the
/// **Pinned** section (`pinnedQueues`, on `ReadingQueue.isPinned`), the tag
/// filter pills over `ReadingQueue.tags` with an Untagged option, each row's
/// tags, and the New Queue row's "Name it, colour it, tag it" — true now that
/// `NewReadingQueueSheet` takes a colour and tags. The kicker is "Home": this
/// screen is only reachable from Home's Queues chevron. The header's two glass
/// buttons — New Queue, and the overflow menu carrying select mode with bulk
/// Pin / Tag / Delete (`QueueOrganizerSelection`) — and always-live drag,
/// switched off under a filter with the header line saying so. Each row leads
/// with the queue's 48pt cover stack (`StackedWorkCover`, `.queue`; T-461).
///
/// **What 1i draws that this does not build, and why:**
/// - The tag rail's "Edit tags" chip — tags are edited per queue in Queue
///   Details (1h), or across a selection from select mode's Tag, not from a
///   rail that filters by them; a third editor would be one more way to write
///   one list.
struct AllReadingQueuesGridView: View {
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure
    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var themeManager
    @Environment(PrivacyGate.self) private var gate
    @Query(filter: #Predicate<ReadingQueue> { !$0.isPendingDeletion }, sort: \ReadingQueue.sortOrder)
    private var readingQueues: [ReadingQueue]
    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion })
    private var libraryWorks: [SavedWork]
    @Query private var tagAliases: [TagAlias]

    @State private var showingNewQueue = false
    @State private var newQueueHue: Double?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// 1i's tag rail. Empty means All; `untaggedFilter` means the queues with no
    /// tags; anything else is a tag name.
    @AppStorage("library.queueOrganizer.tagFilter") private var tagFilter = ""
    @State private var newQueueName = ""
    @State private var pendingEdit: ReadingQueue?
    /// The queues waiting on the delete confirmation: one from a row's swipe,
    /// or select mode's whole selection — one dialog, one delete path.
    @State private var pendingDelete: [ReadingQueue] = []
    @State private var isSelecting = false
    /// Owner, 2026-09-28: the drag is a mode chosen from "...", not always on.
    @State private var isReordering = false
    @State private var selection = Set<UUID>()
    @State private var showingBulkTags = false
    /// 1i: "search over queues, tags and works". One field over all three,
    /// rather than three — the reader is looking for a queue and does not know
    /// or care which of the three matched it.
    ///
    @State private var searchText = ""

    /// Resolves every queue's works once per render using a single library snapshot.
    private func resolveWorksByQueueID() -> [UUID: [SavedWork]] {
        let smartSnapshot = readingQueues.contains { $0.kind == .smart }
            ? ReadingQueueService.SmartLibrarySnapshot(
                works: libraryWorks,
                aliases: TagAliasResolver(models: tagAliases)
            )
            : nil
        var result: [UUID: [SavedWork]] = [:]
        result.reserveCapacity(readingQueues.count)
        for queue in readingQueues {
            if let smartSnapshot {
                result[queue.id] = ReadingQueueService.orderedWorks(in: queue, snapshot: smartSnapshot) {
                    !gate.isHidden($0, enabled: hideMature, mode: matureMode)
                }
            } else {
                result[queue.id] = ReadingQueueService.orderedMemberships(in: queue).compactMap(\.work)
            }
        }
        return result
    }

    /// List queues and smart queues. The name predates smart queues.
    private func filteredCustomQueues(worksByQueueID: [UUID: [SavedWork]]) -> [ReadingQueue] {
        readingQueues
            .filter(\.isUserQueue)
            .sorted { $0.sortOrder < $1.sortOrder }
            .filter(matchesTagFilter)
            .filter { matchesSearch($0, works: worksByQueueID[$0.id]) }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Every queue on screen, once each — Pinned repeats queues from All queues.
    private func visibleQueues(
        pinned: [ReadingQueue],
        savedForLater: ReadingQueue?,
        custom: [ReadingQueue]
    ) -> [ReadingQueue] {
        var seen = Set<UUID>()
        return (pinned + [savedForLater].compactMap(\.self) + custom)
            .filter { seen.insert($0.id).inserted }
    }

    private var selectedQueues: [ReadingQueue] {
        readingQueues.filter { selection.contains($0.id) }
    }

    private func allSelected(in visible: [ReadingQueue]) -> Bool {
        let ids = Set(visible.map(\.id))
        return !ids.isEmpty && ids.isSubset(of: selection)
    }

    /// 1i draws **Pinned** as its own section above **All queues**, and the tree
    /// lists the same queue in both — so a pin is a shortcut to the top, not a
    /// reordering. Keeping the main list in pure `sortOrder` also means the drag
    /// order has no pin boundary to fight over.
    ///
    /// Saved for Later can be pinned like any other: the tree shows it in the
    /// Pinned section.
    private func filteredPinnedQueues(worksByQueueID: [UUID: [SavedWork]]) -> [ReadingQueue] {
        readingQueues
            .filter(\.isPinned)
            .sorted { $0.sortOrder < $1.sortOrder }
            .filter(matchesTagFilter)
            .filter { matchesSearch($0, works: worksByQueueID[$0.id]) }
    }

    /// 1i's rail: All, then one chip per tag actually in use, then Untagged.
    /// Only tags that are on a queue appear — a rail offering a filter that
    /// returns nothing is furniture.
    private var queueTagNames: [String] {
        Set(readingQueues.flatMap { $0.tags.map(\.name) }).sorted()
    }

    /// The works half is what makes this cross-queue: a queue matches when a work
    /// INSIDE it matches, so typing a title finds the queue you filed it under
    /// without having to remember which one that was.
    ///
    /// Only loaded memberships are searched, which is honest here — they are
    /// local SwiftData relationships, not a paged remote list, so there is no
    /// "rest of the results" being silently skipped.
    private func matchesSearch(_ queue: ReadingQueue, works: [SavedWork]?) -> Bool {
        QueueOrganizerSelection.matchesSearch(queue, term: searchText, works: works) {
            !gate.isHidden($0, enabled: hideMature, mode: matureMode)
        }
    }

    private func matchesTagFilter(_ queue: ReadingQueue) -> Bool {
        switch tagFilter {
        case "": true
        case Self.untaggedFilter: queue.tags.isEmpty
        default: queue.tags.contains { $0.name == tagFilter }
        }
    }

    /// Sentinel rather than an enum: the other cases are tag names, which are
    /// user text, and a name could never be this — it is not a legal `Tag.name`
    /// the sheet can produce, since that trims to non-empty plain text.
    static let untaggedFilter = "\u{0}untagged"

    /// Board `Queues.dc.html` pill search bar (still searches queues, tags, and works).
    private var queueSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondaryInk)
                .accessibilityHidden(true)
            TextField("Search queues", text: $searchText)
                .font(.callout)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .accessibilityLabel("Search queues")
                .accessibilityHint("Also searches tags and works")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondaryInk)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 38)
        .background(
            themeManager.appTheme.glassFill(0.12),
            in: SubjectMetrics.controlShape(dynamicTypeSize)
        )
    }

    private var tagRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                tagChip("All", value: "", count: readingQueues.count)
                ForEach(queueTagNames, id: \.self) { name in
                    tagChip(name, value: name, count: readingQueues.count { $0.tags.contains { $0.name == name } })
                }
                let untagged = readingQueues.count { $0.tags.isEmpty }
                if untagged > 0 {
                    tagChip("Untagged", value: Self.untaggedFilter, count: untagged)
                }
            }
            .padding(.horizontal, SubjectMetrics.gutter)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Filter by tag")
        }
        .horizontalScrollViewport()
    }

    private func tagChip(_ title: String, value: String, count: Int) -> some View {
        let isSelected = tagFilter == value
        let fill = themeManager.effectiveTint
        let shape = SubjectMetrics.controlShape(dynamicTypeSize)
        return Button {
            tagFilter = isSelected ? "" : value
        } label: {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? ThemeManager.label(on: fill) : Color.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .frame(minHeight: 32)
                .background(
                    shape.fill(
                        isSelected
                            ? AnyShapeStyle(fill)
                            : AnyShapeStyle(themeManager.appTheme.cardSurface)
                    )
                )
        }
        .buttonStyle(.plain)
        .minimumHitTarget()
        .accessibilityLabel(title)
        .accessibilityValue(count == 1 ? "1 queue" : "\(count) queues")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Saved for Later, when the search and the tag filter both let it through.
    private func filteredSavedForLaterQueue(worksByQueueID: [UUID: [SavedWork]]) -> ReadingQueue? {
        readingQueues.first {
            $0.kind == .savedForLater && matchesTagFilter($0) && matchesSearch($0, works: worksByQueueID[$0.id])
        }
    }

    /// Every queue's own hue tints its row; the page itself has no single
    /// subject, so its wash takes the app's own accent scope — the same choice
    /// `LibrarySectionListView.scopePalette` makes for the same reason.
    private var organizerPalette: SubjectPalette {
        themeManager.scopePalette
    }

    var body: some View {
        let worksByQueueID = resolveWorksByQueueID()
        let pinned = filteredPinnedQueues(worksByQueueID: worksByQueueID)
        let custom = filteredCustomQueues(worksByQueueID: worksByQueueID)
        let savedForLater = filteredSavedForLaterQueue(worksByQueueID: worksByQueueID)
        let visible = visibleQueues(pinned: pinned, savedForLater: savedForLater, custom: custom)
        let visibleCount = custom.count + (savedForLater == nil ? 0 : 1)
        let showsTagRail = !queueTagNames.isEmpty || !tagFilter.isEmpty
        let showsWhatFits = !isSelecting && !isReordering
        let pinnedSegments = PanelSegment.keyed(pinned, id: \.id)
        let customSegments = PanelSegment.keyed(custom, id: \.id)
        List {
            Section {
                queueSearchField
                    .padding(.bottom, (!showsTagRail && !showsWhatFits && pinned.isEmpty) ? 12 : 0)
                    .pageBodyRow(top: 12, gutter: SubjectMetrics.gutter)
                if showsWhatFits {
                    WhatFitsOrganizerRow()
                        .padding(.bottom, (!showsTagRail && pinned.isEmpty) ? 12 : 0)
                        .pageBodyRow(top: 12, gutter: SubjectMetrics.gutter)
                }
            }

            // A persisted filter whose tag is gone still needs the rail's All chip,
            // or nothing on screen can clear it.
            if showsTagRail {
                Section {
                    tagRail
                        .padding(.bottom, pinned.isEmpty ? 12 : 0)
                        .pageBodyRow(top: 12, gutter: 0)
                }
            }

            if !pinned.isEmpty {
                Section {
                    SectionRuleHeader(title: "Pinned", count: pinned.count)
                        .padding(.bottom, 8)
                        .pageBodyRow(top: 16, gutter: 0)
                    ForEach(pinnedSegments, id: \.key) { segment in
                        let queue = segment.element
                        organizerRow(queue, works: worksByQueueID[queue.id] ?? [], isReorderable: false)
                            .subjectPanelSegmentRow(
                                isFirst: segment.offset == 0,
                                isLast: segment.offset == pinnedSegments.count - 1,
                                gutter: SubjectMetrics.gutter,
                                padsContent: false
                            )
                            .swipeActions(edge: .trailing) { queueSwipes(queue) }
                            .modifier(QueueCardMenu(queue: queue, isEnabled: !isSelecting && !isReordering))
                    }
                }
            }

            Section {
                if !pinned.isEmpty {
                    SectionRuleHeader(title: "All Queues", count: visibleCount)
                        .padding(.bottom, 8)
                        .pageBodyRow(top: 16, gutter: 0)
                }

                if let savedForLater {
                    organizerRow(savedForLater, works: worksByQueueID[savedForLater.id] ?? [], isReorderable: false)
                        .subjectPanelSegmentRow(
                            isFirst: true,
                            isLast: custom.isEmpty,
                            gutter: SubjectMetrics.gutter,
                            padsContent: false
                        )
                }

                ForEach(customSegments, id: \.key) { segment in
                    let queue = segment.element
                    organizerRow(queue, works: worksByQueueID[queue.id] ?? [], isReorderable: true)
                        .subjectPanelSegmentRow(
                            isFirst: savedForLater == nil && segment.offset == 0,
                            isLast: segment.offset == customSegments.count - 1,
                            gutter: SubjectMetrics.gutter,
                            padsContent: false
                        )
                        .swipeActions(edge: .trailing) { queueSwipes(queue) }
                        .modifier(QueueCardMenu(queue: queue, isEnabled: !isSelecting && !isReordering))
                }
                .onMove(perform: moveAction)

                // A search or tag filter that leaves nothing says so, with the
                // way back, rather than an empty "All queues 0".
                if visible.isEmpty, isSearching || !tagFilter.isEmpty {
                    ContentUnavailableView {
                        Label("No matching queues", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("Your search and tag filter don't match any queues.")
                    } actions: {
                        Button("Clear Search and Filters") {
                            searchText = ""
                            tagFilter = ""
                        }
                    }
                    .bareListRow()
                }
            }
        }
        .cardList()
        .navigationTitle(isSelecting ? "\(selection.count) selected" : "Reading Queues")
        .subjectScreenWash(palette: organizerPalette, role: .grouped)
        .toolbar { toolbarContent(visibleQueues: visible) }
        #if os(iOS)
        .environment(
            \.editMode,
            .constant(isReordering && canReorder ? .active : .inactive)
        )
        // Select mode owns the bottom edge with its bulk bar.
        .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
        #endif
        .sheet(isPresented: $showingBulkTags) {
            QueueTagSheet(queues: selectedQueues)
        }
        #if DEBUG
        .task {
            // Only the "newqueue" shot opens this. The bare "queues" route has to
            // stay the organizer root, or that screen can never be shot again.
            if DebugLaunchRoute.takeSheet("newqueue") {
                showingNewQueue = true
            }
        }
        #endif
        .sheet(isPresented: $showingNewQueue) {
            NewReadingQueueSheet(
                name: $newQueueName,
                hue: $newQueueHue,
                onCreate: createQueue,
                onCancel: {
                    newQueueName = ""
                    newQueueHue = nil
                    showingNewQueue = false
                }
            )
        }
        .sheet(item: $pendingEdit) { EditReadingQueueSheet(queue: $0) }
        // `presenting:` hands the queues INTO the action: dismissal clears
        // `pendingDelete` through the binding, and on iOS 27 it lands first (see
        // `RecentlyDeletedView`'s alert).
        .confirmationDialog(
            QueueOrganizerSelection.deleteTitle(pendingDelete),
            isPresented: Binding(get: { !pendingDelete.isEmpty }, set: { if !$0 { pendingDelete = [] } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { queues in
            Button("Delete", role: .destructive) {
                QueueOrganizerSelection.delete(queues, in: context)
                selection.subtract(queues.map(\.id))
                pendingDelete = []
            }
            Button("Cancel", role: .cancel) { pendingDelete = [] }
        } message: { queues in
            Text(QueueOrganizerSelection.deleteMessage(count: queues.count))
        }
    }

    @ToolbarContentBuilder
    private func toolbarContent(visibleQueues: [ReadingQueue]) -> some ToolbarContent {
        if isSelecting {
            let isAllSelected = allSelected(in: visibleQueues)
            ToolbarItem(placement: .confirmationAction) {
                SelectAllButton(allSelected: isAllSelected) {
                    selection = isAllSelected ? [] : Set(visibleQueues.map(\.id))
                }
            }
            #if os(iOS)
            ToolbarItemGroup(placement: .bottomBar) { selectionBar }
            #else
            ToolbarItemGroup(placement: .primaryAction) { selectionBar }
            #endif
        } else if isReordering {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { isReordering = false }
            }
        } else {
            // 1i: "two glass buttons in the header — new queue, and the overflow
            // menu, which carries select mode".
            ActionToolbar(items: [
                AnyView(ToolbarIconButton(title: "New Queue", systemImage: "plus") {
                    newQueueName = ""
                    showingNewQueue = true
                }),
                AnyView(WorkListMoreMenu {
                    Button {
                        isSelecting = true
                    } label: {
                        Label("Select", systemImage: "checklist")
                    }
                    if readingQueues.count(where: \.isUserQueue) > 1 {
                        Button {
                            isReordering = true
                        } label: {
                            Label(canReorder ? "Reorder" : "Clear Filters to Reorder",
                                  systemImage: "arrow.up.arrow.down")
                        }
                        .disabled(!canReorder)
                    }
                })
            ])
        }
    }

    /// Pin · Tag · Delete, then Done. Pin reads Unpin when every selected
    /// queue already is; Delete takes the custom queues only.
    @ViewBuilder
    private var selectionBar: some View {
        let queues = selectedQueues
        let pins = QueueOrganizerSelection.pinTarget(queues)
        Button {
            QueueOrganizerSelection.setPinned(queues, pins, in: context)
        } label: {
            Label(pins ? "Pin" : "Unpin", systemImage: pins ? "pin" : "pin.slash")
        }
        .disabled(queues.isEmpty)
        Spacer()
        Button {
            showingBulkTags = true
        } label: {
            Label("Tag", systemImage: "tag")
        }
        .disabled(queues.isEmpty)
        Spacer()
        Button(role: .destructive) {
            pendingDelete = QueueOrganizerSelection.deletable(queues)
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .disabled(QueueOrganizerSelection.deletable(queues).isEmpty)
        Spacer()
        Button {
            isSelecting = false
            selection = []
        } label: {
            Image(systemName: "checkmark")
        }
        .accessibilityLabel("Done")
    }

    /// Edit and Delete for a custom queue, wherever its row is drawn —
    /// Pinned and All queues show the same queue. Saved for Later has neither.
    @ViewBuilder
    private func queueSwipes(_ queue: ReadingQueue) -> some View {
        if !isSelecting, queue.isUserQueue {
            Button(role: .destructive) {
                pendingDelete = [queue]
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                pendingEdit = queue
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    @ViewBuilder
    private func organizerRow(_ queue: ReadingQueue, works: [SavedWork], isReorderable: Bool) -> some View {
        let detail = ReadingQueueFacts.planFacts(for: works)
        let palette = queue.isUserQueue
            ? themeManager.appTheme.subjectPalette(hue: queue.displayHue, pickedHex: queue.colorHex)
            : organizerPalette
        let isSelected = selection.contains(queue.id)

        let content = HStack(spacing: 12) {
            if isSelecting {
                WorkLeadingSelectionCheck(isSelected: isSelected)
            }
            peekTile(queue, works: works)

            VStack(alignment: .leading, spacing: 3) {
                Text(queue.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                if !works.isEmpty {
                    QueueProgressStrip(
                        progress: ReadingQueueFacts.progress(of: works.map(\.readingState)),
                        palette: palette,
                        fills: works.map {
                            ReadingQueueFacts.segmentFill(state: $0.readingState, progress: $0.readingProgress)
                        },
                        height: 3,
                        gap: 2
                    )
                    .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !isSelecting && !isReordering {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 72)
        .contentShape(Rectangle())

        if isSelecting {
            Button {
                if isSelected { selection.remove(queue.id) } else { selection.insert(queue.id) }
            } label: {
                content
            }
            .buttonStyle(.plain)
            .moveDisabled(!isReorderable)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(queue.displayName)
            .accessibilityValue("\(isSelected ? "Selected" : "Not selected"), \(detail)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            content
                .accessibilityHidden(true)
                .subjectRowNavigation(
                    to: AllReadingQueuesDestination(initialQueueID: queue.id),
                    accessibilityLabel: "\(queue.displayName), \(detail)"
                )
                .moveDisabled(!isReorderable)
        }
    }

    /// Board 05: the queue's 48pt cover stack (T-461) — its own colour and initial
    /// in front, its first works stacked straight up behind. A cover is its work's
    /// fandom colour, so a work the privacy setting keeps back is left out.
    private func peekTile(_ queue: ReadingQueue, works: [SavedWork]) -> some View {
        StackedWorkCover(
            kind: .queue,
            name: queue.displayName,
            identity: queue.id,
            hue: queue.hue,
            pickedHex: queue.colorHex,
            backs: Array(works.filter { !gate.isConcealed($0, enabled: hideMature) }
                .prefix(CoverStackLayout.maxBacks)),
            size: CGSize(width: 48, height: 48)
        )
        .accessibilityHidden(true)
    }

    /// Reorder mode only, and off under a filter: a drag there reorders only
    /// the visible ids and rewrites `sortOrder` from 0, scrambling the hidden
    /// queues' order.
    private var moveAction: ((IndexSet, Int) -> Void)? {
        guard isReordering, canReorder else { return nil }
        return { moveCustomQueues(from: $0, to: $1) }
    }

    private var canReorder: Bool {
        QueueOrganizerSelection.canReorder(tagFilterActive: !tagFilter.isEmpty, searchActive: isSearching)
    }

    private func moveCustomQueues(from source: IndexSet, to destination: Int) {
        var ids = readingQueues
            .filter(\.isUserQueue)
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        reorderCustomQueues(ids, context: context)
    }

    /// False keeps the sheet open: the queue did not save (`NewReadingQueueSheet` says so).
    private func createQueue(_ options: NewQueueOptions) -> Bool {
        let trimmed = newQueueName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        _ = ReadingQueueService.createQueue(
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
        // `createQueue` saved best-effort; this asks whether that stuck (a no-op when it
        // did). Unsaved, the half-made queue is dropped so a second Create can't make two.
        guard context.saveBestEffort(reason: "Saving reading queue failed") else {
            context.rollback()
            return false
        }
        newQueueName = ""
        newQueueHue = nil
        showingNewQueue = false
        return true
    }
}

/// Persists a new queue order after 1i's `.onMove` — mirrors
/// `ReadingQueueService.reorder(_:in:context:)`'s index rewrite, but for
/// `ReadingQueue.sortOrder` itself (the queues' own order) rather than a
/// membership's position inside one queue, so it stays local to this screen —
/// the only caller — rather than in the service.
///
/// The list this reorders is in pure `sortOrder` — pinning does not reorder it,
/// it adds a separate Pinned section above (1i lists the same queue in both) —
/// so a drag here means exactly what it looks like.
private func reorderCustomQueues(_ orderedIDs: [UUID], context: ModelContext) {
    let queues = (try? context.fetch(FetchDescriptor<ReadingQueue>())) ?? []
    let byID = Dictionary(uniqueKeysWithValues: queues.map { ($0.id, $0) })
    for (index, id) in orderedIDs.enumerated() {
        byID[id]?.sortOrder = index
    }
    context.saveBestEffort(reason: "Saving reading queue order failed")
}

/// 1i's select mode and drag rule, kept out of the view so tests can hand them
/// fixtures.
@MainActor
enum QueueOrganizerSelection {
    /// A queue answers a search by its name, a tag, or a member work's title or
    /// author. A work Hide mode hides does not answer, here as in Search: typing
    /// its title used to find the queue it is in.
    static func matchesSearch(
        _ queue: ReadingQueue,
        term rawTerm: String,
        works: [SavedWork]? = nil,
        mayAnswer: (SavedWork) -> Bool
    ) -> Bool {
        let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return true }
        if queue.name.localizedCaseInsensitiveContains(term) { return true }
        if queue.tags.contains(where: { $0.name.localizedCaseInsensitiveContains(term) }) {
            return true
        }
        let resolvedWorks = works ?? ReadingQueueService.orderedWorks(in: queue)
        return resolvedWorks.contains { work in
            guard mayAnswer(work) else { return false }
            return work.title.localizedCaseInsensitiveContains(term)
                || work.author.localizedCaseInsensitiveContains(term)
        }
    }

    /// Saved for Later can't be deleted — no row offers it — so a bulk Delete
    /// takes the custom queues in the selection and nothing else.
    static func deletable(_ queues: [ReadingQueue]) -> [ReadingQueue] {
        queues.filter(\.isUserQueue)
    }

    /// Pin, unless every selected queue already is — then Unpin. The same
    /// "all, else apply to the rest" rule `WorkBulkTagSheet` uses.
    static func pinTarget(_ queues: [ReadingQueue]) -> Bool {
        !queues.isEmpty && queues.contains { !$0.isPinned }
    }

    /// Queue Details' Pin toggle, over a selection; a queue already there is
    /// left alone rather than stamped modified for nothing.
    static func setPinned(_ queues: [ReadingQueue], _ pinned: Bool, in context: ModelContext) {
        for queue in queues where queue.isPinned != pinned {
            queue.isPinned = pinned
            queue.markModified()
        }
        context.saveBestEffort(reason: "Saving queue pins failed")
    }

    /// The single-queue delete, once per queue: each goes to Recently Deleted
    /// with its works intact.
    static func delete(_ queues: [ReadingQueue], in context: ModelContext) {
        for queue in deletable(queues) {
            PreservedWorkService.softDelete(queue, in: context)
        }
    }

    static func deleteTitle(_ queues: [ReadingQueue]) -> String {
        queues.count == 1
            ? "Delete “\(queues[0].displayName)”?"
            : "Delete \(queues.count) queues?"
    }

    static func deleteMessage(count: Int) -> String {
        count == 1
            ? "Kudos will move this queue to Recently Deleted for "
                + "\(PreservedWorkService.recoveryWindowText). Its list of works stays with it, "
                + "and the works stay in Kudos."
            : "Kudos will move these \(count) queues to Recently Deleted for "
                + "\(PreservedWorkService.recoveryWindowText). Their lists of works stay with them, "
                + "and the works stay in Kudos."
    }

    /// A filtered list can't write its order back: the drag would renumber only
    /// the queues on screen.
    static func canReorder(tagFilterActive: Bool, searchActive: Bool) -> Bool {
        !tagFilterActive && !searchActive
    }
}

/// A queue's tag wherever the queue is shown — 1i's rows and 1h's header:
/// small caps on a faint plate, not the page's full-size chip. `dashed` is
/// the "+ Tag" that adds one.
struct QueueRowTagLabel: View {
    let text: String
    var dashed = false

    @ScaledMetric(relativeTo: .caption2) private var fontSize: CGFloat = 9.5

    var body: some View {
        let shape = Capsule()
        Text(text)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(.secondaryInk)
            .lineLimit(1)
            .padding(.vertical, 3)
            .padding(.horizontal, 7)
            .background {
                if dashed {
                    shape.strokeBorder(style: StrokeStyle(lineWidth: 0.75, dash: [3]))
                        .foregroundStyle(.tertiary)
                } else {
                    shape.fill(Color.primary.opacity(0.08))
                }
            }
    }
}
