import SwiftUI

/// Renders each entry in `items` (front to back) as its own Liquid Glass
/// toolbar pill.
///
/// iOS 26 auto-merges every adjacent item in the same placement into one
/// shared glass pill regardless of `ToolbarItem` vs `ToolbarItemGroup` and
/// regardless of each item's own `.tint()` — confirmed against a live device
/// (both were tried here first and neither split the group). The only real
/// separator is `ToolbarSpacer(.fixed)` placed *between* items — see
/// https://developer.apple.com/forums/thread/788446.
///
/// Not a `ForEach` over `items`: `ForEach` inside a `@ToolbarContentBuilder`
/// requires its per-row content to conform to `CustomizableToolbarContent`,
/// which a conditional `ToolbarSpacer` + `ToolbarItem` pair doesn't (confirmed
/// by a real build failure) — so this unrolls 5 fixed optional slots by hand
/// instead (the widest call site, AccountInboxViews, uses up to 5), each
/// gated by plain `if` (which `@ToolbarContentBuilder` does support,
/// mirroring `@ViewBuilder`).
struct ActionToolbar: ToolbarContent {
    var items: [AnyView]

    var body: some ToolbarContent {
        if !items.isEmpty {
            ToolbarItem(placement: .primaryAction) { items[0].labelStyle(.iconOnly) }
        }
        if items.count > 1 {
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) { items[1].labelStyle(.iconOnly) }
        }
        if items.count > 2 {
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) { items[2].labelStyle(.iconOnly) }
        }
        if items.count > 3 {
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) { items[3].labelStyle(.iconOnly) }
        }
        if items.count > 4 {
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) { items[4].labelStyle(.iconOnly) }
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
