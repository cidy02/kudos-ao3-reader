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
        let id: Int            // AO3 work id
        let title: String
        let sourceURL: URL?
        let isComplete: Bool
        let seriesURL: String
        var status: Status = .queued
    }

    enum Status: Equatable { case queued, downloading, done, skipped, failed }

    private(set) var items: [Item] = []
    private(set) var isRunning = false

    private var context: ModelContext?

    /// Works still to process (queued or in flight).
    var pendingCount: Int { items.filter { $0.status == .queued || $0.status == .downloading }.count }
    var finishedCount: Int { items.count - pendingCount }
    var total: Int { items.count }
    var failedCount: Int { items.filter { $0.status == .failed }.count }
    var currentTitle: String? { items.first { $0.status == .downloading }?.title }
    var isActive: Bool { pendingCount > 0 }

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
            isRunning = true   // set synchronously so a rapid second enqueue appends
            Task { await run() }
        }
    }

    /// Cancels everything still queued. A download already in flight finishes.
    func cancel() {
        items.removeAll { $0.status == .queued }
    }

    private func run() async {
        defer { isRunning = false }
        guard let context else { return }

        while let index = items.firstIndex(where: { $0.status == .queued }) {
            let item = items[index]
            // Already in the library? skip rather than make a duplicate.
            if let source = item.sourceURL, existingWork(forSource: source, in: context) != nil {
                items[index].status = .skipped
                continue
            }
            items[index].status = .downloading
            do {
                let temp = try await AO3Client.shared.downloadEPUB(workID: item.id)
                _ = try await importEPUB(
                    temp, source: item.sourceURL,
                    isComplete: item.isComplete, seriesURL: item.seriesURL, into: context
                )
                items[index].status = .done
            } catch {
                items[index].status = .failed
                Log.library.error(
                    "Queue download failed for work \(item.id): \(error.localizedDescription, privacy: .public)"
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
                    ProgressView()
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
