import Testing
@testable import Kudos

struct MenuTopRowTests {
    @Test func validItemCounts() {
        #expect(MenuTopRowRules.isValidCount(1))
        #expect(MenuTopRowRules.isValidCount(2))
        #expect(MenuTopRowRules.isValidCount(3))
        #expect(MenuTopRowRules.isValidCount(4))
        #expect(!MenuTopRowRules.isValidCount(0))
        #expect(!MenuTopRowRules.isValidCount(5))
        #expect(!MenuTopRowRules.isValidCount(-1))
    }

    @Test func kudosSymbols() {
        #expect(MenuTopRowRules.kudosSymbol(isGiven: false) == "heart")
        #expect(MenuTopRowRules.kudosSymbol(isGiven: true) == "heart.fill")
    }

    @Test func bookmarkSymbols() {
        #expect(MenuTopRowRules.bookmarkSymbol(isBookmarked: false) == "bookmark")
        #expect(MenuTopRowRules.bookmarkSymbol(isBookmarked: true) == "bookmark.fill")
    }

    @Test func subscribeSymbols() {
        #expect(MenuTopRowRules.subscribeSymbol(isSubscribed: false) == "bell")
        #expect(MenuTopRowRules.subscribeSymbol(isSubscribed: true) == "bell.fill")
    }

    @Test func readAloudSymbols() {
        #expect(MenuTopRowRules.readAloudSymbol(isActive: false) == "waveform")
        #expect(MenuTopRowRules.readAloudSymbol(isActive: true) == "waveform.circle.fill")
    }
}
