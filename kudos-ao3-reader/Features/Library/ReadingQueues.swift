import Foundation
import OSLog
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Navigation route for Reading Queues beyond the Library carousel.
/// - `initialQueueID == nil` — the full grid of queue stack cards ("See all" chevron).
/// - non-nil — the Safari-style browser pre-selected on that queue (carousel tile
///   or a stack tapped inside the grid).
struct AllReadingQueuesDestination: Hashable {
    var initialQueueID: UUID?
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

    /// 1b's numbers are for a 164pt card; the deck scales with it.
    private var scale: CGFloat { cardSize.width / CarouselCardMetrics.width }

    var body: some View {
        VStack(alignment: .leading, spacing: 9 * scale) {
            deck
            VStack(alignment: .leading, spacing: 2) {
                Text(queue.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                Text(ReadingQueueFacts.cardFooter(states: works.map(\.readingState)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: cardSize.width, alignment: .leading)
    }

    /// Spec 1b: a short deck, not a full-height card — two faint cards fanned
    /// up and to the right behind the next-up work's face, 96pt in all. Each
    /// card is 148×88; the back one sits 16pt in, the middle 8pt in and 4pt
    /// down, the face flush left and 8pt down. The owner caught the app
    /// drawing a 232pt work-sized card here instead (2026-10-01).
    private var deck: some View {
        let width = 148 * scale
        let height = 88 * scale
        let shape = RoundedRectangle(cornerRadius: 12 * scale, style: .continuous)
        let theme = themeManager.appTheme
        return ZStack(alignment: .topLeading) {
            shape.fill(theme.glassFill(0.06))
                .overlay(shape.strokeBorder(theme.glassStroke(0.07), lineWidth: 0.5))
                .frame(width: width, height: height)
                .offset(x: 16 * scale)
            shape.fill(theme.glassFill(0.09))
                .overlay(shape.strokeBorder(theme.glassStroke(0.09), lineWidth: 0.5))
                .frame(width: width, height: height)
                .offset(x: 8 * scale, y: 4 * scale)
            face(shape: shape)
                .frame(width: width, height: height)
                .offset(y: 8 * scale)
        }
        .frame(width: cardSize.width, height: 96 * scale, alignment: .topLeading)
    }

    /// The next-up work's fandom and title over its own gradient — the work
    /// cards' `cardWash` — with 1h's finished / in-progress / unread strip for
    /// the whole queue along the bottom. A fully read queue shows its first
    /// work; an empty one says so. The queue page's Up next row is this same
    /// work (`ReadingQueueFacts.upNext`).
    @ViewBuilder
    private func face(shape: RoundedRectangle) -> some View {
        let queued = works
        if let work = ReadingQueueFacts.upNext(in: queued).upNext {
            let palette = themeManager.appTheme.subjectPalette(
                hue: CoverArt.workHue(fandoms: work.workFandoms, title: work.title)
            )
            let fandom = work.workFandoms.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map(FandomDisplayName.bareTitle)
            VStack(alignment: .leading, spacing: 6 * scale) {
                if let fandom {
                    SubjectKicker(text: fandom, palette: palette, size: 8.5, ruleWidth: 18 * scale, ruleSpacing: 5)
                }
                Text(work.title)
                    .font(.system(size: 13 * scale, weight: .bold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                QueueProgressStrip(
                    progress: ReadingQueueFacts.progress(of: queued.map(\.readingState)),
                    palette: palette,
                    height: 3.5 * scale,
                    gap: 2.5 * scale
                )
            }
            .padding(10 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(shape.fill(palette.cardWash))
            .overlay(shape.strokeBorder(themeManager.appTheme.glassStroke(0.12), lineWidth: 0.5))
        } else {
            Text("No works yet")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(10 * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(shape.fill(themeManager.appTheme.glassFill(0.12)))
                .overlay(shape.strokeBorder(themeManager.appTheme.glassStroke(0.12), lineWidth: 0.5))
        }
    }
}

/// A queue's 2×2 "tab group" tile: padding, glass, hairline and shadow around
/// four cells. `ReadingQueueCard` fills it with skeleton cells for an empty
/// queue; 1i's organizer rows fill it with the queue's first four works at 44pt.
/// One frame, so the two stay the same shape at any size.
struct QueuePeekTile<Cell: View>: View {
    var spacing: CGFloat = 4
    var inset: CGFloat = 6
    var cornerRadius: CGFloat = CarouselCardMetrics.cornerRadius
    /// The queue's own colour over the glass (`carouselQueueTint`); nil is plain glass.
    var tint: Color?
    /// Cell 0 is top-left, then reading order.
    @ViewBuilder var cell: (Int) -> Cell

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        VStack(spacing: spacing) {
            HStack(spacing: spacing) {
                cell(0)
                cell(1)
            }
            HStack(spacing: spacing) {
                cell(2)
                cell(3)
            }
        }
        .padding(inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            shape.fill(.regularMaterial)
                .overlay(shape.fill(tint ?? .clear))
        }
        .overlay { shape.strokeBorder(.quaternary, lineWidth: 0.75) }
        .shadow(color: .black.opacity(0.12), radius: 5, x: 0, y: 2)
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
                                    // These are already on the device — a queue keeps them.
                                    // This keeps the file after they leave their queues.
                                    if !work.isSaved {
                                        Button {
                                            WorkLifecycle.setSaved(work, true, in: context)
                                        } label: {
                                            Label("Keep Download", systemImage: "pin")
                                        }
                                        .tint(.blue)
                                    }
                                }
                                .contextMenu {
                                    if !work.isSaved {
                                        Button {
                                            WorkLifecycle.setSaved(work, true, in: context)
                                        } label: {
                                            Label("Keep Download", systemImage: "pin")
                                        }
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
        queueByteCountString(bytes)
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
