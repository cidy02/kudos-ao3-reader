import SwiftUI
import Testing
@testable import Kudos

struct SubjectPaletteTests {
    /// The bug this exists for: every tab-scoped screen used to hand the palette
    /// `effectiveTint.hueComponent` and nothing else, so two accents that shared a
    /// hue — a dusty rose and a hot pink — produced byte-identical washes. Spec
    /// 1m's rule is that the wash *is* the chosen colour, so they must not.
    @Test func twoAccentsSharingAHueDoNotWashTheSame() {
        let muted = Color(hue: 0.95, saturation: 0.22, brightness: 0.62)
        let vivid = Color(hue: 0.95, saturation: 1.0, brightness: 1.0)

        for theme in [ReaderTheme.dark, .oled, .light, .sepia] {
            let mutedStops = SubjectPalette(color: muted, theme: theme).washStops
            let vividStops = SubjectPalette(color: vivid, theme: theme).washStops
            #expect(mutedStops.first?.color != vividStops.first?.color, "\(theme)")
        }
    }

    /// And what reaches the wash is the colour itself at reduced alpha, rather
    /// than a saturation/brightness pair sharing its hue. Alpha subtracts how
    /// much of a colour is present; substitution changes which colour it is.
    @Test func aPickedColourReachesTheWashAsItself() {
        let picked = Color(hue: 0.58, saturation: 0.40, brightness: 0.80)
        let stops = SubjectPalette(color: picked, theme: .dark).washStops

        // Dark's ramp, fitted to the weight the derived stops already had for the
        // default AO3 red — every stop is the one colour, only less of it.
        #expect(stops.dropLast().map(\.color)
            == [0.41, 0.33, 0.21, 0.09].map { picked.opacity($0) })
    }

    /// The wash has to end at the page it sits on, or the screen keeps a coloured
    /// band at the bottom instead of resolving into the backdrop.
    @Test func theWashResolvesIntoThePageOnBothPaths() {
        for theme in [ReaderTheme.dark, .oled, .light, .sepia] {
            let picked = SubjectPalette(color: .purple, theme: theme).washStops
            let derived = SubjectPalette(hue: 0.75, theme: theme).washStops
            #expect(picked.last?.color == theme.cardBackdrop, "\(theme)")
            #expect(derived.last?.color == theme.cardBackdrop, "\(theme)")
            #expect(picked.last?.location == 1)
            #expect(derived.last?.location == 1)
        }
    }

    /// A fandom or a queue has no chosen colour — its hue comes from its name —
    /// so those keep the tuned saturation/brightness table that makes a gold
    /// fandom and a violet queue read at the same weight.
    @Test func aDerivedHueKeepsTheTunedTable() {
        let stops = SubjectPalette(hue: 0.58, theme: .dark).washStops
        let asPicked = SubjectPalette(
            color: Color(hue: 0.58, saturation: 1, brightness: 1), theme: .dark
        ).washStops
        #expect(stops.first?.color != asPicked.first?.color)
    }

    /// Both paths lay their stops at the spec's own positions.
    @Test func bothPathsUseTheSameStopPositions() {
        let picked = SubjectPalette(color: .orange, theme: .dark).washStops.map(\.location)
        let derived = SubjectPalette(hue: 0.1, theme: .dark).washStops.map(\.location)
        #expect(picked == derived)
        #expect(picked == [0, 0.26, 0.52, 0.74, 1])
    }
}
