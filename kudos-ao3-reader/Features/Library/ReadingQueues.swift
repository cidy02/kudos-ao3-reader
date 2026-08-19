import Foundation
import OSLog
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// swiftlint:disable file_length

/// Navigation route for Reading Queues beyond the Library carousel.
/// - `initialQueueID == nil` — the full grid of queue stack cards ("See all" chevron).
/// - non-nil — the Safari-style browser pre-selected on that queue (carousel tile
///   or a stack tapped inside the grid).
struct AllReadingQueuesDestination: Hashable {
    var initialQueueID: UUID?
}

/// Full grid of Reading Queue stack cards behind the Library carousel chevron.
/// Owns its own "New Queue" sheet so creation works while this destination is
/// pushed (parent LibraryView alerts often don't present on top of a nav child).
struct AllReadingQueuesGridView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<ReadingQueue> { !$0.isPendingDeletion }, sort: \ReadingQueue.sortOrder)
    private var readingQueues: [ReadingQueue]

    @State private var showingNewQueue = false
    @State private var newQueueName = ""

    private var customQueues: [ReadingQueue] {
        readingQueues
            .filter { $0.kind == .custom }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        LibraryEntityGridView(
            title: "Reading Queues",
            items: customQueues,
            destination: { AllReadingQueuesDestination(initialQueueID: $0.id) },
            onNew: {
                newQueueName = ""
                showingNewQueue = true
            },
            card: { ReadingQueueCard(queue: $0) },
            newCard: { NewReadingQueueCard() }
        )
        .sheet(isPresented: $showingNewQueue) {
            NavigationStack {
                Form {
                    TextField("Name", text: $newQueueName)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif
                }
                .navigationTitle("New Queue")
                #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            newQueueName = ""
                            showingNewQueue = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            createQueue()
                        }
                        .disabled(newQueueName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            #if os(iOS)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            #endif
        }
    }

    private func createQueue() {
        let trimmed = newQueueName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        newQueueName = ""
        showingNewQueue = false
        _ = ReadingQueueService.createQueue(named: trimmed, in: context)
    }
}

// MARK: - Cards

struct ReadingQueueCard: View {
    @Environment(ThemeManager.self) private var themeManager
    let queue: ReadingQueue

    /// Scales width and height together so the card grows proportionally at
    /// large Dynamic Type sizes instead of only getting taller.
    var cardSize = ScaledCarouselCardSize()

    /// Explicit, non-defaulted init — the compiler-synthesized memberwise
    /// init's defaulted `cardSize:` parameter measurably slows type-checking
    /// of the already-long `.navigationDestination` chain this card is
    /// constructed inside (LibraryView.swift), to the point of a hard
    /// "unable to type-check in reasonable time" build failure.
    init(queue: ReadingQueue) {
        self.queue = queue
    }

    // Ordered the same way the queue's own detail view is (sortOrderInQueue).
    // Memberships of a soft-deleted work survive (so restoring it re-joins its
    // queues), but the work itself belongs to Recently Deleted, not this card —
    // orderedWorks already excludes it.
    private var works: [SavedWork] {
        ReadingQueueService.orderedWorks(in: queue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            tile
                // Exact, not `minHeight:` — a flexible `Shape`/grid fill given only
                // a floor grows to soak up whatever extra height the row proposes
                // to match a taller sibling. Pinning both dimensions keeps this
                // tile at its sqrt(2):1 ratio regardless of what the row offers.
                .frame(width: cardSize.width, height: cardSize.height)
            Text(queue.displayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)
            Text("\(works.count) work\(works.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: cardSize.width, alignment: .leading)
    }

    // Safari Tab-Groups style: a 2×2 grid of the queue's own first 4 works (each
    // its own hued title/author cell), reading as a peek at what's actually
    // queued rather than an abstract icon. An empty queue has no titles to
    // preview, so it shows 4 skeleton cells in the same grid shape instead —
    // "a place for works to land" rather than a dead, contentless tile.
    @ViewBuilder
    private var tile: some View {
        if works.isEmpty {
            skeletonGrid
        } else {
            tabGroupGrid
        }
    }

    private var tabGroupGrid: some View {
        let cells = Array(works.prefix(4))
        return gridFrame {
            HStack(spacing: 4) {
                gridCell(!cells.isEmpty ? cells[0] : nil)
                gridCell(cells.count > 1 ? cells[1] : nil)
            }
            HStack(spacing: 4) {
                gridCell(cells.count > 2 ? cells[2] : nil)
                gridCell(cells.count > 3 ? cells[3] : nil)
            }
        }
    }

    // No `.skeletonShimmer()` — this isn't a loading state waiting on a request
    // (that's what the shimmer promises elsewhere), just a static placeholder
    // shape showing where works will land once the queue has some.
    private var skeletonGrid: some View {
        gridFrame {
            HStack(spacing: 4) {
                skeletonCell()
                skeletonCell()
            }
            HStack(spacing: 4) {
                skeletonCell()
                skeletonCell()
            }
        }
    }

    /// Shared 2×2 grid chrome (padding, material background, border, shadow) —
    /// both `tabGroupGrid` and `skeletonGrid` are just this frame around
    /// different row content.
    private func gridFrame(@ViewBuilder rows: () -> some View) -> some View {
        VStack(spacing: 4, content: rows)
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: CarouselCardMetrics.cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CarouselCardMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.12), radius: 5, x: 0, y: 2)
    }

