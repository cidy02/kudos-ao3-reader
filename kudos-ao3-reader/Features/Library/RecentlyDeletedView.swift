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

    /// Set when a restore did not persist. Recently Deleted is the last stop
    /// before permanent deletion, so "it looked like it worked" is the one
    /// outcome this screen must never produce.
    @State private var restoreFailure: String?
    /// The row whose Delete Permanently is waiting on its alert. One slot for all
    /// three kinds: each entry carries its own message and its own delete.
    @State private var pendingPermanent: DeletedEntry?
    @State private var confirmingDeleteAll = false

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
        // 1bj draws an alert, not a sheet, and "repeats it per item with the real
        // numbers" — the title names the record and the message says what goes.
        .alert(
            pendingPermanent.map { "Delete “\($0.title)” permanently?" } ?? "",
            isPresented: Binding(
                get: { pendingPermanent != nil },
                set: { if !$0 { pendingPermanent = nil } }
            ),
            // `presenting:` hands the value INTO the action. Without it the
            // action re-read the pending state, which the binding's own setter
            // clears on dismissal — and on iOS 27 dismissal lands first, so
            // "Delete Permanently" could silently do nothing. A destructive
            // control that quietly does nothing teaches people not to trust it.
            presenting: pendingPermanent
        ) { entry in
            Button("Delete Permanently", role: .destructive) {
                entry.deletePermanently()
                pendingPermanent = nil
            }
            Button("Cancel", role: .cancel) { pendingPermanent = nil }
        } message: { entry in
            Text(entry.deletionMessage())
        }
        .alert(
            entries.count == 1 ? "Delete 1 item permanently?" : "Delete all \(entries.count) items permanently?",
            isPresented: $confirmingDeleteAll
        ) {
            Button("Delete All Permanently", role: .destructive) {
                PreservedWorkService.hardDeleteAllPending(in: context)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every work, collection and reading queue here is removed from this device, "
                + "with its download, progress and notes. The works stay on AO3. "
                + "This cannot be undone.")
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
                        row(entry)
                    }
                }
            }

            if !later.isEmpty {
                Section {
                    SectionRuleHeader(title: "Later", count: later.count)
                        .pageBodyRow(top: 18, gutter: 0)
                    ForEach(later) { entry in
                        row(entry)
                    }
                }
            }

            Section {
                deleteAllButton.pageBodyRow(top: 24, gutter: SubjectMetrics.accountGutter)
            }
        }
        .cardList()
        .alert(
            "Couldn't Restore",
            isPresented: Binding(
                get: { restoreFailure != nil },
                set: { if !$0 { restoreFailure = nil } }
            ),
            presenting: restoreFailure
        ) { _ in
            Button("OK", role: .cancel) { restoreFailure = nil }
        } message: { message in
            Text(message)
        }
    }

    private func row(_ entry: DeletedEntry) -> some View {
        RecentlyDeletedRow(entry: entry, palette: palette) { pendingPermanent = entry }
            .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
    }

    /// 1bj's footer: an outlined red capsule, behind its own confirmation.
    private var deleteAllButton: some View {
        Button {
            confirmingDeleteAll = true
        } label: {
            Label("Delete All Permanently", systemImage: "trash")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, minHeight: 44)
                .overlay(Capsule().strokeBorder(Color.red.opacity(0.42), lineWidth: 0.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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
        theme.scopePalette
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
                onRestore: {
                    if !PreservedWorkService.restore(work, in: context) {
                        restoreFailure = "Kudos could not save the restored work. "
                            + "It is still scheduled for permanent deletion, so try again."
                    }
                },
                deletionMessage: { workDeletionMessage(work) },
                deletePermanently: { PreservedWorkService.deletePermanently(work, in: context) }
            ))
        }
        for collection in deletedCollections {
            all.append(DeletedEntry(
                id: collection.id,
                // "Local" because AO3 has collections too, and those are never here.
                kicker: "Local collection",
                title: collection.name,
                detail: containerDetail(collection.works.count, deletedAt: collection.deletedAt),
                daysRemaining: Self.daysRemaining(collection.permanentDeletionScheduledAt),
                onRestore: {
                    if !PreservedWorkService.restore(collection, in: context) {
                        restoreFailure = "Kudos could not save the restored collection. "
                            + "It is still scheduled for permanent deletion, so try again."
                    }
                },
                deletionMessage: { Self.containerDeletionMessage(workCount: collection.works.count) },
                deletePermanently: { PreservedWorkService.deletePermanently(collection, in: context) }
            ))
        }
        for queue in deletedQueues {
            all.append(DeletedEntry(
                id: queue.id,
                kicker: "Reading queue",
                title: queue.displayName,
                detail: containerDetail(queue.memberships.count, deletedAt: queue.deletedAt),
                daysRemaining: Self.daysRemaining(queue.permanentDeletionScheduledAt),
                onRestore: {
                    if !PreservedWorkService.restore(queue, in: context) {
                        restoreFailure = "Kudos could not save the restored reading queue. "
                            + "It is still scheduled for permanent deletion, so try again."
                    }
                },
                deletionMessage: { Self.containerDeletionMessage(workCount: queue.memberships.count) },
                deletePermanently: { PreservedWorkService.deletePermanently(queue, in: context) }
            ))
        }
        return all.sorted { $0.daysRemaining < $1.daysRemaining }
    }

    /// Spec 1bj: "8 works · deleted 30 Aug".
    private func containerDetail(_ count: Int, deletedAt: Date?) -> String {
        let works = countPhrase(count, "work")
        guard let deletedAt else { return works }
        return works + " · deleted " + deletedAt.formatted(.dateTime.day().month(.abbreviated))
    }

    /// The per-item alert's real numbers for a work. Read only when the alert is
    /// up, so the annotation fetch is not paid for every row on every render —
    /// fetched the same way `WorkLifecycle.hardDelete` finds what it deletes.
    private func workDeletionMessage(_ work: SavedWork) -> String {
        let workID = work.id
        let marks = ((try? context.fetch(FetchDescriptor<ReadingAnnotation>())) ?? [])
            .filter { $0.work?.id == workID && !$0.isPendingDeletion }
        return Self.workDeletionMessage(
            hasDownload: work.hasEPUB,
            place: work.isFinished ? nil : work.readingProgressLabel,
            highlights: marks.filter { $0.kind == .highlight }.count,
            bookmarks: marks.filter { $0.kind == .bookmark }.count
        )
    }

    /// 1bj's per-item message: "The download, your place at chapter 4 and your
    /// two notes are removed from this device. This cannot be undone." Built from
    /// what this work actually has, so a work with none of it says so plainly
    /// rather than listing things that are not there.
    ///
    /// `place` is `SavedWork.readingProgressLabel` ("Ch 4" or "42%"), nil when
    /// there is no place worth naming.
    static func workDeletionMessage(hasDownload: Bool, place: String?, highlights: Int, bookmarks: Int) -> String {
        var parts: [String] = []
        if hasDownload { parts.append("the download") }
        if let place {
            parts.append("your place at " + (place.hasPrefix("Ch ") ? "chapter " + place.dropFirst(3) : place))
        }
        if highlights > 0 { parts.append("your \(highlights) highlight\(highlights == 1 ? "" : "s")") }
        if bookmarks > 0 { parts.append("your \(bookmarks) bookmark\(bookmarks == 1 ? "" : "s")") }
        guard let last = parts.popLast() else {
            return "Its record is removed from this device. This cannot be undone."
        }
        let list = parts.isEmpty ? last : parts.joined(separator: ", ") + " and " + last
        return "This removes " + list + " from this device. This cannot be undone."
    }

    /// A collection or queue is a list of works, not the works: deleting it
    /// leaves every one of them in the Library, and the count says how many.
    static func containerDeletionMessage(workCount: Int) -> String {
        let works = switch workCount {
        case 0: "It holds no works."
        case 1: "The 1 work in it stays in your Library."
        default: "The \(workCount) works in it stay in your Library."
        }
        return works + " This cannot be undone."
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

    /// 1bj: "amber under a week". Amber, not red — red is the destructive
    /// action's colour on this screen, and a countdown is a warning, not an act.
    static func isUrgent(daysRemaining: Int) -> Bool {
        daysRemaining < 7
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
    /// The per-item alert's message — a closure so a work's annotation count is
    /// fetched only once its alert is up.
    let deletionMessage: () -> String
    /// The existing per-kind permanent delete; runs only from the alert.
    let deletePermanently: () -> Void
}

/// A single Recently Deleted row on the subject card. Spec 1bj: "Swipe gives
/// Restore and Delete in that order", both on the trailing edge. The same two
/// actions live in a context menu — swipes are invisible until tried, and on
/// macOS they only exist for trackpad users, so the menu is the discoverable path.
private struct RecentlyDeletedRow: View {
    let entry: DeletedEntry
    let palette: SubjectPalette
    /// Asks for the alert; never deletes by itself.
    let onDeletePermanently: () -> Void

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
        // Trailing actions lay out from the edge inward, so Delete is declared
        // first to sit outermost with Restore to its left — the artboard's order.
        // A full swipe lands on Delete, which only opens the alert.
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDeletePermanently) {
                Label("Delete", systemImage: "trash.fill")
            }
            Button(action: entry.onRestore) {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button(action: entry.onRestore) {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            Button(role: .destructive, action: onDeletePermanently) {
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
                .foregroundStyle(
                    RecentlyDeletedView.isUrgent(daysRemaining: entry.daysRemaining) ? Color.orange : Color.primary
                )
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
