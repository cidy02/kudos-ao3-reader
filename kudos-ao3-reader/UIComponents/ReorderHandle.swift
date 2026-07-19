import SwiftUI

/// The only view any drag gesture is ever attached to for manual reordering — card
/// bodies and their `.contextMenu` stay completely untouched, so press-and-hold on
/// the card always opens the context menu; only dragging this small handle reorders.
/// Shown only while a view's reorder mode is active (mutually exclusive with select
/// mode), matching `WorkSelectionBubble`'s corner placement and sizing.
struct ReorderHandleView: View {
    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .background(.regularMaterial, in: Circle())
            .accessibilityLabel("Reorder")
            // Dragging this handle isn't performable with VoiceOver — the card it sits
            // on carries the actual VoiceOver-accessible equivalent as custom actions
            // (Move Up / Move Down / Move to Top / Move to Bottom), reachable via the
            // Actions rotor while focused anywhere on the card.
            .accessibilityHint("Use the Actions rotor on this card to move it")
    }
}
