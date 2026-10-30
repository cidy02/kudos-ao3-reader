import Testing
@testable import Kudos

/// The one generated-art function, the cover's meta line, and the Resume card's
/// ring and bar inputs. No views: the same work has to pick the same art on
/// every surface, and the card copy has to stay a pure function of the work.
@Suite("Generated covers and Resume card")
struct CoverAndResumeArtTests {
    @Test func theSameWorkKeepsItsHueShadeAndLayout() {
        let first = CoverArt.workArt(fandoms: ["Sherlock Holmes"], title: "The Baker Street Irregular")
        let second = CoverArt.workArt(fandoms: ["Sherlock Holmes"], title: "The Baker Street Irregular")
        #expect(first == second)
        #expect(first.hue == (first.familyHue + first.shade + 360) % 360)
        #expect((0 ... 2).contains(first.layout))
    }

    @Test func titlesInOneFandomStayInsideTwelveDegrees() {
        let titles = ["First Work", "Another Work", "Salt", "The Empty Child"]
        let arts = titles.map { CoverArt.workArt(fandoms: ["Doctor Who"], title: $0) }
        let family = arts[0].familyHue
        #expect(arts.allSatisfy { $0.familyHue == family })
        #expect(arts.allSatisfy { (-12 ... 12).contains($0.shade) })
        #expect(Set(arts.map(\.shade)).count == titles.count)
        let again = CoverArt.workArt(fandoms: ["Doctor Who"], title: "Salt")
        #expect(again.layout == arts[2].layout)
    }

    @Test func aDifferentFandomChangesTheFamily() {
        let who = CoverArt.workArt(fandoms: ["Doctor Who"], title: "Salt")
        let holmes = CoverArt.workArt(fandoms: ["Sherlock Holmes"], title: "Salt")
        #expect(who.familyHue != holmes.familyHue)
        #expect(who.shade == holmes.shade)
    }

    @Test func readingMetaNamesTheChapterBeingRead() {
        // Posted and current differ: 0.4 of 30 equal chapters is chapter 13,
        // because the boundary belongs to the chapter it enters.
        let current = ChapterBarGeometry.readingChapter(posted: 30, progress: 0.4, weights: nil)
        #expect(current == 13)
        #expect(current != 30)
        #expect(WorkCoverMetadata.reading(chapters: "30/30", progress: 0.4) == "Ch 13 of 30 · 40%")
        #expect(WorkCoverMetadata.reading(chapters: "12/30", progress: 0.4) == "Ch 5 of 30 · 40%")
        #expect(WorkCoverMetadata.reading(chapters: "12/?", progress: 0.4) == "Ch 5 · 40%")
        #expect(WorkCoverMetadata.reading(chapters: "", progress: 1) == "100%")
    }

    @Test func downloadedMetaJoinsDateAndSize() {
        #expect(WorkCoverMetadata.downloaded(date: "Oct 21", size: "1.2 MB") == "Oct 21 · 1.2 MB")
        #expect(WorkCoverMetadata.downloaded(date: "Oct 21", size: nil) == "Oct 21")
        #expect(WorkCoverMetadata.downloaded(date: nil, size: nil) == nil)
        #expect(WorkCoverMetadata.downloaded(date: "", size: "") == nil)
    }

    @Test func updateBadgeKeepsALeadingCount() {
        #expect(WorkCoverMetadata.updateBadge(from: "+3 new") == "+3")
        #expect(WorkCoverMetadata.updateBadge(from: "+12") == "+12")
        #expect(WorkCoverMetadata.updateBadge(from: "Updated") == nil)
        #expect(WorkCoverMetadata.updateBadge(from: "Finished") == nil)
    }

