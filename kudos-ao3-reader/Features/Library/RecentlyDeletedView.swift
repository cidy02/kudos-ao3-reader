import SwiftData
import SwiftUI

/// Navigation-path marker for `LibraryView`'s Recently Deleted row — a plain button
/// rather than a `NavigationLink`, since it's conditionally shown, so it pushes onto
/// `path` explicitly instead of using a `.navigationDestination(for: WorkCollection.self)`-
/// style typed value that doesn't otherwise exist here.
struct RecentlyDeletedDestination: Hashable {}

/// Works, collections, and reading queues within their 90-day recovery window (see
/// `PreservedWorkService`). Restore brings a record back exactly as it was; Delete
/// Permanently skips the rest of the window. Hidden entirely from navigation when
/// empty — see `RecentlyDeletedEntryRow` in `LibraryView`.
struct RecentlyDeletedView: View {
    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var themeManager

    @Query(filter: #Predicate<SavedWork> { $0.isPendingDeletion }) private var deletedWorks: [SavedWork]
    @Query(filter: #Predicate<WorkCollection> { $0.isPendingDeletion }) private var deletedCollections: [WorkCollection]
    @Query(filter: #Predicate<ReadingQueue> { $0.isPendingDeletion }) private var deletedQueues: [ReadingQueue]

    @State private var pendingPermanentWork: SavedWork?
    @State private var pendingPermanentCollection: WorkCollection?
    @State private var pendingPermanentQueue: ReadingQueue?

    private var isEmpty: Bool {
        deletedWorks.isEmpty && deletedCollections.isEmpty && deletedQueues.isEmpty
    }

    private var sortedWorks: [SavedWork] {
        deletedWorks.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    private var sortedCollections: [WorkCollection] {
        deletedCollections.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    private var sortedQueues: [ReadingQueue] {
        deletedQueues.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    var body: some View {
        Group {
            if isEmpty {
                ContentUnavailableView {
                    Label("Recently Deleted", systemImage: "trash")
                } description: {
                    Text("Deleted works, collections, and reading queues stay here for 90 "
                        + "days before they're permanently removed.")
                }
            } else {
                List {
                    if !sortedWorks.isEmpty {
                        Section("Works") {
                            ForEach(sortedWorks) { work in
                                RecentlyDeletedRow(
                                    title: work.title,
                                    subtitle: work.author,
                                    daysRemaining: daysRemaining(work.permanentDeletionScheduledAt),
                                    onRestore: { PreservedWorkService.restore(work, in: context) },
                                    onDeletePermanently: { pendingPermanentWork = work }
                                )
                            }
                        }
                        .cardRow()
                    }
                    if !sortedCollections.isEmpty {
                        Section("Collections") {
                            ForEach(sortedCollections) { collection in
                                RecentlyDeletedRow(
                                    title: collection.name,
                                    subtitle: "\(collection.works.count) work"
                                        + (collection.works.count == 1 ? "" : "s"),
                                    daysRemaining: daysRemaining(collection.permanentDeletionScheduledAt),
                                    onRestore: { PreservedWorkService.restore(collection, in: context) },
                                    onDeletePermanently: { pendingPermanentCollection = collection }
                                )
                            }
                        }
                        .cardRow()
                    }
                    if !sortedQueues.isEmpty {
                        Section("Reading Queues") {
                            ForEach(sortedQueues) { queue in
                                RecentlyDeletedRow(
                                    title: queue.displayName,
                                    subtitle: "\(queue.memberships.count) work"
                                        + (queue.memberships.count == 1 ? "" : "s"),
                                    daysRemaining: daysRemaining(queue.permanentDeletionScheduledAt),
                                    onRestore: { PreservedWorkService.restore(queue, in: context) },
                                    onDeletePermanently: { pendingPermanentQueue = queue }
                                )
                            }
                        }
                        .cardRow()
                    }
                }
                .cardList()
            }
        }
        .background((themeManager.appTheme.appBaseBackground ?? Color.clear).ignoresSafeArea())
        .navigationTitle("Recently Deleted")
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .confirmationDialog(
                "Delete Permanently?",
                isPresented: Binding(
                    get: { pendingPermanentWork != nil },
                    set: { if !$0 { pendingPermanentWork = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Permanently", role: .destructive) {
                    if let work = pendingPermanentWork { WorkLifecycle.hardDelete(work, in: context) }
                    pendingPermanentWork = nil
                }
                Button("Cancel", role: .cancel) { pendingPermanentWork = nil }
            } message: {
                Text("This work is gone for good — it can't be restored afterward.")
            }
            .confirmationDialog(
                "Delete Permanently?",
                isPresented: Binding(
                    get: { pendingPermanentCollection != nil },
                    set: { if !$0 { pendingPermanentCollection = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Permanently", role: .destructive) {
                    if let collection = pendingPermanentCollection {
                        PreservedWorkService.hardDelete(collection, in: context)
                    }
                    pendingPermanentCollection = nil
                }
                Button("Cancel", role: .cancel) { pendingPermanentCollection = nil }
            } message: {
                Text("This collection is gone for good — it can't be restored afterward. "
                    + "The works themselves stay in your Library.")
            }
            .confirmationDialog(
                "Delete Permanently?",
                isPresented: Binding(
                    get: { pendingPermanentQueue != nil },
                    set: { if !$0 { pendingPermanentQueue = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Permanently", role: .destructive) {
                    if let queue = pendingPermanentQueue { PreservedWorkService.hardDelete(queue, in: context) }
                    pendingPermanentQueue = nil
                }
                Button("Cancel", role: .cancel) { pendingPermanentQueue = nil }
            } message: {
                Text("This queue is gone for good — it can't be restored afterward. "
                    + "The works themselves stay in your Library.")
            }
    }

    private func daysRemaining(_ date: Date?) -> Int {
        guard let date else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        return max(0, days)
    }
}

/// A single Recently Deleted row: title, subtitle, and a days-remaining label, with
/// Restore (leading swipe) and Delete Permanently (trailing swipe) actions.
private struct RecentlyDeletedRow: View {
    let title: String
    let subtitle: String
    let daysRemaining: Int
    let onRestore: () -> Void
    let onDeletePermanently: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(daysRemaining == 1 ? "1 day left" : "\(daysRemaining) days left")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDeletePermanently) {
                Label("Delete Permanently", systemImage: "trash.fill")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(action: onRestore) {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .tint(.blue)
        }
    }
}
