import SwiftUI

/// Wiring for the system zoom transition: a work card expands into the screen it
/// opens, and collapses back into that card on dismiss.
///
/// All of the animation is Apple's — `matchedTransitionSource` marks the card,
/// `navigationTransition(.zoom(sourceID:in:))` marks the destination, and the system
/// drives the push, the dismiss, and the interactive swipe-back. Nothing here
/// interpolates a frame.
///
/// The only problem worth solving in this app is *reach*: the two ends are far apart.
/// Cards are built in `WorkCoverCard` / `AO3WorkCoverCard` inside a dozen containers,
/// while their destinations are resolved centrally in `LocalWorkDestinationView`, so
/// neither can hold the `Namespace` the pair has to share. The environment carries it
/// instead — one namespace declared per tab stack, read by both ends.
///
/// Both helpers no-op when the namespace is absent, so a container that hasn't opted
/// in simply gets the ordinary push rather than a broken one.
private struct WorkCardTransitionNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// Set once per tab stack; read by cards and by their pushed destinations.
    var workCardTransitionNamespace: Namespace.ID? {
        get { self[WorkCardTransitionNamespaceKey.self] }
        set { self[WorkCardTransitionNamespaceKey.self] = newValue }
    }
}

extension View {
    /// Marks this card as the thing a pushed screen should zoom out of.
    @ViewBuilder
    func workCardZoomSource(_ id: some Hashable, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// Marks this screen as zooming out of the card with the same id.
    @ViewBuilder
    func workCardZoomDestination(_ id: some Hashable, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}
