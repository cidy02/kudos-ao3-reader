import SwiftUI

/// Formalizes the `ToolbarItem(.primaryAction) { HStack(spacing: 2) { ... }.labelStyle(.iconOnly) }`
/// pattern repeated across the app, so adjacent icon buttons/menus sit tight instead of inheriting
/// the system's wide inter-item toolbar spacing.
struct ActionToolbar<Content: View>: ToolbarContent {
    @ViewBuilder var content: () -> Content

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 2) {
                content()
            }
            .labelStyle(.iconOnly)
        }
    }
}

/// A single icon-only toolbar action with a required accessible title, since `.labelStyle(.iconOnly)`
/// only hides the label visually — VoiceOver still needs it, so a bare `Image(systemName:)` isn't enough.
struct ToolbarIconButton: View {
    var title: String
    var systemImage: String
    var role: ButtonRole? = nil
    var tint: Color? = nil
    var isDisabled: Bool = false
    var help: String? = nil
    var action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
        }
        .tint(tint)
        .disabled(isDisabled)
        .help(help ?? title)
    }
}
