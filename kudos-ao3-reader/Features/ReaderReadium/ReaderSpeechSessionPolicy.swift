#if os(iOS)
import Foundation

/// Pure app/reader lifetime rules for a read-aloud session.
nonisolated enum ReaderSpeechSessionPolicy {
    enum LeaveReaderAction: Equatable {
        case detach
        case tearDown
    }

    enum OpenReaderAction: Equatable {
        case prepare
        case reattach
        case endPreviousSession
    }

    enum DetachedSaveDecision: Equatable {
        case write
        case endSession
        case suspendWrites
    }

    static func leaveReader(sessionActive: Bool) -> LeaveReaderAction {
        sessionActive ? .detach : .tearDown
    }

    static func openReader(
        sessionActive: Bool,
        sessionWorkID: UUID?,
        openingWorkID: UUID
    ) -> OpenReaderAction {
        guard sessionActive else { return .prepare }
        return sessionWorkID == openingWorkID ? .reattach : .endPreviousSession
    }

    static func showsMiniPlayer(sessionActive: Bool, readerOpen: Bool) -> Bool {
        sessionActive && !readerOpen
    }

    static func showsMiniPlayer(
        sessionActive: Bool,
        readerOpen: Bool,
        commentAccessoryTab: AppTab?,
        selectedTab: AppTab
    ) -> Bool {
        showsMiniPlayer(sessionActive: sessionActive, readerOpen: readerOpen)
            && commentAccessoryTab != selectedTab
    }

    static func detachedSaveDecision(
        isPendingDeletion: Bool,
        workProgressStamp: Date?,
        sessionProgressStamp: Date
    ) -> DetachedSaveDecision {
        if isPendingDeletion { return .endSession }
        if let workProgressStamp, workProgressStamp > sessionProgressStamp {
            return .suspendWrites
        }
        return .write
    }

    static func canFreeEPUB(
        workID: UUID,
        sessionActive: Bool,
        sessionWorkID: UUID?
    ) -> Bool {
        !sessionActive || sessionWorkID != workID
    }
}

nonisolated enum ReaderSpeechPositionSaveResult: Equatable {
    case wrote(progressStamp: Date)
    case endSession
    case suspendWrites
}

/// Saves at speech boundaries and lifecycle checkpoints, never for every
/// word-range callback. Repeated reports of the same boundary are coalesced.
nonisolated struct ReaderSpeechPositionSaveThrottle {
    enum Event: Equatable {
        case utteranceBoundary
        case spokenRange
        case pause
        case stop
        case sessionEnd
        case appBackground

        var stampsShelf: Bool {
            switch self {
            case .utteranceBoundary, .spokenRange:
                false
            case .pause, .stop, .sessionEnd, .appBackground:
                true
            }
        }
    }

    private var lastBoundaryLocator: String?
    private var hasSavedDetachedProgress = false

    mutating func shouldSave(locatorString: String?, for event: Event) -> Bool {
        guard let locatorString, !locatorString.isEmpty else { return false }
        switch event {
        case .spokenRange:
            return false
        case .utteranceBoundary:
            guard locatorString != lastBoundaryLocator else { return false }
            lastBoundaryLocator = locatorString
            return true
        case .pause, .stop, .sessionEnd, .appBackground:
            guard hasSavedDetachedProgress else { return false }
            lastBoundaryLocator = locatorString
            return true
        }
    }

    mutating func didSave(for event: Event) {
        if event == .utteranceBoundary {
            hasSavedDetachedProgress = true
        }
    }

    mutating func reset() {
        lastBoundaryLocator = nil
        hasSavedDetachedProgress = false
    }
}
#endif
