import SwiftUI
import Testing
@testable import Kudos

/// A filled control's label is whichever of black or white reads better on it.
struct ProminentLabelTests {
    @Test func picksTheHigherContrastLabel() {
        // AO3 red (Light's accent) keeps white.
        #expect(ThemeManager.label(on: Color(red: 0.6, green: 0, blue: 0)) == .white)
        // Dark's lifted accent (AO3 red mixed halfway to white) takes black —
        // white on it measured ~2.8:1, black ~7.6:1.
        #expect(ThemeManager.label(on: Color(red: 0.8, green: 0.5, blue: 0.5)) == .black)
        #expect(ThemeManager.label(on: .white) == .black)
        #expect(ThemeManager.label(on: .black) == .white)
    }
}
