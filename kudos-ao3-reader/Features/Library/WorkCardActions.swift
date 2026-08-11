import SwiftData
import SwiftUI

enum LocalWorkDestination: Hashable {
    case reader(SavedWork)
    case detail(SavedWork)
}

enum LocalWorkRowOpenMode {
    case detail
    case reader
}

struct LocalWorkDestinationView: View {
    let destination: LocalWorkDestination
    var onReaderOpen: (SavedWork) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    /// Pairs with the card this was pushed from — see `WorkCardZoomTransition.swift`.
    @Environment(\.workCardTransitionNamespace) private var zoomNamespace
    /// Set once, on this view's genuine first `.onAppear` — never updated again, so a
    /// later re-appearance (e.g. Back from a pushed Author Profile revealing this view)
    /// is never mistaken for a fresh, possibly-spurious push.
    @State private var appearedAt: Date?

    /// The card this screen was opened from — the other half of the zoom pair.
    private var sourceWorkID: UUID {
        switch destination {
        case let .reader(work), let .detail(work): work.id
        }
    }

    var body: some View {
        Group {
            switch destination {
            case let .reader(work):
                LocalWorkReaderDestination(work: work, onOpen: onReaderOpen)
            case let .detail(work):
                WorkDetailView(work: work)
            }
        }
        // On the *pushed view as a whole*, not inside the switch: the transition
        // describes this screen's own push, so a modifier buried on one branch of a
        // `Group` never registers it.
        .workCardZoomDestination(sourceWorkID, in: zoomNamespace)
        // Author byline taps can also activate the row NavigationLink. Dismiss must
        // be async — SwiftUI often ignores dismiss() inside the same navigation
        // transaction as the push (profile stayed buried until the user pressed Back).
        // Only the first appearance can be that spurious push, so only it sets
        // `appearedAt` / runs the check — a later re-appearance (Back from a child)
        // must never re-trigger it.
        .onAppear {
            if appearedAt == nil {
                appearedAt = Date()
                dismissIfAuthorBylineConflict()
            }
        }
        .onChange(of: router.cardNavigationSuppressed) { _, suppressed in
            if suppressed { dismissIfAuthorBylineConflict() }
        }
    }

    private func dismissIfAuthorBylineConflict() {
        guard router.shouldSuppressCardNavigation else { return }
        // Only a same-touch race at this view's own genuine push can make it the
        // spurious duplicate `cardNavigationSuppressed` guards against. Without this,
        // tapping this already-settled screen's own author byline flips the same
        // global flag and this handler dismissed the very screen the user is on.
        guard let appearedAt, Date().timeIntervalSince(appearedAt) < 0.5 else { return }
        Task { @MainActor in
            await Task.yield()
            guard router.shouldSuppressCardNavigation else { return }
            dismiss()
        }
    }
}

private struct LocalWorkReaderDestination: View {
    let work: SavedWork
    let onOpen: (SavedWork) -> Void

    @Environment(\.modelContext) private var context
    @State private var phase: Phase = .opening
    @State private var didPrepare = false

    private enum Phase: Equatable {
        case opening
        case restoring
        case failed(String)
    }

    var body: some View {
        Group {
            if WorkReaderPreparation.hasReadableEPUB(for: work) {
                BookReaderView(work: work)
                    .onAppear { onOpen(work) }
            } else {
                restorationView
            }
        }
        .task(id: work.id) { await prepareForReading() }
    }

