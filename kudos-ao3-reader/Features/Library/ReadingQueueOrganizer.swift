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
/// - The tag filter pills (All/Rereads/Comfort/Long fic/Untagged) and their
///   "Edit tags" chip. Same gap as `ReadingQueueSettingsView`'s file note:
///   queues have no tag concept at all.
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
    @State private var newQueueName = ""
    @State private var pendingRename: ReadingQueue?
    @State private var renameText = ""
    @State private var pendingDelete: ReadingQueue?
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
    }

    private var savedForLaterQueue: ReadingQueue? {
        readingQueues.first { $0.kind == .savedForLater }
    }

    /// Every queue's own hue tints its row; the page itself has no single
    /// subject, so its wash takes the app's own accent scope — the same choice
    /// `LibrarySectionListView.scopePalette` makes for the same reason.
    private var organizerPalette: SubjectPalette {
        themeManager.appTheme.subjectPalette(hue: themeManager.scopeHue)
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
                statStrip
                    .pageBodyRow(top: 8, gutter: SubjectMetrics.gutter)
            }

            Section {
                SectionRuleHeader(title: "All Queues", count: readingQueues.count)
                    .pageBodyRow(top: 18, gutter: 0)

                if let savedForLaterQueue {
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
        // Unrestyled for now (plain `Form`, unchanged from before this file
        // existed) — artboard 1j gives this its own redesign pass and, at the
        // same time, folds this sheet and `ReadingQueueBrowserView`'s
        // near-identical copy into one shared component.
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
                        Button("Create", action: createQueue)
                            .disabled(newQueueName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            #if os(iOS)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            #endif
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
                        .fill(themeManager.appTheme.carouselQueueTint(hue: CoverArt.hue(for: queue.displayName)))
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

    private func createQueue() {
        let trimmed = newQueueName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        newQueueName = ""
        showingNewQueue = false
        _ = ReadingQueueService.createQueue(named: trimmed, in: context)
    }
}

/// Persists a new queue order after 1i's `.onMove` — mirrors
/// `ReadingQueueService.reorder(_:in:context:)`'s index rewrite, but for
/// `ReadingQueue.sortOrder` itself (the queues' own order) rather than a
/// membership's position inside one queue, so it stays local to this screen —
/// the only caller — rather than in the service.
private func reorderCustomQueues(_ orderedIDs: [UUID], context: ModelContext) {
    let queues = (try? context.fetch(FetchDescriptor<ReadingQueue>())) ?? []
    let byID = Dictionary(uniqueKeysWithValues: queues.map { ($0.id, $0) })
    for (index, id) in orderedIDs.enumerated() {
        byID[id]?.sortOrder = index
    }
    context.saveBestEffort(reason: "Saving reading queue order failed")
}
