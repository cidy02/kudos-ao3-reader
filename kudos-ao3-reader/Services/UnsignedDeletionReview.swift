import Foundation
import Observation
import SwiftData

/// D8 notify-on-use + anomaly hold. Populated by `KudosBackupService.restore`
/// after a successful merge; `ContentView` presents the review sheet / digest.
@MainActor
@Observable
final class UnsignedDeletionReview {
    static let shared = UnsignedDeletionReview()

    struct Hold: Equatable, Identifiable {
        let id = UUID()
        var titles: [String]
        var workIDs: [UUID]
        var sourceLabel: String

        var count: Int { titles.count }
    }

    var pendingHold: Hold?
    var pendingDigest: String?

    static func record(_ summary: KudosBackupRestoreSummary, source: String) {
        if summary.unsignedHidesHeld >= KudosBackupService.unsignedHideHoldFloor {
            shared.pendingHold = Hold(
                titles: summary.unsignedHideTitles,
                workIDs: summary.heldUnsignedHideWorkIDs,
                sourceLabel: source
            )
            shared.pendingDigest = nil
        } else if summary.unsignedHidesApplied > 0 {
            let applied = summary.unsignedHidesApplied
            shared.pendingDigest =
                "\(applied) work\(applied == 1 ? "" : "s") moved to Recently Deleted by \(source)."
            shared.pendingHold = nil
        }
    }

    func dismissHold() {
        pendingHold = nil
    }

    func dismissDigest() {
        pendingDigest = nil
    }

    func confirmHold(in context: ModelContext) {
        guard let hold = pendingHold else { return }
        KudosBackupService.applyHeldUnsignedHides(workIDs: hold.workIDs, in: context)
        pendingHold = nil
    }

    /// Tests reset the singleton so suites don't leak hold state.
    func resetForTests() {
        pendingHold = nil
        pendingDigest = nil
    }
}
