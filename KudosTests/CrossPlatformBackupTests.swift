import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import Kudos

extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct CrossPlatformBackupTests {
    @Test func iosAndAndroidGoldenArchivesRestoreAndRoundTrip() throws {
        let seeded = try seedLibrary()
        defer { seeded.cleanup() }

        let plan = try KudosBackupService.makeExportPlan(
            works: seeded.works,
            bookmarks: [seeded.bookmark],
            fonts: [],
            collections: [seeded.collection],
            readingQueues: seeded.queues,
            annotations: seeded.annotations,
            savedSearches: [seeded.search],
            readingSessions: [seeded.session],
            readingFavorites: seeded.favorites,
            fandomReadWatermarks: [seeded.watermark],
            tombstones: [seeded.tombstone],
            defaults: seeded.defaults
        )
        let generatedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("kudosbackup")
        defer { try? FileManager.default.removeItem(at: generatedURL) }
        try KudosBackupService.writeArchive(plan, to: generatedURL)
        let generated = try KudosBackupContents.read(from: generatedURL)
        try assertArchive(generated, matches: generated.manifest, epub: seeded.epub)
        assertOriginals(in: generated)
        assertDeviceLocalFieldsAreAbsent(from: plan.manifestData)

        let paths = fixturePaths()
        // xcodebuild injects TEST_RUNNER_* into the test process and strips the prefix.
        // Accept either spelling so a direct env and the runner prefix both work.
        let writeGolden = ProcessInfo.processInfo.environment["KUDOS_WRITE_GOLDEN"] == "1"
            || ProcessInfo.processInfo.environment["TEST_RUNNER_KUDOS_WRITE_GOLDEN"] == "1"
        if writeGolden {
            try FileManager.default.createDirectory(
                at: paths.iosArchive.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(contentsOf: generatedURL).write(to: paths.iosArchive, options: .atomic)
            try plan.manifestData.write(to: paths.expectedValues, options: .atomic)
        }

        let expectedData = try Data(contentsOf: paths.expectedValues)
        let expected = try KudosBackupContents.decodeManifest(expectedData)
        let generatedCanonical = try canonicalManifest(plan.manifestData)
        let expectedCanonical = try canonicalManifest(expectedData)
        if generatedCanonical != expectedCanonical,
           let dir = ProcessInfo.processInfo.environment["KUDOS_GOLDEN_DIFF_DIR"] {
            try? generatedCanonical.write(
                to: URL(fileURLWithPath: dir).appendingPathComponent("ios-generated.json")
            )
            try? expectedCanonical.write(
                to: URL(fileURLWithPath: dir).appendingPathComponent("ios-expected.json")
            )
        }
        #expect(generatedCanonical == expectedCanonical)
        let iosArchive = try KudosBackupContents.read(from: paths.iosArchive)
        try assertArchive(iosArchive, matches: expected, epub: seeded.epub)
        assertOriginals(in: iosArchive)

        let androidArchive = try KudosBackupContents.read(from: paths.androidArchive)
        // The seeded copies are still on disk and would satisfy "already here".
        // Take them away, so the archive Android wrote has to bring its own.
        seeded.removeOriginals()
        let restored = try restore(androidArchive)
        defer { restored.cleanup() }
        let reexported = try KudosBackupService.makeContents(
            works: restored.works,
            bookmarks: restored.bookmarks,
            fonts: [],
            collections: restored.collections,
            readingQueues: restored.queues,
            annotations: restored.annotations,
            savedSearches: restored.searches,
            readingSessions: restored.sessions,
            readingFavorites: restored.favorites,
            fandomReadWatermarks: restored.watermarks,
            tombstones: restored.tombstones,
            defaults: restored.defaults
        )
        let iosCanonical = try canonicalManifest(reexported.manifestData())
        let androidCanonical = try canonicalManifest(androidArchive.manifestData())
        if iosCanonical != androidCanonical, let dir = ProcessInfo.processInfo.environment["KUDOS_GOLDEN_DIFF_DIR"] {
            try? iosCanonical.write(to: URL(fileURLWithPath: dir).appendingPathComponent("ios-reexport.json"))
            try? androidCanonical.write(to: URL(fileURLWithPath: dir).appendingPathComponent("android-archive.json"))
        }
        #expect(iosCanonical == androidCanonical)
        try assertRestoredEPUBs(restored.works, expected: seeded.epub)
        // What iOS wrote into its archive came back out of Android's: a backup
        // that passes through Android keeps a converted import's original.
        assertOriginals(in: androidArchive)
        let restoredOriginal = try #require(Storage.existingOriginalDocumentURL(for: Self.workOneID))
        #expect(restoredOriginal.pathExtension == "html")
        #expect(try Data(contentsOf: restoredOriginal) == Self.originalBytes)
        #expect(WorkConversionRecord.read(for: Self.workOneID) == Self.conversionRecord)
    }

    private func seedLibrary() throws -> SeededLibrary {
        let schema = backupSchema()
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let dates = (0..<20).map { Date(timeIntervalSince1970: 1_700_000_000 + Double($0 * 60)) }
        let epub = try Data(contentsOf: EPUBTests.sampleEPUB)
        let digest = SHA256.hash(data: epub).map { String(format: "%02x", $0) }.joined()

        let first = SavedWork(
            id: Self.workOneID,
            title: "Cross Platform One",
            author: "Archive Author",
            summary: "Distinctive summary",
            sourceURL: "https://archiveofourown.org/works/820001"
        )
        first.dateAdded = dates[0]
        first.downloadedAt = dates[4] // T-353; the second work leaves it nil
        first.createdAt = dates[1]
        first.lastModifiedAt = dates[9]
        first.deletedAt = dates[2]
        first.isPendingDeletion = true
        first.permanentDeletionScheduledAt = dates[19]
        first.assetIdentifier = Storage.defaultEPUBAssetIdentifier(for: Self.workOneID)
        first.isFavorite = true
        first.hasGivenKudos = true
        first.isSaved = true
        first.isFinished = true
        first.keepInProgressOverride = true
        first.hiddenFromHistoryAt = dates[8]
        first.hasEPUB = true
        first.isComplete = true
        first.rating = "Mature"
        first.language = "English"
        first.wordCount = 82_001
        first.datePublished = "2026-01-02"
        first.dateUpdated = "2026-02-03"
        first.chapters = "7/9"
        first.kudos = 901
        first.comments = 81
        first.bookmarks = 71
        first.hits = 8_201
        first.workWarnings = ["Creator Chose Not To Use Archive Warnings"]
        first.workCategories = ["F/F"]
        first.seriesTitle = "Portable Series"
        first.seriesPosition = 2
        first.seriesURL = "https://archiveofourown.org/series/73001"
        first.ao3SeriesID = 73_001
        first.lastSpineIndex = 4
        first.lastScrollFraction = 0.37
        first.lastReadDate = dates[7]
        first.progressModifiedAt = dates[8]
        first.knownChapterCount = 6
        first.lastUpdateCheck = dates[10]
        first.workTags = ["Adventure", "Found Family"]
        first.workFandoms = ["Portable Fandom"]
        first.workCharacters = ["Alex"]
        first.workRelationships = ["Alex/Sam"]
        first.workFreeforms = ["Slow Burn"]
        first.workTagsFetched = true
        first.ao3Unavailable = true
        first.isQueuedForLater = true
        first.epubPreservationStatusRaw = EPUBPreservationStatus.preserved.rawValue
        first.metadataSyncStatusRaw = MetadataSyncStatus.complete.rawValue
        first.preservedAt = dates[5]
        first.lastPreservationAttemptAt = dates[6]
        first.lastAvailabilityCheck = dates[11]
        first.ao3WorkID = 820_001
        first.readiumLocator = #"{"href":"chapter-5.xhtml","locations":{"progression":0.4,"totalProgression":0.57}}"#
        first.legacyReaderProgress = 0.58
        first.epubDigest = digest
        first.tags = [Tag(name: "Portable"), Tag(name: "Re-read")]

        let second = SavedWork(
            id: Self.workTwoID,
            title: "Cross Platform Two",
            author: "Second Author",
            summary: "The explicit nil history marker case",
            sourceURL: "https://archiveofourown.org/works/820002"
        )
        second.dateAdded = dates[3]
        second.createdAt = dates[4]
        second.lastModifiedAt = dates[12]
        second.assetIdentifier = Storage.defaultEPUBAssetIdentifier(for: Self.workTwoID)
        second.hasEPUB = true
        second.isSaved = true
        second.hiddenFromHistoryAt = nil
        second.readiumLocator = #"{"href":"chapter-1.xhtml","locations":{"totalProgression":0.12}}"#
        second.ao3WorkID = 820_002
        second.epubDigest = digest
        // Membership in Saved for Later makes this the state
        // `ReadingQueueService.normalize` leaves behind: the flag follows the
        // membership, a queued file is preserved, and unknown metadata that
        // still needs an AO3 refresh becomes pending. preservedAt is set so
        // normalize does not stamp "now".
        second.isQueuedForLater = true
        second.epubPreservationStatusRaw = EPUBPreservationStatus.preserved.rawValue
        second.metadataSyncStatusRaw = MetadataSyncStatus.pending.rawValue
        second.preservedAt = dates[17]

        for work in [first, second] {
            try epub.write(to: work.fileURL, options: .atomic)
            context.insert(work)
        }
        // The first work is a converted import: the file it was made from and
        // the record of its conversion travel with it (`Originals/`).
        try Self.originalBytes.write(
            to: Storage.originalDocumentURL(for: first.id, fileExtension: "html"),
            options: .atomic
        )
        Self.conversionRecord.write(for: first.id)

        let collection = WorkCollection(name: "Portable Collection")
        collection.id = Self.collectionID
        collection.dateAdded = dates[0]
        collection.createdAt = dates[1]
        collection.lastModifiedAt = dates[13]
        collection.collectionDescription = "Collection description"
        collection.sortOrder = 7
        collection.hue = 0.63
        collection.colorHex = "#3456A8"
        collection.keepsWorksOffline = true
        collection.showsOnHome = true
        collection.works = [first, second]
        collection.workOrderRaw = [second.id, first.id].map(\.uuidString).joined(separator: ",")
        context.insert(collection)

        let custom = ReadingQueue(
            id: Self.queueOneID,
            name: "Portable Queue",
            sortOrder: 4,
            dateCreated: dates[1],
            dateUpdated: dates[14]
        )
        custom.hue = 0.21
        custom.colorHex = "#739A22"
        custom.isPinned = true
        custom.keepsWorksOffline = false
        custom.notes = "Queue notes"
        custom.tags = [Tag(name: "Queue Tag")]
        let customMembership = ReadingQueueMembership(
            id: Self.membershipOneID,
            queue: custom,
            work: first,
            queuedAt: dates[2],
            sortOrderInQueue: 3,
            note: "First in custom queue"
        )
        customMembership.lastModifiedAt = dates[15]
        // Restore sets lastMembershipChangedAt to the newest membership clock.
        custom.lastMembershipChangedAt = dates[15]

        let savedForLater = ReadingQueue(
            id: Self.savedForLaterID,
            name: "Saved for Later",
            kind: .savedForLater,
            sortOrder: -1000,
            dateCreated: dates[0],
            dateUpdated: dates[13]
        )
        savedForLater.hue = 0.84
        savedForLater.colorHex = "#A92A78"
        savedForLater.isPinned = true
        savedForLater.keepsWorksOffline = true
        savedForLater.notes = "System queue notes"
        savedForLater.tags = [Tag(name: "System Tag")]
        let savedMembership = ReadingQueueMembership(
            id: Self.membershipTwoID,
            queue: savedForLater,
            work: second,
            queuedAt: dates[3],
            sortOrderInQueue: 5,
            note: "Second in system queue"
        )
        savedMembership.lastModifiedAt = dates[16]
        savedForLater.lastMembershipChangedAt = dates[16]
        for item in [custom, savedForLater] { context.insert(item) }
        for item in [customMembership, savedMembership] { context.insert(item) }

        let annotations = [
            ReadingAnnotation(
                id: Self.annotationBookmarkID,
                work: first,
                kind: .bookmark,
                locatorString: first.readiumLocator,
                progression: 0.57,
                spineIndex: 4,
                chapterTitle: "Five",
                createdAt: dates[4]
            ),
            ReadingAnnotation(
                id: Self.annotationHighlightID,
                work: first,
                kind: .highlight,
                locatorString: first.readiumLocator,
                selectedText: "Distinctive highlighted text",
                color: .purple,
                progression: 0.58,
                spineIndex: 4,
                chapterTitle: "Five",
                createdAt: dates[5]
            ),
            ReadingAnnotation(
                id: Self.annotationNoteID,
                work: second,
                kind: .highlight,
                locatorString: second.readiumLocator,
                selectedText: "Text with a note",
                note: "Reader note",
                color: .green,
                progression: 0.12,
                spineIndex: 0,
                chapterTitle: "One",
                createdAt: dates[6]
            )
        ]
        annotations.forEach(context.insert)

        let log = seedReadingLog(in: context, first: first, second: second, dates: dates)
        let (session, favorites, watermark) = (log.session, log.favorites, log.watermark)

        let (search, bookmark) = seedSearchAndBookmark(in: context, dates: dates)

        let tombstone = seedTombstone(in: context, dates: dates)

        let defaults = try seedDefaults()

        try context.save()
        return SeededLibrary(
            container: container,
            works: [first, second],
            collection: collection,
            queues: [custom, savedForLater],
            annotations: annotations,
            session: session,
            favorites: favorites,
            watermark: watermark,
            search: search,
            bookmark: bookmark,
            tombstone: tombstone,
            defaults: defaults,
            epub: epub
        )
    }

    private struct SeededLog {
        let session: ReadingSession
        let favorites: [ReadingFavorite]
        let watermark: FandomReadWatermark
    }

    /// The reading session, one favourite of each kind, and a fandom watermark.
    private func seedReadingLog(
        in context: ModelContext, first: SavedWork, second: SavedWork, dates: [Date]
    ) -> SeededLog {
        let session = ReadingSession(
            id: Self.sessionID,
            workID: first.id,
            ao3WorkID: first.ao3WorkID,
            sourceURL: first.sourceURL,
            workTitle: first.title,
            startedAt: dates[7],
            endedAt: dates[8],
            durationSeconds: 1_234,
            lastSpineIndex: 4,
            chapterTitle: "Five",
            endingProgress: 0.58,
            wordCount: 82_001,
            chapterCountAtVisit: 7,
            didFinish: true,
            lastModifiedAt: dates[9]
        )
        let favorites = ReadingFavoriteKind.allCases.enumerated().map { index, kind in
            ReadingFavorite(
                id: Self.favoriteIDs[index],
                kind: kind,
                targetKey: "\(kind.rawValue)-target",
                displayName: "\(kind.rawValue.capitalized) Favorite",
                createdAt: dates[10 + index]
            )
        }
        let watermark = FandomReadWatermark(
            id: Self.watermarkID,
            fandomName: "Portable Fandom",
            lastVisitedAt: dates[14],
            newestWorkIDSeen: 820_002,
            newestWorkTitleSeen: second.title,
            lastModifiedAt: dates[15]
        )
        context.insert(session)
        favorites.forEach(context.insert)
        context.insert(watermark)
        return SeededLog(session: session, favorites: favorites, watermark: watermark)
    }

    /// The saved search and bookmark the golden carries, inserted into `context`.
    private func seedSearchAndBookmark(in context: ModelContext, dates: [Date]) -> (SavedSearch, Bookmark) {
        let filters = AO3SearchFilters(
            query: "portable query",
            title: "Exact title",
            creators: "Archive Author",
            fandom: "Portable Fandom",
            characters: "Alex",
            relationships: "Alex/Sam",
            additionalTags: "Slow Burn",
            excludedFandoms: "Excluded Fandom",
            excludedCharacters: "Villain",
            excludedRelationships: "NoTP",
            excludedAdditionalTags: "Major Character Death",
            wordsFrom: "1000",
            wordsTo: "90000",
            hitsFrom: "10",
            hitsTo: "9000",
            kudosFrom: "5",
            kudosTo: "1000",
            commentsFrom: "1",
            commentsTo: "100",
            bookmarksFrom: "2",
            bookmarksTo: "200",
            dateFrom: dates[0],
            dateTo: dates[19]
        )
        let search = SavedSearch(name: "Portable Search", filters: filters)
        search.id = Self.searchID
        search.dateAdded = dates[4]
        let bookmark = Bookmark(
            title: "Portable Bookmark",
            urlString: "https://archiveofourown.org/works/820001#comments"
        )
        bookmark.id = Self.bookmarkID
        bookmark.dateAdded = dates[5]
        context.insert(search)
        context.insert(bookmark)
        return (search, bookmark)
    }

    /// One signed tombstone (fixed signature: Ed25519 signing is randomized).
    private func seedTombstone(in context: ModelContext, dates: [Date]) -> SyncTombstone {
        let tombstone = SyncTombstone(
            recordID: Self.deletedRecordID,
            recordType: .savedSearch,
            sourceURL: "https://archiveofourown.org/works/829999",
            createdAt: dates[16],
            deletedOnDeviceID: "ios-golden-device",
            deletionReason: "cross-platform golden"
        )
        tombstone.id = Self.tombstoneID
        // CryptoKit's Ed25519 `signature(for:)` is randomized, so calling
        // `TombstoneSigning.sign` on every run would mint a new signature and
        // the golden would never settle. This is one valid signature from the
        // all-zero test key over this tombstone's payload. Restore checks it;
        // it does not re-sign.
        tombstone.signerPublicKey = "03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8"
        tombstone.signature = "716fe0862b2769a5a06c558de57a7772de0877dd3ba527335ae0b9d405f46652e9f1cb6387a022ba4f067b8746fc0ac9da815c8ac5eb1caa0394fd1ad5deaa0a"
        context.insert(tombstone)
        return tombstone
    }

    /// Every backed-up setting set to a distinctive value.
    private func seedDefaults() throws -> UserDefaults {
        let defaults = try testDefaults()
        defaults.set("paged", forKey: "readerMode")
        defaults.set(true, forKey: "readerTwoPage")
        defaults.set(true, forKey: "readerCustomize")
        defaults.set(true, forKey: "readerBoldText")
        defaults.set(22.5, forKey: "readerFontPt")
        defaults.set(1.91, forKey: "readerLineHeight")
        defaults.set(0.04, forKey: "readerLetterSpacing")
        defaults.set(0.08, forKey: "readerWordSpacing")
        defaults.set(33.0, forKey: "readerMargin")
        defaults.set(true, forKey: "readerJustify")
        defaults.set(true, forKey: "confirmBeforeDelete")
        defaults.set(true, forKey: "hideMatureContent")
        defaults.set("hide", forKey: "matureContentMode")
        defaults.set(true, forKey: "requireBiometricToReveal")
        defaults.set("dark", forKey: "appTheme")
        defaults.set("sepia", forKey: "readerTheme")
        defaults.set(false, forKey: "matchAppReaderTheme")
        defaults.set("#2468AC", forKey: "accentColorHex")
        defaults.set(true, forKey: "autoPreserveSmallSeriesOnSaveForLater")
        defaults.set(9, forKey: "autoPreserveSeriesWorkThreshold")
        return defaults
    }

    private func restore(_ contents: KudosBackupContents) throws -> RestoredLibrary {
        let schema = backupSchema()
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let defaults = try testDefaults()
        for tombstone in contents.manifest.tombstones {
            #expect(TombstoneTrustStore.add(tombstone.signerPublicKey, defaults: defaults))
        }
        _ = try KudosBackupService.restore(contents, into: context, defaults: defaults)
        return RestoredLibrary(
            container: container,
            works: try context.fetch(FetchDescriptor<SavedWork>()),
            bookmarks: try context.fetch(FetchDescriptor<Bookmark>()),
            collections: try context.fetch(FetchDescriptor<WorkCollection>()),
            queues: try context.fetch(FetchDescriptor<ReadingQueue>()),
            annotations: try context.fetch(FetchDescriptor<ReadingAnnotation>()),
            searches: try context.fetch(FetchDescriptor<SavedSearch>()),
            sessions: try context.fetch(FetchDescriptor<ReadingSession>()),
            favorites: try context.fetch(FetchDescriptor<ReadingFavorite>()),
            watermarks: try context.fetch(FetchDescriptor<FandomReadWatermark>()),
            tombstones: try context.fetch(FetchDescriptor<SyncTombstone>()),
            defaults: defaults
        )
    }

    private func assertArchive(
        _ archive: KudosBackupContents,
        matches expected: KudosBackupManifest,
        epub: Data
    ) throws {
        let expectedData = try KudosBackupContents(manifest: expected).manifestData()
        #expect(try canonicalManifest(archive.manifestData()) == canonicalManifest(expectedData))
        #expect(archive.epubData(for: Self.workOneID) == epub)
        #expect(archive.epubData(for: Self.workTwoID) == epub)
    }

    private func assertOriginals(in archive: KudosBackupContents) {
        let original = "\(Self.workOneID.uuidString).html"
        let record = "\(Self.workOneID.uuidString).conversion.json"
        // Without regard to letter case: iOS parses the id in the name, and
        // Android may write it either way.
        #expect(Set(archive.originalFileNames.map { $0.lowercased() })
            == [original.lowercased(), record.lowercased()])
        let names = Dictionary(
            archive.originalFileNames.map { ($0.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        #expect(names[original.lowercased()].flatMap(archive.originalData(named:)) == Self.originalBytes)
        #expect(names[record.lowercased()].flatMap(archive.originalData(named:))
            .flatMap { try? JSONDecoder().decode(WorkConversionRecord.self, from: $0) } == Self.conversionRecord)
    }

    private func assertRestoredEPUBs(_ works: [SavedWork], expected: Data) throws {
        #expect(works.count == 2)
        for work in works {
            #expect(try Data(contentsOf: work.fileURL) == expected)
        }
    }

    private func assertDeviceLocalFieldsAreAbsent(from data: Data) {
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let works = root?["works"] as? [[String: Any]]
        #expect(works?.allSatisfy { $0["freedAt"] == nil } == true)
        #expect(works?.allSatisfy { $0["authorIdentitiesJSON"] == nil } == true)
    }

    private func canonicalManifest(_ data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data)
        var root = try #require(lowercasedUUIDs(in: object) as? [String: Any])
        root.removeValue(forKey: "exportedAt")
        root.removeValue(forKey: "exportedBy")
        root.removeValue(forKey: "pronunciations")
        if var settings = root["settings"] as? [String: Any] {
            settings.removeValue(forKey: "readerFontID") // iOS restore deliberately keeps it device-local.
            root["settings"] = settings
        }
        if var works = root["works"] as? [[String: Any]] {
            for index in works.indices {
                works[index].removeValue(forKey: "permanentDeletionScheduledAt")
                works[index].removeValue(forKey: "collectionIDs")
                works[index].removeValue(forKey: "readiumLocatorPlatform")
                works[index].removeValue(forKey: "readiumLocatorEngine")
                works[index].removeValue(forKey: "readiumLocatorVersion")
            }
            root["works"] = sorted(works)
        }
        for key in ["collections", "annotations", "savedSearches", "readingSessions",
                    "readingFavorites", "fandomReadWatermarks", "tombstones"] {
            if var records = root[key] as? [[String: Any]] {
                if key == "collections" {
                    for index in records.indices {
                        records[index].removeValue(forKey: "permanentDeletionScheduledAt")
                    }
                }
                root[key] = sorted(records)
            }
        }
        if var queues = root["readingQueues"] as? [[String: Any]],
           let systemIndex = queues.firstIndex(where: { $0["kindRaw"] as? String == "savedForLater" }) {
            let oldID = queues[systemIndex]["id"] as? String
            queues[systemIndex]["id"] = "00000000-0000-0000-0000-000000000000"
            queues[systemIndex].removeValue(forKey: "permanentDeletionScheduledAt")
            root["readingQueues"] = sorted(queues)
            if let oldID, var memberships = root["readingQueueMemberships"] as? [[String: Any]] {
                for index in memberships.indices where memberships[index]["queueID"] as? String == oldID {
                    memberships[index]["queueID"] = "00000000-0000-0000-0000-000000000000"
                }
                root["readingQueueMemberships"] = sorted(memberships)
            }
        } else if let memberships = root["readingQueueMemberships"] as? [[String: Any]] {
            root["readingQueueMemberships"] = sorted(memberships)
        }
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    private func lowercasedUUIDs(in value: Any) -> Any {
        if let string = value as? String {
            if let uuid = UUID(uuidString: string) {
                return uuid.uuidString.lowercased()
            }
            let components = string.split(separator: ",", omittingEmptySubsequences: false)
            if components.count > 1, components.allSatisfy({ UUID(uuidString: String($0)) != nil }) {
                return components.map { $0.lowercased() }.joined(separator: ",")
            }
            return string
        }
        if let array = value as? [Any] {
            return array.map(lowercasedUUIDs)
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.mapValues(lowercasedUUIDs)
        }
        return value
    }

    private func sorted(_ records: [[String: Any]]) -> [[String: Any]] {
        records.sorted {
            let left = ($0["id"] ?? $0["urlString"] ?? $0["name"] ?? "") as? String ?? ""
            let right = ($1["id"] ?? $1["urlString"] ?? $1["name"] ?? "") as? String ?? ""
            return left < right
        }
    }

    private func fixturePaths() -> (iosArchive: URL, expectedValues: URL, androidArchive: URL) {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let android = root.appendingPathComponent("android/app/src/test/resources/cross-platform")
        return (
            android.appendingPathComponent("ios-export.kudosbackup"),
            android.appendingPathComponent("expected-values.json"),
            root.appendingPathComponent("KudosTests/Fixtures/cross-platform/android-export.kudosbackup")
        )
    }

    private func backupSchema() -> Schema {
        Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self, WorkCollection.self,
            ReadingQueue.self, ReadingQueueMembership.self, SavedSearch.self, SyncTombstone.self,
            ReadingAnnotation.self, ReadingSession.self, ReadingFavorite.self,
            FandomReadWatermark.self
        ])
    }

    private func testDefaults() throws -> UserDefaults {
        let name = "CrossPlatformBackupTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private static let originalBytes = Data("<html><body><p>The original.</p></body></html>".utf8)
    private static let conversionRecord = WorkConversionRecord(
        converterVersion: 1,
        format: "html",
        originalFileName: "cross-platform.html",
        convertedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    private static let workOneID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    private static let workTwoID = UUID(uuidString: "10000000-0000-4000-8000-000000000002")!
    private static let collectionID = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
    private static let queueOneID = UUID(uuidString: "30000000-0000-4000-8000-000000000001")!
    private static let savedForLaterID = UUID(uuidString: "30000000-0000-4000-8000-000000000002")!
    private static let membershipOneID = UUID(uuidString: "40000000-0000-4000-8000-000000000001")!
    private static let membershipTwoID = UUID(uuidString: "40000000-0000-4000-8000-000000000002")!
    private static let annotationBookmarkID = UUID(uuidString: "50000000-0000-4000-8000-000000000001")!
    private static let annotationHighlightID = UUID(uuidString: "50000000-0000-4000-8000-000000000002")!
    private static let annotationNoteID = UUID(uuidString: "50000000-0000-4000-8000-000000000003")!
    private static let sessionID = UUID(uuidString: "60000000-0000-4000-8000-000000000001")!
    private static let favoriteIDs = (1...4).map {
        UUID(uuidString: "70000000-0000-4000-8000-00000000000\($0)")!
    }
    private static let watermarkID = UUID(uuidString: "80000000-0000-4000-8000-000000000001")!
    private static let searchID = UUID(uuidString: "90000000-0000-4000-8000-000000000001")!
    private static let bookmarkID = UUID(uuidString: "a0000000-0000-4000-8000-000000000001")!
    private static let deletedRecordID = UUID(uuidString: "b0000000-0000-4000-8000-000000000001")!
    private static let tombstoneID = UUID(uuidString: "c0000000-0000-4000-8000-000000000001")!
}

private struct SeededLibrary {
    let container: ModelContainer
    let works: [SavedWork]
    let collection: WorkCollection
    let queues: [ReadingQueue]
    let annotations: [ReadingAnnotation]
    let session: ReadingSession
    let favorites: [ReadingFavorite]
    let watermark: FandomReadWatermark
    let search: SavedSearch
    let bookmark: Bookmark
    let tombstone: SyncTombstone
    let defaults: UserDefaults
    let epub: Data

    func cleanup() {
        for work in works { try? FileManager.default.removeItem(at: work.fileURL) }
        removeOriginals()
    }

    func removeOriginals() {
        for work in works {
            if let original = Storage.existingOriginalDocumentURL(for: work.id) {
                try? FileManager.default.removeItem(at: original)
            }
            WorkConversionRecord.delete(for: work.id)
        }
    }
}

private struct RestoredLibrary {
    let container: ModelContainer
    let works: [SavedWork]
    let bookmarks: [Bookmark]
    let collections: [WorkCollection]
    let queues: [ReadingQueue]
    let annotations: [ReadingAnnotation]
    let searches: [SavedSearch]
    let sessions: [ReadingSession]
    let favorites: [ReadingFavorite]
    let watermarks: [FandomReadWatermark]
    let tombstones: [SyncTombstone]
    let defaults: UserDefaults

    func cleanup() {
        for work in works { try? FileManager.default.removeItem(at: work.fileURL) }
        removeOriginals()
    }

    func removeOriginals() {
        for work in works {
            if let original = Storage.existingOriginalDocumentURL(for: work.id) {
                try? FileManager.default.removeItem(at: original)
            }
            WorkConversionRecord.delete(for: work.id)
        }
    }
}
}
