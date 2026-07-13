import Foundation
#if os(iOS)
import ReadiumNavigator
import ReadiumShared

/// Decides when the Readium reader has truly reached the end of a publication,
/// for auto-finishing completed works (A7-F1).
///
/// The rule is the navigator's own last-resource/end state, not a progression
/// threshold: the publication's final reading-order resource must be visible
/// with its trailing edge at the resource's very end. Readium 3.9.0 clamps each
/// visible resource's progression range to `0.0...1.0` and reports an upper
/// bound of exactly `1.0` when the viewport rests at (or rubber-bands past) the
/// resource's end — its own position calculator relies on the same
/// `== 1.0` comparison — so no floating-point tolerance is needed, and none is
/// used: any tolerance would re-admit the "99% ≈ done" defect this replaces.
/// `Locator.locations.totalProgression` is deliberately not consulted; it is
/// the viewport's *leading* edge, which stays below 1.0 while the last page is
/// being read, and its interpolated value is not exact at the boundaries.
enum ReadiumReaderCompletion {
    /// True only when the trailing edge of the visible viewport rests at the
    /// end of the publication's final reading-order resource.
    static func isAtEnd(viewport: NavigatorViewport?, readingOrder: [ReadiumShared.Link]) -> Bool {
        guard let viewport, let lastLink = readingOrder.last else { return false }
        // Match hrefs the same way the toolkit does (`firstIndexWithHREF`):
        // by normalized URL string, so both sides of the comparison are built
        // from the same `Link.url()` normalization.
        let lastHref = lastLink.url().normalized.string
        guard let visibleLast = viewport.resources.last(where: {
            $0.href.normalized.string == lastHref
        }) else { return false }
        return visibleLast.progression.upperBound == 1.0
    }
}
#endif
