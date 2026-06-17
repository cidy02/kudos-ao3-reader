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