    @ViewBuilder
    private var restorationView: some View {
        switch phase {
        case .opening, .restoring:
            // Same themed page skeleton as Readium's open path — never
            // `.systemBackground`, which flashes Light/Dark under Sepia/OLED.
            ReaderOpeningSkeleton(
                accessibilityLabel: phase == .restoring ? "Restoring EPUB" : "Opening"
            )
        case let .failed(message):
            ContentUnavailableView {
                Label("Couldn't Open Reader", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                NavigationLink(value: LocalWorkDestination.detail(work)) {
                    Label("Work Details", systemImage: "info.circle")
                }
            }
        }
    }

    @MainActor
    private func prepareForReading() async {
        guard !didPrepare else { return }
        didPrepare = true
        onOpen(work)
        guard !WorkReaderPreparation.hasReadableEPUB(for: work) else { return }
        phase = .restoring

        do {
            try await WorkReaderPreparation.restoreReadableEPUB(for: work, in: context)
            phase = .opening
        } catch {
            phase = .failed(WorkCardActionError.message(for: error))
        }
    }
}

/// Pushed when a card for a work the library does not have yet should *read* it:
/// import it from AO3 first, then open the reader.
///
/// The Account tab's lists (bookmarks, subscriptions, the account works lists) are the
/// caller. A card there was a route to Work Details, which meant reading something you
/// had bookmarked took two screens and a second decision; tapping the card now does the
/// obvious thing instead. Importing on tap is a real side effect — the work joins the
/// library — but that is what "open this" has to mean for a work stored on AO3.
struct RemoteWorkReaderRoute: Hashable {
    let work: AO3WorkSummary
}

/// Resolves `RemoteWorkReaderRoute` to a local work, then hands off to the same reader
/// destination a local card uses, so restore/skeleton/failure behaviour is shared
/// rather than reimplemented for remote works.
struct RemoteWorkReaderDestination: View {
    let summary: AO3WorkSummary

    @Environment(\.modelContext) private var context
    @State private var resolved: SavedWork?
    @State private var failure: String?

    var body: some View {
        Group {
            if let resolved {
                LocalWorkDestinationView(destination: .reader(resolved))
            } else if let failure {
                ContentUnavailableView {
                    Label("Couldn't Open Work", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(failure)
                } actions: {
                    NavigationLink(value: summary) {
                        Label("Work Details", systemImage: "info.circle")
                    }
                }
            } else {
                // Same themed skeleton a local open / restore shows, so import,
                // restore, and Readium open hand off without a theme flash.
                ReaderOpeningSkeleton(accessibilityLabel: "Downloading work")
            }
        }
        .task(id: summary) { await resolve() }
    }

    @MainActor
    private func resolve() async {
        guard resolved == nil, failure == nil else { return }
        do {
            // Reuses the queue's importer, so a work opened this way is indexed,
            // deduplicated against an existing copy, and preserved exactly like one
            // added through any other path.
            resolved = try await ReadingQueueService.resolveLocalWork(for: summary, in: context)
        } catch {
            failure = WorkCardActionError.message(for: error)
        }
    }
}

/// A compact work card's tap: open the work.
///
/// One rule app-wide, not a per-screen choice — a card in a carousel, on the Account
/// tab, or on an author profile all do the same thing, and the ⓘ in the corner is how
/// you get to Work Details from any of them. A remote work is imported on the way.
///
/// Note the concrete types. An earlier version returned an `AnyHashable` so one
/// `NavigationLink` could cover both a detail and a reader destination, and every card
/// stopped opening: `navigationDestination(for:)` matches on the value's **static**
/// type, so an erased value matches nothing and the tap silently does nothing.
enum WorkCardTap {
    static func destination(for work: SavedWork) -> LocalWorkDestination { .reader(work) }
    static func destination(for remote: AO3WorkSummary) -> RemoteWorkReaderRoute {
        RemoteWorkReaderRoute(work: remote)
    }
}

/// Label/icon pairs for work-lifecycle toggles duplicated across card context
/// menus, work detail, and the bulk-action bar.
enum WorkActionLabels {
    static func finished(isFinished: Bool) -> (title: String, systemImage: String) {
        isFinished
            ? ("Mark as Still Reading", "arrow.uturn.backward.circle")
            : ("Mark as Finished", "checkmark.circle")
    }

