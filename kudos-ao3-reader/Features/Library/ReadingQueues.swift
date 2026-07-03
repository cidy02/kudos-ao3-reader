import Foundation
import OSLog
import SwiftData
import SwiftUI

// MARK: - Cards

struct ReadingQueueCard: View {
    @Environment(ThemeManager.self) private var themeManager
    let queue: ReadingQueue

    private var works: [SavedWork] {
        queue.memberships.compactMap(\.work)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            tile
                .frame(width: CarouselCardMetrics.width, height: CarouselCardMetrics.height)
            Text(queue.displayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)
            Text("\(works.count) work\(works.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: CarouselCardMetrics.width, alignment: .leading)
    }

    private var tile: some View {
        let hue = CoverArt.hue(for: queue.displayName)
        return RoundedRectangle(cornerRadius: CarouselCardMetrics.cornerRadius, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: CarouselCardMetrics.cornerRadius, style: .continuous)
                    .fill(themeManager.appTheme.carouselQueueTint(hue: hue))
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: queue.kind == .savedForLater ? "bookmark.fill" : "list.bullet.rectangle")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.tint)
                    Spacer()
                    Text(queue.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                }
                .padding(12)
            }
            .overlay {
                RoundedRectangle(cornerRadius: CarouselCardMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.12), radius: 5, x: 0, y: 2)
    }
}

struct NewReadingQueueCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: CarouselCardMetrics.cornerRadius, style: .continuous)
                .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .frame(width: CarouselCardMetrics.width, height: CarouselCardMetrics.height)
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
        .frame(width: CarouselCardMetrics.width, alignment: .leading)
    }
}

// MARK: - Queue detail

struct ReadingQueueDetailView: View {
    let queue: ReadingQueue

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var showingRename = false
    @State private var renameText = ""
    @State private var confirmDelete = false
    @State private var expandAll = false
    @State private var filters = LibraryFilters()
    @State private var showingFilters = false
    /// Tracks the in-flight refresh so it can be cancelled if the user switches tabs
    /// (see `cancelRefreshOnTabChange`) — a queue can hold a large number of works.
    @State private var refreshTask: Task<Void, Never>?

    private var works: [SavedWork] {
        queue.memberships
            .sorted {
                if $0.sortOrderInQueue != $1.sortOrderInQueue {
                    return $0.sortOrderInQueue < $1.sortOrderInQueue
                }
                return $0.queuedAt > $1.queuedAt
            }
            .compactMap(\.work)
    }

    private var visibleWorks: [SavedWork] {
        filters.hasActiveFilters ? filters.apply(to: works) : works
    }

