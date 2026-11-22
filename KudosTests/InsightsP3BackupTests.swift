import Foundation
import SwiftData
import Testing
@testable import Kudos

/// T-536 backup contract: every D7 to D11 field is additive on v8, absent when unrecorded, and an
/// archive that lacks a key (older iOS, Android) never wipes what the device recorded.
extension PersistenceGateSuites {
    @MainActor
    @Suite(.serialized)
    struct InsightsP3BackupTests {
        private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        private func makeContext() throws -> ModelContext {
            let schema = Schema([
                SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
                WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
                SavedSearch.self, QueueSavedSearchLink.self, SyncTombstone.self, ReadingAnnotation.self,
                ReadingSession.self, ReadingFavorite.self, FandomReadWatermark.self,
                ChapterUpdateEvent.self
            ])
            return ModelContext(try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            ))
        }

        private func defaults() throws -> UserDefaults {
            let name = "InsightsP3BackupTests.\(UUID().uuidString)"
            let value = try #require(UserDefaults(suiteName: name))
            value.removePersistentDomain(forName: name)
            return value
        }

        private func contents(
            works: [SavedWork],
            sessions: [ReadingSession] = [],
            events: [ChapterUpdateEvent] = []
        ) throws -> KudosBackupContents {
            try KudosBackupService.makeContents(
                works: works, bookmarks: [], fonts: [], readingQueues: [],
                readingSessions: sessions, chapterUpdateEvents: events, defaults: try defaults()
            )
        }

        private func root(_ contents: KudosBackupContents) throws -> [String: Any] {
            try #require(JSONSerialization.jsonObject(with: contents.manifestData()) as? [String: Any])
        }

        private func reload(_ root: [String: Any]) throws -> KudosBackupContents {
            KudosBackupContents(manifest: try KudosBackupContents.decodeManifest(
                JSONSerialization.data(withJSONObject: root)
            ))
        }

        private func recordedWork(id: UUID = UUID()) -> SavedWork {
            let work = SavedWork(id: id, title: "Recorded", author: "A")
            work.ao3WorkID = 500
            work.recordImportSource(.series, at: t0)
            work.recordStatsAtSave(
                WorkStatsAtSave(kudos: 310, hits: 4_000, bookmarks: 12, fandomWorks: 9_000), at: t0
            )
            work.ageDaysAtSave = 30
            work.recordOwnAction(.bookmarked(isPrivate: true), at: t0.addingTimeInterval(10))
            work.recordOwnAction(.commented, at: t0.addingTimeInterval(20))
            work.recordKudosGiven(at: t0.addingTimeInterval(30))
            return work
        }

        private func fetchWorks(_ context: ModelContext) throws -> [SavedWork] {
            try context.fetch(FetchDescriptor<SavedWork>())
        }

        // MARK: works (D8, D9, D11)

        @Test func provenanceRoundTripsAndAnUntouchedWorkExportsNoKeys() throws {
            let source = try makeContext()
            let recorded = recordedWork()
            let untouched = SavedWork(title: "Untouched", author: "B")
            source.insert(recorded)
            source.insert(untouched)
            try source.save()
            let exported = try contents(works: [recorded, untouched])
            let json = try root(exported)
            let works = try #require(json["works"] as? [[String: Any]])
            let recordedJSON = try #require(works.first { $0["title"] as? String == "Recorded" })
            let untouchedJSON = try #require(works.first { $0["title"] as? String == "Untouched" })
            for key in [
                "importSourceRaw", "importSourceSince", "kudosAtSave", "hitsAtSave", "bookmarksAtSave",
                "statsSavedAt", "ageDaysAtSave", "fandomWorksAtSave", "bookmarkedAt", "bookmarkIsPrivate",
                "lastCommentedAt", "kudosGivenAt"
            ] {
                #expect(untouchedJSON[key] == nil, "an unrecorded work must not export \(key)")
                #expect(recordedJSON[key] != nil, "a recorded work must export \(key)")
            }
            #expect(json["version"] as? Int == 8)
            #expect(json["chapterUpdateEvents"] == nil)

            let dest = try makeContext()
            _ = try KudosBackupService.restore(try reload(json), into: dest, defaults: try defaults())
            let restored = try #require(try fetchWorks(dest).first { $0.id == recorded.id })
            #expect(restored.importSource == .series)
            #expect(restored.importSourceSince == t0)
            #expect(restored.kudosAtSave == 310)
            #expect(restored.hitsAtSave == 4_000)
            #expect(restored.bookmarksAtSave == 12)
            #expect(restored.statsSavedAt == t0)
            #expect(restored.ageDaysAtSave == 30)
            #expect(restored.fandomWorksAtSave == 9_000)
            #expect(restored.bookmarkedAt == t0.addingTimeInterval(10))
            #expect(restored.bookmarkIsPrivate)
            #expect(restored.lastCommentedAt == t0.addingTimeInterval(20))
            #expect(restored.kudosGivenAt == t0.addingTimeInterval(30))
            let plain = try #require(try fetchWorks(dest).first { $0.id == untouched.id })
            #expect(plain.importSourceRaw == nil)
            #expect(plain.statsSavedAt == nil)
            #expect(plain.bookmarkedAt == nil)
        }

