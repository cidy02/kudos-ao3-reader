import Foundation
import Testing
@testable import Kudos

/// Tests work-origin detection and the preservation states the Library badges read.
struct WorkOriginTests {
    @Test func detectsTheSitesFanficActuallyComesFrom() {
        #expect(WorkOrigin.detect(sourceURL: "https://archiveofourown.org/works/12345") == .archiveOfOurOwn)
        #expect(WorkOrigin.detect(sourceURL: "https://www.fanfiction.net/s/13100/1/") == .fanfictionNet)
        #expect(WorkOrigin.detect(sourceURL: "https://m.fanfiction.net/s/13100/1/") == .fanfictionNet)
        #expect(WorkOrigin.detect(sourceURL: "https://www.wattpad.com/story/1234-title") == .wattpad)
        #expect(WorkOrigin.detect(sourceURL: "https://www.fictionpress.com/s/999/1/") == .fictionPress)
        #expect(WorkOrigin.detect(sourceURL: "https://forums.spacebattles.com/threads/x.1/") == .spaceBattles)
        #expect(WorkOrigin.detect(sourceURL: "https://squidgeworld.org/works/500") == .squidgeWorld)
    }

    @Test func noSourceURLMeansAnImportedFile() {
        // The community-copy case: a file handed over with no site behind it.
        #expect(WorkOrigin.detect(sourceURL: "") == .importedFile)
        #expect(WorkOrigin.detect(sourceURL: "   ") == .importedFile)
    }

    @Test func anUnrecognisedSiteIsReportedAsOtherRatherThanGuessed() {
        #expect(WorkOrigin.detect(sourceURL: "https://someones-blog.example/fic/1") == .unknown)
    }

    @Test func onlyTheHostIsMatched() {
        // A fic hosted on AO3 whose URL happens to mention another archive must not be
        // filed under it — matching the whole string would do exactly that.
        let url = "https://archiveofourown.org/works/1?note=mirrored-from-fanfiction.net"
        #expect(WorkOrigin.detect(sourceURL: url) == .archiveOfOurOwn)
    }

    @Test func onlyAO3SupportsLiveLookup() {
        // This is what stops the UI offering kudos or a tag refresh on a work whose
        // site Kudos cannot talk to.
        #expect(WorkOrigin.archiveOfOurOwn.supportsLiveLookup)
        #expect(!WorkOrigin.fanfictionNet.supportsLiveLookup)
        #expect(!WorkOrigin.importedFile.supportsLiveLookup)
        #expect(!WorkOrigin.archiveOfOurOwnMirror.supportsLiveLookup)
    }

    @Test func everyOriginHasALabelShortEnoughForACardBadge() {
        for origin in WorkOrigin.allCases {
            #expect(!origin.shortLabel.isEmpty)
            #expect(!origin.displayName.isEmpty)
            // The badge shares a row with Offline/Saved/Favorite; anything longer
            // pushes them off the card.
            #expect(origin.shortLabel.count <= 18, "\(origin) label is too long for a badge")
        }
    }

    // MARK: - Work-level origin

    @Test func anAO3WorkIDOutranksTheSourceURL() {
        // A natively downloaded work's sourceURL is often a /downloads/ link, and some
        // have no host at all — the id is the stronger evidence.
        let work = SavedWork(title: "Downloaded", author: "A", sourceURL: "")
        work.ao3WorkID = 4242
        #expect(work.origin == .archiveOfOurOwn)
    }

    @Test func aConvertedCommunityCopyReportsItsSite() {
        let work = SavedWork(
            title: "Rescued",
            author: "Lost",
            sourceURL: "https://www.fanfiction.net/s/999/1/"
        )
        #expect(work.origin == .fanfictionNet)
    }

    // MARK: - Preservation state

    @Test func anOrdinaryWorkHasNothingToSay() {
        let work = SavedWork(title: "Fine", author: "A")
        #expect(work.preservationState == .available)
        #expect(work.preservationState.badgeLabel == nil)
        #expect(work.preservationState.explanation(origin: .archiveOfOurOwn) == nil)
    }

    @Test func aDeletedWorkWeStillHoldIsTheLastCopy() {
        // The whole point of the preservation feature, made visible.
        let work = SavedWork(title: "Deleted Fic", author: "A")
        work.ao3WorkID = 1
        work.ao3Unavailable = true
        work.hasEPUB = true
        #expect(work.preservationState == .preservedLastCopy)
        #expect(work.preservationState.badgeLabel == "Last Copy")
        let explanation = try? #require(work.preservationState.explanation(origin: work.origin))
        #expect(explanation?.contains("Archive of Our Own") == true)
    }

    @Test func aDeletedWorkWithNoFileIsReportedAsUnavailable() {
        // Not "restorable history": there is nothing left to download.
        let work = SavedWork(title: "Lost Fic", author: "A")
        work.ao3WorkID = 2
        work.ao3Unavailable = true
        work.hasEPUB = false
        #expect(work.preservationState == .goneWithNoCopy)
        #expect(work.preservationState.badgeLabel == "Unavailable")
    }

    @Test func aNetworkFailureIsNotMistakenForADeletion() {
        // `ao3Unavailable` is set only on a 404. A locked or failing page leaves it
        // false and retryable, so a bad connection must never label a work as gone.
        let work = SavedWork(title: "Locked Fic", author: "A")
        work.ao3WorkID = 3
        work.hasEPUB = true
        #expect(work.ao3Unavailable == false)
        #expect(work.preservationState == .available)
    }
}
