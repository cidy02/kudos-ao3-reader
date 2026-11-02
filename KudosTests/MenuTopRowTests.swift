import Foundation
import Testing
@testable import Kudos

struct MenuTopRowTests {
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

    @Test func everyMenuUsesTheSharedTopRow() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "kudos-ao3-reader")
        let expectations = [
            ("Features/Comments/CommentThreadRow.swift", "MenuTopRow {"),
            ("Features/Library/WorkCardActions.swift", "MenuTopRow {"),
            ("Features/Reader/ReaderView.swift", "MenuTopRow {"),
            ("Features/ReaderReadium/ReaderFanMenu.swift", "MenuTopRow {"),
            ("Features/WorkDetail/AO3WorkActionsMenu.swift", "MenuTopRow {"),
            ("Features/WorkDetail/WorkDetailView.swift", "AO3WorkActionsTopRow(")
        ]
        for (path, needle) in expectations {
            let source = try String(contentsOf: root.appending(path: path), encoding: .utf8)
            #expect(source.contains(needle), "\(path)")
        }
    }

    @Test func workDetailDeleteUsesTheSharedConfirmationPolicy() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "kudos-ao3-reader/Features/WorkDetail/WorkDetailView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        #expect(source.contains("PreservedWorkService.shouldConfirmDelete"))
        #expect(source.contains(".deleteConfirmation("))
    }
}
