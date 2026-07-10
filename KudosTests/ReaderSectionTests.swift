import Foundation
import Testing
@testable import Kudos

/// Covers the AO3 EPUB Preface/Summary/Chapter/Afterword normalization
/// (`ReaderSection`/`ReaderSectionBuilder`). Regression scenarios mirror a real
/// AO3/Calibre export (`The_Queens_Mercy.epub`: 104 spine items, 103 TOC nav
/// points — Preface, an untitled Summary gap, 95 numbered chapters, 6 "Epilogue:
/// Chapter N" entries, Afterword; Preface page text reads "Chapters: 101/101"),
/// reconstructed synthetically here rather than bundling a real, specific fanwork.
struct ReaderSectionTests {
    // MARK: - Helpers

    private typealias Raw = ReaderSectionBuilder.RawTOCEntry

    /// A spine of `count` placeholder hrefs — content doesn't matter to the
    /// builder, only position and count.
    private func spine(_ count: Int) -> [String] {
        (0 ..< count).map { "split_\($0).xhtml" }
    }

    /// The reference EPUB's exact shape: Preface(0), [gap → Summary](1),
    /// Chapter 1-95 (2...96), Epilogue: Chapter 1-6 (97...102), Afterword(103).
    /// 104 spine items, 103 TOC entries (Summary omitted, matching real AO3 export).
    private func referenceEPUBTOC() -> [Raw] {
        var entries = [Raw(title: "Preface", spineIndex: 0)]
        for chapter in 1 ... 95 {
            entries.append(Raw(title: "Chapter \(chapter)", spineIndex: chapter + 1))
        }
        for epilogue in 1 ... 6 {
            entries.append(Raw(title: "Epilogue: Chapter \(epilogue)", spineIndex: 96 + epilogue))
        }
        entries.append(Raw(title: "Afterword", spineIndex: 103))
        return entries
    }

    // MARK: - Reference EPUB assertions (spec's own checklist)

    @Test func referenceEPUBIndexIncludesEveryRequiredSection() {
        let sections = ReaderSectionBuilder.build(tocEntries: referenceEPUBTOC(), spineHrefs: spine(104))

        #expect(sections.count == 104)
        #expect(sections[0].kind == .preface)
        #expect(sections[0].title == "Preface")
        #expect(sections[1].kind == .summary)
        #expect(sections[1].title == "Summary")
        // Summary sits strictly between Preface and Chapter 1.
        #expect(sections[1].spineIndex > sections[0].spineIndex)
        #expect(sections[2].kind == .chapter)
        #expect(sections[2].title == "Chapter 1")
        #expect(sections[103].kind == .afterword)
        #expect(sections[103].title == "Afterword")

        let storyChapters = sections.filter { $0.kind == .chapter }
        #expect(storyChapters.count == 101) // 95 numbered + 6 epilogue
        // Real chapter titles are preserved verbatim, not renamed.
        #expect(storyChapters.first?.title == "Chapter 1")
        #expect(storyChapters.last?.title == "Epilogue: Chapter 6")
    }

    @Test func referenceEPUBPillLabelsMatchSpecExactly() {
        let sections = ReaderSectionBuilder.build(tocEntries: referenceEPUBTOC(), spineHrefs: spine(104))
        let total = SavedWork.totalChapterCount(from: "101/101") ?? sections.storyChapterCount
        #expect(total == 101)

        #expect(sections[0].pillLabel(storyChapterTotal: total) == "P")
        #expect(sections[1].pillLabel(storyChapterTotal: total) == "S")
        #expect(sections[2].pillLabel(storyChapterTotal: total) == "1/101") // real Chapter 1
        #expect(sections[103].pillLabel(storyChapterTotal: total) == "A")
        // Last story chapter (Epilogue: Chapter 6, spine 102) is the 101st chapter.
        #expect(sections[102].pillLabel(storyChapterTotal: total) == "101/101")
    }

    @Test func referenceEPUBDenominatorExcludesFrontAndBackMatter() {
        let sections = ReaderSectionBuilder.build(tocEntries: referenceEPUBTOC(), spineHrefs: spine(104))
        // Without AO3's own "Chapters: X/Y", the fallback must still exclude
        // Preface/Summary/Afterword from the denominator (101, not 104).
        #expect(sections.storyChapterCount == 101)
    }

