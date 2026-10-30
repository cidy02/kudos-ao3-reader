import SwiftUI
import Testing
@testable import Kudos

struct WorkStatLabelTests {
    /// AO3's own hexes (T-479), not the system colours.
    @Test func ratingColorMatchesAO3sOwnCoding() {
        #expect(WorkStat.ratingColor("General Audiences")?.hexString == "#2F8F3A")
        #expect(WorkStat.ratingColor("Teen And Up Audiences")?.hexString == "#F5C400")
        #expect(WorkStat.ratingColor("Mature")?.hexString == "#E07000")
        #expect(WorkStat.ratingColor("Explicit")?.hexString == "#C8102E")
        // Gray, not nil — nil falls through to the app's red accent tint, which
        // would make an unrated work look like the most severe rating.
        #expect(WorkStat.ratingColor("Not Rated") == .gray)
        #expect(WorkStat.ratingColor("") == nil)
    }

    /// As text on a page the tile yellow is ~1.6:1, so Teen keeps L3-TH-4's dark
    /// mustard in the light themes; the others print in their own colour there.
    @Test func teenRatingTextDarkensInLightThemes() throws {
        for theme in [ReaderTheme.light, .sepia] {
            let teen = try #require(WorkStat.ratingInk("Teen And Up Audiences", on: theme))
            #expect(teen == AO3TagPalette.teenTextOnLight)
            #expect(teen.contrastRatio(on: .white) >= 4.5)
            #expect(WorkStat.ratingInk("Mature", on: theme) == AO3TagPalette.mature)
        }
        #expect(WorkStat.ratingInk("", on: .light) == nil)
    }

    /// Dark and OLED take T-419's readable step: Explicit's red is ~3.3:1 on
    /// the Dark page as it stands.
    @Test func ratingTextReadsOnBothDarkPages() throws {
        for theme in [ReaderTheme.dark, .oled] {
            for rating in ["General Audiences", "Teen And Up Audiences", "Mature", "Explicit"] {
                let ink = try #require(WorkStat.ratingInk(rating, on: theme))
                #expect(ink.contrastRatio(on: theme.cardBackdrop) >= 4.5, "\(rating) on \(theme)")
            }
        }
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

        // A full blurb: AO3 omits a zero count, so nil reads as 0.
        work.comments = nil
        work.kudos = 0
        work.bookmarks = nil
        work.hits = 0
        #expect(AO3WorkRow.ledgerMetadata(for: work, showsZeroStats: false) == [
            "English", "84,210 words", "11/11",
        ])
        #expect(AO3WorkRow.ledgerMetadata(for: work, showsZeroStats: true) == [
            "English", "84,210 words", "11/11", "0 comments", "0 kudos", "0 bookmarks", "0 hits",
        ])

        // A sparse list row (no word count): unknown stats are not zeros.
        work.words = nil
        #expect(AO3WorkRow.ledgerMetadata(for: work, showsZeroStats: true) == [
            "English", "11/11", "0 kudos", "0 hits",
        ])
    }

    @Test func categoryColorMatchesAO3sOwnCoding() {
        #expect(WorkStat.categoryColor("F/F")?.hexString == "#D2264B")
        #expect(WorkStat.categoryColor("F/M")?.hexString == "#B3127A")
        #expect(WorkStat.categoryColor("Gen")?.hexString == "#2F8F3A")
        #expect(WorkStat.categoryColor("M/M")?.hexString == "#1E63C8")
        // The board has no one colour for Multi; its text chip keeps purple.
        #expect(WorkStat.categoryColor("Multi") == .purple)
        // Near-black, not gray: AO3's own Symbols Key badge for "Other" sits on
        // solid black.
        #expect(WorkStat.categoryColor("Other")?.hexString == "#1C1C1E")
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

    /// The chips' glyphs are the tiles': a plain check, a half-filled ring, "?".
    @Test func completionStatusChipMatchesItsTile() {
        #expect(WorkCompletionStatus.complete.symbol == "checkmark")
        #expect(WorkCompletionStatus.complete.color == AO3TagPalette.general)
        #expect(WorkCompletionStatus.inProgress.symbol == "circle.lefthalf.filled")
        #expect(WorkCompletionStatus.inProgress.color == AO3TagPalette.wipInk)
        #expect(WorkCompletionStatus.unknown.symbol == "questionmark")
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
        #expect(undisclosed.color == AO3TagPalette.mature)
        #expect(WorkWarningStatus.none.text == "No Warnings")
        #expect(WorkWarningStatus.none.color == .gray)
    }

    // MARK: The one local metadata line (was two, byte for byte)

    @Test func localWorkMetadataNamesAuthorWordsAndChapters() {
        #expect(WorkStat.localWorkMetadata(author: "Rosalita", wordCount: 1_773, chapters: "3/3")
            == ["Rosalita", "1.77K words", "3/3"])
    }

    /// The ledger row's metadata sits in a column narrower than the card, so the
    /// figure is compacted past 999 rather than printed in full.
    @Test func localWorkMetadataCompactsWordCountsPastNineHundredNinetyNine() {
        func words(_ count: Int) -> String? {
            WorkStat.localWorkMetadata(author: "", wordCount: count, chapters: "").first
        }
        // Under the threshold the notation prints the plain figure.
        #expect(words(999) == "999 words")
        #expect(words(1_000) == "1K words")
        // Two fraction digits, not `.compactName`'s default one — "1.2K" would
        // lose the 50 that distinguishes 1,250 from 1,200.
        #expect(words(1_250) == "1.25K words")
        #expect(words(33_700) == "33.7K words")
        #expect(words(1_200_000) == "1.2M words")
    }

    @Test func localWorkMetadataSkipsWhatIsNotKnown() {
        // A plain EPUB import can have none of the three. Each is dropped
        // independently rather than printing "0 words" or an empty segment,
        // because the line is joined with dots and an empty one shows.
        #expect(WorkStat.localWorkMetadata(author: "", wordCount: 0, chapters: "") == [])
        #expect(WorkStat.localWorkMetadata(author: "Rosalita", wordCount: 0, chapters: "")
            == ["Rosalita"])
        #expect(WorkStat.localWorkMetadata(author: "", wordCount: 1_773, chapters: "")
            == ["1.77K words"])
    }

    @Test func localWorkMetadataTreatsWhitespaceOnlyValuesAsAbsent() {
        // AO3 blurbs and EPUB metadata both yield padded strings; an author of
        // " " would otherwise print as a segment made of one space.
        #expect(WorkStat.localWorkMetadata(author: "   ", wordCount: 0, chapters: "  ") == [])
    }
}

