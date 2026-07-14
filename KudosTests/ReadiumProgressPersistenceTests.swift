import Foundation
import Testing
@testable import Kudos

/// Debounced Readium locator persistence (scrolled-mode hang fix / T-98).
/// Mirrors the guarantees of `ReaderProgressBridgeTests` for the iOS path:
/// interval gating, progression-delta noise filter, trailing write, and flush
/// that always bypasses the window.
@MainActor
struct ReadiumProgressPersistenceTests {

    private func persistence() -> ReadiumProgressPersistence {
        ReadiumProgressPersistence()
    }

    private func locator(total: Double, href: String = "chapter1.xhtml") -> String {
        #"{"href":"\#(href)","type":"application/xhtml+xml","locations":{"totalProgression":\#(total),"progression":\#(total),"position":5}}"#
    }

    // MARK: Debounce window

    @Test func streamedUpdatesAreDebounced() {
        let bridge = persistence()
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var writes: [String] = []
        bridge.onDebouncedWrite = { writes.append($0) }
        bridge.seed(persistedLocatorString: locator(total: 0))
        // Seed does not count as a persist timestamp — first real note may write.
        bridge.markPersisted(locatorString: locator(total: 0), totalProgression: 0, at: start)

        let mid = locator(total: 0.2)
        bridge.note(locatorString: mid, totalProgression: 0.2, at: start.addingTimeInterval(0.5))
        #expect(writes.isEmpty)
        #expect(bridge.locatorForDebouncedWrite(at: start.addingTimeInterval(0.5)) == nil)

        // Window elapsed: latest value is eligible.
        #expect(bridge.locatorForDebouncedWrite(at: start.addingTimeInterval(2.5)) == mid)
    }

    @Test func noteEmitsWhenWindowElapsed() {
        let bridge = persistence()
        let start = Date(timeIntervalSinceReferenceDate: 2_000)
        var writes: [String] = []
        bridge.onDebouncedWrite = { writes.append($0) }
        bridge.markPersisted(locatorString: locator(total: 0.1), totalProgression: 0.1, at: start)

        let next = locator(total: 0.4)
        bridge.note(locatorString: next, totalProgression: 0.4, at: start.addingTimeInterval(2.1))
        #expect(writes == [next])
        #expect(bridge.locatorForFlush() == nil) // already marked persisted
    }

    @Test func progressionNoiseBelowThresholdIsNeverWritten() {
        let bridge = persistence()
        let start = Date(timeIntervalSinceReferenceDate: 3_000)
        var writes: [String] = []
        bridge.onDebouncedWrite = { writes.append($0) }
        bridge.markPersisted(locatorString: locator(total: 0.5), totalProgression: 0.5, at: start)

        // Sub-threshold jitter after the window — still no write.
        let noisy = locator(total: 0.5004)
        bridge.note(locatorString: noisy, totalProgression: 0.5004, at: start.addingTimeInterval(10))
        #expect(writes.isEmpty)
        #expect(bridge.locatorForDebouncedWrite(at: start.addingTimeInterval(10)) == nil)
    }

    @Test func progressionPastThresholdIsWrittenAfterInterval() {
        let bridge = persistence()
        let start = Date(timeIntervalSinceReferenceDate: 4_000)
        var writes: [String] = []
        bridge.onDebouncedWrite = { writes.append($0) }
        bridge.markPersisted(locatorString: locator(total: 0.5), totalProgression: 0.5, at: start)

        let moved = locator(total: 0.52)
        bridge.note(locatorString: moved, totalProgression: 0.52, at: start.addingTimeInterval(2.5))
        #expect(writes == [moved])
    }

    // MARK: Flush

    @Test func flushBypassesTheDebounceWindow() {
        let bridge = persistence()
        let start = Date(timeIntervalSinceReferenceDate: 5_000)
        bridge.markPersisted(locatorString: locator(total: 0), totalProgression: 0, at: start)

        let mid = locator(total: 0.42)
        bridge.record(locatorString: mid, totalProgression: 0.42)
        // Window still open for debounced writes…
        #expect(bridge.locatorForDebouncedWrite(at: start.addingTimeInterval(0.2)) == nil)
        // …but flush always returns the latest.
        #expect(bridge.locatorForFlush() == mid)
        bridge.markPersisted(locatorString: mid, totalProgression: 0.42, at: start.addingTimeInterval(0.2))
        #expect(bridge.locatorForFlush() == nil)
    }

