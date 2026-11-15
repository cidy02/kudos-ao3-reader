import SwiftUI
import Testing
@testable import Kudos

/// Layout picked by Dynamic Type size. Reverting the choice fails these,
/// which a modifier-existence check would not.
struct HomeAccessibilityLayoutTests {
    @Test func resumeActionsStayInOneRowBelowAccessibilitySizes() {
        #expect(HomeResumeLayout.stacksActions(.large) == false)
        #expect(HomeResumeLayout.stacksActions(.xxxLarge) == false)
        #expect(HomeResumeLayout.stacksActions(.accessibility1) == true)
        #expect(HomeResumeLayout.stacksActions(.accessibility5) == true)
    }

    @Test func sectionCountStaysBesideTheTitleBelowAccessibilitySizes() {
        #expect(SectionHeaderLayout.stacksCount(.large) == false)
        #expect(SectionHeaderLayout.stacksCount(.xxxLarge) == false)
        #expect(SectionHeaderLayout.stacksCount(.accessibility1) == true)
        #expect(SectionHeaderLayout.stacksCount(.accessibility5) == true)
    }

    @Test func softBreaksLeaveAFittingWordAndOpenATokenThatCannot() {
        #expect(AccessibilitySoftBreak.opportunities(in: "Chapters") == "Chapters")
        #expect(AccessibilitySoftBreak.opportunities(in: "New Chapters") == "New Chapters")
        let subscriptions = AccessibilitySoftBreak.opportunities(in: "Subscriptions")
        #expect(subscriptions.contains("\u{200B}"))
        #expect(subscriptions.replacingOccurrences(of: "\u{200B}", with: "") == "Subscriptions")
        #expect(AccessibilitySoftBreak.opportunities(in: "nine_of_wands") == "nine_\u{200B}of_\u{200B}wands")
    }
}
