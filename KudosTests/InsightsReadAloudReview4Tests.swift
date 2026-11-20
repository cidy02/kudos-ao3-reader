import Foundation
#if os(iOS)
import ReadiumNavigator
import ReadiumShared
#endif
import SwiftData
import Testing
@testable import Kudos

/// T-535c: the review-4 P3 follow-ups (Read Aloud skip rule, unspeakable chapters,
/// Reset re-anchoring, re-rated live works, view-wiring pins).
@MainActor
@Suite(.serialized)
struct InsightsReadAloudReview4Tests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, QueueSavedSearchLink.self, SyncTombstone.self,
            ReadingAnnotation.self, ReadingSession.self, ReadingFavorite.self,
            FandomReadWatermark.self, TagAlias.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func source(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "kudos-ao3-reader")
            .appending(path: path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The text from `start` up to (not including) the next `end` after it.
    private func slice(_ text: String, from start: String, to end: String) -> String? {
        guard let lower = text.range(of: start) else { return nil }
        let rest = text[lower.lowerBound...]
        guard let upper = rest.range(of: end, range: rest.index(after: rest.startIndex)..<rest.endIndex) else {
            return String(rest)
        }
        return String(rest[..<upper.lowerBound])
    }

    // MARK: - 1. One skip rule for ⏭ and ⏮

    @Test func pausedAfterBrowsingBothSkipsCountFromTheVisiblePage() throws {
        // Paused on Ch 2, browsed to Ch 5 (page 1).
        let origin = try #require(ReaderSpeechSkip.origin(
            followsSpeech: false, speechChapter: 2, visibleChapter: 5, visiblePage: 1
        ))
        #expect(origin == .init(chapter: 5, page: 1))
        #expect(ReaderSpeechSkip.targetChapter(forward: true, from: origin, chapterCount: 10) == 6)
        #expect(ReaderSpeechSkip.targetChapter(forward: false, from: origin, chapterCount: 10) == 4)
    }

    @Test func playingSkipsCountFromTheSpeechPosition() throws {
        // Playing Ch 2, page in step.
        let inStep = try #require(ReaderSpeechSkip.origin(
            followsSpeech: true, speechChapter: 2, visibleChapter: 2, visiblePage: 4
        ))
        #expect(ReaderSpeechSkip.targetChapter(forward: true, from: inStep, chapterCount: 10) == 3)
        #expect(ReaderSpeechSkip.targetChapter(forward: false, from: inStep, chapterCount: 10) == 2)
        // Speech just moved to Ch 3; the navigator still shows Ch 2.
        let stale = try #require(ReaderSpeechSkip.origin(
            followsSpeech: true, speechChapter: 3, visibleChapter: 2, visiblePage: 7
        ))
        #expect(stale == .init(chapter: 3, page: 1))
        #expect(ReaderSpeechSkip.targetChapter(forward: true, from: stale, chapterCount: 10) == 4)
        #expect(ReaderSpeechSkip.targetChapter(forward: false, from: stale, chapterCount: 10) == 2)
    }

    @Test func skipBoundsAndMissingPositions() {
        let last = ReaderSpeechSkip.Origin(chapter: 4, page: 3)
        #expect(ReaderSpeechSkip.targetChapter(forward: true, from: last, chapterCount: 4) == nil)
        let first = ReaderSpeechSkip.Origin(chapter: 1, page: 1)
        #expect(ReaderSpeechSkip.targetChapter(forward: false, from: first, chapterCount: 4) == nil)
        #expect(ReaderSpeechSkip.origin(
            followsSpeech: false, speechChapter: nil, visibleChapter: nil, visiblePage: 1
        ) == nil)
        #expect(ReaderSpeechSkip.origin(
            followsSpeech: false, speechChapter: 3, visibleChapter: nil, visiblePage: 1
        ) == .init(chapter: 3, page: 1))
    }

    // MARK: - 5. The view's skip handlers go through `ReadiumBook.speechSkipTarget`

    @Test func readerSkipHandlersUseTheSharedSkipRule() throws {
        let view = try source("Features/ReaderReadium/ReadiumReaderView.swift")
        let handlers = try #require(slice(
            view,
            from: "private func handleSpeechSkipBack()",
            to: "/// 1-based spine chapter → first Readium position"
        ))
        #expect(handlers.contains("private func handleSpeechSkipForward()"))
        // Both directions, both resolved by the book from the speech locator and the
        // controller's follows-speech flag; neither reads the visible position itself.
        #expect(handlers.components(separatedBy: "book.speechSkipTarget(").count - 1 == 2)
        #expect(handlers.components(separatedBy: "speech.skipFollowsSpeechPosition").count - 1 == 2)
        #expect(handlers.components(separatedBy: "speechLocator: speech.resumeLocator").count - 1 == 2)
        #expect(!handlers.contains("readingPosition"))
        #expect(view.contains("onSkipNext: { handleSpeechSkipForward() }"))
        #expect(view.contains("onSkipPrevious: { handleSpeechSkipBack() }"))
    }

    // MARK: - 5. Insights re-lock wiring and the cheap fingerprint

    @Test func insightsViewKeepsItsRelockHandlersAndCheapFingerprint() throws {
        let view = try source("Features/Library/ReadingInsightsView.swift")
        let reveal = try #require(slice(view, from: ".onChange(of: gate.revealAll)", to: ".onChange(of:"))
        #expect(reveal.contains("scopeState.handleRevealChange(revealed: revealed, hideMature: hideMature)"))
        #expect(reveal.contains("if !revealed { clearMainDisplayState() }"))
        #expect(reveal.contains("reload()"))
        let hide = try #require(slice(view, from: ".onChange(of: hideMature)", to: ".onReceive("))
        #expect(hide.contains("scopeState.handleHideMatureChange(hideMature: isHiding, revealed: gate.revealAll)"))
        #expect(hide.contains("clearMainDisplayState()"))
        #expect(hide.contains("reload()"))
        #expect(view.contains("if scopeState.mayDisplayLoadedData(hideMature: hideMature, revealed: gate.revealAll)"))
        // No walk over the library on every body evaluation.
        let fingerprint = try #require(slice(
            view, from: "private var libraryWorksFingerprint: String", to: "private var reloadKey"
        ))
        #expect(!fingerprint.contains("for "))
        #expect(view.contains("publisher(for: ModelContext.didSave)"))
    }

    // MARK: - 6. `includes(_:)` is gone

    @Test func scopeSelectionHasNoPerSittingIncludes() throws {
        let stats = try source("Features/Library/ReadingStatistics.swift")
        #expect(!stats.contains("func includes("))
    }

    // MARK: - 4. A live work follows its current rating

    @Test func reRatedLiveWorkReturnsToMainWhileDeletedMatureWorkStaysHidden() throws {
        let context = try makeContext()
        let reRated = SavedWork(title: "Re-rated Fic", author: "A")
        reRated.isSaved = true
        reRated.rating = "Teen And Up Audiences"
        reRated.wordCount = 10_000
        context.insert(reRated)
        let adult = SavedWork(title: "Adult Fic", author: "A")
        adult.isSaved = true
        adult.rating = "Explicit"
        context.insert(adult)
        let goneID = UUID()

        func sitting(_ workID: UUID, rating: String, at offset: TimeInterval) -> ReadingSession {
            let session = ReadingSession(
                workID: workID,
                startedAt: Date(timeIntervalSince1970: 1_000 + offset),
                endedAt: Date(timeIntervalSince1970: 1_600 + offset),
                durationSeconds: 600
            )
            session.rating = rating
            context.insert(session)
            return session
        }
        // Read while Explicit, then once more after the re-rating.
        let reRatedOld = sitting(reRated.id, rating: "Explicit", at: 0)
        let reRatedNew = sitting(reRated.id, rating: "Teen And Up Audiences", at: 1_000)
        // An adult work since hard-deleted: only its snapshot can classify it.
        let gone = sitting(goneID, rating: "Explicit", at: 2_000)
        let adultSitting = sitting(adult.id, rating: "", at: 3_000)
        try context.save()

        let all = try context.fetch(FetchDescriptor<ReadingSession>())
        let library = [reRated, adult]
        for revealed in [false, true] {
            let main = HomeReadingStats.insightsScope(.main, from: library, hideMature: true, revealed: revealed)
                .sessions(all, in: context).map(\.id)
            #expect(Set(main) == [reRatedOld.id, reRatedNew.id])
        }
        let hidden = HomeReadingStats.insightsScope(.hidden, from: library, hideMature: true, revealed: true)
            .sessions(all, in: context).map(\.id)
        #expect(Set(hidden) == [gone.id, adultSitting.id])
        let combined = HomeReadingStats.insightsScope(.combined, from: library, hideMature: true, revealed: true)
            .sessions(all, in: context)
        #expect(combined.count == all.count)
    }

    // MARK: - 3. Reset re-anchors the open sitting

    @Test func resetReAnchorsOpenSittingAtCurrentPositionAndFinishState() throws {
        ReadingLogService.resetOpenSessionsForTests()
        defer { ReadingLogService.resetOpenSessionsForTests() }
        let context = try makeContext()
        let work = SavedWork(title: "Listened", author: "A")
        work.wordCount = 10_000
        work.legacyReaderProgress = 0.2
        context.insert(work)
        try context.save()

        let t0 = Date(timeIntervalSince1970: 700_000)
        ReadingLogService.handleDetachedSpeech(.playing, for: work, playbackRate: 1.0, now: t0)
        // Listened to the end (and finished) before the Reset, same sitting.
        work.legacyReaderProgress = 0.98
        work.isFinished = true
        let resetTime = t0.addingTimeInterval(120)
        try InsightsExportService.resetReadingLog(in: context, now: resetTime)

        ReadingLogService.handleDetachedSpeech(
            .stopped, for: work, playbackRate: 1.0, now: resetTime.addingTimeInterval(40)
        )
        let rows = try context.fetch(FetchDescriptor<ReadingSession>())
        let row = try #require(rows.first)
        #expect(rows.count == 1)
        #expect(row.startProgress == 0.98)
        #expect(!row.didFinish)
        #expect(row.durationSeconds == 40)
    }

    @Test func resetKeepsAFinishMadeAfterTheReset() throws {
        ReadingLogService.resetOpenSessionsForTests()
        defer { ReadingLogService.resetOpenSessionsForTests() }
        let context = try makeContext()
        let work = SavedWork(title: "Finished Later", author: "A")
        work.wordCount = 10_000
        work.legacyReaderProgress = 0.2
        context.insert(work)
        try context.save()

        let t0 = Date(timeIntervalSince1970: 800_000)
        ReadingLogService.handleDetachedSpeech(.playing, for: work, playbackRate: 1.0, now: t0)
        work.legacyReaderProgress = 0.5
        let resetTime = t0.addingTimeInterval(120)
        try InsightsExportService.resetReadingLog(in: context, now: resetTime)
        work.legacyReaderProgress = 1
        work.isFinished = true
        ReadingLogService.handleDetachedSpeech(
            .stopped, for: work, playbackRate: 1.0, now: resetTime.addingTimeInterval(60)
        )
        let row = try #require(try context.fetch(FetchDescriptor<ReadingSession>()).first)
        #expect(row.startProgress == 0.5)
        #expect(row.didFinish)
    }
}

