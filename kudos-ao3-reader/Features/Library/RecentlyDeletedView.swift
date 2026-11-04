import CoreTransferable
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

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
/// Deleted records and finished, un-kept copies have separate sections; each is
/// sorted soonest to expire first. Work rows carry their required-tag symbols,
/// while collections and queues name their kind above the title.
///
/// The reassurance line at the top is the spec's and is the most important sentence
/// here: readers reach this screen worried they have deleted something off AO3.
///
/// **Select** picks several rows for Restore or Delete Permanently, each through
/// the row's own per-kind path; the permanent one asks once, naming the count
/// and how many cannot be downloaded again. There is no Delete All — emptying
/// the list is Select → Select All → Delete Permanently (T-469).
struct RecentlyDeletedView: View {
    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var theme

    @Query(filter: #Predicate<SavedWork> { $0.isPendingDeletion }) private var deletedWorks: [SavedWork]
    @Query(filter: #Predicate<WorkCollection> { $0.isPendingDeletion }) private var deletedCollections: [WorkCollection]
    @Query(filter: #Predicate<ReadingQueue> { $0.isPendingDeletion }) private var deletedQueues: [ReadingQueue]
    /// Finished, un-kept works whose copy is waiting out its 60 days.
    @Query(filter: #Predicate<SavedWork> { $0.freedAt != nil && !$0.isPendingDeletion })
    private var heldWorks: [SavedWork]

    /// Set when a restore did not persist. Recently Deleted is the last stop
    /// before permanent deletion, so "it looked like it worked" is the one
    /// outcome this screen must never produce.
    @State private var restoreFailure: String?
    /// The row whose Delete Permanently is waiting on its alert. One slot for all
    /// three kinds: each entry carries its own message and its own delete.
    @State private var pendingPermanent: RecentlyDeletedEntry?
    @State private var isSelecting = false
    @State private var selection = Set<UUID>()
    /// The selection waiting on the bulk alert, captured when it was asked for.
    @State private var pendingBulkDelete: Set<UUID> = []
    /// Haptic triggers, bumped by the handlers when a restore / permanent delete is committed.
    @State private var restoreCount = 0
    @State private var permanentDeleteCount = 0
    /// The imported original waiting on the Files exporter, after "Save the
    /// Original File…" on a permanent-delete ask.
    @State private var originalExport: OriginalImportExport?
    @State private var exportingOriginal = false

    @ScaledMetric(relativeTo: .caption) private var sectionNoteSize: CGFloat = 11.5
    @ScaledMetric(relativeTo: .footnote) private var reassuranceSize: CGFloat = 12.5

    var body: some View {
        // Bound once. `entries` flattens and sorts three `@Query` results, and the
        // body reads it four times — emptiness, the header count, and both groups.
        let entries = self.entries
        return Group {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label("Recently Deleted", systemImage: "trash")
                } description: {
                    Text("Items you delete stay here for \(Self.windowDays) days. Copies of works "
                        + "you finish without keeping them stay for \(Self.heldWindowDays) days.")
                }
            } else {
                list(entries)
            }
        }
        .navigationTitle(isSelecting ? "\(selection.count) selected" : "Recently Deleted")
        .subjectScreenWash(palette: palette)
        .toolbar { toolbarContent(entries) }
        #if os(iOS)
        // Select mode owns the bottom edge with its action bar.
        .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
        #endif
        .onChange(of: entries.isEmpty) { _, isEmpty in
            if isEmpty { exitSelectMode() }
        }
        #if DEBUG
        .task {
            for _ in 0..<10 {
                if !entries.isEmpty { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            if DebugLaunchRoute.takeSheet("recentlydeleted") || DebugLaunchRoute.takeSheet("libselect") || DebugLaunchRoute.value == "recentlyDeleted" {
                if let first = entries.first {
                    selection = [first.id]
                    isSelecting = true
                }
            }
        }
        #endif
        // 1bj draws an alert, not a sheet, and "repeats it per item with the real
        // numbers" — the title names the record and the message says what goes.
        .alert(
            pendingPermanent?.deleteTitle ?? "",
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
            if let original = entry.originalFile {
                Button("Save the Original File…") {
                    originalExport?.cleanUp()
                    originalExport = OriginalImportExport.prepare(
                        url: original.url,
                        suggestedName: original.suggestedName
                    )
                    exportingOriginal = originalExport != nil
                }
            }
            Button(entry.deleteLabel, role: .destructive) {
                entry.deletePermanently()
                permanentDeleteCount += 1
                pendingPermanent = nil
            }
            Button("Cancel", role: .cancel) { pendingPermanent = nil }
        } message: { entry in
            Text(entry.deletionMessage())
        }
        // One alert for the whole selection, naming the count. Item-driven, so the ids
        // are handed INTO the action (see the per-item alert above).
        .destructiveConfirmation(
            for: Binding(
                get: { pendingBulkDelete.isEmpty ? nil : pendingBulkDelete },
                set: { pendingBulkDelete = $0 ?? [] }
            ),
            style: .alert,
            title: Self.bulkDeleteTitle(count: pendingBulkDelete.count),
            confirmLabel: "Delete Permanently",
            message: { Self.bulkPermanentMessage(ids: $0, in: entries) },
            perform: { ids in
                Self.deletePermanently(ids, in: entries)
                permanentDeleteCount += 1
                exitSelectMode()
            }
        )
        .sensoryFeedback(.success, trigger: restoreCount)
        .sensoryFeedback(.impact(weight: .heavy), trigger: permanentDeleteCount)
        .fileExporter(
            isPresented: $exportingOriginal,
            item: originalExport,
            contentTypes: [.data],
            defaultFilename: originalExport?.suggestedName
        ) { _ in
            originalExport?.cleanUp()
            originalExport = nil
        } onCancellation: {
            originalExport?.cleanUp()
            originalExport = nil
        }
    }

    @ToolbarContentBuilder
    private func toolbarContent(_ entries: [RecentlyDeletedEntry]) -> some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .confirmationAction) {
                let ids = Set(entries.map(\.id))
                let allSelected = !ids.isEmpty && ids.isSubset(of: selection)
                SelectAllButton(allSelected: allSelected) {
                    selection = allSelected ? [] : ids
                }
            }
            #if os(iOS)
            ToolbarItemGroup(placement: .bottomBar) { selectionBar(entries) }
            #else
            ToolbarItemGroup(placement: .primaryAction) { selectionBar(entries) }
            #endif
        } else if !entries.isEmpty {
            // Select lives in the "…", as on every other list (owner, 2026-10-01).
            ActionToolbar(items: [AnyView(WorkListMoreMenu {
                Button { isSelecting = true } label: {
                    Label("Select", systemImage: "checklist")
                }
            })])
        }
    }

    /// Restore · Delete Permanently, then Done — the row's two swipe actions,
    /// in the same order, over the selection.
    @ViewBuilder
    private func selectionBar(_ entries: [RecentlyDeletedEntry]) -> some View {
        let chosen = selection.intersection(entries.map(\.id))
        Button {
            let failed = Self.restore(chosen, in: entries)
            if !failed.isEmpty { restoreFailure = Self.restoreFailureMessage(failed) }
            if failed.count < chosen.count { restoreCount += 1 }
            exitSelectMode()
        } label: {
            Label("Restore", systemImage: "arrow.uturn.backward")
        }
        .disabled(chosen.isEmpty)
        Spacer()
        Button(role: .destructive) {
            pendingBulkDelete = chosen
        } label: {
            Label("Delete Permanently", systemImage: "trash")
        }
        .disabled(chosen.isEmpty)
        Spacer()
        Button {
            exitSelectMode()
        } label: {
            Image(systemName: "checkmark")
        }
        .accessibilityLabel("Done")
    }

    private func exitSelectMode() {
        isSelecting = false
        selection = []
    }

    /// Two sections (owner, 2026-10-01): what you deleted, kept for 90 days, and
    /// the copies of works you finished without keeping, held for 60. Each is
    /// soonest to expire first.
    private func list(_ entries: [RecentlyDeletedEntry]) -> some View {
        let deleted = entries.filter { !$0.isHeldCopy }
        let held = entries.filter(\.isHeldCopy)
        return List {
            Section {
                header(count: entries.count).pageBodyRow(top: 12, gutter: 0)
                reassurance(irreplaceableCount: Self.irreplaceableCount(in: entries))
                    .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
            }

            if !deleted.isEmpty {
                Section {
                    SectionRuleHeader(title: "Deleted", count: deleted.count)
                        .pageBodyRow(top: 18, gutter: 0)
                    sectionNote("Kept for \(Self.windowDays) days, then removed for good.")
                    ForEach(Array(deleted.enumerated()), id: \.element.id) { index, entry in
                        row(entry, showsSeparator: index < deleted.count - 1)
                    }
                }
            }

            if !held.isEmpty {
                Section {
                    SectionRuleHeader(title: "Finished, Not Kept", count: held.count)
                        .pageBodyRow(top: 18, gutter: 0)
                    sectionNote("Works you finished without downloading, favoriting or queuing them. "
                        + "Their copies stay here for \(Self.heldWindowDays) days so you can still read them "
                        + "offline, then they're removed. The works stay in your reading history.")
                    ForEach(Array(held.enumerated()), id: \.element.id) { index, entry in
                        row(entry, showsSeparator: index < held.count - 1)
                    }
                }
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

    private func row(_ entry: RecentlyDeletedEntry, showsSeparator: Bool) -> some View {
        RecentlyDeletedRow(
            entry: entry,
            palette: palette,
            showsSeparator: showsSeparator,
            isSelecting: isSelecting,
            isSelected: selection.contains(entry.id),
            onToggleSelection: {
                if selection.contains(entry.id) { selection.remove(entry.id) } else { selection.insert(entry.id) }
            },
            onRestore: {
                if entry.restore() {
                    restoreCount += 1
                } else {
                    restoreFailure = Self.restoreFailureMessage([entry])
                }
            },
            onDeletePermanently: { pendingPermanent = entry }
        )
        .pageBodyRow(
            top: entry.savedWork == nil ? 8 : 0,
            gutter: entry.savedWork == nil ? SubjectMetrics.accountGutter : 0
        )
    }

    private func sectionNote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: sectionNoteSize))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pageBodyRow(top: 6, gutter: SubjectMetrics.accountGutter)
    }

    private func header(count: Int) -> some View {
        SubjectPageFact(
            "\(count) item\(count == 1 ? "" : "s")",
            gutter: SubjectMetrics.accountGutter
        )
    }

    /// The sentence readers come here for. Kept verbatim from the spec, because the
    /// worry it answers — "have I deleted this off AO3?" — is exactly what makes the
    /// screen frightening without it. When some of these cannot be fetched again,
    /// a second line names how many.
    private func reassurance(irreplaceableCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Deleting an item here removes only the copy in Kudos, including its download, your progress, "
                + "and your notes. The work stays on AO3.")
            if irreplaceableCount > 0 {
                Text(irreplaceableCount == 1
                     ? "1 of these can't be downloaded again once it's gone."
                     : "\(irreplaceableCount) of these can't be downloaded again once they're gone.")
                    .fontWeight(.medium)
            }
        }
        .font(.system(size: reassuranceSize))
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