    @Test func referenceEPUBEveryChapterIsNavigableAndSpineOrdered() {
        let sections = ReaderSectionBuilder.build(tocEntries: referenceEPUBTOC(), spineHrefs: spine(104))
        // spineIndex is monotonically increasing — index order == spine order.
        #expect(sections.map(\.spineIndex) == Array(0 ..< 104))
        #expect(sections.map(\.href) == spine(104))
    }

    // MARK: - Spec's own regression matrix

    @Test func epubWithoutAfterwordHasNoAfterwordSection() {
        var entries = [Raw(title: "Preface", spineIndex: 0)]
        entries.append(contentsOf: (1 ... 3).map { Raw(title: "Chapter \($0)", spineIndex: $0 + 1) })
        let sections = ReaderSectionBuilder.build(tocEntries: entries, spineHrefs: spine(5))

        #expect(!sections.contains { $0.kind == .afterword })
        #expect(sections[1].kind == .summary) // gap synthesis still fires without an Afterword present
        #expect(sections.storyChapterCount == 3)
    }

    @Test func singleChapterAO3Work() {
        let entries = [Raw(title: "Preface", spineIndex: 0), Raw(title: "Chapter 1", spineIndex: 2)]
        let sections = ReaderSectionBuilder.build(tocEntries: entries, spineHrefs: spine(3))

        #expect(sections[1].kind == .summary)
        #expect(sections[2].kind == .chapter)
        #expect(sections[2].storyChapterIndex == 1)
        #expect(sections.storyChapterCount == 1)
        #expect(sections[2].pillLabel(storyChapterTotal: 1) == "1/1")
    }

    @Test func multipleChapterAO3Work() {
        let entries = [Raw(title: "Preface", spineIndex: 0)]
            + (1 ... 10).map { Raw(title: "Chapter \($0)", spineIndex: $0 + 1) }
            + [Raw(title: "Afterword", spineIndex: 12)]
        let sections = ReaderSectionBuilder.build(tocEntries: entries, spineHrefs: spine(13))

        #expect(sections.storyChapterCount == 10)
        #expect(sections.filter { $0.kind == .chapter }.map(\.storyChapterIndex) == Array(1 ... 10))
    }

    @Test func summaryMissingFromTOCIsSynthesizedExactlyOnce() {
        // The exact bug: TOC jumps from Preface straight to Chapter 1 with no
        // Summary entry, even though the spine has an item in between.
        let entries = [Raw(title: "Preface", spineIndex: 0), Raw(title: "Chapter 1", spineIndex: 2)]
        let sections = ReaderSectionBuilder.build(tocEntries: entries, spineHrefs: spine(3))

        #expect(sections.filter { $0.kind == .summary }.count == 1)
        #expect(sections[1].title == "Summary")
    }

    @Test func summaryAlreadyInTOCIsNotDuplicated() {
        // A future/different EPUB that DOES list Summary in its own TOC — must
        // not also get a synthesized second Summary entry.
        let entries = [
            Raw(title: "Preface", spineIndex: 0),
            Raw(title: "Summary", spineIndex: 1),
            Raw(title: "Chapter 1", spineIndex: 2)
        ]
        let sections = ReaderSectionBuilder.build(tocEntries: entries, spineHrefs: spine(3))

        #expect(sections.filter { $0.kind == .summary }.count == 1)
        #expect(sections[1].title == "Summary")
    }

    @Test func nonAO3EPUBsAreCompletelyUnaffected() throws {
        // The real bundled non-AO3 fixture: no Preface entry at all, so the
        // AO3-specific gate never opens — every item is just a numbered chapter,
        // identical to the pre-normalization behavior.
        let doc = try EPUBDocument.open(epubURL: try EPUBTests.sampleEPUB, into: freshTempDir())
        let sections = ReaderSectionBuilder.build(
            tocEntries: doc.chapters.map { Raw(title: $0.title, spineIndex: $0.spineIndex) },
            spineHrefs: doc.spineURLs.map(\.absoluteString)
        )

        #expect(sections.allSatisfy { $0.kind == .chapter })
        #expect(sections.map(\.title) == ["Chapter One", "Chapter Two"])
        #expect(sections.map(\.storyChapterIndex) == [1, 2])
        #expect(sections.storyChapterCount == 2)
    }

