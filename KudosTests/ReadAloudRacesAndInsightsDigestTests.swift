import Foundation
#if os(iOS)
import ReadiumNavigator
import ReadiumShared
#endif
import SwiftData
import Testing
@testable import Kudos

/// T-535e: reproduction and regression tests for the Codex T-535d review findings
/// (suspending scan/engine races, real Readium empty-XHTML chapter boundaries,
/// engine startup cancellation / pause-before-enqueue, and Insights per-record digest + O(1) save filter).
@MainActor
@Suite(.serialized)
struct ReadAloudRacesAndInsightsDigestTests {
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

    // MARK: - Finding 8: Insights digest per-record accuracy

    @Test func insightsDigestDetectsRatingSwapMetadataSoftDeletedAndOlderSittingEdits() throws {
        let context = try makeContext()
        let workA = SavedWork(title: "Work A", author: "Author")
        workA.isSaved = true
        workA.rating = "General Audiences"
        workA.wordCount = 5_000
        workA.isComplete = false
        workA.readiumLocator = #"{"href":"ch1.xhtml","locations":{"totalProgression":0.2}}"#
        workA.lastReadDate = Date(timeIntervalSince1970: 5_000)

        let workB = SavedWork(title: "Work B", author: "Author")
        workB.isSaved = true
        workB.rating = "Explicit"
        workB.wordCount = 5_000
        workB.isComplete = true

        let deleted = SavedWork(title: "In Recently Deleted", author: "Author")
        deleted.isSaved = true
        deleted.rating = "General Audiences"
        deleted.isPendingDeletion = true

        context.insert(workA)
        context.insert(workB)
        context.insert(deleted)

        let olderSession = ReadingSession(
            workID: workA.id,
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 1_600),
            durationSeconds: 600,
            lastModifiedAt: Date(timeIntervalSince1970: 2_000)
        )
        let newerSession = ReadingSession(
            workID: workB.id,
            startedAt: Date(timeIntervalSince1970: 8_000),
            endedAt: Date(timeIntervalSince1970: 8_600),
            durationSeconds: 600,
            lastModifiedAt: Date(timeIntervalSince1970: 9_000)
        )
        context.insert(olderSession)
        context.insert(newerSession)
        try context.save()

        let liveWorks = [workA, workB]
        var previous = InsightsReloadDigest.make(works: liveWorks, context: context)

        func expectChanged(_ reason: Comment) {
            let next = InsightsReloadDigest.make(works: liveWorks, context: context)
            #expect(next != previous, reason)
            previous = next
        }

        // 1. Swap ratings between A and B in a single batch (total adult count stays 1).
        workA.rating = "Explicit"
        workB.rating = "General Audiences"
        try context.save()
        expectChanged("rating swap A General->Explicit, B Explicit->General must change digest")

        // 2. General -> Teen (neither is adult, still changes Taste rating breakdown).
        workB.rating = "Teen And Up Audiences"
        try context.save()
        expectChanged("General -> Teen rating change must change digest")

        // 3. WIP becomes complete (changes WIP freshness and status buckets).
        workA.isComplete = true
        try context.save()
        expectChanged("WIP becoming complete must change digest")

        // 4. Soft-deleted work rating changes (affects sitting privacy classification).
        deleted.rating = "Explicit"
        try context.save()
        expectChanged("soft-deleted work rating change must change digest")