    private static var heldWindowDays: Int {
        Int((WorkLifecycle.freedCopyWindow / 86_400).rounded())
    }

    // MARK: Entries

    /// All three kinds in one list, soonest to expire first.
    ///
    /// Flattened into a value here rather than kept as three `ForEach`es because the
    /// spec's grouping cuts across type: a queue expiring in three days belongs next
    /// to a work expiring in three days, not in a Reading Queues section further
    /// down the page.
    private var entries: [RecentlyDeletedEntry] {
        let all = deletedWorks.map { RecentlyDeletedEntry.work($0, in: context) }
            + deletedCollections.map { RecentlyDeletedEntry.collection($0, in: context) }
            + deletedQueues.map { RecentlyDeletedEntry.queue($0, in: context) }
            + heldWorks.filter { $0.isFinished && !$0.isProtected && $0.hasEPUB }
                .map { RecentlyDeletedEntry.heldCopy($0, in: context) }
        return Self.sortedSoonestFirst(all)
    }

    // MARK: Select mode

    /// Restores each selected entry through its own per-kind path, and returns
    /// the ones whose restore did not persist — they are still scheduled, and
    /// the reader must be told.
    static func restore(_ selection: Set<UUID>, in entries: [RecentlyDeletedEntry]) -> [RecentlyDeletedEntry] {
        entries.filter { selection.contains($0.id) && !$0.restore() }
    }

