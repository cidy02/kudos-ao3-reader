import SwiftUI

extension View {
    /// A destructive confirmation alert for a pending `SavedWork` deletion, driven
    /// by an optional binding (non-nil = ask). Shared by the Library and History
    /// swipe-to-delete so both confirm the same way, gated by `confirmBeforeDelete`.
    func deleteConfirmation(
        for item: Binding<SavedWork?>,
        title: String,
        confirmLabel: String,
        message: @escaping (SavedWork) -> String,
        perform: @escaping (SavedWork) -> Void
    ) -> some View {
        alert(
            title,
            isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } }
            ),
            presenting: item.wrappedValue
        ) { work in
            Button(confirmLabel, role: .destructive) {
                perform(work)
                item.wrappedValue = nil
            }
            Button("Cancel", role: .cancel) { item.wrappedValue = nil }
        } message: { work in
            Text(message(work))
        }
    }
}

/// How a `destructiveConfirmation` presents itself. Both render the identical
/// shape — a `role: .destructive` confirm button, a `role: .cancel` Cancel, and
/// consequence text in `message` — so the choice is about context, not voice:
/// `.alert` for one concrete item reached via swipe or a context menu; `.dialog`
/// for a count-based bulk action or a menu-triggered flow (matches the bulk-delete
/// action-sheet idiom already used by `WorkBulkActionBar`).
enum DestructiveConfirmationStyle {
    case alert
    case dialog
}

extension View {
    /// The app's shared destructive-confirmation idiom, item-driven: presented
    /// whenever `item` is non-nil, dismissed (and `item` cleared) on either button.
    /// Generalizes `deleteConfirmation(for:title:confirmLabel:message:perform:)` to
    /// any item type and either presentation style. Callers keep owning the "ask at
    /// all?" decision (e.g. `confirmBeforeDelete`) by choosing whether to set `item`
    /// in the first place; this modifier only renders the ask once asked.
    func destructiveConfirmation<Item>(
        for item: Binding<Item?>,
        style: DestructiveConfirmationStyle = .alert,
        title: String,
        confirmLabel: String = "Delete",
        message: @escaping (Item) -> String,
        perform: @escaping (Item) -> Void
    ) -> some View {
        let isPresented = Binding(
            get: { item.wrappedValue != nil },
            set: { if !$0 { item.wrappedValue = nil } }
        )
        return Group {
            switch style {
            case .alert:
                self.alert(title, isPresented: isPresented, presenting: item.wrappedValue) { value in
                    Button(confirmLabel, role: .destructive) {
                        perform(value)
                        item.wrappedValue = nil
                    }
                    Button("Cancel", role: .cancel) { item.wrappedValue = nil }
                } message: { value in
                    Text(message(value))
                }
            case .dialog:
                self.confirmationDialog(
                    title, isPresented: isPresented, titleVisibility: .visible,
                    presenting: item.wrappedValue
                ) { value in
                    Button(confirmLabel, role: .destructive) {
                        perform(value)
                        item.wrappedValue = nil
                    }
                    Button("Cancel", role: .cancel) { item.wrappedValue = nil }
                } message: { value in
                    Text(message(value))
                }
            }
        }
    }

    /// The same idiom keyed by a plain `Bool` instead of an optional item — for a
    /// fixed action with no per-item payload: bulk-action bars, "Delete Collection",
    /// "Reset Filters". Defaults to `.dialog` since these tend to carry a dynamic,
    /// count-based title.
    func destructiveConfirmation(
        isPresented: Binding<Bool>,
        style: DestructiveConfirmationStyle = .dialog,
        title: String,
        confirmLabel: String = "Delete",
        message: String,
        perform: @escaping () -> Void
    ) -> some View {
        Group {
            switch style {
            case .alert:
                self.alert(title, isPresented: isPresented) {
                    Button(confirmLabel, role: .destructive, action: perform)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(message)
                }
            case .dialog:
                self.confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {
                    Button(confirmLabel, role: .destructive, action: perform)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(message)
                }
            }
        }
    }
}