        @Test func anArchiveWithoutTheKeysNeverWipesWhatTheDeviceRecorded() throws {
            let context = try makeContext()
            let work = recordedWork()
            context.insert(work)
            try context.save()
            var json = try root(try contents(works: [work]))
            var works = try #require(json["works"] as? [[String: Any]])
            for key in [
                "importSourceRaw", "importSourceSince", "kudosAtSave", "hitsAtSave", "bookmarksAtSave",
                "statsSavedAt", "ageDaysAtSave", "fandomWorksAtSave", "bookmarkedAt", "bookmarkIsPrivate",
                "lastCommentedAt", "kudosGivenAt"
            ] {
                works[0].removeValue(forKey: key)
            }
            // A newer clock, as an Android re-export of the same work would carry.
            works[0]["lastModifiedAt"] = "2099-01-01T00:00:00Z"
            json["works"] = works
            for mode in [BackupImportMode.reconcile, .merge, .replaceLibrary] {
                _ = try KudosBackupService.restore(
                    try reload(json), into: context, defaults: try defaults(), mode: mode
                )
                let after = try #require(try fetchWorks(context).first { $0.id == work.id })
                #expect(after.importSource == .series, "mode \(mode)")
                #expect(after.kudosAtSave == 310, "mode \(mode)")
                #expect(after.bookmarkedAt == t0.addingTimeInterval(10), "mode \(mode)")
                #expect(after.bookmarkIsPrivate, "mode \(mode)")
                #expect(after.kudosGivenAt == t0.addingTimeInterval(30), "mode \(mode)")
            }
        }

        @Test func mergeKeepsFirstFactsAndMovesActionTimesTheRightWay() throws {
            let id = UUID()
            // The device holds an older bookmark, a later comment, a later kudos time and a source.
            let local = try makeContext()
            let here = SavedWork(id: id, title: "Same", author: "A")
            here.recordImportSource(.search, at: t0)
            here.recordStatsAtSave(WorkStatsAtSave(kudos: 50, hits: 500, bookmarks: nil, fandomWorks: nil), at: t0)
            here.recordOwnAction(.bookmarked(isPrivate: false), at: t0.addingTimeInterval(100))
            here.recordOwnAction(.commented, at: t0.addingTimeInterval(500))
            here.kudosGivenAt = t0.addingTimeInterval(900)
            here.hasGivenKudos = true
            local.insert(here)
            try local.save()

            // The other device recorded a different source and stats, a newer bookmark (now
            // public again), an older comment, and the earlier kudos.
            let other = try makeContext()
            let there = SavedWork(id: id, title: "Same", author: "A")
            there.recordImportSource(.fandom, at: t0.addingTimeInterval(-9))
            there.recordStatsAtSave(WorkStatsAtSave(kudos: 3, hits: 30, bookmarks: nil, fandomWorks: nil), at: t0.addingTimeInterval(-9))
            there.recordOwnAction(.bookmarked(isPrivate: true), at: t0.addingTimeInterval(300))
            there.recordOwnAction(.commented, at: t0.addingTimeInterval(200))
            there.kudosGivenAt = t0.addingTimeInterval(400)
            there.hasGivenKudos = true
            other.insert(there)
            try other.save()
            let archive = try root(try contents(works: [there]))

            _ = try KudosBackupService.restore(try reload(archive), into: local, defaults: try defaults())
            #expect(here.importSource == .search)
            #expect(here.kudosAtSave == 50)
            #expect(here.bookmarkedAt == t0.addingTimeInterval(300))
            #expect(here.bookmarkIsPrivate)
            #expect(here.lastCommentedAt == t0.addingTimeInterval(500))
            #expect(here.kudosGivenAt == t0.addingTimeInterval(400))

            // Replace Library makes the device look like the archive.
            _ = try KudosBackupService.restore(
                try reload(archive), into: local, defaults: try defaults(), mode: .replaceLibrary
            )
            #expect(here.importSource == .fandom)
            #expect(here.kudosAtSave == 3)
            #expect(here.lastCommentedAt == t0.addingTimeInterval(200))
        }