        // 5. Older sitting updated with incoming edit stamp still below newest sitting's stamp.
        olderSession.durationSeconds = 1_200
        olderSession.lastModifiedAt = Date(timeIntervalSince1970: 5_000)
        try context.save()
        expectChanged("older sitting edit below newest timestamp must change digest")
    }

    @Test func reloadTrackerFiltersPositionSavesInFastPathAndCatchesRelevantSaves() throws {
        let context = try makeContext()
        let now = Date(timeIntervalSince1970: 200_000)

        let workA = SavedWork(title: "Active WIP", author: "Author")
        workA.isSaved = true
        workA.rating = "General Audiences"
        workA.wordCount = 10_000
        workA.isComplete = false
        workA.readiumLocator = #"{"href":"ch1.xhtml","locations":{"totalProgression":0.25}}"#
        workA.lastReadDate = now.addingTimeInterval(-300)
        workA.lastModifiedAt = now.addingTimeInterval(-300)

        let workB = SavedWork(title: "Adult Fic", author: "Author")
        workB.isSaved = true
        workB.rating = "Explicit"
        workB.wordCount = 8_000
        workB.isComplete = true

        let deleted = SavedWork(title: "Deleted Fic", author: "Author")
        deleted.isSaved = true
        deleted.rating = "General Audiences"
        deleted.isPendingDeletion = true

        context.insert(workA)
        context.insert(workB)
        context.insert(deleted)
        try context.save()

        let liveWorks = [workA, workB]
        let tracker = InsightsReloadTracker()
        let baseDigest = tracker.recordBaseline(works: liveWorks, context: context, now: now)

        var capturedNotifications: [Notification] = []
        let observer = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: context,
            queue: nil
        ) { notification in
            capturedNotifications.append(notification)
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        func saveAndCapture() throws -> Notification {
            capturedNotifications.removeAll()
            try context.save()
            return try #require(capturedNotifications.last)
        }

        // 1. Ordinary detached Read Aloud mid-chapter position save -> fast-path `.ignored`!
        workA.applyDebouncedReadiumLocator(
            #"{"href":"ch2.xhtml","locations":{"totalProgression":0.42}}"#,
            at: now.addingTimeInterval(-10)
        )
        workA.lastSpineIndex = 1
        workA.lastScrollFraction = 0.4
        let posNote = try saveAndCapture()
        #expect(tracker.classifySave(posNote, context: context, now: now) == .ignored)
        #expect(!tracker.shouldReload(afterSave: posNote, works: liveWorks, context: context, now: now))

        // 2. Unrelated model (Bookmark) save -> fast-path `.ignored`!
        let bookmark = Bookmark(title: "Tag", urlString: "https://archiveofourown.org/tags/test")
        context.insert(bookmark)
        let bookmarkNote = try saveAndCapture()
        #expect(tracker.classifySave(bookmarkNote, context: context, now: now) == .ignored)
        #expect(!tracker.shouldReload(afterSave: bookmarkNote, works: liveWorks, context: context, now: now))

        // 3. Same-count rating swap (A General->Explicit, B Explicit->General) -> `.needsReload` + new digest!
        workA.rating = "Explicit"
        workB.rating = "General Audiences"
        let swapNote = try saveAndCapture()
        #expect(tracker.classifySave(swapNote, context: context, now: now) == .needsReload)
        #expect(tracker.shouldReload(afterSave: swapNote, works: liveWorks, context: context, now: now))
        let afterSwap = tracker.currentDigest(works: liveWorks, context: context, now: now)
        #expect(afterSwap != baseDigest)
        tracker.recordBaseline(works: liveWorks, context: context, now: now)

        // 4. Progress crossing WIP caught-up bucket (>= 0.98) -> `.needsReload` + new digest!
        workA.applyDebouncedReadiumLocator(
            #"{"href":"ch5.xhtml","locations":{"totalProgression":0.99}}"#,
            at: now
        )
        let caughtUpNote = try saveAndCapture()
        #expect(tracker.classifySave(caughtUpNote, context: context, now: now) == .needsReload)
        #expect(tracker.currentDigest(works: liveWorks, context: context, now: now) != afterSwap)
        let afterCaughtUp = tracker.recordBaseline(works: liveWorks, context: context, now: now)

        // 5. Soft-deleted work re-rated -> `.needsReload` + new digest!
        deleted.rating = "Explicit"
        let deletedNote = try saveAndCapture()
        #expect(tracker.classifySave(deletedNote, context: context, now: now) == .needsReload)
        #expect(tracker.currentDigest(works: liveWorks, context: context, now: now) != afterCaughtUp)
        let afterDeleted = tracker.recordBaseline(works: liveWorks, context: context, now: now)

        // 6. Unread work started -> `.needsReload` + new digest!
        workB.readiumLocator = #"{"href":"ch1.xhtml","locations":{"totalProgression":0.05}}"#
        let startedNote = try saveAndCapture()
        #expect(tracker.classifySave(startedNote, context: context, now: now) == .needsReload)
        #expect(tracker.currentDigest(works: liveWorks, context: context, now: now) != afterDeleted)
    }

    @Test func sameDayDateAddedCorrectionChangesSignatureAndDigest() throws {
        let context = try makeContext()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day = Date(timeIntervalSince1970: 1_699_920_000)
        let work = SavedWork(title: "W", author: "A")
        work.isSaved = true
        work.dateAdded = day.addingTimeInterval(22 * 3_600)
        context.insert(work)
        try context.save()
        let before = InsightsReloadDigest.workSignature(work, calendar: calendar)
        let digestBefore = InsightsReloadDigest.make(works: [work], context: context, calendar: calendar)
        work.dateAdded = day.addingTimeInterval(8 * 3_600)
        try context.save()
        #expect(calendar.isDate(work.dateAdded, inSameDayAs: day.addingTimeInterval(22 * 3_600)))
        #expect(InsightsReloadDigest.workSignature(work, calendar: calendar) != before)
        #expect(InsightsReloadDigest.make(works: [work], context: context, calendar: calendar) != digestBefore)
    }

    @Test func cancelledCoalescerTaskCannotEraseItsSuccessor() async {
        let coalescer = InsightsSaveCoalescer(interval: .milliseconds(80))
        var fired: [String] = []
        coalescer.schedule { fired.append("A") }
        coalescer.cancel()
        coalescer.schedule { fired.append("B") }
        // Let the cancelled A task wake and unwind; it must not clear B's handle.
        try? await Task.sleep(for: .milliseconds(20))
        #expect(coalescer.hasPendingRefresh)
        coalescer.schedule { fired.append("C") }
        try? await Task.sleep(for: .milliseconds(200))
        #expect(fired == ["B"])
        #expect(!coalescer.hasPendingRefresh)
    }

    @Test func coordinatorReloadsOnceWithOneSnapshotForSameCountEditAndNotForPositionSave() async throws {
        let context = try makeContext()
        let a = SavedWork(title: "A", author: "x")
        a.isSaved = true
        a.rating = "General Audiences"
        a.readiumLocator = #"{"href":"c1.xhtml","locations":{"totalProgression":0.2}}"#
        a.lastReadDate = Date()
        let b = SavedWork(title: "B", author: "x")
        b.isSaved = true
        b.rating = "Explicit"
        context.insert(a)
        context.insert(b)
        try context.save()
        let works = [a, b]
        let coordinator = InsightsReloadCoordinator(interval: .milliseconds(40))
        coordinator.tracker.recordBaseline(works: works, context: context)

        var notes: [Notification] = []
        let observer = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: context, queue: nil
        ) { notes.append($0) }
        defer { NotificationCenter.default.removeObserver(observer) }
        var snapshots: [InsightsReloadDigest.Snapshot] = []
        func feed() {
            coordinator.noteSave(
                notes.last!, works: { works }, context: context,
                isOnScreen: { true }, reload: { snapshots.append($0) }
            )
        }

        a.applyDebouncedReadiumLocator(#"{"href":"c2.xhtml","locations":{"totalProgression":0.3}}"#, at: Date())
        try context.save()
        feed()
        try await Task.sleep(for: .milliseconds(120))
        #expect(snapshots.isEmpty)

        // Same count, rating swap, two saves inside one window -> one reload.
        a.rating = "Explicit"
        b.rating = "General Audiences"
        try context.save()
        feed()
        b.title = "B2"
        try context.save()
        feed()
        try await Task.sleep(for: .milliseconds(150))
        #expect(snapshots.count == 1)
        #expect(snapshots.first?.digest != coordinator.tracker.lastDigest)
    }

    @Test func refreshWalksTheLibraryOnceAndPositionSavesNeverWalk() async throws {
        let context = try makeContext()
        let a = SavedWork(title: "A", author: "x")
        a.isSaved = true
        a.rating = "General Audiences"
        a.readiumLocator = #"{"href":"c1.xhtml","locations":{"totalProgression":0.2}}"#
        a.lastReadDate = Date()
        context.insert(a)
        try context.save()
        let coordinator = InsightsReloadCoordinator(interval: .milliseconds(30))
        coordinator.tracker.recordBaseline(works: [a], context: context)
        var notes: [Notification] = []
        let observer = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: context, queue: nil
        ) { notes.append($0) }
        defer { NotificationCenter.default.removeObserver(observer) }
        var adopted = 0
        func feed(_ works: [SavedWork]) {
            coordinator.noteSave(
                notes.last!, works: { works }, context: context, isOnScreen: { true },
                reload: { snapshot in
                    coordinator.tracker.adopt(snapshot)
                    adopted += 1
                }
            )
        }
        let before = InsightsReloadDigest.snapshotCountForTests
        a.applyDebouncedReadiumLocator(#"{"href":"c2.xhtml","locations":{"totalProgression":0.3}}"#, at: Date())
        try context.save()
        feed([a])
        try await Task.sleep(for: .milliseconds(100))
        #expect(InsightsReloadDigest.snapshotCountForTests == before)

        // Membership grows while the refresh is pending: the refresh reads the array
        // when it fires, so its figures include the newcomer.
        a.rating = "Explicit"
        try context.save()
        var live = [a]
        coordinator.noteSave(
            notes.last!, works: { live }, context: context, isOnScreen: { true },
            reload: { snapshot in
                coordinator.tracker.adopt(snapshot)
                adopted += 1
            }
        )
        let b = SavedWork(title: "B", author: "x")
        b.isSaved = true
        context.insert(b)
        live.append(b)
        try await Task.sleep(for: .milliseconds(100))
        #expect(adopted == 1)
        #expect(InsightsReloadDigest.snapshotCountForTests == before + 1)
        #expect(coordinator.tracker.lastDigest.hasPrefix("2:"))
    }

    @Test func fullReloadCancelsAPendingSaveRefresh() async throws {
        let context = try makeContext()
        let a = SavedWork(title: "A", author: "x")
        a.isSaved = true
        a.rating = "General Audiences"
        context.insert(a)
        try context.save()
        let coordinator = InsightsReloadCoordinator(interval: .milliseconds(40))
        coordinator.tracker.recordBaseline(works: [a], context: context)
        var note: Notification?
        let observer = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: context, queue: nil
        ) { note = $0 }
        defer { NotificationCenter.default.removeObserver(observer) }
        a.rating = "Explicit"
        try context.save()
        var fired = 0
        coordinator.noteSave(
            note!, works: { [a] }, context: context, isOnScreen: { true }, reload: { _ in fired += 1 }
        )
        #expect(coordinator.hasPendingRefresh)
        coordinator.cancel() // what the view's reload() does first
        try await Task.sleep(for: .milliseconds(120))
        #expect(fired == 0)
    }

    @Test func insightsViewCancelsPendingRefreshOnReloadAndReloadsOnMembershipChange() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("kudos-ao3-reader/Features/Library/ReadingInsightsView.swift")
        let view = try String(contentsOf: url, encoding: .utf8)
        let reload = try #require(view.range(of: "private func reload(baseline:"))
        let head = String(view[reload.upperBound...].prefix(400))
        #expect(head.contains("reloadCoordinator.cancel()"))
        #expect(view.contains(".onChange(of: libraryWorks.map(\\.id))"))
        #expect(view.contains("reloadCoordinator.tracker.adopt($0)"))
    }

    @Test func reloadKeyChangesWithLibraryDigestAtSameCount() {
        func key(_ digest: String) -> String {
            InsightsReloadKey.make(
                range: "month", referenceDate: Date(timeIntervalSince1970: 0), hideMature: false,
                revealAll: false, includeHidden: false, countRereads: true, countReadAloud: true,
                askAboutUntouched: true, untouchedDays: 30, optionsRevision: 0,
                libraryCount: 2, libraryDigest: digest
            )
        }
        #expect(key("a") != key("b"))
    }

    @Test func saveCoalescerRefreshesWithinBoundedIntervalUnderContinuousSaves() async {
        let coalescer = InsightsSaveCoalescer(interval: .milliseconds(80))
        var fireCount = 0

        // Schedule saves spaced 30 ms apart (faster than the 80 ms interval) for 180 ms.
        // A debounce would starve until after the stream ends; a bounded coalescer must
        // still fire during the stream.
        for _ in 0..<6 {
            coalescer.schedule { fireCount += 1 }
            try? await Task.sleep(for: .milliseconds(30))
        }
        try? await Task.sleep(for: .milliseconds(120))
        #expect(fireCount >= 2)
        #expect(fireCount <= 4)
        coalescer.cancel()
    }
}