    var body: some View {
        Group {
            if works.isEmpty {
                ContentUnavailableView {
                    Label(queue.displayName, systemImage: "bookmark")
                } description: {
                    Text("Works you add to this queue will keep a local EPUB for offline reading.")
                }
            } else {
                List {
                    ForEach(visibleWorks) { work in
                        SensitiveWorkRow(work: work, expandAll: expandAll, openMode: .reader)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    ReadingQueueService.removeFromQueue(work, from: queue, in: context)
                                } label: {
                                    Label("Remove from Queue", systemImage: "minus.circle")
                                }
                            }
                    }
                    .cardRow()
                }
                .cardList()
                .refreshable {
                    let task = Task { _ = await WorkMetadataRefresh.refresh(visibleWorks, in: context) }
                    refreshTask = task
                    await task.value
                }
                .cancelRefreshOnTabChange($refreshTask)
                .overlay {
                    if visibleWorks.isEmpty {
                        ContentUnavailableView {
                            Label("No matching works", systemImage: "line.3.horizontal.decrease.circle")
                        } description: {
                            Text("No works in this queue match the current filters.")
                        } actions: {
                            Button("Clear Filters") { filters = LibraryFilters() }
                        }
                    }
                }
            }
        }
        .background((themeManager.appTheme.appBaseBackground ?? Color.clear).ignoresSafeArea())
        .navigationTitle(queue.displayName)
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .inspector(isPresented: $showingFilters) {
                LibraryFilterPanel(filters: $filters, works: works, userTagNames: allTags.map(\.name))
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
                #if os(iOS)
                    .presentationDragIndicator(.visible)
                #endif
            }
            .toolbar {
                if !works.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        WorkCardListControls(expandAll: $expandAll,
                                             filtersActive: filters.hasActiveFilters,
                                             showingFilters: $showingFilters,
                                             filterHelp: "Filter the works in this queue")
                    }
                }
                if queue.kind == .custom {
                    ToolbarItem {
                        Menu {
                            Button {
                                renameText = queue.name
                                showingRename = true
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                confirmDelete = true
                            } label: {
                                Label("Delete Queue", systemImage: "trash")
                            }
                        } label: {
                            Label("Queue options", systemImage: "ellipsis.circle")
                        }
                    }
                }
            }
            .alert("Rename Queue", isPresented: $showingRename) {
                TextField("Name", text: $renameText)
                Button("Save") {
                    let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        queue.name = trimmed
                        queue.dateUpdated = Date()
                        saveBestEffort("Saving queue rename failed")
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Delete “\(queue.displayName)”?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    deleteQueue()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The queue is removed. Works stay in Kudos; only this queue membership is cleared.")
            }
    }

    private func deleteQueue() {
        for work in works {
            ReadingQueueService.removeFromQueue(work, from: queue, in: context)
        }
        context.delete(queue)
        saveBestEffort("Saving queue deletion failed")
        dismiss()
    }

    private func saveBestEffort(_ reason: StaticString) {
        do {
            try context.save()
        } catch {
            Log.library.error(
                "\(String(describing: reason), privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

// MARK: - Queue storage

struct ReadingQueueStorageView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedWork.dateAdded, order: .reverse) private var works: [SavedWork]
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
                                        Label("Save to Keep", systemImage: "bookmark")
                                    }
                                    .tint(.blue)
                                }
                                .contextMenu {
                                    Button {
                                        WorkLifecycle.setSaved(work, true, in: context)
                                    } label: {
                                        Label("Save to Keep", systemImage: "bookmark")
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
            Image(systemName: work.isInSavedForLaterQueue ? "bookmark.fill" : "list.bullet.rectangle")
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(work.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if !work.author.isEmpty {
                    Text(work.author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
    let work: SavedWork

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ReadingQueue.sortOrder) private var queues: [ReadingQueue]
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
                        Button("Done") { dismiss() }
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
        work.queueMemberships.contains { $0.queue?.id == queue.id }
    }

    private func queueSymbol(_ queue: ReadingQueue) -> String {
        queue.kind == .savedForLater ? "bookmark" : "list.bullet.rectangle"
    }

    private var hasSeries: Bool {
        URL(string: work.seriesURL) != nil && !work.seriesURL.isEmpty
    }

    private var selectedQueuesForSeries: [ReadingQueue] {
        sortedQueues.filter(isMember)
    }

    private func loadSeriesPreview() async {
        guard includeSeries, let url = URL(string: work.seriesURL) else { return }
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
        guard !preservingSeries, URL(string: work.seriesURL) != nil else { return }
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
                    anchoredAt: work,
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
            ReadingQueueService.removeFromQueue(work, from: queue, in: context)
            return
        }
        workingQueueIDs.insert(queue.id)
        Task {
            _ = await ReadingQueueService.addAndPreserve(work, to: queue, in: context)
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
        var parts: [String] = []
        if result.preserved > 0 {
            parts.append("\(result.preserved) added")
        }
        if result.alreadyPreserved > 0 {
            parts.append("\(result.alreadyPreserved) already preserved")
        }
        if result.unavailable > 0 {
            parts.append("\(result.unavailable) unavailable")
        }
        if result.failed > 0 {
            parts.append("\(result.failed) failed")
        }
        if result.skipped > 0 {
            parts.append("\(result.skipped) skipped")
        }
        return parts.isEmpty ? "Series works are already in the selected queues." : parts.joined(separator: ", ") + "."
    }

    private func create() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let queue = ReadingQueueService.createQueue(named: trimmed, in: context)
        newName = ""
        workingQueueIDs.insert(queue.id)
        Task {
            _ = await ReadingQueueService.addAndPreserve(work, to: queue, in: context)
            workingQueueIDs.remove(queue.id)
        }
    }
}