    /// Each selected entry's own permanent delete — the per-item path, not a
    /// second way to delete. Runs only from the bulk alert.
    static func deletePermanently(_ selection: Set<UUID>, in entries: [RecentlyDeletedEntry]) {
        for entry in entries where selection.contains(entry.id) {
            entry.deletePermanently()
        }
    }

    static func bulkDeleteTitle(count: Int) -> String {
        count == 1 ? "Delete 1 item permanently?" : "Delete \(count) items permanently?"
    }

    static func sortedSoonestFirst(_ entries: [RecentlyDeletedEntry]) -> [RecentlyDeletedEntry] {
        entries.sorted { $0.daysRemaining < $1.daysRemaining }
    }

    static func irreplaceableCount(in entries: [RecentlyDeletedEntry]) -> Int {
        entries.reduce(into: 0) { count, entry in
            if !entry.redownloadability.canRedownload { count += 1 }
        }
    }

    static func bulkPermanentMessage(ids: Set<UUID>, in entries: [RecentlyDeletedEntry]) -> String {
        let chosen = entries.filter { ids.contains($0.id) }
        return PreservedWorkService.deleteConfirmationMessage(
            itemCount: chosen.count,
            irreplaceableCount: irreplaceableCount(in: chosen),
            permanently: true
        )
    }

