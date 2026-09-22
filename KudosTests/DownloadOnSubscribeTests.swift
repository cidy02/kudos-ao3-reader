import Foundation
import SwiftData
import Testing
@testable import Kudos

/// `WorkDetailView.downloadItem(for:downloadOnSubscribe:)` — the pure decision
/// seam behind the Downloads toggle. The surrounding method reads
/// `@Environment`/`@AppStorage` a test cannot construct, so this is the part
/// worth asserting directly: whether a successful subscribe queues a download,
/// and that it never queues one that would be wasted or wrong.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct DownloadOnSubscribeTests {
    private func work(
        hasEPUB: Bool = false, sourceURL: String = "https://archiveofourown.org/works/9001"
    ) -> SavedWork {
        let work = SavedWork(title: "Bound By Starlight", author: "Writer", sourceURL: sourceURL)
        work.hasEPUB = hasEPUB
        work.isComplete = true
        return work
    }

    /// The toggle is off by default — see it settled.
    @Test func offByDefaultQueuesNothing() {
        #expect(WorkDetailView.downloadItem(for: work(), downloadOnSubscribe: false) == nil)
    }

    /// Already has the file: queuing a download would just redo work
    /// `DownloadQueue` already skips, and would mislead the progress banner
    /// into announcing a download that does nothing.
    @Test func alreadyDownloadedQueuesNothing() {
        let item = WorkDetailView.downloadItem(for: work(hasEPUB: true), downloadOnSubscribe: true)
        #expect(item == nil)
    }

    /// No source URL at all — an EPUB import that never resolved one, or a
    /// hand-edited record — means no way to fetch anything. `URL(string:)`
    /// is lenient (it percent-encodes rather than rejects almost any
    /// non-empty string), so empty is the one input it reliably refuses; the
    /// same guard `downloadSeries` uses before it enqueues anything.
    @Test func emptySourceURLQueuesNothing() {
        let item = WorkDetailView.downloadItem(
            for: work(sourceURL: ""), downloadOnSubscribe: true
        )
        #expect(item == nil)
    }

    /// The one case that should queue something, with the fields
    /// `DownloadQueue.run` actually needs: the AO3 work id (parsed from the
    /// source URL), the title for the progress banner, the source URL to
    /// fetch, completion for the importer, and an empty `seriesURL` — this is
    /// one work, not a series.
    @Test func missingEPUBWithToggleOnQueuesTheWork() throws {
        let item = try #require(
            WorkDetailView.downloadItem(for: work(), downloadOnSubscribe: true)
        )
        #expect(item.id == 9001)
        #expect(item.title == "Bound By Starlight")
        #expect(item.sourceURL == URL(string: "https://archiveofourown.org/works/9001"))
        #expect(item.isComplete)
        #expect(item.seriesURL.isEmpty)
    }
}

/// `DownloadQueue.disposition(for:)` — the part `downloadItem` alone cannot
/// prove. A queued `Item` reaching the real queue is, by construction,
/// already the work it names (source-matched to itself), so the case that
/// matters most here is the one the production bug got backwards: an
/// ordinary, undeleted match with no EPUB has to fall through to a download,
/// not skip because *something* matched.
@MainActor
@Suite(.serialized)
struct DownloadQueueDispositionTests {
    private func work(hasEPUB: Bool, isPendingDeletion: Bool = false) -> SavedWork {
        let work = SavedWork(title: "Bound By Starlight", author: "Writer")
        work.hasEPUB = hasEPUB
        work.isPendingDeletion = isPendingDeletion
        return work
    }

    /// No match at all — nothing to be skipped for.
    @Test func noExistingMatchDownloads() {
        #expect(DownloadQueue.disposition(for: nil) == .download)
    }

    /// The bug this test would have caught: `downloadItem` only ever queues a
    /// work that is already in the library and already missing its EPUB —
    /// the exact shape reached here. Before the fix this returned `.skip`,
    /// which is why "Download on subscribe" queued an item and then silently
    /// did nothing with it.
    @Test func ordinaryMatchMissingEPUBDownloads() {
        #expect(DownloadQueue.disposition(for: work(hasEPUB: false)) == .downloadOverMissingEPUB)
    }

    /// Already has the file: this is `downloadSeries`'s ordinary case, and
    /// must still skip.
    @Test func ordinaryMatchWithEPUBSkips() {
        #expect(DownloadQueue.disposition(for: work(hasEPUB: true)) == .skip)
    }

    /// Recently Deleted, EPUB still on disk: restore, don't re-fetch.
    @Test func pendingDeletionMatchWithEPUBRestores() {
        #expect(
            DownloadQueue.disposition(for: work(hasEPUB: true, isPendingDeletion: true))
                == .restoreThenSkip
        )
    }

    /// Recently Deleted, EPUB gone: revive it via the download, the same way
    /// `importEPUB`'s own Recently Deleted reuse does.
    @Test func pendingDeletionMatchMissingEPUBDownloads() {
        #expect(
            DownloadQueue.disposition(for: work(hasEPUB: false, isPendingDeletion: true))
                == .downloadOverMissingEPUB
        )
    }
}
}