    @Test func resumeRingAndBarsFollowTheWork() {
        let model = ResumeCardModel(
            title: "The Salt Road",
            authors: ["wren"],
            authorIdentities: [],
            fandoms: ["Original Work"],
            rating: "T",
            categories: ["F/M"],
            warnings: [],
            completion: .inProgress,
            words: 84_210,
            kudos: 3_104,
            chapters: "12/20",
            progress: 0.58,
            chapterProgress: 0.22,
            chapterName: "Ch 7, The Salt Road",
            published: "Mar 3",
            updated: "Oct 21",
            newChapterCount: 2
        )
        #expect(model.workPercent == 58)
        #expect(model.chapterPercent == 22)
        #expect(model.postedChapters == 12)
        #expect(model.plannedChapters == 20)
        #expect(model.chapterNumber == 7)
        #expect(model.postedLabel == "12 of 20 posted")
        #expect(model.figureLine == "\(84_210.formatted()) words · ♥ \(3_104.formatted())")
        #expect(ResumeCardVariant.home.barsHeight == 52)
        #expect(ResumeCardVariant.next.barsHeight == 52)
        #expect(ResumeCardVariant.detail.barsHeight == 76)
        let items = model.chapterItems(weights: nil)
        #expect(items.count == 20)
        #expect(items.filter { if case .notPosted = $0.role { return true }; return false }.count == 8)
    }

    @Test func anUnreadCompleteWorkNamesItsChapters() {
        let model = ResumeCardModel(
            title: "One-shot",
            authors: [],
            authorIdentities: [],
            fandoms: [],
            rating: "",
            categories: [],
            warnings: [],
            completion: .complete,
            words: nil,
            kudos: nil,
            chapters: "1/1",
            progress: 0,
            chapterProgress: nil,
            chapterName: nil,
            published: "",
            updated: "",
            newChapterCount: 0
        )
        #expect(model.postedLabel == "1 chapter")
        #expect(model.displayedChapterName == "Not started")
        #expect(model.workPercent == 0)
    }

    @Test func workArtMatchesTheFandomPageHue() {
        let holmes = CoverArt.workArt(fandoms: ["Sherlock Holmes"], title: "The Baker Street Irregular")
        #expect(holmes.familyHue == 280)
        #expect(holmes.shade == 2)
        #expect(holmes.hue == 282)
        #expect(holmes.layout == 0)
        #expect(CoverArt.hue(for: "Sherlock Holmes") == Double(holmes.familyHue) / 360)
        #expect(
            CoverArt.workHue(fandoms: ["Sherlock Holmes"], title: "The Baker Street Irregular")
                == CoverArt.hue(for: "Sherlock Holmes")
        )

        let salt = CoverArt.workArt(fandoms: ["Doctor Who"], title: "Salt")
        #expect(salt.familyHue == 78)
        #expect(salt.shade == -6)
        #expect(salt.hue == 72)
        #expect(salt.layout == 0)
        #expect(CoverArt.workHue(fandoms: ["Doctor Who"], title: "Salt") == CoverArt.hue(for: "Doctor Who"))

        let first = CoverArt.workArt(fandoms: ["Doctor Who"], title: "First Work")
        #expect(first.familyHue == salt.familyHue)
        #expect(first.shade == 12)
        #expect(first.hue == 90)
        #expect(first.layout == 2)