        // MARK: sittings (D7)

        private func timedSession(workID: UUID) -> ReadingSession {
            let session = ReadingSession(
                workID: workID, startedAt: t0, endedAt: t0.addingTimeInterval(900),
                durationSeconds: 900, modeRaw: "read", rulesVersion: 1
            )
            session.chapterSeconds = [3: 120.5, 4: 80]
            session.chapterWords = [3: 3_000, 4: 2_500]
            session.skimmedChapters = [4]
            session.skimmedStoryChapters = [2]
            session.endedAtChapterEnd = true
            session.peekedAtEnding = false
            return session
        }

        @Test func chapterTimingRoundTripsAndAnOldSittingExportsNone() throws {
            let source = try makeContext()
            let work = SavedWork(title: "W", author: "A")
            source.insert(work)
            let timed = timedSession(workID: work.id)
            let old = ReadingSession(workID: work.id, startedAt: t0, endedAt: t0.addingTimeInterval(60), durationSeconds: 60)
            source.insert(timed)
            source.insert(old)
            try source.save()
            let json = try root(try contents(works: [work], sessions: [timed, old]))
            let sessions = try #require(json["readingSessions"] as? [[String: Any]])
            let timedJSON = try #require(sessions.first { $0["id"] as? String == timed.id.uuidString })
            let oldJSON = try #require(sessions.first { $0["id"] as? String == old.id.uuidString })
            for key in ["chapterSecondsJSON", "chapterWordsJSON", "skimmedChaptersJSON", "endedAtChapterEnd", "peekedAtEnding"] {
                #expect(timedJSON[key] != nil, "a timed sitting must export \(key)")
                #expect(oldJSON[key] == nil, "a sitting without chapter timing must not export \(key)")
            }
            #expect(timedJSON["peekedAtEnding"] as? Bool == false)

            let dest = try makeContext()
            _ = try KudosBackupService.restore(try reload(json), into: dest, defaults: try defaults())
            let restored = try #require(try dest.fetch(FetchDescriptor<ReadingSession>()).first { $0.id == timed.id })
            #expect(restored.chapterSeconds == [3: 120.5, 4: 80])
            #expect(restored.chapterWords == [3: 3_000, 4: 2_500])
            #expect(restored.skimmedChapters == [4])
            // The story-chapter judgement (what the words-read calculator uses) travels too.
            #expect(restored.skimmedStoryChapters == [2])
            #expect(timedJSON["skimmedStoryChaptersJSON"] as? String == "[2]")
            #expect(oldJSON["skimmedStoryChaptersJSON"] == nil)
            #expect(restored.endedAtChapterEnd == true)
            #expect(restored.peekedAtEnding == false)
            let plain = try #require(try dest.fetch(FetchDescriptor<ReadingSession>()).first { $0.id == old.id })
            #expect(plain.chapterSecondsJSON == nil)
            #expect(plain.endedAtChapterEnd == nil)
        }

        @Test func aSittingReExportedWithoutTheKeysKeepsItsTimingAndDamagedValuesAreRefused() throws {
            let context = try makeContext()
            let work = SavedWork(title: "W", author: "A")
            context.insert(work)
            let timed = timedSession(workID: work.id)
            context.insert(timed)
            try context.save()
            var json = try root(try contents(works: [work], sessions: [timed]))
            var sessions = try #require(json["readingSessions"] as? [[String: Any]])
            for key in ["chapterSecondsJSON", "chapterWordsJSON", "skimmedChaptersJSON", "skimmedStoryChaptersJSON", "endedAtChapterEnd", "peekedAtEnding"] {
                sessions[0].removeValue(forKey: key)
            }
            sessions[0]["durationSeconds"] = 901
            sessions[0]["lastModifiedAt"] = "2099-01-01T00:00:00Z"
            json["readingSessions"] = sessions
            _ = try KudosBackupService.restore(
                try reload(json), into: context, defaults: try defaults(), mode: .replaceLibrary
            )
            #expect(timed.durationSeconds == 901)
            #expect(timed.chapterSeconds == [3: 120.5, 4: 80])
            #expect(timed.skimmedChapters == [4])
            #expect(timed.skimmedStoryChapters == [2])
            #expect(timed.endedAtChapterEnd == true)

            sessions[0]["chapterSecondsJSON"] = "{\"3\":\"soon\"}"
            sessions[0]["skimmedChaptersJSON"] = "not json"
            json["readingSessions"] = sessions
            _ = try KudosBackupService.restore(
                try reload(json), into: context, defaults: try defaults(), mode: .replaceLibrary
            )
            #expect(timed.chapterSeconds == [3: 120.5, 4: 80])
            #expect(timed.skimmedChapters == [4])
        }

