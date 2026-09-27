import Foundation
import Testing
@testable import Kudos

/// The decisions behind the 1u / 1w / 1bn / 1bq / 1bo / 1br text on the writing
/// screens. Presentation only — none of these change what is posted to AO3.
@MainActor
struct WritingScreensPresentationTests {
    // MARK: 1u — Add Chapter only on a work in progress

    @Test func addChapterSwipeIsOfferedOnlyOnAWorkInProgress() {
        #expect(!AO3AuthorWorksSection.offersAddChapter(work(1, isComplete: true)))
        #expect(AO3AuthorWorksSection.offersAddChapter(work(2, isComplete: false)))
        // AO3 printing no completion is not proof the work is finished.
        #expect(AO3AuthorWorksSection.offersAddChapter(work(3, isComplete: nil)))
    }

    // MARK: 1w — hero tally

    @Test func seriesTallySumsTheLoadedSeries() {
        let parts = AuthorProfileView.seriesTallyParts(
            [series(1, works: 3, words: 118_600), series(2, works: 6, words: 100_700)],
            isPartial: false
        )
        #expect(parts == ["9 works", "219,300 words"])
    }

    /// With more series pages than loaded, one clause scopes both sums: "on
    /// this page" used to qualify the words alone, and stayed after every page
    /// had loaded.
    @Test func aPartialSeriesTallyScopesBothSumsToTheLoadedSeries() {
        let parts = AuthorProfileView.seriesTallyParts(
            [series(1, works: 2, words: 100), series(2, works: 7, words: 200)], isPartial: true
        )
        #expect(parts == ["9 works, 300 words in the 2 loaded series"])
        #expect(AuthorProfileView.seriesTallyParts([series(1, works: 1, words: nil)], isPartial: true)
            == ["1 work in the 1 loaded series"])
    }

    @Test func seriesTallyDropsAFigureAO3PrintedForNoSeries() {
        #expect(AuthorProfileView.seriesTallyParts([series(1, works: nil, words: nil)], isPartial: false).isEmpty)
        #expect(AuthorProfileView.seriesTallyParts([], isPartial: true).isEmpty)
        #expect(AuthorProfileView.seriesTallyParts([series(1, works: 2, words: nil)], isPartial: false)
            == ["2 works"])
    }

    // MARK: 1bn — select-mode chrome

    @Test func selectionCountIsChosenOfLoaded() {
        let works = [work(1), work(2), work(3)]
        #expect(AO3AuthorWorksSection.selectionCountText(selection: [1, 3], works: works) == "2 / 3")
        // A leftover id from before a refetch is not on screen and not counted.
        #expect(AO3AuthorWorksSection.selectionCountText(selection: [1, 99], works: works) == "1 / 3")
        #expect(AO3AuthorWorksSection.selectionCountText(selection: [], works: []) == "0 / 0")
    }

    @Test func selectAllTogglesOverTheLoadedWorksOnly() {
        let controller = RemoteWorkSelectionController()
        let works = [work(1), work(2)]
        controller.selection = [2, 99]
        #expect(!controller.allSelected(in: works))

        controller.toggleSelectAll(in: works)
        #expect(controller.selection == [1, 2, 99])
        #expect(controller.allSelected(in: works))

        controller.toggleSelectAll(in: works)
        #expect(controller.selection == [99])
        #expect(!controller.allSelected(in: []))
    }

    // MARK: 1bq — Add Chapter

    @Test func chapterHeaderNamesThePosition() {
        #expect(AddChapterView.subtitle(workTitle: "Water", chapterTitle: "Tide", position: "13")
            == "Water · chapter 13")
        #expect(AddChapterView.subtitle(workTitle: "Water", chapterTitle: "Tide", position: "")
            == "Water · Tide")
        #expect(AddChapterView.subtitle(workTitle: "Water", chapterTitle: "", position: "x")
            == "Water · chapter")
    }

    @Test func positionReadsAsAfterChapterAndPostsTheSameValue() {
        #expect(AddChapterView.afterChapterText(position: "13") == "12")
        #expect(AddChapterView.position(afterChapterText: "12") == "13")
        #expect(AddChapterView.position(afterChapterText: "0") == "1")
        // Untouched round trips: a number, and whatever is not a positive number.
        for raw in ["13", "1", "", "abc", "-2"] {
            #expect(AddChapterView.position(afterChapterText: AddChapterView.afterChapterText(position: raw))
                == raw)
        }
        #expect(AddChapterView.chapterNumber(" 7 ") == 7)
        #expect(AddChapterView.chapterNumber("0") == nil)
    }

    // MARK: 1bo / 1br / 1bq — editor rows

    @Test func editorRowDetailLine() {
        #expect(WritingTextEditorRow.detail(text: "", previewsText: true, emptyHint: "opens the editor.")
            == "Empty — opens the editor.")
        #expect(WritingTextEditorRow.detail(text: "", previewsText: true, emptyHint: nil) == nil)
        #expect(WritingTextEditorRow.detail(text: "<p>Gojo &amp; Nanami</p>", previewsText: true, emptyHint: nil)
            == "Gojo & Nanami")
        #expect(WritingTextEditorRow.detail(text: "Set text", previewsText: false, emptyHint: "x") == nil)
        // Markup with no words keeps the one-line "Set" row.
        #expect(WritingTextEditorRow.detail(text: "<p> </p>", previewsText: true, emptyHint: nil) == nil)
        #expect(WritingTextEditorRow.detail(text: "  ", previewsText: true, emptyHint: nil) == nil)
    }

    @Test func workEditSubtitleCarriesThePostedChapterCount() throws {
        let url = try #require(URL(string: "https://archiveofourown.org/works/1"))
        var form = AO3WorkForm(
            kind: .edit, actionURL: url, csrfToken: "", isDraft: false, isPosted: true,
            title: "The Weight of Water", chaptersPosted: 12
        )
        #expect(WorkEditView.subtitle(for: form) == "The Weight of Water · 12 chapters")
        form.chaptersPosted = 1
        #expect(WorkEditView.subtitle(for: form) == "The Weight of Water · 1 chapter")
        form.chaptersPosted = nil
        #expect(WorkEditView.subtitle(for: form) == "The Weight of Water")

        let draft = AO3WorkForm(
            kind: .draft, actionURL: url, csrfToken: "", isDraft: true, isPosted: false, chaptersPosted: 3
        )
        #expect(WorkEditView.subtitle(for: draft) == "Untitled · never posted")
    }

    // MARK: 1bo Chapters / 1bv chapter menu (T-267)

    @Test func deleteIsOfferedOnlyForAnExistingChapterOfSeveral() {
        #expect(AddChapterView.offersDelete(chapterID: 9, chapterCount: 2))
        #expect(!AddChapterView.offersDelete(chapterID: 9, chapterCount: 1))
        #expect(!AddChapterView.offersDelete(chapterID: 9, chapterCount: nil))
        #expect(!AddChapterView.offersDelete(chapterID: nil, chapterCount: 5))
    }

    @Test func theDeleteAlertNamesTheChapterAsAO3Does() {
        #expect(AddChapterView.chapterName(position: "13", title: "What the tide leaves")
            == "Chapter 13: What the tide leaves")
        #expect(AddChapterView.chapterName(position: "13", title: " ") == "Chapter 13")
        #expect(AddChapterView.chapterName(position: "", title: "Coda") == "Coda")
        #expect(WritingChaptersView.subtitle(workTitle: "Water", count: 1) == "Water · 1 chapter")
        #expect(WritingChaptersView.subtitle(workTitle: "Water", count: nil) == "Water")
    }

    @Test func pasteAsPlainTextReplacesTheSelection() {
        let controller = WritingTextController(text: "<p>one two</p>")
        let two = ("<p>one two</p>" as NSString).range(of: "two")
        #if os(iOS)
        controller.textView.selectedRange = two
        #else
        controller.textView.setSelectedRange(two)
        #endif
        controller.insertPlainText("three\nfour")
        #expect(controller.text == "<p>one three\nfour</p>")
        #expect(controller.takeCheckpoint() == "<p>one three\nfour</p>")
    }

    // MARK: Fixtures

    private func work(_ id: Int, isComplete: Bool? = nil) -> AO3WorkSummary {
        AO3WorkSummary(
            id: id, title: "Work \(id)", authors: [], fandoms: [], rating: "", warnings: [],
            categories: [], isComplete: isComplete, dateUpdated: "", tags: [], summary: "",
            language: "", chapters: ""
        )
    }

    private func series(_ id: Int, works: Int?, words: Int?) -> AO3SeriesSummary {
        AO3SeriesSummary(
            id: id, title: "Series \(id)", creatorNames: [], creatorIdentities: [], fandoms: [],
            summary: "", words: words, workCount: works, bookmarkCount: nil, dateUpdated: "",
            isComplete: nil, isRestricted: false,
            url: URL(string: "https://archiveofourown.org/series/\(id)")!
        )
    }
}
