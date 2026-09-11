import SwiftData
import SwiftUI

/// Navigation-path marker for `LibraryView`'s Recently Deleted row — a plain button
/// rather than a `NavigationLink`, since it's conditionally shown, so it pushes onto
/// `path` explicitly instead of using a `.navigationDestination(for: WorkCollection.self)`-
/// style typed value that doesn't otherwise exist here.
struct RecentlyDeletedDestination: Hashable {}

/// Artboard **1bj** — works, collections and reading queues inside their recovery
/// window (see `PreservedWorkService`). Restore brings a record back exactly as it
/// was; Delete Permanently skips the rest of the window. Hidden entirely from
/// navigation when empty — see `RecentlyDeletedEntryRow` in `LibraryView`.
///
/// **Grouped by how long is left, not by type.** The spec's sections are Expiring
/// soon and Later, which is the only grouping that answers the question this screen
/// exists for: what am I about to lose? Nothing is lost by regrouping, because each
/// row names its own kind in its kicker — a queue no longer needs a section header to
/// say it is a queue.
///
/// The reassurance line at the top is the spec's and is the most important sentence
/// here: readers reach this screen worried they have deleted something off AO3.
struct RecentlyDeletedView: View {
    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var theme

    @Query(filter: #Predicate<SavedWork> { $0.isPendingDeletion }) private var deletedWorks: [SavedWork]
    @Query(filter: #Predicate<WorkCollection> { $0.isPendingDeletion }) private var deletedCollections: [WorkCollection]
    @Query(filter: #Predicate<ReadingQueue> { $0.isPendingDeletion }) private var deletedQueues: [ReadingQueue]

    @State private var pendingPermanentWork: SavedWork?
    @State private var pendingPermanentCollection: WorkCollection?
    @State private var pendingPermanentQueue: ReadingQueue?

    /// Spec 1bj splits at a threshold rather than showing a continuous countdown.
    /// Two weeks: long enough that the Expiring soon group is not everything on the
    /// day someone clears out a shelf, short enough that landing in it is a prompt.
    private static let expiringSoonDays = 14

    var body: some View {
        // Bound once. `entries` flattens and sorts three `@Query` results, and the
        // body reads it four times — emptiness, the header count, and both groups.
        let entries = self.entries
        return Group {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label("Recently Deleted", systemImage: "trash")
                } description: {
                    Text("Deleted works, collections, and reading queues stay here for "
                        + "\(Self.windowDays) days before they're permanently removed.")
                }
            } else {
                list(entries)
            }
        }
        .subjectScreenWash(palette: palette)
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

    private func list(_ entries: [DeletedEntry]) -> some View {
        let soon = entries.filter { $0.daysRemaining <= Self.expiringSoonDays }
        let later = entries.filter { $0.daysRemaining > Self.expiringSoonDays }
        return List {
            Section {
                header(count: entries.count).pageBodyRow(top: 20, gutter: 0)
                reassurance.pageBodyRow(top: 12, gutter: SubjectMetrics.accountGutter)
            }

            if !soon.isEmpty {
                Section {
                    SectionRuleHeader(title: "Expiring soon", count: soon.count)
                        .pageBodyRow(top: 18, gutter: 0)
                    ForEach(soon) { entry in
                        RecentlyDeletedRow(entry: entry, palette: palette)
                            .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
                    }
                }
            }

            if !later.isEmpty {
                Section {
                    SectionRuleHeader(title: "Later", count: later.count)
                        .pageBodyRow(top: 18, gutter: 0)
                    ForEach(later) { entry in
                        RecentlyDeletedRow(entry: entry, palette: palette)
                            .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
                    }
                }
            }
        }
        .cardList()
    }

    private func header(count: Int) -> some View {
        SubjectHeaderBlock(
            kicker: "Library",
            title: "Recently Deleted",
            subtitle: "\(count) item\(count == 1 ? "" : "s") · removed from "
                + "the app after \(Self.windowDays) days",
            palette: palette,
            gutter: SubjectMetrics.accountGutter
        )
    }

    /// The sentence readers come here for. Kept verbatim from the spec, because the
    /// worry it answers — "have I deleted this off AO3?" — is exactly what makes the
    /// screen frightening without it.
    private var reassurance: some View {
        Text("Deleting here only removes the app's copy — the download, your progress and "
            + "your notes. The work stays on AO3.")
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .subjectPanel()
    }

    private var palette: SubjectPalette {
        theme.appTheme.subjectPalette(hue: theme.scopeHue)
    }

    /// The window stated in days, read from `PreservedWorkService` rather than
    /// written out. Spec 1bj says 30; the app's window is 90, and the screen must
    /// say what the code will actually do.
    private static var windowDays: Int {
        Int((PreservedWorkService.recoveryWindow / 86_400).rounded())
    }

    // MARK: Entries

    /// All three kinds in one list, soonest to expire first.
    ///
    /// Flattened into a value here rather than kept as three `ForEach`es because the
    /// spec's grouping cuts across type: a queue expiring in three days belongs next
    /// to a work expiring in three days, not in a Reading Queues section further
    /// down the page.
    private var entries: [DeletedEntry] {
        var all: [DeletedEntry] = []
        for work in deletedWorks {
            all.append(DeletedEntry(
                id: work.id,
                kicker: work.hasEPUB ? "Downloaded work" : "Work",
                title: work.title,
                detail: workDetail(work),
                authorIdentities: work.verifiedAuthorIdentities,
                daysRemaining: Self.daysRemaining(work.permanentDeletionScheduledAt),
                onRestore: { PreservedWorkService.restore(work, in: context) },
                onDeletePermanently: { pendingPermanentWork = work }
            ))
        }
        for collection in deletedCollections {
            all.append(DeletedEntry(
                id: collection.id,
                kicker: "Collection",
                title: collection.name,
                detail: countPhrase(collection.works.count, "work"),
                daysRemaining: Self.daysRemaining(collection.permanentDeletionScheduledAt),
                onRestore: { PreservedWorkService.restore(collection, in: context) },
                onDeletePermanently: { pendingPermanentCollection = collection }
            ))
        }
        for queue in deletedQueues {
            all.append(DeletedEntry(
                id: queue.id,
                kicker: "Reading queue",
                title: queue.displayName,
                detail: countPhrase(queue.memberships.count, "work"),
                daysRemaining: Self.daysRemaining(queue.permanentDeletionScheduledAt),
                onRestore: { PreservedWorkService.restore(queue, in: context) },
                onDeletePermanently: { pendingPermanentQueue = queue }
            ))
        }
        return all.sorted { $0.daysRemaining < $1.daysRemaining }
    }

    /// Spec 1bj: "sprawl_ghost · 66,410 words · unread". The last fact is the state
    /// the record was in when it was deleted, which is what tells a reader whether
    /// restoring gets them back something they had got partway through.
    private func workDetail(_ work: SavedWork) -> String {
        var parts: [String] = []
        if !work.author.isEmpty { parts.append(work.author) }
        if work.wordCount > 0 { parts.append("\(work.wordCount.formatted()) words") }
        parts.append(stateWord(work.readingState))
        return parts.joined(separator: " · ")
    }

    private func stateWord(_ state: SavedWork.ReadingState) -> String {
        switch state {
        case .unread: "unread"
        case .inProgress: "part-read"
        case .finished: "finished"
        case .freedHistory: "read, file freed"
        }
    }

    private func countPhrase(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    static func daysRemaining(_ date: Date?) -> Int {
        guard let date else { return 0 }
        // Round up: an hour after deleting, the honest answer is still the full
        // window, not the truncated one less.
        let days = Int((date.timeIntervalSinceNow / 86_400).rounded(.up))
        return max(0, days)
    }
}

/// One pending-deletion record of any kind, reduced to what the row draws.
private struct DeletedEntry: Identifiable {
    let id: UUID
    /// What kind of thing this is — the spec puts it above the title, which is what
    /// lets the list group by expiry instead of by type.
    let kicker: String
    let title: String
    let detail: String
    var authorIdentities: [AO3AuthorIdentity] = []
    let daysRemaining: Int
    let onRestore: () -> Void
    let onDeletePermanently: () -> Void
}

/// A single Recently Deleted row on the subject card, with Restore (leading swipe)
/// and Delete Permanently (trailing swipe). The same two actions live in a context
/// menu — swipes are invisible until tried, and on macOS they only exist for
/// trackpad users, so the menu is the discoverable path.
private struct RecentlyDeletedRow: View {
    let entry: DeletedEntry
    let palette: SubjectPalette

    var body: some View {
        // authorIdentities.isEmpty: the detail line is a plain, non-interactive Text,
        // so the whole row safely combines into one VoiceOver stop instead of three
        // (HIG audit UI-2). Otherwise it is an AO3AuthorBylineView, whose author names
        // can be individually VoiceOver-focusable (AO3AuthorNavigation) — combining
        // would sweep those into one non-interactive element and silently remove that
        // navigation, so that case is left as separate stops instead.
        Group {
            if entry.authorIdentities.isEmpty {
                rowContent.accessibilityElement(children: .combine)
            } else {
                rowContent
            }
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: entry.onDeletePermanently) {
                Label("Delete Permanently", systemImage: "trash.fill")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(action: entry.onRestore) {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button(action: entry.onRestore) {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            Button(role: .destructive, action: entry.onDeletePermanently) {
                Label("Delete Permanently", systemImage: "trash.fill")
            }
        }
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                SubjectKicker(
                    text: entry.kicker,
                    palette: palette,
                    ruleWidth: SubjectMetrics.kickerRuleWidth,
                    ruleSpacing: 5
                )
                Text(entry.title)
                    .font(.system(size: 16.5, weight: .semibold))
                    .lineLimit(2)
                if !entry.detail.isEmpty {
                    detailLine
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            remaining
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .subjectCard(palette: palette)
    }

    @ViewBuilder
    private var detailLine: some View {
        if entry.authorIdentities.isEmpty {
            Text(entry.detail)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        } else {
            AO3AuthorBylineView(
                displayText: entry.detail,
                identities: entry.authorIdentities,
                includesBy: false,
                font: .caption,
                compact: true
            )
        }
    }

    /// Spec 1bj stacks the figure over the word — "3d" over "left" — so the number
    /// carries at a glance down a column of rows.
    private var remaining: some View {
        VStack(spacing: 1) {
            Text("\(entry.daysRemaining)d")
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(entry.daysRemaining <= 7 ? Color.red : Color.primary)
            Text("left")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            entry.daysRemaining == 1 ? "1 day left" : "\(entry.daysRemaining) days left"
        )
    }
}