#if os(iOS)
extension InsightsReadAloudReview4Tests {
    /// A stub engine that, like a real one, reports the first utterance's text once it
    /// starts, so a pending pause after a paused re-anchor takes effect.
    @MainActor
    private final class SpeakingStub: TTSService {
        var status: TTSServiceStatus = .stopped
        var spokenText: String = ""
        var speechEnergy: Double = 0
        var speechEnergySeed: Double = 0
        var availableVoices: [TTSVoice] = []
        var onStatusChange: ((TTSServiceStatus) -> Void)?
        var onSpokenTextChange: ((String) -> Void)?
        var onSpeechEnergyPulse: ((Double, Double) -> Void)?
        var onSpeechSpectrum: ((SpeechSpectrum) -> Void)?
        var onAdvance: ((Locator) -> Void)?
        var onSpokenRange: ((Locator) -> Void)?

        func speak(units: [TTSSpeechUnit]) async throws -> Bool {
            status = .stopped
            guard let prose = units.first(where: { $0.text.contains("Prose") }) else { return false }
            status = .playing
            onStatusChange?(.playing)
            onSpokenTextChange?(prose.text)
            return true
        }

        func pause() {
            guard status == .playing else { return }
            status = .paused
            onStatusChange?(.paused)
        }

        func resume() {
            guard status == .paused else { return }
            status = .playing
            onStatusChange?(.playing)
        }

