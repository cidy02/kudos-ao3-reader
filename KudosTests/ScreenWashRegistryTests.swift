import SwiftUI
import Testing
@testable import Kudos

/// Owner, 2026-10-11: the tab bar and chrome buttons take the colour of the
/// screen on top. `ScreenWashRegistry` decides which screen that is.
@MainActor
struct ScreenWashRegistryTests {
    @Test func theScreenThatAppearedLastIsCurrentAndGoingBackReturnsTheColour() {
        let registry = ScreenWashRegistry()
        let library = UUID()
        let collection = UUID()
        #expect(registry.current == nil)

        registry.show(library, tint: .purple)
        #expect(registry.current == .purple)
        registry.show(collection, tint: .green) // pushed
        #expect(registry.current == .green)
        registry.hide(collection) // popped
        #expect(registry.current == .purple)
        registry.hide(library) // a screen with no wash is on top
        #expect(registry.current == nil)
    }

    /// The hero work changing on the page underneath must not take the colour
    /// from the screen on top of it.
    @Test func aNewColourUnderneathDoesNotTakeOver() {
        let registry = ScreenWashRegistry()
        let home = UUID()
        let work = UUID()
        registry.show(home, tint: .purple)
        registry.show(work, tint: .pink)
        registry.show(home, tint: .orange)
        #expect(registry.current == .pink)
        registry.hide(work)
        #expect(registry.current == .orange)
    }

    /// Home and Library with no work to lead with have no wash: they withdraw.
    @Test func aScreenWhoseWashGoesWithdraws() {
        let registry = ScreenWashRegistry()
        let home = UUID()
        registry.show(home, tint: .purple)
        registry.show(home, tint: nil)
        #expect(registry.current == nil)
    }
}
