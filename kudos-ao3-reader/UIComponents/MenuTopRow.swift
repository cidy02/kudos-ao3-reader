import SwiftUI

/// The top row of a menu: up to four labelled icons for the most frequent,
/// non-destructive actions. A toggle that is on draws filled.
/// Share, when present, goes last. Everything else stays a row below,
/// and Delete is the last row, in red.
///
/// Built using native `ControlGroup` per spec boards 20, 25, 27 and component
/// `Menu top row`.
public struct MenuTopRow<Content: View>: View {
    @ViewBuilder private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        ControlGroup {
            content
        }
    }
}

/// Pure logic validation and constants for menu top rows.
public enum MenuTopRowRules: Sendable {
    /// Up to 4 items in the top row per design rules.
    public static let maxItems = 4

    /// Validates whether an item count is allowed for a MenuTopRow.
    public static func isValidCount(_ count: Int) -> Bool {
        count >= 1 && count <= maxItems
    }

    /// Symbol name for Kudos button given toggle state.
    public static func kudosSymbol(isGiven: Bool) -> String {
        isGiven ? "heart.fill" : "heart"
    }

    /// Symbol name for Bookmark button given bookmarked state.
    public static func bookmarkSymbol(isBookmarked: Bool) -> String {
        isBookmarked ? "bookmark.fill" : "bookmark"
    }

    /// Symbol name for Subscribe button given subscribed state.
    public static func subscribeSymbol(isSubscribed: Bool) -> String {
        isSubscribed ? "bell.fill" : "bell"
    }

    /// Symbol name for Read Aloud button given active state.
    public static func readAloudSymbol(isActive: Bool) -> String {
        isActive ? "waveform.circle.fill" : "waveform"
    }
}