    static func daysLeftLabel(_ days: Int) -> String {
        days == 1 ? "1 day left" : "\(days) days left"
    }

    static func restoreFailureMessage(_ failed: [RecentlyDeletedEntry]) -> String {
        let what = failed.count == 1 ? "the restored \(failed[0].noun)" : "\(failed.count) of the restored items"
        let still = failed.count == 1 ? "It is" : "They are"
        return "Kudos could not save \(what). \(still) still scheduled for permanent deletion, so try again."
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
            return "Kudos removes this item from your device. You can't undo this."
        }
        let list = parts.isEmpty ? last : parts.joined(separator: ", ") + " and " + last
        return "Kudos removes " + list + " from this device. You can't undo this."
    }

    /// A collection or queue is a list of works, not the works: deleting it
    /// leaves every one of them in the Library, and the count says how many.
    static func containerDeletionMessage(workCount: Int) -> String {
        let works = switch workCount {
        case 0: "It holds no works."
        case 1: "The 1 work in it stays in your Library."
        default: "The \(workCount) works in it stay in your Library."
        }
        return works + " You can't undo this."
    }

    /// Spec board 08: app/destructive red in the last 7 days, inclusive.
    static func isUrgent(daysRemaining: Int) -> Bool {
        daysRemaining <= 7
    }

    static func daysRemaining(_ date: Date?) -> Int {
        guard let date else { return 0 }
        // Round up: an hour after deleting, the honest answer is still the full
        // window, not the truncated one less.
        let days = Int((date.timeIntervalSinceNow / 86_400).rounded(.up))
        return max(0, days)
    }
}

/// One pending-deletion record of any kind, reduced to what the row draws and
/// the record's own per-kind restore and permanent delete.
struct RecentlyDeletedEntry: Identifiable {
    let id: UUID
    /// What kind of non-work item this is. Work rows use their symbol tile instead.
    let kicker: String
    /// "work", "collection", "reading queue" — for the restore-failure copy.
    let noun: String
    let title: String
    let detail: String
    var authorIdentities: [AO3AuthorIdentity] = []
    /// Present only for work rows, whose required-tag symbols come from the work.
    var savedWork: SavedWork? = nil
    let daysRemaining: Int
    /// `PreservedWorkService.restore` for this kind; false when it did not persist.
    let restore: () -> Bool
    /// The per-item alert's message — a closure so a work's annotation count is
    /// fetched only once its alert is up.
    let deletionMessage: () -> String
    /// The existing per-kind permanent delete; runs only from an alert.
    let deletePermanently: () -> Void
    /// A finished, un-kept work's copy, not something deleted.
    var isHeldCopy = false
    var redownloadability: WorkRedownloadability = .canRedownload
    var originalFile: (url: URL, suggestedName: String)?

    var deleteTitle: String {
        isHeldCopy ? "Remove the copy of “\(title)”?" : "Delete “\(title)” permanently?"
    }

    var deleteLabel: String { isHeldCopy ? "Remove Copy" : "Delete Permanently" }
}

