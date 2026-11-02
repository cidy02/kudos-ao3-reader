import SwiftUI

/// The top row of a menu: up to four labelled icons for the most frequent,
/// non-destructive actions. A toggle that is on draws filled.
/// Share, when present, goes last. Everything else stays a row below,
/// and Delete is the last row, in red.
///
/// Built using native `ControlGroup` per spec boards 20, 25, 27 and component
/// `Menu top row`.
struct MenuTopRow<Content: View>: View {
    @ViewBuilder private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ControlGroup {
            content
        }
        .tint(Color.primary)
    }
}

/// Toggle symbols shared by the top-row call sites.
enum MenuTopRowRules: Sendable {
    /// Symbol name for Kudos button given toggle state.
    static func kudosSymbol(isGiven: Bool) -> String {
        isGiven ? "heart.fill" : "heart"
    }

    /// Symbol name for Bookmark button given bookmarked state.
    static func bookmarkSymbol(isBookmarked: Bool) -> String {
        isBookmarked ? "bookmark.fill" : "bookmark"
    }

    /// Symbol name for Subscribe button given subscribed state.
    static func subscribeSymbol(isSubscribed: Bool) -> String {
        isSubscribed ? "bell.fill" : "bell"
    }

    /// Symbol name for Read Aloud button given active state.
    static func readAloudSymbol(isActive: Bool) -> String {
        isActive ? "waveform.circle.fill" : "waveform"
    }
}
