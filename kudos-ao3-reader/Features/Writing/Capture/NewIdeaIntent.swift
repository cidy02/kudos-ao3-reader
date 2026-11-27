import AppIntents
import Foundation
import Observation

/// Hand-off from the "New Idea" App Intent to the UI (T-576e). `ContentView` watches `isPresenting`
/// and shows `NewIdeaSheet` over whatever is on screen. No URL scheme: a widget or Control Center
/// control added later only has to run `NewIdeaIntent`.
@MainActor @Observable
final class NewIdeaRequest {
    static let shared = NewIdeaRequest()

    var isPresenting = false
    /// Set by the sheet while it is on screen.
    var isShowing = false
    private(set) var requestID = 0

    init() {}

    func request() {
        requestID &+= 1
        if isPresenting && !isShowing {
            // The last request never showed (SwiftUI shows one sheet at a time and another was up): ask again from
            // scratch rather than stay stuck. A sheet already open, text and all, is left alone.
            isPresenting = false
            Task { @MainActor in self.isPresenting = true }
        } else {
            isPresenting = true
        }
    }
}

/// "New Idea" in Shortcuts, Spotlight and Siri, and on the Action button (Settings → Action Button →
/// Shortcut). Opens the app straight to the New Idea sheet.
nonisolated struct NewIdeaIntent: AppIntent {
    static let title: LocalizedStringResource = "New Idea"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NewIdeaRequest.shared.request()
        return .result()
    }
}

nonisolated struct KudosShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewIdeaIntent(),
            phrases: [
                "New idea in \(.applicationName)",
                "Capture an idea in \(.applicationName)",
            ],
            shortTitle: "New Idea",
            systemImageName: "lightbulb"
        )
    }
}
