import Foundation
import SwiftData
import Testing
@testable import Kudos

/// T-536a backup contract: every D7 to D9 field is additive on v8, absent when unrecorded, and an
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
                ReadingSession.self, ReadingFavorite.self, FandomReadWatermark.self
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
            sessions: [ReadingSession] = []
        ) throws -> KudosBackupContents {
            try KudosBackupService.makeContents(
                works: works, bookmarks: [], fonts: [], readingQueues: [],
                readingSessions: sessions, defaults: try defaults()
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
            return work
        }

        private func fetchWorks(_ context: ModelContext) throws -> [SavedWork] {
            try context.fetch(FetchDescriptor<SavedWork>())
        }

        // MARK: works (D8, D9)

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
                "statsSavedAt", "ageDaysAtSave", "fandomWorksAtSave"
            ] {
                #expect(untouchedJSON[key] == nil, "an unrecorded work must not export \(key)")
                #expect(recordedJSON[key] != nil, "a recorded work must export \(key)")
            }
            #expect(json["version"] as? Int == 8)

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
            let plain = try #require(try fetchWorks(dest).first { $0.id == untouched.id })
            #expect(plain.importSourceRaw == nil)
            #expect(plain.statsSavedAt == nil)
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
                "statsSavedAt", "ageDaysAtSave", "fandomWorksAtSave"
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
            }
        }

        @Test func mergeKeepsFirstFactsAndReplaceAdoptsTheArchives() throws {
            let id = UUID()
            // The device holds a source and a stats snapshot.
            let local = try makeContext()
            let here = SavedWork(id: id, title: "Same", author: "A")
            here.recordImportSource(.search, at: t0)
            here.recordStatsAtSave(WorkStatsAtSave(kudos: 50, hits: 500, bookmarks: nil, fandomWorks: nil), at: t0)
            local.insert(here)
            try local.save()

            // The other device recorded a different source and stats.
            let other = try makeContext()
            let there = SavedWork(id: id, title: "Same", author: "A")
            there.recordImportSource(.fandom, at: t0.addingTimeInterval(-9))
            there.recordStatsAtSave(WorkStatsAtSave(kudos: 3, hits: 30, bookmarks: nil, fandomWorks: nil), at: t0.addingTimeInterval(-9))
            other.insert(there)
            try other.save()
            let archive = try root(try contents(works: [there]))

            _ = try KudosBackupService.restore(try reload(archive), into: local, defaults: try defaults())
            #expect(here.importSource == .search)
            #expect(here.kudosAtSave == 50)

            // Replace Library makes the device look like the archive.
            _ = try KudosBackupService.restore(
                try reload(archive), into: local, defaults: try defaults(), mode: .replaceLibrary
            )
            #expect(here.importSource == .fandom)
            #expect(here.kudosAtSave == 3)
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

        // MARK: review fixes

        @Test func aLegacyRestoredSittingGainsItsTimingFromALaterMergeOrReconcile() throws {
            let source = try makeContext()
            let work = SavedWork(title: "W", author: "A")
            source.insert(work)
            let timed = timedSession(workID: work.id)
            source.insert(timed)
            try source.save()
            let current = try root(try contents(works: [work], sessions: [timed]))
            var legacy = current
            var sessions = try #require(legacy["readingSessions"] as? [[String: Any]])
            for key in [
                "chapterSecondsJSON", "chapterWordsJSON", "skimmedChaptersJSON", "skimmedStoryChaptersJSON",
                "endedAtChapterEnd", "peekedAtEnding"
            ] {
                sessions[0].removeValue(forKey: key)
            }
            legacy["readingSessions"] = sessions
            for mode in [BackupImportMode.merge, .reconcile] {
                let dest = try makeContext()
                _ = try KudosBackupService.restore(try reload(legacy), into: dest, defaults: try defaults())
                let row = try #require(try dest.fetch(FetchDescriptor<ReadingSession>()).first)
                #expect(row.chapterSecondsJSON == nil)
                // The local sitting is strictly newer than the archive's, so Reconcile rejects the
                // incoming row as older: only the missing timing may come in.
                let newer = row.lastModifiedAt.addingTimeInterval(3_600)
                row.lastModifiedAt = newer
                row.durationSeconds = 999
                _ = try KudosBackupService.restore(
                    try reload(current), into: dest, defaults: try defaults(), mode: mode
                )
                #expect(row.chapterSeconds == [3: 120.5, 4: 80], "mode \(mode)")
                #expect(row.skimmedChapters == [4], "mode \(mode)")
                #expect(row.endedAtChapterEnd == true, "mode \(mode)")
                #expect(row.durationSeconds == 999, "mode \(mode)")
                #expect(row.lastModifiedAt == newer, "mode \(mode)")
                // Timing the row already has is never overwritten by the fill.
                row.chapterSeconds = [9: 1]
                _ = try KudosBackupService.restore(
                    try reload(current), into: dest, defaults: try defaults(), mode: mode
                )
                #expect(row.chapterSeconds == [9: 1], "mode \(mode)")
                #expect(row.durationSeconds == 999, "mode \(mode)")
            }
        }

        @Test func damagedSittingValuesAreRefusedOnRestoreAndFiguresStillWork() throws {
            let source = try makeContext()
            let work = SavedWork(title: "W", author: "A")
            source.insert(work)
            let timed = timedSession(workID: work.id)
            source.insert(timed)
            try source.save()
            var json = try root(try contents(works: [work], sessions: [timed]))
            var sessions = try #require(json["readingSessions"] as? [[String: Any]])
            sessions[0]["chapterWordsJSON"] = "{\"1\":9223372036854775807,\"2\":1}"
            sessions[0]["skimmedChaptersJSON"] = "[1,2]"
            json["readingSessions"] = sessions

            let dest = try makeContext()
            _ = try KudosBackupService.restore(try reload(json), into: dest, defaults: try defaults())
            let row = try #require(try dest.fetch(FetchDescriptor<ReadingSession>()).first)
            // The out-of-range words are refused (a fresh row keeps none), so no sum overflows.
            #expect(row.chapterWords.isEmpty)
            #expect(row.chapterSeconds == [3: 120.5, 4: 80])
            _ = InsightsProvenance.chapterTiming(sessions: [row])
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
            // An earlier current archive: the snapshot without its later-filled age.
            works[0].removeValue(forKey: "ageDaysAtSave")
            works[0].removeValue(forKey: "fandomWorksAtSave")
            json["works"] = works
            _ = try KudosBackupService.restore(
                try reload(json), into: context, defaults: try defaults(), mode: .replaceLibrary
            )
            #expect(work.ageDaysAtSave == 30)
            #expect(work.fandomWorksAtSave == 9_000)
        }

    }
}
