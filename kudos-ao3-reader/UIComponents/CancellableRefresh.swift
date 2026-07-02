import SwiftUI

/// Wraps a `.refreshable` action in an explicitly tracked `Task` and cancels it when
/// the active tab changes. `TabView` keeps every tab's view hierarchy (and thus its
/// `.refreshable` task) alive when the user switches away, so a pull-to-refresh over
/// a large list — a full Library section, a Collection, a Reading Queue, or the whole
/// Library in select mode — would otherwise keep firing sequential AO3 requests
/// invisibly in the background after the user has moved to a different tab. Cheap for
/// the common case (the task finishes before any tab switch, so this never fires).
private struct CancelRefreshOnTabChangeModifier: ViewModifier {
    @Environment(AppRouter.self) private var router
    @Binding var refreshTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content.onChange(of: router.selection) { _, _ in
            refreshTask?.cancel()
        }
    }
}

extension View {
    /// Cancels `refreshTask` (the task started by a `.refreshable` closure) when the
    /// active tab changes, so a large refresh doesn't keep running after the user
    /// navigates away. Pair with `Task { ... }.store(in: &refreshTask)`-style tracking
    /// in the `.refreshable` closure itself.
    func cancelRefreshOnTabChange(_ refreshTask: Binding<Task<Void, Never>?>) -> some View {
        modifier(CancelRefreshOnTabChangeModifier(refreshTask: refreshTask))
    }
}