    private func freshTempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    // MARK: - Empty / missing TOC fallback (mirrors EPUBDocument's own fallback)

    @Test func emptyTOCFallsBackToOneChapterPerSpineItem() {
        let sections = ReaderSectionBuilder.build(
            tocEntries: (0 ..< 4).map { Raw(title: "Section \($0 + 1)", spineIndex: $0) },
            spineHrefs: spine(4)
        )
        #expect(sections.allSatisfy { $0.kind == .chapter })
        #expect(sections.storyChapterCount == 4)
    }

    @Test func emptySpineProducesNoSections() {
        #expect(ReaderSectionBuilder.build(tocEntries: [], spineHrefs: []).isEmpty)
    }

    // MARK: - AO3 total-chapter-count parsing

    @Test func totalChapterCountPrefersAO3PostedTotal() {
        #expect(SavedWork.totalChapterCount(from: "101/101") == 101)
        #expect(SavedWork.totalChapterCount(from: "5/10") == 10)
    }

    @Test func totalChapterCountIsNilForUnknownOrMissingStats() {
        #expect(SavedWork.totalChapterCount(from: "5/?") == nil) // AO3's own "unknown total" WIP marker
        #expect(SavedWork.totalChapterCount(from: "") == nil)
        #expect(SavedWork.totalChapterCount(from: "garbage") == nil)
    }

    @Test func fallsBackToSectionCountWhenAO3TotalUnknown() {
        let sections = ReaderSectionBuilder.build(tocEntries: referenceEPUBTOC(), spineHrefs: spine(104))
        let total = SavedWork.totalChapterCount(from: "5/?") ?? sections.storyChapterCount
        #expect(total == 101)
    }

    // MARK: - hrefKey normalization (used to resolve Readium `Link.href`s to spine indices)