        // MARK: events (D10)

        @Test func eventsRoundTripAndTheKeyIsAbsentWhenThereAreNone() throws {
            let source = try makeContext()
            let work = SavedWork(title: "W", author: "A")
            source.insert(work)
            let event = ChapterUpdateEvent(
                workID: work.id, ao3WorkID: 500, chapterCount: 6, previousChapterCount: 4,
                detectedAt: t0, postedDate: "2026-11-10", rating: "Mature"
            )
            source.insert(event)
            try source.save()
            let withEvents = try root(try contents(works: [work], events: [event]))
            let entries = try #require(withEvents["chapterUpdateEvents"] as? [[String: Any]])
            #expect(entries.count == 1)
            #expect(entries[0]["postedDate"] as? String == "2026-11-10")
            #expect(try root(try contents(works: [work]))["chapterUpdateEvents"] == nil)

            let dest = try makeContext()
            _ = try KudosBackupService.restore(try reload(withEvents), into: dest, defaults: try defaults())
            let restored = try #require(try dest.fetch(FetchDescriptor<ChapterUpdateEvent>()).first)
            #expect(restored.id == event.id)
            #expect(restored.workID == work.id)
            #expect(restored.ao3WorkID == 500)
            #expect(restored.chapterCount == 6)
            #expect(restored.previousChapterCount == 4)
            #expect(restored.detectedAt == t0)
            #expect(restored.postedDate == "2026-11-10")
            #expect(restored.rating == "Mature")
            // Restoring the same archive again adds nothing.
            _ = try KudosBackupService.restore(try reload(withEvents), into: dest, defaults: try defaults())
            #expect(try dest.fetch(FetchDescriptor<ChapterUpdateEvent>()).count == 1)
        }

        @Test func anEventFollowsItsWorkWhenTheMergeKeptTheLocalCopyAndTheEarlierSightingWins() throws {
            // The same AO3 work under two UUIDs: the device's copy survives the merge.
            let source = try makeContext()
            let theirs = SavedWork(title: "Same", author: "A", sourceURL: "https://archiveofourown.org/works/500")
            theirs.ao3WorkID = 500
            source.insert(theirs)
            let sighted = ChapterUpdateEvent(
                workID: theirs.id, ao3WorkID: 500, chapterCount: 6, previousChapterCount: 4,
                detectedAt: t0, postedDate: "2026-11-10"
            )
            source.insert(sighted)
            try source.save()
            let archive = try root(try contents(works: [theirs], events: [sighted]))

            let dest = try makeContext()
            let ours = SavedWork(title: "Same", author: "A", sourceURL: "https://archiveofourown.org/works/500")
            ours.ao3WorkID = 500
            dest.insert(ours)
            // This device saw the same chapters later, under its own event id.
            let later = ChapterUpdateEvent(
                workID: ours.id, ao3WorkID: 500, chapterCount: 6, previousChapterCount: 4,
                detectedAt: t0.addingTimeInterval(3_600)
            )
            dest.insert(later)
            try dest.save()
            _ = try KudosBackupService.restore(try reload(archive), into: dest, defaults: try defaults())
            #expect(try fetchWorks(dest).count == 1)
            let events = try dest.fetch(FetchDescriptor<ChapterUpdateEvent>())
            #expect(events.count == 1)
            #expect(events[0].workID == ours.id)
            #expect(events[0].detectedAt == t0)
            #expect(events[0].postedDate == "2026-11-10")

            // A different work's event is remapped to the surviving copy.
            let fresh = ChapterUpdateEvent(
                workID: theirs.id, ao3WorkID: 500, chapterCount: 9, previousChapterCount: 6, detectedAt: t0
            )
            source.insert(fresh)
            let again = try root(try contents(works: [theirs], events: [sighted, fresh]))
            _ = try KudosBackupService.restore(try reload(again), into: dest, defaults: try defaults())
            let after = try dest.fetch(FetchDescriptor<ChapterUpdateEvent>())
            #expect(after.count == 2)
            #expect(after.allSatisfy { $0.workID == ours.id })
        }

