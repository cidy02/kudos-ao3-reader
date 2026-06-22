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
}