    /// Clock — not bookmark. Bookmark is reserved for AO3 bookmarks and "Save
    /// to Keep" (permanent EPUB retention); reusing it here made those three
    /// actions unreadable next to each other.
    static func savedForLater(isQueued: Bool) -> (title: String, systemImage: String) {
        isQueued
            ? ("Remove from Saved for Later", "clock.badge.xmark")
            : ("Save for Later", "clock")
    }

    /// Filled clock for "this *is* Saved for Later" states (queue glyph, badges).
    static let savedForLaterSymbol = "clock.fill"
    /// Outline clock for empty/idle Saved for Later affordances.
    static let savedForLaterEmptySymbol = "clock"

    static func favorite(isFavorite: Bool) -> (title: String, systemImage: String) {
        isFavorite
            ? ("Unfavorite", "star.slash")
            : ("Favorite", "star")
    }

    /// "Saved" keeps a work's EPUB from ever being freed. Distinct from Delete, which
    /// removes the work — the two used to share one menu slot.
    static func saved(isSaved: Bool) -> (title: String, systemImage: String) {
        isSaved
            ? ("Remove from Saved", "bookmark.slash")
            : ("Save", "bookmark")
    }
}

enum WorkReaderPreparation {
    @MainActor
    static func hasReadableEPUB(for work: SavedWork) -> Bool {
        work.hasEPUB && FileManager.default.fileExists(atPath: work.fileURL.path)
    }

    @MainActor
    static func restoreReadableEPUB(for work: SavedWork, in context: ModelContext) async throws {
        guard let id = work.ao3WorkID ?? WorkTags.ao3WorkID(from: work.sourceURL) else {
            throw WorkReaderPreparationError.missingAO3ID
        }

        let temp = try await AO3Client.shared.downloadEPUB(workID: id)
        try ReadingQueueService.replaceEPUB(for: work, with: temp)
        work.hasEPUB = true
        work.isFinished = false
        if work.isQueuedForLater {
            work.epubPreservationStatus = .preserved
            work.preservedAt = Date()
        }
        work.lastSpineIndex = 0
        // The intra-chapter fraction pairs with the spine index — clear both so
        // the fresh copy doesn't restore mid-chapter-one from a stale fraction.
        work.lastScrollFraction = 0
        work.markModified()
        try context.save()
    }
}

private enum WorkReaderPreparationError: LocalizedError {
    case missingAO3ID

    var errorDescription: String? {
        switch self {
        case .missingAO3ID:
            "This work can't be re-downloaded automatically. Open Work Details for more options."
        }
    }
}

private enum WorkCardActionError {
    static func message(for error: Error) -> String {
        if let ao3 = error as? AO3Error, let description = ao3.errorDescription {
            return description
        }
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}

private struct LocalWorkContextMenuModifier: ViewModifier {
    let work: SavedWork
    var onSelect: (() -> Void)?

    @Environment(\.modelContext) private var context
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete = true
    @State private var showingAddToQueue = false
    @State private var showingAddToCollection = false
    @State private var showingComments = false
    @State private var rebuildError: String?
    @State private var confirmingRebuild = false
    @State private var pendingDelete: SavedWork?

    private var commentsWorkID: Int? {
        work.ao3WorkID ?? WorkTags.ao3WorkID(from: work.sourceURL)
    }