#if os(iOS)
extension ReadAloudRacesAndInsightsDigestTests {
    /// Manual gate so tests can suspend an async operation (extraction or engine startup)
    /// and interleave transport calls deterministically at the exact suspension point.
    @MainActor
    private final class AsyncGate {
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

        func waitUntilEntered(count: Int = 1) async {
            while enteredCount < count {
                await withCheckedContinuation { enteredWaiters.append($0) }
            }
        }

        func release() {
            released = true
            let waiters = releaseWaiters
            releaseWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    private enum EngineTestError: LocalizedError {
        case audioSessionFailed

        var errorDescription: String? { "Audio session unavailable" }
    }

    /// Controllable TTS engine that can suspend inside `speak`, defer or suppress
    /// its first utterance, go `.unavailable`, or throw on activation.
    @MainActor
    private final class ControllableTTSService: TTSService {
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

        var speakGate: AsyncGate?
        var goesUnavailable = false
        /// With `goesUnavailable`: also throws after publishing `.unavailable`
        /// (Sherpa's `engine.start()` failure).
        var throwsAfterUnavailable = false
        var returnsFalse = false
        var throwsOnSpeak = false
        var silentHrefs: Set<String> = []
        var autoEmitFirstUtterance = true
        /// Simulates a buggy/late engine callback firing even after `stop()` if callbacks weren't unbound.
        var emitPlayingAfterGateEvenIfStopped = false
        var speakFinishedGate: AsyncGate?

        private(set) var spokenHrefs: [String] = []
        private(set) var pauseCount = 0
        private(set) var resumeCount = 0
        private(set) var stopCount = 0

        init(status: TTSServiceStatus = .stopped) {
            self.status = status
        }

        func speak(units: [TTSSpeechUnit]) async throws -> Bool {
            status = .stopped
            if throwsOnSpeak {
                throw EngineTestError.audioSessionFailed
            }
            if goesUnavailable {
                status = .unavailable
                onStatusChange?(.unavailable)
                if throwsAfterUnavailable { throw EngineTestError.audioSessionFailed }
                return false
            }
            if returnsFalse {
                return false
            }
            if let speakGate {
                await speakGate.enterAndWait()
                if emitPlayingAfterGateEvenIfStopped {
                    status = .playing
                    onStatusChange?(.playing)
                    speakFinishedGate?.release()
                    return true
                }
            }
            guard let first = units.first(where: \.hasSpeakableText) else { return false }
            let href = first.locator?.href.string ?? ""
            spokenHrefs.append(href)
            status = .playing
            onStatusChange?(.playing)
            if autoEmitFirstUtterance, !silentHrefs.contains(href) {
                if let locator = first.locator {
                    onAudible?(locator)
                }
                spokenText = first.text
                onSpokenTextChange?(first.text)
            }
            return true
        }

        func emitNaturalFinish() {
            status = .stopped
            onStatusChange?(.stopped)
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

    private func chapterLocators(count: Int = 6) -> [Locator] {
        (1...count).map { index in
            Locator(
                href: AnyURL(string: "ch\(index).xhtml")!,
                mediaType: .xhtml,
                locations: .init(position: index)
            )
        }
    }

    // MARK: - Finding 1 [P1]: Pending skip must never persist unread chapter or hijack reopen

    @Test func detachedStopAndPauseDuringPendingSkipPersistLastCommittedPosition() async {
        let locators = chapterLocators(count: 4)
        let ch3Gate = AsyncGate()
        let engine = ControllableTTSService(status: .playing)
        let controller = ReaderSpeechController()
        let workID = UUID()
        var savedLocators: [String] = []

        controller.onSavePosition = { _, locatorString, _, _, date, _ in
            savedLocators.append(locatorString)
            return .wrote(progressStamp: date)
        }
        controller.seedSessionForTests(
            workID: workID,
            status: .playing,
            isReaderOpen: true,
            ttsService: engine,
            unitProvider: { locator in
                if locator?.href.string == "ch3.xhtml" {
                    await ch3Gate.enterAndWait()
                    return []
                }
                return [TTSSpeechUnit(text: "Prose in \(locator?.href.string ?? "").", locator: locator)]
            },
            resumeLocator: locators[1],
            chapterStartLocators: locators
        )

        // Detach into background listening and commit an utterance in ch2 so throttle allows checkpoints.
        _ = controller.readerDidClose(workID: workID)
        engine.emitUtterance(text: "Line in ch2.", locator: locators[1])
        #expect(savedLocators.count == 1)
        #expect(savedLocators[0].contains("ch2.xhtml"))

        // Start detached skip toward image-only ch3; suspend before extraction finishes.
        controller.reanchor(to: locators[2], resumePlaying: true, direction: .forward)
        await ch3Gate.waitUntilEntered()

        // Pause before extraction completes must NOT save ch3.
        controller.pause()
        #expect(savedLocators.last?.contains("ch2.xhtml") == true)
        #expect(!savedLocators.contains { $0.contains("ch3.xhtml") })

        // Stop before extraction completes must NOT save ch3.
        controller.stop()
        #expect(!savedLocators.contains { $0.contains("ch3.xhtml") })
        ch3Gate.release()
    }

    @Test func reopenMidPendingSkipFollowsLastCommittedPositionNotPendingTarget() async {
        let locators = chapterLocators(count: 4)
        let ch3Gate = AsyncGate()
        let engine = ControllableTTSService(status: .playing)
        let controller = ReaderSpeechController()
        let workID = UUID()

        controller.seedSessionForTests(
            workID: workID,
            status: .playing,
            isReaderOpen: true,
            ttsService: engine,
            unitProvider: { locator in
                if locator?.href.string == "ch3.xhtml" {
                    await ch3Gate.enterAndWait()
                    return []
                }
                return []
            },
            resumeLocator: locators[1],
            chapterStartLocators: locators
        )

        _ = controller.readerDidClose(workID: workID)
        controller.reanchor(to: locators[2], resumePlaying: true, direction: .forward)
        await ch3Gate.waitUntilEntered()

        var reattachedAdvances: [String] = []
        controller.readerDidOpen(workID: workID)
        controller.attachReader(
            workID: workID,
            onAdvance: { reattachedAdvances.append($0.href.string) },
            onSpokenRange: { _ in },
            onSessionEnded: {},
            onSkipPrevious: {},
            onSkipNext: { false }
        )

        #expect(reattachedAdvances == ["ch2.xhtml"])
        ch3Gate.release()
        await controller.waitForStartTaskForTests()
        #expect(controller.resumeLocator?.href.string == "ch2.xhtml")
    }

    @Test func failedScanDoesNotRollbackLiveUtteranceAdvancedDuringScan() async {
        let locators = chapterLocators(count: 4)
        let ch2Late = Locator(
            href: AnyURL(string: "ch2.xhtml")!,
            mediaType: .xhtml,
            locations: .init(position: 99)
        )
        let ch3Gate = AsyncGate()
        let engine = ControllableTTSService(status: .playing)
        let controller = ReaderSpeechController()

        controller.seedSessionForTests(
            workID: UUID(),
            status: .playing,
            isReaderOpen: true,
            ttsService: engine,
            unitProvider: { locator in
                if locator?.href.string == "ch3.xhtml" {
                    await ch3Gate.enterAndWait()
                }
                return []
            },
            resumeLocator: locators[1],
            chapterStartLocators: locators
        )

        controller.reanchor(to: locators[2], resumePlaying: true, direction: .forward)
        await ch3Gate.waitUntilEntered()

        // While scan is in flight, old engine keeps speaking to a later position in ch2.
        engine.emitUtterance(text: "Later sentence in ch2.", locator: ch2Late)

        // Scan exhausts with nothing speakable ahead: must keep ch2Late, not roll back!
        ch3Gate.release()
        await controller.waitForStartTaskForTests()
        #expect(controller.resumeLocator?.locations.position == 99)
    }

    // MARK: - Finding 2 [P1]: Reader close during engine startup unbinds old engine callbacks

    @Test func readerCloseDuringEngineStartupUnbindsOldEngineSoLatePlayingCannotResurrectSession() async {
        let locators = chapterLocators(count: 3)
        let speakGate = AsyncGate()
        let finishedGate = AsyncGate()
        let engine = ControllableTTSService(status: .stopped)
        engine.speakGate = speakGate
        engine.emitPlayingAfterGateEvenIfStopped = true
        engine.speakFinishedGate = finishedGate
        let controller = ReaderSpeechController()
        let workID = UUID()

        controller.seedSessionForTests(
            workID: workID,
            status: .stopped,
            isReaderOpen: true,
            ttsService: engine,
            unitProvider: { locator in
                [TTSSpeechUnit(text: "Prose.", locator: locator)]
            },
            resumeLocator: locators[0],
            chapterStartLocators: locators
        )

        controller.toggle(from: locators[0])
        await speakGate.waitUntilEntered()

        // Reader closes while `speak` is still suspended before `.playing`.
        let leaveAction = controller.readerDidClose(workID: workID)
        #expect(leaveAction == .tearDown)
        #expect(controller.status == .unavailable)

        // Wait until the suspended `speak` actually runs past the gate and tries to emit `.playing`.
        speakGate.release()
        await finishedGate.enterAndWait()
        #expect(controller.status == .unavailable)
        #expect(!controller.isSessionActive)
    }

    @Test func coreMLKokoroStopOrReaderCloseDuringStartupNeverPublishesPlayingOrStartsTask() async {
        let locators = chapterLocators(count: 3)

        // Case A: Reader closes while real CoreMLKokoroTTSService awaits startup setup.
        do {
            let setupGate = AsyncGate()
            let setupFinished = AsyncGate()
            let coreML = CoreMLKokoroTTSService()
            coreML.testSetupOverride = {
                await setupGate.enterAndWait()
                setupFinished.release()
            }
            let controller = ReaderSpeechController()
            let workID = UUID()
            controller.seedSessionForTests(
                workID: workID,
                status: .stopped,
                isReaderOpen: true,
                ttsService: coreML,
                unitProvider: { locator in
                    [TTSSpeechUnit(text: "Hello from Core ML.", locator: locator)]
                },
                resumeLocator: locators[0],
                chapterStartLocators: locators
            )

            controller.toggle(from: locators[0])
            await setupGate.waitUntilEntered()

            let action = controller.readerDidClose(workID: workID)
            #expect(action == .tearDown)
            setupGate.release()
            await setupFinished.enterAndWait()
            await Task.yield()

            #expect(!coreML.testDidStartPlaybackTask)
            #expect(coreML.status == .stopped)
            #expect(controller.status == .unavailable)
            #expect(!controller.isSessionActive)
        }

        // Case B: Stop pressed during replacement chapter's Core ML startup.
        do {
            let setupGate = AsyncGate()
            let setupFinished = AsyncGate()
            let coreML = CoreMLKokoroTTSService()
            coreML.testSetupOverride = {
                await setupGate.enterAndWait()
                setupFinished.release()
            }
            let controller = ReaderSpeechController()
            controller.seedSessionForTests(
                workID: UUID(),
                status: .playing,
                isReaderOpen: true,
                ttsService: coreML,
                unitProvider: { locator in
                    [TTSSpeechUnit(text: "Replacement chapter.", locator: locator)]
                },
                resumeLocator: locators[0],
                chapterStartLocators: locators
            )

            controller.reanchor(to: locators[1], resumePlaying: true, direction: .forward)
            await setupGate.waitUntilEntered()

            controller.stop()
            setupGate.release()
            await setupFinished.enterAndWait()
            await Task.yield()

            #expect(!coreML.testDidStartPlaybackTask)
            #expect(coreML.status == .stopped)
            #expect(controller.status == .stopped)
            #expect(!controller.isSessionActive)
        }
    }

    // MARK: - Finding 3 [P1]: Unplayable / failing engine must not move reader or advance cursor

    @Test func unavailableRefusingAndThrowingEngineNeverMoveReaderOrOverwriteResumeLocator() async {
        let locators = chapterLocators(count: 3)

        // Case A: engine goes `.unavailable` on final chapter.
        do {
            let engine = ControllableTTSService(status: .stopped)
            engine.goesUnavailable = true
            let controller = ReaderSpeechController()
            var moves: [String] = []
            controller.seedSessionForTests(
                workID: UUID(),
                status: .stopped,
                isReaderOpen: true,
                ttsService: engine,
                unitProvider: { locator in
                    locator?.href.string == "ch3.xhtml"
                        ? [TTSSpeechUnit(text: "Short final chapter.", locator: locator)]
                        : []
                },
                resumeLocator: locators[1],
                chapterStartLocators: locators
            )
            controller.onAdvance = { moves.append($0.href.string) }

            controller.toggle(from: locators[1])
            await controller.waitForStartTaskForTests()
            #expect(controller.status == .unavailable)
            #expect(moves.isEmpty)
            #expect(controller.resumeLocator?.href.string == "ch2.xhtml")
        }

        // Case B: engine throws on audio session activation.
        do {
            let engine = ControllableTTSService(status: .stopped)
            engine.throwsOnSpeak = true
            let controller = ReaderSpeechController()
            var moves: [String] = []
            controller.seedSessionForTests(
                workID: UUID(),
                status: .stopped,
                isReaderOpen: true,
                ttsService: engine,
                unitProvider: { locator in
                    locator?.href.string == "ch3.xhtml"
                        ? [TTSSpeechUnit(text: "Short final chapter.", locator: locator)]
                        : []
                },
                resumeLocator: locators[1],
                chapterStartLocators: locators
            )
            controller.onAdvance = { moves.append($0.href.string) }

            controller.toggle(from: locators[1])
            await controller.waitForStartTaskForTests()
            #expect(controller.status == .stopped)
            #expect(moves.isEmpty)
            #expect(controller.resumeLocator?.href.string == "ch2.xhtml")
            #expect(controller.speechErrorMessage == "Audio session unavailable")
            controller.readerDidClose(workID: controller.openReaderWorkID ?? UUID())
            #expect(controller.speechErrorMessage == nil)
        }

        // Case C: engine returns `true` (e.g. Kokoro priming) then emits `.stopped` with zero audio.
        do {
            let engine = ControllableTTSService(status: .stopped)
            engine.silentHrefs = ["ch3.xhtml"]
            let controller = ReaderSpeechController()
            var moves: [String] = []
            controller.seedSessionForTests(
                workID: UUID(),
                status: .stopped,
                isReaderOpen: true,
                ttsService: engine,
                unitProvider: { locator in
                    locator?.href.string == "ch3.xhtml"
                        ? [TTSSpeechUnit(text: "Zero audio chapter.", locator: locator)]
                        : []
                },
                resumeLocator: locators[1],
                chapterStartLocators: locators
            )
            controller.onAdvance = { moves.append($0.href.string) }

            controller.toggle(from: locators[1])
            await controller.waitForStartTaskForTests()
            #expect(moves.isEmpty)
            #expect(controller.resumeLocator?.href.string == "ch2.xhtml")
            engine.emitNaturalFinish()
            await controller.waitForStartTaskForTests()
            #expect(moves.isEmpty)
            #expect(controller.resumeLocator?.href.string == "ch2.xhtml")
            #expect(controller.status == .stopped)
            #expect(controller.showsNothingToSpeakAlert)
        }
    }

    // MARK: - Finding 4 [P2]: Old chapter finish during scan & second skip over dead engine

    @Test func oldChapterFinishingDuringSkipBackDoesNotCancelUserRequest() async {
        let locators = chapterLocators(count: 4)
        let ch2Gate = AsyncGate()
        let engine = ControllableTTSService(status: .playing)
        let controller = ReaderSpeechController()
        var moves: [String] = []

        controller.seedSessionForTests(
            workID: UUID(),
            status: .playing,
            isReaderOpen: true,
            ttsService: engine,
            unitProvider: { locator in
                switch locator?.href.string {
                case "ch2.xhtml":
                    await ch2Gate.enterAndWait()
                    return []
                case "ch1.xhtml":
                    return [TTSSpeechUnit(text: "Chapter one prose.", locator: locator)]
                case "ch4.xhtml":
                    return [TTSSpeechUnit(text: "Chapter four prose.", locator: locator)]
                default:
                    return []
                }
            },
            resumeLocator: locators[2],
            chapterStartLocators: locators
        )
        controller.onAdvance = { moves.append($0.href.string) }

        // User skips back from ch3 across empty ch2 toward ch1.
        controller.reanchor(to: locators[1], resumePlaying: true, direction: .backward)
        await ch2Gate.waitUntilEntered()

        // While scanning ch2, old ch3 finishes naturally! Must NOT override with ch4.
        engine.emitNaturalFinish()

        ch2Gate.release()
        await controller.waitForStartTaskForTests()

        #expect(engine.spokenHrefs == ["ch1.xhtml"])
        #expect(moves == ["ch1.xhtml"])
        #expect(controller.resumeLocator?.href.string == "ch1.xhtml")
        #expect(controller.status == .playing)
    }

    @Test func failedUserSkipWhileAutoAdvancePendingDoesNotLeavePlayingOverStoppedEngine() async {
        let locators = chapterLocators(count: 4)
        let ch3Gate = AsyncGate()
        let engine = ControllableTTSService(status: .playing)
        let controller = ReaderSpeechController()

        controller.seedSessionForTests(
            workID: UUID(),
            status: .playing,
            isReaderOpen: true,
            ttsService: engine,
            unitProvider: { locator in
                if locator?.href.string == "ch3.xhtml" {
                    await ch3Gate.enterAndWait()
                }
                return []
            },
            resumeLocator: locators[1],
            chapterStartLocators: locators
        )

        // Ch2 finishes naturally -> engine is now `.stopped`, controller keeps `.playing` while scanning ch3.
        engine.emitNaturalFinish()
        await ch3Gate.waitUntilEntered()
        #expect(engine.status == .stopped)
        #expect(controller.status == .playing)

        // User presses Skip Forward toward empty ch4 while auto-advance is still scanning.
        controller.reanchor(to: locators[3], resumePlaying: true, direction: .forward)
        ch3Gate.release()
        await controller.waitForStartTaskForTests()

        // Engine is stopped and nothing speakable was found -> session MUST end, never stay `.playing`.
        #expect(controller.status == .stopped)
        #expect(!controller.isSessionActive)
        #expect(controller.showsNothingToSpeakAlert)
    }

    // MARK: - Finding 5 [P2]: Transport changes during a scan must be honored

    @Test func pauseDuringPlayingSkipScanKeepsReplacementPaused() async {
        let locators = chapterLocators(count: 4)
        let ch3Gate = AsyncGate()
        let engine = ControllableTTSService(status: .playing)
        let controller = ReaderSpeechController()

        controller.seedSessionForTests(
            workID: UUID(),
            status: .playing,
            isReaderOpen: true,
            ttsService: engine,
            unitProvider: { locator in
                if locator?.href.string == "ch3.xhtml" {
                    await ch3Gate.enterAndWait()
                    return [TTSSpeechUnit(text: "Chapter three prose.", locator: locator)]
                }
                return [TTSSpeechUnit(text: "Prose.", locator: locator)]
            },
            resumeLocator: locators[1],
            chapterStartLocators: locators
        )

        // Playing skip to ch3; pause before extraction returns.
        controller.reanchor(to: locators[2], resumePlaying: true, direction: .forward)
        await ch3Gate.waitUntilEntered()
        controller.pause()
        #expect(controller.status == .paused)

        ch3Gate.release()
        await controller.waitForStartTaskForTests()

        // Replacement chapter must commit PAUSED, never play aloud after user pressed Pause!
        #expect(controller.status == .paused)
        #expect(engine.status == .paused)
        #expect(controller.resumeLocator?.href.string == "ch3.xhtml")
    }

    @Test func playDuringPausedSkipScanStartsReplacementPlayingWithoutSelfPausing() async {
        let locators = chapterLocators(count: 4)
        let ch3Gate = AsyncGate()
        let engine = ControllableTTSService(status: .paused)
        let controller = ReaderSpeechController()

        controller.seedSessionForTests(
            workID: UUID(),
            status: .paused,
            isReaderOpen: true,
            ttsService: engine,
            unitProvider: { locator in
                if locator?.href.string == "ch3.xhtml" {
                    await ch3Gate.enterAndWait()
                    return [TTSSpeechUnit(text: "Chapter three prose.", locator: locator)]
                }
                return [TTSSpeechUnit(text: "Prose.", locator: locator)]
            },
            resumeLocator: locators[1],
            chapterStartLocators: locators
        )

        // Paused skip to ch3; before extraction returns, user presses Play!
        controller.reanchor(to: locators[2], resumePlaying: false, direction: .forward)
        await ch3Gate.waitUntilEntered()
        controller.toggle(from: nil)
        // Old engine emitting text mid-scan must not self-pause either.
        engine.emitUtterance(text: "Continuing ch2.", locator: locators[1])
        #expect(controller.status == .playing)

        ch3Gate.release()
        await controller.waitForStartTaskForTests()

        // Replacement chapter must play aloud, NOT pause itself!
        #expect(controller.status == .playing)
        #expect(engine.status == .playing)
        #expect(controller.resumeLocator?.href.string == "ch3.xhtml")
    }

    // MARK: - Finding 6 [P2]: Real Readium Publication with empty XHTML between prose chapters

    private final class CountingInMemoryContainer: Container, @unchecked Sendable {
        let sourceURL: AbsoluteURL? = nil
        let entries: Set<AnyURL>
        private let payloads: [String: Data]
        private let lock = NSLock()
        private var reads: [String: Int] = [:]

        init(pages: [(href: String, xhtml: String)]) {
            var map: [String: Data] = [:]
            var urls = Set<AnyURL>()
            for page in pages {
                map[page.href] = Data(page.xhtml.utf8)
                if let url = AnyURL(string: page.href) {
                    urls.insert(url)
                }
            }
            self.payloads = map
            self.entries = urls
        }

        func readCount(for href: String) -> Int {
            lock.lock()
            defer { lock.unlock() }
            return reads[href] ?? 0
        }

        subscript(url: any URLConvertible) -> Resource? {
            let key = url.anyURL.removingQuery().removingFragment().string.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let data = payloads[key] else { return nil }
            return DataResource { [weak self] in
                self?.recordRead(key)
                return .success(data)
            }
        }

        private func recordRead(_ key: String) {
            lock.lock()
            reads[key, default: 0] += 1
            lock.unlock()
        }
    }

    private func makeRealPublication(
        pages: [(href: String, xhtml: String)]
    ) -> (publication: Publication, container: CountingInMemoryContainer, locators: [Locator]) {
        let container = CountingInMemoryContainer(pages: pages)
        let links = pages.map { Link(href: $0.href, mediaType: .xhtml) }
        let manifest = Manifest(
            metadata: Metadata(title: "Empty Chapter Fixture"),
            readingOrder: links
        )
        var builder = PublicationServicesBuilder()
        builder.setContentServiceFactory(
            DefaultContentService.makeFactory(
                resourceContentIteratorFactories: [HTMLResourceContentIterator.Factory()]
            )
        )
        let publication = Publication(
            manifest: manifest,
            container: container,
            servicesBuilder: builder
        )
        let locators = pages.enumerated().map { index, page in
            Locator(
                href: AnyURL(string: page.href)!,
                mediaType: .xhtml,
                locations: .init(position: index + 1)
            )
        }
        return (publication, container, locators)
    }

    @Test func skipBackOverZeroElementXHTMLReachesEarlierProseAndDoesNotReParseEmptyRuns() async {
        let emptyHTML = "<html><body></body></html>"
        let (publication, container, locators) = makeRealPublication(pages: [
            ("ch1.xhtml", "<html><body><p>Chapter one prose.</p></body></html>"),
            ("ch2.xhtml", emptyHTML),
            ("ch3.xhtml", emptyHTML),
            ("ch4.xhtml", emptyHTML),
            ("ch5.xhtml", "<html><body><p>Chapter five prose.</p></body></html>"),
        ])

        let engine = ControllableTTSService(status: .playing)
        let controller = ReaderSpeechController()
        let workID = UUID()
        var moves: [String] = []
        controller.prepare(
            publication: publication,
            workID: workID,
            title: "Empty Chapter Fixture",
            author: "Author",
            totalPositions: locators.count,
            sections: [],
            chapterStartLocators: locators
        )
        controller.seedSessionForTests(
            workID: workID,
            status: .playing,
            isReaderOpen: true,
            ttsService: engine,
            unitProvider: nil,
            resumeLocator: locators[4],
            chapterStartLocators: locators
        )
        controller.onAdvance = { moves.append($0.href.string) }

        // Skip Back from ch5 across empty ch4, ch3, ch2 -> MUST land on ch1 (never bounce back to ch5!).
        controller.reanchor(to: locators[3], resumePlaying: true, direction: .backward)
        await controller.waitForStartTaskForTests()

        #expect(engine.spokenHrefs == ["ch1.xhtml"])
        #expect(moves == ["ch1.xhtml"])
        #expect(controller.resumeLocator?.href.string == "ch1.xhtml")
        // Each empty chapter must be parsed at most once (never O(N^2) re-walked into ch5).
        #expect(container.readCount(for: "ch4.xhtml") == 1)
        #expect(container.readCount(for: "ch3.xhtml") == 1)
        #expect(container.readCount(for: "ch2.xhtml") == 1)
        #expect(container.readCount(for: "ch5.xhtml") == 0)
    }

    // MARK: - Finding 7a [P2]: Silent Kokoro chapter preserves backward skip direction

    @Test func silentKokoroChapterDuringPausedSkipBackContinuesBackwardNotForward() async {
        let locators = chapterLocators(count: 4)
        let engine = ControllableTTSService(status: .paused)
        engine.silentHrefs = ["ch2.xhtml"]
        let controller = ReaderSpeechController()
        var moves: [String] = []

        controller.seedSessionForTests(
            workID: UUID(),
            status: .paused,
            isReaderOpen: true,
            ttsService: engine,
            unitProvider: { locator in
                [TTSSpeechUnit(text: "Prose in \(locator?.href.string ?? "").", locator: locator)]
            },
            resumeLocator: locators[2],
            chapterStartLocators: locators
        )
        controller.onAdvance = { moves.append($0.href.string) }

        // Paused Skip Back from ch3 into silent Kokoro ch2 -> must continue BACK to ch1!
        controller.reanchor(to: locators[1], resumePlaying: false, direction: .backward)
        await controller.waitForStartTaskForTests()
        #expect(engine.spokenHrefs == ["ch2.xhtml"])
        #expect(moves.isEmpty)

        engine.emitNaturalFinish()
        await controller.waitForStartTaskForTests()

        #expect(engine.spokenHrefs == ["ch2.xhtml", "ch1.xhtml"])
        #expect(moves == ["ch1.xhtml"])
        #expect(controller.resumeLocator?.href.string == "ch1.xhtml")
        #expect(controller.status == .paused)
    }

    // MARK: - Finding 5 (remote commands), 6 (forward empty run), 7b (Apple pause-before-enqueue), 10 (copy & haptic)

    @Test func remotePauseAndPlayDuringScanControlReplacementPlaybackState() async {
        let locators = chapterLocators(count: 4)

        // Remote Pause during a playing skip scan keeps replacement paused.
        do {
            let gate = AsyncGate()
            let engine = ControllableTTSService(status: .playing)
            let controller = ReaderSpeechController()
            controller.seedSessionForTests(
                workID: UUID(),
                status: .playing,
                isReaderOpen: false,
                ttsService: engine,
                unitProvider: { locator in
                    if locator?.href.string == "ch3.xhtml" {
                        await gate.enterAndWait()
                    }
                    return [TTSSpeechUnit(text: "Prose in ch3.", locator: locator)]
                },
                resumeLocator: locators[1],
                chapterStartLocators: locators
            )

            controller.reanchor(to: locators[2], resumePlaying: true, direction: .forward)
            await gate.waitUntilEntered()
            #expect(controller.handleRemotePauseForTests() == .success)

            gate.release()
            await controller.waitForStartTaskForTests()
            #expect(controller.status == .paused)
            #expect(engine.status == .paused)
        }

        // Remote Play during a paused skip scan plays replacement aloud.
        do {
            let gate = AsyncGate()
            let engine = ControllableTTSService(status: .paused)
            let controller = ReaderSpeechController()
            controller.seedSessionForTests(
                workID: UUID(),
                status: .paused,
                isReaderOpen: false,
                ttsService: engine,
                unitProvider: { locator in
                    if locator?.href.string == "ch3.xhtml" {
                        await gate.enterAndWait()
                    }
                    return [TTSSpeechUnit(text: "Prose in ch3.", locator: locator)]
                },
                resumeLocator: locators[1],
                chapterStartLocators: locators
            )

            controller.reanchor(to: locators[2], resumePlaying: false, direction: .forward)
            await gate.waitUntilEntered()
            #expect(controller.handleRemotePlayForTests() == .success)

            gate.release()
            await controller.waitForStartTaskForTests()
            #expect(controller.status == .playing)
            #expect(engine.status == .playing)
        }
    }

    @Test func skipForwardOverZeroElementXHTMLReachesLaterProseAndParsesEachEmptyOnce() async {
        let emptyHTML = "<html><body></body></html>"
        let (publication, container, locators) = makeRealPublication(pages: [
            ("ch1.xhtml", "<html><body><p>Chapter one prose.</p></body></html>"),
            ("ch2.xhtml", emptyHTML),
            ("ch3.xhtml", emptyHTML),
            ("ch4.xhtml", emptyHTML),
            ("ch5.xhtml", "<html><body><p>Chapter five prose.</p></body></html>"),
        ])

        let engine = ControllableTTSService(status: .playing)
        let controller = ReaderSpeechController()
        let workID = UUID()
        var moves: [String] = []
        controller.prepare(
            publication: publication,
            workID: workID,
            title: "Empty Chapter Forward Fixture",
            author: "Author",
            totalPositions: locators.count,
            sections: [],
            chapterStartLocators: locators
        )
        controller.seedSessionForTests(
            workID: workID,
            status: .playing,
            isReaderOpen: true,
            ttsService: engine,
            unitProvider: nil,
            resumeLocator: locators[0],
            chapterStartLocators: locators
        )
        controller.onAdvance = { moves.append($0.href.string) }

        controller.reanchor(to: locators[1], resumePlaying: true, direction: .forward)
        await controller.waitForStartTaskForTests()

        #expect(engine.spokenHrefs == ["ch5.xhtml"])
        #expect(moves == ["ch5.xhtml"])
        #expect(container.readCount(for: "ch2.xhtml") == 1)
        #expect(container.readCount(for: "ch3.xhtml") == 1)
        #expect(container.readCount(for: "ch4.xhtml") == 1)
        #expect(container.readCount(for: "ch5.xhtml") == 1)
    }

    @Test func systemTTSPausedSkipDoesNotEnqueueUtteranceUntilResumed() async {
        let locators = chapterLocators(count: 4)
        let systemTTS = SystemTTSService()
        systemTTS.testSkipAudioSessionActivation = true
        let spokenGate = AsyncGate()
        var enqueuedTexts: [String] = []
        systemTTS.testSpeakUtterance = { unit in
            enqueuedTexts.append(unit.text)
            spokenGate.release()
        }

        let controller = ReaderSpeechController()
        var moves: [String] = []
        controller.seedSessionForTests(
            workID: UUID(),
            status: .paused,
            isReaderOpen: true,
            ttsService: systemTTS,
            unitProvider: { locator in
                [TTSSpeechUnit(text: "First spoken sentence in chapter three.", locator: locator)]
            },
            resumeLocator: locators[1],
            chapterStartLocators: locators
        )
        controller.onAdvance = { moves.append($0.href.string) }

        controller.reanchor(to: locators[2], resumePlaying: false, direction: .forward)
        await controller.waitForStartTaskForTests()
        // Let SystemTTSService's playback task reach its pause gate.
        try? await Task.sleep(for: .milliseconds(30))

        // Held before it announced: the page and saved position have NOT moved to
        // text nobody has heard, and nothing was handed to the synthesizer.
        #expect(controller.status == .paused)
        #expect(systemTTS.status == .paused)
        #expect(moves.isEmpty)
        #expect(controller.resumeLocator?.href.string == "ch2.xhtml")
        #expect(enqueuedTexts.isEmpty)

        // Pressing Play resumes the held first utterance: now it commits and speaks.
        controller.toggle(from: nil)
        await spokenGate.enterAndWait()
        #expect(enqueuedTexts == ["First spoken sentence in chapter three."])
        #expect(moves == ["ch3.xhtml"])
        #expect(controller.resumeLocator?.href.string == "ch3.xhtml")
        #expect(controller.status == .playing)
        controller.stop()
    }

    @Test func skipBackFailureShowsBackwardCopyAndManualHapticFiresOnlyOnCommit() async {
        let locators = chapterLocators(count: 4)
        let engine = ControllableTTSService(status: .playing)
        let controller = ReaderSpeechController()
        var manualHaptics = 0

        controller.seedSessionForTests(
            workID: UUID(),
            status: .playing,
            isReaderOpen: true,
            ttsService: engine,
            unitProvider: { locator in
                switch locator?.href.string {
                case "ch4.xhtml":
                    return [TTSSpeechUnit(text: "Prose in chapter four.", locator: locator)]
                default:
                    return []
                }
            },
            resumeLocator: locators[2],
            chapterStartLocators: locators
        )
        controller.onChapterSkipCommitted = { manualHaptics += 1 }

        // Failed Skip Back: backward-specific copy and NO manual haptic.
        controller.reanchor(to: locators[1], resumePlaying: true, direction: .backward, isManualSkip: true)
        await controller.waitForStartTaskForTests()
        #expect(controller.showsNothingToSpeakAlert)
        #expect(controller.nothingToSpeakDirection == .backward)
        #expect(controller.nothingToSpeakMessage.contains("start"))
        #expect(!controller.nothingToSpeakMessage.contains("end"))
        #expect(manualHaptics == 0)

        // Successful manual Skip Forward: manual haptic fires once on commit.
        controller.reanchor(to: locators[3], resumePlaying: true, direction: .forward, isManualSkip: true)
        await controller.waitForStartTaskForTests()
        #expect(manualHaptics == 1)

        // Natural chapter-end auto-advance: NO manual haptic.
        let autoEngine = ControllableTTSService(status: .playing)
        let autoController = ReaderSpeechController()
        var autoHaptics = 0
        autoController.seedSessionForTests(
            workID: UUID(),
            status: .playing,
            isReaderOpen: true,
            ttsService: autoEngine,
            unitProvider: { locator in
                [TTSSpeechUnit(text: "Auto prose.", locator: locator)]
            },
            resumeLocator: locators[0],
            chapterStartLocators: locators
        )
        autoController.onChapterSkipCommitted = { autoHaptics += 1 }
        autoEngine.emitNaturalFinish()
        await autoController.waitForStartTaskForTests()
        #expect(autoHaptics == 0)
    }

    // MARK: - T-535f: engine races

    private func startedController(
        engine: ControllableTTSService,
        locators: [Locator],
        isReaderOpen: Bool = true
    ) -> ReaderSpeechController {
        let controller = ReaderSpeechController()
        controller.seedSessionForTests(
            workID: UUID(),
            status: .stopped,
            isReaderOpen: isReaderOpen,
            ttsService: engine,
            unitProvider: { [TTSSpeechUnit(text: "Prose in \($0?.href.string ?? "").", locator: $0)] },
            resumeLocator: locators[0],
            chapterStartLocators: locators
        )
        return controller
    }

    @Test func secondTapDuringPendingStartCancelsItAndLateOutputCannotMoveReader() async {
        let locators = chapterLocators(count: 3)
        let engine = ControllableTTSService(status: .stopped)
        engine.autoEmitFirstUtterance = false
        let controller = startedController(engine: engine, locators: locators)
        var moves: [String] = []
        controller.onAdvance = { moves.append($0.href.string) }

        controller.toggle(from: locators[0])
        await controller.waitForStartTaskForTests()
        #expect(controller.isStartPending)

        controller.toggle(from: locators[0])
        #expect(!controller.isStartPending)
        #expect(engine.stopCount >= 1)
        engine.emitUtterance(text: "Late.", locator: locators[0])
        #expect(moves.isEmpty)
        #expect(controller.status == .stopped)
    }

    @Test func skipDuringPendingStartStopsTheUncommittedEngineEvenWhenScanFindsNothing() async {
        let locators = chapterLocators(count: 3)
        let engine = ControllableTTSService(status: .stopped)
        engine.autoEmitFirstUtterance = false
        let controller = ReaderSpeechController()
        controller.seedSessionForTests(
            workID: UUID(), status: .stopped, isReaderOpen: true, ttsService: engine,
            unitProvider: { $0?.href.string == "ch1.xhtml" ? [TTSSpeechUnit(text: "One.", locator: $0)] : [] },
            resumeLocator: locators[0], chapterStartLocators: locators
        )
        var moves: [String] = []
        controller.onAdvance = { moves.append($0.href.string) }
        controller.toggle(from: locators[0])
        await controller.waitForStartTaskForTests()
        let stopsBefore = engine.stopCount

        controller.reanchor(to: locators[1], resumePlaying: true, direction: .forward)
        #expect(engine.stopCount > stopsBefore)
        await controller.waitForStartTaskForTests()
        engine.emitUtterance(text: "Late one.", locator: locators[0])
        #expect(moves.isEmpty)
        #expect(controller.status == .stopped)
    }

    @Test func playAfterInterruptionBeforeFirstOutputResumesTheEngine() async {
        let locators = chapterLocators(count: 3)
        let engine = ControllableTTSService(status: .stopped)
        engine.autoEmitFirstUtterance = false
        let controller = startedController(engine: engine, locators: locators)
        controller.toggle(from: locators[0])
        await controller.waitForStartTaskForTests()

        engine.pause() // audio interruption before the first utterance
        #expect(engine.status == .paused)
        #expect(controller.handleRemotePlayForTests() == .success)
        #expect(engine.resumeCount == 1)
        #expect(engine.status == .playing)
    }

    @Test func engineUnavailableBeforeThrowStillReportsStartupError() async {
        let locators = chapterLocators(count: 3)
        let engine = ControllableTTSService(status: .stopped)
        engine.goesUnavailable = true
        engine.throwsAfterUnavailable = true
        let controller = startedController(engine: engine, locators: locators)
        controller.toggle(from: locators[0])
        await controller.waitForStartTaskForTests()
        #expect(controller.status == .unavailable)
        #expect(controller.speechErrorMessage == "Audio session unavailable")
        #expect(!controller.remoteCommandsInstalledForTests)
    }

    // MARK: Core ML production startup path (seams replace only pack + audio hardware)

    private func coreMLController(
        _ coreML: CoreMLKokoroTTSService,
        locators: [Locator]
    ) -> ReaderSpeechController {
        let controller = ReaderSpeechController()
        controller.seedSessionForTests(
            workID: UUID(), status: .stopped, isReaderOpen: true, ttsService: coreML,
            unitProvider: { $0?.href.string == "ch2.xhtml" ? [TTSSpeechUnit(text: "Short last chapter.", locator: $0)] : [] },
            resumeLocator: locators[0], chapterStartLocators: locators
        )
        return controller
    }

    @Test func coreMLAudioEngineFailureNeverAnnouncesOrMovesTheReader() async {
        let locators = chapterLocators(count: 2)
        let coreML = CoreMLKokoroTTSService()
        coreML.testSetupOverride = {}
        coreML.testSynthesize = { _ in [0.2, -0.2, 0.2] }
        coreML.testStartAudioEngine = { throw EngineTestError.audioSessionFailed }
        let controller = coreMLController(coreML, locators: locators)
        var moves: [String] = []
        controller.onAdvance = { moves.append($0.href.string) }
        controller.toggle(from: locators[0])
        await controller.waitForStartTaskForTests()
        await waitUntil { controller.status == .unavailable }
        #expect(moves.isEmpty)
        #expect(controller.resumeLocator?.href.string == "ch1.xhtml")
        #expect(controller.status == .unavailable)
        #expect(controller.speechErrorMessage != nil)
        #expect(!controller.remoteCommandsInstalledForTests)
    }

    @Test func coreMLAnnouncesOnlyAfterTheAudioEngineStarted() async {
        let locators = chapterLocators(count: 2)
        let coreML = CoreMLKokoroTTSService()
        var order: [String] = []
        coreML.testSetupOverride = {}
        coreML.testSynthesize = { _ in [0.2, -0.2, 0.2] }
        coreML.testStartAudioEngine = { order.append("start") }
        coreML.testPlayBuffer = { _ in order.append("play") }
        let controller = coreMLController(coreML, locators: locators)
        controller.onAdvance = { order.append("advance:\($0.href.string)") }
        controller.toggle(from: locators[0])
        await controller.waitForStartTaskForTests()
        await waitUntil { order.contains("play") }
        #expect(order.prefix(3) == ["start", "advance:ch2.xhtml", "play"])
    }

    @Test func coreMLSilentSynthesisCommitsNothing() async {
        let locators = chapterLocators(count: 2)
        let coreML = CoreMLKokoroTTSService()
        coreML.testSetupOverride = {}
        coreML.testSynthesize = { _ in [] }
        coreML.testStartAudioEngine = {}
        let controller = coreMLController(coreML, locators: locators)
        var moves: [String] = []
        controller.onAdvance = { moves.append($0.href.string) }
        controller.toggle(from: locators[0])
        await controller.waitForStartTaskForTests()
        await waitUntil { controller.showsNothingToSpeakAlert }
        #expect(moves.isEmpty)
        #expect(controller.resumeLocator?.href.string == "ch1.xhtml")
        #expect(controller.showsNothingToSpeakAlert)
        // Zero output ended the start: no remote Play target may stay registered.
        #expect(!controller.remoteCommandsInstalledForTests)
    }

    /// Polls until `condition` holds (or 2 s), instead of guessing a number of yields.
    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private func seededCoreML(
        _ coreML: CoreMLKokoroTTSService,
        locators: [Locator],
        status: ReaderSpeechController.Status
    ) -> ReaderSpeechController {
        let controller = ReaderSpeechController()
        controller.seedSessionForTests(
            workID: UUID(), status: status, isReaderOpen: true, ttsService: coreML,
            unitProvider: { [TTSSpeechUnit(text: "Prose in \($0?.href.string ?? "").", locator: $0)] },
            resumeLocator: locators[0], chapterStartLocators: locators
        )
        return controller
    }

    @Test func pausedCoreMLSkipHoldsUntilPlayThenCommits() async {
        let locators = chapterLocators(count: 2)
        let coreML = CoreMLKokoroTTSService()
        var armed = false
        var played = false
        coreML.testSetupOverride = {}
        coreML.testSynthesize = { _ in [0.2, -0.2, 0.2] }
        coreML.testStartAudioEngine = { armed = true }
        coreML.testPlayBuffer = { _ in played = true }
        let controller = seededCoreML(coreML, locators: locators, status: .paused)
        var moves: [String] = []
        controller.onAdvance = { moves.append($0.href.string) }

        controller.reanchor(to: locators[1], resumePlaying: false, direction: .forward)
        await controller.waitForStartTaskForTests()
        await waitUntil { coreML.status == .paused }
        // Held by the engine, nobody pressed Play: nothing moved or saved.
        try? await Task.sleep(for: .milliseconds(30))
        #expect(coreML.status == .paused)
        #expect(!armed)
        #expect(moves.isEmpty)
        #expect(!played)
        #expect(controller.resumeLocator?.href.string == "ch1.xhtml")

        controller.toggle(from: nil)
        await waitUntil { played }
        #expect(moves == ["ch2.xhtml"])
        #expect(controller.resumeLocator?.href.string == "ch2.xhtml")
    }

    @Test func stopOnPausedCoreMLSkipNeverCommitsTheUnheardChapter() async {
        let locators = chapterLocators(count: 2)
        let coreML = CoreMLKokoroTTSService()
        coreML.testSetupOverride = {}
        coreML.testSynthesize = { _ in [0.2, -0.2, 0.2] }
        coreML.testStartAudioEngine = {}
        coreML.testPlayBuffer = { _ in }
        let controller = seededCoreML(coreML, locators: locators, status: .paused)
        var moves: [String] = []
        var saves: [String] = []
        controller.onAdvance = { moves.append($0.href.string) }
        controller.onSavePosition = { _, loc, _, _, date, _ in
            saves.append(loc)
            return .wrote(progressStamp: date)
        }
        controller.reanchor(to: locators[1], resumePlaying: false, direction: .forward)
        await controller.waitForStartTaskForTests()
        await waitUntil { coreML.status == .paused }
        controller.stop()
        try? await Task.sleep(for: .milliseconds(30))
        #expect(moves.isEmpty)
        #expect(!saves.contains { $0.contains("ch2.xhtml") })
        #expect(controller.resumeLocator?.href.string == "ch1.xhtml")
    }

    @Test func pauseDuringPendingCoreMLStartHoldsTheEngineAndPlayResumesIt() async {
        let locators = chapterLocators(count: 2)
        let coreML = CoreMLKokoroTTSService()
        let synthGate = AsyncGate()
        var armed = false
        var played = false
        coreML.testSetupOverride = {}
        coreML.testSynthesize = { _ in
            await synthGate.enterAndWait()
            return [0.2, -0.2, 0.2]
        }
        coreML.testStartAudioEngine = { armed = true }
        coreML.testPlayBuffer = { _ in played = true }
        let controller = seededCoreML(coreML, locators: locators, status: .stopped)
        var moves: [String] = []
        controller.onAdvance = { moves.append($0.href.string) }
        controller.toggle(from: locators[0])
        await controller.waitForStartTaskForTests()
        await synthGate.waitUntilEntered() // first output still being prepared
        controller.pause()
        #expect(coreML.status == .paused)
        synthGate.release()
        await waitUntil { armed }
        try? await Task.sleep(for: .milliseconds(30))
        #expect(moves.isEmpty)
        #expect(!played)

        #expect(controller.handleRemotePlayForTests() == .success)
        await waitUntil { played }
        #expect(moves.first == "ch1.xhtml")
    }

    @Test func coreMLStopDuringLexiconOrObserverStepNeverStartsPlayback() async {
        let locators = chapterLocators(count: 2)
        for stage in ["lexicon", "observer"] {
            let gate = AsyncGate()
            let coreML = CoreMLKokoroTTSService()
            coreML.testSetupOverride = {}
            if stage == "lexicon" {
                coreML.testLexiconStep = { await gate.enterAndWait() }
            } else {
                coreML.testObserverStep = { await gate.enterAndWait() }
            }
            let controller = seededCoreML(coreML, locators: locators, status: .stopped)
            controller.toggle(from: locators[0])
            await gate.waitUntilEntered()
            controller.stop()
            gate.release()
            try? await Task.sleep(for: .milliseconds(30))
            #expect(!coreML.testDidStartPlaybackTask, "stage \(stage)")
            #expect(coreML.status == .stopped, "stage \(stage)")
        }
    }

    @Test func sherpaResumeFailureEndsInsteadOfPublishingPlaying() {
        let sherpa = SherpaKokoroTTSService(modelDirectory: URL(fileURLWithPath: "/nonexistent-kudos-model"))
        sherpa.pauseForTests()
        var statuses: [TTSServiceStatus] = []
        sherpa.onStatusChange = { statuses.append($0) }
        sherpa.testRestartEngine = { throw EngineTestError.audioSessionFailed }
        sherpa.resume()
        #expect(sherpa.status == .unavailable)
        #expect(!statuses.contains(.playing))
    }

    @Test func pauseAssemblerDoesNotPadAnEmptySynthesis() {
        #expect(KokoroPauseAssembler.assemble(samples: [], sampleRate: 24_000, pauseAfter: .paragraph).isEmpty)
    }
}
#endif
