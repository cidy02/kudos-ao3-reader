import Foundation
import Testing
@testable import Kudos

@Suite("Reader speech app lifetime")
struct ReaderSpeechSessionPolicyTests {
    private let firstWorkID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let secondWorkID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    @Test func leavingDetachesOnlyAnActiveSession() {
        #expect(ReaderSpeechSessionPolicy.leaveReader(sessionActive: true) == .detach)
        #expect(ReaderSpeechSessionPolicy.leaveReader(sessionActive: false) == .tearDown)
    }

    @Test func openingReattachesOnlyTheSameWork() {
        #expect(ReaderSpeechSessionPolicy.openReader(
            sessionActive: true,
            sessionWorkID: firstWorkID,
            openingWorkID: firstWorkID
        ) == .reattach)
        #expect(ReaderSpeechSessionPolicy.openReader(
            sessionActive: true,
            sessionWorkID: firstWorkID,
            openingWorkID: secondWorkID
        ) == .endPreviousSession)
    }

    @Test func miniPlayerRequiresAnActiveDetachedSession() {
        #expect(ReaderSpeechSessionPolicy.showsMiniPlayer(sessionActive: true, readerOpen: false))
        #expect(!ReaderSpeechSessionPolicy.showsMiniPlayer(sessionActive: true, readerOpen: true))
        #expect(!ReaderSpeechSessionPolicy.showsMiniPlayer(sessionActive: false, readerOpen: false))
    }

    @Test func positionSavingIgnoresRangesButKeepsBoundariesAndCheckpoints() {
        var throttle = ReaderSpeechPositionSaveThrottle()
        let events: [ReaderSpeechPositionSaveThrottle.Event] = [
            .spokenRange, .utteranceBoundary, .utteranceBoundary,
            .pause, .stop, .sessionEnd, .appBackground
        ]
        // #expect cannot call a mutating member, so record the answers first.
        let saved = events.map { throttle.shouldSave(locatorString: "one", for: $0) }
        #expect(saved == [false, true, false, true, true, true, true])
    }

    @Test func activeSpeechProtectsOnlyItsOwnEPUB() {
        #expect(!ReaderSpeechSessionPolicy.canFreeEPUB(
            workID: firstWorkID,
            sessionActive: true,
            sessionWorkID: firstWorkID
        ))
        #expect(ReaderSpeechSessionPolicy.canFreeEPUB(
            workID: secondWorkID,
            sessionActive: true,
            sessionWorkID: firstWorkID
        ))
        #expect(ReaderSpeechSessionPolicy.canFreeEPUB(
            workID: firstWorkID,
            sessionActive: false,
            sessionWorkID: firstWorkID
        ))
    }
}
