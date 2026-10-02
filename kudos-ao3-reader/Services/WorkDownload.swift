import Foundation
import SwiftData

/// Download / Remove Download follow what the reader chose to keep (owner,
/// 2026-10-01, reversing 2026-09-28's "follow the file"): a copy fetched only to
/// read a work is not a download, so that work offers Download — which, with
/// the file already here, keeps it at once. Download still fetches a missing
/// file, and Remove Download still deletes one.
enum WorkDownload {
    enum Action: Equatable {
        /// Not kept: fetches the file if it is missing, then keeps it.
        case download
        /// Kept by Download (or "Keep works you read"), and nothing else is
        /// keeping it.
        case removeDownload
        /// On this device because a Keep-offline queue or collection holds it —
        /// removing the file there would only be fetched back.
        case keptBy(String)
    }

    /// Nil when there is nothing to offer: not on the device and no AO3 id to
    /// fetch it from (an import whose file was freed).
    @MainActor
    static func action(for work: SavedWork) -> Action? {
        let hasFile = WorkReaderPreparation.hasReadableEPUB(for: work)
        if hasFile {
            if let holder = keeper(of: work) { return .keptBy(holder) }
            if work.isDownloaded { return .removeDownload }
            return .download
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
            let hasFile = WorkReaderPreparation.hasReadableEPUB(for: work)
            WorkLifecycle.setSaved(work, true, in: context)
            if hasFile {
                // Nothing to fetch; the ring still shows a short fill so the tap
                // reads as a download (owner, 2026-10-01: 0.7 s).
                queue?.showInstantDownload(for: work)
                return
            }
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

    /// Remove Downloads when every selected work is downloaded (one a queue or
    /// collection keeps is skipped); otherwise Download, which keeps the rest and
    /// fetches only the missing ones.
    @MainActor
    static func bulkAction(for works: [SavedWork]) -> Action? {
        guard !works.isEmpty else { return nil }
        if works.allSatisfy(\.isDownloaded) {
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
