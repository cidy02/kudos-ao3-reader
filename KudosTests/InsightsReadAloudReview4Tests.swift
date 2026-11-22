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

    /// The text from `start` up to (not including) the next `end` after it, or `nil`
    /// when either is missing: a moved anchor fails the test instead of silently
    /// widening the slice to the end of the file.
    private func slice(_ text: String, from start: String, to end: String) -> String? {
        guard let lower = text.range(of: start),
              let upper = text.range(of: end, range: lower.upperBound..<text.endIndex)
        else { return nil }
        return String(text[lower.lowerBound..<upper.lowerBound])
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

    // MARK: - 5. View wiring the controller tests cannot reach

    @Test func readerSkipHandlersUseTheSharedRuleAndNeverMoveThePageThemselves() throws {
        let view = try source("Features/ReaderReadium/ReadiumReaderView.swift")
        let back = try #require(slice(
            view, from: "private func handleSpeechSkipBack()", to: "private func handleSpeechSkipForward()"
        ))
        #expect(back.contains("forward: false"))
        #expect(back.contains("speechLocator: speech.resumeLocator"))
        #expect(back.contains("followsSpeech: speech.skipFollowsSpeechPosition"))
        #expect(back.contains("direction: .backward"))
        #expect(!back.contains("readingPosition"))
        #expect(!back.contains("playSpeechChapterHaptic"))
        let forward = try #require(slice(
            view, from: "private func handleSpeechSkipForward()", to: "private func goToSpineChapterStart("
        ))
        #expect(forward.contains("forward: true"))
        #expect(forward.contains("speechLocator: speech.resumeLocator"))
        #expect(forward.contains("followsSpeech: speech.skipFollowsSpeechPosition"))
        #expect(!forward.contains("readingPosition"))
        #expect(!forward.contains("playSpeechChapterHaptic"))
        // Read Aloud moves the page (`onAdvance`) and fires the manual chapter haptic
        // (`onChapterSkipCommitted`) only once a speakable chapter commits.
        let go = try #require(slice(
            view, from: "private func goToSpineChapterStart(", to: "private func handleSpeechSeekHoldStart("
        ))
        #expect(go.contains(
            "speech.reanchor(to: first, resumePlaying: resumePlaying, direction: direction, isManualSkip: true)"
        ))
        #expect(!go.contains("book.go("))
        #expect(view.contains("onChapterSkipCommitted: { playSpeechChapterHaptic() }"))
        #expect(view.contains("onSkipNext: { handleSpeechSkipForward() }"))
        #expect(view.contains("onSkipPrevious: { handleSpeechSkipBack() }"))
        #expect(view.contains("onSkipForward: { handleSpeechSkipForward() }"))
        #expect(view.contains("onSkipBack: { handleSpeechSkipBack() }"))
        // The alerts belong to the reader Read Aloud is attached to.
        #expect(view.contains(".alert(\"Nothing to Read Aloud\", isPresented: nothingToSpeakPresented)"))
        #expect(view.contains("Text(speech.nothingToSpeakMessage)"))
        #expect(view.contains(".alert(\"Couldn't Start Read Aloud\", isPresented: speechErrorPresented)"))
        let binding = try #require(slice(
            view, from: "private var nothingToSpeakPresented: Binding<Bool>", to: "private var kudosErrorPresented"
        ))
        #expect(binding.contains("speech.showsNothingToSpeakAlert && speech.openReaderWorkID == work.id"))
        #expect(binding.contains("speech.showsNothingToSpeakAlert = $0"))
        #expect(binding.contains("speech.speechErrorMessage != nil && speech.openReaderWorkID == work.id"))
    }

    @Test func insightsViewKeepsItsRelockHandlersAndGatedSaveObserver() throws {
        let view = try source("Features/Library/ReadingInsightsView.swift")
        let reveal = try #require(slice(
            view, from: ".onChange(of: gate.revealAll)", to: ".onChange(of: hideMature)"
        ))
        #expect(reveal.contains("scopeState.handleRevealChange(revealed: revealed, hideMature: hideMature)"))
        #expect(reveal.contains("if !revealed { clearMainDisplayState() }"))
        #expect(reveal.contains("reload()"))
        let hide = try #require(slice(
            view, from: ".onChange(of: hideMature)",
            to: ".onReceive(NotificationCenter.default.publisher(for: .kudosSyncRelevantSettingChanged))"
        ))
        #expect(hide.contains("scopeState.handleHideMatureChange(hideMature: isHiding, revealed: gate.revealAll)"))
        #expect(hide.contains("if isHiding && !gate.revealAll { clearMainDisplayState() }"))
        #expect(hide.contains("reload()"))
        #expect(view.contains("if scopeState.mayDisplayLoadedData(hideMature: hideMature, revealed: gate.revealAll)"))
        let saves = try #require(slice(
            view, from: "publisher(for: ModelContext.didSave)", to: ".refreshable {"
        ))
        #expect(saves.contains(".receive(on: DispatchQueue.main)"))
        #expect(saves.contains("guard isOnScreen else { return }"))
        // The save -> classify -> coalesce -> single-snapshot reload chain itself is
        // exercised behaviourally in `InsightsReloadCoordinatorTests`; this only pins
        // that the screen routes `didSave` through it.
        #expect(saves.contains("reloadCoordinator.noteSave("))
        #expect(saves.contains("isOnScreen: { isOnScreen }"))
        #expect(saves.contains("reload: { snapshot in reload(baseline: snapshot) }"))
        let disappear = try #require(slice(
            view, from: ".onDisappear {", to: ".onChange(of: gate.revealAll)"
        ))
        #expect(disappear.contains("isOnScreen = false"))
        #expect(disappear.contains("reloadCoordinator.cancel()"))
        let key = try #require(slice(
            view, from: "private var reloadKey: String", to: "enum Tab: String"
        ))
        #expect(key.contains("InsightsReloadKey.make("))
        #expect(key.contains("libraryDigest: libraryDigest"))
    }

    // MARK: - 5. What a save must change for Insights to reload

    @Test func reloadDigestIgnoresPositionSavesAndTracksWhatInsightsCounts() throws {
        let context = try makeContext()
        let now = Date(timeIntervalSince1970: 100_000)
        let work = SavedWork(title: "Digest", author: "A")
        work.isSaved = true
        work.wordCount = 5_000
        // Already started and read today: mid-chapter position saves do not change
        // any displayed bucket (unread/started, caught-up, abandoned, 7d/30d).
        work.readiumLocator = #"{"href":"ch1.xhtml","locations":{"totalProgression":0.2}}"#
        work.lastSpineIndex = 0
        work.lastReadDate = now.addingTimeInterval(-600)
        work.lastModifiedAt = now.addingTimeInterval(-600)
        context.insert(work)
        try context.save()
        let works = [work]
        let base = InsightsReloadDigest.make(works: works, context: context, now: now)

        // Read Aloud / reader mid-chapter position saves.
        work.legacyReaderProgress = 0.4
        work.readiumLocator = #"{"href":"ch2.xhtml","locations":{"totalProgression":0.4}}"#
        work.lastSpineIndex = 1
        work.lastReadDate = now.addingTimeInterval(-60)
        work.lastModifiedAt = now.addingTimeInterval(-60)
        try context.save()
        #expect(InsightsReloadDigest.make(works: works, context: context, now: now) == base)

        var previous = base
        func expectChanged(_ label: Comment) {
            let next = InsightsReloadDigest.make(works: works, context: context, now: now)
            #expect(next != previous, label)
            previous = next
        }
        work.rating = "Explicit"
        expectChanged("rating")
        work.isFinished = true
        expectChanged("finished")
        work.setReadingStatus(.stopped, at: Date(timeIntervalSince1970: 10_000))
        expectChanged("status")
        work.wordCount = 6_000
        expectChanged("word count")
        let session = ReadingSession(
            workID: work.id,
            startedAt: Date(timeIntervalSince1970: 11_000),
            endedAt: Date(timeIntervalSince1970: 11_600),
            durationSeconds: 600
        )
        context.insert(session)
        try context.save()
        expectChanged("sitting written")
        session.durationSeconds = 900
        session.lastModifiedAt = Date(timeIntervalSince1970: 12_000)
        try context.save()
        expectChanged("sitting updated")
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

    @Test func softDeletedWorkFollowsItsCurrentRatingLikeALiveOne() throws {
        let context = try makeContext()
        let reRated = SavedWork(title: "Re-rated then deleted", author: "A")
        reRated.rating = "General Audiences"
        reRated.isPendingDeletion = true
        context.insert(reRated)
        let adult = SavedWork(title: "Adult then deleted", author: "A")
        adult.rating = "Explicit"
        adult.isPendingDeletion = true
        context.insert(adult)
        func sitting(_ workID: UUID, rating: String) -> ReadingSession {
            let session = ReadingSession(
                workID: workID,
                startedAt: Date(timeIntervalSince1970: 1_000),
                endedAt: Date(timeIntervalSince1970: 1_600),
                durationSeconds: 600
            )
            session.rating = rating
            context.insert(session)
            return session
        }
        let oldExplicit = sitting(reRated.id, rating: "Explicit")
        let blankAdult = sitting(adult.id, rating: "")
        try context.save()
        let all = try context.fetch(FetchDescriptor<ReadingSession>())
        let library = [reRated, adult]
        let main = HomeReadingStats.insightsScope(.main, from: library, hideMature: true, revealed: false)
            .sessions(all, in: context).map(\.id)
        #expect(main == [oldExplicit.id])
        let hidden = HomeReadingStats.insightsScope(.hidden, from: library, hideMature: true, revealed: true)
            .sessions(all, in: context).map(\.id)
        #expect(hidden == [blankAdult.id])
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
    /// A stub engine shaped like the real ones. It reports the first utterance's text
    /// once it starts (so a pending pause after a paused re-anchor takes effect),
    /// "plays" `silentHrefs` without ever reporting a word (Kokoro on a chapter it
    /// renders no audio for), and can go `.unavailable`.
    @MainActor
    private final class SpeakingStub: TTSService {
        var status: TTSServiceStatus
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

        var silentHrefs: Set<String> = []
        var goesUnavailable = false
        private(set) var spokenHrefs: [String] = []
        private(set) var stopCount = 0

        init(status: TTSServiceStatus = .stopped) {
            self.status = status
        }

        func speak(units: [TTSSpeechUnit]) async throws -> Bool {
            // Real engines reset playback before looking at the text.
            status = .stopped
            if goesUnavailable {
                status = .unavailable
                onStatusChange?(.unavailable)
                return false
            }
            guard let first = units.first(where: \.hasSpeakableText) else { return false }
            spokenHrefs.append(first.locator?.href.string ?? "")
            status = .playing
            onStatusChange?(.playing)
            if !silentHrefs.contains(first.locator?.href.string ?? "") {
                onSpokenTextChange?(first.text)
            }
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
            stopCount += 1
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

    /// A controller and book wired the way `ReadiumReaderView` wires them: ⏭/⏮ resolve
    /// through `speechSkipTarget` and re-anchor at the target chapter's first position
    /// (the view does not move the page); `onAdvance` is the page-follow, recorded in
    /// `moves` and settled into the book.
    @MainActor
    private final class Rig {
        let positions: [[Locator]]
        let book = ReadiumBook()
        let controller = ReaderSpeechController()
        let engine: SpeakingStub
        var moves: [String] = []

        init(
            status: ReaderSpeechController.Status,
            unspeakable: Set<String>,
            at chapter: Int,
            isReaderOpen: Bool = true,
            engine: SpeakingStub? = nil
        ) {
            let engine = engine ?? SpeakingStub()
            let positions = (1...6).map { chapter in
                (0..<2).map { offset in
                    Locator(
                        href: AnyURL(string: "ch\(chapter).xhtml")!,
                        mediaType: .xhtml,
                        locations: .init(position: (chapter - 1) * 2 + offset + 1)
                    )
                }
            }
            self.positions = positions
            self.engine = engine
            if engine.status == .stopped, status == .paused { engine.status = .paused }
            if engine.status == .stopped, status == .playing { engine.status = .playing }
            book.seedChaptersForTests(positions, current: positions[chapter - 1][0])
            controller.seedSessionForTests(
                workID: UUID(),
                status: status,
                isReaderOpen: isReaderOpen,
                ttsService: engine,
                unitProvider: { locator in
                    let href = locator?.href.string ?? ""
                    if unspeakable.contains(href) {
                        return href == "ch6.xhtml" ? [] : [TTSSpeechUnit(text: "* * *", locator: locator)]
                    }
                    return [TTSSpeechUnit(text: "Prose in \(href).", locator: locator)]
                },
                resumeLocator: positions[chapter - 1][0],
                chapterStartLocators: positions.map(\.first)
            )
            controller.onAdvance = { [unowned self] locator in
                moves.append(locator.href.string)
                book.seedChaptersForTests(positions, current: locator)
            }
        }

        func skip(forward: Bool) {
            guard let target = book.speechSkipTarget(
                forward: forward,
                speechLocator: controller.resumeLocator,
                followsSpeech: controller.skipFollowsSpeechPosition
            ) else { return }
            controller.reanchor(
                to: positions[target - 1][0],
                resumePlaying: controller.isPlaying,
                direction: forward ? .forward : .backward
            )
        }

        var speechHref: String? { controller.resumeLocator?.href.string }
    }

    @Test func pausedSkipOntoUnspeakableChapterMovesOnAndStaysPaused() async {
        let rig = Rig(status: .paused, unspeakable: ["ch3.xhtml"], at: 2)
        rig.skip(forward: true)
        await rig.controller.waitForStartTaskForTests()
        #expect(rig.controller.status == .paused)
        #expect(rig.speechHref == "ch4.xhtml")
        #expect(rig.moves == ["ch4.xhtml"])
        #expect(rig.engine.spokenHrefs == ["ch4.xhtml"])
        #expect(!rig.controller.showsNothingToSpeakAlert)
    }

    @Test func freshPlayOnUnspeakableChaptersStartsAtTheNextSpeakableOne() async {
        let rig = Rig(status: .stopped, unspeakable: ["ch3.xhtml", "ch4.xhtml"], at: 3)
        rig.controller.toggle(from: rig.positions[2][0])
        await rig.controller.waitForStartTaskForTests()
        #expect(rig.controller.status == .playing)
        #expect(rig.speechHref == "ch5.xhtml")
        #expect(rig.moves == ["ch5.xhtml"])
        #expect(rig.engine.spokenHrefs == ["ch5.xhtml"])
    }

    @Test func freshPlayWithNothingSpeakableToTheEndNeverMovesThePage() async {
        let rig = Rig(status: .stopped, unspeakable: ["ch5.xhtml", "ch6.xhtml"], at: 5)
        rig.controller.toggle(from: rig.positions[4][0])
        await rig.controller.waitForStartTaskForTests()
        #expect(rig.controller.status == .stopped)
        #expect(rig.moves.isEmpty)
        #expect(rig.engine.spokenHrefs.isEmpty)
        #expect(rig.controller.showsNothingToSpeakAlert)
        // Closing or tearing down the reader clears it, so it never shows later.
        rig.controller.readerDidClose(workID: rig.controller.openReaderWorkID ?? UUID())
        #expect(!rig.controller.showsNothingToSpeakAlert)
    }

    @Test func pausedSkipWithNothingSpeakableAheadStaysPausedWhereItWas() async {
        let rig = Rig(status: .paused, unspeakable: ["ch6.xhtml"], at: 5)
        rig.skip(forward: true)
        await rig.controller.waitForStartTaskForTests()
        #expect(rig.controller.status == .paused)
        #expect(rig.engine.status == .paused)
        #expect(rig.engine.stopCount == 0)
        #expect(rig.speechHref == "ch5.xhtml")
        #expect(rig.moves.isEmpty)
        #expect(rig.controller.showsNothingToSpeakAlert)
        rig.controller.tearDown()
        #expect(!rig.controller.showsNothingToSpeakAlert)
    }

    /// Review P1: a playing ⏭ onto an image-only final chapter used to end the session
    /// while the engine kept speaking the previous chapter, with no stop control.
    @Test func playingSkipOntoImageOnlyLastChapterKeepsAStoppableSession() async {
        let rig = Rig(status: .playing, unspeakable: ["ch6.xhtml"], at: 5)
        rig.skip(forward: true)
        await rig.controller.waitForStartTaskForTests()
        #expect(rig.controller.status == .playing)
        #expect(rig.controller.isSessionActive)
        #expect(rig.engine.status == .playing)
        #expect(rig.speechHref == "ch5.xhtml")
        #expect(rig.engine.spokenHrefs.isEmpty)
        #expect(rig.moves.isEmpty)
        #expect(rig.controller.showsNothingToSpeakAlert)
        rig.controller.stop()
        #expect(rig.controller.status == .stopped)
        #expect(rig.engine.status == .stopped)
    }

    @Test func skipBackOntoUnspeakableChapterKeepsGoingBack() async {
        let rig = Rig(status: .paused, unspeakable: ["ch2.xhtml"], at: 3)
        rig.skip(forward: false)
        await rig.controller.waitForStartTaskForTests()
        #expect(rig.controller.status == .paused)
        #expect(rig.speechHref == "ch1.xhtml")
        #expect(rig.moves == ["ch1.xhtml"])

        // Nothing speakable behind: stays put (paused at Ch 3) and says why.
        let stuck = Rig(status: .playing, unspeakable: ["ch1.xhtml", "ch2.xhtml"], at: 3)
        stuck.skip(forward: false)
        await stuck.controller.waitForStartTaskForTests()
        #expect(stuck.controller.status == .playing)
        #expect(stuck.speechHref == "ch3.xhtml")
        #expect(stuck.moves.isEmpty)
        #expect(stuck.controller.showsNothingToSpeakAlert)
    }

    /// Review P2: Kokoro "plays" a chapter it renders no audio for and reports a natural
    /// finish before the first word. While a paused re-anchor is pending, that must not
    /// unpause the session, and the pending pause must not leak into a later Play.
    @Test func silentChapterAfterPausedSkipStaysPausedAndLeavesNoPendingPause() async {
        let rig = Rig(status: .paused, unspeakable: [], at: 2)
        rig.engine.silentHrefs = ["ch3.xhtml"]
        rig.skip(forward: true)
        await rig.controller.waitForStartTaskForTests()
        #expect(rig.engine.spokenHrefs == ["ch3.xhtml"])
        rig.controller.handleEngineStatusChange(.stopped)
        await rig.controller.waitForStartTaskForTests()
        #expect(rig.controller.status == .paused)
        #expect(rig.speechHref == "ch4.xhtml")
        #expect(rig.engine.spokenHrefs == ["ch3.xhtml", "ch4.xhtml"])

        // Same on the last chapter: the session ends, says why, and a fresh Play
        // somewhere else plays instead of pausing itself.
        let last = Rig(status: .paused, unspeakable: [], at: 5)
        last.engine.silentHrefs = ["ch6.xhtml"]
        last.skip(forward: true)
        await last.controller.waitForStartTaskForTests()
        last.controller.handleEngineStatusChange(.stopped)
        await last.controller.waitForStartTaskForTests()
        #expect(last.controller.status == .stopped)
        #expect(last.controller.showsNothingToSpeakAlert)
        last.controller.toggle(from: last.positions[0][0])
        await last.controller.waitForStartTaskForTests()
        #expect(last.controller.status == .playing)
    }

    /// Review P3 / T-535e P1 #3: an engine that goes `.unavailable` on a paused skip
    /// is neither stopped (which turned `.unavailable` back into `.stopped`) nor
    /// allowed to move the reader or advance `resumeLocator`.
    @Test func engineGoingUnavailableOnPausedSkipStaysUnavailable() async {
        let engine = SpeakingStub()
        let rig = Rig(status: .paused, unspeakable: [], at: 2, engine: engine)
        engine.goesUnavailable = true
        rig.skip(forward: true)
        await rig.controller.waitForStartTaskForTests()
        #expect(rig.controller.status == .unavailable)
        #expect(engine.stopCount == 0)
        #expect(rig.moves.isEmpty)
        #expect(rig.speechHref == "ch2.xhtml")
        #expect(!rig.controller.showsNothingToSpeakAlert)
    }

    @Test func detachedSessionNeverRaisesTheReaderAlert() async {
        let rig = Rig(status: .paused, unspeakable: ["ch6.xhtml"], at: 5, isReaderOpen: false)
        rig.controller.reanchor(to: rig.positions[5][0], resumePlaying: false)
        await rig.controller.waitForStartTaskForTests()
        #expect(rig.controller.status == .paused)
        #expect(!rig.controller.showsNothingToSpeakAlert)
    }
}
#endif
