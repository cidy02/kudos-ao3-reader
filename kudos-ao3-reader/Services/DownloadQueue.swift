import Foundation
import OSLog
import SwiftData
import SwiftUI

/// Serially downloads several AO3 works (e.g. a whole series) and imports them,
/// reusing the already-serialized `AO3Client` so the network stays polite. Injected
/// at the app root; views enqueue work and `DownloadQueueBanner` shows progress.
@MainActor
@Observable
final class DownloadQueue {
    struct Item: Identifiable, Equatable {
        let id: Int // AO3 work id
        let title: String
        let sourceURL: URL?
        let isComplete: Bool
        let seriesURL: String
        var status: Status = .queued
        /// 0…1 from the download task, when AO3 says how big the file is.
        var fraction: Double = 0
        var startedAt: Date?
    }

    enum Status: Equatable { case queued, downloading, done, skipped, failed }

    private(set) var items: [Item] = []
    private(set) var isRunning = false
    /// Downloads of a work whose file was already here (`WorkDownload.perform`
    /// keeps it at once): when each one's short fill started, by `SavedWork.id`.
    private(set) var instantDownloads: [UUID: Date] = [:]

    /// An in-place chapter update. `enqueue` skips a work that already has its
    /// EPUB, so this is the only way the Resume circle's fraction moves.
    private var updateDownloads: [UUID: UpdateTrack] = [:]

    private struct UpdateTrack {
        var fraction: Double
        var startedAt: Date
    }

    /// The fill a download with nothing to fetch still shows (owner, 2026-10-01).
    static let instantDuration: TimeInterval = 0.7

    private var context: ModelContext?

    /// Works still to process (queued or in flight).
    var pendingCount: Int {
        items.count(where: { $0.status == .queued || $0.status == .downloading })
    }

    var finishedCount: Int {
        items.count - pendingCount
    }

    var total: Int {
        items.count
    }

    var failedCount: Int {
        items.count(where: { $0.status == .failed })
    }

    var currentTitle: String? {
        items.first { $0.status == .downloading }?.title
    }

    var isActive: Bool {
        pendingCount > 0
    }

    /// Enqueues works that aren't already queued and starts processing. A fresh run
    /// (nothing in flight) first clears the previous run's finished rows.
    func enqueue(_ newItems: [Item], into context: ModelContext) {
        self.context = context
        if !isRunning { items.removeAll() }
        var seen = Set(items.map(\.id))
        for item in newItems where seen.insert(item.id).inserted {
            items.append(item)
        }
        if !isRunning, !items.isEmpty {
            isRunning = true // set synchronously so a rapid second enqueue appends
            Task { await run() }
        }
    }

    /// The short fill for a work whose file was already here.
    func showInstantDownload(for work: SavedWork) {
        let id = work.id
        instantDownloads[id] = Date()
        Task {
            try? await Task.sleep(for: .seconds(Self.instantDuration))
            instantDownloads[id] = nil
        }
    }

    /// Whether `work`'s progress ring should show a download right now.
    func isDownloading(_ work: SavedWork) -> Bool {
        instantDownloads[work.id] != nil
            || updateDownloads[work.id] != nil
            || activeItem(for: work) != nil
    }

    /// Starts the fraction the Resume update circle reads. `at` is the creep's
    /// origin; production passes the default.
    func beginUpdateDownload(for id: UUID, at now: Date = Date()) {
        updateDownloads[id] = UpdateTrack(fraction: 0, startedAt: now)
    }

    /// AO3's reported fraction, when the response includes a size. Ignored
    /// once the update has ended, so a late callback cannot revive it.
    func noteUpdateDownloadProgress(_ fraction: Double, for id: UUID) {
        guard var track = updateDownloads[id] else { return }
        track.fraction = max(track.fraction, fraction)
        updateDownloads[id] = track
    }

    func endUpdateDownload(for id: UUID) {
        updateDownloads[id] = nil
    }

    /// The download fill for `work`'s ring at `now`, or nil when it is not
    /// downloading. A real download shows the larger of AO3's own progress and a
    /// floor that creeps toward 90%, so the ring moves while AO3 paces the
    /// request or sends no file size; it reaches 100% when the file is in.
    func downloadFraction(for work: SavedWork, at now: Date) -> Double? {
        if let update = updateDownloads[work.id] {
            return Self.creepingFraction(from: update.startedAt, reported: update.fraction, at: now)
        }
        if let start = instantDownloads[work.id] {
            return min(1, now.timeIntervalSince(start) / Self.instantDuration)
        }
        guard let item = activeItem(for: work) else { return nil }
        guard let start = item.startedAt else { return 0 }
        return Self.creepingFraction(from: start, reported: item.fraction, at: now)
    }