@MainActor
extension RecentlyDeletedEntry {
    static func work(_ work: SavedWork, in context: ModelContext) -> Self {
        RecentlyDeletedEntry(
            id: work.id,
            kicker: work.isDownloaded ? "Downloaded work" : "Work",
            noun: "work",
            title: work.title,
            detail: workDetail(work),
            authorIdentities: work.verifiedAuthorIdentities,
            savedWork: work,
            daysRemaining: RecentlyDeletedView.daysRemaining(work.permanentDeletionScheduledAt),
            restore: { PreservedWorkService.restore(work, in: context) },
            deletionMessage: { workDeletionMessage(work, in: context) },
            deletePermanently: { PreservedWorkService.deletePermanently(work, in: context) },
            redownloadability: WorkRedownloadability.of(work),
            originalFile: WorkRedownloadability.originalFile(for: work.id)
        )
    }

    /// A copy waiting out its 60 days after its work was finished un-kept.
    /// Restore keeps it downloaded; Delete frees it now. The work itself stays.
    static func heldCopy(_ work: SavedWork, in context: ModelContext) -> Self {
        let expires = work.freedAt.map { $0.addingTimeInterval(WorkLifecycle.freedCopyWindow) }
        return RecentlyDeletedEntry(
            id: work.id,
            kicker: "Finished work",
            noun: "work",
            title: work.title,
            detail: workDetail(work),
            authorIdentities: work.verifiedAuthorIdentities,
            savedWork: work,
            daysRemaining: RecentlyDeletedView.daysRemaining(expires),
            restore: {
                WorkLifecycle.restoreHeldCopy(work, in: context)
                return true
            },
            deletionMessage: { heldCopyDeletionMessage(work) },
            deletePermanently: { WorkLifecycle.freeHeldCopy(work, in: context) },
            isHeldCopy: true,
            redownloadability: WorkRedownloadability.of(work),
            originalFile: WorkRedownloadability.originalFile(for: work.id)
        )
    }

    static func collection(_ collection: WorkCollection, in context: ModelContext) -> Self {
        RecentlyDeletedEntry(
            id: collection.id,
            // "Local" because AO3 has collections too, and those are never here.
            kicker: "Local collection",
            noun: "collection",
            title: collection.name,
            detail: containerDetail(collection.works.count, deletedAt: collection.deletedAt),
            daysRemaining: RecentlyDeletedView.daysRemaining(collection.permanentDeletionScheduledAt),
            restore: { PreservedWorkService.restore(collection, in: context) },
            deletionMessage: { RecentlyDeletedView.containerDeletionMessage(workCount: collection.works.count) },
            deletePermanently: { PreservedWorkService.deletePermanently(collection, in: context) }
        )
    }

    static func queue(_ queue: ReadingQueue, in context: ModelContext) -> Self {
        RecentlyDeletedEntry(
            id: queue.id,
            kicker: "Reading queue",
            noun: "reading queue",
            title: queue.displayName,
            detail: containerDetail(queue.memberships.count, deletedAt: queue.deletedAt),
            daysRemaining: RecentlyDeletedView.daysRemaining(queue.permanentDeletionScheduledAt),
            restore: { PreservedWorkService.restore(queue, in: context) },
            deletionMessage: { RecentlyDeletedView.containerDeletionMessage(workCount: queue.memberships.count) },
            deletePermanently: { PreservedWorkService.deletePermanently(queue, in: context) }
        )
    }

    /// Spec 1bj: "8 works · deleted 30 Aug".
    static func containerDetail(_ count: Int, deletedAt: Date?, locale: Locale = .current) -> String {
        let works = "\(count) work\(count == 1 ? "" : "s")"
        guard let deletedAt else { return works }
        return works + " · deleted "
            + deletedAt.formatted(.dateTime.day().month(.abbreviated).locale(locale))
    }

    /// The facts below the author/fandom line. The last is the state the record was
    /// in when it was deleted, which tells a reader what restoring gets them back.
    private static func workDetail(_ work: SavedWork) -> String {
        var parts: [String] = []
        if work.wordCount > 0 { parts.append("\(work.wordCount.formatted()) words") }
        parts.append(stateWord(work.readingState))
        return parts.joined(separator: " · ")
    }

    private static func stateWord(_ state: SavedWork.ReadingState) -> String {
        switch state {
        case .unread: "unread"
        case .inProgress: "part-read"
        case .finished: "finished"
        case .freedHistory: "read, file freed"
        }
    }