        @Test func replaceLibraryNeverDeletesAnEventWhateverTheArchiveCarries() throws {
            let context = try makeContext()
            let work = SavedWork(title: "W", author: "A")
            context.insert(work)
            let keep = ChapterUpdateEvent(workID: work.id, chapterCount: 5, previousChapterCount: 4, detectedAt: t0)
            let extra = ChapterUpdateEvent(workID: work.id, chapterCount: 8, previousChapterCount: 5, detectedAt: t0)
            context.insert(keep)
            context.insert(extra)
            try context.save()

            let withoutArray = try root(try contents(works: [work]))
            _ = try KudosBackupService.restore(
                try reload(withoutArray), into: context, defaults: try defaults(), mode: .replaceLibrary
            )
            #expect(try context.fetch(FetchDescriptor<ChapterUpdateEvent>()).count == 2)

            let withArray = try root(try contents(works: [work], events: [keep]))
            _ = try KudosBackupService.restore(
                try reload(withArray), into: context, defaults: try defaults(), mode: .replaceLibrary
            )
            let left = try context.fetch(FetchDescriptor<ChapterUpdateEvent>())
            // Hiding is display-only: sync never erases, so the extra event stays.
            #expect(Set(left.map(\.id)) == [keep.id, extra.id])
        }

        // MARK: review fixes

        @Test func damagedEventsAndSittingsAreRefusedOnRestoreAndFiguresStillWork() throws {
            let source = try makeContext()
            let work = SavedWork(title: "W", author: "A")
            source.insert(work)
            let good = ChapterUpdateEvent(workID: work.id, chapterCount: 5, previousChapterCount: 4, detectedAt: t0)
            let timed = timedSession(workID: work.id)
            source.insert(good)
            source.insert(timed)
            try source.save()
            var json = try root(try contents(works: [work], sessions: [timed], events: [good]))
            var events = try #require(json["chapterUpdateEvents"] as? [[String: Any]])
            var bad = events[0]
            bad["id"] = UUID().uuidString
            bad["previousChapterCount"] = Int.min
            bad["chapterCount"] = 1
            var huge = events[0]
            huge["id"] = UUID().uuidString
            huge["previousChapterCount"] = 2
            huge["chapterCount"] = Int.max
            events.append(contentsOf: [bad, huge])
            json["chapterUpdateEvents"] = events
            var sessions = try #require(json["readingSessions"] as? [[String: Any]])
            sessions[0]["chapterWordsJSON"] = "{\"1\":9223372036854775807,\"2\":1}"
            sessions[0]["skimmedChaptersJSON"] = "[1,2]"
            sessions[0]["highestStoryChapter"] = Int.max
            json["readingSessions"] = sessions

            let dest = try makeContext()
            _ = try KudosBackupService.restore(try reload(json), into: dest, defaults: try defaults())
            let restoredEvents = try dest.fetch(FetchDescriptor<ChapterUpdateEvent>())
            #expect(restoredEvents.map(\.id) == [good.id])
            let row = try #require(try dest.fetch(FetchDescriptor<ReadingSession>()).first)
            // The out-of-range words are refused (a fresh row keeps none), so no sum overflows.
            #expect(row.chapterWords.isEmpty)
            #expect(row.chapterSeconds == [3: 120.5, 4: 80])
            #expect(row.highestStoryChapter == nil)
            _ = InsightsProvenance.chapterTiming(sessions: [row])
            _ = InsightsProvenance.newChapters(events: restoredEvents, sessions: [row])
        }

        @Test func theHighestChapterRoundTripsAndAMergeFillsAMissingPostingDay() throws {
            let source = try makeContext()
            let work = SavedWork(title: "W", author: "A")
            source.insert(work)
            let timed = timedSession(workID: work.id)
            timed.highestStoryChapter = 7
            source.insert(timed)
            let dated = ChapterUpdateEvent(
                workID: work.id, chapterCount: 5, previousChapterCount: 4,
                detectedAt: t0.addingTimeInterval(3_600), postedDate: "2026-11-09"
            )
            source.insert(dated)
            try source.save()
            let archive = try root(try contents(works: [work], sessions: [timed], events: [dated]))

            let dest = try makeContext()
            let sameWork = SavedWork(id: work.id, title: "W", author: "A")
            dest.insert(sameWork)
            // This device saw the same chapters earlier but without the posting day.
            let undated = ChapterUpdateEvent(
                workID: work.id, chapterCount: 5, previousChapterCount: 4, detectedAt: t0
            )
            dest.insert(undated)
            try dest.save()
            _ = try KudosBackupService.restore(try reload(archive), into: dest, defaults: try defaults())
            #expect(undated.detectedAt == t0)
            #expect(undated.postedDate == "2026-11-09")
            let row = try #require(try dest.fetch(FetchDescriptor<ReadingSession>()).first)
            #expect(row.highestStoryChapter == 7)
        }

