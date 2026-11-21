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
    /// A width swap can remove the compact sheet without SwiftUI's dismiss callback.
    var onDismiss: (() -> Void)? = nil
    @ViewBuilder var panel: () -> Panel

    /// The inspector's content lives in the host's view tree, so a panel built while
    /// closed leaks its own navigation title and Close button into the host's toolbar
    /// (Library and Search read "Filters" with a stray ✕, T-562c N1). Build it only
    /// while presented.
    @ViewBuilder private var inspectorPanel: some View {
        if isPresented { panel() }
    }

    func body(content: Content) -> some View {
        #if os(iOS)
        let wide = WideLayout.isAvailable(
            horizontal: horizontalSizeClass, vertical: verticalSizeClass
        )
        return Group {
            if wide {
                content.inspector(isPresented: $isPresented) {
                    inspectorPanel.environment(\.filterPanelInInspector, true)
                }
                    .onChange(of: isPresented) { _, presented in
                        if !presented { onDismiss?() }
                    }
            } else {
                content.sheet(isPresented: $isPresented, onDismiss: onDismiss) {
                    panel()
                        // The panel supplies its own navigation bar; the grabber sits
                        // above it, so the sheet still reads as swipe-to-dismiss.
                        .presentationDragIndicator(.visible)
                        // `[.large]` is what a sheet does when given no detents.
                        .presentationDetents(detents ?? [.large])
                }
            }
        }
        .onChange(of: wide) { _, _ in
            if !isPresented { onDismiss?() }
        }
        #else
        content.inspector(isPresented: $isPresented) {
            inspectorPanel.environment(\.filterPanelInInspector, true)
        }
            .onChange(of: isPresented) { _, presented in
                if !presented { onDismiss?() }
            }
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
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder panel: @escaping () -> some View
    ) -> some View {
        modifier(FilterPanelPresentation(
            isPresented: isPresented, detents: detents, onDismiss: onDismiss, panel: panel
        ))
    }
}

extension EnvironmentValues {
    /// True inside the filter panel's inspector (wide layouts, macOS), false in the sheet.
    @Entry var filterPanelInInspector = false
}

/// The filter panel's header. In a sheet it is the navigation title and Close button. In an
/// inspector the panel's navigation stack is part of the host's, so a title there replaces the
/// screen's own ("Library" read "Filters" while the Library was still showing, T-562c): the
/// inspector draws its own header inside the pane instead and publishes no title.
struct FilterPanelChrome: ViewModifier {
    @Environment(\.filterPanelInInspector) private var inInspector
    @Environment(\.dismiss) private var dismiss
    let title: String

    func body(content: Content) -> some View {
        if inInspector {
            content.safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                    Spacer(minLength: 0)
                    Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    // Balances the Close button so the title stays centred.
                    Image(systemName: "xmark").hidden().accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        } else {
            content
                .navigationTitle(title)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Close")
                    }
                }
        }
    }
}

extension View {
    func filterPanelChrome(title: String) -> some View { modifier(FilterPanelChrome(title: title)) }
}