    /// The per-item alert's real numbers for a work. Read only when the alert is
    /// up, so the annotation fetch is not paid for every row on every render —
    /// fetched the same way `WorkLifecycle.hardDelete` finds what it deletes.
    /// A work Kudos cannot fetch again uses the shared escalated copy instead.
    private static func workDeletionMessage(_ work: SavedWork, in context: ModelContext) -> String {
        let reason = WorkRedownloadability.of(work)
        if !reason.canRedownload {
            return PreservedWorkService.deleteConfirmationMessage(
                title: work.title,
                reason: reason,
                permanently: true
            )
        }
        let workID = work.id
        let marks = ((try? context.fetch(FetchDescriptor<ReadingAnnotation>())) ?? [])
            .filter { $0.work?.id == workID && !$0.isPendingDeletion }
        return RecentlyDeletedView.workDeletionMessage(
            hasDownload: work.hasEPUB,
            place: work.isFinished ? nil : work.readingProgressLabel,
            highlights: marks.filter { $0.kind == .highlight }.count,
            bookmarks: marks.filter { $0.kind == .bookmark }.count
        )
    }

    private static func heldCopyDeletionMessage(_ work: SavedWork) -> String {
        let reason = WorkRedownloadability.of(work)
        if !reason.canRedownload {
            return PreservedWorkService.deleteConfirmationMessage(
                title: work.title,
                reason: reason,
                permanently: true
            )
        }
        return "Kudos removes this work's copy from your device now. The work stays in your "
            + "reading history, and you can download it again from AO3."
    }
}

/// A single Recently Deleted row. Works use the flat Library-row grammar;
/// collections and queues keep their kind-labelled subject cards. Spec 1bj: "Swipe gives
/// Restore and Delete in that order", both on the trailing edge. The same two
/// actions live in a context menu — swipes are invisible until tried, and on
/// macOS they only exist for trackpad users, so the menu is the discoverable path.
/// While selecting, a tap toggles the row and neither is offered.
struct RecentlyDeletedRow: View {
    enum SelectionEdge: Equatable {
        case none
        case leading
    }

    static func selectionEdge(isSelecting: Bool) -> SelectionEdge {
        isSelecting ? .leading : .none
    }

    static func separatorInset(isSelecting: Bool) -> CGFloat? {
        isSelecting ? 115 : nil
    }

    /// Title, detail and the days figure scale together at AX sizes.
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 16.5
    @ScaledMetric(relativeTo: .caption) private var detailSize: CGFloat = 11.5
    @ScaledMetric(relativeTo: .footnote) private var daysSize: CGFloat = 13

    let entry: RecentlyDeletedEntry
    let palette: SubjectPalette
    let showsSeparator: Bool
    var isSelecting = false
    var isSelected = false
    var onToggleSelection: () -> Void = {}
    let onRestore: () -> Void
    /// Asks for the alert; never deletes by itself.
    let onDeletePermanently: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if isSelecting {
            Button(action: onToggleSelection) {
                rowContent
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            idleRow
        }
    }

