import Foundation
import Testing
@testable import Kudos

/// `SubscriptionUpdate` is where `kudos-mail-core`'s caution either survives into
/// the UI or is thrown away.
///
/// The crate went through thirteen adversarial review passes to reach one rule:
/// when a notification's preface cannot be told from an AO3 author's imitation of
/// one, report nothing read from it rather than guess. An author controls the work
/// title, the chapter title, the summaries and the tag values, and all of it
/// arrives inside genuinely DKIM-signed mail. The crate signals the two failures
/// separately — `Ao3EventKind.contested` (the preface lost) and `Identity.body`
/// (nothing pinned the work) — and either one must stop the screen claiming a
/// chapter, because a chapter id is what a deep link and an unread count are built
/// from.
struct SubscriptionUpdateTests {
    private let when = Date(timeIntervalSince1970: 1_762_000_000)

    private func make(
        contested: Bool = false,
        anchored: Bool = true,
        chapterID: UInt64? = 255_464_091,
        chapterNumber: Int? = 9,
        isNewWork: Bool = false
    ) -> SubscriptionUpdate {
        SubscriptionUpdate(
            workID: 83_701_926,
            chapterID: chapterID,
            chapterNumber: chapterNumber,
            isNewWork: isNewWork,
            isContested: contested,
            isAnchoredToWork: anchored,
            workTitle: "Honest Work",
            author: "skydarius11",
            at: when
        )
    }

    @Test("An ordinary chapter notification keeps everything AO3 said")
    func confirmedChapter() {
        let update = make()
        #expect(update.certainty == .confirmed)
        #expect(update.workID == 83_701_926)
        #expect(update.chapterID == 255_464_091)
        #expect(update.change == .newChapter(number: 9))
        #expect(update.workTitle == "Honest Work")
        #expect(update.canDeepLinkToChapter)
    }

    @Test("A contested preface drops the chapter, the title and the author")
    func contestedKeepsOnlyTheWork() {
        let update = make(contested: true)
        #expect(update.certainty == .workOnly)
        #expect(update.workID == 83_701_926, "the footer's work id is still AO3's")
        #expect(update.chapterID == nil, "a contested preface must never yield a chapter")
        #expect(update.change == .unknown)
        #expect(update.workTitle.isEmpty)
        #expect(update.author.isEmpty)
        #expect(!update.canDeepLinkToChapter)
    }

    /// An author or series subscription pins nothing: AO3's footer names a user or
    /// a series, so which work changed was only ever read from the body.
    @Test("An unanchored event may not claim a chapter either")
    func unanchoredKeepsOnlyTheWork() {
        let update = make(anchored: false)
        #expect(update.certainty == .workOnly)
        #expect(update.chapterID == nil)
        #expect(!update.canDeepLinkToChapter)
    }

    /// The nastiest shape: the crate read a chapter id, but the preface that
    /// produced it was contested. The id must not survive just because it exists.
    @Test("A chapter id present on a contested event is still dropped")
    func contestedDropsAPresentChapterID() {
        let update = make(contested: true, chapterID: 1, chapterNumber: 1)
        #expect(update.chapterID == nil)
        #expect(update.change == .unknown)
    }

    @Test("A new work with no chapter is confirmed, not contested")
    func confirmedNewWork() {
        let update = make(chapterID: nil, chapterNumber: nil, isNewWork: true)
        #expect(update.certainty == .confirmed)
        #expect(update.change == .newWork)
        #expect(!update.canDeepLinkToChapter, "a new work has no chapter to open")
    }

    /// Both failures at once must not cancel out into something confident.
    @Test("Contested and unanchored together stay workOnly")
    func bothFailuresStayWorkOnly() {
        let update = make(contested: true, anchored: false)
        #expect(update.certainty == .workOnly)
        #expect(update.chapterID == nil)
        #expect(update.change == .unknown)
    }
}
