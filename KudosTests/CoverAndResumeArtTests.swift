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

    @Test func readingMetaNamesPostedChaptersAndPercent() {
        #expect(WorkCoverMetadata.reading(chapters: "12/30", progress: 0.4) == "Ch 12 of 30 · 40%")
        #expect(WorkCoverMetadata.reading(chapters: "12/?", progress: 0.4) == "Ch 12 · 40%")
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
        #expect(model.displayedChapterName == "Ready to resume")
        #expect(model.workPercent == 0)
    }
}
