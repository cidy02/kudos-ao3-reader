import SwiftUI

/// How `AO3FilterPanel` is presented: an inspector in regular/regular iOS layouts
/// and on macOS, a sheet in other iOS layouts.
///
/// **Why compact layouts need a real sheet.** An inspector's content is part of
/// the *same* view tree as the screen it is attached to. In compact layouts there is no room
/// for a side panel, so it collapses into something that looks like a sheet — but it
/// is not a separate presentation context. A `NavigationStack` inside it therefore
/// lands inside the tab's own stack, and SwiftUI stops matching that stack's
/// `navigationDestination` declarations against links in it:
///
///     A NavigationLink is presenting a value of type "AO3MediaCategory" but there
///     is no matching navigationDestination declaration visible from the location
///     of the link. The link cannot be activated.
///
/// That is what broke Browse → any category when the panel gained a navigation bar
/// for its Apply/Reset buttons — on a screen the panel is not even attached to.
///
/// A real `.sheet` *is* a separate presentation context, which is why `CommentsView`
/// has wrapped itself in a `NavigationStack` since forever with no such effect.
/// Verified both directions in the simulator: same panel, same navigation stack —
/// inspector breaks the category link, sheet does not.
///
/// The compact fallback also applies to narrow iPad multitasking windows. Use
/// this view's size classes so a regular/regular phone display can use a sidebar.
private struct FilterPanelPresentation<Panel: View>: ViewModifier {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    @Binding var isPresented: Bool
    /// The compact layout's sheet detents; nil keeps the sheet's own full height.
    var detents: Set<PresentationDetent>?
    @ViewBuilder var panel: () -> Panel

    func body(content: Content) -> some View {
        #if os(iOS)
        if WideLayout.isAvailable(horizontal: horizontalSizeClass, vertical: verticalSizeClass) {
            content.inspector(isPresented: $isPresented) { panel() }
        } else {
            content.sheet(isPresented: $isPresented) {
                panel()
                    // The panel supplies its own navigation bar; the grabber sits
                    // above it, so the sheet still reads as swipe-to-dismiss.
                    .presentationDragIndicator(.visible)
                    // `[.large]` is what a sheet does when given no detents.
                    .presentationDetents(detents ?? [.large])
            }
        }
        #else
        content.inspector(isPresented: $isPresented) { panel() }
        #endif
    }
}

extension View {
    /// Presents the AO3 filter panel — see `FilterPanelPresentation` for why compact
    /// layouts need a sheet rather than a collapsed inspector.
    /// `detents` applies to the compact sheet only: the AO3 search panel passes
    /// `[.medium, .large]`, spec 1ao's "opens over the results at half height".
    func filterPanelPresentation(
        isPresented: Binding<Bool>,
        detents: Set<PresentationDetent>? = nil,
        @ViewBuilder panel: @escaping () -> some View
    ) -> some View {
        modifier(FilterPanelPresentation(isPresented: isPresented, detents: detents, panel: panel))
    }
}