    /// One skeleton cell, matching `gridCell`'s current layout so an empty
    /// queue previews the same shape it'll fill into: title placeholder,
    /// a 2×2 of blocks the same size as `miniStatusTile`'s real tiles, then
    /// author/fandom placeholder lines.
    private func skeletonCell() -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return VStack(alignment: .leading, spacing: 2) {
            SkeletonTextLine(height: 7, width: 40)
            Spacer(minLength: 0)
            skeletonStatusGrid
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            SkeletonTextLine(height: 6, width: 32)
            SkeletonTextLine(height: 5, width: 28)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.05))
        .clipShape(shape)
    }

    /// Placeholder for `miniStatusGrid` — same 14×14/3pt-radius/2pt-gap
    /// geometry as `miniStatusTile`, just `SkeletonBlock` instead of a real
    /// hued icon tile.
    private var skeletonStatusGrid: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                SkeletonBlock(height: 14, width: 14, cornerRadius: 3)
                SkeletonBlock(height: 14, width: 14, cornerRadius: 3)
            }
            HStack(spacing: 2) {
                SkeletonBlock(height: 14, width: 14, cornerRadius: 3)
                SkeletonBlock(height: 14, width: 14, cornerRadius: 3)
            }
        }
    }

    /// One grid cell, left-aligned like every other card in the app, over its
    /// own title-hued tint: `work`'s title at top, its rating/category/
    /// warnings/completion as a compact icon-only 2×2 (AO3's own tag-grid
    /// idea, reimagined for this app's chip colors/symbols) centered in the
    /// middle, then author and fandom at the bottom. An empty placeholder
    /// when the queue has fewer than 4 works.
    @ViewBuilder
    private func gridCell(_ work: SavedWork?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Group {
            if let work {
                let hue = CoverArt.hue(for: work.title)
                VStack(alignment: .leading, spacing: 2) {
                    Text(work.title)
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    miniStatusGrid(for: work)
                        .frame(maxWidth: .infinity)
                    Spacer(minLength: 0)
                    if !work.author.isEmpty {
                        Text(work.author)
                            .font(.system(size: 8))
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                    if let fandom = work.workFandoms.first, !fandom.isEmpty {
                        Text(fandom)
                            .font(.system(size: 7))
                            .lineLimit(1)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(themeManager.appTheme.carouselCardTint(hue: hue))
            } else {
                Color.clear
            }
        }
        .clipShape(shape)
    }

    /// `work`'s rating/category/warnings/completion — same per-facet symbol and
    /// color `WorkTopStatsRow` already resolves everywhere else in the app
    /// (AO3's real category-collapsing rules included) — as 4 icon-only tiles,
    /// no text. Decorative: the cell's own title above is the real accessible
    /// content here, same as `StackedWorkCover`'s hidden decorative stack.
    private func miniStatusGrid(for work: SavedWork) -> some View {
        let items = WorkTopStatsRow(
            rating: work.rating.isEmpty ? nil : work.rating,
            categories: work.workCategories,
            warnings: work.workWarnings,
            completion: work.completionStatus
        ).topItems
        return VStack(spacing: 2) {
            HStack(spacing: 2) {
                miniStatusTile(!items.isEmpty ? items[0] : nil)
                miniStatusTile(items.count > 1 ? items[1] : nil)
            }
            HStack(spacing: 2) {
                miniStatusTile(items.count > 2 ? items[2] : nil)
                miniStatusTile(items.count > 3 ? items[3] : nil)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func miniStatusTile(_ item: WorkTopStatsRow.Item?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        if let item {
            shape
                .fill((item.iconColor ?? .gray).opacity(0.3))
                .overlay {
                    // Rating (AO3's own quadrant reads a letter, not a checkmark):
                    // no `{letter}.shield` SF Symbol exists — confirmed against
                    // the live catalog, unlike `{letter}.circle`/`.square`, which
                    // do — so the letter is composited by hand over a filled
                    // shield instead of a single systemName.
                    if item.symbol == "checkmark.shield" {
                        ratingShield(item)
                    } else {
                        Image(systemName: item.symbol)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(item.iconColor ?? .gray)
                    }
                }
                .frame(width: 14, height: 14)
        } else {
            Color.clear.frame(width: 14, height: 14)
        }
    }

    private func ratingShield(_ item: WorkTopStatsRow.Item) -> some View {
        // "NR" (WorkStat.ratingLetter's own text for Not Rated) is two
        // characters — cramped at this size, and "?" already reads as
        // "unrated/unknown" without needing to fit two glyphs.
        let letter = item.text == "NR" ? "?" : item.text
        return ZStack {
            // Matches the other 3 tiles' own 8pt icon size — was 13pt, visibly
            // heavier than its neighbors in the same grid.
            Image(systemName: "shield.fill")
                .font(.system(size: 9))
                .foregroundStyle(item.iconColor ?? .gray)
            Text(letter)
                .font(.system(size: 5, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                // Shields taper at the bottom point, so their centroid sits
                // above true geometric center — an un-offset letter reads low.
                .offset(y: -0.5)
        }
    }
}

struct NewReadingQueueCard: View {
    /// Scales width and height together so the card grows proportionally at
    /// large Dynamic Type sizes instead of only getting taller.
    var cardSize = ScaledCarouselCardSize()

    /// Explicit, non-defaulted init — see `ReadingQueueCard.init`.
    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: CarouselCardMetrics.cornerRadius, style: .continuous)
                .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                // Exact, not `minHeight:` — see ReadingQueueCard's own tile frame
                // for why a flexible `Shape` fill can't be bounded by a minimum
                // alone in a row where a sibling card might end up taller.
                .frame(width: cardSize.width, height: cardSize.height)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            Text("New Queue")
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)
            Text("Tap to create")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: cardSize.width, alignment: .leading)
    }
}

// MARK: - Queue detail (redirect)

/// Formerly the full manage surface. Management now lives on
/// `ReadingQueueBrowserView` (queue switcher + filters/reorder/select/rename).
/// Kept as a thin entry point for any remaining `NavigationLink(value: ReadingQueue)`.
struct ReadingQueueDetailView: View {
    let queue: ReadingQueue

    var body: some View {
        ReadingQueueBrowserView(initialQueueID: queue.id)
    }
}

/// Live-reorders as the drag crosses into each card's drop target, purely from
/// local state — the drag payload itself is never decoded back, which keeps this
/// synchronous and avoids `NSItemProvider` async-decode pitfalls for what is always
/// a same-app-only reorder. `dropEntered` writes only `pendingOrder` (plain local
/// state); the SwiftData write is deferred to `performDrop`. An earlier version
/// called `ReadingQueueService.reorder(_:)` straight from `dropEntered` on every
/// drag-over. The actual failure wasn't the resulting SwiftUI re-render by itself —
/// this type's ForEach already re-renders on every `pendingOrder` write today, and
/// that's fine, because `SavedWork` identities stay stable across a plain local-array
/// reorder. What broke the drag was that call's `context.saveBestEffort` writing
/// `queue.memberships` — a SwiftData relationship this screen *observes* — which
/// invalidates the owning `@Model` and tore down the OS drag session mid-gesture, not
/// merely rebuilding views under it. That's the reproduced failure behind A6-F1
/// (owner-confirmed broken): the drag visibly starts but never completes, and nothing
/// is ever persisted. A future edit must not reintroduce any observed-model write
/// inside `dropEntered` — only `performDrop`, once the gesture has actually ended, is
/// safe for that.
struct WorkReorderDropDelegate: DropDelegate {
    let target: SavedWork
    let works: [SavedWork]
    @Binding var draggedWorkID: UUID?
    @Binding var pendingOrder: [UUID]?
    let queue: ReadingQueue
    let context: ModelContext

    /// What this drag is currently reordering relative to: the in-progress preview
    /// if this is a continuation of the same gesture (it already crossed at least
    /// one other card), otherwise the persisted order the drag started from.
    private var baseOrder: [UUID] {
        pendingOrder ?? works.map(\.id)
    }

    func dropEntered(info: DropInfo) {
        guard let draggedWorkID else { return }
        pendingOrder = ReadingQueueService.reorderedIDs(base: baseOrder, moving: draggedWorkID, over: target.id)
    }

    func performDrop(info: DropInfo) -> Bool {
        // Persist only when the drag actually changed the order. `reorderedIDs` is a
        // no-op for a self-hover (which fires at drag start, over the source card's
        // own drop target) and for a cross-and-return, so `pendingOrder` can be
        // non-nil yet equal to the stored order; committing that would rewrite every
        // `sortOrderInQueue`, flip all memberships to `.pending` for sync, and hit
        // disk for a drag that moved nothing. `works` is unmutated during the gesture
        // (the whole point of deferring the write), so it's still the pre-drag order.
        if let pendingOrder, pendingOrder != works.map(\.id) {
            ReadingQueueService.reorder(pendingOrder, in: queue, context: context)
        }
        pendingOrder = nil
        draggedWorkID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

// MARK: - Queue storage

struct ReadingQueueStorageView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }, sort: \SavedWork.dateAdded, order: .reverse)
    private var works: [SavedWork]
    @State private var pendingQueueRemoval: SavedWork?

    private var queuedWorks: [SavedWork] {
        works.filter(\.isQueuedForLater)
    }

    private var preservedWorks: [SavedWork] {
        queuedWorks.filter { work in
            work.hasEPUB && FileManager.default.fileExists(atPath: work.fileURL.path)
        }
    }

    private var queueOnlyWorks: [SavedWork] {
        queuedWorks.filter(\.isQueueOnlyWork)
    }

    private var preservedByteCount: Int64 {
        preservedWorks.reduce(0) { total, work in
            total + fileSize(for: work.fileURL)
        }
    }

    var body: some View {
        List {
            Group {
                Section("Summary") {
                    LabeledContent("Queued Works", value: queuedWorks.count.formatted())
                    LabeledContent("Queue-only Works", value: queueOnlyWorks.count.formatted())
                    LabeledContent("Preserved EPUBs", value: preservedWorks.count.formatted())
                    LabeledContent("Preserved Storage", value: byteString(preservedByteCount))
                }

                Section {
                    if preservedWorks.isEmpty {
                        Text("No queued EPUBs are currently stored on this device.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(preservedWorks) { work in
                            preservedWorkRow(work)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        pendingQueueRemoval = work
                                    } label: {
                                        Label("Remove from Queues", systemImage: "minus.circle")
                                    }
                                    Button {
                                        WorkLifecycle.setSaved(work, true, in: context)
                                    } label: {
                                        Label(
                                            WorkActionLabels.saved(isSaved: false).title,
                                            systemImage: WorkActionLabels.saved(isSaved: false).systemImage
                                        )
                                    }
                                    .tint(.blue)
                                }
                                .contextMenu {
                                    Button {
                                        WorkLifecycle.setSaved(work, true, in: context)
                                    } label: {
                                        Label(
                                            WorkActionLabels.saved(isSaved: false).title,
                                            systemImage: WorkActionLabels.saved(isSaved: false).systemImage
                                        )
                                    }
                                    Button(role: .destructive) {
                                        pendingQueueRemoval = work
                                    } label: {
                                        Label("Remove from Reading Queues", systemImage: "minus.circle")
                                    }
                                }
                        }
                    }
                } header: {
                    Text("Preserved EPUBs")
                } footer: {
                    Text("Removing a work here only removes queue membership. Saved or favorited works stay "
                        + "in Kudos; queue-only works are removed when no queues remain.")
                }
            }
            .appThemedRows()
        }
        .appThemedScroll()
        .navigationTitle("Queue Storage")
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .confirmationDialog(
                "Remove from reading queues?",
                isPresented: Binding(
                    get: { pendingQueueRemoval != nil },
                    set: { if !$0 { pendingQueueRemoval = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(queueRemovalButtonTitle, role: .destructive) {
                    if let work = pendingQueueRemoval {
                        removeFromQueues(work)
                    }
                    pendingQueueRemoval = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingQueueRemoval = nil
                }
            } message: {
                Text(queueRemovalMessage)
            }
    }

    private func preservedWorkRow(_ work: SavedWork) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: work.isInSavedForLaterQueue
                ? WorkActionLabels.savedForLaterSymbol
                : "list.bullet.rectangle")
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(work.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if !work.author.isEmpty {
                    AO3AuthorBylineView(
                        displayText: work.author,
                        identities: work.verifiedAuthorIdentities,
                        includesBy: false,
                        font: .caption,
                        compact: true
                    )
                }
                Text(byteString(fileSize(for: work.fileURL)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if work.isQueueOnlyWork {
                Text("Queue")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var queueRemovalMessage: String {
        guard let work = pendingQueueRemoval else { return "" }
        if work.isSaved || work.isFavorite {
            return "This keeps the work in your Library and only removes its reading queue membership."
        }
        return "This queue-only work will be removed from Kudos if it has no remaining queues."
    }

    private var queueRemovalButtonTitle: String {
        guard let work = pendingQueueRemoval else { return "Remove from Queues" }
        return work.isQueueOnlyWork ? "Remove Queues & Delete" : "Remove from Queues"
    }

    private func removeFromQueues(_ work: SavedWork) {
        ReadingQueueService.removeFromAllQueuesAndDeleteIfQueueOnly(work, in: context)
    }

    private func fileSize(for url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Add to queue

struct AddToQueueView: View {
    let works: [SavedWork]

    init(work: SavedWork) {
        works = [work]
    }

    init(works: [SavedWork]) {
        self.works = works
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<ReadingQueue> { !$0.isPendingDeletion }, sort: \ReadingQueue.sortOrder)
    private var queues: [ReadingQueue]
    @State private var newName = ""
    @State private var workingQueueIDs: Set<UUID> = []
    @State private var includeSeries = false
    @State private var checkingSeriesPreview = false
    @State private var seriesPrompt: ReadingQueueService.SeriesPreservationPrompt?
    @State private var preservingSeries = false
    @State private var seriesResult: ReadingQueueService.SeriesPreservationResult?
    @State private var seriesTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("New queue", text: $newName)
                            .onSubmit(create)
                        Button("Add", action: create)
                            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section {
                    ForEach(sortedQueues) { queue in
                        Button {
                            toggle(queue)
                        } label: {
                            HStack {
                                Label(queue.displayName, systemImage: queueSymbol(queue))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if workingQueueIDs.contains(queue.id) {
                                    ProgressView()
                                } else if isMember(queue) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                        .accessibilityLabel("In this queue")
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Queues")
                } footer: {
                    Text("Queue membership keeps a local EPUB available without marking the work as saved.")
                }

                if hasSeries {
                    Section {
                        Toggle("Also add works from this AO3 series", isOn: $includeSeries)

                        if includeSeries {
                            if checkingSeriesPreview {
                                HStack {
                                    ProgressView()
                                    Text("Checking series size…")
                                        .foregroundStyle(.secondary)
                                }
                            } else if let seriesPrompt {
                                Text(seriesPrompt.message)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            Button {
                                preserveSelectedSeries()
                            } label: {
                                HStack {
                                    Label("Add Series to Selected Queues", systemImage: "square.stack.3d.up")
                                    Spacer()
                                    if preservingSeries { ProgressView() }
                                }
                            }
                            .disabled(preservingSeries || selectedQueuesForSeries.isEmpty)

                            if preservingSeries {
                                Button(role: .cancel) {
                                    cancelSeriesPreservation()
                                } label: {
                                    Label("Cancel Series Addition", systemImage: "xmark.circle")
                                }
                            }

                            if let seriesResult {
                                Text(seriesCompletionText(seriesResult))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Series")
                    } footer: {
                        Text("Series works are added only after you tap the series action. Requests are paced.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add to Queue")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { dismiss() } label: {
                            Image(systemName: "checkmark")
                        }
                        .accessibilityLabel("Done")
                    }
                }
                .task {
                    ReadingQueueService.ensureSavedForLaterQueue(in: context)
                }
                .onChange(of: includeSeries) { _, isEnabled in
                    if isEnabled {
                        Task { await loadSeriesPreview() }
                    } else {
                        seriesPrompt = nil
                        seriesResult = nil
                    }
                }
                // Search → Add to Queue creates a metadata-only stub so the sheet can
                // open instantly. If the user never joins a queue, drop that stub so it
                // doesn't show up as empty History.
                .onDisappear {
                    for work in works {
                        ReadingQueueService.discardUnattachedMetadataIfNeeded(work, in: context)
                    }
                }
        }
        .presentationDragIndicator(.visible)
    }

    private var sortedQueues: [ReadingQueue] {
        queues.sorted {
            if $0.kind != $1.kind { return $0.kind == .savedForLater }
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.displayName < $1.displayName
        }
    }

    private func isMember(_ queue: ReadingQueue) -> Bool {
        works.allSatisfy { work in work.queueMemberships.contains { $0.queue?.id == queue.id } }
    }

    private func queueSymbol(_ queue: ReadingQueue) -> String {
        queue.kind == .savedForLater
            ? WorkActionLabels.savedForLaterEmptySymbol
            : "list.bullet.rectangle"
    }

    // Series preservation is anchored to a single AO3 series, so it only applies
    // when this sheet is managing one work.
    private var soloWork: SavedWork? {
        works.count == 1 ? works[0] : nil
    }

    private var hasSeries: Bool {
        guard let soloWork else { return false }
        return URL(string: soloWork.seriesURL) != nil && !soloWork.seriesURL.isEmpty
    }

    private var selectedQueuesForSeries: [ReadingQueue] {
        sortedQueues.filter(isMember)
    }

    private func loadSeriesPreview() async {
        guard includeSeries, let soloWork, let url = URL(string: soloWork.seriesURL) else { return }
        checkingSeriesPreview = true
        do {
            let preview = try await AO3Client.shared.seriesPreview(seriesURL: url)
            seriesPrompt = ReadingQueueService.seriesPrompt(for: preview, threshold: 5)
        } catch {
            seriesPrompt = ReadingQueueService.seriesPrompt(for: nil, threshold: 5, previewFailed: true)
        }
        checkingSeriesPreview = false
    }

    private func preserveSelectedSeries() {
        guard !preservingSeries, let soloWork, URL(string: soloWork.seriesURL) != nil else { return }
        let queues = selectedQueuesForSeries
        guard !queues.isEmpty else { return }
        preservingSeries = true
        seriesResult = nil
        seriesTask = Task { @MainActor in
            let result: ReadingQueueService.SeriesPreservationResult = if let seriesPrompt,
                                                                          seriesPrompt.canUsePreviewForPreservation,
                                                                          let summaries = seriesPrompt.preview?.works {
                await ReadingQueueService.preserveSeries(
                    summaries,
                    to: queues,
                    in: context,
                    progress: { seriesResult = $0 }
                )
            } else {
                await ReadingQueueService.preserveSeries(
                    anchoredAt: soloWork,
                    to: queues,
                    in: context,
                    progress: { seriesResult = $0 }
                )
            }
            seriesResult = result
            preservingSeries = false
            seriesTask = nil
        }
    }

    private func cancelSeriesPreservation() {
        seriesTask?.cancel()
        preservingSeries = false
    }

    private func toggle(_ queue: ReadingQueue) {
        if isMember(queue) {
            for work in works {
                ReadingQueueService.removeFromQueue(work, from: queue, in: context)
            }
            return
        }
        let nonMembers = works.filter { work in !work.queueMemberships.contains { $0.queue?.id == queue.id } }
        workingQueueIDs.insert(queue.id)
        Task {
            for work in nonMembers {
                _ = await ReadingQueueService.addAndPreserve(work, to: queue, in: context)
            }
            workingQueueIDs.remove(queue.id)
        }
    }

    private func seriesCompletionText(_ result: ReadingQueueService.SeriesPreservationResult) -> String {
        if preservingSeries, result.total > 0 {
            return "Adding \(result.completed) of \(result.total) series works…"
        }
        if result.cancelled > 0 {
            return "Series preservation cancelled. Added \(result.preserved) work"
                + "\(result.preserved == 1 ? "" : "s")."
        }
        if result.total == 0 { return "No series works were found." }
        let parts = result.summaryParts(verb: "added")
        return parts.isEmpty ? "Series works are already in the selected queues." : parts.joined(separator: ", ") + "."
    }

    private func create() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let queue = ReadingQueueService.createQueue(named: trimmed, in: context)
        newName = ""
        workingQueueIDs.insert(queue.id)
        Task {
            for work in works {
                _ = await ReadingQueueService.addAndPreserve(work, to: queue, in: context)
            }
            workingQueueIDs.remove(queue.id)
        }
    }
}
