import SwiftUI

/// Each top-level view in `content` becomes its own Liquid Glass toolbar
/// pill — `ToolbarItemGroup` (unlike a single `ToolbarItem`) splits multiple
/// children into separate, individually-glassed, system-spaced items, which
/// is what makes Filter/More/the privacy eye read as three distinct buttons
/// instead of one fused pill. A single `ToolbarItem` wrapping a manual
/// `HStack` (the previous approach here) glasses the *whole HStack* as one
/// pill no matter what each child's own `.tint()` is set to.
struct ActionToolbar<Content: View>: ToolbarContent {
    @ViewBuilder var content: () -> Content

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            content()
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
        // `.tint(_:)` is only applied when non-nil: calling it even with `nil` opts
        // this button out of the system's automatic Liquid Glass grouping with
        // adjacent untinted toolbar buttons, which otherwise share one pill — an
        // always-nil-tint button ends up rendered in its own isolated pill instead.
        if let tint {
            Button(role: role, action: action) {
                Label(title, systemImage: systemImage)
            }
            .tint(tint)
            .disabled(isDisabled)
            .help(help ?? title)
        } else {
            Button(role: role, action: action) {
                Label(title, systemImage: systemImage)
            }
            .disabled(isDisabled)
            .help(help ?? title)
        }
    }
}
