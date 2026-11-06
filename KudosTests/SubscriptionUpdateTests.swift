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

    // The generated UniFFI binding is `#if os(iOS)`, so everything that names
    // `Reading`, `Ao3Event` or `Subscription` has to be too. Nothing catches this
    // today — Scripts/verify.sh runs the suite on the iOS simulator and only
    // BUILDS the macOS app — but the test target does list macosx, so an
    // unguarded reference breaks the first macOS test build anyone attempts.
    #if os(iOS)
    private func reading(
        uid: UInt32 = 4_201,
        identity: Identity = .work,
        kind: Ao3EventKind = .newChapter(number: 9),
        via: Subscription = .work(id: 83_701_926, name: "Honest Work"),
        verdict: Verdict = .trusted
    ) -> Reading {
        Reading(
            uid: uid,
            event: Ao3Event(
                identity: identity,
                kind: kind,
                at: Int64(when.timeIntervalSince1970),
                workId: 83_701_926,
                chapterId: 255_464_091,
                workTitle: "Honest Work",
                author: "skydarius11",
                via: via,
                chaptersPosted: 9,
                chaptersTotal: 13,
                words: 34_920,
                chapterTitle: "Chapter 9",
                chapterWords: 4_679,
                rating: nil,
                warnings: [],
                fandoms: [],
                relationships: [],
                characters: [],
                additionalTags: [],
                series: nil,
                summary: nil,
                extraCreations: 0
            ),
            verdict: verdict
        )
    }

    #endif

    private func make(
        uid: UInt32 = 4_201,
        contested: Bool = false,
        anchored: Bool = true,
        chapterID: UInt64? = 255_464_091,
        chapterNumber: Int? = 9,
        isNewWork: Bool = false,
        source: SubscriptionUpdate.Source = .work
    ) -> SubscriptionUpdate {
        SubscriptionUpdate(
            uid: uid,
            workID: 83_701_926,
            chapterID: chapterID,
            chapterNumber: chapterNumber,
            isNewWork: isNewWork,
            isContested: contested,
            isAnchoredToWork: anchored,
            workTitle: "Honest Work",
            author: "skydarius11",
            at: when,
            source: source
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
        let update = make(anchored: false, source: .author("skydarius11"))
        #expect(update.certainty == .workOnly)
        #expect(update.chapterID == nil)
        #expect(!update.canDeepLinkToChapter)
        #expect(!update.pinsTheWork, "an author subscription's footer names a user, not a work")
    }

    @Test("A non-work source can never become confirmed")
    func nonWorkSourceFailsClosed() {
        let update = make(anchored: true, source: .author("skydarius11"))
        #expect(update.certainty == .workOnly)
        #expect(update.chapterID == nil)
        #expect(!update.canDeepLinkToChapter)
    }

    /// A work subscription's footer *is* the work's own unsubscribe URL, so even a
    /// contested preface leaves the work itself AO3's. The screen needs the two
    /// cases apart: one may say "this work updated" and the other may not.
    @Test("Only a work subscription pins the work")
    func onlyAWorkSubscriptionPinsTheWork() {
        #expect(make(contested: true, source: .work).pinsTheWork)
        #expect(!make(anchored: false, source: .series("Winter Court")).pinsTheWork)
        #expect(!make(anchored: false, source: .author("marrowlight")).pinsTheWork)
        #expect(!make(anchored: false, source: .unknown).pinsTheWork,
                "an unparsed footer pins nothing at all")
    }

    /// The identity has to come from the message, not from its contents. Two
    /// contested notifications for one work in the same second agree on every
    /// field the id used to be built from — and an author can send that pair.
    @Test("Two contested updates for one work in the same second stay distinct")
    func contestedUpdatesDoNotCollide() {
        let first = make(uid: 1, contested: true)
        let second = make(uid: 2, contested: true)
        #expect(first.chapterID == nil)
        #expect(second.chapterID == nil)
        #expect(first.at == second.at)
        #expect(first.workID == second.workID)
        #expect(first.id != second.id, "duplicate ForEach ids are undefined behaviour in SwiftUI")
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

    /// Decision on the unpinned headline, recorded as a test so it is not
    /// quietly reverted either way. An author or series notification pins no
    /// work, so the body's title may not lead the row — but blanking it would
    /// reduce every such row to "Work #83701926". It is kept and attributed.
    @Test("An unpinned row keeps its title as a claim, not as the headline")
    func unpinnedTitleIsAClaim() {
        let unpinned = make(anchored: false, source: .author("marrowlight"))
        #expect(!unpinned.pinsTheWork)
        #expect(unpinned.workTitle == "Honest Work", "the title survives for the reader to judge")

        let pinned = make()
        #expect(pinned.pinsTheWork, "a work subscription's footer IS the work URL")
    }

    /// AO3 batches several creations into one email and the crate parses only the
    /// first, so the count of the rest has to reach the screen — otherwise one row
    /// silently stands in for several updates.
    @Test("A batch email's unparsed creations are carried, not dropped")
    func batchCountSurvives() {
        #expect(make().extraCreations == 0)

        let batch = SubscriptionUpdate(
            uid: 9, workID: 83_701_926, chapterID: 255_464_091, chapterNumber: 9,
            isNewWork: false, isContested: false, isAnchoredToWork: true,
            workTitle: "Honest Work", author: "skydarius11", at: when,
            source: .work, extraCreations: 2
        )
        #expect(batch.extraCreations == 2)
        #expect(batch.certainty == .confirmed, "a batch is not itself a reason to doubt")
    }

    #if os(iOS)
    @Test("A trusted UniFFI reading maps its UID and chapter")
    func mapsTrustedReading() throws {
        let update = try #require(SubscriptionUpdate(reading: reading(uid: 77)))
        #expect(update.uid == 77)
        #expect(update.chapterID == 255_464_091)
        #expect(update.change == .newChapter(number: 9))
        #expect(update.certainty == .confirmed)
        #expect(update.at == when)
    }

    /// Nothing unattested becomes a row. `Verdict.senderOnly` means only that a
    /// message claims to be from AO3, and a `From` address is trivially forged,
    /// so its work id, title and byline are all choosable by the sender. It was
    /// briefly admitted as a `.workOnly` row on the argument that refusing it
    /// discarded a watched folder's mail silently; that cannot be told apart
    /// from live mail with no provider to believe, because `read_new` yields
    /// senderOnly for a nil `authserv_id` too.
    @Test("Unattested readings never reach the screen")
    func refusesUnattestedReadings() {
        #expect(SubscriptionUpdate(reading: reading(verdict: .senderOnly)) == nil)
        #expect(SubscriptionUpdate(reading: reading(verdict: .rejected)) == nil)
    }

    @Test("Contested and body identities both drop the chapter")
    func ffiDoubtFailsClosed() throws {
        let contested = try #require(SubscriptionUpdate(reading: reading(kind: .contested)))
        let body = try #require(SubscriptionUpdate(reading: reading(identity: .body)))
        #expect(contested.change == .unknown)
        #expect(contested.chapterID == nil)
        #expect(body.certainty == .workOnly)
        #expect(body.chapterID == nil)
    }

    @Test("Every UniFFI subscription kind maps without guessing work")
    func mapsSources() throws {
        let work = try #require(SubscriptionUpdate(reading: reading())?.source)
        let series = try #require(SubscriptionUpdate(
            reading: reading(via: .series(id: 4021, name: nil))
        )?.source)
        let author = try #require(SubscriptionUpdate(
            reading: reading(via: .author(username: "marrowlight", name: nil))
        )?.source)
        let unknown = try #require(SubscriptionUpdate(reading: reading(via: .unknown))?.source)

        #expect(work == .work)
        #expect(series == .series("Series #4021"))
        #expect(author == .author("marrowlight"))
        #expect(unknown == .unknown)
    }

    /// The regression test for the bug this file previously let through:
    /// `mapsSources` only ever passed `name: nil`, so it pinned the fallback and
    /// never the preference, and the mapper preferred `name`.
    ///
    /// `name` is the footer SENTENCE. The crate's own fixture
    /// `f4_title_in_footer_moves_the_rule` shows a work title can end the layout
    /// rule early and plant a second sentence, producing
    /// `Author { username: "lamplighter", name: Some("impostor") }` — inside
    /// genuinely DKIM-signed mail. The username and the series id come from
    /// `polymorphic_url` and cannot be moved, so only they may caption a row.
    @Test("A forged footer name never becomes the subscription identity")
    func forgedNameLosesToTheURL() throws {
        let author = try #require(SubscriptionUpdate(
            reading: reading(via: .author(username: "lamplighter", name: "impostor"))
        )?.source)
        #expect(author == .author("lamplighter"), "the URL's login wins, not the sentence")

        let series = try #require(SubscriptionUpdate(
            reading: reading(via: .series(id: 4021, name: "Totally Different Series"))
        )?.source)
        #expect(series == .series("Series #4021"), "the URL's id wins, not the sentence")
    }

    @Test("A UniFFI new-work event stays a new work")
    func mapsNewWork() throws {
        let update = try #require(SubscriptionUpdate(reading: reading(kind: .newWork)))
        #expect(update.change == .newWork)
    }
    #endif
}
