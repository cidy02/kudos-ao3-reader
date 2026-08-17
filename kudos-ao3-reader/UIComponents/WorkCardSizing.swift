import SwiftUI

/// Gives every work card in one container the same height: the tallest card's.
///
/// ## Why a container decides this, not a card
///
/// A card is a fixed sqrt(2):1 tile (scaled by Dynamic Type — `ScaledCarouselCardSize`),
/// and its content sometimes needs more than that. Left alone, each card grows on its
/// own, so a carousel ends up with ragged bottoms and a grid row's cards don't line up.
/// Height is a property of the *set* of cards on screen, so the set is what resolves it.
///
/// Width deliberately does **not** change. Every grid sizes its columns with
/// `CarouselCardMetrics.adaptiveCardColumns(minimum: cardSize.width)`, so a card that
/// grew wider than that constant would overlap its neighbour — the exact bug that
/// helper's own comment documents. Keeping width fixed makes that impossible by
/// construction. (If cards should also widen to hold the sqrt(2):1 proportion, the
/// column math has to be fed the resolved width in the same change.)
///
/// ## Why this needs no hidden measuring copy
///
/// The obvious implementation renders each card twice — once hidden at its natural
/// size to measure, once visibly at the resolved size — which doubles the view tree,
/// including each card's ⓘ `NavigationLink`. It isn't necessary. `frame(minHeight:)`
/// is a floor, not a clamp: content taller than the floor still reports its real
/// height, so one render both displays and measures.
///
/// The feedback loop that usually makes this unsafe is closed off because the resolved
/// height only ever *rises*: each pass reports `max(natural, resolved)`, the container
/// takes the max across cards, and that reaches a fixed point in a pass or two instead
/// of oscillating. The one thing monotonic growth can't do is shrink when content gets
/// smaller, so the height resets whenever Dynamic Type changes.
///
/// ## In a lazy grid
///
/// A `LazyVGrid` only builds the cells it can show, so the tallest card is known only
/// for what has been scrolled past. Scrolling into a taller one raises the height for
/// every card at once. That is a deliberate trade: the alternative is measuring cards
/// that are not on screen, which is what lazy containers exist to avoid. Monotonic
/// growth keeps it to a settling-in effect rather than a flicker, and capping card
/// titles at two lines keeps most cards inside the floor to begin with.
struct WorkCardHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct UniformWorkCardHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    /// The height every work card in the enclosing container should render at, once
    /// the container has measured them. `nil` until then — cards use their own floor.
    var uniformWorkCardHeight: CGFloat? {
        get { self[UniformWorkCardHeightKey.self] }
        set { self[UniformWorkCardHeightKey.self] = newValue }
    }
}

extension View {
    /// Apply to a carousel or grid so the work cards inside it share one height.
    ///
    /// Safe to leave off: a container without it just renders cards at their own
    /// floor, which is the behaviour that existed before this modifier.
    func uniformWorkCardHeights() -> some View {
        modifier(UniformWorkCardHeights())
    }
}

private struct UniformWorkCardHeights: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var resolvedHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .environment(\.uniformWorkCardHeight, resolvedHeight > 0 ? resolvedHeight : nil)
            .onPreferenceChange(WorkCardHeightPreferenceKey.self) { measured in
                // Rises only — see the type comment. Guarding on `>` also stops a
                // report equal to the current value from re-entering state.
                if measured > resolvedHeight { resolvedHeight = measured }
            }
            // Content shrinks when text does, and a monotonic height would otherwise
            // keep the taller box forever. Dropping to zero re-measures from the floor.
            .onChange(of: dynamicTypeSize) { _, _ in resolvedHeight = 0 }
    }
}
