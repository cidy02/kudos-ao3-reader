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
/// with a 44pt 2×2 peek of its first four works (`QueuePeekTile`, the frame
/// `ReadingQueueCard` draws) over the queue's own colour.
///
/// **What 1i draws that this does not build, and why:**
/// - The tag rail's "Edit tags" chip — tags are edited per queue in Queue
///   Details (1h), or across a selection from select mode's Tag, not from a
///   rail that filters by them; a third editor would be one more way to write
///   one list.
struct AllReadingQueuesGridView: View {
    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var themeManager
    @Query(filter: #Predicate<ReadingQueue> { !$0.isPendingDeletion }, sort: \ReadingQueue.sortOrder)
    private var readingQueues: [ReadingQueue]

    @State private var showingNewQueue = false
    @State private var newQueueHue: Double?
    /// The row's name, count and storage line scale with the tag chips beside
    /// them; at AX sizes the chips grew to twice the size of the queue's name.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var rowTitleSize: CGFloat = 15.5
    @ScaledMetric(relativeTo: .caption) private var rowCountSize: CGFloat = 11.5
    @ScaledMetric(relativeTo: .caption2) private var rowStorageSize: CGFloat = 10.5
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

    private var customQueues: [ReadingQueue] {
        readingQueues
            .filter { $0.kind == .custom }
            .sorted { $0.sortOrder < $1.sortOrder }
            .filter(matchesTagFilter)
            .filter(matchesSearch)
    }

    /// What the section header counts. `readingQueues.count` is the total, and
    /// under a search or a tag filter that put "2" above a single row — the same
    /// wrong-count defect this sweep keeps finding. With nothing filtering, this
    /// is the total anyway.
    private var visibleQueueCount: Int {
        customQueues.count + (savedForLaterQueue == nil ? 0 : 1)
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Every queue on screen, once each — Pinned repeats queues from All queues.
    private var visibleQueues: [ReadingQueue] {
        var seen = Set<UUID>()
        return (pinnedQueues + [savedForLaterQueue].compactMap(\.self) + customQueues)
            .filter { seen.insert($0.id).inserted }
    }

    private var selectedQueues: [ReadingQueue] {
        readingQueues.filter { selection.contains($0.id) }
    }

    private var allSelected: Bool {
        let ids = Set(visibleQueues.map(\.id))
        return !ids.isEmpty && ids.isSubset(of: selection)
    }

    /// 1i draws **Pinned** as its own section above **All queues**, and the tree
    /// lists the same queue in both — so a pin is a shortcut to the top, not a
    /// reordering. Keeping the main list in pure `sortOrder` also means the drag
    /// order has no pin boundary to fight over.
    ///
    /// Saved for Later can be pinned like any other: the tree shows it in the
    /// Pinned section.
    private var pinnedQueues: [ReadingQueue] {
        readingQueues
            .filter(\.isPinned)
            .sorted { $0.sortOrder < $1.sortOrder }
            .filter(matchesTagFilter)
            .filter(matchesSearch)
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
    private func matchesSearch(_ queue: ReadingQueue) -> Bool {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return true }
        if queue.name.localizedCaseInsensitiveContains(term) { return true }
        if queue.tags.contains(where: { $0.name.localizedCaseInsensitiveContains(term) }) {
            return true
        }
        return queue.memberships.contains { membership in
            guard !membership.isPendingDeletion, let work = membership.work else { return false }
            return work.title.localizedCaseInsensitiveContains(term)
                || work.author.localizedCaseInsensitiveContains(term)
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

    /// 1i's own placeholder, verbatim.
    private var queueSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search queues, tags and works", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .subjectPanel()
    }

    private var tagRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                // 1i: each pill carries how many queues it keeps — "Rereads 2".
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
        }
    }

    private func tagChip(_ title: String, value: String, count: Int) -> some View {
        let isSelected = tagFilter == value
        return Button {
            tagFilter = isSelected ? "" : value
        } label: {
            SubjectChip(
                text: "\(title) \(count.compactCount)",
                style: .pill(isSelected: isSelected),
                palette: organizerPalette
            )
        }
        .buttonStyle(.plain)
        .minimumHitTarget()
        .accessibilityLabel(title)
        .accessibilityValue(count == 1 ? "1 queue" : "\(count) queues")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Saved for Later, when the search and the tag filter both let it through.
    private var savedForLaterQueue: ReadingQueue? {
        readingQueues.first { $0.kind == .savedForLater && matchesTagFilter($0) && matchesSearch($0) }
    }

    /// Every queue's own hue tints its row; the page itself has no single
    /// subject, so its wash takes the app's own accent scope — the same choice
    /// `LibrarySectionListView.scopePalette` makes for the same reason.
    private var organizerPalette: SubjectPalette {
        themeManager.scopePalette
    }

    private var allWorks: [SavedWork] {
        readingQueues.flatMap(ReadingQueueService.orderedWorks(in:))
    }

    private var allPreservedWorks: [SavedWork] {
        allWorks.filter { $0.hasEPUB && FileManager.default.fileExists(atPath: $0.fileURL.path) }
    }

    private var allPreservedByteCount: Int64 {
        allPreservedWorks.reduce(0) { $0 + queueWorkFileSize($1.fileURL) }
    }

    var body: some View {
        List {
            Section {
                // 1i sets its header at 16, where the queue page (1h) uses 26.
                SubjectHeaderBlock(
                    kicker: "Home", title: "Queues", palette: organizerPalette,
                    gutter: SubjectMetrics.accountGutter
                )
                    .pageBodyRow(top: 20, gutter: 0)
                // 1i's tree puts the search between the title and the signal
                // strip, in the content — not in the navigation bar, where a
                // `.searchable` drawer would hide it until the list is scrolled.
                queueSearchField
                    .pageBodyRow(top: 12, gutter: SubjectMetrics.gutter)
                statStrip
                    .pageBodyRow(top: 8, gutter: SubjectMetrics.gutter)
            }

            // A persisted filter whose tag is gone still needs the rail's All chip,
            // or nothing on screen can clear it.
            if !queueTagNames.isEmpty || !tagFilter.isEmpty {
                Section {
                    tagRail.pageBodyRow(top: 14, gutter: 0)
                }
            }

            if !pinnedQueues.isEmpty {
                Section {
                    SectionRuleHeader(title: "Pinned", count: pinnedQueues.count)
                        .pageBodyRow(top: 18, gutter: 0)
                    ForEach(pinnedQueues) { queue in
                        organizerRow(queue, isReorderable: false)
                            .organizerCard(queue)
                            .swipeActions(edge: .trailing) { queueSwipes(queue) }
                    }
                }
            }

            Section {
                SectionRuleHeader(title: "All queues", count: visibleQueueCount)
                    .pageBodyRow(top: 18, gutter: 0)

                if let savedForLaterQueue {
                    organizerRow(savedForLaterQueue, isReorderable: false)
                        .organizerCard(savedForLaterQueue)
                }

                ForEach(customQueues) { queue in
                    organizerRow(queue, isReorderable: true)
                        .organizerCard(queue)
                        .swipeActions(edge: .trailing) { queueSwipes(queue) }
                }
                .onMove(perform: moveAction)

                // A search or tag filter that leaves nothing says so, with the
                // way back, rather than an empty "All queues 0".
                if visibleQueues.isEmpty, isSearching || !tagFilter.isEmpty {
                    ContentUnavailableView {
                        Label("No matching queues", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("No queue matches the current search and tag filter.")
                    } actions: {
                        Button("Clear Search and Filters") {
                            searchText = ""
                            tagFilter = ""
                        }
                    }
                    .bareListRow()
                }

                if !isSelecting {
                    newQueueRow
                        .pageBodyRow(top: 8, gutter: SubjectMetrics.gutter)
                }
            }
        }
        .cardList()
        .subjectScreenWash(palette: organizerPalette)
        // 1bg's grammar: the title bar takes the count while selecting.
        .navigationTitle(isSelecting ? "\(selection.count) selected" : "")
        .toolbar { toolbarContent }
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
    private var toolbarContent: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .confirmationAction) {
                SelectAllButton(allSelected: allSelected) {
                    selection = allSelected ? [] : Set(visibleQueues.map(\.id))
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
                    if readingQueues.count(where: { $0.kind == .custom }) > 1 {
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

    private var statStrip: some View {
        SubjectStatStrip(
            cells: [
                .init(value: readingQueues.count.compactCount, label: "Queues"),
                .init(value: allWorks.count.compactCount, label: "Works"),
                .init(value: allPreservedWorks.count.compactCount, label: "Offline"),
                .init(value: queueByteCountString(allPreservedByteCount), label: "Storage")
            ],
            palette: organizerPalette
        )
    }

    private var newQueueRow: some View {
        Button {
            newQueueName = ""
            showingNewQueue = true
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(organizerPalette.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("New queue")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Name it, colour it, tag it")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.rowRadius, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                .foregroundStyle(.tertiary)
        )
        .accessibilityElement(children: .combine)
        .accessibilityHint("Creates a new reading queue")
    }

    /// Edit and Delete for a custom queue, wherever its row is drawn —
    /// Pinned and All queues show the same queue. Saved for Later has neither.
    @ViewBuilder
    private func queueSwipes(_ queue: ReadingQueue) -> some View {
        if !isSelecting, queue.kind == .custom {
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
    private func organizerRow(_ queue: ReadingQueue, isReorderable: Bool) -> some View {
        let works = ReadingQueueService.orderedWorks(in: queue)
        let preserved = works.filter { $0.hasEPUB && FileManager.default.fileExists(atPath: $0.fileURL.path) }
        let byteCount = preserved.reduce(Int64(0)) { $0 + queueWorkFileSize($1.fileURL) }
        let storageLine = preserved.isEmpty
            ? "nothing kept yet"
            : "\(preserved.count) offline · \(queueByteCountString(byteCount))"
        // 1i: "count, tags and offline size on every row".
        let tagNames = queue.tags.map(\.name).sorted()
        let tagLine = tagNames.joined(separator: " · ")
        let palette = queue.kind == .custom
            ? themeManager.appTheme.subjectPalette(hue: queue.displayHue, pickedHex: queue.colorHex)
            : organizerPalette

        let isSelected = selection.contains(queue.id)
        let content = HStack(spacing: 12) {
            peekTile(queue, works: works)

            // 1i's row: dot · name · count, the per-work strip, then the tags
            // as chips with the storage line after them.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    if queue.kind == .custom {
                        Circle()
                            .fill(palette.accent)
                            .frame(width: 10, height: 10)
                            .accessibilityHidden(true)
                    }
                    Text(queue.displayName)
                        .font(.system(size: rowTitleSize, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    Text(works.count.compactCount)
                        .font(.system(size: rowCountSize, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if !works.isEmpty {
                    QueueProgressStrip(
                        progress: ReadingQueueFacts.progress(of: works.map(\.readingState)),
                        palette: palette
                    )
                    .accessibilityHidden(true)
                }
                FlowLayout(spacing: 6, rowSpacing: 4) {
                    ForEach(tagNames, id: \.self) { name in
                        QueueRowTagLabel(text: name)
                    }
                    Text(storageLine)
                        .font(.system(size: rowStorageSize))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if isSelecting {
                WorkSelectionBubble(isSelected: isSelected)
            }
        }
        .contentShape(Rectangle())
        let summary = "\(works.count) work\(works.count == 1 ? "" : "s"), "
            + "\(tagLine.isEmpty ? "" : "\(tagLine), ")\(storageLine)"

        Group {
            if isSelecting {
                Button {
                    if isSelected { selection.remove(queue.id) } else { selection.insert(queue.id) }
                } label: {
                    content
                }
            } else {
                NavigationLink(value: AllReadingQueuesDestination(initialQueueID: queue.id)) {
                    content
                }
            }
        }
        .buttonStyle(.plain)
        .moveDisabled(!isReorderable)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isSelecting ? "\(isSelected ? "Selected" : "Not selected"), \(summary)" : summary)
        .accessibilityAddTraits(isSelecting && isSelected ? .isSelected : [])
    }

    /// 1i: "a 2×2 peek tile of the queue's first four works (ReadingQueueCard's
    /// idea, at 44px)". The queue's colour is the card's wash and the dot, so
    /// the tile's glass stays plain and each cell is a work's colour.
    private func peekTile(_ queue: ReadingQueue, works: [SavedWork]) -> some View {
        QueuePeekTile(
            spacing: 2.5,
            inset: 3,
            cornerRadius: 9,
            tint: nil
        ) { index in
            let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
            if index < works.count {
                let work = works[index]
                shape.fill(
                    themeManager.appTheme.subjectPalette(
                        hue: CoverArt.workHue(fandoms: work.workFandoms, title: work.title)
                    ).accent.opacity(0.4)
                )
            } else {
                shape.fill(Color.primary.opacity(0.05))
            }
        }
        .frame(width: 44, height: 44)
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
        var ids = customQueues.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        reorderCustomQueues(ids, context: context)
    }

    private func createQueue(_ options: NewQueueOptions) {
        let trimmed = newQueueName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let hue = newQueueHue
        newQueueName = ""
        newQueueHue = nil
        showingNewQueue = false
        _ = ReadingQueueService.createQueue(
            named: trimmed,
            hue: hue,
            colorHex: options.colorHex,
            keepsWorksOffline: options.keepsWorksOffline,
            seededFrom: options.seed,
            tagNames: options.tagNames,
            in: context
        )
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
    /// Saved for Later can't be deleted — no row offers it — so a bulk Delete
    /// takes the custom queues in the selection and nothing else.
    static func deletable(_ queues: [ReadingQueue]) -> [ReadingQueue] {
        queues.filter { $0.kind == .custom }
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
            ? "The queue moves to Recently Deleted "
                + "for \(PreservedWorkService.recoveryWindowText), with everything in it "
                + "intact. Works stay in Kudos either way."
            : "The \(count) queues move to Recently Deleted "
                + "for \(PreservedWorkService.recoveryWindowText), with everything in them "
                + "intact. Works stay in Kudos either way."
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
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Text(text.uppercased())
            .font(.system(size: fontSize, weight: .semibold))
            .tracking(fontSize * 0.06)
            .foregroundStyle(.secondary)
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

private extension View {
    /// 1i draws every queue as a card washed in its own colour (radius 16,
    /// 11pt top and bottom, 8pt apart). Saved for Later has no colour.
    func organizerCard(_ queue: ReadingQueue) -> some View {
        cardRow(
            tintHue: queue.kind == .custom ? queue.displayHue : nil,
            tintHex: queue.kind == .custom ? queue.colorHex : nil,
            cornerRadius: 16,
            verticalPadding: 11,
            interCardSpacing: 8
        )
    }
}