    func body(content: Content) -> some View {
        content
            .contextMenu {
                NavigationLink(value: LocalWorkDestination.reader(work)) {
                    Label("Read", systemImage: "book")
                }

                if commentsWorkID != nil {
                    Button {
                        showingComments = true
                    } label: {
                        Label("Comments", systemImage: "bubble.left.and.bubble.right")
                    }
                }

                if let onSelect {
                    Button(action: onSelect) {
                        Label("Select", systemImage: "checklist")
                    }
                }

                // Save and Delete are different axes, so both are always offered.
                // Previously this was an either/or — saved works got Delete, unsaved
                // works got Save — which meant a work the user had never explicitly
                // saved (an imported file, say) had **no way to delete it from this
                // menu at all**. Delete now lives at the bottom, where a destructive
                // action belongs.
                Button {
                    WorkLifecycle.setSaved(work, !work.isSaved, in: context)
                } label: {
                    let labels = WorkActionLabels.saved(isSaved: work.isSaved)
                    Label(labels.title, systemImage: labels.systemImage)
                }

                Button {
                    toggleFavorite()
                } label: {
                    let labels = WorkActionLabels.favorite(isFavorite: work.isFavorite)
                    Label(labels.title, systemImage: labels.systemImage)
                }

                Button {
                    toggleSavedForLater()
                } label: {
                    let labels = WorkActionLabels.savedForLater(isQueued: work.isInSavedForLaterQueue)
                    Label(labels.title, systemImage: labels.systemImage)
                }

                Button {
                    showingAddToQueue = true
                } label: {
                    Label("Add to Queue", systemImage: "list.bullet.rectangle")
                }

                Button {
                    toggleFinished()
                } label: {
                    let labels = WorkActionLabels.finished(isFinished: work.isFinished)
                    Label(labels.title, systemImage: labels.systemImage)
                }

                Button {
                    showingAddToCollection = true
                } label: {
                    Label("Add to Collection", systemImage: "square.stack")
                }

                // Offered for any converted import, not just a stale one: a rebuild also
                // applies *importer* fixes the converter version cannot know about, so an
                // up-to-date work still has a reason to be rebuilt. A redundant rebuild
                // asks first, since it costs time and changes the file.
                if let rebuildable = WorkReconversion.candidate(for: work) {
                    Button {
                        if rebuildable.isStale {
                            Task { await rebuildFromOriginal() }
                        } else {
                            confirmingRebuild = true
                        }
                    } label: {
                        Label("Rebuild from Original", systemImage: "arrow.triangle.2.circlepath")
                    }
                }

                NavigationLink(value: LocalWorkDestination.detail(work)) {
                    Label("Work Details", systemImage: "info.circle")
                }

                Divider()

                Button(role: .destructive) {
                    if confirmBeforeDelete {
                        pendingDelete = work
                    } else {
                        PreservedWorkService.softDelete(work, in: context)
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .sheet(isPresented: $showingAddToQueue) {
                AddToQueueView(work: work)
            }
            .sheet(isPresented: $showingAddToCollection) {
                AddToCollectionView(work: work)
            }
            .commentsSheet(
                isPresented: $showingComments,
                workID: commentsWorkID ?? 0,
                context: .init(savedWork: work)
            )
            .deleteConfirmation(
                for: $pendingDelete,
                title: "Delete this work?",
                confirmLabel: "Delete",
                message: { PreservedWorkService.deleteConfirmationMessage(for: $0) },
                perform: { PreservedWorkService.softDelete($0, in: context) }
            )
            .confirmationDialog(
                "Rebuild this work?",
                isPresented: $confirmingRebuild,
                titleVisibility: .visible
            ) {
                Button("Rebuild") { Task { await rebuildFromOriginal() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This work was already built with the latest converter, so its text is "
                    + "unlikely to change. Rebuilding re-reads everything from the original file, "
                    + "which is worth doing if its details look wrong.")
            }
            .alert(
                "Couldn't Rebuild This Work",
                isPresented: Binding(
                    get: { rebuildError != nil },
                    set: { if !$0 { rebuildError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { rebuildError = nil }
            } message: {
                Text(rebuildError ?? "")
            }
    }

    /// Rebuilds the EPUB from the archived original. Failure is surfaced through the
    /// same notice the card's other actions use rather than swallowed — a rebuild that
    /// silently did nothing would be worse than one that says why it could not.
    @MainActor
    private func rebuildFromOriginal() async {
        do {
            try await WorkReconversion.reconvert(work, in: context)
        } catch {
            rebuildError = WorkCardActionError.message(for: error)
        }
    }

    @MainActor
    private func toggleFavorite() {
        work.isFavorite.toggle()
        work.markModified()
        try? context.save()
    }

    @MainActor
    private func toggleFinished() {
        if work.isFinished {
            WorkLifecycle.markStillReading(work, in: context)
        } else {
            WorkLifecycle.markFinished(work, in: context)
        }
    }

    @MainActor
    private func toggleSavedForLater() {
        if work.isInSavedForLaterQueue {
            ReadingQueueService.removeFromQueueAndDeleteIfQueueOnly(
                work,
                from: ReadingQueueService.ensureSavedForLaterQueue(in: context),
                in: context
            )
        } else {
            // Discard membership: Task must not inherit a non-Sendable PersistentModel result.
            Task { @MainActor in
                _ = await ReadingQueueService.addToSavedForLater(work, in: context)
            }
        }
    }
}

private struct RemoteWorkContextMenuModifier: ViewModifier {
    let work: AO3WorkSummary

    @Environment(\.modelContext) private var context
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete = true
    // A soft-deleted (pending Recently Deleted) work must not match here — the
    // remote card should offer a fresh "Save" rather than "Delete" for a work
    // that's scheduled to disappear.
    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }, sort: \SavedWork.dateAdded, order: .reverse)
    private var savedWorks: [SavedWork]

    @State private var working = false
    @State private var actionError: String?
    @State private var readerWork: SavedWork?
    @State private var queueWork: SavedWork?
    @State private var collectionWork: SavedWork?
    @State private var showingComments = false
    @State private var pendingDelete: SavedWork?

    private var existingLocalWork: SavedWork? {
        WorkIdentityIndex(savedWorks).existingWork(for: work)
    }

    func body(content: Content) -> some View {
        content
            // Inline, not a modifier taking `existingLocalWork` as a parameter.
            // That lookup builds a `WorkIdentityIndex` over the *entire* library
            // (three dictionaries, with URL parsing per work), and passing it as
            // a parameter forced it to run for every visible card on every body
            // pass. Referenced only inside these closures it keeps the same
            // deferred cost profile `.contextMenu` below already relies on.
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                // Full swipe takes the first action. Save is the common intent
                // from a listing, and it's what the local rows put here too.
                if existingLocalWork?.isSaved != true {
                    Button(action: save) {
                        Label("Save", systemImage: "bookmark")
                    }
                    .tint(.blue)
                    .disabled(working)
                }

                Button(action: toggleSavedForLater) {
                    let labels = WorkActionLabels.savedForLater(
                        isQueued: existingLocalWork?.isInSavedForLaterQueue == true
                    )
                    Label(labels.title, systemImage: labels.systemImage)
                }
                .tint(.indigo)
                .disabled(working)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                // Delete only exists once the work is actually in the library —
                // there is nothing to delete for a listing not taken yet. Full
                // swipe stays off so a flick can't destroy a saved work.
                if let existingLocalWork, existingLocalWork.isSaved {
                    Button(role: .destructive) {
                        if confirmBeforeDelete {
                            pendingDelete = existingLocalWork
                        } else {
                            PreservedWorkService.softDelete(existingLocalWork, in: context)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(working)
                }

                Button(action: addToQueue) {
                    Label("Add to Queue", systemImage: "list.bullet.rectangle")
                }
                .tint(.orange)
                .disabled(working)
            }
            .contextMenu {
                Button {
                    read()
                } label: {
                    Label("Read", systemImage: "book")
                }
                .disabled(working)

                Button {
                    showingComments = true
                } label: {
                    Label("Comments", systemImage: "bubble.left.and.bubble.right")
                }

                if let existingLocalWork, existingLocalWork.isSaved {
                    Button(role: .destructive) {
                        if confirmBeforeDelete {
                            pendingDelete = existingLocalWork
                        } else {
                            PreservedWorkService.softDelete(existingLocalWork, in: context)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(working)
                } else {
                    Button {
                        save()
                    } label: {
                        Label("Save", systemImage: "bookmark")
                    }
                    .disabled(working)
                }

                Button {
                    toggleSavedForLater()
                } label: {
                    let labels = WorkActionLabels.savedForLater(
                        isQueued: existingLocalWork?.isInSavedForLaterQueue == true
                    )
                    Label(labels.title, systemImage: labels.systemImage)
                }
                .disabled(working)

                Button {
                    addToQueue()
                } label: {
                    Label("Add to Queue", systemImage: "list.bullet.rectangle")
                }
                .disabled(working)

                Button {
                    toggleFinished()
                } label: {
                    let labels = WorkActionLabels.finished(isFinished: existingLocalWork?.isFinished == true)
                    Label(labels.title, systemImage: labels.systemImage)
                }
                .disabled(working)

                Button {
                    addToCollection()
                } label: {
                    Label("Add to Collection", systemImage: "square.stack")
                }
                .disabled(working)

                NavigationLink(value: work) {
                    Label("Work Details", systemImage: "info.circle")
                }
            }
            .navigationDestination(item: $readerWork) { BookReaderView(work: $0) }
            .sheet(item: $queueWork) { AddToQueueView(work: $0) }
            .sheet(item: $collectionWork) { AddToCollectionView(work: $0) }
            .commentsSheet(
                isPresented: $showingComments,
                workID: work.id,
                context: .init(remote: work)
            )
            .deleteConfirmation(
                for: $pendingDelete,
                title: "Delete this work?",
                confirmLabel: "Delete",
                message: { PreservedWorkService.deleteConfirmationMessage(for: $0) },
                perform: { PreservedWorkService.softDelete($0, in: context) }
            )
            .alert(
                "Action Failed",
                isPresented: Binding(
                    get: { actionError != nil },
                    set: { if !$0 { actionError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { actionError = nil }
            } message: {
                Text(actionError ?? "")
            }
    }

    private func read() {
        performRemoteAction { saved in
            if !WorkReaderPreparation.hasReadableEPUB(for: saved) {
                try await WorkReaderPreparation.restoreReadableEPUB(for: saved, in: context)
            }
            readerWork = saved
        }
    }

    private func save() {
        performRemoteAction { saved in
            WorkLifecycle.setSaved(saved, true, in: context)
        }
    }

    private func addToQueue() {
        performRemoteAction { saved in
            queueWork = saved
        }
    }

    private func toggleSavedForLater() {
        performRemoteAction { saved in
            if saved.isInSavedForLaterQueue {
                ReadingQueueService.removeFromQueueAndDeleteIfQueueOnly(
                    saved,
                    from: ReadingQueueService.ensureSavedForLaterQueue(in: context),
                    in: context
                )
            } else {
                _ = await ReadingQueueService.addToSavedForLater(saved, in: context)
            }
        }
    }

    private func addToCollection() {
        performRemoteAction { saved in
            collectionWork = saved
        }
    }

    private func toggleFinished() {
        performRemoteAction { saved in
            if saved.isFinished {
                WorkLifecycle.markStillReading(saved, in: context)
            } else {
                WorkLifecycle.markFinished(saved, in: context)
            }
        }
    }

    private func performRemoteAction(_ action: @MainActor @escaping (SavedWork) async throws -> Void) {
        guard !working else { return }
        Task { @MainActor in
            working = true
            actionError = nil
            defer { working = false }

            do {
                let saved = try await resolveLocalWork()
                try await action(saved)
            } catch {
                actionError = WorkCardActionError.message(for: error)
            }
        }
    }

    @MainActor
    private func resolveLocalWork() async throws -> SavedWork {
        try await ReadingQueueService.resolveLocalWork(for: work, in: context)
    }
}

extension View {
    func localWorkContextMenu(work: SavedWork, onSelect: (() -> Void)? = nil) -> some View {
        modifier(LocalWorkContextMenuModifier(work: work, onSelect: onSelect))
    }

    func remoteWorkContextMenu(work: AO3WorkSummary) -> some View {
        modifier(RemoteWorkContextMenuModifier(work: work))
    }
}
