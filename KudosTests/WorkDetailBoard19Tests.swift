import Foundation
import Testing
@testable import Kudos

/// Work Detail's pure pieces: symbol names, the 3×3 stats card, disclosure
/// digests and My copy models.
struct WorkDetailBoard19Tests {
    // MARK: Inline symbols

    @Test func inlineNamesFollowTileOrderInSentenceCase() {
        let names = WorkStatusIconGrid.inlineLabels(
            rating: "Teen And Up Audiences", categories: ["F/M"], warnings: ["No Archive Warnings Apply"],
            completion: .inProgress
        )
        #expect(names == ["Teen", "F/M", "No warnings", "WIP"])
    }

    @Test func inlineNamesSpeakUnknownStatesInsteadOfLeavingGaps() {
        let names = WorkStatusIconGrid.inlineLabels(
            rating: nil, categories: [], warnings: ["Creator Chose Not To Use Archive Warnings"],
            completion: .unknown
        )
        #expect(names == ["Not rated", "No category", "Not disclosed", "Unknown"])
    }

    @Test func inlineNamesListEveryRecognisedCategoryAndCountWarnings() {
        let names = WorkStatusIconGrid.inlineLabels(
            rating: "Mature", categories: ["F/F", "Gen", "Not a category"],
            warnings: ["Graphic Depictions Of Violence", "Major Character Death"], completion: .complete
        )
        #expect(names == ["Mature", "F/F, Gen", "2 warnings", "Complete"])
    }

    @Test func inlineRunIsBareLikeAStrip() {
        #expect(!WorkStatusIconGrid.drawsBacking(arrangement: .inline, backed: true))
        #expect(!WorkStatusIconGrid.drawsBacking(arrangement: .strip, backed: true))
    }

    // MARK: Version E disclosure digests

