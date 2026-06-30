import SwiftUI
import SwiftData

// MARK: - Cards

struct ReadingQueueCard: View {
    let queue: ReadingQueue

    private var works: [SavedWork] {
        queue.memberships.compactMap(\.work)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            tile
                .frame(width: 120, height: 172)
            Text(queue.displayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)
            Text("\(works.count) work\(works.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 120, alignment: .leading)
    }

    private var tile: some View {
        let hue = CoverArt.hue(for: queue.displayName)
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(hue: hue, saturation: 0.32, brightness: 0.72).opacity(0.22))
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: queue.kind == .savedForLater ? "bookmark.fill" : "list.bullet.rectangle")
                        .font(.system(size: 28, weight: .semibold))
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
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.12), radius: 5, x: 0, y: 2)
    }
}

struct NewReadingQueueCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .frame(width: 120, height: 172)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .medium))
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
        .frame(width: 120, alignment: .leading)
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
                        SensitiveWorkRow(work: work, expandAll: expandAll)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    ReadingQueueService.remove(work, from: queue, in: context)
                                } label: {
                                    Label("Remove", systemImage: "minus.circle")
                                }
                            }
                    }
                    .cardRow()
                }
                .cardList()
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
                    try? context.save()
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
            Text("The queue is removed. The works themselves stay in Kudos if they are saved, "
                 + "favorited, or in another queue.")
        }
    }

    private func deleteQueue() {
        for work in works {
            ReadingQueueService.remove(work, from: queue, in: context)
        }
        context.delete(queue)
        try? context.save()
        dismiss()
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

    private func toggle(_ queue: ReadingQueue) {
        if isMember(queue) {
            ReadingQueueService.remove(work, from: queue, in: context)
            return
        }
        workingQueueIDs.insert(queue.id)
        Task {
            _ = await ReadingQueueService.addAndPreserve(work, to: queue, in: context)
            workingQueueIDs.remove(queue.id)
        }
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
