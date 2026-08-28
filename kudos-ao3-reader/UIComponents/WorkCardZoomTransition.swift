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

/// The identity a work is matched on for the zoom pair.
///
/// The model that represents "this work" changes shape between a remote card and the
/// destination it opens. `AO3WorkSummary.id` is AO3's own numeric work id; `SavedWork.id`
/// is a UUID minted fresh at import time with no relationship to it whatsoever. A remote
/// card only ever knows the AO3 id, while the reader it pushes resolves to a `SavedWork`
/// — so keying the pair on each model's raw `id` meant a remote card's advertised source
/// could never equal its own destination's, and every remote card (Home Subscriptions,
/// Library's remote Marked-for-Later entries, Account's bookmarks and account-works
/// lists) silently fell back to a plain push. Nothing reports it: `matchedTransitionSource`
/// takes `some Hashable`, so an `Int` that can never equal a `UUID` is not a compiler
/// error, and an unmatched pair is just an ordinary push.
///
/// Both sides normalize onto the AO3 id when one exists (`SavedWork.ao3WorkID`, set the
/// moment a remote work resolves to a local one), and only fall back to the `SavedWork`'s
/// own UUID for a work with no AO3 origin — an imported PDF/HTML/text file — where no
/// remote card ever exists to need matching.
enum WorkZoomKey: Hashable {
    case ao3(Int)
    case local(UUID)
}

extension SavedWork {
    /// See `WorkZoomKey`.
    var zoomKey: WorkZoomKey {
        ao3WorkID.map(WorkZoomKey.ao3) ?? .local(id)
    }
}

extension AO3WorkSummary {
    /// See `WorkZoomKey`. Every remote summary has an AO3 id by definition.
    var zoomKey: WorkZoomKey { .ao3(id) }
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
        #if os(macOS)
        self
        #else
        if let namespace {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
        #endif
    }

    /// Marks this screen as zooming out of the card with the same id.
    ///
    /// iOS only: `NavigationTransition.zoom` is unavailable on macOS, where a window's
    /// navigation has no such presentation to animate. The Mac build keeps the plain
    /// push, which is why this is a no-op there rather than a compile-time exclusion
    /// at every call site.
    @ViewBuilder
    func workCardZoomDestination(_ id: some Hashable, in namespace: Namespace.ID?) -> some View {
        #if os(macOS)
        self
        #else
        if let namespace {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
        #endif
    }
}
