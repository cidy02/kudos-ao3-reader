import Foundation
import Testing
@testable import Kudos

/// Covers the `SavedWork` reading helpers shared by the Home and Library "Reading
/// Now" shelves (`isInProgress`, `readingProgress`), extracted from the views so the
/// two dashboards can never drift.
@MainActor
struct SavedWorkProgressTests {

    private func work(_ title: String = "Work") -> SavedWork {
        SavedWork(title: title, author: "Author")
    }

    // MARK: isInProgress

    @Test func freshlyAddedWorkIsNotInProgress() {
        // Has an EPUB but hasn't been opened — not "reading now".
        #expect(work().isInProgress == false)
    }

    @Test func startedWorkIsInProgress() {
        let started = work()
        started.lastSpineIndex = 2
        #expect(started.isInProgress)

        let scrolled = work()
        scrolled.lastScrollFraction = 0.1
        #expect(scrolled.isInProgress)
    }

    @Test func finishedWorkIsNotInProgress() {
        let finished = work()
        finished.lastSpineIndex = 3
        finished.isFinished = true
        #expect(finished.isInProgress == false)
    }

    @Test func freedWorkIsNotInProgress() {
        // A history entry whose EPUB was freed can't be "reading now".
        let freed = work()
        freed.lastSpineIndex = 3
        freed.hasEPUB = false
        #expect(freed.isInProgress == false)
    }

    // MARK: readingProgress

    @Test func progressUsesChapterPositionWhenChaptersKnown() {
        let reading = work()
        reading.chapters = "5/10"
        reading.lastSpineIndex = 4   // on chapter 5 of 10
        #expect(reading.readingProgress == 0.5)
    }

    @Test func progressIsClampedToOne() {
        let reading = work()
        reading.chapters = "10/10"
        reading.lastSpineIndex = 20  // past the end (stale count)
        #expect(reading.readingProgress == 1)
    }

    @Test func progressFallsBackToScrollFractionWithoutChapterTotal() {
        let reading = work()
        reading.chapters = "1/?"      // single/unknown total
        reading.lastScrollFraction = 0.4
        #expect(reading.readingProgress == 0.4)
    }

    @Test func progressIsNilWhenNothingMeaningful() {
        #expect(work().readingProgress == nil)
    }

    // MARK: Readium reader progress (the iOS path)

    /// A minimal persisted Readium locator carrying an overall progression.
    private static func readiumLocator(total: Double) -> String {
        #"{"href":"chapter1.xhtml","type":"application/xhtml+xml","locations":{"totalProgression":\#(total),"progression":0.1,"position":5}}"#
    }

    @Test func readiumReadWorkIsInProgress() {
        // The Readium reader records only a locator (no spine index / scroll fraction).
        let reading = work()
        reading.readiumLocator = Self.readiumLocator(total: 0.42)
        #expect(reading.isInProgress)
        #expect(reading.readingProgress == 0.42)
        #expect(reading.readingProgressLabel == "42%")
    }

    @Test func openedWorkWithOnlyLastReadDateIsInProgress() {
        // Defensive: lastReadDate alone (e.g. a restored backup) still counts.
        let opened = work()
        opened.lastReadDate = Date()
        #expect(opened.isInProgress)
    }

    @Test func readiumProgressTakesPrecedenceOverLegacyChapters() {
        let reading = work()
        reading.chapters = "5/10"
        reading.lastSpineIndex = 4              // legacy would compute 0.5
        reading.readiumLocator = Self.readiumLocator(total: 0.8)
        #expect(reading.readingProgress == 0.8)
    }

    // MARK: readingState — one partition for the whole reading lifecycle

    @Test func readingStatePartitionsTheLifecycle() {
        // Fresh EPUB, never opened.
        #expect(work().readingState == .unread)

        // Opened (either reader) with the file on disk.
        let reading = work()
        reading.lastScrollFraction = 0.3
        #expect(reading.readingState == .inProgress)

        let readiumRead = work()
        readiumRead.readiumLocator = Self.readiumLocator(total: 0.2)
        #expect(readiumRead.readingState == .inProgress)

        // Marked finished.
        let finished = work()
        finished.isFinished = true
        #expect(finished.readingState == .finished)

        // EPUB freed without finishing → history-only record.
        let freed = work()
        freed.lastReadDate = Date()
        freed.hasEPUB = false
        #expect(freed.readingState == .freedHistory)
    }

    @Test func finishedWinsOverFreedEPUB() {
        // Finished works can have their EPUB freed (WorkLifecycle) — they must stay
        // "finished", not degrade to history, so the Finished shelf keeps them.
        let finishedFreed = work()
        finishedFreed.isFinished = true
        finishedFreed.hasEPUB = false
        #expect(finishedFreed.readingState == .finished)
    }

    @Test func readingStateMatchesIsInProgress() {
        // isInProgress is defined via the partition; a work is in progress iff its
        // state says so, across the axes that feed it.
        let variants: [(SavedWork) -> Void] = [
            { _ in },                                  // unread
            { $0.lastScrollFraction = 0.5 },           // legacy scroll
            { $0.readiumLocator = Self.readiumLocator(total: 0.1) },
            { $0.isFinished = true },
            { $0.hasEPUB = false },
            { $0.hasEPUB = false; $0.lastReadDate = Date() },
        ]
        for configure in variants {
            let sample = work()
            configure(sample)
            #expect(sample.isInProgress == (sample.readingState == .inProgress))
        }
    }
}
