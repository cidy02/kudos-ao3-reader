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
                            WorkLifecycle.delete(work, in: context)
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
                message: { "“\($0.title)” will be removed from your Library. This can't be undone." },
                perform: { WorkLifecycle.delete($0, in: context) }
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
}

private struct RemoteWorkContextMenuModifier: ViewModifier {
    let work: AO3WorkSummary

    @Environment(\.modelContext) private var context
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete = true
    @Query(sort: \SavedWork.dateAdded, order: .reverse) private var savedWorks: [SavedWork]

    @State private var working = false
    @State private var actionError: String?
    @State private var readerWork: SavedWork?
    @State private var queueWork: SavedWork?
    @State private var collectionWork: SavedWork?
    @State private var pendingDelete: SavedWork?

    private var existingLocalWork: SavedWork? {
        let canonicalURL = WorkTags.canonicalAO3WorkURL(from: work.workURL.absoluteString)
        return savedWorks.first { saved in
            saved.ao3WorkID == work.id
                || WorkTags.ao3WorkID(from: saved.sourceURL) == work.id
                || WorkTags.canonicalAO3WorkURL(from: saved.sourceURL) == canonicalURL
        }
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
                            WorkLifecycle.delete(existingLocalWork, in: context)
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
                message: { "“\($0.title)” will be removed from your Library. This can't be undone." },
                perform: { WorkLifecycle.delete($0, in: context) }
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
        if let existing = ReadingQueueService.existingWork(for: work, in: context) {
            return existing
        }

        let temp = try await AO3Client.shared.downloadEPUB(workID: work.id)
        let saved = try await importEPUB(
            temp,
            source: work.workURL,
            isComplete: work.isComplete ?? false,
            seriesURL: work.seriesURL ?? "",
            knownChapterCount: SavedWork.postedChapterCount(from: work.chapters),
            into: context
        )
        ReadingQueueService.applyRemoteMetadata(work, to: saved)
        try? context.save()
        return saved
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
