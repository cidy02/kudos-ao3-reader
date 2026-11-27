#if os(iOS)
import Foundation
import MediaPlayer
import ReadiumNavigator
import ReadiumShared
import SwiftData
import Testing
@testable import Kudos

/// T-535k: regression tests for Read Aloud follow-ups #4 (transport ownership),
/// #5 (close flush behind heard speech during unsettled jump), and #7 (hold-to-seek
/// saving an unheard target). Drives production handlers with controlled events
/// and bounded waits; no real audio hardware is started.
@MainActor
@Suite(.serialized)
struct ReadAloudFollowUpsTests {

    // MARK: - Helpers

    @MainActor
    private final class FollowUpAsyncGate {
        private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
        private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
        private(set) var enteredCount = 0
        private var released = false

        func enterAndWait() async {
            enteredCount += 1
            let waiters = enteredWaiters
            enteredWaiters.removeAll()
            waiters.forEach { $0.resume() }
            guard !released else { return }
            await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    if released || Task.isCancelled {
                        continuation.resume()
                    } else {
                        releaseWaiters.append(continuation)
                    }
                }
            } onCancel: {
                Task { @MainActor [weak self] in
                    self?.release()
                }
            }
        }

        func waitUntilEntered(count: Int = 1, timeout: Duration = .seconds(2)) async -> Bool {
            let deadline = ContinuousClock.now + timeout
            while enteredCount < count, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(5))
            }
            return enteredCount >= count
        }

        func release() {
            released = true
            let waiters = releaseWaiters
            releaseWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    @MainActor
    private final class FollowUpTTSService: TTSService {
        var status: TTSServiceStatus
        var spokenText: String = ""
        var speechEnergy: Double = 0
        var speechEnergySeed: Double = 0
        var availableVoices: [TTSVoice] = []
        var onStatusChange: ((TTSServiceStatus) -> Void)?
        var onSpokenTextChange: ((String) -> Void)?
        var onSpeechEnergyPulse: ((Double, Double) -> Void)?
        var onSpeechSpectrum: ((SpeechSpectrum) -> Void)?
        var onAudible: ((Locator) -> Void)?
        var onSpokenRange: ((Locator) -> Void)?

        var autoEmitFirstUtterance = true
        private(set) var spokenLocators: [Locator] = []
        private(set) var pauseCount = 0
        private(set) var resumeCount = 0
        private(set) var stopCount = 0

        init(status: TTSServiceStatus = .stopped) {
            self.status = status
        }

        func speak(units: [TTSSpeechUnit]) async throws -> Bool {
            status = .stopped
            guard let first = units.first(where: \.hasSpeakableText) else { return false }
            if let locator = first.locator {
                spokenLocators.append(locator)
            }
            status = .playing
            onStatusChange?(.playing)
            if autoEmitFirstUtterance {
                if let locator = first.locator {
                    onAudible?(locator)
                }
                spokenText = first.text
                onSpokenTextChange?(first.text)
            }
            return true
        }

        func emitUtterance(text: String, locator: Locator) {
            onAudible?(locator)
            spokenText = text
            onSpokenTextChange?(text)
        }

        func pause() {
            pauseCount += 1
            guard status == .playing else { return }
            status = .paused
            onStatusChange?(.paused)
        }

        func resume() {
            resumeCount += 1
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

    private final class FollowUpTestNavigator: @preconcurrency Navigator {
        let publication = Publication(manifest: Manifest())
        var currentLocation: Locator? { nil }
        func go(to locator: Locator, options: NavigatorGoOptions) async -> Bool { false }
        func go(to link: ReadiumShared.Link, options: NavigatorGoOptions) async -> Bool { false }
        func goForward(options: NavigatorGoOptions) async -> Bool { false }
        func goBackward(options: NavigatorGoOptions) async -> Bool { false }
    }

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

    private func makeLocator(
        chapter: Int,
        position: Int,
        progression: Double,
        totalProgression: Double
    ) -> Locator {
        Locator(
            href: AnyURL(string: "ch\(chapter).xhtml")!,
            mediaType: .xhtml,
            locations: .init(position: position)
        ).copy(locations: {
            $0.progression = progression
            $0.totalProgression = totalProgression
        })
    }

    private func makeChapterPositions(
        chapterCount: Int,
        positionsPerChapter: Int = 2
    ) -> (positions: [[Locator]], sections: [ReaderSection]) {
        let total = max(1, chapterCount * positionsPerChapter)
        let positions: [[Locator]] = (1...chapterCount).map { chapter in
            (0..<positionsPerChapter).map { offset in
                let global = (chapter - 1) * positionsPerChapter + offset + 1
                let chapProg = positionsPerChapter > 1
                    ? Double(offset) / Double(positionsPerChapter - 1)
                    : 0
                let totalProg = Double(global - 1) / Double(total)
                return makeLocator(
                    chapter: chapter,
                    position: global,
                    progression: chapProg,
                    totalProgression: totalProg
                )
            }
        }
        let rawTOC = (1...chapterCount).map { index in
            ReaderSectionBuilder.RawTOCEntry(title: "Chapter \(index)", spineIndex: index - 1)
        }
        let sections = ReaderSectionBuilder.build(
            tocEntries: rawTOC,
            spineHrefs: (1...chapterCount).map { "ch\($0).xhtml" }
        )
        return (positions, sections)
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    private func startActiveBookController(
        title: String,
        engine: FollowUpTTSService,
        chapterStarts: [Locator]
    ) async -> ReaderSpeechController {
        let controller = ReaderSpeechController()
        controller.seedSessionForTests(
            workID: UUID(),
            status: .stopped,
            isReaderOpen: true,
            ttsService: engine,
            unitProvider: { locator in
                [TTSSpeechUnit(text: "Prose in \(locator?.href.string ?? "").", locator: locator)]
            },
            resumeLocator: chapterStarts[0],
            chapterStartLocators: chapterStarts,
            title: title
        )
        controller.toggle(from: chapterStarts[0])
        await controller.waitForStartTaskForTests()
        return controller
    }

    // MARK: - #4: Transport ownership (Now Playing card & remote targets)

    @Test func idleControllerStopAndTearDownPreserveOwningControllerNowPlayingAndRemotes() async {
        let (positions, _) = makeChapterPositions(chapterCount: 2)
        let engine = FollowUpTTSService()
        let bookController = await startActiveBookController(
            title: "Active Book",
            engine: engine,
            chapterStarts: positions.compactMap(\.first)
        )
        defer { bookController.stop() }

        let rcc = MPRemoteCommandCenter.shared()
        #expect(bookController.status == .playing)
        #expect(bookController.isTransportOwnerForTests)
        #expect(bookController.remoteCommandsInstalledForTests)
        #expect(NowPlayingInfo.shared.media?.title == "Active Book")
        #expect(NowPlayingInfo.shared.playback.rate == 1)
        #expect(rcc.playCommand.isEnabled)
        #expect(rcc.pauseCommand.isEnabled)

        // Mirrors ReaderSpeechSettingsSection's idle auditionController stopping on exit.
        let idleAuditionController = ReaderSpeechController()
        idleAuditionController.stop()
        idleAuditionController.tearDown()

        #expect(bookController.status == .playing)
        #expect(bookController.isTransportOwnerForTests)
        #expect(bookController.remoteCommandsInstalledForTests)
        #expect(NowPlayingInfo.shared.media?.title == "Active Book")
        #expect(NowPlayingInfo.shared.playback.rate == 1)
        #expect(rcc.playCommand.isEnabled)
        #expect(rcc.pauseCommand.isEnabled)

        // Only the owning controller relinquishing transport clears the card and targets.
        bookController.stop()
        #expect(!bookController.isTransportOwnerForTests)
        #expect(!bookController.remoteCommandsInstalledForTests)
        #expect(NowPlayingInfo.shared.media == nil)
        #expect(NowPlayingInfo.shared.playback == nil)
        #expect(!rcc.playCommand.isEnabled)
        #expect(!rcc.pauseCommand.isEnabled)
    }

    @Test func auditionStopAfterPreviewPreservesPausedBookNowPlayingAndRemotes() async {
        let (positions, _) = makeChapterPositions(chapterCount: 2)
        let bookEngine = FollowUpTTSService()
        let bookController = await startActiveBookController(
            title: "Paused Book",
            engine: bookEngine,
            chapterStarts: positions.compactMap(\.first)
        )
        defer { bookController.stop() }

        // Exact ReaderSpeechSettingsSection.audition(_:) sequence: pause book, play sample, stop sample.
        bookController.pause()
        #expect(bookController.status == .paused)
        #expect(NowPlayingInfo.shared.media?.title == "Paused Book")
        #expect(NowPlayingInfo.shared.playback.rate == 0)

        let auditionEngine = FollowUpTTSService()
        let auditionController = ReaderSpeechController()
        auditionController.seedSessionForTests(
            workID: UUID(),
            status: .stopped,
            isReaderOpen: false,
            isAuditioning: true,
            ttsService: auditionEngine
        )
        auditionController.audition(text: "Sample voice preview.")
        await auditionController.waitForStartTaskForTests()
        #expect(auditionController.isPlaying)
        #expect(!auditionController.isTransportOwnerForTests)

        auditionController.stop()

        let rcc = MPRemoteCommandCenter.shared()
        #expect(bookController.isTransportOwnerForTests)
        #expect(bookController.remoteCommandsInstalledForTests)
        #expect(NowPlayingInfo.shared.media?.title == "Paused Book")
        #expect(NowPlayingInfo.shared.playback.rate == 0)
        #expect(rcc.playCommand.isEnabled)
        let remotePlayStatus = bookController.handleRemotePlayForTests()
        #expect(remotePlayStatus == .success)
        #expect(bookController.status == .playing)
        #expect(NowPlayingInfo.shared.playback.rate == 1)
    }

    @Test func formerTransportOwnerStoppingAfterHandoffDoesNotClearNewOwner() async {
        let (positions, _) = makeChapterPositions(chapterCount: 2)
        let firstEngine = FollowUpTTSService()
        let first = await startActiveBookController(
            title: "First Book",
            engine: firstEngine,
            chapterStarts: positions.compactMap(\.first)
        )
        let secondEngine = FollowUpTTSService()
        let second = await startActiveBookController(
            title: "Second Book",
            engine: secondEngine,
            chapterStarts: positions.compactMap(\.first)
        )
        defer {
            first.stop()
            second.stop()
        }

        #expect(!first.isTransportOwnerForTests)
        #expect(!first.remoteCommandsInstalledForTests)
        #expect(second.isTransportOwnerForTests)
        #expect(NowPlayingInfo.shared.media?.title == "Second Book")

        // A late stop/tearDown on the former owner must leave the new owner intact.
        first.stop()
        first.tearDown()

        let rcc = MPRemoteCommandCenter.shared()
        #expect(second.isTransportOwnerForTests)
        #expect(second.remoteCommandsInstalledForTests)
        #expect(NowPlayingInfo.shared.media?.title == "Second Book")
        #expect(NowPlayingInfo.shared.playback.rate == 1)
        #expect(rcc.playCommand.isEnabled)
    }

    // MARK: - #5: Close flush never lags behind heard speech

    @Test func closeDuringUnsettledSpeechChapterSkipFlushesHeardChapterNotPreJumpLocator() async throws {
        let context = try makeContext()
        let (positions, sections) = makeChapterPositions(chapterCount: 4)
        let ch1 = positions[0][0]
        let ch1Late = positions[0][1]
        let ch2 = positions[1][0]
        let ch1String = try #require(ch1.persistenceString)

        let work = SavedWork(title: "Skip Race", author: "Author")
        work.readiumLocator = ch1String
        context.insert(work)
        try context.save()

        let book = ReadiumBook()
        book.seedChaptersForTests(positions, current: ch1)
        let jumpGate = FollowUpAsyncGate()
        var jumpedHrefs: [String] = []
        book.testGoToLocator = { locator in
            jumpedHrefs.append(locator.href.string)
            await jumpGate.enterAndWait()
            return true
        }
        defer { jumpGate.release() }

        let persistence = ReadiumProgressPersistence()
        persistence.seed(persistedLocatorString: ch1String)
        defer { persistence.cancelTrailingWrite() }
        book.onLocatorChange = { locator in
            guard let string = locator.persistenceString else { return }
            persistence.note(locatorString: string, totalProgression: locator.locations.totalProgression)
        }

        let engine = FollowUpTTSService(status: .playing)
        let controller = ReaderSpeechController()
        controller.seedSessionForTests(
            workID: work.id,
            status: .playing,
            isReaderOpen: true,
            ttsService: engine,
            unitProvider: { locator in
                [TTSSpeechUnit(text: "Spoken in \(locator?.href.string ?? "").", locator: locator)]
            },
            resumeLocator: ch1,
            chapterStartLocators: positions.compactMap(\.first),
            title: work.title
        )
        defer { controller.stop() }
        controller.onAdvance = { locator in
            book.goForSpeech(to: locator)
        }

        // Explicit Skip Forward to ch2; ch2 becomes audible while navigator jump is suspended.
        controller.reanchor(to: ch2, resumePlaying: true, direction: .forward, isManualSkip: true)
        await controller.waitForStartTaskForTests()
        let enteredJump = await jumpGate.waitUntilEntered()
        #expect(enteredJump)
        #expect(jumpedHrefs == ["ch2.xhtml"])
        #expect(book.currentLocator?.href.string == "ch1.xhtml")
        #expect(book.hasSpeechJumpInFlight)

        // A stale pre-jump settle from ch1 during the jump must not regress the flush target.
        let nav = FollowUpTestNavigator()
        book.navigator(nav, locationDidChange: ch1Late)
        #expect(book.locatorForProgressFlush?.href.string == "ch2.xhtml")

        // Close before navigator.go(to: ch2) settles -> must persist ch2, never ch1.
        let wrote = ReadiumReaderPersistence.flushProgress(
            liveLocator: book.locatorForProgressFlush,
            work: work,
            sections: sections,
            progressPersistence: persistence,
            allowsPersistence: true,
            exitCommitted: false,
            shelfStamp: true,
            in: context
        )
        #expect(wrote)
        #expect(work.readiumLocator.contains("ch2.xhtml"))
        #expect(work.lastSpineIndex == 1)

        // Subsequent detach + immediate Stop keeps ch2 on disk.
        let leaveAction = controller.readerDidClose(workID: work.id)
        #expect(leaveAction == .detach)
        controller.stop()
        #expect(work.readiumLocator.contains("ch2.xhtml"))
        #expect(work.lastSpineIndex == 1)

        jumpGate.release()
        let finished = await waitUntil { !book.hasSpeechJumpInFlight }
        #expect(finished)
    }

    @Test func closeAfterSpeechJumpReturnsWithoutSettleStillFlushesHeardChapter() async throws {
        let context = try makeContext()
        let (positions, sections) = makeChapterPositions(chapterCount: 3)
        let ch1 = positions[0][0]
        let ch1Late = positions[0][1]
        let ch2 = positions[1][0]
        let ch1String = try #require(ch1.persistenceString)

        let work = SavedWork(title: "Late Settle", author: "Author")
        work.readiumLocator = ch1String
        context.insert(work)
        try context.save()

        let book = ReadiumBook()
        book.seedChaptersForTests(positions, current: ch1)
        // Navigator returns without delivering locationDidChange(ch2) yet.
        book.testGoToLocator = { _ in true }

        let persistence = ReadiumProgressPersistence()
        persistence.seed(persistedLocatorString: ch1String)
        defer { persistence.cancelTrailingWrite() }

        book.goForSpeech(to: ch2)
        let jumpDone = await waitUntil { !book.hasSpeechJumpInFlight }
        #expect(jumpDone)
        #expect(book.currentLocator?.href.string == "ch1.xhtml")

        // Even a stale ch1 echo after go(to:) returned must not clear pending ch2.
        let nav = FollowUpTestNavigator()
        book.navigator(nav, locationDidChange: ch1Late)
        #expect(book.locatorForProgressFlush?.href.string == "ch2.xhtml")

        ReadiumReaderPersistence.flushProgress(
            liveLocator: book.locatorForProgressFlush,
            work: work,
            sections: sections,
            progressPersistence: persistence,
            allowsPersistence: true,
            exitCommitted: false,
            shelfStamp: true,
            in: context
        )
        #expect(work.readiumLocator.contains("ch2.xhtml"))
        #expect(work.lastSpineIndex == 1)
    }

    @Test func laterUserNavigationSupersedesPendingSpeechLocatorOnClose() async throws {
        let context = try makeContext()
        let (positions, sections) = makeChapterPositions(chapterCount: 4)
        let ch1 = positions[0][0]
        let ch2 = positions[1][0]
        let ch4 = positions[3][0]
        let ch1String = try #require(ch1.persistenceString)

        let work = SavedWork(title: "User Wins", author: "Author")
        work.readiumLocator = ch1String
        context.insert(work)
        try context.save()

        let book = ReadiumBook()
        book.seedChaptersForTests(positions, current: ch1)
        let ch2Gate = FollowUpAsyncGate()
        book.testGoToLocator = { locator in
            if locator.href.string == "ch2.xhtml" {
                await ch2Gate.enterAndWait()
            }
            return true
        }
        defer { ch2Gate.release() }

        let persistence = ReadiumProgressPersistence()
        persistence.seed(persistedLocatorString: ch1String)
        defer { persistence.cancelTrailingWrite() }

        // Speech jump to ch2 is in flight, then user manually jumps to ch4.
        book.goForSpeech(to: ch2)
        let entered = await ch2Gate.waitUntilEntered()
        #expect(entered)
        #expect(book.pendingSpeechLocator?.href.string == "ch2.xhtml")

        book.go(to: ch4)
        let nav = FollowUpTestNavigator()
        book.navigator(nav, locationDidChange: ch4)
        #expect(book.pendingSpeechLocator == nil)
        #expect(book.locatorForProgressFlush?.href.string == "ch4.xhtml")

        ch2Gate.release()
        let settled = await waitUntil { !book.hasSpeechJumpInFlight }
        #expect(settled)

        ReadiumReaderPersistence.flushProgress(
            liveLocator: book.locatorForProgressFlush,
            work: work,
            sections: sections,
            progressPersistence: persistence,
            allowsPersistence: true,
            exitCommitted: false,
            shelfStamp: true,
            in: context
        )
        #expect(work.readiumLocator.contains("ch4.xhtml"))
        #expect(work.lastSpineIndex == 3)

        // Post-settle: speech settles on ch2, then user turns back to ch1 -> ch1 wins.
        book.goForSpeech(to: ch2)
        let settledSpeech = await waitUntil { !book.hasSpeechJumpInFlight }
        #expect(settledSpeech)
        book.navigator(nav, locationDidChange: ch2)
        #expect(book.pendingSpeechLocator == nil)

        _ = book.beginExplicitUserTurn()
        book.navigator(nav, locationDidChange: ch1)
        #expect(book.locatorForProgressFlush?.href.string == "ch1.xhtml")
        ReadiumReaderPersistence.flushProgress(
            liveLocator: book.locatorForProgressFlush,
            work: work,
            sections: sections,
            progressPersistence: persistence,
            allowsPersistence: true,
            exitCommitted: false,
            shelfStamp: true,
            in: context
        )
        #expect(work.readiumLocator.contains("ch1.xhtml"))
        #expect(work.lastSpineIndex == 0)
    }

    // MARK: - #7: Hold-to-seek keeps target separate until speech reaches it

    @Test func pausedHoldToSeekReleaseAndCloseWithoutPlayNeverMovesNavigatorOrPersistsTarget() async throws {
        let context = try makeContext()
        let (positions, sections) = makeChapterPositions(chapterCount: 2, positionsPerChapter: 6)
        let pos1 = positions[0][0]
        let pos1String = try #require(pos1.persistenceString)

        let work = SavedWork(title: "Hold Seek Paused", author: "Author")
        work.readiumLocator = pos1String
        context.insert(work)
        try context.save()

        let book = ReadiumBook()
        book.seedChaptersForTests(positions, current: pos1)
        var navigatedPositions: [Int] = []
        book.testGoToLocator = { locator in
            if let pos = locator.locations.position {
                navigatedPositions.append(pos)
            }
            return true
        }

        let persistence = ReadiumProgressPersistence()
        persistence.seed(persistedLocatorString: pos1String)
        defer { persistence.cancelTrailingWrite() }

        let engine = FollowUpTTSService(status: .paused)
        let controller = ReaderSpeechController()
        var detachedSaves: [String] = []
        controller.onSavePosition = { _, locatorString, _, _, date, _ in
            detachedSaves.append(locatorString)
            return .wrote(progressStamp: date)
        }
        controller.seedSessionForTests(
            workID: work.id,
            status: .paused,
            isReaderOpen: true,
            ttsService: engine,
            unitProvider: { locator in
                [TTSSpeechUnit(text: "Prose.", locator: locator)]
            },
            resumeLocator: pos1,
            chapterStartLocators: positions.compactMap(\.first),
            title: work.title
        )
        defer { controller.stop() }
        controller.onAdvance = { locator in
            book.goForSpeech(to: locator)
        }

        // Pause -> hold Next for 3 ticks -> release without pressing Play.
        var tickTargets: [Int] = []
        for _ in 0..<3 {
            let next = try #require(book.nextSpeechSeekLocator(
                forward: true,
                pendingSeekLocator: controller.pendingSeekLocator,
                speechLocator: controller.resumeLocator,
                followsSpeech: false
            ))
            controller.noteSeekLocator(next)
            if let pos = next.locations.position {
                tickTargets.append(pos)
            }
        }
        controller.finishSeekHold(resumePlaying: false)

        #expect(tickTargets == [2, 3, 4])
        #expect(controller.pendingSeekLocator?.locations.position == 4)
        #expect(controller.resumeLocator?.locations.position == 1)
        #expect(navigatedPositions.isEmpty)
        #expect(book.currentLocator?.locations.position == 1)
        #expect(book.locatorForProgressFlush?.locations.position == 1)

        // Closing the reader without pressing Play must NOT persist the unheard seek target.
        let wrote = ReadiumReaderPersistence.flushProgress(
            liveLocator: book.locatorForProgressFlush,
            work: work,
            sections: sections,
            progressPersistence: persistence,
            allowsPersistence: true,
            exitCommitted: false,
            shelfStamp: true,
            in: context
        )
        #expect(!wrote)
        #expect(work.readiumLocator == pos1String)

        _ = controller.readerDidClose(workID: work.id)
        controller.stop()
        #expect(controller.pendingSeekLocator == nil)
        #expect(detachedSaves.isEmpty)
        #expect(work.readiumLocator == pos1String)
    }

    @Test func pausedHoldToSeekThenPlayMovesNavigatorAndPersistsOnlyWhenAudible() async throws {
        let context = try makeContext()
        let (positions, sections) = makeChapterPositions(chapterCount: 2, positionsPerChapter: 6)
        let pos1 = positions[0][0]
        let pos4 = positions[0][3]
        let pos1String = try #require(pos1.persistenceString)

        let work = SavedWork(title: "Hold Seek Play", author: "Author")
        work.readiumLocator = pos1String
        context.insert(work)
        try context.save()

        let book = ReadiumBook()
        book.seedChaptersForTests(positions, current: pos1)
        var navigatedPositions: [Int] = []
        book.testGoToLocator = { locator in
            if let pos = locator.locations.position {
                navigatedPositions.append(pos)
            }
            return true
        }

        let persistence = ReadiumProgressPersistence()
        persistence.seed(persistedLocatorString: pos1String)
        defer { persistence.cancelTrailingWrite() }

        let engine = FollowUpTTSService(status: .paused)
        engine.autoEmitFirstUtterance = false
        let controller = ReaderSpeechController()
        controller.seedSessionForTests(
            workID: work.id,
            status: .paused,
            isReaderOpen: true,
            ttsService: engine,
            unitProvider: { locator in
                [TTSSpeechUnit(text: "Prose at seek target.", locator: locator)]
            },
            resumeLocator: pos1,
            chapterStartLocators: positions.compactMap(\.first),
            title: work.title
        )
        defer { controller.stop() }
        controller.onAdvance = { locator in
            book.goForSpeech(to: locator)
        }

        // First paused hold: 2 ticks -> pos 3; release paused.
        for _ in 0..<2 {
            let next = try #require(book.nextSpeechSeekLocator(
                forward: true,
                pendingSeekLocator: controller.pendingSeekLocator,
                speechLocator: controller.resumeLocator,
                followsSpeech: false
            ))
            controller.noteSeekLocator(next)
        }
        controller.finishSeekHold(resumePlaying: false)
        #expect(controller.pendingSeekLocator?.locations.position == 3)

        // Second paused hold continues from pos 3 -> pos 4.
        let thirdTick = try #require(book.nextSpeechSeekLocator(
            forward: true,
            pendingSeekLocator: controller.pendingSeekLocator,
            speechLocator: controller.resumeLocator,
            followsSpeech: false
        ))
        controller.noteSeekLocator(thirdTick)
        controller.finishSeekHold(resumePlaying: false)
        #expect(controller.pendingSeekLocator?.locations.position == 4)

        // Pressing Play targets pos 4, but before audio is audible nothing moves or persists.
        controller.toggle(from: nil)
        await controller.waitForStartTaskForTests()
        #expect(engine.spokenLocators.last?.locations.position == 4)
        #expect(controller.resumeLocator?.locations.position == 1)
        #expect(navigatedPositions.isEmpty)
        #expect(book.locatorForProgressFlush?.locations.position == 1)

        // Once speech reaches pos 4, navigator jumps and close flush writes pos 4.
        engine.emitUtterance(text: "Prose at seek target.", locator: pos4)
        let jumped = await waitUntil { navigatedPositions == [4] }
        #expect(jumped)
        #expect(controller.resumeLocator?.locations.position == 4)
        #expect(controller.pendingSeekLocator == nil)
        #expect(book.locatorForProgressFlush?.locations.position == 4)

        let wrote = ReadiumReaderPersistence.flushProgress(
            liveLocator: book.locatorForProgressFlush,
            work: work,
            sections: sections,
            progressPersistence: persistence,
            allowsPersistence: true,
            exitCommitted: false,
            shelfStamp: true,
            in: context
        )
        #expect(wrote)
        #expect(Locator(persistenceString: work.readiumLocator)?.locations.position == 4)
    }

    @Test func playingHoldToSeekCommitsOnAudibleAndResumesWhenAtChapterBound() async throws {
        let (positions, _) = makeChapterPositions(chapterCount: 2, positionsPerChapter: 4)
        let pos1 = positions[0][0]
        let pos3 = positions[0][2]
        let pos4 = positions[0][3]

        let book = ReadiumBook()
        book.seedChaptersForTests(positions, current: pos1)
        var navigatedPositions: [Int] = []
        book.testGoToLocator = { locator in
            if let pos = locator.locations.position {
                navigatedPositions.append(pos)
            }
            return true
        }

        let engine = FollowUpTTSService(status: .playing)
        engine.autoEmitFirstUtterance = false
        let controller = ReaderSpeechController()
        controller.seedSessionForTests(
            workID: UUID(),
            status: .playing,
            isReaderOpen: true,
            ttsService: engine,
            unitProvider: { locator in
                [TTSSpeechUnit(text: "Prose.", locator: locator)]
            },
            resumeLocator: pos1,
            chapterStartLocators: positions.compactMap(\.first),
            title: "Playing Hold"
        )
        defer { controller.stop() }
        controller.onAdvance = { locator in
            book.goForSpeech(to: locator)
        }

        // Playing hold: pauses, steps 2 ticks to pos 3 without moving navigator, then releases.
        let wasPlaying = controller.isPlaying
        controller.noteSeekLocator(nil)
        controller.pause()
        for _ in 0..<2 {
            let next = try #require(book.nextSpeechSeekLocator(
                forward: true,
                pendingSeekLocator: controller.pendingSeekLocator,
                speechLocator: controller.resumeLocator,
                followsSpeech: wasPlaying
            ))
            controller.noteSeekLocator(next)
        }
        #expect(navigatedPositions.isEmpty)
        #expect(controller.resumeLocator?.locations.position == 1)
        #expect(controller.pendingSeekLocator?.locations.position == 3)

        controller.finishSeekHold(resumePlaying: wasPlaying)
        await controller.waitForStartTaskForTests()
        #expect(engine.spokenLocators.last?.locations.position == 3)
        #expect(navigatedPositions.isEmpty)
        #expect(controller.resumeLocator?.locations.position == 1)

        engine.emitUtterance(text: "Prose.", locator: pos3)
        let jumped = await waitUntil { navigatedPositions == [3] }
        #expect(jumped)
        #expect(controller.resumeLocator?.locations.position == 3)
        #expect(controller.status == .playing)

        // Playing hold at the end of the chapter (0 valid ticks): release resumes playback.
        book.seedChaptersForTests(positions, current: pos4)
        controller.noteSeekLocator(nil)
        controller.pause()
        let outOfBounds = book.nextSpeechSeekLocator(
            forward: true,
            pendingSeekLocator: controller.pendingSeekLocator,
            speechLocator: pos4,
            followsSpeech: true
        )
        #expect(outOfBounds == nil)
        controller.finishSeekHold(resumePlaying: true)
        #expect(engine.resumeCount == 1)
        #expect(controller.status == .playing)
    }
}
#endif
