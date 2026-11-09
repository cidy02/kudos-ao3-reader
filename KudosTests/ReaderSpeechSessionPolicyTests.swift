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
        #expect(!throttle.shouldSave(locatorString: "one", for: .spokenRange))
        #expect(throttle.shouldSave(locatorString: "one", for: .utteranceBoundary))
        #expect(!throttle.shouldSave(locatorString: "one", for: .utteranceBoundary))
        #expect(throttle.shouldSave(locatorString: "one", for: .pause))
        #expect(throttle.shouldSave(locatorString: "one", for: .stop))
        #expect(throttle.shouldSave(locatorString: "one", for: .sessionEnd))
        #expect(throttle.shouldSave(locatorString: "one", for: .appBackground))
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
