import Foundation
import SwiftData
import SwiftUI

/// Artboard **1i**'s "Queues — organizer": the full list of every queue behind
/// the Library carousel's "See all" chevron. Was a `LibraryEntityGridView`
/// wrapping the carousel's own `ReadingQueueCard` — a 2-column grid with no
/// swipe actions, no reorder, and no per-queue detail beyond the title and a
/// work count. This restyles it into 1i's shape: a header stat strip across
/// every queue, then one reorderable row per queue with its own tally and
/// storage line.
///
/// **What 1i draws that this does not build, and why:**
/// - The "Search queues, tags and works" search field. There is no
///   cross-queue/tag/work search anywhere in the app to back it — building the
///   field without the search behind it would be decoration, not a control.
/// - The tag filter pills are **built now**: `ReadingQueue.tags` exists, so the
///   rail filters on the real relationship. Their "Edit tags" chip is not — tags
///   are edited per queue in Queue Details (1h), not from a rail that filters by
///   them, and a second editor here would be two ways to write one list.
/// - The "Pinned" section. There is no per-queue pin/favorite flag — Saved for
///   Later is the only queue this app treats specially, and it already gets
///   its own un-reorderable row at the top of "All Queues" here, which is what
///   the mock's "Pinned" section is standing in for.
/// - The "Name it, colour it, tag it" copy on the New Queue row. Creating a
///   queue only takes a name — colour is derived from that name
///   (`CoverArt.hue`) and there is no tag step — so this keeps the existing,
///   accurate "Tap to create" line instead.
/// - The mini 2×2 "tab group" preview tile `ReadingQueueCard` draws on Home's
///   carousel. Reusing it here would mean either building a second copy of its
///   (currently `private`, single-type-scoped) tile logic or reaching across a
///   `Home`-owned file this task does not touch; a plain hue dot (`queueGlyph`'s
///   own device, used identically in `ReadingQueueBrowserView`) carries the same
///   identity information at a fraction of the code.
struct AllReadingQueuesGridView: View {
    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var themeManager
    @Query(filter: #Predicate<ReadingQueue> { !$0.isPendingDeletion }, sort: \ReadingQueue.sortOrder)
    private var readingQueues: [ReadingQueue]

    @State private var showingNewQueue = false
    @State private var newQueueHue: Double?
    /// 1i's tag rail. Empty means All; `untaggedFilter` means the queues with no
    /// tags; anything else is a tag name.
    @AppStorage("library.queueOrganizer.tagFilter") private var tagFilter = ""
    @State private var newQueueName = ""
    @State private var pendingRename: ReadingQueue?
    @State private var renameText = ""
    @State private var pendingDelete: ReadingQueue?
    /// 1i: "search over queues, tags and works". One field over all three,
    /// rather than three — the reader is looking for a queue and does not know
    /// or care which of the three matched it.
    ///
    /// Outside the platform guard: the search field and the filtering it feeds
    /// are both shared code, so guarding the declaration left them undefined on
    /// macOS and broke that build. Only the reorder state below is iOS-shaped.
    @State private var searchText = ""
    #if os(iOS)
    @State private var reorderMode: EditMode = .inactive
    #else
    @State private var isReorderingMac = false
    #endif

    private var isReordering: Bool {
        #if os(iOS)
        reorderMode.isEditing
        #else
        isReorderingMac
        #endif
    }

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
        let savedForLaterShown = savedForLaterQueue.map(matchesSearch) ?? false
        return customQueues.count + (savedForLaterShown ? 1 : 0)
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
                tagChip("All", value: "")
                ForEach(queueTagNames, id: \.self) { name in
                    tagChip(name, value: name)
                }
                if readingQueues.contains(where: { $0.tags.isEmpty }) {
                    tagChip("Untagged", value: Self.untaggedFilter)
                }
            }
            .padding(.horizontal, SubjectMetrics.gutter)
        }
    }

    private func tagChip(_ title: String, value: String) -> some View {
        let isSelected = tagFilter == value
        return Button {
            tagFilter = isSelected ? "" : value
        } label: {
            SubjectChip(
                text: title,
                style: .pill(isSelected: isSelected),
                palette: organizerPalette
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var savedForLaterQueue: ReadingQueue? {
        readingQueues.first { $0.kind == .savedForLater }
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
                SubjectHeaderBlock(kicker: "Library", title: "Queues", palette: organizerPalette)
                    .pageBodyRow(top: 20, gutter: 0)
                // 1i's tree puts the search between the title and the signal
                // strip, in the content — not in the navigation bar, where a
                // `.searchable` drawer would hide it until the list is scrolled.
                queueSearchField
                    .pageBodyRow(top: 12, gutter: SubjectMetrics.gutter)
                statStrip
                    .pageBodyRow(top: 8, gutter: SubjectMetrics.gutter)
            }

            if !queueTagNames.isEmpty {
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
                            .pageBodyRow(top: 8, gutter: SubjectMetrics.gutter)
                    }
                }
            }

            Section {
                SectionRuleHeader(title: "All queues", count: visibleQueueCount)
                    .pageBodyRow(top: 18, gutter: 0)

                if let savedForLaterQueue, matchesSearch(savedForLaterQueue) {
                    organizerRow(savedForLaterQueue, isReorderable: false)
                        .pageBodyRow(top: 8, gutter: SubjectMetrics.gutter)
                }

                ForEach(customQueues) { queue in
                    organizerRow(queue, isReorderable: true)
                        .pageBodyRow(top: 8, gutter: SubjectMetrics.gutter)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDelete = queue
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                renameText = queue.name
                                pendingRename = queue
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                }
                .onMove(perform: moveCustomQueues)

                newQueueRow
                    .pageBodyRow(top: 8, gutter: SubjectMetrics.gutter)
            }
        }
        .cardList()
        .subjectScreenWash(palette: organizerPalette)
        #if os(iOS)
        .environment(\.editMode, $reorderMode)
        #endif
        .toolbar {
            if !customQueues.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(isReordering ? "Done" : "Reorder") {
                        setReordering(!isReordering)
                    }
                }
            }
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
        .alert(
            "Rename Queue",
            isPresented: Binding(get: { pendingRename != nil }, set: { if !$0 { pendingRename = nil } })
        ) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let queue = pendingRename {
                    let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        queue.name = trimmed
                        queue.markModified()
                        context.saveBestEffort(reason: "Saving queue rename failed")
                    }
                }
                pendingRename = nil
            }
            Button("Cancel", role: .cancel) { pendingRename = nil }
        }
        .confirmationDialog(
            "Delete “\(pendingDelete?.displayName ?? "Queue")”?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let queue = pendingDelete {
                    PreservedWorkService.softDelete(queue, in: context)
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text(
                "The queue moves to Recently Deleted for 90 days, with everything in it "
                    + "intact. Works stay in Kudos either way."
            )
        }
    }

    private var statStrip: some View {
        SubjectStatStrip(
            cells: [
                .init(value: "\(readingQueues.count)", label: "Queues"),
                .init(value: "\(allWorks.count)", label: "Works"),
                .init(value: "\(allPreservedWorks.count)", label: "Offline"),
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
                    Text("New Queue")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Tap to create")
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

    @ViewBuilder
    private func organizerRow(_ queue: ReadingQueue, isReorderable: Bool) -> some View {
        let works = ReadingQueueService.orderedWorks(in: queue)
        let preserved = works.filter { $0.hasEPUB && FileManager.default.fileExists(atPath: $0.fileURL.path) }
        let byteCount = preserved.reduce(Int64(0)) { $0 + queueWorkFileSize($1.fileURL) }
        let storageLine = preserved.isEmpty
            ? "nothing kept yet"
            : "\(preserved.count) offline · \(queueByteCountString(byteCount))"

        NavigationLink(value: AllReadingQueuesDestination(initialQueueID: queue.id)) {
            HStack(spacing: 12) {
                if queue.kind == .savedForLater {
                    Image(systemName: WorkActionLabels.savedForLaterEmptySymbol)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                } else {
                    Circle()
                        .fill(themeManager.appTheme.carouselQueueTint(hue: queue.displayHue))
                        .frame(width: 12, height: 12)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(queue.displayName)
                            .font(.system(size: 15.5, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("\(works.count)")
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Text(storageLine)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .moveDisabled(!isReorderable)
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            "\(works.count) work\(works.count == 1 ? "" : "s"), \(storageLine)"
        )
    }

    private func setReordering(_ active: Bool) {
        #if os(iOS)
        reorderMode = active ? .active : .inactive
        #else
        isReorderingMac = active
        #endif
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
            keepsWorksOffline: options.keepsWorksOffline,
            seededFrom: options.seed,
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