        // MARK: review 2

        @Test func replaceNeverClearsAMemberTheArchiveRecordOmits() throws {
            let context = try makeContext()
            let work = recordedWork()
            work.ageDaysAtSave = 30
            context.insert(work)
            try context.save()
            var json = try root(try contents(works: [work]))
            var works = try #require(json["works"] as? [[String: Any]])
            // An earlier current archive: the snapshot without its later-filled age, a bookmark
            // time without its privacy flag.
            works[0].removeValue(forKey: "ageDaysAtSave")
            works[0].removeValue(forKey: "fandomWorksAtSave")
            works[0].removeValue(forKey: "bookmarkIsPrivate")
            works[0]["bookmarkedAt"] = "2023-11-15T00:00:00Z"
            json["works"] = works
            _ = try KudosBackupService.restore(
                try reload(json), into: context, defaults: try defaults(), mode: .replaceLibrary
            )
            #expect(work.ageDaysAtSave == 30)
            #expect(work.fandomWorksAtSave == 9_000)
            #expect(work.bookmarkIsPrivate)
        }

        private func eventContents(
            workID: UUID, previous: Int, count: Int, detected: Date, day: String = "", rating: String = ""
        ) throws -> [String: Any] {
            let source = try makeContext()
            let work = SavedWork(id: workID, title: "W", author: "A")
            source.insert(work)
            let event = ChapterUpdateEvent(
                workID: workID, chapterCount: count, previousChapterCount: previous,
                detectedAt: detected, postedDate: day, rating: rating
            )
            source.insert(event)
            try source.save()
            return try root(try contents(works: [work], events: [event]))
        }

        @Test func eventMergeIsOrderIndependentAndKeepsEveryRangeAndAdultEvidence() throws {
            let workID = UUID()
            let narrow = try eventContents(workID: workID, previous: 5, count: 6, detected: t0)
            let wide = try eventContents(
                workID: workID, previous: 3, count: 6, detected: t0.addingTimeInterval(60),
                day: "2023-11-09", rating: "Explicit"
            )
            for order in [[narrow, wide], [wide, narrow]] {
                let dest = try makeContext()
                for archive in order {
                    _ = try KudosBackupService.restore(try reload(archive), into: dest, defaults: try defaults())
                }
                let events = try dest.fetch(FetchDescriptor<ChapterUpdateEvent>())
                #expect(events.count == 2)
                #expect(Set(events.map(\.previousChapterCount)) == [3, 5])
                let figure = InsightsProvenance.newChapters(events: events, sessions: [])
                #expect(figure.entries.map(\.chapter) == [4, 5, 6])
                let locked = HomeReadingStats.insightsScope(.main, from: [], hideMature: true, revealed: false)
                #expect(locked.events(events, in: dest).isEmpty)
            }
        }

        @Test func sameRangeObservationsMergeToTheEarliestDayAndTheAdultRating() throws {
            let workID = UUID()
            let early = try eventContents(
                workID: workID, previous: 3, count: 6, detected: t0, day: "2023-11-09", rating: "Explicit"
            )
            let late = try eventContents(
                workID: workID, previous: 3, count: 6, detected: t0.addingTimeInterval(86_400), day: "2023-11-12"
            )
            for order in [[early, late], [late, early]] {
                let dest = try makeContext()
                for archive in order {
                    _ = try KudosBackupService.restore(try reload(archive), into: dest, defaults: try defaults())
                }
                let events = try dest.fetch(FetchDescriptor<ChapterUpdateEvent>())
                #expect(events.count == 1)
                #expect(events[0].detectedAt == t0)
                #expect(events[0].postedDate == "2023-11-09")
                #expect(events[0].rating == "Explicit")
            }
        }

