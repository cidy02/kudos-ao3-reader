import Foundation
import SwiftData
import Testing
@testable import Kudos

/// Owner, 2026-11-19: queue-only reading counts in the main figures; hidden (Hide Mature)
/// works get their own section, shown only while revealed; a combined view adds them in.
@MainActor
@Suite struct InsightsHiddenScopeTests {
    private let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }()

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

    private func date(day: Int) -> Date {
        utcCalendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: 12))!
    }

    private var aug: DateInterval {
        utcCalendar.dateInterval(of: .month, for: date(day: 1))!
    }

    private var jul: DateInterval {
        utcCalendar.dateInterval(of: .month, for: date(day: 1).addingTimeInterval(-86_400 * 5))!
    }

    private struct Fixture {
        let context: ModelContext
        let library: [SavedWork]
        let visible: SavedWork
        let mature: SavedWork
        let queueOnly: SavedWork
        let queueOnlyMature: SavedWork
        let softDeletedMature: SavedWork
        let hardDeletedMatureID: UUID
        let unreadVisible: SavedWork
        let stoppedVisible: SavedWork
        let sessions: [ReadingSession]
    }

    private func makeFixture() throws -> Fixture {
        let context = try makeContext()
        func work(_ title: String, words: Int, fandom: String) -> SavedWork {
            let work = SavedWork(title: title, author: "A")
            work.wordCount = words
            work.workFandoms = [fandom]
            work.isSaved = true
            return work
        }
        let visible = work("Visible Fic", words: 10_000, fandom: "Fandom One")
        visible.isFinished = true

        let mature = work("Explicit Fic", words: 20_000, fandom: "Secret Fandom")
        mature.rating = "Explicit"
        mature.isFinished = true

        let queueOnly = work("Queued Fic", words: 6_000, fandom: "Queue Fandom")
        queueOnly.isSaved = false
        queueOnly.isQueuedForLater = true
        queueOnly.isFinished = true

        let queueOnlyMature = work("Queued Explicit Fic", words: 8_000, fandom: "Queue Secret Fandom")
        queueOnlyMature.isSaved = false
        queueOnlyMature.isQueuedForLater = true
        queueOnlyMature.rating = "Explicit"
        queueOnlyMature.isFinished = true

        let softDeletedMature = work("Soft Deleted Mature", words: 12_000, fandom: "Trash Mature Fandom")
        softDeletedMature.rating = "Mature"
        softDeletedMature.isPendingDeletion = true

        let unreadVisible = work("Unread Backlog", words: 5_000, fandom: "Fandom One")

        let stoppedVisible = work("Stopped Fic", words: 9_000, fandom: "Fandom One")
        stoppedVisible.setReadingStatus(.stopped, at: date(day: 10))
        stoppedVisible.stoppedAt = date(day: 10)
        stoppedVisible.stopReasonRaw = "tooLong"

        let hardDeletedMatureID = UUID()

        func finished(_ work: SavedWork, day: Int, seconds: Double, ratingOverride: String? = nil) -> ReadingSession {
            let start = date(day: day)
            let session = ReadingSession(
                workID: work.id, workTitle: work.title,
                startedAt: start, endedAt: start.addingTimeInterval(seconds),
                durationSeconds: seconds,
                startProgress: 0, endingProgress: 1.0, wordCount: work.wordCount, didFinish: true
            )
            session.fandoms = work.workFandoms
            session.rating = ratingOverride ?? work.rating
            return session
        }

        // Pre-D1 session with blank snapshot rating on a soft-deleted mature work:
        // must still classify as hidden via `softDeletedAdultWorkIDs(in:)`.
        let softDeletedPreD1 = finished(softDeletedMature, day: 5, seconds: 400, ratingOverride: "")

        // Hard-deleted mature work (no SavedWork in store): one D1+ session carrying
        // `rating = "Explicit"` plus an earlier pre-D1 session with blank rating — both
        // must classify as hidden while locked and appear in Hidden when revealed.
        let hardDeletedPreD1Start = date(day: 6)
        let hardDeletedPreD1 = ReadingSession(
            workID: hardDeletedMatureID, workTitle: "Purged Explicit Fic",
            startedAt: hardDeletedPreD1Start, endedAt: hardDeletedPreD1Start.addingTimeInterval(200),
            durationSeconds: 200,
            startProgress: 0, endingProgress: 0.4, wordCount: 10_000, didFinish: false
        )
        hardDeletedPreD1.fandoms = ["Purged Secret Fandom"]
        hardDeletedPreD1.rating = ""

        let hardDeletedD1Start = date(day: 7)
        let hardDeletedD1 = ReadingSession(
            workID: hardDeletedMatureID, workTitle: "Purged Explicit Fic",
            startedAt: hardDeletedD1Start, endedAt: hardDeletedD1Start.addingTimeInterval(300),
            durationSeconds: 300,
            startProgress: 0.4, endingProgress: 1.0, wordCount: 10_000, didFinish: true
        )
        hardDeletedD1.fandoms = ["Purged Secret Fandom"]
        hardDeletedD1.rating = "Explicit"
        hardDeletedD1.freeformTags = ["Purged Secret Tag"]

        let liveLibrary = [visible, mature, queueOnly, queueOnlyMature, unreadVisible, stoppedVisible]
        (liveLibrary + [softDeletedMature]).forEach { context.insert($0) }
        let sessions = [
            finished(visible, day: 2, seconds: 600),
            finished(mature, day: 3, seconds: 1_200),
            finished(queueOnly, day: 4, seconds: 300),
            finished(queueOnlyMature, day: 8, seconds: 500),
            softDeletedPreD1,
            hardDeletedPreD1,
            hardDeletedD1
        ]
        sessions.forEach { context.insert($0) }
        try context.save()
        return Fixture(
            context: context, library: liveLibrary,
            visible: visible, mature: mature, queueOnly: queueOnly,
            queueOnlyMature: queueOnlyMature, softDeletedMature: softDeletedMature,
            hardDeletedMatureID: hardDeletedMatureID,
            unreadVisible: unreadVisible, stoppedVisible: stoppedVisible,
            sessions: sessions
        )
    }

    private func gather(_ scope: InsightsScope, revealed: Bool, _ f: Fixture) -> ReadingLogService.InsightsGatherResult {
        ReadingLogService.gatherInsights(
            for: aug, previousPeriod: jul,
            scope: HomeReadingStats.insightsScope(scope, from: f.library, hideMature: true, revealed: revealed),
            calendar: utcCalendar, context: f.context,
            now: date(day: 20)
        )
    }

    private func fandoms(_ result: ReadingLogService.InsightsGatherResult) -> Set<String> {
        Set(result.insights.fandomWordsShares.filter { !$0.isRemainder }.map(\.name))
    }

    @Test func mainExcludesAllHiddenIncludingQueueOnlyAndDeletedMatureWorks() throws {
        let f = try makeFixture()
        let matureWorkIDs: Set<UUID> = [
            f.mature.id, f.queueOnlyMature.id, f.softDeletedMature.id, f.hardDeletedMatureID
        ]
        for revealed in [false, true] {
            let main = gather(.main, revealed: revealed, f)
            #expect(main.insights.totalWordsRead == 16_000)
            #expect(main.insights.totalSeconds == 900)
            #expect(main.insights.finishedWorksCount == 2)
            #expect(fandoms(main) == ["Fandom One", "Queue Fandom"])
            #expect(Set(main.finishedWorksInPeriod.map(\.id)) == [f.visible.id, f.queueOnly.id])
            // Inventory figures describe the saved library only: visible, unread, stopped.
            #expect(main.libraryStats.totalWorks == 3)
            #expect(main.library.unreadWorksCount == 1)
            #expect(main.library.statuses.total == 3)
            #expect(main.library.statuses.stoppedCount == 1)
            #expect(main.library.statuses.finishedCount == 1)
            #expect(main.library.statuses.savedForLaterCount == 1)
            #expect(main.habits.stoppedCount == 1)
            #expect(!main.filteredSessions.contains { matureWorkIDs.contains($0.workID) })
        }
    }

    @Test func hiddenScopeHoldsLiveQueueOnlySoftDeletedAndHardDeletedMatureWorks() throws {
        let f = try makeFixture()
        let hidden = gather(.hidden, revealed: true, f)
        // 20k (live mature) + 8k (queue-only mature) + 12k (soft-deleted mature) + 10k (hard-deleted mature)
        #expect(hidden.insights.totalWordsRead == 50_000)
        #expect(hidden.insights.totalSeconds == 2_600)
        #expect(hidden.insights.finishedWorksCount == 4)
        #expect(fandoms(hidden) == [
            "Secret Fandom", "Queue Secret Fandom", "Trash Mature Fandom", "Purged Secret Fandom"
        ])
        #expect(Set(hidden.finishedWorksInPeriod.map(\.id)) == [f.mature.id, f.queueOnlyMature.id])
        // Only the live saved mature work counts in library inventory.
        #expect(hidden.libraryStats.totalWorks == 1)
    }

    @Test func combinedIsMainPlusHidden() throws {
        let f = try makeFixture()
        let main = gather(.main, revealed: true, f)
        let hidden = gather(.hidden, revealed: true, f)
        let combined = gather(.combined, revealed: true, f)
        #expect(combined.insights.totalWordsRead == main.insights.totalWordsRead + hidden.insights.totalWordsRead)
        #expect(combined.insights.totalSeconds == main.insights.totalSeconds + hidden.insights.totalSeconds)
        #expect(combined.insights.finishedWorksCount
            == main.insights.finishedWorksCount + hidden.insights.finishedWorksCount)
        #expect(Set(combined.finishedWorksInPeriod.map(\.id))
            == Set(main.finishedWorksInPeriod.map(\.id)).union(hidden.finishedWorksInPeriod.map(\.id)))
        #expect(combined.libraryStats.totalWorks == 4)
        #expect(combined.library.unreadWorksCount == 1)
        #expect(combined.habits.stoppedCount == 1)
    }

    @Test func lockedComputesExportsAndExclusionsLeakNothingHidden() throws {
        let f = try makeFixture()
        let lockedHidden = HomeReadingStats.insightsScope(.hidden, from: f.library, hideMature: true, revealed: false)
        #expect(lockedHidden.readingWorks.isEmpty)
        #expect(lockedHidden.libraryWorks.isEmpty)
        #expect(lockedHidden.sessions(f.sessions, in: f.context).isEmpty)
        let hidden = gather(.hidden, revealed: false, f)
        #expect(hidden.insights.totalWordsRead == 0)
        #expect(hidden.filteredSessions.isEmpty)

        // Exclusions picker scope (`.main`) must drop live, queue-only, soft-deleted, and hard-deleted mature.
        let exclusionsScope = HomeReadingStats.insightsScope(.main, from: f.library, hideMature: true, revealed: false)
        let exclusionSessions = exclusionsScope.sessions(f.sessions, in: f.context)
        #expect(Set(exclusionSessions.map(\.workID)) == [f.visible.id, f.queueOnly.id])

        // Locked, "combined" is the main view, so its export carries no hidden work (live or deleted).
        let lockedCombined = gather(.combined, revealed: false, f)
        #expect(lockedCombined.insights.totalWordsRead == 16_000)
        let leakedSecrets = [
            "Explicit Fic", "Secret Fandom",
            "Queued Explicit Fic", "Queue Secret Fandom",
            "Soft Deleted Mature", "Trash Mature Fandom",
            "Purged Explicit Fic", "Purged Secret Fandom", "Purged Secret Tag"
        ]
        for scope in [InsightsScope.main, .combined, .hidden] {
            let selection = HomeReadingStats.insightsScope(scope, from: f.library, hideMature: true, revealed: false)
            let scopedSessions = selection.sessions(f.sessions, in: f.context)
            let csv = InsightsExportService.csvString(
                works: selection.libraryWorks,
                readingWorks: selection.readingWorks,
                sessions: scopedSessions
            )
            let jsonData = try InsightsExportService.jsonData(
                works: selection.libraryWorks,
                readingWorks: selection.readingWorks,
                sessions: scopedSessions
            )
            let json = try #require(String(bytes: jsonData, encoding: .utf8))
            for secret in leakedSecrets {
                #expect(!csv.contains(secret))
                #expect(!json.contains(secret))
            }
        }

        // Revealed and combined, the export follows the screen and includes live and deleted mature works.
        let revealed = HomeReadingStats.insightsScope(.combined, from: f.library, hideMature: true, revealed: true)
        let csv = InsightsExportService.csvString(
            works: revealed.libraryWorks,
            readingWorks: revealed.readingWorks,
            sessions: revealed.sessions(f.sessions, in: f.context)
        )
        #expect(csv.contains("Explicit Fic"))
        #expect(csv.contains("Queued Fic"))
        #expect(csv.contains("Purged Explicit Fic"))
        #expect(csv.contains("Soft Deleted Mature"))
    }

    @Test func hideMatureOffHasNoHiddenWorks() throws {
        let f = try makeFixture()
        #expect(HomeReadingStats.insightsHiddenWorkIDs(from: f.library, hideMature: false).isEmpty)
        let main = HomeReadingStats.insightsScope(.main, from: f.library, hideMature: false, revealed: false)
        #expect(main.excludedWorkIDs.isEmpty)
        #expect(main.sessions(f.sessions, in: f.context).count == f.sessions.count)
    }

    /// Review 3 P2 #3: exports pass `scope.readingWorks` so queue-only sittings honor
    /// live-work exclusions, CJK `word_unit`, D3 chapter word counts, and pre-D1 fallbacks,
    /// while library `statuses` stay saved-library-only.
    @Test func exportsUseReadingWorksForQueueOnlyExclusionsWordUnitChapterCountsAndFallbacks() throws {
        let context = try makeContext()
        let saved = SavedWork(title: "Saved English", author: "Author S")
        saved.wordCount = 5_000
        saved.workFandoms = ["Saved Fandom"]
        saved.isSaved = true

        let cjkQueued = SavedWork(title: "Queue JP", author: "Author JP")
        cjkQueued.isSaved = false
        cjkQueued.isQueuedForLater = true
        cjkQueued.language = "日本語"
        cjkQueued.wordUnitRaw = SavedWork.WordUnit.characters.rawValue
        cjkQueued.wordCount = 10_000
        cjkQueued.chapters = "2/2"
        // Unequal chapters: reading 0.5 of progress spans ch1 (2_000) + 3_000 of ch2 -> 5_000,
        // while reading 0.2 of progress with chapter counts [2_000, 8_000] differs when ch1 was
        // previously read and ch2 was shortened, or with exact chapter sum 9_200 (within 10% of 10_000).
        cjkQueued.chapterWordCounts = [2_200, 7_000]
        cjkQueued.workFandoms = ["JP Fandom"]

        let excludedQueued = SavedWork(title: "Excluded Queue Fic", author: "Author E")
        excludedQueued.isSaved = false
        excludedQueued.isQueuedForLater = true
        excludedQueued.wordCount = 12_000
        excludedQueued.workFandoms = ["Queue Fandom"]
        let userTag = Tag(name: "SkipMeTag")
        excludedQueued.tags = [userTag]

        // Pre-D1 session: blank fandoms/language/authorAccounts -> must fall back to `cjkQueued`.
        let sCJK = ReadingSession(
            workID: cjkQueued.id, workTitle: cjkQueued.title,
            startedAt: date(day: 2), endedAt: date(day: 2).addingTimeInterval(600),
            durationSeconds: 600,
            startProgress: 0, endingProgress: 1.0, wordCount: 10_000,
            chapterCountAtVisit: 2, didFinish: true
        )
        let sExcluded = ReadingSession(
            workID: excludedQueued.id, workTitle: excludedQueued.title,
            startedAt: date(day: 3), endedAt: date(day: 3).addingTimeInterval(600),
            durationSeconds: 600,
            startProgress: 0, endingProgress: 1.0, wordCount: 12_000, didFinish: true
        )
        [saved, cjkQueued, excludedQueued].forEach { context.insert($0) }
        context.insert(userTag)
        [sCJK, sExcluded].forEach { context.insert($0) }
        try context.save()

        let scope = HomeReadingStats.insightsScope(
            .main, from: [saved, cjkQueued, excludedQueued], hideMature: true, revealed: false
        )
        let options = InsightsOptions(excludedTags: ["SkipMeTag"])
        let doc = InsightsExportService.makeDocument(
            works: scope.libraryWorks,
            readingWorks: scope.readingWorks,
            sessions: scope.sessions([sCJK, sExcluded], in: context),
            options: options
        )
        // Queue-only work excluded via user Tag must NOT appear in export.
        #expect(doc.sittings.map(\.workID) == [cjkQueued.id])
        let exportedCJK = try #require(doc.sittings.first)
        #expect(exportedCJK.wordUnit == "characters")
        // D3 chapter counts [2_200, 7_000] sum to 9_200 (matches screen, not legacy 10_000).
        #expect(exportedCJK.wordsRead == 9_200)
        #expect(exportedCJK.authors == ["Author JP"])
        #expect(exportedCJK.fandoms == ["JP Fandom"])
        #expect(exportedCJK.language == "日本語")
        // Status rows remain saved-library-only (never queue-only).
        #expect(doc.statuses.map(\.workID) == [saved.id])
    }

    /// Review 3 P2 #4, P2 #5, P2 #8, P3 #9, P3 #12: scope/re-lock state machine,
    /// Library menu gating, locked Reset alert copy, and Discreet Mode shared masker.
    @Test func scopeStateRelockLibraryMenuAndLockedResetCopy() throws {
        // P2 #4: Library's "Reading Insights" menu entry shows for queue-only / mature-only / deleted-with-sessions.
        #expect(HomeReadingStats.showsReadingInsightsMenuEntry(liveWorkCount: 1, sessionCount: 0))
        #expect(HomeReadingStats.showsReadingInsightsMenuEntry(liveWorkCount: 0, sessionCount: 1))
        #expect(!HomeReadingStats.showsReadingInsightsMenuEntry(liveWorkCount: 0, sessionCount: 0))

        // P2 #5 & P3 #12: lock -> reveal -> Include Hidden -> re-lock clears state synchronously.
        var state = ReadingInsightsScopeState()
        #expect(state.screenScope(hideMature: true, revealed: false) == .main)
        #expect(!state.canIncludeHidden(hideMature: true, revealed: false))
        #expect(state.scopeSuffix(hideMature: true, revealed: false) == "")

        #expect(state.handleRevealChange(revealed: true, hideMature: true) == true)
        #expect(state.canIncludeHidden(hideMature: true, revealed: true))
        state.includeHidden = true
        #expect(state.screenScope(hideMature: true, revealed: true) == .combined)
        #expect(state.scopeSuffix(hideMature: true, revealed: true) == " · incl. hidden")

        var mainBuilder = InsightsDiscreetMasker.Builder()
        mainBuilder.registerFandom("Fandom One")
        mainBuilder.registerFandom("Secret Fandom")
        let mainMasker = mainBuilder.build()
        var hiddenBuilder = InsightsDiscreetMasker.Builder()
        hiddenBuilder.registerFandom("Secret Fandom")
        let hiddenMasker = hiddenBuilder.build()

        state.recordGather(
            scope: .combined,
            hiddenInsights: ReadingInsights(totalWordsRead: 20_000),
            hiddenMasker: hiddenMasker
        )
        // P3 #12: combined mode uses `mainMasker` in Hidden section so "Secret Fandom" stays "Fandom B".
        #expect(state.hiddenSectionMasker(
            mainMasker: mainMasker, hideMature: true, revealed: true
        ).fandom("Secret Fandom") == "Fandom B")

        // Before `handleRevealChange` runs on the re-lock render pass, stale `.combined` cannot paint.
        #expect(!state.mayDisplayLoadedData(hideMature: true, revealed: false))

        // Re-lock clears `includeHidden` and cached hidden figures/masker synchronously.
        let mustReload = state.handleRevealChange(revealed: false, hideMature: true)
        #expect(mustReload == true)
        #expect(state.includeHidden == false)
        #expect(state.hiddenInsights == nil)
        #expect(state.hiddenMasker == .empty)
        #expect(state.screenScope(hideMature: true, revealed: false) == .main)
        #expect(state.scopeSuffix(hideMature: true, revealed: false) == "")
        state.recordGather(scope: .main, hiddenInsights: nil, hiddenMasker: .empty)
        #expect(state.mayDisplayLoadedData(hideMature: true, revealed: false))

        // Toggling `hideMature` OFF then back ON while `revealed == true` resets `includeHidden`.
        state.includeHidden = true
        state.handleHideMatureChange(hideMature: false, revealed: true)
        #expect(state.includeHidden == false)
        #expect(state.hiddenInsights == nil)

        // P3 #9: locked Reset alert never leaks hidden counts.
        let f = try makeFixture()
        let lockedScope = HomeReadingStats.insightsScope(.main, from: f.library, hideMature: true, revealed: false)
        let lockedCounts = InsightsExportService.resetCounts(in: f.context, scope: lockedScope)
        #expect(lockedCounts == InsightsResetCounts(sessionCount: 2, workCount: 2))
        let totalCounts = InsightsExportService.resetCounts(in: f.context)
        #expect(totalCounts == InsightsResetCounts(sessionCount: 7, workCount: 6))

        let zeroLockedCopy = InsightsResetAlertCopy.make(
            counts: InsightsResetCounts(sessionCount: 0, workCount: 0), isPrivacyLocked: true
        )
        #expect(zeroLockedCopy.title == "Reset Reading Log?")
        #expect(zeroLockedCopy.destructiveButtonTitle == "Reset Reading Log")
        #expect(zeroLockedCopy.message.contains("hidden mature"))

        let visibleLockedCopy = InsightsResetAlertCopy.make(counts: lockedCounts, isPrivacyLocked: true)
        #expect(visibleLockedCopy.message.contains("2 reading sittings"))
        #expect(!visibleLockedCopy.message.contains("7"))
        #expect(visibleLockedCopy.message.contains("hidden mature"))
    }
}