    @Test func hrefKeyStripsFragmentsAndPathPrefixesCaseInsensitively() {
        #expect(ReaderSectionBuilder.hrefKey("OEBPS/Text/ch1.xhtml#section1")
            == ReaderSectionBuilder.hrefKey("Text/CH1.XHTML"))
        #expect(ReaderSectionBuilder.hrefKey("a.xhtml") != ReaderSectionBuilder.hrefKey("b.xhtml"))
    }

    // MARK: - ao3StoryChapter mapping (reader position → AO3 comment chapter)

    /// The spec's reference table over the real EPUB shape: Preface(0),
    /// Summary(1), Chapter 1-95(2...96), Epilogue 1-6(97...102 → story 96-101),
    /// Afterword(103). 101 story chapters.
    @Test func mapsReaderPositionToAO3StoryChapterAcrossFrontAndBackMatter() {
        let sections = ReaderSectionBuilder.build(tocEntries: referenceEPUBTOC(), spineHrefs: spine(104))

        #expect(sections.ao3StoryChapter(forSpineIndex: 0) == 1)   // Preface → Ch 1
        #expect(sections.ao3StoryChapter(forSpineIndex: 1) == 1)   // Summary → Ch 1
        #expect(sections.ao3StoryChapter(forSpineIndex: 2) == 1)   // Chapter 1 → 1
        #expect(sections.ao3StoryChapter(forSpineIndex: 6) == 5)   // Chapter 5 → 5
        #expect(sections.ao3StoryChapter(forSpineIndex: 96) == 95) // Chapter 95 → 95
        #expect(sections.ao3StoryChapter(forSpineIndex: 97) == 96) // Epilogue 1 → story 96
        #expect(sections.ao3StoryChapter(forSpineIndex: 102) == 101) // final story chapter
        #expect(sections.ao3StoryChapter(forSpineIndex: 103) == 101) // Afterword → last chapter
    }

    @Test func singleChapterWorkWithFrontMatterAlwaysMapsToChapter1() {
        // Preface(0), untitled Summary gap(1), Chapter 1(2).
        let toc = [Raw(title: "Preface", spineIndex: 0), Raw(title: "Chapter 1", spineIndex: 2)]
        let sections = ReaderSectionBuilder.build(tocEntries: toc, spineHrefs: spine(3))

        #expect(sections.storyChapterCount == 1)
        #expect(sections.ao3StoryChapter(forSpineIndex: 0) == 1) // Preface
        #expect(sections.ao3StoryChapter(forSpineIndex: 1) == 1) // Summary
        #expect(sections.ao3StoryChapter(forSpineIndex: 2) == 1) // the one chapter
    }

    @Test func mapsWorkWithNoAfterword() {
        // Preface(0), Summary(1), Chapter 1(2), Chapter 2(3) — no back matter.
        let toc = [Raw(title: "Preface", spineIndex: 0),
                   Raw(title: "Chapter 1", spineIndex: 2),
                   Raw(title: "Chapter 2", spineIndex: 3)]
        let sections = ReaderSectionBuilder.build(tocEntries: toc, spineHrefs: spine(4))

        #expect(sections[1].kind == .summary)
        #expect(sections.ao3StoryChapter(forSpineIndex: 3) == 2) // final chapter, no afterword
    }

    @Test func mapsWorkWithPrefaceButNoSummaryGap() {
        // Preface immediately followed by Chapter 1 (no untitled gap → no Summary).
        let toc = [Raw(title: "Preface", spineIndex: 0),
                   Raw(title: "Chapter 1", spineIndex: 1),
                   Raw(title: "Chapter 2", spineIndex: 2)]
        let sections = ReaderSectionBuilder.build(tocEntries: toc, spineHrefs: spine(3))

        #expect(!sections.contains { $0.kind == .summary })
        #expect(sections.ao3StoryChapter(forSpineIndex: 0) == 1) // Preface → Ch 1
        #expect(sections.ao3StoryChapter(forSpineIndex: 2) == 2) // Chapter 2
    }

    @Test func nonAO3EPUBMapsEverySpineItemToItsOwnChapter() {
        // No Preface entry → every spine item is a plain .chapter, numbered by order
        // (today's unchanged behavior; the naive index happens to be correct here).
        let toc = [Raw(title: "Intro", spineIndex: 0),
                   Raw(title: "Middle", spineIndex: 1),
                   Raw(title: "End", spineIndex: 2)]
        let sections = ReaderSectionBuilder.build(tocEntries: toc, spineHrefs: spine(3))

        #expect(sections.storyChapterCount == 3)
        #expect(sections.ao3StoryChapter(forSpineIndex: 0) == 1)
        #expect(sections.ao3StoryChapter(forSpineIndex: 2) == 3)
    }

    @Test func unmappableSectionAndOutOfRangeFallBackToChapter1() {
        // A stray cover (.other, no TOC entry, no Preface) before Chapter 1.
        let toc = [Raw(title: "Chapter 1", spineIndex: 1)]
        let sections = ReaderSectionBuilder.build(tocEntries: toc, spineHrefs: spine(2))

        #expect(sections[0].kind == .other)
        #expect(sections.ao3StoryChapter(forSpineIndex: 0) == 1)  // .other before Ch 1 → 1
        #expect(sections.ao3StoryChapter(forSpineIndex: 99) == 1) // out of range → 1
        #expect([ReaderSection]().ao3StoryChapter(forSpineIndex: 0) == 1) // empty → 1
    }

    // MARK: - Comments-layer clamp (target chapter → live /navigate index)

    @Test func clampedChapterPositionStaysInRangeOrNilWhenNoChapters() {
        #expect(CommentsModel.clampedChapterPosition(3, chapterCount: 10) == 3)
        #expect(CommentsModel.clampedChapterPosition(0, chapterCount: 10) == 1)  // floor
        #expect(CommentsModel.clampedChapterPosition(99, chapterCount: 10) == 10) // ceil → last
        #expect(CommentsModel.clampedChapterPosition(1, chapterCount: 1) == 1)   // single chapter
        #expect(CommentsModel.clampedChapterPosition(5, chapterCount: 0) == nil) // no index → All
    }
}
