import SwiftUI
import Testing
@testable import Kudos

struct WorkStatLabelTests {
    @Test func ratingColorMatchesAO3sOwnCoding() {
        #expect(WorkStat.ratingColor("General Audiences") == .green)
        #expect(WorkStat.ratingColor("Teen And Up Audiences") == .yellow)
        #expect(WorkStat.ratingColor("Mature") == .orange)
        #expect(WorkStat.ratingColor("Explicit") == .red)
        // Gray, not nil — nil falls through to the app's red accent tint, which
        // would make an unrated work look like the most severe rating.
        #expect(WorkStat.ratingColor("Not Rated") == .gray)
        #expect(WorkStat.ratingColor("") == nil)
    }

    @Test func ratingNameShortensKnownAO3Ratings() {
        #expect(WorkStat.ratingName("General Audiences") == "General")
        #expect(WorkStat.ratingName("Teen And Up Audiences") == "Teen")
        #expect(WorkStat.ratingName("Mature") == "Mature")
        #expect(WorkStat.ratingName("Explicit") == "Explicit")
        #expect(WorkStat.ratingName("Not Rated") == "Not Rated")
        #expect(WorkStat.ratingName("") == nil)
        #expect(WorkStat.ratingName("Some Custom Thing") == "Some Custom Thing")
    }

    @Test func ratingLetterAbbreviatesForTheDenseTopRow() {
        #expect(WorkStat.ratingLetter("General Audiences") == "G")
        #expect(WorkStat.ratingLetter("Teen And Up Audiences") == "T")
        #expect(WorkStat.ratingLetter("Mature") == "M")
        #expect(WorkStat.ratingLetter("Explicit") == "E")
        #expect(WorkStat.ratingLetter("Not Rated") == "NR")
        #expect(WorkStat.ratingLetter("") == nil)
        // The compact cover cards deliberately keep the spelled-out name.
        #expect(WorkStat.ratingName("General Audiences") == "General")
    }

    @Test func completionShortTextOnlyAbbreviatesInProgress() {
        #expect(WorkCompletionStatus.inProgress.shortText == "WIP")
        #expect(WorkCompletionStatus.inProgress.text == "In Progress")
        #expect(WorkCompletionStatus.complete.shortText == "Complete")
        #expect(WorkCompletionStatus.unknown.shortText == "Unknown")
    }

    @Test func displayDateParsesTheWorkDetailPageISOFormat() {
        #expect(WorkStat.displayDate("2025-11-01") == "11/01/2025")
    }

    @Test func displayDateParsesTheSearchBlurbFormat() {
        #expect(WorkStat.displayDate("01 Nov 2025") == "11/01/2025")
    }

    @Test func displayDateFallsBackToTheRawStringWhenUnrecognized() {
        #expect(WorkStat.displayDate("not a date") == "not a date")
    }

