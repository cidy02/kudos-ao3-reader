import SwiftUI
import Testing
@testable import Kudos

/// The Rules board's "Shape and space", held as numbers (T-484). Each one is a
/// rule the owner wrote down, so a change here is a design decision, not a tweak.
struct ShapeAndSpaceTokensTests {
    @Test func everyCardTileCoverAndPanelTakesSixteen() {
        #expect(SubjectMetrics.cornerRadius == 16)
    }

    /// "16 pt edge on every screen" — including the account's lists, whose
    /// name for it must not drift into a second number.
    @Test func theScreenEdgeIsSixteenEverywhere() {
        #expect(SubjectMetrics.gutter == 16)
        #expect(SubjectMetrics.accountGutter == SubjectMetrics.gutter)
        #expect(CardListMetrics.sideMargin == SubjectMetrics.gutter)
    }

    @Test func contentScreenSectionsAreTwentySixApart() {
        #expect(SubjectMetrics.sectionSpacing == 26)
    }

    /// A capsule is a radius SwiftUI clamps to half the shorter side; anything
    /// finite and small would draw a rounded rect on a tall enough control.
    @Test func controlsAreCapsulesUntilTheirLabelCanWrap() {
        #expect(SubjectMetrics.capsuleRadius == .infinity)
        #expect(SubjectMetrics.controlShape(.large).cornerSize.width == SubjectMetrics.capsuleRadius)
        #expect(SubjectMetrics.controlShape(.xxxLarge).cornerSize.width == SubjectMetrics.capsuleRadius)
        #expect(SubjectMetrics.controlShape(.accessibility1).cornerSize.width == SubjectMetrics.cornerRadius)
        #expect(SubjectMetrics.controlShape(.accessibility5).cornerSize.width == SubjectMetrics.cornerRadius)
        #expect(SubjectMetrics.controlShape(.large).style == .continuous)
    }
}
