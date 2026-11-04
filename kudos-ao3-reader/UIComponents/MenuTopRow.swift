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

    /// Library toggles in a top row: a short title under the icon, "on" shown by the
    /// filled symbol, the full action for VoiceOver ("Remove from Want to Read" does not
    /// fit under an icon).
    struct Toggle: Equatable, Sendable {
        let title: String
        let systemImage: String
        let accessibilityLabel: String
    }

    static func wantToRead(isQueued: Bool) -> Toggle {
        Toggle(title: "Want to Read", systemImage: isQueued ? "clock.fill" : "clock",
               accessibilityLabel: isQueued ? "Remove from Want to Read" : "Want to Read")
    }

    static func favorite(isFavorite: Bool) -> Toggle {
        Toggle(title: "Favorite", systemImage: isFavorite ? "star.fill" : "star",
               accessibilityLabel: isFavorite ? "Unfavorite" : "Favorite")
    }

    static func finished(isFinished: Bool) -> Toggle {
        Toggle(title: "Finished", systemImage: isFinished ? "checkmark.circle.fill" : "checkmark.circle",
               accessibilityLabel: isFinished ? "Mark as Still Reading" : "Mark as Finished")
    }
}