    @Test func tagsDigestCountsTheThreeWorkGroups() {
        #expect(WorkDetailDisclosure.tagsDigest(
            relationships: 1, characters: 3, additional: 4
        ) == "1 relationship · 3 characters · 4 more")
        #expect(WorkDetailDisclosure.tagsDigest(
            relationships: 2, characters: 1, additional: 0
        ) == "2 relationships · 1 character")
        #expect(WorkDetailDisclosure.tagsDigest(
            relationships: 0, characters: 0, additional: 0
        ) == "No AO3 tags")
    }

    @Test func tagLinksRoundTripAnyTagText() throws {
        for tag in ["Tenth Doctor & Donna Noble", "Ben Solo/Rey", "Doctor Who (2005)", "a?b#c%d", "Café"] {
            let url = try #require(WorkDetailTagLink.url(for: tag))
            #expect(WorkDetailTagLink.tag(from: url) == tag)
        }
        #expect(WorkDetailTagLink.tag(from: URL(string: "https://archiveofourown.org")!) == nil)
        let text = WorkDetailTagLink.text(["Tenth Doctor", "Donna Noble"])
        #expect(String(text.characters) == "Tenth Doctor, Donna Noble")
        #expect(text.runs.compactMap(\.link).count == 2)
    }

    @Test func seriesDigestClaimsNoSeriesSizeTheDeviceCannotKnow() {
        #expect(WorkDetailDisclosure.seriesDigest(title: "The Coast Road", position: 2)
            == "The Coast Road · part 2")
        #expect(WorkDetailDisclosure.seriesDigest(title: "The Coast Road", position: 0)
            == "The Coast Road")
    }

    // MARK: Stats card

    private func cells(
        words: Int? = 84_210, chapters: String = "12/20", kudos: Int? = 3_104, kudosGiven: Bool = false,
        hits: Int? = 41_200, comments: Int? = 286, bookmarks: Int? = 512,
        published: String = "2024-03-03", updated: String = "2024-10-21", language: String = "English"
    ) -> [WorkDetailStats.Cell] {
        WorkDetailStats.cells(
            words: words, chapters: chapters, kudos: kudos, kudosGiven: kudosGiven, hits: hits,
            comments: comments, bookmarks: bookmarks, published: published, updated: updated,
            language: language
        )
    }

    @Test func statsCardIsNineCellsInTheBoardsOrder() {
        #expect(cells().map(\.label) == [
            "Words", "Chapters", "Kudos", "Hits", "Comments", "Bookmarks", "Published", "Updated", "Language"
        ])
    }

    @Test func statsCardFormatsFigures() {
        let all = cells()
        #expect(all[0].value == 84_210.formatted())
        #expect(all[1].value == "12/20")
        #expect(all[2].value == 3_104.formatted())
        #expect(all[3].value == 41_200.compactCount)
        #expect(all[4].value == 286.compactCount)
        #expect(all[8].value == "English")
        #expect(all[0].accessibilityText == 84_210.formatted() + " words")
    }

    @Test func statsCardKeepsItsShapeWhenFieldsAreUnknown() {
        let all = cells(
            words: nil, chapters: " ", kudos: nil, hits: nil, comments: nil, bookmarks: nil,
            published: "", updated: "", language: ""
        )
        #expect(all.count == 9)
        #expect(all.allSatisfy { $0.value == WorkDetailStats.emptyFigure })
        #expect(all.allSatisfy { !$0.showsGivenHeart })
    }

    @MainActor @Test func assigningATagStampsTheWorkModified() {
        let work = SavedWork(title: "Tagged", author: "A")
        let before = Date(timeIntervalSince1970: 1)
        work.markModified(before)
        #expect(WorkDetailView.assign(Tag(name: "comfort"), to: work))
        #expect(work.lastModifiedAt > before)
        let stamped = work.lastModifiedAt
        #expect(!WorkDetailView.assign(Tag(name: "comfort"), to: work))
        #expect(work.lastModifiedAt == stamped)
    }

    @Test func kudosHeartShowsForAGivenWorkEvenWithoutAFigure() {
        #expect(cells(kudosGiven: true)[2].showsGivenHeart)
        #expect(cells(kudosGiven: true)[2].accessibilityText.hasSuffix("given by you"))
        #expect(!cells(kudosGiven: false)[2].showsGivenHeart)
        let unknown = cells(kudos: nil, kudosGiven: true)[2]
        #expect(unknown.showsGivenHeart)
        #expect(unknown.value == WorkDetailStats.emptyFigure)
        // No other cell ever carries the heart.
        #expect(cells(kudosGiven: true).filter(\.showsGivenHeart).count == 1)
    }

    @Test func statsCardPrintsShortDatesAndAddsTheYearWhenNotCurrent() {
        let now = Date(timeIntervalSince1970: 1_730_000_000) // Oct 2024
        #expect(WorkDetailStats.shortDate("2024-03-03", now: now) == "Mar 3")
        #expect(WorkDetailStats.shortDate("21 Oct 2023", now: now) == "Oct 21, 2023")
        #expect(WorkDetailStats.shortDate("garbled", now: now) == "garbled")
    }

    // MARK: My copy rows

    private func rows(
        progress: Double? = 0.58, chapterNumber: Int? = nil, downloadedAt: Date? = nil,
        tags: [String] = [], collections: [String] = [], queues: [String] = [],
        hasFile: Bool = true, fileSize: String? = "1.2 MB"
    ) -> [WorkDetailPresentation.MyCopyRow] {
        WorkDetailPresentation.myCopyRows(
            progress: progress, chapterNumber: chapterNumber, downloadedAt: downloadedAt, tags: tags,
            collections: collections, queues: queues, hasFile: hasFile, fileSize: fileSize
        )
    }

    @Test func myCopyRowsFollowTheBoardAndCarryTheirActions() {
        let all = rows()
        #expect(all.map(\.label) == ["Progress", "Downloaded", "Your Tags", "Collections", "Queues", "File"])
        #expect(all.map(\.action) == [nil, .edit, .add, .add, .add, nil])
    }

    @Test func myCopyCellsMoveProgressToTheReadingCardAndKeepEveryOtherFact() {
        let cells = WorkDetailPresentation.myCopyCells(from: rows())
        #expect(cells.map(\.kind) == [.downloaded, .file, .tags, .collections, .queues])
        #expect(cells.map(\.action) == [.edit, nil, .add, .add, .add])
    }

    @Test func myCopyProgressNamesTheChapterWhenKnown() {
        #expect(rows(chapterNumber: 7)[0].value == "Ch 7 · 58%")
        #expect(rows()[0].value == "58%")
        #expect(rows(progress: nil)[0].value == "Not started")
    }

    @Test func myCopyListsNamesAndSaysNoneWhenEmpty() {
        let filled = rows(tags: ["coast", "reread"], collections: ["Comfort Reads"], queues: ["Summer Reading"])
        #expect(filled[2].value == "coast, reread")
        #expect(filled[3].value == "Comfort Reads")
        #expect(filled[4].value == "Summer Reading")
        let empty = rows()
        #expect(empty[2].value == "None" && empty[3].value == "None" && empty[4].value == "None")
    }

    @Test func myCopyDownloadedDateAndFileRows() {
        let date = Date(timeIntervalSince1970: 1_729_468_800)
        #expect(rows(downloadedAt: date)[1].value == date.formatted(date: .abbreviated, time: .omitted))
        #expect(rows()[1].value == "Not recorded")
        #expect(rows()[5].value == "EPUB · 1.2 MB")
        #expect(rows(fileSize: nil)[5].value == "EPUB")
        #expect(rows(hasFile: false, fileSize: "1.2 MB")[5].value == "Not on this device")
    }
}