        let original = CoverArt.workArt(fandoms: ["Original Work"], title: "The Salt Road")
        #expect(original.familyHue == 173)
        #expect(original.shade == -6)
        #expect(original.hue == 167)
        #expect(original.layout == 2)
        #expect(
            CoverArt.workHue(fandoms: ["Original Work"], title: "The Salt Road")
                == CoverArt.hue(for: "Original Work")
        )

        let blankFandom = CoverArt.workArt(fandoms: ["   "], title: "The Salt Road")
        #expect(blankFandom.familyHue == 120)
        #expect(CoverArt.hue(for: "The Salt Road") == Double(blankFandom.familyHue) / 360)
        #expect(blankFandom.familyHue != original.familyHue)
    }

    @Test func chapterProgressReadsTheInChapterFraction() {
        #expect(WorkReadingPosition.chapterProgress(
            from: #"{"title":"Chapter 2","locations":{"progression":0.5,"totalProgression":0.25}}"#
        ) == 0.5)
        #expect(WorkReadingPosition.chapterProgress(from: #"{"locations":{"progression":1.5}}"#) == 1)
        #expect(WorkReadingPosition.chapterProgress(from: #"{"locations":{"progression":-0.2}}"#) == 0)
        #expect(WorkReadingPosition.chapterProgress(from: #"{"locations":{"totalProgression":0.4}}"#) == nil)
        #expect(WorkReadingPosition.chapterProgress(from: "{}") == nil)
        #expect(WorkReadingPosition.chapterProgress(from: "not json") == nil)
    }

    @Test func coverMetaLinePrefersDownloadThenReadingThenFooter() {
        #expect(WorkCoverMetadata.line(
            style: .downloaded,
            downloadedDate: "Oct 21",
            downloadedSize: "1.2 MB",
            progress: 0.4,
            chapters: "15/30",
            footer: "Finished",
            words: 118_000
        ) == "Oct 21 · 1.2 MB")

        #expect(WorkCoverMetadata.line(
            style: .standard,
            downloadedDate: nil,
            downloadedSize: nil,
            progress: 0.4,
            chapters: "30/30",
            footer: "Finished",
            words: 118_000
        ) == "Ch 13 of 30 · 40%")

        #expect(WorkCoverMetadata.line(
            style: .standard,
            downloadedDate: nil,
            downloadedSize: nil,
            progress: nil,
            chapters: "15/30",
            footer: "Finished",
            words: 118_000
        ) == "Finished")

        let words = "\(118_000.compactCount) words · 15/30"
        #expect(WorkCoverMetadata.line(
            style: .standard,
            downloadedDate: nil,
            downloadedSize: nil,
            progress: nil,
            chapters: "15/30",
            footer: "+3 new",
            words: 118_000
        ) == words)
        #expect(WorkCoverMetadata.chaptersOnly("15/30") == "15/30")
        #expect(WorkCoverMetadata.chaptersOnly("  ") == nil)
        #expect(WorkCoverMetadata.dropsWordsBeforeChapters(style: .standard, progress: nil, footer: "+3 new"))
        #expect(!WorkCoverMetadata.dropsWordsBeforeChapters(style: .downloaded, progress: nil, footer: nil))
        #expect(!WorkCoverMetadata.dropsWordsBeforeChapters(style: .standard, progress: 0.4, footer: nil))
        #expect(!WorkCoverMetadata.dropsWordsBeforeChapters(style: .standard, progress: nil, footer: "Finished"))
    }

    @Test func resumeProgressClampsAndAnUnopenedWorkInventsNothing() {
        let over = resume(progress: 1.4, chapterProgress: 2)
        #expect(over.progress == 1)
        #expect(over.chapterProgress == 1)
        #expect(over.workPercent == 100)
        #expect(over.chapterPercent == 100)

        let under = resume(progress: -0.2, chapterProgress: -1)
        #expect(under.progress == 0)
        #expect(under.chapterProgress == 0)

        let unopened = resume(progress: nil, chapterProgress: nil)
        #expect(unopened.progress == nil)
        #expect(unopened.detailProgressLine == nil)
        #expect(unopened.detailPrimaryTitle(fallback: "Read") == "Read")

        let chapterOnly = resume(progress: nil, chapterProgress: 0.5)
        #expect(chapterOnly.detailProgressLine == nil)
        #expect(chapterOnly.detailPrimaryTitle(fallback: "Read") == "Read")

        let noChapterFraction = resume(progress: 0.4, chapterProgress: nil)
        #expect(noChapterFraction.detailProgressLine == "40% of the work")
        #expect(noChapterFraction.detailPrimaryTitle(fallback: "Read").hasPrefix("Resume Chapter "))
    }

    private func resume(progress: Double?, chapterProgress: Double?) -> ResumeCardModel {
        ResumeCardModel(
            title: "The Salt Road",
            authors: ["wren"],
            authorIdentities: [],
            fandoms: ["Original Work"],
            rating: "T",
            categories: [],
            warnings: [],
            completion: .inProgress,
            words: 84_210,
            kudos: nil,
            chapters: "12/20",
            progress: progress,
            chapterProgress: chapterProgress,
            chapterName: nil,
            published: "",
            updated: "",
            newChapterCount: 0
        )
    }
}
