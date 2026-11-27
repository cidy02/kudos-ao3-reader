import AppIntents

/// "New Idea" (T-576e): in Shortcuts, Spotlight and Siri, on the Action button, and behind the Lock Screen widget and
/// the Control Center control. It opens the app straight to the New Idea sheet. Compiled into the app and the widget
/// extension: the extension only offers it, the app runs it.
nonisolated struct NewIdeaIntent: AppIntent {
    static let title: LocalizedStringResource = "New Idea"
    static let description = IntentDescription("Write down an idea for your story in Kudos.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !KUDOS_WIDGETS
        NewIdeaRequest.shared.request()
        #endif
        return .result()
    }
}
