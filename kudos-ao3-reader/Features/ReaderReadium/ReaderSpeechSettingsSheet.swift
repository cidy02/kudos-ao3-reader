#if os(iOS)
import SwiftUI

/// Read-aloud settings reachable from the reader itself, without leaving the
/// book for Settings.
///
/// Wraps the same `ReaderSpeechSettingsSection` the Settings screen renders
/// rather than a reader-specific copy — the voice, speed, engine and pack
/// controls are the *same* preferences, and a second surface that drifts from
/// the first is worse than no second surface. It carries the audition harness
/// with it, so a setting can be changed and heard without closing the sheet.
struct ReaderSpeechSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                ReaderSpeechSettingsSection()
            }
            .navigationTitle("Read Aloud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // Medium first so the book stays partly visible — this is a tweak-while-
        // listening surface, not a destination. Large is there because the
        // section is long once a pack is installed.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
#endif
