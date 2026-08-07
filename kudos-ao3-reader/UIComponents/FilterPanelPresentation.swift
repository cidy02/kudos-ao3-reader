import SwiftUI

/// How `AO3FilterPanel` is presented: a sheet on iPhone, an inspector on iPad and
/// macOS where it can be a real side panel.
///
/// **Why iPhone can't just use `.inspector` too.** An inspector's content is part of
/// the *same* view tree as the screen it is attached to. On iPhone there is no room
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
/// **Per platform, not per size class.** iPad keeps the inspector even in a narrow
/// split view, where the size class goes compact but the panel is still a sidebar
/// the user can widen — the thing the inspector exists for. Only iPhone, which can
/// never show one, takes the sheet.
private struct FilterPanelPresentation<Panel: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder var panel: () -> Panel

    func body(content: Content) -> some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            content.sheet(isPresented: $isPresented) {
                panel()
                    // The panel supplies its own navigation bar; the grabber sits
                    // above it, so the sheet still reads as swipe-to-dismiss.
                    .presentationDragIndicator(.visible)
            }
        } else {
            content.inspector(isPresented: $isPresented) { panel() }
        }
        #else
        content.inspector(isPresented: $isPresented) { panel() }
        #endif
    }
}

extension View {
    /// Presents the AO3 filter panel — see `FilterPanelPresentation` for why iPhone
    /// differs, and why using `.inspector` there is not merely a styling choice.
    func filterPanelPresentation(
        isPresented: Binding<Bool>,
        @ViewBuilder panel: @escaping () -> some View
    ) -> some View {
        modifier(FilterPanelPresentation(isPresented: isPresented, panel: panel))
    }
}
