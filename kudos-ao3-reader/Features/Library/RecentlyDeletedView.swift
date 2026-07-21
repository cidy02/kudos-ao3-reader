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
                                    authorIdentities: work.verifiedAuthorIdentities,
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
        // Round up: an hour after deleting, the honest answer is still "90 days left",
        // not the truncated 89.
        let days = Int((date.timeIntervalSinceNow / 86_400).rounded(.up))
        return max(0, days)
    }
}

/// A single Recently Deleted row: title, subtitle, and a days-remaining label, with
/// Restore (leading swipe) and Delete Permanently (trailing swipe) actions. The same
/// two actions live in a context menu — swipes are invisible until tried, and on
/// macOS they only exist for trackpad users, so the menu is the discoverable path.
private struct RecentlyDeletedRow: View {
    let title: String
    let subtitle: String
    var authorIdentities: [AO3AuthorIdentity] = []
    let daysRemaining: Int
    let onRestore: () -> Void
    let onDeletePermanently: () -> Void

    var body: some View {
        // authorIdentities.isEmpty: subtitle is a plain, non-interactive Text, so the
        // whole row safely combines into one VoiceOver stop instead of three (HIG
        // audit UI-2). Otherwise the subtitle is an AO3AuthorBylineView, whose author
        // names can be individually VoiceOver-focusable/navigable (AO3AuthorNavigation)
        // — combining would sweep those into one non-interactive element and silently
        // remove that navigation, so this case is left as separate stops instead.
        Group {
            if authorIdentities.isEmpty {
                rowContent.accessibilityElement(children: .combine)
            } else {
                rowContent
            }
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
        .contextMenu {
            Button(action: onRestore) {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            Button(role: .destructive, action: onDeletePermanently) {
                Label("Delete Permanently", systemImage: "trash.fill")
            }
        }
    }

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            if !subtitle.isEmpty {
                if authorIdentities.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    AO3AuthorBylineView(
                        displayText: subtitle,
                        identities: authorIdentities,
                        includesBy: false,
                        font: .caption,
                        compact: true
                    )
                }
            }
            Text(daysRemaining == 1 ? "1 day left" : "\(daysRemaining) days left")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
