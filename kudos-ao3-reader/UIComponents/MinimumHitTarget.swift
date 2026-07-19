import SwiftUI

/// Pads a control's tappable/hit region up to Apple's HIG minimum without growing
/// its visible glyph, background, or bordered chrome — only the invisible margin
/// around the already-rendered control grows.
///
/// Apply this as the LAST modifier on an already-styled control — after
/// `.buttonStyle`, `.buttonBorderShape`, `.controlSize`, `.tint`, and any
/// `.gesture`/`.contentShape`. Applied earlier (inside a label, before the
/// button/menu closure ends), a `.frame` instead grows the size a bordered/glass
/// style measures itself against and enlarges the *visible* chrome — see
/// `ReaderView.navButton`, which intentionally does that to reach a real 44pt
/// circle. This modifier is for the opposite case: a control that must stay
/// visually small but still needs a full-size invisible tap margin.
private struct MinimumHitTargetModifier: ViewModifier {
    let size: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(minWidth: size, minHeight: size)
            .contentShape(Rectangle())
    }
}

extension View {
    /// Grows this view's hit-testable area to at least `size`×`size` points while
    /// leaving its rendered appearance untouched. Defaults to 44pt, Apple's HIG
    /// minimum for a direct tap target; pass a smaller floor (e.g. 28) only for a
    /// control deliberately boxed tightly against other small controls, where a
    /// full 44pt region would visually overlap its neighbors.
    func minimumHitTarget(_ size: CGFloat = 44) -> some View {
        modifier(MinimumHitTargetModifier(size: size))
    }
}
