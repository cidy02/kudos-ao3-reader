import SwiftUI

/// Home and Library take the wash colour of the work they lead with: Home from
/// the current Continue Reading hero, Library from the top of Reading Now.
/// Controls remain AO3 red; no work means no wash. Android does the same in
/// `MainScaffold` (`washHue`).
private struct HeroWash: ViewModifier {
    @Environment(ThemeManager.self) private var themeManager
    let work: SavedWork?

    func body(content: Content) -> some View {
        let palette = work.map {
            themeManager.appTheme.subjectPalette(hue: CoverArt.workHue(fandoms: $0.workFandoms, title: $0.title))
        }
        // One path for both cases: an `if` here would rebuild the page when the
        // hero appears or goes.
        content
            .background(alignment: .top) {
                if let palette {
                    palette.wash
                        .frame(height: 380)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .ignoresSafeArea()
                }
            }
            .accentTint(palette?.tint ?? themeManager.effectiveTint, on: themeManager.appTheme)
            .environment(\.screenTint, palette?.tint)
    }
}

extension View {
    /// Apply before the screen's backdrop `.background`, so the wash sits in front of it.
    func heroWash(_ work: SavedWork?) -> some View {
        modifier(HeroWash(work: work))
    }
}