        @Test func aNewerSignedSoftDeleteIsAdoptedAndTheRecoverableWorkKeepsItsVisibleEvents() throws {
            let dest = try makeContext()
            let held = SavedWork(title: "Held", author: "A", sourceURL: "https://archiveofourown.org/works/920")
            held.ao3WorkID = 920
            dest.insert(held)
            let kept = ChapterUpdateEvent(
                workID: held.id, ao3WorkID: 920, chapterCount: 5, previousChapterCount: 4, detectedAt: t0
            )
            dest.insert(kept)
            PreservedWorkService.softDelete(held, in: dest)
            try dest.save()
            let localTombstone = try #require(try dest.fetch(FetchDescriptor<SyncTombstone>()).first)
            let localStamp = localTombstone.lastModifiedAt

            // The other device soft-deletes the same work later, and its (unsigned) reason field
            // claims a permanent delete.
            let source = try makeContext()
            let theirs = SavedWork(id: held.id, title: "Held", author: "A", sourceURL: "https://archiveofourown.org/works/920")
            theirs.ao3WorkID = 920
            source.insert(theirs)
            PreservedWorkService.softDelete(theirs, in: source)
            let forged = try #require(try source.fetch(FetchDescriptor<SyncTombstone>()).first)
            forged.deletionReason = "workPermanentlyDeleted"
            forged.lastModifiedAt = localStamp.addingTimeInterval(3_600)
            let archive = try KudosBackupService.makeContents(
                works: [theirs], bookmarks: [], fonts: [], readingQueues: [],
                tombstones: [forged], defaults: try defaults()
            )
            _ = try KudosBackupService.restore(archive, into: dest, defaults: try defaults())

            // The newer tombstone was adopted, the work row is still there in Recently Deleted,
            // and the event is stored and visible.
            #expect(try dest.fetch(FetchDescriptor<SyncTombstone>()).contains { $0.lastModifiedAt > localStamp })
            let row = try #require(try fetchWorks(dest).first { $0.id == held.id })
            #expect(row.isPendingDeletion)
            let stored = try dest.fetch(FetchDescriptor<ChapterUpdateEvent>())
            #expect(stored.map(\.id) == [kept.id])
            #expect(ChapterUpdateRecorder.visible(stored, in: dest).count == 1)

            // Restore from Recently Deleted: the history is still there.
            PreservedWorkService.restore(row, in: dest)
            #expect(ChapterUpdateRecorder.visible(try dest.fetch(FetchDescriptor<ChapterUpdateEvent>()), in: dest).count == 1)
        }

        @Test func aStaleArchiveEventOfAGoneWorkStaysInTheStoreHiddenButIsStillExported() throws {
            let source = try makeContext()
            let theirs = SavedWork(title: "Gone", author: "A", sourceURL: "https://archiveofourown.org/works/900")
            theirs.ao3WorkID = 900
            source.insert(theirs)
            let event = ChapterUpdateEvent(
                workID: theirs.id, ao3WorkID: 900, chapterCount: 5, previousChapterCount: 4, detectedAt: t0
            )
            source.insert(event)
            try source.save()
            let stale = try root(try contents(works: [theirs], events: [event]))

            let dest = try makeContext()
            let ours = SavedWork(title: "Gone", author: "A", sourceURL: "https://archiveofourown.org/works/900")
            ours.ao3WorkID = 900
            dest.insert(ours)
            try dest.save()
            WorkLifecycle.hardDelete(ours, in: dest)
            _ = try KudosBackupService.restore(try reload(stale), into: dest, defaults: try defaults())
            let stored = try dest.fetch(FetchDescriptor<ChapterUpdateEvent>())
            #expect(stored.count == 1)
            #expect(try fetchWorks(dest).isEmpty)
            #expect(ChapterUpdateRecorder.visible(stored, in: dest).isEmpty)
            let tombstones = try dest.fetch(FetchDescriptor<SyncTombstone>())
            let exported = try KudosBackupService.makeContents(
                works: [], bookmarks: [], fonts: [], readingQueues: [],
                chapterUpdateEvents: stored, tombstones: tombstones, defaults: try defaults()
            )
            // Hiding is display-only: the archive still carries the event.
            #expect(exported.manifest.chapterUpdateEvents?.count == 1)
            let locked = HomeReadingStats.insightsScope(.main, from: [], hideMature: false, revealed: false)
            #expect(locked.events(stored, in: dest).isEmpty)
        }

