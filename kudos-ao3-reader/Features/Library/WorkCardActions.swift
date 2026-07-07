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

    var body: some View {
        switch destination {
        case let .reader(work):
            LocalWorkReaderDestination(work: work, onOpen: onReaderOpen)
        case let .detail(work):
            WorkDetailView(work: work)
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
            ProgressView(phase == .restoring ? "Restoring EPUB…" : "Opening…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    @State private var pendingDelete: SavedWork?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                NavigationLink(value: LocalWorkDestination.reader(work)) {
                    Label("Read", systemImage: "book")
                }

                if let onSelect {
                    Button(action: onSelect) {
                        Label("Select", systemImage: "checklist")
                    }
                }

                if work.isSaved {
                    Button(role: .destructive) {
                        if confirmBeforeDelete {
                            pendingDelete = work
                        } else {
                            PreservedWorkService.softDelete(work, in: context)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } else {
                    Button {
                        WorkLifecycle.setSaved(work, true, in: context)
                    } label: {
                        Label("Save", systemImage: "bookmark")
                    }
                }

                Button {
                    toggleSavedForLater()
                } label: {
                    Label(
                        work.isInSavedForLaterQueue ? "Remove from Saved for Later" : "Save for Later",
                        systemImage: work.isInSavedForLaterQueue ? "bookmark.slash" : "bookmark.fill"
                    )
                }

                Button {
                    showingAddToQueue = true
                } label: {
                    Label("Add to Queue", systemImage: "list.bullet.rectangle")
                }

                Button {
                    toggleFinished()
                } label: {
                    Label(
                        work.isFinished ? "Mark as Still Reading" : "Mark as Finished",
                        systemImage: work.isFinished ? "arrow.uturn.backward.circle" : "checkmark.circle"
                    )
                }

                Button {
                    showingAddToCollection = true
                } label: {
                    Label("Add to Collection", systemImage: "square.stack")
                }

                NavigationLink(value: LocalWorkDestination.detail(work)) {
                    Label("Work Details", systemImage: "info.circle")
                }
            }
            .sheet(isPresented: $showingAddToQueue) {
                AddToQueueView(work: work)
            }
            .sheet(isPresented: $showingAddToCollection) {
                AddToCollectionView(work: work)
            }
            .deleteConfirmation(
                for: $pendingDelete,
                title: "Delete this work?",
                confirmLabel: "Delete",
                message: { PreservedWorkService.deleteConfirmationMessage(for: $0) },
                perform: { PreservedWorkService.softDelete($0, in: context) }
            )
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
            Task { await ReadingQueueService.addToSavedForLater(work, in: context) }
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
    @State private var pendingDelete: SavedWork?

    private var existingLocalWork: SavedWork? {
        WorkIdentityIndex(savedWorks).existingWork(for: work)
    }

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button {
                    read()
                } label: {
                    Label("Read", systemImage: "book")
                }
                .disabled(working)

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
                    Label(
                        existingLocalWork?.isInSavedForLaterQueue == true
                            ? "Remove from Saved for Later" : "Save for Later",
                        systemImage: existingLocalWork?.isInSavedForLaterQueue == true
                            ? "bookmark.slash" : "bookmark.fill"
                    )
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
                    Label(
                        existingLocalWork?.isFinished == true ? "Mark as Still Reading" : "Mark as Finished",
                        systemImage: existingLocalWork?.isFinished == true
                            ? "arrow.uturn.backward.circle"
                            : "checkmark.circle"
                    )
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
