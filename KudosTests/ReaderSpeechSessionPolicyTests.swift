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
            sessionActive: false,
            sessionWorkID: nil,
            openingWorkID: firstWorkID
        ) == .prepare)
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

    @Test func commentAccessoryOnlyHidesSpeechOnItsSelectedTab() {
        #expect(!ReaderSpeechSessionPolicy.showsMiniPlayer(
            sessionActive: true,
            readerOpen: false,
            commentAccessoryTab: .library,
            selectedTab: .library
        ))
        #expect(ReaderSpeechSessionPolicy.showsMiniPlayer(
            sessionActive: true,
            readerOpen: false,
            commentAccessoryTab: .library,
            selectedTab: .home
        ))
    }

    @Test func checkpointsRequireSuccessfullySavedDetachedProgress() {
        var throttle = ReaderSpeechPositionSaveThrottle()
        let spokenRange = throttle.shouldSave(locatorString: "one", for: .spokenRange)
        let beforeBoundary = throttle.shouldSave(locatorString: "one", for: .pause)
        let boundary = throttle.shouldSave(locatorString: "two", for: .utteranceBoundary)
        let repeatedBoundary = throttle.shouldSave(locatorString: "two", for: .utteranceBoundary)
        let beforeSuccessfulSave = throttle.shouldSave(locatorString: "two", for: .stop)
        throttle.didSave(for: .utteranceBoundary)
        let afterSuccessfulSave = throttle.shouldSave(locatorString: "two", for: .appBackground)
        #expect(!spokenRange)
        #expect(!beforeBoundary)
        #expect(boundary)
        #expect(!repeatedBoundary)
        #expect(!beforeSuccessfulSave)
        #expect(afterSuccessfulSave)
    }

    @Test func detachedSaverProtectsDeletedAndNewerProgress() {
        let baseline = Date(timeIntervalSince1970: 100)
        #expect(ReaderSpeechSessionPolicy.detachedSaveDecision(
            isPendingDeletion: true,
            workProgressStamp: nil,
            sessionProgressStamp: baseline
        ) == .endSession)
        #expect(ReaderSpeechSessionPolicy.detachedSaveDecision(
            isPendingDeletion: false,
            workProgressStamp: baseline.addingTimeInterval(1),
            sessionProgressStamp: baseline
        ) == .suspendWrites)
        #expect(ReaderSpeechSessionPolicy.detachedSaveDecision(
            isPendingDeletion: false,
            workProgressStamp: baseline,
            sessionProgressStamp: baseline
        ) == .write)
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
