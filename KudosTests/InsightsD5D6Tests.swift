import Foundation
import SwiftData
import Testing
@testable import Kudos

@MainActor
@Suite struct InsightsD5D6Tests {
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

    private func makeDefaults() throws -> UserDefaults {
        let suite = "InsightsD5D6Tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        utcCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func interval(year: Int, month: Int) -> DateInterval {
        let start = date(year: year, month: month, day: 1, hour: 0)
        return utcCalendar.dateInterval(of: .month, for: start)!
    }

    private func parseCSV(_ csv: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(csv)
        var index = 0
        while index < chars.count {
            let ch = chars[index]
            if inQuotes {
                if ch == "\"" {
                    if index + 1 < chars.count && chars[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(ch)
                }
            } else if ch == "\"" {
                inQuotes = true
            } else if ch == "," {
                row.append(field)
                field = ""
            } else if ch == "\n" {
                row.append(field)
                if !(row.count == 1 && row[0].isEmpty) {
                    rows.append(row)
                }
                row = []
                field = ""
            } else if ch != "\r" {
                field.append(ch)
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    @Test func optionsDefaultsRoundTripNormalizationAndClamping() throws {
        let defaults = try makeDefaults()
        let initial = InsightsOptions.load(from: defaults)
        #expect(initial.discreetMode == false)
        #expect(initial.hideReadingTime == false)
        #expect(initial.countRereads == true)
        #expect(initial.countReadAloud == true)
        #expect(initial.askAboutUntouched == true)
        #expect(initial.untouchedDays == 21)
        #expect(initial.excludedFandoms.isEmpty)
        #expect(initial.excludedTags.isEmpty)
        #expect(initial.excludedWorkIDs.isEmpty)

        let id1 = UUID()
        let custom = InsightsOptions(
            discreetMode: true,
            hideReadingTime: true,
            countRereads: false,
            countReadAloud: false,
            askAboutUntouched: false,
            untouchedDays: 999,
            excludedFandoms: [" Star Wars ", "star wars", ""],
            excludedTags: [" Angst ", "Fluff", "angst"],
            excludedWorkIDs: [id1.uuidString.uppercased(), id1.uuidString.lowercased(), " "]
        )
        custom.save(to: defaults, notifySync: false)

        let loaded = InsightsOptions.load(from: defaults)
        #expect(loaded.discreetMode == true)
        #expect(loaded.hideReadingTime == true)
        #expect(loaded.countRereads == false)
        #expect(loaded.countReadAloud == false)
        #expect(loaded.askAboutUntouched == false)
        #expect(loaded.untouchedDays == 365)
        #expect(loaded.excludedFandoms == ["Star Wars"])
        #expect(loaded.excludedTags == ["Angst", "Fluff"])
        #expect(loaded.excludedWorkIDs == [id1.uuidString.lowercased()])
        #expect(loaded.excludedCount == 4)
    }

    @Test func singleFilterExcludesByWorkIDFandomAliasTagAndDeletedSnapshot() throws {
        let context = try makeContext()
        let aug = interval(year: 2026, month: 8)
        let jul = interval(year: 2026, month: 7)

        let keptWork = SavedWork(title: "Keep Me", author: "Author K")
        keptWork.wordCount = 10_000
        keptWork.workFandoms = ["Haikyuu!!"]
        keptWork.workFreeforms = ["Found Family"]
        keptWork.workTags = ["Found Family"]
        keptWork.isFinished = true

        let excludedByWorkID = SavedWork(title: "Skip By ID", author: "Author W")
        excludedByWorkID.wordCount = 20_000
        excludedByWorkID.workFandoms = ["Haikyuu!!"]

        let excludedByFandom = SavedWork(title: "Skip By Alias Fandom", author: "Author F")
        excludedByFandom.wordCount = 30_000
        excludedByFandom.workFandoms = ["MCU"]

        let excludedByTag = SavedWork(title: "Skip By Tag", author: "Author T")
        excludedByTag.wordCount = 40_000
        excludedByTag.workFandoms = ["Sherlock"]
        excludedByTag.workFreeforms = ["Major Character Death"]
        excludedByTag.workTags = ["Major Character Death"]

        let orphanDeletedID = UUID()
        let orphanSession = ReadingSession(
            workID: orphanDeletedID,
            workTitle: "Deleted Excluded Work",
            startedAt: date(year: 2026, month: 8, day: 10, hour: 20),
            endedAt: date(year: 2026, month: 8, day: 10, hour: 20).addingTimeInterval(1_200),
            durationSeconds: 1_200,
            startProgress: 0,
            endingProgress: 1.0,
            wordCount: 5_000,
            didFinish: true
        )
        orphanSession.fandoms = ["Star Trek"]

        let sKeep = ReadingSession(
            workID: keptWork.id, workTitle: keptWork.title,
            startedAt: date(year: 2026, month: 8, day: 2),
            endedAt: date(year: 2026, month: 8, day: 2).addingTimeInterval(600),
            durationSeconds: 600,
            startProgress: 0, endingProgress: 1.0, wordCount: 10_000, didFinish: true
        )
        let sID = ReadingSession(
            workID: excludedByWorkID.id, workTitle: excludedByWorkID.title,
            startedAt: date(year: 2026, month: 8, day: 3),
            endedAt: date(year: 2026, month: 8, day: 3).addingTimeInterval(900),
            durationSeconds: 900,
            startProgress: 0, endingProgress: 0.5, wordCount: 20_000
        )
        let sFandom = ReadingSession(
            workID: excludedByFandom.id, workTitle: excludedByFandom.title,
            startedAt: date(year: 2026, month: 8, day: 4),
            endedAt: date(year: 2026, month: 8, day: 4).addingTimeInterval(900),
            durationSeconds: 900,
            startProgress: 0, endingProgress: 0.5, wordCount: 30_000
        )
        let sTag = ReadingSession(
            workID: excludedByTag.id, workTitle: excludedByTag.title,
            startedAt: date(year: 2026, month: 8, day: 5),
            endedAt: date(year: 2026, month: 8, day: 5).addingTimeInterval(900),
            durationSeconds: 900,
            startProgress: 0, endingProgress: 0.5, wordCount: 40_000
        )

        [keptWork, excludedByWorkID, excludedByFandom, excludedByTag].forEach { context.insert($0) }
        [orphanSession, sKeep, sID, sFandom, sTag].forEach { context.insert($0) }
        try context.save()

        let aliases = TagAliasResolver(entries: [
            TagAliasResolver.Entry(
                name: "MCU",
                canonicalName: "Marvel Cinematic Universe",
                kind: .fandom
            )
        ])
        let works = [keptWork, excludedByWorkID, excludedByFandom, excludedByTag]

        // Baseline: everything included
        let baseline = ReadingLogService.gatherInsights(
            for: aug, previousPeriod: jul, works: works,
            calendar: utcCalendar, context: context,
            options: InsightsOptions(), aliases: aliases,
            now: date(year: 2026, month: 8, day: 20)
        )
        #expect(baseline.insights.totalWordsRead == 10_000 + 10_000 + 15_000 + 20_000 + 5_000)
        #expect(baseline.libraryStats.totalWorks == 4)

        // Exclusions applied once at gather boundary affect Overview, Taste, Habits, Library & Statistics
        let options = InsightsOptions(
            excludedFandoms: ["Marvel Cinematic Universe", "Star Trek"],
            excludedTags: ["Major Character Death"],
            excludedWorkIDs: [excludedByWorkID.id.uuidString]
        )
        let filtered = ReadingLogService.gatherInsights(
            for: aug, previousPeriod: jul, works: works,
            calendar: utcCalendar, context: context,
            options: options, aliases: aliases,
            now: date(year: 2026, month: 8, day: 20)
        )
        #expect(filtered.insights.totalWordsRead == 10_000)
        #expect(filtered.insights.totalSeconds == 600)
        #expect(filtered.insights.finishedWorksCount == 1)
        #expect(filtered.taste?.fandoms.map(\.name) == ["Haikyuu!!"])
        #expect(filtered.taste?.tags.map(\.name) == ["Found Family"])
        #expect(filtered.habits.fandomTimeline.map(\.name) == ["Haikyuu!!"])
        #expect(filtered.library.unreadWorksCount == 0)
        #expect(filtered.libraryStats.totalWorks == 1)
        #expect(filtered.finishedWorksInPeriod.map(\.id) == [keptWork.id])
    }

    @Test func countReadAloudFalseRemovesListenSessionsFromEveryMetric() throws {
        let context = try makeContext()
        let aug = interval(year: 2026, month: 8)
        let jul = interval(year: 2026, month: 7)

        let readWork = SavedWork(title: "Read Fic", author: "A")
        readWork.wordCount = 6_000
        readWork.workFandoms = ["Fandom One"]

        let listenWork = SavedWork(title: "Listen Fic", author: "B")
        listenWork.wordCount = 8_000
        listenWork.workFandoms = ["Fandom Two"]
        listenWork.isFinished = true

        let sRead = ReadingSession(
            workID: readWork.id, workTitle: readWork.title,
            startedAt: date(year: 2026, month: 8, day: 2, hour: 10),
            endedAt: date(year: 2026, month: 8, day: 2, hour: 10).addingTimeInterval(600),
            durationSeconds: 600,
            startProgress: 0,
            modeRaw: ReadingSession.Mode.read.rawValue,
            endingProgress: 0.5, wordCount: 6_000, didFinish: false
        )
        let sListen = ReadingSession(
            workID: listenWork.id, workTitle: listenWork.title,
            startedAt: date(year: 2026, month: 8, day: 3, hour: 14),
            endedAt: date(year: 2026, month: 8, day: 3, hour: 14).addingTimeInterval(900),
            durationSeconds: 900,
            startProgress: 0,
            modeRaw: ReadingSession.Mode.listen.rawValue,
            playbackRate: 1.25,
            endingProgress: 1.0, wordCount: 8_000, didFinish: true
        )

        context.insert(readWork)
        context.insert(listenWork)
        context.insert(sRead)
        context.insert(sListen)
        try context.save()

        let withAudio = ReadingLogService.gatherInsights(
            for: aug, previousPeriod: jul, works: [readWork, listenWork],
            calendar: utcCalendar, context: context,
            options: InsightsOptions(countReadAloud: true),
            now: date(year: 2026, month: 8, day: 20)
        )
        #expect(withAudio.insights.totalWordsRead == 11_000)
        #expect(withAudio.insights.totalSeconds == 1_500)
        #expect(withAudio.insights.listeningSeconds == 900)
        #expect(withAudio.insights.finishedWorksCount == 1)
        #expect(withAudio.finishedWorksInPeriod.count == 1)

        let withoutAudio = ReadingLogService.gatherInsights(
            for: aug, previousPeriod: jul, works: [readWork, listenWork],
            calendar: utcCalendar, context: context,
            options: InsightsOptions(countReadAloud: false),
            now: date(year: 2026, month: 8, day: 20)
        )
        #expect(withoutAudio.insights.totalWordsRead == 3_000)
        #expect(withoutAudio.insights.totalSeconds == 600)
        #expect(withoutAudio.insights.listeningSeconds == 0)
        #expect(withoutAudio.insights.finishedWorksCount == 0)
        #expect(withoutAudio.taste?.totalWorksCount == 1)
        #expect(withoutAudio.taste?.fandoms.map(\.name) == ["Fandom One"])
        #expect(withoutAudio.finishedWorksInPeriod.isEmpty)
    }

    @Test func hiddenWorkSessionsLeaveGatheredFiguresAlongsideOptionsFilter() throws {
        let context = try makeContext()
        let aug = interval(year: 2026, month: 8)
        let jul = interval(year: 2026, month: 7)

        let visible = SavedWork(title: "Visible Fic", author: "A")
        visible.wordCount = 10_000
        visible.workFandoms = ["Fandom One"]
        let listened = SavedWork(title: "Listened Fic", author: "B")
        listened.wordCount = 4_000
        listened.workFandoms = ["Fandom Two"]
        let hiddenID = UUID()

        let sVisible = ReadingSession(
            workID: visible.id, workTitle: visible.title,
            startedAt: date(year: 2026, month: 8, day: 2),
            endedAt: date(year: 2026, month: 8, day: 2).addingTimeInterval(600),
            durationSeconds: 600,
            startProgress: 0, endingProgress: 1.0, wordCount: 10_000, didFinish: true
        )
        let sListen = ReadingSession(
            workID: listened.id, workTitle: listened.title,
            startedAt: date(year: 2026, month: 8, day: 3),
            endedAt: date(year: 2026, month: 8, day: 3).addingTimeInterval(900),
            durationSeconds: 900,
            startProgress: 0,
            modeRaw: ReadingSession.Mode.listen.rawValue,
            endingProgress: 0.5, wordCount: 4_000
        )
        // A privacy-gated work: not in `works`, so only `hiddenWorkIDs` keeps it out.
        let sHidden = ReadingSession(
            workID: hiddenID, workTitle: "Hidden Mature Fic",
            startedAt: date(year: 2026, month: 8, day: 4),
            endedAt: date(year: 2026, month: 8, day: 4).addingTimeInterval(1_200),
            durationSeconds: 1_200,
            startProgress: 0, endingProgress: 1.0, wordCount: 20_000, didFinish: true
        )
        sHidden.fandoms = ["Secret Fandom"]

        [visible, listened].forEach { context.insert($0) }
        [sVisible, sListen, sHidden].forEach { context.insert($0) }
        try context.save()

        let gathered = ReadingLogService.gatherInsights(
            for: aug, previousPeriod: jul, works: [visible, listened],
            hiddenWorkIDs: [hiddenID],
            calendar: utcCalendar, context: context,
            options: InsightsOptions(countReadAloud: false),
            now: date(year: 2026, month: 8, day: 20)
        )
        #expect(gathered.insights.totalWordsRead == 10_000)
        #expect(gathered.insights.totalSeconds == 600)
        #expect(gathered.insights.fandomWordsShares.filter { !$0.isRemainder }.map(\.name) == ["Fandom One"])
        #expect(gathered.filteredSessions.map(\.id) == [sVisible.id])
    }

    @Test func countRereadsFalseExcludesRereadSittingsAndRereadList() throws {
        let context = try makeContext()
        let jan = interval(year: 2026, month: 1)
        let feb = interval(year: 2026, month: 2)

        let work = SavedWork(title: "Comfort Fic", author: "Writer")
        work.wordCount = 10_000
        work.workFandoms = ["Original Work"]
        work.isFinished = true

        // First read-through in January
        let first1 = ReadingSession(
            workID: work.id, workTitle: work.title,
            startedAt: date(year: 2026, month: 1, day: 5),
            endedAt: date(year: 2026, month: 1, day: 5).addingTimeInterval(400),
            durationSeconds: 400,
            startProgress: 0, endingProgress: 0.4, wordCount: 10_000, didFinish: false
        )
        let first2 = ReadingSession(
            workID: work.id, workTitle: work.title,
            startedAt: date(year: 2026, month: 1, day: 6),
            endedAt: date(year: 2026, month: 1, day: 6).addingTimeInterval(600),
            durationSeconds: 600,
            startProgress: 0.4, endingProgress: 1.0, wordCount: 10_000, didFinish: true
        )
        // Second read-through (reread) in February
        let reread1 = ReadingSession(
            workID: work.id, workTitle: work.title,
            startedAt: date(year: 2026, month: 2, day: 4),
            endedAt: date(year: 2026, month: 2, day: 4).addingTimeInterval(500),
            durationSeconds: 500,
            startProgress: 0, endingProgress: 0.5, wordCount: 10_000, didFinish: false
        )
        let reread2 = ReadingSession(
            workID: work.id, workTitle: work.title,
            startedAt: date(year: 2026, month: 2, day: 5),
            endedAt: date(year: 2026, month: 2, day: 5).addingTimeInterval(500),
            durationSeconds: 500,
            startProgress: 0.5, endingProgress: 1.0, wordCount: 10_000, didFinish: true
        )

        context.insert(work)
        [first1, first2, reread1, reread2].forEach { context.insert($0) }
        try context.save()

        let withRereads = ReadingLogService.gatherInsights(
            for: feb, previousPeriod: jan, works: [work],
            calendar: utcCalendar, context: context,
            options: InsightsOptions(countRereads: true),
            now: date(year: 2026, month: 2, day: 20)
        )
        #expect(withRereads.insights.totalWordsRead == 10_000)
        #expect(withRereads.insights.totalSeconds == 1_000)
        #expect(withRereads.insights.finishedWorksCount == 1)
        #expect(withRereads.habits.rereads.count == 1)
        #expect(withRereads.habits.rereads.first?.finishCount == 2)

        let withoutRereads = ReadingLogService.gatherInsights(
            for: feb, previousPeriod: jan, works: [work],
            calendar: utcCalendar, context: context,
            options: InsightsOptions(countRereads: false),
            now: date(year: 2026, month: 2, day: 20)
        )
        #expect(withoutRereads.insights.totalWordsRead == 0)
        #expect(withoutRereads.insights.totalSeconds == 0)
        #expect(withoutRereads.insights.finishedWorksCount == 0)
        #expect(withoutRereads.taste == nil)
        #expect(withoutRereads.habits.rereads.isEmpty)
        #expect(withoutRereads.finishedWorksInPeriod.isEmpty)

        // First read-through in January still counts cleanly
        let janWithoutRereads = ReadingLogService.gatherInsights(
            for: jan, previousPeriod: nil, works: [work],
            calendar: utcCalendar, context: context,
            options: InsightsOptions(countRereads: false),
            now: date(year: 2026, month: 2, day: 20)
        )
        #expect(janWithoutRereads.insights.totalWordsRead == 10_000)
        #expect(janWithoutRereads.insights.finishedWorksCount == 1)
    }

    @Test func askAboutUntouchedAndUntouchedDaysControlStillReadingCandidate() throws {
        let context = try makeContext()
        let aug = interval(year: 2026, month: 8)
        let now = date(year: 2026, month: 8, day: 25)

        let staleWork = SavedWork(title: "Partway Work", author: "Author P")
        staleWork.hasEPUB = true
        staleWork.lastSpineIndex = 1
        staleWork.lastScrollFraction = 0.5
        staleWork.chapters = "4/?"
        staleWork.legacyReaderProgress = 0.45
        staleWork.lastReadDate = date(year: 2026, month: 8, day: 15) // 10 days ago
        context.insert(staleWork)

        let stoppedWork = SavedWork(title: "Explicitly Stopped", author: "Author S")
        stoppedWork.hasEPUB = true
        stoppedWork.lastSpineIndex = 1
        stoppedWork.legacyReaderProgress = 0.45
        stoppedWork.lastReadDate = date(year: 2026, month: 7, day: 1)
        stoppedWork.setReadingStatus(.stopped, at: date(year: 2026, month: 8, day: 1))
        context.insert(stoppedWork)
        try context.save()

        // At 21 days threshold, 10 days untouched does NOT trigger candidate
        let at21Days = ReadingLogService.gatherInsights(
            for: aug, previousPeriod: nil, works: [stoppedWork, staleWork],
            calendar: utcCalendar, context: context,
            options: InsightsOptions(askAboutUntouched: true, untouchedDays: 21),
            now: now
        )
        #expect(at21Days.library.stillReadingCandidate == nil)

        // At 7 days threshold, staleWork surfaces while stoppedWork is skipped
        let at7Days = ReadingLogService.gatherInsights(
            for: aug, previousPeriod: nil, works: [stoppedWork, staleWork],
            calendar: utcCalendar, context: context,
            options: InsightsOptions(askAboutUntouched: true, untouchedDays: 7),
            now: now
        )
        #expect(at7Days.library.stillReadingCandidate?.id == staleWork.id)
        #expect(at7Days.library.stillReadingCandidate?.daysUntouched == 10)

        // Turning askAboutUntouched off hides it even with a short threshold
        let disabled = ReadingLogService.gatherInsights(
            for: aug, previousPeriod: nil, works: [stoppedWork, staleWork],
            calendar: utcCalendar, context: context,
            options: InsightsOptions(askAboutUntouched: false, untouchedDays: 7),
            now: now
        )
        #expect(disabled.library.stillReadingCandidate == nil)
    }

    @Test func discreetModeUsesStableLetterPlaceholdersAcrossScreenAndExport() throws {
        let context = try makeContext()
        let aug = interval(year: 2026, month: 8)
        let now = date(year: 2026, month: 8, day: 25)

        let w1 = SavedWork(title: "Midnight Tea, Vol 1", author: "SecretAuthorOne")
        w1.wordCount = 20_000
        w1.workFandoms = ["Arcane"]
        w1.workRelationships = ["Caitlyn/Vi"]
        w1.workCharacters = ["Vi (Arcane)"]
        w1.workFreeforms = ["Slow Burn", "Found Family"]
        w1.workTags = ["Slow Burn", "Found Family"]
        w1.isFinished = true

        let w2 = SavedWork(title: "Stars Above", author: "SecretAuthorTwo")
        w2.wordCount = 10_000
        w2.workFandoms = ["Mass Effect"]
        w2.workRelationships = ["Femshep/Garrus"]
        w2.workCharacters = ["Garrus Vakarian"]
        w2.workFreeforms = ["Banter"]
        w2.workTags = ["Banter"]
        w2.setReadingStatus(.stopped, at: date(year: 2026, month: 8, day: 18))
        w2.stoppedAt = date(year: 2026, month: 8, day: 18)
        w2.stopReasonRaw = "tooLong"
        w2.stopTag = "Slow Burn"
        w2.stopNote = "Dropped near Caitlyn/Vi chapter in Stars Above"

        let s1 = ReadingSession(
            workID: w1.id, workTitle: w1.title,
            startedAt: date(year: 2026, month: 8, day: 2),
            endedAt: date(year: 2026, month: 8, day: 2).addingTimeInterval(1_200),
            durationSeconds: 1_200,
            startProgress: 0, endingProgress: 1.0, wordCount: 20_000, didFinish: true
        )
        let s2 = ReadingSession(
            workID: w2.id, workTitle: w2.title,
            startedAt: date(year: 2026, month: 8, day: 3),
            endedAt: date(year: 2026, month: 8, day: 3).addingTimeInterval(600),
            durationSeconds: 600,
            startProgress: 0, endingProgress: 0.4, wordCount: 10_000, didFinish: false
        )

        context.insert(w1)
        context.insert(w2)
        context.insert(s1)
        context.insert(s2)
        try context.save()

        let options = InsightsOptions(discreetMode: true)
        let gathered = ReadingLogService.gatherInsights(
            for: aug, previousPeriod: nil, works: [w1, w2],
            calendar: utcCalendar, context: context, options: options, now: now
        )
        let masker = gathered.discreetMasker
        #expect(masker.fandom("Arcane") == "Fandom A")
        #expect(masker.fandom("Mass Effect") == "Fandom B")
        #expect(masker.ship("Caitlyn/Vi") == "Ship A")
        #expect(masker.ship("Femshep/Garrus") == "Ship B")
        #expect(masker.character("Vi (Arcane)").hasPrefix("Character "))
        #expect(masker.tag("Slow Burn") == masker.tag("slow burn"))
        #expect(masker.work(id: w1.id, title: w1.title) != masker.work(id: w2.id, title: w2.title))
        #expect(masker.fandom(ReadingInsights.remainderName) == ReadingInsights.remainderName)
        #expect(gathered.insights.totalWordsRead == 24_000)

        let jsonBytes = try InsightsExportService.jsonData(
            works: [w1, w2], sessions: [s1, s2], options: options, exportedAt: now
        )
        let jsonString = try #require(String(bytes: jsonBytes, encoding: .utf8))
        let csv = InsightsExportService.csvString(
            works: [w1, w2], sessions: [s1, s2], options: options, exportedAt: now
        )

        for secret in ["Arcane", "Mass Effect", "Caitlyn/Vi", "Femshep/Garrus",
                       "Vi (Arcane)", "Garrus Vakarian", "Slow Burn", "Found Family",
                       "Midnight Tea", "Stars Above", "SecretAuthorOne", "SecretAuthorTwo"] {
            #expect(!jsonString.contains(secret))
            #expect(!csv.contains(secret))
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let doc = try decoder.decode(InsightsExportDocument.self, from: jsonBytes)
        #expect(doc.discreetMode == true)
        #expect(doc.sittings.count == 2)
        #expect(doc.statuses.count == 2)
        #expect(doc.sittings.map(\.wordsRead).reduce(0, +) == 24_000)
        // Work A placeholder must match across sitting, status, reason, and note for w2
        let w2Sitting = try #require(doc.sittings.first { $0.workID == w2.id })
        let w2Status = try #require(doc.statuses.first { $0.workID == w2.id })
        let w2Reason = try #require(doc.reasons.first { $0.workID == w2.id })
        let w2Note = try #require(doc.notes.first { $0.workID == w2.id })
        #expect(w2Sitting.workTitle == w2Status.workTitle)
        #expect(w2Reason.workTitle == w2Status.workTitle)
        #expect(w2Note.workTitle == w2Status.workTitle)
        #expect(w2Sitting.fandoms == w2Status.fandoms)
        #expect(w2Reason.reason == "tooLong")
        #expect(w2Note.note == "[Hidden in Discreet Mode]")
    }

    @Test func csvAndJsonExportsProduceValidShapeAndRespectExclusions() throws {
        let context = try makeContext()
        let wIncluded = SavedWork(title: "Salt, Wind & \"Anchors\"", author: "Author, One")
        wIncluded.wordCount = 12_000
        wIncluded.workFandoms = ["Original"]
        wIncluded.workFreeforms = ["Nautical"]
        wIncluded.setReadingStatus(.stopped, at: date(year: 2026, month: 8, day: 12))
        wIncluded.stoppedAt = date(year: 2026, month: 8, day: 12)
        wIncluded.stopReasonRaw = "tagDealbreaker"
        wIncluded.stopTag = "Nautical"
        wIncluded.stopNote = "Line one, \"quoted\" detail"

        let wFinished = SavedWork(title: "Harbor Light", author: "Author Two")
        wFinished.wordCount = 8_000
        wFinished.workFandoms = ["Harbor Fandom"]
        wFinished.isFinished = true

        let wExcluded = SavedWork(title: "Secret Excluded", author: "Hidden Author")
        wExcluded.wordCount = 50_000
        wExcluded.workFandoms = ["Excluded Fandom"]

        let s1 = ReadingSession(
            workID: wIncluded.id, workTitle: wIncluded.title,
            startedAt: date(year: 2026, month: 8, day: 5, hour: 10),
            endedAt: date(year: 2026, month: 8, day: 5, hour: 11),
            durationSeconds: 3_600,
            startProgress: 0,
            activeSeconds: 2_400,
            endingProgress: 0.5, wordCount: 12_000, didFinish: false
        )
        let s2 = ReadingSession(
            workID: wFinished.id, workTitle: wFinished.title,
            startedAt: date(year: 2026, month: 8, day: 6, hour: 10),
            endedAt: date(year: 2026, month: 8, day: 6, hour: 11),
            durationSeconds: 1_800,
            startProgress: 0,
            modeRaw: ReadingSession.Mode.listen.rawValue,
            playbackRate: 1.5,
            endingProgress: 1.0, wordCount: 8_000, didFinish: true
        )
        let sExcluded = ReadingSession(
            workID: wExcluded.id, workTitle: wExcluded.title,
            startedAt: date(year: 2026, month: 8, day: 7, hour: 10),
            endedAt: date(year: 2026, month: 8, day: 7, hour: 11),
            durationSeconds: 1_200,
            startProgress: 0, endingProgress: 1.0, wordCount: 50_000, didFinish: true
        )

        [wIncluded, wFinished, wExcluded].forEach { context.insert($0) }
        [s1, s2, sExcluded].forEach { context.insert($0) }
        try context.save()

        let options = InsightsOptions(excludedFandoms: ["Excluded Fandom"])
        let works = [wIncluded, wFinished, wExcluded]
        let sessions = [s1, s2, sExcluded]

        let csv = InsightsExportService.csvString(works: works, sessions: sessions, options: options)
        let rows = parseCSV(csv)
        #expect(rows.first == InsightsExportService.csvHeaderColumns)
        // 2 sittings + 2 work statuses = 4 data rows + 1 header row = 5
        #expect(rows.count == 5)
        let sittingRows = rows.dropFirst().filter { $0[0] == "sitting" }
        let statusRows = rows.dropFirst().filter { $0[0] == "status" }
        #expect(sittingRows.count == 2)
        #expect(statusRows.count == 2)
        #expect(sittingRows.allSatisfy { $0.count == InsightsExportService.csvHeaderColumns.count })
        #expect(statusRows.allSatisfy { $0.count == InsightsExportService.csvHeaderColumns.count })
        #expect(!csv.contains("Secret Excluded"))
        #expect(statusRows.contains { $0[3] == "Salt, Wind & \"Anchors\"" && $0[22] == "Line one, \"quoted\" detail" })

        let json = try InsightsExportService.jsonData(works: works, sessions: sessions, options: options)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let doc = try decoder.decode(InsightsExportDocument.self, from: json)
        #expect(doc.sittings.count == 2)
        #expect(doc.statuses.count == 2)
        #expect(doc.reasons.count == 1)
        #expect(doc.notes.count == 1)
        #expect(doc.reasons.first?.reason == "tagDealbreaker")
        #expect(doc.reasons.first?.stopTag == "Nautical")
        #expect(doc.notes.first?.note == "Line one, \"quoted\" detail")
        #expect(doc.statuses.contains { $0.workID == wFinished.id && $0.status == "finished" })
        #expect(doc.sittings.first { $0.sessionID == s2.id }?.mode == "listen")
        #expect(doc.sittings.first { $0.sessionID == s1.id }?.wordsRead == 6_000)
    }

    @Test func resetLogStatesCountsDeletesSessionsAndPreservesWorksProgressAndStatuses() throws {
        let context = try makeContext()
        let modifiedDate = date(year: 2026, month: 8, day: 1)
        let stoppedDate = date(year: 2026, month: 8, day: 10)

        let stopped = SavedWork(title: "Stopped Story", author: "Author A")
        stopped.lastSpineIndex = 4
        stopped.lastScrollFraction = 0.62
        stopped.readiumLocator = "{\"href\":\"ch5.xhtml\"}"
        stopped.progressModifiedAt = modifiedDate
        stopped.lastReadDate = stoppedDate
        stopped.isFinished = false
        stopped.setReadingStatus(.stopped, at: stoppedDate)
        stopped.stoppedAt = stoppedDate
        stopped.stopReasonRaw = "lostInterest"
        stopped.stopTag = "Pacing"
        stopped.stopNote = "Slowed down in chapter 5"
        stopped.stackThreshold = 5
        stopped.stackBaselineChapterCount = 9

        let finished = SavedWork(title: "Finished Story", author: "Author B")
        finished.isFinished = true
        finished.lastSpineIndex = 10
        finished.lastScrollFraction = 1.0
        finished.readiumLocator = "{\"href\":\"ch11.xhtml\"}"
        finished.progressModifiedAt = modifiedDate
        finished.lastReadDate = modifiedDate

        let s1 = ReadingSession(
            workID: stopped.id, workTitle: stopped.title,
            startedAt: date(year: 2026, month: 8, day: 2),
            endedAt: date(year: 2026, month: 8, day: 2).addingTimeInterval(300),
            durationSeconds: 300
        )
        let s2 = ReadingSession(
            workID: stopped.id, workTitle: stopped.title,
            startedAt: date(year: 2026, month: 8, day: 5),
            endedAt: date(year: 2026, month: 8, day: 5).addingTimeInterval(400),
            durationSeconds: 400
        )
        let s3 = ReadingSession(
            workID: finished.id, workTitle: finished.title,
            startedAt: date(year: 2026, month: 8, day: 3),
            endedAt: date(year: 2026, month: 8, day: 3).addingTimeInterval(900),
            durationSeconds: 900, didFinish: true
        )

        context.insert(stopped)
        context.insert(finished)
        [s1, s2, s3].forEach { context.insert($0) }
        try context.save()

        let counts = InsightsExportService.resetCounts(in: context)
        #expect(counts == InsightsResetCounts(sessionCount: 3, workCount: 2))

        let deleted = try InsightsExportService.resetReadingLog(in: context)
        #expect(deleted == 3)
        #expect(try context.fetch(FetchDescriptor<ReadingSession>()).isEmpty)

        // Tombstones were minted via ReadingLogService.delete(_:in:)
        let tombstones = try context.fetch(FetchDescriptor<SyncTombstone>())
        for id in [s1.id, s2.id, s3.id] {
            #expect(tombstones.contains {
                $0.recordType == .readingSession && $0.recordID == id && !$0.signature.isEmpty
            })
        }

        // Works, progress, and D2 statuses are completely untouched
        let remainingWorks = try context.fetch(FetchDescriptor<SavedWork>())
        #expect(remainingWorks.count == 2)
        let verifiedStopped = try #require(remainingWorks.first { $0.id == stopped.id })
        #expect(verifiedStopped.lastSpineIndex == 4)
        #expect(verifiedStopped.lastScrollFraction == 0.62)
        #expect(verifiedStopped.readiumLocator == "{\"href\":\"ch5.xhtml\"}")
        #expect(verifiedStopped.progressModifiedAt == modifiedDate)
        #expect(verifiedStopped.lastReadDate == stoppedDate)
        #expect(verifiedStopped.isFinished == false)
        #expect(verifiedStopped.readingStatusRaw == "stopped")
        #expect(verifiedStopped.statusChangedAt == stoppedDate)
        #expect(verifiedStopped.stoppedAt == stoppedDate)
        #expect(verifiedStopped.stopReasonRaw == "lostInterest")
        #expect(verifiedStopped.stopTag == "Pacing")
        #expect(verifiedStopped.stopNote == "Slowed down in chapter 5")
        #expect(verifiedStopped.stackThreshold == 5)
        #expect(verifiedStopped.stackBaselineChapterCount == 9)

        let verifiedFinished = try #require(remainingWorks.first { $0.id == finished.id })
        #expect(verifiedFinished.isFinished == true)
        #expect(verifiedFinished.lastSpineIndex == 10)
        #expect(verifiedFinished.lastScrollFraction == 1.0)
        #expect(verifiedFinished.readiumLocator == "{\"href\":\"ch11.xhtml\"}")
        #expect(verifiedFinished.progressModifiedAt == modifiedDate)
        #expect(verifiedFinished.lastReadDate == modifiedDate)
    }
}