    private var idleRow: some View {
        // authorIdentities.isEmpty: the content is plain, non-interactive text, so
        // the whole row safely combines into one VoiceOver stop instead of three
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
                Label(entry.isHeldCopy ? "Remove" : "Delete", systemImage: "trash.fill")
            }
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
                Label(entry.deleteLabel, systemImage: "trash.fill")
            }
        }
    }

    @ViewBuilder
    private var rowContent: some View {
        if let work = entry.savedWork {
            workRowContent(work)
        } else {
            containerRowContent
        }
    }

    private func workRowContent(_ work: SavedWork) -> some View {
        WorkPlainRow(
            showsSeparator: showsSeparator,
            separatorInset: Self.separatorInset(isSelecting: isSelecting)
        ) {
            HStack(alignment: .center, spacing: 12) {
                if Self.selectionEdge(isSelecting: isSelecting) == .leading {
                    WorkLeadingSelectionCheck(isSelected: isSelected)
                }
                WorkStatusIconGrid(
                    rating: work.rating.isEmpty ? nil : work.rating,
                    categories: work.workCategories,
                    warnings: work.workWarnings,
                    completion: work.completionStatus,
                    tileSize: WorkRow.ledgerTileSize,
                    announcesToVoiceOver: true
                )
            }
        } heading: {
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title)
                        .font(.system(size: titleSize, weight: .semibold))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    authorAndFandoms(work)
                    if !entry.detail.isEmpty {
                        Text(entry.detail)
                            .font(.system(size: detailSize))
                            .foregroundStyle(.secondary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                remaining
                warningNote
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } remainder: {
            EmptyView()
        }
        .background {
            if isSelected {
                Rectangle().fill(.tint).opacity(0.08)
            }
        }
    }

    private var containerRowContent: some View {
        HStack(alignment: .center, spacing: 12) {
            if Self.selectionEdge(isSelecting: isSelecting) == .leading {
                WorkLeadingSelectionCheck(isSelected: isSelected)
            }

            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    SubjectKicker(
                        text: entry.kicker,
                        palette: palette,
                        ruleWidth: SubjectMetrics.kickerRuleWidth,
                        ruleSpacing: 5
                    )
                    Text(entry.title)
                        .font(.system(size: titleSize, weight: .semibold))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    if !entry.detail.isEmpty {
                        Text(entry.detail)
                            .font(.system(size: detailSize))
                            .foregroundStyle(.secondary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                remaining
                warningNote
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .subjectCard(palette: palette)
        .overlay {
            if isSelected {
                let shape = RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                shape.fill(.tint.opacity(0.08))
                    .overlay(shape.strokeBorder(.tint, lineWidth: 2))
            }
        }
    }

    @ViewBuilder
    private func authorAndFandoms(_ work: SavedWork) -> some View {
        let fandoms = work.workFandoms.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !work.author.isEmpty || !fandoms.isEmpty {
            ViewThatFits(in: .horizontal) {
                workByline(work, fandoms: fandoms, wraps: false)
                workByline(work, fandoms: fandoms, wraps: true)
            }
        }
    }

    private func workByline(_ work: SavedWork, fandoms: [String], wraps: Bool) -> some View {
        let layout = wraps
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 4))
        return layout {
            if !work.author.isEmpty {
                AO3AuthorBylineView(
                    displayText: work.author,
                    identities: entry.authorIdentities,
                    font: .caption,
                    compact: !dynamicTypeSize.isAccessibilitySize
                )
            }
            if !wraps, !work.author.isEmpty, !fandoms.isEmpty {
                Text("·")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if !fandoms.isEmpty {
                Text(fandoms.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var warningNote: some View {
        if let title = entry.redownloadability.rowTitle,
           let body = entry.redownloadability.rowBody {
            RedownloadWarningNote(title: title, message: body)
        }
    }

    /// Board 08: clock + "N days left". App/destructive red in the last 7 days.
    private var remaining: some View {
        let urgent = RecentlyDeletedView.isUrgent(daysRemaining: entry.daysRemaining)
        let label = RecentlyDeletedView.daysLeftLabel(entry.daysRemaining)
        return HStack(alignment: .center, spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: daysSize, weight: .semibold))
            Text(label)
                .font(.system(size: daysSize, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(urgent ? Color.red : Color.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

/// Orange note on a Recently Deleted row for a work Kudos cannot fetch again.
/// Adaptive fill so Dark / Sepia / OLED keep contrast; the spec's cream tile is
/// Light-only.
private struct RedownloadWarningNote: View {
    let title: String
    let message: String

    @ScaledMetric(relativeTo: .footnote) private var size: CGFloat = 13

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Color.orange)
                .accessibilityHidden(true)
            (Text(title).fontWeight(.semibold) + Text(" ") + Text(message))
                .font(.system(size: size))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.orange.opacity(0.14),
            in: RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

/// Copies the preserved original to a uniquely named temp file so the item-based
/// `fileExporter` has a real `preferredFilename` (the same trap `KudosBackupArchiveFile`
/// documents). Cleaned up when the exporter finishes or is cancelled.
private struct OriginalImportExport: Transferable, Sendable {
    let url: URL
    let suggestedName: String
    let cleanupURL: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .data) {
            SentTransferredFile($0.url, allowAccessingOriginalFile: true)
        }
        .suggestedFileName("Original")
    }

    static func prepare(url: URL, suggestedName: String) -> OriginalImportExport? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kudos-original-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent((suggestedName as NSString).lastPathComponent)
            try FileManager.default.copyItem(at: url, to: dest)
            return OriginalImportExport(url: dest, suggestedName: suggestedName, cleanupURL: dir)
        } catch {
            try? FileManager.default.removeItem(at: dir)
            return nil
        }
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: cleanupURL)
    }
}
