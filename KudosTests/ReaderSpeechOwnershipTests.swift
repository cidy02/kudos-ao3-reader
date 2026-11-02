import Testing
@testable import Kudos

@MainActor
private final class StubSpeaker: SpeechStoppable {
    var stops = 0
    func stop() { stops += 1 }
}

@Suite("Read Aloud auto-start and single speech owner")
@MainActor
struct ReaderSpeechOwnershipTests {
    @Test func startsOnceOnFirstSettledLocation() {
        var gate = ReadAloudAutoStart()
        // `.ready` alone (seeded locator, no navigator settle yet) never starts.
        let fired1 = gate.shouldStart(requested: true, isReady: true, settledCount: 0)
        #expect(!fired1)
        let fired2 = gate.shouldStart(requested: true, isReady: true, settledCount: 1)
        #expect(fired2)
        // Later ready/location events don't restart.
        let fired3 = gate.shouldStart(requested: true, isReady: true, settledCount: 2)
        #expect(!fired3)
        let fired4 = gate.shouldStart(requested: true, isReady: true, settledCount: 1)
        #expect(!fired4)
    }

    @Test func notRequestedOrNotReadyNeverStarts() {
        var gate = ReadAloudAutoStart()
        let fired5 = gate.shouldStart(requested: false, isReady: true, settledCount: 1)
        #expect(!fired5)
        let fired6 = gate.shouldStart(requested: true, isReady: false, settledCount: 1)
        #expect(!fired6)
        // Neither consumed the one-shot.
        let fired7 = gate.shouldStart(requested: true, isReady: true, settledCount: 1)
        #expect(fired7)
    }

    @Test func secondOwnerStopsFirst() {
        let registry = SpeechOwnerRegistry()
        let a = StubSpeaker(), b = StubSpeaker()
        registry.claim(a)
        registry.claim(a) // re-claim by the owner must not stop itself
        #expect(a.stops == 0)
        registry.claim(b)
        #expect(a.stops == 1)
        #expect(b.stops == 0)
        registry.release(a) // stale release is ignored
        #expect(registry.owner === b)
        registry.release(b)
        #expect(registry.owner == nil)
    }
}