    @Test func flushIsNilWhenNothingChanged() {
        let bridge = persistence()
        let s = locator(total: 0.3)
        bridge.seed(persistedLocatorString: s)
        bridge.markPersisted(locatorString: s, totalProgression: 0.3)
        #expect(bridge.locatorForFlush() == nil)
        #expect(bridge.hasSessionPosition)
    }

    @Test func emptyLocatorIsIgnored() {
        let bridge = persistence()
        bridge.note(locatorString: "", totalProgression: 0.5)
        #expect(bridge.latestLocatorString == nil)
        #expect(bridge.locatorForFlush() == nil)
    }

    // MARK: Seed

    @Test func seedPreventsRewriteOfIdenticalOpenLocator() {
        let bridge = persistence()
        var writes: [String] = []
        bridge.onDebouncedWrite = { writes.append($0) }
        let s = locator(total: 0.25)
        bridge.seed(persistedLocatorString: s)
        // Same string + same progression after open should not write (no prior persist time
        // means interval is open, but progression vs lastPersistedProgression is nil/nil —
        // after seed, lastPersistedProgression is nil so string equality gates).
        bridge.record(locatorString: s, totalProgression: 0.25)
        // Without a prior markPersisted progression, string equality: same as seed → no change
        // once we also mark progression. Simulate post-open baseline fully:
        bridge.markPersisted(locatorString: s, totalProgression: 0.25, at: Date())
        bridge.note(locatorString: s, totalProgression: 0.25, at: Date().addingTimeInterval(5))
        #expect(writes.isEmpty)
    }

    // MARK: SavedWork stamp split

    @Test func debouncedLocatorDoesNotThrashLastReadDateOrLastModified() {
        let work = SavedWork(title: "T", author: "A")
        let opened = Date(timeIntervalSince1970: 1_000)
        work.markProgressModified(opened)
        let lastRead = work.lastReadDate
        let lastMod = work.lastModifiedAt

        let later = Date(timeIntervalSince1970: 1_100)
        work.applyDebouncedReadiumLocator(locator(total: 0.6), at: later)

        #expect(work.readiumLocator == locator(total: 0.6))
        #expect(work.progressModifiedAt == later)
        #expect(work.lastReadDate == lastRead)
        #expect(work.lastModifiedAt == lastMod)
    }

    @Test func fullProgressStampUpdatesShelfAndSyncFields() {
        let work = SavedWork(title: "T", author: "A")
        let t = Date(timeIntervalSince1970: 2_000)
        work.markProgressModified(t)
        #expect(work.lastReadDate == t)
        #expect(work.progressModifiedAt == t)
        #expect(work.lastModifiedAt == t)
    }

    // MARK: Trailing-write gating

    @Test func noiseDoesNotArmATrailingWrite() async {
        // A noise-only note after a real persist must not schedule a trailing
        // emit (and must leave the last-persisted baseline alone).
        let bridge = persistence()
        let start = Date(timeIntervalSinceReferenceDate: 6_000)
        var writes: [String] = []
        bridge.onDebouncedWrite = { writes.append($0) }
        bridge.markPersisted(locatorString: locator(total: 0.5), totalProgression: 0.5, at: start)

        bridge.note(locatorString: locator(total: 0.5004), totalProgression: 0.5004,
                    at: start.addingTimeInterval(0.1))
        // Wait past the debounce window; noise must still not emit.
        try? await Task.sleep(nanoseconds: 2_200_000_000)
        #expect(writes.isEmpty)
    }

    @Test func meaningfulChangeInsideWindowArmsTrailingWrite() async {
        let bridge = persistence()
        let start = Date(timeIntervalSinceReferenceDate: 7_000)
        var writes: [String] = []
        bridge.onDebouncedWrite = { writes.append($0) }
        bridge.markPersisted(locatorString: locator(total: 0.1), totalProgression: 0.1, at: start)

        let moved = locator(total: 0.35)
        bridge.note(locatorString: moved, totalProgression: 0.35, at: start.addingTimeInterval(0.2))
        #expect(writes.isEmpty) // still inside window
        try? await Task.sleep(nanoseconds: 2_200_000_000)
        #expect(writes == [moved])
    }
}
