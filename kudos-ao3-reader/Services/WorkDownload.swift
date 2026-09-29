import Foundation
import SwiftData

/// Download / Remove Download follow the EPUB on this device (owner,
/// 2026-09-28) — not `isSaved`, the keep-forever flag. A work opened once, or
/// kept by a queue, is downloaded; offering "Download" on it said otherwise, and
/// the old toggle only flipped the flag, so "Download" never fetched anything
/// and "Remove Download" never removed a file.
enum WorkDownload {
    enum Action: Equatable {
        /// Not on this device, and AO3 can supply it.
        case download
        /// On this device, and nothing else is keeping it.
        case removeDownload
        /// On this device because a Keep-offline queue or collection holds it —
        /// removing the file there would only be fetched back.
        case keptBy(String)
    }

    /// Nil when there is nothing to offer: not on the device and no AO3 id to
    /// fetch it from (an import whose file was freed).
    @MainActor
    static func action(for work: SavedWork) -> Action? {
        if WorkReaderPreparation.hasReadableEPUB(for: work) {
            if let holder = keeper(of: work) { return .keptBy(holder) }
            return .removeDownload
        }
        guard work.ao3WorkID ?? WorkTags.ao3WorkID(from: work.sourceURL) != nil else { return nil }
        return .download
    }

    /// The first Keep-offline container holding this work, by name.
    static func keeper(of work: SavedWork) -> String? {
        if let queue = work.activeQueueMemberships.compactMap(\.queue)
            .first(where: { KeepOffline.queueKeeps($0.keepsWorksOffline) }) {
            return queue.displayName
        }
        return work.activeCollections
            .first { KeepOffline.collectionKeeps($0.keepsWorksOffline) }?
            .name
    }

    static func label(_ action: Action) -> (title: String, systemImage: String) {
        switch action {
        case .download: ("Download", WorkActionLabels.downloadEmptySymbol)
        case .removeDownload: ("Remove Download", "arrow.down.circle.badge.xmark")
        case let .keptBy(name): ("Kept Offline by \(name)", WorkActionLabels.downloadedSymbol)
        }
    }

    /// Download fetches the EPUB and keeps it; Remove Download deletes the file
    /// and the keep flag, leaving the record as history. `keptBy` does nothing.
    /// With a `queue`, Download goes through the app's `DownloadQueue`, whose
    /// banner shows it running and says if it failed; without one it fetches
    /// inline and throws.
    @MainActor
    static func perform(
        _ action: Action, on work: SavedWork, in context: ModelContext, queue: DownloadQueue? = nil
    ) async throws {
        switch action {
        case .download:
            WorkLifecycle.setSaved(work, true, in: context)
            if let queue {
                queue.enqueue(KeepOffline.downloadItems(for: [work]), into: context)
                return
            }
            try await WorkReaderPreparation.restoreReadableEPUB(for: work, in: context)
        case .removeDownload:
            work.isSaved = false
            WorkLifecycle.freeEPUB(work)
            context.saveBestEffort(reason: "Removing a download failed")
        case .keptBy:
            return
        }
    }

    // MARK: Bulk

    /// Remove Downloads when every selected work is on this device (a kept one
    /// is skipped); otherwise Download, which fetches only the missing ones.
    @MainActor
    static func bulkAction(for works: [SavedWork]) -> Action? {
        guard !works.isEmpty else { return nil }
        if works.allSatisfy(WorkReaderPreparation.hasReadableEPUB(for:)) {
            return works.contains { keeper(of: $0) == nil } ? .removeDownload : nil
        }
        return .download
    }

    static func bulkLabel(_ action: Action) -> (title: String, systemImage: String) {
        action == .removeDownload ? ("Remove Downloads", label(action).systemImage) : label(action)
    }

    /// One at a time: the same AO3 endpoint per work, never a burst.
    @MainActor
    static func performBulk(
        _ action: Action, on works: [SavedWork], in context: ModelContext, queue: DownloadQueue? = nil
    ) async {
        for work in works {
            guard let own = self.action(for: work) else { continue }
            switch (action, own) {
            case (.download, .download), (.removeDownload, .removeDownload):
                try? await perform(own, on: work, in: context, queue: queue)
            case (.download, .removeDownload), (.download, .keptBy):
                WorkLifecycle.setSaved(work, true, in: context)
            default:
                continue
            }
        }
    }
}
