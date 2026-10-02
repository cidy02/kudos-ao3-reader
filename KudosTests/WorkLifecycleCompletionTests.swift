import Foundation
import SwiftData
import Testing
@testable import Kudos

/// Covers the storage-policy half of A7-F1: `freeEPUBIfFinished` (the
/// reader-close hook) must never free an unfinished work's EPUB — completion at
/// 99%/99.9% no longer exists, so those works stay reopenable offline — and
/// protected works keep their EPUB even once genuinely finished.
@MainActor
struct WorkLifecycleCompletionTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
    }

    /// An ordinary AO3-backed work: not saved/favorited/queued, so it is NOT
    /// protected — the only kind eligible for post-finish EPUB freeing.
    private func unprotectedWork(in context: ModelContext) -> SavedWork {
        let work = SavedWork(title: "Work", author: "Author")
        work.ao3WorkID = 123
        context.insert(work)
        return work
    }

    private func locator(totalProgression: Double) -> String {
        #"{"href":"ch9.xhtml","type":"application/xhtml+xml","locations":{"totalProgression":\#(totalProgression)}}"#
    }

    /// "Keep works you read": opening a work marks it Downloaded only while the
    /// setting is on, so finishing it no longer frees the EPUB.
    @Test func keepWorksYouReadMarksAnOpenedWorkDownloaded() throws {
        let context = try makeContext()
        let name = "WorkLifecycleCompletionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let work = unprotectedWork(in: context)

        WorkLifecycle.keepIfKeepingWorksYouRead(work, in: context, defaults: defaults)
        #expect(!work.isSaved)

        defaults.set(true, forKey: WorkLifecycle.keepsWorksYouReadKey)
        WorkLifecycle.keepIfKeepingWorksYouRead(work, in: context, defaults: defaults)
        #expect(work.isSaved)
        work.isFinished = true
        WorkLifecycle.freeEPUBIfFinished(work, in: context)
        #expect(work.hasEPUB)
    }

    /// Owner, 2026-10-01: finishing an un-kept work holds its copy in Recently
    /// Deleted for 60 days instead of freeing it. The sweep frees it after the
    /// window; reading again or keeping it lets go.
    @Test func finishingHoldsTheCopyForSixtyDays() throws {
        let context = try makeContext()
        let work = unprotectedWork(in: context)
        WorkLifecycle.markFinished(work, in: context)
        #expect(work.hasEPUB)
        let held = try #require(work.freedAt)

        WorkLifecycle.sweepHeldCopies(in: context, now: held.addingTimeInterval(59 * 86_400))
        #expect(work.hasEPUB && work.freedAt != nil)
        WorkLifecycle.sweepHeldCopies(in: context, now: held.addingTimeInterval(61 * 86_400))
        #expect(!work.hasEPUB && work.freedAt == nil)

        let kept = unprotectedWork(in: context)
        WorkLifecycle.markFinished(kept, in: context)
        WorkLifecycle.restoreHeldCopy(kept, in: context)
        #expect(kept.isSaved && kept.freedAt == nil && kept.hasEPUB)

        let reread = unprotectedWork(in: context)
        WorkLifecycle.markFinished(reread, in: context)
        WorkLifecycle.releaseHeldCopy(reread)
        WorkLifecycle.sweepHeldCopies(in: context, now: Date().addingTimeInterval(90 * 86_400))
        #expect(reread.hasEPUB)
    }

    @Test func unfinishedWorkAt99PercentKeepsItsEPUB() throws {
        let context = try makeContext()
        let work = unprotectedWork(in: context)
        work.readiumLocator = locator(totalProgression: 0.99)

        // Reader close always calls this; at 99% the work is not finished, so
        // the EPUB must survive and an offline reopen keeps working.
        WorkLifecycle.freeEPUBIfFinished(work, in: context)

        #expect(!work.isFinished)
        #expect(work.hasEPUB)
        #expect(work.readingState == .inProgress)
    }

    @Test func unfinishedWorkAt999PermilleKeepsItsEPUB() throws {
        let context = try makeContext()
        let work = unprotectedWork(in: context)
        work.readiumLocator = locator(totalProgression: 0.999)

        WorkLifecycle.freeEPUBIfFinished(work, in: context)

        #expect(!work.isFinished)
        #expect(work.hasEPUB)
    }

    @Test func protectedFinishedWorkKeepsItsEPUB() throws {
        let context = try makeContext()
        let work = unprotectedWork(in: context)
        work.isSaved = true // protected

        WorkLifecycle.markFinished(work, in: context)
        WorkLifecycle.freeEPUBIfFinished(work, in: context)

        #expect(work.isFinished)
        #expect(work.hasEPUB)
    }

    @Test func unprotectedFinishedWorkIsHeldOnClose() throws {
        // The post-finish storage policy still applies once a work is genuinely
        // finished — as a 60-day hold in Recently Deleted (owner, 2026-10-01).
        let context = try makeContext()
        let work = unprotectedWork(in: context)
        work.isFinished = true

        WorkLifecycle.freeEPUBIfFinished(work, in: context)

        #expect(work.hasEPUB && work.freedAt != nil)
        #expect(work.readingState == .finished)
    }
}
