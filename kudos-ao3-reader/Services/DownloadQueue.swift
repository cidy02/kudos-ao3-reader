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
        var requiresOfflineQueue = false
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
        /// The `beginUpdateDownload` call that created this entry. A later
        /// `endUpdateDownload` removes the entry only when it presents this.
        var token: UUID
    }

    /// The fill a download with nothing to fetch still shows (owner, 2026-10-01).
    static let instantDuration: TimeInterval = 0.7

    typealias EPUBDownload = @MainActor (Int, @escaping @Sendable (Double) -> Void) async throws -> URL
    typealias AvailabilityVerifier = @MainActor (SavedWork, ModelContext) async -> Void

    @ObservationIgnored private let downloadEPUB: EPUBDownload
    @ObservationIgnored private let verifyAvailability: AvailabilityVerifier

    init(
        downloadEPUB: @escaping EPUBDownload = { workID, onProgress in
            try await AO3Client.shared.downloadEPUB(workID: workID, onProgress: onProgress)
        },
        verifyAvailability: @escaping AvailabilityVerifier = { work, context in
            await WorkAvailability.verify(work, in: context)
        }
    ) {
        self.downloadEPUB = downloadEPUB
        self.verifyAvailability = verifyAvailability
    }

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
        Self.merge(newItems, into: &items)
        if !isRunning, !items.isEmpty {
            isRunning = true // set synchronously so a rapid second enqueue appends
            Task { await run() }
        }
    }

    static func merge(_ newItems: [Item], into items: inout [Item]) {
        for item in newItems {
            guard let index = items.firstIndex(where: { $0.id == item.id }) else {
                items.append(item)
                continue
            }
            switch items[index].status {
            case .queued, .downloading:
                if !item.requiresOfflineQueue { items[index].requiresOfflineQueue = false }
            case .done, .skipped, .failed:
                items.remove(at: index)
                items.append(item)
            }
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

    /// Starts the fraction the Resume update circle reads. Returns false when
    /// this work already has an update in flight, so a second view does not
    /// start another request. `token` identifies the entry this call created.
    /// `at` is the creep's origin; production passes the default.
    @discardableResult
    func beginUpdateDownload(for id: UUID, token: UUID, at now: Date = Date()) -> Bool {
        guard updateDownloads[id] == nil else { return false }
        updateDownloads[id] = UpdateTrack(fraction: 0, startedAt: now, token: token)
        return true
    }

    /// AO3's reported fraction, when the response includes a size. Ignored
    /// once the update has ended, so a late callback cannot revive it.
    func noteUpdateDownloadProgress(_ fraction: Double, for id: UUID) {
        guard var track = updateDownloads[id] else { return }
        track.fraction = max(track.fraction, fraction)
        updateDownloads[id] = track
    }

    /// Removes the entry only when `token` is the one `beginUpdateDownload`
    /// stored. The view that lost the race must not clear the winner, and a
    /// late end must not clear an update that started after this one finished.
    func endUpdateDownload(for id: UUID, token: UUID) {
        guard updateDownloads[id]?.token == token else { return }
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

    private func index(of id: Int) -> Int? {
        items.firstIndex(where: { $0.id == id })
    }

    private func setFraction(_ fraction: Double, for id: Int) {
        guard let index = items.firstIndex(where: { $0.id == id && $0.status == .downloading }) else { return }
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

    static func shouldProcess(_ item: Item, existing: SavedWork?) -> Bool {
        guard item.requiresOfflineQueue else { return true }
        guard let existing, existing.modelContext != nil, !existing.isPendingDeletion else { return false }
        return existing.activeQueueMemberships.contains { membership in
            membership.queue.map { KeepOffline.queueKeeps($0.keepsWorksOffline) } == true
        }
    }

    private func run() async {
        defer { isRunning = false }
        guard let context else { return }

        while let index = items.firstIndex(where: { $0.status == .queued }) {
            let item = items[index]
            let id = item.id
            let existing = item.sourceURL.flatMap { existingWork(forSource: $0, in: context) }
            guard Self.shouldProcess(item, existing: existing) else {
                items[index].status = .skipped
                continue
            }
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
                let temp = try await downloadEPUB(id) { fraction in
                    Task { @MainActor [weak self] in self?.setFraction(fraction, for: id) }
                }
                guard let current = self.index(of: id),
                      Self.shouldProcess(
                          items[current], existing: item.sourceURL.flatMap { existingWork(forSource: $0, in: context) }
                      ) else {
                    try? FileManager.default.removeItem(at: temp)
                    if let current = self.index(of: id) { items[current].status = .skipped }
                    continue
                }
                let saved = try await importEPUB(
                    temp, source: item.sourceURL,
                    isComplete: item.isComplete, seriesURL: item.seriesURL,
                    verifyAvailability: false,
                    canImport: {
                        guard let liveIndex = self.index(of: id) else { return false }
                        return Self.shouldProcess(
                            self.items[liveIndex],
                            existing: item.sourceURL.flatMap { existingWork(forSource: $0, in: context) }
                        )
                    }, into: context
                )
                if saved.modelContext != nil, !saved.isPendingDeletion {
                    await verifyAvailability(saved, context)
                    if saved.modelContext != nil, !saved.isPendingDeletion {
                        Self.finishImportedWork(saved, in: context)
                    }
                }
                // A beat at 100% before the ring hands back to reading progress.
                if let current = self.index(of: id) { items[current].fraction = 1 }
                try? await Task.sleep(for: .milliseconds(300))
                if let current = self.index(of: id) { items[current].status = .done }
            } catch {
                if let current = self.index(of: id) {
                    items[current].status = error is CancellationError ? .skipped : .failed
                }
                if !(error is CancellationError) {
                    let reason = error.localizedDescription
                    Log.library.error(
                        "Queue download \(id, privacy: .private(mask: .hash)) failed: \(reason, privacy: .private)"
                    )
                }
            }
        }
        Log.library.info("Download queue finished: \(self.finishedCount) processed, \(self.failedCount) failed")
    }

    static func finishImportedWork(_ work: SavedWork, in context: ModelContext) {
        ReadingQueueService.normalize(work)
        if work.isQueuedForLater {
            work.metadataSyncStatus = work.ao3Unavailable ? .failed
                : (!work.workTagsFetched || work.needsAO3Refresh ? .incomplete : .complete)
        }
        context.saveBestEffort(reason: "Saving queued import status failed")
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