        func stop() {
            let wasStopped = status == .stopped
            status = .stopped
            if !wasStopped { onStatusChange?(.stopped) }
        }

        func setVoice(id _: String) {}
        func setRate(_: Float) {}
        func setPitch(_: Float) {}
    }

    /// Six chapters, two positions each (global positions 1…12), hrefs `chN.xhtml`.
    private func chapterPositions() -> [[Locator]] {
        (1...6).map { chapter in
            (0..<2).map { offset in
                Locator(
                    href: AnyURL(string: "ch\(chapter).xhtml")!,
                    mediaType: .xhtml,
                    locations: .init(position: (chapter - 1) * 2 + offset + 1)
                )
            }
        }
    }

    @Test func bookSkipTargetFollowsTheRuleTheViewUses() throws {
        let positions = chapterPositions()
        let book = ReadiumBook()
        // Paused on Ch 2, browsed to Ch 5.
        book.seedChaptersForTests(positions, current: positions[4][0])
        let speech = positions[1][1]
        #expect(book.speechSkipTarget(forward: true, speechLocator: speech, followsSpeech: false) == 6)
        #expect(book.speechSkipTarget(forward: false, speechLocator: speech, followsSpeech: false) == 4)
        // Deep into Ch 5 (page 3 of 6): ⏮ restarts Ch 5.
        book.seedChaptersForTests(positions, current: positions[4][1], visualPage: 3, visualPageCount: 6)
        #expect(book.speechSkipTarget(forward: false, speechLocator: speech, followsSpeech: false) == 5)
        // Playing Ch 2 with the page in step.
        book.seedChaptersForTests(positions, current: positions[1][0])
        #expect(book.speechSkipTarget(forward: true, speechLocator: positions[1][1], followsSpeech: true) == 3)
        // Playing: speech already on Ch 3, navigator not settled (still Ch 2).
        #expect(book.speechSkipTarget(forward: true, speechLocator: positions[2][0], followsSpeech: true) == 4)
        // Last chapter: nothing to skip to.
        book.seedChaptersForTests(positions, current: positions[5][0])
        #expect(book.speechSkipTarget(forward: true, speechLocator: positions[5][0], followsSpeech: true) == nil)
    }

