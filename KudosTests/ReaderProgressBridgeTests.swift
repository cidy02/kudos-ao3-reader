import Foundation
import Testing
@testable import Kudos

/// Covers the platform-neutral half of the macOS reader's intra-chapter
/// position bridge (A7-F2): script-message parsing with stale-generation
/// gating, the fraction ↔ page restore mapping shared by scrolled and paged
/// modes, per-chapter session memory, and the SwiftData write debounce with a
/// guaranteed final flush.
@MainActor
struct ReaderProgressBridgeTests {

    // MARK: Message parsing + stale-generation gating

    @Test func staleGenerationMessagesAreDropped() {
        // A late callback from an old chapter's document must never overwrite
        // the current chapter's state.
        let stale: [String: Any] = ["event": "progress", "fraction": 0.8, "gen": 1]
        #expect(ReaderBridgeMessage.parse(stale, currentGeneration: 2) == nil)

        let current: [String: Any] = ["event": "progress", "fraction": 0.8, "gen": 2]
        #expect(ReaderBridgeMessage.parse(current, currentGeneration: 2) == .progress(fraction: 0.8))
    }

    @Test func messagesWithoutAGenerationAreDropped() {
        #expect(ReaderBridgeMessage.parse(["event": "progress", "fraction": 0.5],
                                          currentGeneration: 0) == nil)
        #expect(ReaderBridgeMessage.parse(["mode": "paged", "page": 2, "total": 9],
                                          currentGeneration: 0) == nil)
    }

    @Test func parsesEveryBridgeMessageShape() {
        func parse(_ body: Any) -> ReaderBridgeMessage? {
            ReaderBridgeMessage.parse(body, currentGeneration: 1)
        }
        #expect(parse(["key": "ArrowLeft", "gen": 1]) == .key("ArrowLeft"))
        #expect(parse(["event": "bottom", "gen": 1]) == .reachedScrollBottom)
        #expect(parse(["mode": "paged", "page": 3, "total": 12, "gen": 1])
            == .pagePosition(page: 3, total: 12))
        #expect(parse(["event": "progress", "fraction": 0.25, "gen": 1])
            == .progress(fraction: 0.25))
        // Hostile/degenerate payloads fail safely.
        #expect(parse("garbage") == nil)
        #expect(parse(["event": "unknown", "gen": 1]) == nil)
        #expect(parse(["event": "progress", "fraction": Double.nan, "gen": 1]) == nil)
        #expect(parse(["event": "progress", "fraction": 1.7, "gen": 1])
            == .progress(fraction: 1.0)) // clamped
        #expect(parse(["mode": "paged", "page": 0, "total": 0, "gen": 1])
            == .pagePosition(page: 1, total: 1)) // floored to sane minimums
    }

    // MARK: Restore mapping (scrolled ↔ paged ↔ reflow)

    @Test func pagedRoundTripRestoresTheExactPage() {
        // Midpoint paged reopen: a persisted page/total fraction restores that
        // same page, including totals whose fractions aren't exact binary
        // doubles (3, 7, 313).
        for total in [1, 2, 3, 7, 10, 313] {
            for page in 0 ..< total {
                let fraction = Double(page) / Double(total)
                #expect(ReaderProgressBridge.pageIndex(fraction: fraction, pageCount: total) == page)
            }
        }
    }

    @Test func scrolledFractionLandsInTheContainingPage() {
        // Scrolled → paged: the restore lands on the page containing the saved
        // spot, never past it (re-reading a line beats skipping one).
        #expect(ReaderProgressBridge.pageIndex(fraction: 0.5, pageCount: 10) == 5)
        #expect(ReaderProgressBridge.pageIndex(fraction: 0.49999, pageCount: 10) == 4)
        #expect(ReaderProgressBridge.pageIndex(fraction: 0, pageCount: 10) == 0)
        #expect(ReaderProgressBridge.pageIndex(fraction: 1, pageCount: 10) == 9) // clamped to last page
        #expect(ReaderProgressBridge.pageIndex(fraction: 0.5, pageCount: 0) == 0) // degenerate layout
    }

    @Test func reflowRemapsTheSameFractionProportionally() {
        // Resize/reflow changes the page count; the same semantic fraction
        // restores the proportional page in the new layout.
        #expect(ReaderProgressBridge.pageIndex(fraction: 0.5, pageCount: 20) == 10)
        #expect(ReaderProgressBridge.pageIndex(fraction: 0.5, pageCount: 7) == 3)
    }

    @Test func modeSwitchQuantizationIsAFixedPoint() {
        // Paged → scrolled → paged quantizes to a page start once, then stays
        // put — repeated switches can't drift the position.
        let total = 10
        let page = ReaderProgressBridge.pageIndex(fraction: 0.52, pageCount: total)
        let quantized = Double(page) / Double(total)
        #expect(ReaderProgressBridge.pageIndex(fraction: quantized, pageCount: total) == page)
    }

    // MARK: Per-chapter session memory

    @Test func returningToAPriorChapterRestoresItsPosition() {
        // A → B → A restores A's position (the audit's revisit requirement).
        let bridge = ReaderProgressBridge()
        _ = bridge.beginChapter(spine: 3)
        bridge.recordProgress(0.62)
        #expect(bridge.beginChapter(spine: 4) == 0) // first visit → top
        bridge.recordProgress(0.1)
        #expect(bridge.beginChapter(spine: 3) == 0.62)
    }

    @Test func seedRestoresThePersistedReopenPosition() {
        // Midpoint reopen: the persisted spine + fraction seed the first load.
        let bridge = ReaderProgressBridge()
        bridge.seed(spine: 5, fraction: 0.5)
        #expect(bridge.beginChapter(spine: 5) == 0.5)
    }

    @Test func explicitSameChapterRepickResetsToTheStart() {
        let bridge = ReaderProgressBridge()
        _ = bridge.beginChapter(spine: 2)
        bridge.recordProgress(0.8)
        bridge.forget(spine: 2)
        #expect(bridge.beginChapter(spine: 2) == 0)
        #expect(bridge.currentFraction == 0)
    }

    // MARK: Write debounce + guaranteed final flush

    @Test func streamedUpdatesAreDebounced() {
        let bridge = ReaderProgressBridge()
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        _ = bridge.beginChapter(spine: 0)
        bridge.markPersisted(0, at: start)

        bridge.recordProgress(0.2)
        // Inside the debounce window: no write, however often progress streams.
        #expect(bridge.fractionForDebouncedWrite(at: start.addingTimeInterval(0.5)) == nil)
        // Window elapsed: the latest value is written.
        #expect(bridge.fractionForDebouncedWrite(at: start.addingTimeInterval(2.5)) == 0.2)
    }

    @Test func noiseBelowTheThresholdIsNeverWritten() {
        let bridge = ReaderProgressBridge()
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        _ = bridge.beginChapter(spine: 0)
        bridge.recordProgress(0.5)
        bridge.markPersisted(0.5, at: start)

        bridge.recordProgress(0.5004) // sub-threshold jitter
        #expect(bridge.fractionForDebouncedWrite(at: start.addingTimeInterval(10)) == nil)
    }

    @Test func dismissalFlushBypassesTheDebounceWindow() {
        let bridge = ReaderProgressBridge()
        _ = bridge.beginChapter(spine: 0)
        bridge.markPersisted(0, at: Date())

        bridge.recordProgress(0.42) // debounce window still open…
        #expect(bridge.fractionForFlush() == 0.42) // …but a flush always writes
        bridge.markPersisted(0.42)
        #expect(bridge.fractionForFlush() == nil) // nothing new → no redundant write
    }

    // MARK: Card percent (legacyReaderProgress)

    /// Two 1 KB spine items: one position each, so spine 1 spans 0.5…1.
    private static let lengths = [1024, 1024]

    @Test func openingWriteKeepsAnotherReadersPercent() {
        // Read to 60% on the iPhone, then opened on the Mac, which lands on its
        // own stale spine: the load's re-save must not relabel the work.
        let bridge = ReaderProgressBridge()
        let work = SavedWork(title: "T", author: "A")
        work.legacyReaderProgress = 0.6
        bridge.seed(spine: 1, fraction: 0.5)
        bridge.persist(bridge.beginChapter(spine: 1), to: work, resourceLengths: Self.lengths)
        #expect(work.lastScrollFraction == 0.5)
        #expect(work.legacyReaderProgress == 0.6)

        // Moving claims it, at the bridge's spine.
        bridge.recordProgress(0.8)
        bridge.persist(0.8, to: work, resourceLengths: Self.lengths)
        #expect(work.legacyReaderProgress == 0.9)
    }

    /// Opened on the Mac and closed again without reading: the layout reports the
    /// restored spot — as seeded, floored to a page (paged mode, which also posts
    /// page 1 first) or clamped to the last screen (scrolled) — and the dismiss
    /// flush writes it. None of that is reading, so the iPhone's percent stays.
    @Test func openingAndClosingNeverClaimsThePercent() {
        for landed in [0.5, 0.25, 0] {
            let bridge = ReaderProgressBridge()
            let work = SavedWork(title: "T", author: "A")
            work.legacyReaderProgress = 0.8
            bridge.seed(spine: 1, fraction: 0.5)
            bridge.persist(bridge.beginChapter(spine: 1), to: work, resourceLengths: Self.lengths)
            bridge.recordProgress(landed)
            if let due = bridge.fractionForDebouncedWrite(at: .distantFuture) {
                bridge.persist(due, to: work, resourceLengths: Self.lengths)
            }
            if let flush = bridge.fractionForFlush() {
                bridge.persist(flush, to: work, resourceLengths: Self.lengths)
            }
            #expect(work.lastScrollFraction == landed) // resume still follows the page
            #expect(work.legacyReaderProgress == 0.8, "landed at \(landed)")
        }
    }

    /// One chapter, opened at 50%. Paged mode posts page 1 and then the restored
    /// page; that pair is the landing, not a read. Scrolling back to the start
    /// and on to 40%, or re-picking this chapter and reading to 40%, has to
    /// replace the other device's percent. The resume fraction already did.
    @Test func readingBackFromTheOpeningClaimsThePercent() {
        let lengths: [Int?] = [1024]
        let atForty = WorkReadingPosition.publicationProgress(
            spineIndex: 0, chapterFraction: 0.4, resourceLengths: lengths)

        let scrolledBack = ReaderProgressBridge()
        let backWork = SavedWork(title: "T", author: "A")
        backWork.legacyReaderProgress = 0.8
        scrolledBack.seed(spine: 0, fraction: 0.5)
        scrolledBack.persist(scrolledBack.beginChapter(spine: 0), to: backWork, resourceLengths: lengths)
        scrolledBack.recordProgress(0) // page 1, before readerRestore
        scrolledBack.recordProgress(0.5) // the restored page
        writeSettled(scrolledBack, to: backWork, lengths: lengths)
        #expect(backWork.legacyReaderProgress == 0.8)

        scrolledBack.recordProgress(0)
        scrolledBack.recordProgress(0.4)
        writeSettled(scrolledBack, to: backWork, lengths: lengths)
        #expect(backWork.lastScrollFraction == 0.4)
        #expect(backWork.legacyReaderProgress == atForty)

        let repick = ReaderProgressBridge()
        let repickWork = SavedWork(title: "T", author: "A")
        repickWork.legacyReaderProgress = 0.8
        repick.seed(spine: 0, fraction: 0.5)
        repick.persist(repick.beginChapter(spine: 0), to: repickWork, resourceLengths: lengths)
        repick.recordProgress(0)
        repick.recordProgress(0.5)
        writeSettled(repick, to: repickWork, lengths: lengths)
        #expect(repickWork.legacyReaderProgress == 0.8)

        repick.forget(spine: 0)
        repick.persist(repick.beginChapter(spine: 0), to: repickWork, resourceLengths: lengths)
        repick.recordProgress(0) // re-pick reloads at the top; no readerRestore
        repick.recordProgress(0.4)
        writeSettled(repick, to: repickWork, lengths: lengths)
        #expect(repickWork.lastScrollFraction == 0.4)
        #expect(repickWork.legacyReaderProgress == atForty)
    }

    @Test func aLaterChapterLoadClaimsThePercent() {
        let bridge = ReaderProgressBridge()
        let work = SavedWork(title: "T", author: "A")
        bridge.persist(bridge.beginChapter(spine: 0), to: work, resourceLengths: Self.lengths)
        #expect(work.legacyReaderProgress == nil)
        bridge.persist(bridge.beginChapter(spine: 1), to: work, resourceLengths: Self.lengths)
        #expect(work.legacyReaderProgress == 0.5)
    }

    @Test func progressBeforeAnyChapterIsIgnored() {
        let bridge = ReaderProgressBridge()
        bridge.recordProgress(0.9)
        #expect(bridge.fractionForFlush() == nil)
        #expect(bridge.fractionForDebouncedWrite() == nil)
    }

    private func writeSettled(_ bridge: ReaderProgressBridge, to work: SavedWork, lengths: [Int?]) {
        if let due = bridge.fractionForDebouncedWrite(at: .distantFuture) {
            bridge.persist(due, to: work, resourceLengths: lengths)
        }
        if let flush = bridge.fractionForFlush() {
            bridge.persist(flush, to: work, resourceLengths: lengths)
        }
    }
}
