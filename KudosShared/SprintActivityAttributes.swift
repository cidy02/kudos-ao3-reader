#if os(iOS)
import ActivityKit
import Foundation

/// The sprint Live Activity (T-576e, `Phone-Sprint.dc.html`): the time left and the words written, on the Lock Screen
/// and in the Dynamic Island. Numbers only, never the chapter's text.
nonisolated struct SprintActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        var words: Int
        var endsAt: Date
        var isFinished: Bool
    }

    var startedAt: Date
    var plannedMinutes: Int
}
#endif
