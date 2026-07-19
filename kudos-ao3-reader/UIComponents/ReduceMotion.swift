import SwiftUI

/// Runs `body` inside `withAnimation(animation)` unless the user has Reduce Motion
/// enabled, in which case `body` runs unanimated — exactly as if `withAnimation`
/// had never been called. Use this at any tap-handler / task call site that
/// currently wraps a state mutation in a bare `withAnimation { ... }`.
///
/// Ordinary functions (including button-action closures) can't read `@Environment`
/// themselves, so `reduceMotion` is a required, explicit parameter — pass through
/// your own `@Environment(\.accessibilityReduceMotion)` value.
///
/// - Parameters:
///   - animation: The animation to run when Reduce Motion is off. Defaults to
///     `.default`, matching the no-argument `withAnimation { }` call this replaces.
///   - reduceMotion: The caller's `\.accessibilityReduceMotion` environment value.
///   - body: The state change to perform, animated or not.
func withAnimationUnlessReduced(
    _ animation: Animation = .default,
    reduceMotion: Bool,
    _ body: () -> Void
) {
    if reduceMotion {
        body()
    } else {
        withAnimation(animation, body)
    }
}

private struct ReduceMotionAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    /// The declarative counterpart to `withAnimationUnlessReduced` — applies
    /// `animation` when `value` changes, but only if the user hasn't asked for
    /// Reduce Motion. Reads the environment itself (via a `ViewModifier`, the
    /// same mechanism `skeletonShimmer()` uses), so no flag needs to be threaded
    /// through by the caller. Use this at sites like `.animation(.easeInOut(duration:
    /// 0.3), value: isHighlighted)` that currently animate unconditionally.
    func animation<Value: Equatable>(unlessReduced animation: Animation, value: Value) -> some View {
        modifier(ReduceMotionAnimationModifier(animation: animation, value: value))
    }
}