/// The four tags as AO3's own solid tiles (T-479, decision TILES; I-1, I-2, I-3).
struct WorkSymbolTileTests {
    private typealias Tile = WorkSymbolTile

    /// Every tile the grid can draw except Multi, which has no glyph.
    private func everyTile(dark: Bool) -> [Tile] {
        let ratings: [String?] = ["General Audiences", "Teen And Up Audiences", "Mature", "Explicit", "Not Rated", nil]
        let categories: [[String]] = [["F/F"], ["F/M"], ["M/M"], ["Gen"], ["Other"], []]
        let warnings: [WorkWarningStatus] = [.none, .undisclosed, .present(count: 1)]
        let statuses: [WorkCompletionStatus] = [.complete, .inProgress, .unknown]
        var tiles: [Tile] = ratings.map { Tile.rating($0, dark: dark) }
        tiles += categories.map { Tile.category($0, dark: dark) }
        tiles += warnings.map { Tile.warnings($0, dark: dark) }
        tiles += statuses.map { Tile.completion($0, dark: dark) }
        return tiles
    }

    @Test func ratingsAreSolidShieldsInAO3sColours() {
        let general = Tile.rating("General Audiences", dark: false)
        #expect(general.mark == .shield("G"))
        #expect(general.fill.hexString == "#2F8F3A")
        #expect(general.ink.hexString == "#FFFFFF")
        #expect(Tile.rating("Mature", dark: false).fill.hexString == "#E07000")
        #expect(Tile.rating("Explicit", dark: true).fill.hexString == "#C8102E")
        // One palette for every theme.
        #expect(Tile.rating("Explicit", dark: true) == Tile.rating("Explicit", dark: false))
    }

    /// White can't hold contrast on the yellow, so Teen's shield is dark.
    @Test func teenTakesTheDarkGlyph() {
        let teen = Tile.rating("Teen And Up Audiences", dark: false)
        #expect(teen.mark == .shield("T"))
        #expect(teen.fill.hexString == "#F5C400")
        #expect(teen.ink.hexString == "#3A2C00")
    }

    @Test func categoriesTakeTheirOwnSignAndColour() {
        let expected: [(String, Tile.Mark, String)] = [
            ("F/F", .femaleFemale, "#D2264B"), ("F/M", .femaleMale, "#B3127A"),
            ("M/M", .maleMale, "#1E63C8"), ("Gen", .gen, "#2F8F3A"), ("Other", .other, "#1C1C1E"),
        ]
        for (category, mark, hex) in expected {
            let tile = Tile.category([category], dark: false)
            #expect(tile.mark == mark, "\(category)")
            #expect(tile.fill.hexString == hex, "\(category)")
            #expect(tile.ink.hexString == "#FFFFFF", "\(category)")
        }
    }