    /// Wires a controller to a seeded book the way `ReadiumReaderView` does: ⏭ resolves
    /// through `speechSkipTarget` and re-anchors at the target chapter's first position.
    /// The book never navigates (no navigator), so its visible page stays put, as an
    /// unsettled navigator's does.
    private func makeWiredController(
        status: ReaderSpeechController.Status,
        unspeakable: Set<String>,
        resumeAt: Locator,
        visible: Locator,
        visited: @escaping (Int) -> Void
    ) -> (ReaderSpeechController, ReadiumBook) {
        let positions = chapterPositions()
        let book = ReadiumBook()
        book.seedChaptersForTests(positions, current: visible)
        let controller = ReaderSpeechController()
        controller.seedSessionForTests(
            workID: UUID(),
            status: status,
            isReaderOpen: true,
            ttsService: SpeakingStub(),
            unitProvider: { locator in
                let href = locator?.href.string ?? ""
                return unspeakable.contains(href)
                    ? [TTSSpeechUnit(text: "* * *", locator: locator)]
                    : [TTSSpeechUnit(text: "Prose in \(href).", locator: locator)]
            },
            resumeLocator: resumeAt,
            onSkipNext: { [weak controller] in
                guard let controller,
                      let target = book.speechSkipTarget(
                          forward: true,
                          speechLocator: controller.resumeLocator,
                          followsSpeech: controller.skipFollowsSpeechPosition
                      )
                else { return false }
                visited(target)
                controller.reanchor(to: positions[target - 1][0], resumePlaying: controller.isPlaying)
                return true
            }
        )
        return (controller, book)
    }

