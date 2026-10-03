import SwiftUI

/// Home and Library wash their top in the colour of the work they lead with
/// (owner, 2026-10-03): Home takes the current Continue Reading hero, Library
/// the top of Reading Now. Only the gradient: controls keep the app accent,
/// which `subjectWash` would change through `screenTint`. No work, no wash.
/// Android draws the same in `MainScaffold` (`washHue`).
private struct HeroWash: ViewModifier {
    @Environment(ThemeManager.self) private var themeManager
    let work: SavedWork?

    func body(content: Content) -> some View {
        content.background(alignment: .top) {
            if let work {
                themeManager.appTheme
                    .subjectPalette(hue: CoverArt.workHue(fandoms: work.workFandoms, title: work.title))
                    .wash
                    .frame(height: 380)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea()
            }
        }
    }
}

extension View {
    /// Apply before the screen's backdrop `.background`, so the wash sits in front of it.
    func heroWash(_ work: SavedWork?) -> some View {
        modifier(HeroWash(work: work))
    }
}
