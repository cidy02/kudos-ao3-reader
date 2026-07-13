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

    @Test func progressBeforeAnyChapterIsIgnored() {
        let bridge = ReaderProgressBridge()
        bridge.recordProgress(0.9)
        #expect(bridge.fractionForFlush() == nil)
        #expect(bridge.fractionForDebouncedWrite() == nil)
    }
}