    @Test func pausedSkipOntoUnspeakableChapterMovesOnAndStaysPaused() async throws {
        let positions = chapterPositions()
        var visited: [Int] = []
        let (controller, _) = makeWiredController(
            status: .paused,
            unspeakable: ["ch3.xhtml"],
            resumeAt: positions[1][0],
            visible: positions[1][0],
            visited: { visited.append($0) }
        )
        // ⏭ while paused on Ch 2: Ch 3 has nothing to speak, so Read Aloud moves on
        // to Ch 4 (counting from the speech position, not the unsettled page) and
        // stays paused there.
        #expect(controller.onSkipNext?() == true)
        await controller.waitForStartTaskForTests()
        #expect(visited == [3, 4])
        #expect(controller.status == .paused)
        #expect(controller.isSessionActive)
        #expect(controller.resumeLocator?.href.string == "ch4.xhtml")
        #expect(!controller.showsNothingToSpeakAlert)
        #expect(!controller.skipFollowsSpeechPosition)
    }

    @Test func freshPlayOnUnspeakableChapterStartsAtTheNextSpeakableOne() async throws {
        let positions = chapterPositions()
        var visited: [Int] = []
        let (controller, _) = makeWiredController(
            status: .stopped,
            unspeakable: ["ch3.xhtml", "ch4.xhtml"],
            resumeAt: positions[2][0],
            visible: positions[2][0],
            visited: { visited.append($0) }
        )
        controller.toggle(from: positions[2][0])
        await controller.waitForStartTaskForTests()
        #expect(visited == [4, 5])
        #expect(controller.status == .playing)
        #expect(controller.resumeLocator?.href.string == "ch5.xhtml")
        #expect(!controller.showsNothingToSpeakAlert)
    }

    @Test func freshPlayWithNothingSpeakableToTheEndSaysWhy() async throws {
        let positions = chapterPositions()
        var visited: [Int] = []
        let (controller, _) = makeWiredController(
            status: .stopped,
            unspeakable: ["ch5.xhtml", "ch6.xhtml"],
            resumeAt: positions[4][0],
            visible: positions[4][0],
            visited: { visited.append($0) }
        )
        controller.toggle(from: positions[4][0])
        await controller.waitForStartTaskForTests()
        #expect(visited == [6])
        #expect(controller.status == .stopped)
        #expect(controller.showsNothingToSpeakAlert)
        // A reader opening clears it, so it never shows in a later reader.
        controller.readerDidOpen(workID: UUID())
        #expect(!controller.showsNothingToSpeakAlert)
    }

    @Test func pausedSkipWithNothingSpeakableToTheEndEndsCleanlyAndSaysWhy() async throws {
        let positions = chapterPositions()
        var visited: [Int] = []
        let (controller, _) = makeWiredController(
            status: .paused,
            unspeakable: ["ch6.xhtml"],
            resumeAt: positions[4][0],
            visible: positions[4][0],
            visited: { visited.append($0) }
        )
        #expect(controller.onSkipNext?() == true)
        await controller.waitForStartTaskForTests()
        #expect(visited == [6])
        #expect(controller.status == .stopped)
        #expect(controller.showsNothingToSpeakAlert)
    }
}
#endif