        @Test func aNewerSoftDeleteDoesNotUnhideAnEarlierPermanentDelete() {
            let oldCopy = UUID()
            let event = ChapterUpdateEvent(
                workID: oldCopy, ao3WorkID: 930, chapterCount: 5, previousChapterCount: 4, detectedAt: t0
            )
            // Monday: the first copy is deleted. Tuesday: a re-saved copy (new id, same AO3 id) is
            // soft deleted. Whatever order they arrive in, the old copy's event stays hidden.
            let permanent = (recordID: oldCopy, ao3WorkID: Optional(930), modifiedAt: t0.addingTimeInterval(86_400))
            let soft = (recordID: UUID(), ao3WorkID: Optional(930), modifiedAt: t0.addingTimeInterval(172_800))
            for order in [[permanent, soft], [soft, permanent]] {
                #expect(ChapterUpdateRecorder.visible([event], localWorkIDs: [], workTombstones: order).isEmpty)
            }
            // A sighting after the delete (a new copy's own event) is not covered by the old one.
            let later = ChapterUpdateEvent(
                workID: UUID(), ao3WorkID: 930, chapterCount: 3, previousChapterCount: 2,
                detectedAt: t0.addingTimeInterval(259_200)
            )
            #expect(ChapterUpdateRecorder.visible([later], localWorkIDs: [], workTombstones: [permanent, soft]).count == 1)
        }

        // MARK: review 4

        @Test func backupsCarryEveryStoredEventEvenWhenATombstoneHidesIt() throws {
            let orphan = ChapterUpdateEvent(
                workID: UUID(), ao3WorkID: 940, chapterCount: 5, previousChapterCount: 4, detectedAt: t0
            )
            let tombstone = SyncTombstone(
                recordID: orphan.workID, recordType: .savedWork, ao3WorkID: 940,
                createdAt: t0.addingTimeInterval(60)
            )
            let exported = try KudosBackupService.makeContents(
                works: [], bookmarks: [], fonts: [], readingQueues: [],
                chapterUpdateEvents: [orphan], tombstones: [tombstone], defaults: try defaults()
            )
            #expect(exported.manifest.chapterUpdateEvents?.map(\.id) == [orphan.id])
        }

        @Test func replaceNeverDeletesEventsOfAWorkThatExistsHere() throws {
            let dest = try makeContext()
            let held = SavedWork(title: "Held", author: "A", sourceURL: "https://archiveofourown.org/works/941")
            held.ao3WorkID = 941
            dest.insert(held)
            let mine = ChapterUpdateEvent(
                workID: held.id, ao3WorkID: 941, chapterCount: 5, previousChapterCount: 4, detectedAt: t0
            )
            dest.insert(mine)
            PreservedWorkService.softDelete(held, in: dest)
            try dest.save()
            // The archive carries an unrelated event only.
            let other = try makeContext()
            let unrelated = SavedWork(title: "Other", author: "A")
            other.insert(unrelated)
            let theirEvent = ChapterUpdateEvent(workID: unrelated.id, chapterCount: 3, previousChapterCount: 2, detectedAt: t0)
            other.insert(theirEvent)
            try other.save()
            let archive = try reload(try root(try contents(works: [unrelated], events: [theirEvent])))
            _ = try KudosBackupService.restore(archive, into: dest, defaults: try defaults(), mode: .replaceLibrary)
            let ids = Set(try dest.fetch(FetchDescriptor<ChapterUpdateEvent>()).map(\.id))
            #expect(ids.contains(mine.id))
            #expect(ids.contains(theirEvent.id))
        }

        @Test func aWorkRestoredUnderANewLocalIDStillOwnsItsEarlierHistory() throws {
            let dest = try makeContext()
            let oldID = UUID()
            let old = ChapterUpdateEvent(
                workID: oldID, ao3WorkID: 900, chapterCount: 5, previousChapterCount: 4, detectedAt: t0
            )
            dest.insert(old)
            dest.insert(SyncTombstone(
                recordID: oldID, recordType: .savedWork, ao3WorkID: 900, createdAt: t0.addingTimeInterval(60)
            ))
            try dest.save()
            // A newer archive brings the work back under another UUID, without the old event.
            let source = try makeContext()
            let back = SavedWork(title: "Back", author: "A", sourceURL: "https://archiveofourown.org/works/900")
            back.ao3WorkID = 900
            back.lastModifiedAt = t0.addingTimeInterval(86_400)
            source.insert(back)
            try source.save()
            _ = try KudosBackupService.restore(
                try reload(try root(try contents(works: [back]))), into: dest, defaults: try defaults()
            )
            let restored = try #require(try fetchWorks(dest).first { $0.ao3WorkID == 900 })
            let stored = try dest.fetch(FetchDescriptor<ChapterUpdateEvent>())
            #expect(ChapterUpdateRecorder.visible(stored, in: dest).count == 1)
            #expect(stored.first?.workID == restored.id)
        }
    }
}