    /// Shared by a queue row and an in-place update: AO3's fraction, or a floor
    /// that creeps toward 90% while the size is unknown.
    private static func creepingFraction(from start: Date, reported: Double, at now: Date) -> Double {
        let creep = 0.9 * (1 - exp(-now.timeIntervalSince(start) / 4))
        return max(reported, creep)
    }

    /// The fill a cover bar or Resume ring draws while `work` is downloading,
    /// or nil when it is not. A missing queue fraction reads as full so the
    /// control does not sit empty. Callers that need the bar to move pass
    /// `TimelineView`'s date.
    func liveDownloadFraction(for work: SavedWork, at now: Date) -> Double? {
        guard isDownloading(work) else { return nil }
        return downloadFraction(for: work, at: now) ?? 1
    }

    private func activeItem(for work: SavedWork) -> Item? {
        guard let ao3ID = work.ao3WorkID ?? WorkTags.ao3WorkID(from: work.sourceURL) else { return nil }
        return items.first { $0.id == ao3ID && ($0.status == .queued || $0.status == .downloading) }
    }

    private func setFraction(_ fraction: Double, for id: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].fraction = max(items[index].fraction, fraction)
    }

    /// Cancels everything still queued. A download already in flight finishes.
    func cancel() {
        items.removeAll { $0.status == .queued }
    }

    /// What an already-existing match means for a queued item — separated from
    /// `run()` so the decision is a plain function a test can call directly,
    /// rather than one only observable by letting the loop reach a real network
    /// fetch. A test that never exercises this is a test that cannot fail when
    /// this disposition is wrong, which is exactly how the ordinary-match branch
    /// stayed unconditional after the comment above it said otherwise.
    enum ExistingMatchDisposition: Equatable {
        /// No existing match (or none was looked up) — proceed to download.
        case download
        /// An existing match with no EPUB — proceed to download, filling it in.
        case downloadOverMissingEPUB
        /// An existing, undeleted match that already has its EPUB.
        case skip
        /// A Recently Deleted match with its EPUB still on disk — restore it
        /// rather than re-fetching.
        case restoreThenSkip
    }

    static func disposition(for existing: SavedWork?) -> ExistingMatchDisposition {
        guard let existing else { return .download }
        if !existing.isPendingDeletion {
            return existing.hasEPUB ? .skip : .downloadOverMissingEPUB
        }
        return existing.hasEPUB ? .restoreThenSkip : .downloadOverMissingEPUB
    }

    private func run() async {
        defer { isRunning = false }
        guard let context else { return }

        while let index = items.firstIndex(where: { $0.status == .queued }) {
            let item = items[index]
            let existing = item.sourceURL.flatMap { existingWork(forSource: $0, in: context) }
            switch Self.disposition(for: existing) {
            case .download, .downloadOverMissingEPUB:
                break
            case .skip:
                items[index].status = .skipped
                continue
            case .restoreThenSkip:
                if let existing { PreservedWorkService.restore(existing, in: context) }
                items[index].status = .skipped
                continue
            }
            items[index].status = .downloading
            items[index].startedAt = Date()
            do {
                let id = item.id
                let temp = try await AO3Client.shared.downloadEPUB(workID: id) { fraction in
                    Task { @MainActor [weak self] in self?.setFraction(fraction, for: id) }
                }
                _ = try await importEPUB(
                    temp, source: item.sourceURL,
                    isComplete: item.isComplete, seriesURL: item.seriesURL, into: context
                )
                // A beat at 100% before the ring hands back to reading progress.
                items[index].fraction = 1
                try? await Task.sleep(for: .milliseconds(300))
                items[index].status = .done
            } catch {
                items[index].status = .failed
                Log.library.error(
                    "Queue download failed for work \(item.id, privacy: .private(mask: .hash)): \(error.localizedDescription, privacy: .private)"
                )
            }
        }
        Log.library.info("Download queue finished: \(self.finishedCount) processed, \(self.failedCount) failed")
    }
}

/// A compact progress banner for the active download queue, shown at the app root.
struct DownloadQueueBanner: View {
    @Environment(DownloadQueue.self) private var queue

    var body: some View {
        Group {
            if queue.isActive {
                HStack(spacing: 12) {
                    ProgressView().accentFill()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Downloading \(min(queue.finishedCount + 1, queue.total)) of \(queue.total)")
                            .font(.subheadline.weight(.medium))
                        if let title = queue.currentTitle {
                            Text(title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Button("Cancel") { queue.cancel() }
                        .font(.callout)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: queue.isActive)
    }
}