    /// #1C1C1E is the Dark theme's own surface and nearly OLED's black.
    @Test func otherLiftsOnTheDarkThemes() {
        #expect(Tile.category(["Other"], dark: true).fill.hexString == "#48484A")
    }

    /// The collapsed card's fold: several categories are Multi, none is a dash.
    @Test func categoryTileFoldsLikeTheCollapsedChip() {
        #expect(Tile.category(["F/F", "M/M"], dark: false).mark == .multi)
        #expect(Tile.category(["Multi"], dark: false).mark == .multi)
        #expect(Tile.category(["M/M", "Not A Category"], dark: false).mark == .maleMale)
        #expect(Tile.category([], dark: false).mark == .dash)
    }

    @Test func absentTagsAreGreyNotGaps() {
        let absent = [
            Tile.rating(nil, dark: false), Tile.rating("Not Rated", dark: false),
            Tile.category([], dark: false), Tile.warnings(.none, dark: false), Tile.completion(.unknown, dark: false),
        ]
        for tile in absent {
            #expect(tile.fill.hexString == "#E6E6EB")
            #expect(tile.ink.hexString == "#6C6C70")
        }
        #expect(Tile.rating(nil, dark: false).mark == .shield("?"))
        #expect(Tile.warnings(.none, dark: false).mark == .dash)
        #expect(Tile.completion(.unknown, dark: false).mark == .question)
    }

    @Test func warningsAndStatusDrawTheBoardsGlyphs() {
        let undisclosed = Tile.warnings(.undisclosed, dark: false)
        #expect(undisclosed.mark == .question)
        #expect(undisclosed.fill.hexString == "#E07000")
        let present = Tile.warnings(.present(count: 2), dark: false)
        #expect(present.mark == .exclamation)
        #expect(present.fill.hexString == "#C8102E")
        let complete = Tile.completion(.complete, dark: false)
        #expect(complete.mark == .check)
        #expect(complete.fill.hexString == "#2F8F3A")
        // WIP stays the board's soft orange, not a third solid orange.
        let wip = Tile.completion(.inProgress, dark: false)
        #expect(wip.mark == .halfRing)
        #expect(wip.fill.hexString == "#FFE6C2")
        #expect(wip.ink.hexString == "#B35A00")
    }

    /// WCAG 1.4.11's 3:1 between each tile and its glyph, in both appearances.
    @Test func everyGlyphHoldsThreeToOneOnItsTile() {
        for dark in [false, true] {
            for tile in everyTile(dark: dark) {
                #expect(tile.ink.contrastRatio(on: tile.fill) >= 3, "\(tile.mark) dark: \(dark)")
            }
        }
    }

    /// I-3: each drawn mark is centred on its own ink and fits its box, with no
    /// per-glyph offset.
    @Test func drawnMarksAreCentredOnTheirInk() {
        let marks: [Tile.Mark] = [
            .shield("G"), .gen, .femaleFemale, .femaleMale, .maleMale, .other, .dash, .check, .halfRing,
        ]
        for mark in marks {
            let bounds = Tile.path(for: mark, in: 100).cgPath.boundingBoxOfPath
            #expect(!bounds.isEmpty, "\(mark)")
            #expect(abs(bounds.midX - 50) < 0.01, "\(mark)")
            #expect(abs(bounds.midY - 50) < 0.01, "\(mark)")
            #expect(bounds.width <= 100 && bounds.height <= 100, "\(mark)")
        }
        #expect(Tile.path(for: .multi, in: 100).isEmpty)
    }

    /// I-2's 24pt grid is two tiles and a 0.12 gap: ~51pt, the row thumbnail's size.
    @Test func gridHeightIsTwoTilesAndOneGap() {
        #expect(abs(WorkStatusIconGrid.gridHeight(tileSize: 24) - 50.88) < 0.001)
    }

    /// I-1: no tray anywhere. The parameter is gone, so this guards against it
    /// (or a hand-rolled tray) coming back at a call site.
    @Test func noCallSitePassesATray() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "kudos-ao3-reader")
        let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var checked = 0
        for case let url as URL in files where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            #expect(!source.contains("showsTray"), "\(url.lastPathComponent)")
            #expect(!source.contains("trayHeight"), "\(url.lastPathComponent)")
            checked += 1
        }
        #expect(checked > 100)
    }
}
