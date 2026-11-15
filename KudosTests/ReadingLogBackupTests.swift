import Foundation
import SwiftData
import Testing
@testable import Kudos

extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct ReadingLogBackupTests {
    private func schema() -> Schema {
        Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self, ReadingAnnotation.self,
            ReadingSession.self, ReadingFavorite.self, FandomReadWatermark.self
        ])
    }

    private func context(_ schema: Schema) throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
    }

    private func testDefaults() throws -> UserDefaults {
        let name = "ReadingLogBackupTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultInsightsFieldsAreAbsentFromManifest() throws {
        let schema = schema()
        let source = try context(schema)
        let work = SavedWork(title: "Default", author: "Writer")
        let session = ReadingSession(
            workID: work.id, startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 1_020), durationSeconds: 20
        )
        source.insert(work)
        source.insert(session)
        try source.save()
        let contents = try KudosBackupService.makeContents(
            works: [work], bookmarks: [], fonts: [], readingQueues: [],
            readingSessions: [session], defaults: try testDefaults()
        )
        let root = try #require(
            JSONSerialization.jsonObject(with: contents.manifestData()) as? [String: Any]
        )
        let archivedWork = try #require((root["works"] as? [[String: Any]])?.first)
        let archivedSession = try #require((root["readingSessions"] as? [[String: Any]])?.first)
        for key in ["readingStatusRaw", "statusChangedAt", "stoppedAt", "stopReasonRaw",
                    "stopTag", "stopNote", "stackThreshold", "stackBaselineChapterCount",
                    "statusWasRecorded"] {
            #expect(archivedWork[key] == nil)
        }
        for key in ["fandoms", "relationships", "characters", "freeformTags",
                    "rating", "warnings", "categories", "authorAccounts", "language",
                    "isCompleteAtVisit", "metadataSnapshotRecorded", "ao3SeriesID",
                    "seriesPosition", "publishedYear"] {
            #expect(archivedSession[key] == nil)
        }
        // A real WIP visit is false, while an old row with no snapshot is unknown.
        session.snapshot(from: work)
        let recorded = try KudosBackupService.makeContents(
            works: [work], bookmarks: [], fonts: [], readingQueues: [],
            readingSessions: [session], defaults: try testDefaults()
        )
        let recordedRoot = try #require(
            JSONSerialization.jsonObject(with: recorded.manifestData()) as? [String: Any]
        )
        let recordedSession = try #require((recordedRoot["readingSessions"] as? [[String: Any]])?.first)
        #expect(recordedSession["metadataSnapshotRecorded"] as? Bool == true)
        #expect(recordedSession["isCompleteAtVisit"] as? Bool == false)
        #expect(recordedSession["fandoms"] as? [String] == [])
        #expect(recordedSession["seriesPosition"] as? Int == 0)
        work.readingStatusRaw = "stacking"
        let stacking = try KudosBackupService.makeContents(
            works: [work], bookmarks: [], fonts: [], readingQueues: [],
            readingSessions: [session], defaults: try testDefaults()
        )
        let stackingRoot = try #require(
            JSONSerialization.jsonObject(with: stacking.manifestData()) as? [String: Any]
        )
        let stackingWork = try #require((stackingRoot["works"] as? [[String: Any]])?.first)
        #expect(stackingWork["stackThreshold"] as? Int == 3)
    }

    @Test func sessionsFavoritesAndWatermarksRoundTrip() throws {
        let schema = schema()
        let source = try context(schema)
        let work = SavedWork(title: "Logged Work", author: "Archivist")
        work.keepInProgressOverride = true
        work.readingStatusRaw = "stopped"
        work.statusChangedAt = Date(timeIntervalSince1970: 900)
        work.stoppedAt = Date(timeIntervalSince1970: 950)
        work.stopReasonRaw = "tagDealbreaker"
        work.stopTag = "Tag"
        work.stopNote = "Reason"
        work.stackThreshold = 5
        work.isSaved = true
        source.insert(work)
        let session = ReadingSession(
            workID: work.id,
            ao3WorkID: 42,
            sourceURL: "https://archiveofourown.org/works/42",
            workTitle: "Logged Work",
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 1_200),
            durationSeconds: 200,
            tzOffsetSeconds: -18_000,
            startProgress: 0.2,
            startSpineIndex: 1,
            modeRaw: "listen",
            playbackRate: 1.4,
            activeSeconds: 140,
            deviceID: "install-1",
            rulesVersion: 1,
            lastSpineIndex: 3,
            chapterTitle: "Chapter 4",
            endingProgress: 0.55,
            wordCount: 80_000,
            chapterCountAtVisit: 10,
            didFinish: true,
            lastModifiedAt: Date(timeIntervalSince1970: 1_200)
        )
        session.fandoms = ["Fandom"]
        session.relationships = ["A/B"]
        session.characters = ["A"]
        session.freeformTags = ["Tag"]
        session.rating = "Mature"
        session.warnings = ["Warning"]
        session.categories = ["M/M"]
        session.authorAccounts = ["writer"]
        session.language = "English"
        session.isCompleteAtVisit = true
        session.metadataSnapshotRecorded = true
        session.ao3SeriesID = 99
        session.seriesPosition = 2
        session.publishedYear = 2020
        let favorite = ReadingFavorite(
            kind: .fandom,
            targetKey: "The Untamed (TV)",
            displayName: "The Untamed (TV)",
            createdAt: Date(timeIntervalSince1970: 500)
        )
        let watermark = FandomReadWatermark(
            fandomName: "The Untamed (TV)",
            lastVisitedAt: Date(timeIntervalSince1970: 800),
            newestWorkIDSeen: 42,
            newestWorkTitleSeen: "Logged Work",
            lastModifiedAt: Date(timeIntervalSince1970: 800)
        )
        source.insert(session)
        source.insert(favorite)
        source.insert(watermark)
        try source.save()

        let contents = try KudosBackupService.makeContents(
            works: [work],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            readingSessions: [session],
            readingFavorites: [favorite],
            fandomReadWatermarks: [watermark],
            defaults: try testDefaults()
        )
        #expect(contents.manifest.version == 8)
        #expect(contents.manifest.readingSessions.count == 1)
        #expect(contents.manifest.readingFavorites.count == 1)
        #expect(contents.manifest.fandomReadWatermarks.count == 1)
        #expect(contents.manifest.works.first?.keepInProgressOverride == true)

        let target = try context(schema)
        _ = try KudosBackupService.restore(contents, into: target, defaults: try testDefaults())

        let restoredWork = try #require(try target.fetch(FetchDescriptor<SavedWork>()).first)
        #expect(restoredWork.keepInProgressOverride)
        #expect(restoredWork.readingStatusRaw == "stopped")
        #expect(restoredWork.statusChangedAt == Date(timeIntervalSince1970: 900))
        #expect(restoredWork.stoppedAt == Date(timeIntervalSince1970: 950))
        #expect(restoredWork.stopReasonRaw == "tagDealbreaker")
        #expect(restoredWork.stopTag == "Tag")
        #expect(restoredWork.stopNote == "Reason")
        #expect(restoredWork.stackThreshold == 5)

        let restoredSession = try #require(try target.fetch(FetchDescriptor<ReadingSession>()).first)
        #expect(restoredSession.id == session.id)
        #expect(restoredSession.workID == work.id)
        #expect(restoredSession.durationSeconds == 200)
        #expect(restoredSession.wordCount == 80_000)
        #expect(restoredSession.didFinish)
        #expect(restoredSession.chapterTitle == "Chapter 4")
        #expect(restoredSession.tzOffsetSeconds == -18_000)
        #expect(restoredSession.startProgress == 0.2)
        #expect(restoredSession.startSpineIndex == 1)
        #expect(restoredSession.mode == .listen)
        #expect(restoredSession.playbackRate == 1.4)
        #expect(restoredSession.activeSeconds == 140)
        #expect(restoredSession.deviceID == "install-1")
        #expect(restoredSession.rulesVersion == 1)
        #expect(restoredSession.fandoms == ["Fandom"])
        #expect(restoredSession.relationships == ["A/B"])
        #expect(restoredSession.characters == ["A"])
        #expect(restoredSession.freeformTags == ["Tag"])
        #expect(restoredSession.rating == "Mature")
        #expect(restoredSession.warnings == ["Warning"])
        #expect(restoredSession.categories == ["M/M"])
        #expect(restoredSession.authorAccounts == ["writer"])
        #expect(restoredSession.language == "English")
        #expect(restoredSession.isCompleteAtVisit)
        #expect(restoredSession.ao3SeriesID == 99)
        #expect(restoredSession.seriesPosition == 2)
        #expect(restoredSession.publishedYear == 2020)

        // Reconcile must update an existing row, including every new fact.
        restoredSession.tzOffsetSeconds = nil
        restoredSession.startProgress = nil
        restoredSession.startSpineIndex = nil
        restoredSession.modeRaw = "read"
        restoredSession.playbackRate = nil
        restoredSession.activeSeconds = nil
        restoredSession.deviceID = "old-install"
        restoredSession.rulesVersion = 0
        restoredSession.lastModifiedAt = Date(timeIntervalSince1970: 1_100)
        try target.save()
        _ = try KudosBackupService.restore(contents, into: target, defaults: try testDefaults())
        let updated = try #require(try target.fetch(FetchDescriptor<ReadingSession>()).first)
        #expect(updated.tzOffsetSeconds == -18_000)
        #expect(updated.startProgress == 0.2)
        #expect(updated.startSpineIndex == 1)
        #expect(updated.mode == .listen)
        #expect(updated.playbackRate == 1.4)
        #expect(updated.activeSeconds == 140)
        #expect(updated.deviceID == "install-1")
        #expect(updated.rulesVersion == 1)

        var object = try #require(
            JSONSerialization.jsonObject(with: contents.manifestData()) as? [String: Any]
        )
        var archived = try #require(object["readingSessions"] as? [[String: Any]])
        for key in ["tzOffsetSeconds", "startProgress", "startSpineIndex", "modeRaw",
                    "playbackRate", "activeSeconds", "deviceID", "rulesVersion",
                    "fandoms", "relationships", "characters", "freeformTags", "rating",
                    "warnings", "categories", "authorAccounts", "language", "isCompleteAtVisit",
                    "metadataSnapshotRecorded", "ao3SeriesID", "seriesPosition", "publishedYear"] {
            archived[0].removeValue(forKey: key)
        }
        object["readingSessions"] = archived
        var legacyWorks = try #require(object["works"] as? [[String: Any]])
        for key in ["readingStatusRaw", "statusChangedAt", "stoppedAt", "stopReasonRaw",
                    "stopTag", "stopNote", "stackThreshold", "stackBaselineChapterCount",
                    "statusWasRecorded"] {
            legacyWorks[0].removeValue(forKey: key)
        }
        object["works"] = legacyWorks
        let legacy = try KudosBackupContents.decodeManifest(
            JSONSerialization.data(withJSONObject: object)
        )
        // An Android/old-build archive may have the same timestamp but no new keys.
        _ = try KudosBackupService.restore(
            KudosBackupContents(manifest: legacy), into: target, defaults: try testDefaults()
        )
        let preserved = try #require(try target.fetch(FetchDescriptor<ReadingSession>()).first)
        #expect(preserved.tzOffsetSeconds == -18_000)
        #expect(preserved.fandoms == ["Fandom"])
        #expect(preserved.authorAccounts == ["writer"])
        #expect(preserved.freeformTags == ["Tag"])
        #expect(restoredWork.readingStatusRaw == "stopped")
        #expect(restoredWork.stopReasonRaw == "tagDealbreaker")
        #expect(restoredWork.stackThreshold == 5)
        #expect(preserved.startProgress == 0.2)
        #expect(preserved.startSpineIndex == 1)
        #expect(preserved.mode == .listen)
        #expect(preserved.playbackRate == 1.4)
        #expect(preserved.activeSeconds == 140)
        #expect(preserved.deviceID == "install-1")
        #expect(preserved.rulesVersion == 1)
        let legacyTarget = try context(schema)
        _ = try KudosBackupService.restore(
            KudosBackupContents(manifest: legacy), into: legacyTarget, defaults: try testDefaults()
        )
        let old = try #require(try legacyTarget.fetch(FetchDescriptor<ReadingSession>()).first)
        #expect(old.tzOffsetSeconds == nil)
        #expect(old.startProgress == nil)
        #expect(old.startSpineIndex == nil)
        #expect(old.playbackRate == nil)
        #expect(old.activeSeconds == nil)
        #expect(old.mode == .read)
        #expect(old.deviceID.isEmpty)
        #expect(old.rulesVersion == 0)

        let restoredFavorite = try #require(try target.fetch(FetchDescriptor<ReadingFavorite>()).first)
        #expect(restoredFavorite.kind == .fandom)
        #expect(restoredFavorite.targetKey == "The Untamed (TV)")

        let restoredWatermark = try #require(
            try target.fetch(FetchDescriptor<FandomReadWatermark>()).first
        )
        #expect(restoredWatermark.fandomName == "The Untamed (TV)")
        #expect(restoredWatermark.newestWorkIDSeen == 42)
    }

    @Test func recordedDefaultsReplaceOlderValuesOnExistingRows() throws {
        let schema = schema()
        let source = try context(schema)
        let work = SavedWork(title: "WIP", author: "Writer")
        work.setReadingStatus(nil)
        work.lastModifiedAt = Date(timeIntervalSince1970: 2_000)
        let session = ReadingSession(
            workID: work.id, startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 1_100), durationSeconds: 100,
            lastModifiedAt: Date(timeIntervalSince1970: 2_000)
        )
        session.metadataSnapshotRecorded = true
        source.insert(work)
        source.insert(session)
        try source.save()
        let contents = try KudosBackupService.makeContents(
            works: [work], bookmarks: [], fonts: [], readingQueues: [],
            readingSessions: [session], defaults: try testDefaults()
        )
        let target = try context(schema)
        let oldWork = SavedWork(title: "WIP", author: "Writer")
        oldWork.id = work.id
        oldWork.readingStatusRaw = "stopped"
        oldWork.statusChangedAt = Date(timeIntervalSince1970: 900)
        oldWork.stoppedAt = Date(timeIntervalSince1970: 950)
        oldWork.stopReasonRaw = "other"
        oldWork.stackThreshold = 9
        oldWork.stackBaselineChapterCount = 8
        oldWork.lastModifiedAt = Date(timeIntervalSince1970: 1_500)
        let oldSession = ReadingSession(
            id: session.id, workID: work.id, startedAt: session.startedAt,
            endedAt: session.endedAt, durationSeconds: 100,
            lastModifiedAt: Date(timeIntervalSince1970: 1_500)
        )
        oldSession.metadataSnapshotRecorded = true
        oldSession.fandoms = ["Stale"]
        oldSession.seriesPosition = 5
        oldSession.ao3SeriesID = 77
        oldSession.publishedYear = 2020
        target.insert(oldWork)
        target.insert(oldSession)
        try target.save()
        _ = try KudosBackupService.restore(contents, into: target, defaults: try testDefaults())
        let restoredWork = try #require(try target.fetch(FetchDescriptor<SavedWork>()).first)
        let restoredSession = try #require(try target.fetch(FetchDescriptor<ReadingSession>()).first)
        #expect(restoredWork.readingStatusRaw.isEmpty)
        #expect(restoredWork.statusChangedAt == nil)
        #expect(restoredWork.stoppedAt == nil)
        #expect(restoredWork.stopReasonRaw.isEmpty)
        #expect(restoredWork.stackThreshold == 3)
        #expect(restoredWork.stackBaselineChapterCount == 0)
        #expect(restoredSession.fandoms.isEmpty)
        #expect(restoredSession.seriesPosition == 0)
        #expect(restoredSession.ao3SeriesID == nil)
        #expect(restoredSession.publishedYear == nil)
    }

    /// Renamed from `keepInProgressOverrideDecodesFalseWhenAbsent`, which
    /// asserted the defect rather than the behaviour: decoding an absent key as
    /// `false` is exactly what let a backup written before this field existed
    /// turn off a preference the reader had turned on. `Bool?` and
    /// `decodeIfPresent` keep "the archive does not say" distinct from "the
    /// archive says no" — see `OmittedFieldKeepsPreferenceTests` for the
    /// restore-side half.
    @Test func keepInProgressOverrideDecodesNilWhenAbsent() throws {
        let work = SavedWork(title: "Legacy", author: "A")
        work.keepInProgressOverride = true
        let contents = try KudosBackupService.makeContents(
            works: [work], bookmarks: [], fonts: [], readingQueues: [],
            defaults: try testDefaults()
        )
        var object = try #require(
            JSONSerialization.jsonObject(with: contents.manifestData()) as? [String: Any]
        )
        var works = try #require(object["works"] as? [[String: Any]])
        works[0].removeValue(forKey: "keepInProgressOverride")
        object["works"] = works
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let decoded = try KudosBackupContents.decodeManifest(stripped)
        #expect(decoded.works.first?.keepInProgressOverride == nil)
    }

    @Test func v7AndV8ArchivesWithoutNewKeysStillImport() throws {
        let v7 = KudosBackupManifest(
            version: 7, works: [], bookmarks: [], fonts: [],
            settings: .capture(defaults: try testDefaults())
        )
        let v7Data = try KudosBackupContents(manifest: v7).manifestData()
        var v7Object = try #require(
            JSONSerialization.jsonObject(with: v7Data) as? [String: Any]
        )
        v7Object.removeValue(forKey: "readingSessions")
        v7Object.removeValue(forKey: "readingFavorites")
        v7Object.removeValue(forKey: "fandomReadWatermarks")
        let strippedV7 = try JSONSerialization.data(withJSONObject: v7Object)
        let decodedV7 = try KudosBackupContents.decodeManifest(strippedV7)
        #expect(decodedV7.readingSessions.isEmpty)
        #expect(decodedV7.readingFavorites.isEmpty)
        #expect(decodedV7.fandomReadWatermarks.isEmpty)
        #expect(decodedV7.version == 7)

        let v8 = KudosBackupManifest(
            version: 8, works: [], bookmarks: [], fonts: [],
            settings: .capture(defaults: try testDefaults())
        )
        let v8Data = try KudosBackupContents(manifest: v8).manifestData()
        var v8Object = try #require(
            JSONSerialization.jsonObject(with: v8Data) as? [String: Any]
        )
        v8Object.removeValue(forKey: "readingSessions")
        v8Object.removeValue(forKey: "readingFavorites")
        v8Object.removeValue(forKey: "fandomReadWatermarks")
        let strippedV8 = try JSONSerialization.data(withJSONObject: v8Object)
        let decodedV8 = try KudosBackupContents.decodeManifest(strippedV8)
        #expect(decodedV8.readingSessions.isEmpty)
        #expect(decodedV8.readingFavorites.isEmpty)
        #expect(decodedV8.fandomReadWatermarks.isEmpty)
        #expect(KudosBackupManifest.currentVersion == 8)
    }

    @Test func tombstoneSuppressesResurrectionOfAnOlderArchive() throws {
        let schema = schema()
        let source = try context(schema)
        let session = ReadingSession(
            workID: UUID(),
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            durationSeconds: 100,
            lastModifiedAt: Date(timeIntervalSince1970: 200)
        )
        let favorite = ReadingFavorite(
            kind: .tag, targetKey: "Angst", displayName: "Angst",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let watermark = FandomReadWatermark(
            fandomName: "Old Fandom",
            lastVisitedAt: Date(timeIntervalSince1970: 100)
        )
        source.insert(session)
        source.insert(favorite)
        source.insert(watermark)
        try source.save()
        let contents = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [],
            readingSessions: [session],
            readingFavorites: [favorite],
            fandomReadWatermarks: [watermark],
            defaults: try testDefaults()
        )

        let target = try context(schema)
        target.insert(SyncTombstone(
            recordID: session.id, recordType: .readingSession,
            createdAt: Date(timeIntervalSince1970: 5_000)
        ))
        target.insert(SyncTombstone(
            recordID: favorite.id, recordType: .readingFavorite,
            createdAt: Date(timeIntervalSince1970: 5_000)
        ))
        target.insert(SyncTombstone(
            recordID: watermark.id, recordType: .fandomReadWatermark,
            createdAt: Date(timeIntervalSince1970: 5_000)
        ))
        try target.save()

        _ = try KudosBackupService.restore(contents, into: target, defaults: try testDefaults())
        #expect(try target.fetch(FetchDescriptor<ReadingSession>()).isEmpty)
        #expect(try target.fetch(FetchDescriptor<ReadingFavorite>()).isEmpty)
        #expect(try target.fetch(FetchDescriptor<FandomReadWatermark>()).isEmpty)
    }

    @Test func replaceOmissionMintsTombstonesAndALaterMergeDoesNotResurrect() throws {
        let schema = schema()
        let context = try context(schema)
        let keepSession = ReadingSession(
            workID: UUID(),
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            durationSeconds: 100
        )
        let dropSession = ReadingSession(
            workID: UUID(),
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            durationSeconds: 100
        )
        let dropFavorite = ReadingFavorite(kind: .author, targetKey: "route/a", displayName: "A")
        let dropWatermark = FandomReadWatermark(fandomName: "Drop Fandom")
        context.insert(keepSession)
        context.insert(dropSession)
        context.insert(dropFavorite)
        context.insert(dropWatermark)
        try context.save()
        let dropSessionID = dropSession.id
        let dropFavoriteID = dropFavorite.id
        let dropWatermarkID = dropWatermark.id

        let stale = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [],
            readingSessions: [keepSession, dropSession],
            readingFavorites: [dropFavorite],
            fandomReadWatermarks: [dropWatermark],
            defaults: try testDefaults()
        )
        let replaceSnapshot = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [],
            readingSessions: [keepSession],
            readingFavorites: [],
            fandomReadWatermarks: [],
            defaults: try testDefaults()
        )
        _ = try KudosBackupService.restore(
            replaceSnapshot, into: context, defaults: try testDefaults(), mode: .replaceLibrary
        )
        _ = try KudosBackupService.restore(
            stale, into: context, defaults: try testDefaults(), mode: .merge
        )

        let sessions = try context.fetch(FetchDescriptor<ReadingSession>())
        #expect(Set(sessions.map(\.id)) == Set([keepSession.id]))
        #expect(try context.fetch(FetchDescriptor<ReadingFavorite>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FandomReadWatermark>()).isEmpty)
        let tombs = try context.fetch(FetchDescriptor<SyncTombstone>())
        #expect(tombs.contains {
            $0.recordType == .readingSession && $0.recordID == dropSessionID && !$0.signature.isEmpty
        })
        #expect(tombs.contains {
            $0.recordType == .readingFavorite && $0.recordID == dropFavoriteID && !$0.signature.isEmpty
        })
        #expect(tombs.contains {
            $0.recordType == .fandomReadWatermark && $0.recordID == dropWatermarkID
                && !$0.signature.isEmpty
        })
    }

    @Test func addingReadingLogDidNotBumpTheSchemaVersion() {
        #expect(KudosBackupManifest.currentVersion == 8)
        #expect(KudosBackupManifest.supportedVersions.contains(8))
        #expect(!KudosBackupManifest.supportedVersions.contains(9))
    }
}
}