    @Test func searchLedgerMetadataKeepsUnitsAndZeroCountPreference() {
        var work = AO3WorkSummary(
            id: 1,
            title: "Title",
            authors: ["Author"],
            fandoms: ["Fandom"],
            rating: "General Audiences",
            warnings: [],
            categories: ["Gen"],
            isComplete: true,
            dateUpdated: "12 Feb 2026",
            tags: [],
            summary: "Summary",
            language: " English ",
            words: 84_210,
            chapters: "11/11",
            comments: 212,
            kudos: 3_204,
            bookmarks: 486,
            hits: 61_904,
            seriesTitle: nil,
            seriesURL: nil,
            seriesPosition: nil
        )
        #expect(AO3WorkRow.ledgerMetadata(for: work, showsZeroStats: false) == [
            "English", "84,210 words", "11/11", "212 comments",
            "3,204 kudos", "486 bookmarks", "61,904 hits",
        ])

        work.words = nil
        work.comments = nil
        work.kudos = 0
        work.bookmarks = nil
        work.hits = 0
        #expect(AO3WorkRow.ledgerMetadata(for: work, showsZeroStats: false) == ["English", "11/11"])
        #expect(AO3WorkRow.ledgerMetadata(for: work, showsZeroStats: true) == [
            "English", "0 words", "11/11", "0 comments", "0 kudos", "0 bookmarks", "0 hits",
        ])
    }

    @Test func categoryColorMatchesAO3sOwnCoding() {
        #expect(WorkStat.categoryColor("F/F") == .red)
        #expect(WorkStat.categoryColor("F/M") == .pink)
        #expect(WorkStat.categoryColor("Gen") == .green)
        #expect(WorkStat.categoryColor("M/M") == .blue)
        #expect(WorkStat.categoryColor("Multi") == .purple)
        // Black, not gray: AO3's own Symbols Key badge for "Other" sits on
        // solid black. Changed deliberately in b4f8faba; this assertion was
        // left behind and has failed ever since.
        #expect(WorkStat.categoryColor("Other") == .black)
        #expect(WorkStat.categoryColor("Not A Category") == nil)
    }

    @Test func realWarningsFiltersOutSentinelValues() {
        #expect(WorkStat.realWarnings(["No Archive Warnings Apply"]).isEmpty)
        #expect(WorkStat.realWarnings(["Creator Chose Not To Use Archive Warnings"]).isEmpty)
        #expect(WorkStat.realWarnings(["Graphic Depictions Of Violence"]) == ["Graphic Depictions Of Violence"])
        #expect(WorkStat.realWarnings([
            "Graphic Depictions Of Violence", "No Archive Warnings Apply"
        ]) == ["Graphic Depictions Of Violence"])
    }

    @Test func completionStatusMapsIsCompleteToTriState() {
        #expect(WorkCompletionStatus(isComplete: true) == .complete)
        #expect(WorkCompletionStatus(isComplete: false) == .inProgress)
        #expect(WorkCompletionStatus(isComplete: nil) == .unknown)
    }

    @Test func completionStatusHasKeptTheShippingIconsAndAddsColor() {
        #expect(WorkCompletionStatus.complete.symbol == "checkmark.seal")
        #expect(WorkCompletionStatus.complete.color == .green)
        #expect(WorkCompletionStatus.inProgress.symbol == "circle.dashed")
        #expect(WorkCompletionStatus.inProgress.color == .orange)
        #expect(WorkCompletionStatus.unknown.symbol == "questionmark.circle.fill")
        #expect(WorkCompletionStatus.unknown.color == .gray)
    }

    @Test func savedWorkCompletionStatusIsUnknownOnlyForNonAO3ImportsWithoutAStatedStatus() {
        let ao3Work = SavedWork(title: "AO3 Import", author: "Someone")
        ao3Work.ao3WorkID = 123
        ao3Work.isComplete = false
        #expect(ao3Work.completionStatus == .inProgress)
        ao3Work.isComplete = true
        #expect(ao3Work.completionStatus == .complete)

        let plainImport = SavedWork(title: "EPUB Import", author: "Someone", sourceURL: "")
        plainImport.isComplete = false
        #expect(plainImport.completionStatus == .unknown)
        plainImport.isComplete = true
        #expect(plainImport.completionStatus == .complete)
    }

    @Test func warningStatusDistinguishesUndisclosedFromNoneFromPresent() {
        #expect(WorkWarningStatus(rawWarnings: []) == .none)
        #expect(WorkWarningStatus(rawWarnings: ["No Archive Warnings Apply"]) == .none)
        #expect(WorkWarningStatus(rawWarnings: ["Creator Chose Not To Use Archive Warnings"]) == .undisclosed)
        #expect(WorkWarningStatus(rawWarnings: ["Graphic Depictions Of Violence"]) == .present(count: 1))
        #expect(WorkWarningStatus(rawWarnings: [
            "Graphic Depictions Of Violence", "Major Character Death"
        ]) == .present(count: 2))
    }

    @Test func warningStatusUndisclosedIsNotTheSameAsNone() {
        // The bug this guards against: collapsing "creator chose not to warn"
        // (content could include anything) into the same bucket as "no
        // warnings apply" (confirmed clean) would misrepresent the former.
        let undisclosed = WorkWarningStatus(rawWarnings: ["Creator Chose Not To Use Archive Warnings"])
        #expect(undisclosed.text == "Not Disclosed")
        #expect(undisclosed.color == .orange)
        #expect(WorkWarningStatus.none.text == "No Warnings")
        #expect(WorkWarningStatus.none.color == .gray)
    }
}
