import Foundation
import SwiftData
import Testing
@testable import Kudos

extension PersistenceGateSuites {
    /// Opt in with KUDOS_SCALE_BENCH set to a writable JSON file path in the test host.
    /// Each completed case is written immediately so a long case can be interrupted.
    @MainActor
    struct LibraryScaleBenchmarkTests {
        private static let resultsPath = ProcessInfo.processInfo.environment["KUDOS_SCALE_BENCH"]

        @Test(.enabled(if: resultsPath != nil)) func measureLibraryScale() async throws {
            let path = try #require(Self.resultsPath)
            let report = LibraryScaleBenchmarkReport(output: URL(fileURLWithPath: path))
            try report.write()
            for library in [15_000, 50_000] {
                let fixture = try LibraryScaleBenchmarkFixture(library: library)
                defer { fixture.cleanUp() }
                let started = ContinuousClock.now
                try fixture.seed()
                let seedSeconds = benchmarkSeconds(since: started)
                let context = fixture.makeContext()
                let sessions = try context.fetchCount(FetchDescriptor<ReadingSession>())
                let annotations = try context.fetchCount(FetchDescriptor<ReadingAnnotation>())
                try #require(sessions == library * 6 && annotations == library * 2 / 5)
                try report.record("seed", for: fixture, seconds: seedSeconds, counts: [
                    "reading_sessions": sessions,
                    "annotations": annotations,
                    "tag_pool": fixture.tagPoolSize,
                    "original_files": library / 5,
                    "collections": fixture.collectionCount,
                    "queues": fixture.queueCount
                ])

                try measureEmptySweep(fixture, report)
                try measureAssets(fixture, report)
                try withLocalTombstoneSigning {
                    try measureQueues(fixture, report)
                }
                try await measureImport(fixture, report)
                try await measureRemoteSave(fixture, report)
                try withLocalTombstoneSigning {
                    try measurePermanentDelete(fixture, report)
                    try measureDueSweep(fixture, report)
                }
            }
        }

        private func measureEmptySweep(
            _ fixture: LibraryScaleBenchmarkFixture, _ report: LibraryScaleBenchmarkReport
        ) throws {
            let context = fixture.makeContext()
            try #require(PersistenceOperationGate.active == nil)
            let started = ContinuousClock.now
            let deleted = PreservedWorkService.sweepExpired(in: context)
            let seconds = benchmarkSeconds(since: started)
            try #require(deleted == 0)
            try report.record("expiry_none_due", for: fixture, seconds: seconds, counts: [
                "works_before": fixture.library, "works_due": 0, "works_deleted": deleted,
                "collections_before": fixture.collectionCount, "queues_before": fixture.queueCount
            ])
        }

        private func measureAssets(
            _ fixture: LibraryScaleBenchmarkFixture, _ report: LibraryScaleBenchmarkReport
        ) throws {
            let context = fixture.makeContext()
            let work = try fixture.work(at: 0, in: context)
            let directoryEntries = try fixture.originalDirectoryEntryCount()
            let lookupStarted = ContinuousClock.now
            let candidate = WorkReconversion.candidate(for: work)
            let lookupSeconds = benchmarkSeconds(since: lookupStarted)
            try #require(candidate?.originalURL.path == fixture.originalURL(for: work.id).path)
            try report.record("original_lookup", for: fixture, seconds: lookupSeconds, counts: [
                "lookups": 1, "original_directory_entries": directoryEntries
            ])

            // The planner's asset pass only visits works. Keep the work and shelf
            // manifest costs in the sample, and leave reading history out of it.
            let works = try context.fetch(FetchDescriptor<SavedWork>())
            let collections = try context.fetch(FetchDescriptor<WorkCollection>())
            let queues = try context.fetch(FetchDescriptor<ReadingQueue>())
            try #require(works.count == fixture.library)
            let suite = "LibraryScaleBenchmark.\(UUID())"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let planStarted = ContinuousClock.now
            let plan = try KudosBackupService.makeExportPlan(
                works: works, bookmarks: [], fonts: [], collections: collections, readingQueues: queues,
                defaults: defaults
            )
            let planSeconds = benchmarkSeconds(since: planStarted)
            let originals = plan.assets.filter { $0.entryName.hasPrefix("Originals/") }.count
            try #require(originals == fixture.library / 5)
            try report.record("backup_asset_plan", for: fixture, seconds: planSeconds, counts: [
                "input_works": works.count, "original_directory_entries": directoryEntries,
                "original_assets": originals, "total_assets": plan.assets.count,
                "manifest_bytes": plan.manifestData.count
            ])
        }

        private func measureQueues(
            _ fixture: LibraryScaleBenchmarkFixture, _ report: LibraryScaleBenchmarkReport
        ) throws {
            let context = fixture.makeContext()
            let queueID = fixture.id(for: fixture.library)
            let descriptor = FetchDescriptor<ReadingQueue>(predicate: #Predicate { $0.id == queueID })
            let largeQueue = try #require(try context.fetch(descriptor).first)
            let ordered = ReadingQueueService.orderedWorks(in: largeQueue)
            let batchSize = 10_000
            // Ten percent of the large queue is pending and hidden by orderedWorks.
            try #require(largeQueue.memberships.count == 15_000 && ordered.count == 13_500)
            let works = Array(ordered.prefix(batchSize))
            let seedIDs = works.map(\.id)

            let createStarted = ContinuousClock.now
            let createdQueue = ReadingQueueService.createQueue(
                named: "Benchmark seeded queue", keepsWorksOffline: false, seedWorkIDs: seedIDs, in: context
            )
            let createSeconds = benchmarkSeconds(since: createStarted)
            try #require(createdQueue.memberships.count == batchSize && !context.hasChanges)
            try report.record("queue_create_seeded", for: fixture, seconds: createSeconds, counts: [
                "memberships_added": createdQueue.memberships.count
            ])
            context.delete(createdQueue)
            try context.save()

            let removeStarted = ContinuousClock.now
            for work in works {
                ReadingQueueService.removeFromQueue(work, from: largeQueue, in: context)
            }
            let removeSeconds = benchmarkSeconds(since: removeStarted)
            try #require(largeQueue.memberships.count == 5_000 && !context.hasChanges)
            try report.record("queue_remove", for: fixture, seconds: removeSeconds, counts: [
                "memberships_before": 15_000, "memberships_removed": batchSize,
                "memberships_after": largeQueue.memberships.count
            ])

            let appendStarted = ContinuousClock.now
            ReadingQueueService.append(works, to: largeQueue, in: context)
            let appendSeconds = benchmarkSeconds(since: appendStarted)
            try #require(largeQueue.memberships.count == 15_000 && !context.hasChanges)
            try report.record("queue_append", for: fixture, seconds: appendSeconds, counts: [
                "memberships_before": 5_000, "memberships_added": batchSize,
                "memberships_after": largeQueue.memberships.count
            ])

            let mergeStarted = ContinuousClock.now
            let primary = ReadingQueueService.ensureSavedForLaterQueue(in: context)
            let mergeSeconds = benchmarkSeconds(since: mergeStarted)
            let uniqueWorks = Set(primary.memberships.compactMap { $0.work?.id })
            try #require(uniqueWorks.count == 12_500)
            try #require(try context.fetchCount(FetchDescriptor<ReadingQueue>()) == fixture.queueCount - 1)
            try report.record("saved_for_later_merge", for: fixture, seconds: mergeSeconds, counts: [
                "primary_memberships_before": 7_500, "duplicate_memberships": 7_500,
                "overlapping_works": 2_500, "unique_works_after": uniqueWorks.count
            ])
        }

        private func measureImport(
            _ fixture: LibraryScaleBenchmarkFixture, _ report: LibraryScaleBenchmarkReport
        ) async throws {
            let context = fixture.makeContext()
            let fm = FileManager.default
            // One existing AO3 identity in every five inputs. Use non-converted
            // rows so files installed by the importer can all be cleaned up.
            let inputs = try (0..<200).map { index in
                let ordinal = index.isMultiple(of: 5) ? (index / 5) * 10 + 2 : fixture.library + index
                let source = try #require(URL(string: fixture.sourceURL(for: ordinal)))
                let file = fixture.directory.appendingPathComponent("import-\(index).epub")
                try fixture.epub.write(to: file)
                return (ordinal: ordinal, source: source, file: file)
            }
            var imported: [SavedWork] = []
            var files: [URL] = []
            defer { for file in files { try? fm.removeItem(at: file) } }
            let started = ContinuousClock.now
            for input in inputs {
                let work = try await importEPUB(
                    input.file, source: input.source, verifyAvailability: false, into: context
                )
                imported.append(work)
                files.append(work.fileURL)
            }
            let seconds = benchmarkSeconds(since: started)
            let merged = zip(inputs, imported).filter { input, work in work.id == fixture.id(for: input.ordinal) }.count
            let newWorks = imported.count - merged
            try #require(merged == 40 && newWorks == 160)
            try #require(try context.fetchCount(FetchDescriptor<SavedWork>()) == fixture.library + newWorks)
            try report.record("epub_import", for: fixture, seconds: seconds, counts: [
                "works_before": fixture.library, "inputs": inputs.count,
                "duplicates_merged": merged, "works_inserted": newWorks
            ])
            for (input, work) in zip(inputs, imported) {
                if input.ordinal < fixture.library {
                    work.hasEPUB = false
                    work.epubDigest = ""
                } else {
                    context.delete(work)
                }
            }
            try context.save()
        }

        private func measureRemoteSave(
            _ fixture: LibraryScaleBenchmarkFixture, _ report: LibraryScaleBenchmarkReport
        ) async throws {
            let context = fixture.makeContext()
            let summaries = (0..<200).map { index in
                let ordinal = index.isMultiple(of: 5) ? (index / 5) * 10 + 3 : fixture.library + index
                return AO3WorkSummary.subscription(id: fixture.ao3ID(for: ordinal),
                                                   title: "Archive work \(ordinal)", authors: ["Archivist"])
            }
            // Never contact AO3: a matched work that already has an EPUB skips the stub and refreshes from AO3
            // (`ReadingQueueService.preserve` → `syncMetadata`). The fixture matches only works without one.
            let matchedIDs = Set(summaries.map(\.id))
            try #require(try context.fetch(FetchDescriptor<SavedWork>()).allSatisfy {
                !($0.hasEPUB && $0.ao3WorkID.map(matchedIDs.contains) == true)
            })
            var downloadRequests = 0
            let started = ContinuousClock.now
            let error = await bulkSaveForLaterRemote(summaries, in: context) { _ in
                downloadRequests += 1
                // A failed stub download retains the queued record and bypasses
                // preserve's subsequent live AO3 metadata refresh.
                throw AO3Error.notFound
            }
            let seconds = benchmarkSeconds(since: started)
            try #require(error == nil && downloadRequests == summaries.count)
            let inputIDs = Set(summaries.map(\.id))
            let saved = try context.fetch(FetchDescriptor<SavedWork>()).filter {
                $0.ao3WorkID.map(inputIDs.contains) == true
            }
            try #require(saved.count == summaries.count && saved.allSatisfy {
                $0.isInSavedForLaterQueue && $0.epubPreservationStatus == .failed
            })
            let inserted = saved.filter { ($0.ao3WorkID ?? 0) >= fixture.ao3ID(for: fixture.library) }
            try #require(inserted.count == 160)
            try report.record("remote_bulk_save_offline", for: fixture, seconds: seconds, counts: [
                "works_before": fixture.library, "inputs": summaries.count,
                "existing_matches": saved.count - inserted.count, "works_inserted": inserted.count,
                "stub_downloads": downloadRequests
            ])
            for work in inserted { context.delete(work) }
            try context.save()
        }

        private func measurePermanentDelete(
            _ fixture: LibraryScaleBenchmarkFixture, _ report: LibraryScaleBenchmarkReport
        ) throws {
            let context = fixture.makeContext()
            let work = try fixture.work(at: 0, in: context)
            let original = fixture.originalURL(for: work.id)
            let annotations = try context.fetchCount(FetchDescriptor<ReadingAnnotation>())
            let directoryEntries = try fixture.originalDirectoryEntryCount()
            work.isPendingDeletion = true
            try context.save()
            let started = ContinuousClock.now
            PreservedWorkService.deletePermanently(work, in: context)
            let seconds = benchmarkSeconds(since: started)
            let remaining = try fixture.makeContext().fetchCount(FetchDescriptor<SavedWork>())
            try #require(remaining == fixture.library - 1)
            try #require(!FileManager.default.fileExists(atPath: original.path))
            try report.record("permanent_delete", for: fixture, seconds: seconds, counts: [
                "works_before": fixture.library, "annotations_before": annotations, "works_deleted": 1,
                "original_directory_entries": directoryEntries
            ])
        }

        private func measureDueSweep(
            _ fixture: LibraryScaleBenchmarkFixture, _ report: LibraryScaleBenchmarkReport
        ) throws {
            let setup = fixture.makeContext()
            let pending = try setup.fetch(FetchDescriptor<SavedWork>(predicate: #Predicate { $0.isPendingDeletion }))
            let due = fixture.library / 10
            try #require(pending.count == due)
            for work in pending {
                work.permanentDeletionScheduledAt = LibraryScaleBenchmarkFixture.historyEnd
            }
            try setup.save()
            let context = fixture.makeContext()
            let annotations = try context.fetchCount(FetchDescriptor<ReadingAnnotation>())
            let worksBefore = try context.fetchCount(FetchDescriptor<SavedWork>())
            let directoryEntries = try fixture.originalDirectoryEntryCount()
            try #require(PersistenceOperationGate.active == nil)
            let started = ContinuousClock.now
            let deleted = PreservedWorkService.sweepExpired(in: context)
            let seconds = benchmarkSeconds(since: started)
            try #require(deleted == due)
            let remaining = try fixture.makeContext().fetchCount(FetchDescriptor<SavedWork>())
            try #require(remaining == worksBefore - due)
            try report.record("expiry_ten_percent_due", for: fixture, seconds: seconds, counts: [
                "works_before": worksBefore, "annotations_before": annotations,
                "works_due": due, "works_deleted": deleted, "collections_before": fixture.collectionCount,
                "queues_before": fixture.queueCount - 1, "original_directory_entries": directoryEntries
            ])
        }

        private func withLocalTombstoneSigning(_ body: () throws -> Void) rethrows {
            let oldSigningKey = TombstoneSigning.keyOverride
            let oldCloudStore = TombstoneTrustStore.iCloudStore
            let deviceKey = "persistenceSyncDeviceID"
            let oldDeviceID = UserDefaults.standard.object(forKey: deviceKey)
            let signingKey = TombstoneSigning.makePrivateKey()
            #if DEBUG
            let oldKeychain = TombstoneTrustStore.keychainOverride
            let legacyTrustKey = TombstoneTrustStore.localKeysKey
            let oldLegacyTrust = UserDefaults.standard.object(forKey: legacyTrustKey)
            TombstoneTrustStore.keychainOverride = .stored([TombstoneSigning.publicKeyHex(of: signingKey)])
            #endif
            TombstoneSigning.keyOverride = signingKey
            TombstoneTrustStore.iCloudStore = nil
            defer {
                TombstoneSigning.keyOverride = oldSigningKey
                TombstoneTrustStore.iCloudStore = oldCloudStore
                UserDefaults.standard.set(oldDeviceID, forKey: deviceKey)
                #if DEBUG
                TombstoneTrustStore.keychainOverride = oldKeychain
                UserDefaults.standard.set(oldLegacyTrust, forKey: legacyTrustKey)
                #endif
            }
            _ = PersistenceDevice.currentID()
            try body()
        }
    }
}

@MainActor
private final class LibraryScaleBenchmarkFixture {
    static let historyEnd = Date(timeIntervalSince1970: 1_767_225_600)

    let library: Int
    let collectionCount = 300
    let queueCount = 300
    let directory: URL
    let epub: Data
    let originalsDirectory: URL
    private let worksDirectory: URL
    private let namespace: UUID
    private let container: ModelContainer
    var tagPoolSize: Int { library * 4 }

    init(library: Int) throws {
        let namespace = UUID()
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("kudos-scale-\(namespace)", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let schema = MyApp.sharedModelContainer.schema
            let configuration = ModelConfiguration(
                schema: schema, url: directory.appendingPathComponent("Library.store"), cloudKitDatabase: .none
            )
            self.container = try ModelContainer(for: schema, configurations: [configuration])
            self.epub = try EPUBBuilder.archive(
                metadata: EPUBBuilder.Metadata(title: "The Light in the Stacks", author: "Archivist",
                                               identifier: "kudos-scale-fixture"),
                chapters: [EPUBBuilder.Chapter(title: "Chapter One", bodyXHTML: "<p>The archivist kept a copy.</p>")],
                modified: Self.historyEnd
            )
        } catch {
            try? fm.removeItem(at: directory)
            throw error
        }
        self.library = library
        self.namespace = namespace
        self.directory = directory
        originalsDirectory = Storage.originalsDirectory
        worksDirectory = Storage.worksDirectory
    }

    func makeContext() -> ModelContext {
        let context = ModelContext(container)
        // Real queue and delete operations use saveBestEffort, which only
        // commits with autosave enabled.
        context.autosaveEnabled = true
        return context
    }

    func cleanUp() {
        let fm = FileManager.default
        // Production Storage has no root override for these assets. Remove
        // only paths in this run's UUID namespace, including partial seeding.
        let prefix = namespace.uuidString.prefix(24)
        for folder in [originalsDirectory, worksDirectory] {
            for name in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] where name.hasPrefix(prefix) {
                try? fm.removeItem(at: folder.appendingPathComponent(name))
            }
        }
        try? fm.removeItem(at: directory)
    }

    func id(for ordinal: Int) -> UUID {
        var bytes = namespace.uuid
        bytes.12 = UInt8(truncatingIfNeeded: ordinal >> 24)
        bytes.13 = UInt8(truncatingIfNeeded: ordinal >> 16)
        bytes.14 = UInt8(truncatingIfNeeded: ordinal >> 8)
        bytes.15 = UInt8(truncatingIfNeeded: ordinal)
        return UUID(uuid: bytes)
    }

    func ao3ID(for ordinal: Int) -> Int { 100_000_000 + ordinal }

    func sourceURL(for ordinal: Int) -> String { "https://archiveofourown.org/works/\(ao3ID(for: ordinal))" }

    func originalURL(for id: UUID) -> URL { originalsDirectory.appendingPathComponent("\(id.uuidString).txt") }

    func originalDirectoryEntryCount() throws -> Int {
        try FileManager.default.contentsOfDirectory(atPath: originalsDirectory.path).count
    }

    func work(at ordinal: Int, in context: ModelContext) throws -> SavedWork {
        let target = id(for: ordinal)
        var descriptor = FetchDescriptor<SavedWork>(predicate: #Predicate { $0.id == target })
        descriptor.fetchLimit = 1
        return try #require(try context.fetch(descriptor).first)
    }

    func seed() throws {
        let tagPool = (0..<tagPoolSize).map { "Archive trope \($0)" }
        let original = Data("The archivist kept the original.".utf8)
        // Small commits bound the number of dirty SwiftData rows. No timed
        // service is used to populate the fixture.
        for start in stride(from: 0, to: library, by: 500) {
            try autoreleasepool {
                let context = ModelContext(container)
                context.autosaveEnabled = false
                for ordinal in start..<min(start + 500, library) {
                    try seedWork(ordinal, tags: tagPool, original: original, in: context)
                }
                try context.save()
            }
        }
        try seedShelves()
    }

    private func seedWork(_ ordinal: Int, tags: [String], original: Data, in context: ModelContext) throws {
        let workID = id(for: ordinal)
        let title = "The \(["Lantern", "Map", "Beacon", "Key", "Letter"][ordinal % 5]) of Archive \(ordinal)"
        let author = "Archivist \(ordinal % 4_000)"
        let source = sourceURL(for: ordinal)
        let daysAgo = (ordinal * 179) % 10_958 + 365
        let date = Self.historyEnd.addingTimeInterval(-Double(daysAgo) * 86_400)
        let work = SavedWork(id: workID, title: title, author: author,
                             summary: "A story preserved from the reading archive.", sourceURL: source)
        let fandom = "Fandom \(ordinal % 1_200)"
        let words = 400 + (ordinal * 307) % 230_000
        let chapters = 1 + ordinal % 35
        let finished = !ordinal.isMultiple(of: 3)
        work.ao3WorkID = ao3ID(for: ordinal)
        work.dateAdded = date
        work.createdAt = date
        work.lastModifiedAt = date
        work.language = "English"
        work.wordCount = words
        work.chapters = "\(chapters)/\(chapters)"
        work.knownChapterCount = chapters
        work.isComplete = true
        work.isFinished = finished
        work.isSaved = true
        work.rating = ordinal.isMultiple(of: 5) ? "Teen And Up Audiences" : "General Audiences"
        work.workFandoms = [fandom]
        work.workFreeforms = (0..<(4 + ordinal % 36)).map { offset in
            tags[(ordinal * 31 + offset * 137) % tags.count]
        }
        work.workTags = work.workFandoms + work.workFreeforms
        work.workTagsFetched = true
        work.hasEPUB = ordinal.isMultiple(of: 5)
        if work.hasEPUB {
            try original.write(to: originalURL(for: workID), options: .withoutOverwriting)
            let file = worksDirectory.appendingPathComponent(work.effectiveAssetIdentifier)
            try epub.write(to: file, options: .withoutOverwriting)
            work.downloadedAt = date
        }
        // Spread pending rows across shelves, including one converted work in
        // every fifty so the sweep also exercises deletion of original files.
        if ordinal % 10 == 5 + ordinal / 10 % 5 {
            work.isPendingDeletion = true
            work.deletedAt = Self.historyEnd
            // The first sweep is a no-op over the same pending population.
            work.permanentDeletionScheduledAt = .distantFuture
        }
        context.insert(work)
        seedSessions(ordinal, workID: workID, title: title, source: source, date: date,
                     words: words, chapters: chapters, finished: finished, in: context)
        if ordinal % 5 < 2 {
            let locator = """
                {"href":"chapter-1.xhtml","type":"application/xhtml+xml","locations":{"progression":0.4}}
                """
            context.insert(ReadingAnnotation(
                id: id(for: 900_000 + ordinal), work: work, kind: .highlight,
                locatorString: locator,
                selectedText: "The archivist kept a copy.", note: "Remember this passage", createdAt: date
            ))
        }
    }

    private func seedSessions(
        _ ordinal: Int, workID: UUID, title: String, source: String, date: Date,
        words: Int, chapters: Int, finished: Bool, in context: ModelContext
    ) {
        for sitting in 0..<6 {
            let start = date.addingTimeInterval(Double(sitting * 18 + 1) * 86_400)
            let duration = Double(180 + (ordinal * 7 + sitting * 97) % 2_700)
            context.insert(ReadingSession(
                id: id(for: 500_000 + ordinal * 6 + sitting), workID: workID, ao3WorkID: ao3ID(for: ordinal),
                sourceURL: source, workTitle: title, startedAt: start, endedAt: start.addingTimeInterval(duration),
                durationSeconds: duration, lastSpineIndex: sitting % chapters,
                chapterTitle: "Chapter \(sitting % chapters + 1)",
                endingProgress: Double(sitting + 1) / (finished ? 6 : 9),
                wordCount: words, chapterCountAtVisit: chapters, didFinish: finished && sitting == 5
            ))
        }
    }

    private func seedShelves() throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let works = try context.fetch(FetchDescriptor<SavedWork>(sortBy: [SortDescriptor(\.sourceURL)]))
        try #require(works.count == library)
        for index in 0..<collectionCount {
            let collection = WorkCollection(name: "Collection \(index + 1)")
            collection.id = id(for: library + queueCount + index)
            collection.dateAdded = Self.historyEnd
            collection.createdAt = Self.historyEnd
            collection.lastModifiedAt = Self.historyEnd
            context.insert(collection)
            collection.works = (0..<24).map { works[(index * 43 + $0 * 107) % library] }
        }
        seedQueue(0, kind: .custom, ordinals: 0..<15_000, works: works, in: context)
        seedQueue(1, kind: .savedForLater, ordinals: 0..<7_500, works: works, in: context)
        seedQueue(2, kind: .savedForLater, ordinals: 5_000..<12_500, works: works, in: context)
        for index in 3..<queueCount {
            let start = (index * 137) % (library - 20)
            seedQueue(index, kind: .custom, ordinals: start..<(start + 20), works: works, in: context)
        }
        try context.save()
        let reloaded = ModelContext(container)
        let membershipCount = try reloaded.fetchCount(FetchDescriptor<ReadingQueueMembership>())
        try #require(membershipCount == 30_000 + (queueCount - 3) * 20)
    }

    private func seedQueue(
        _ index: Int, kind: ReadingQueueKind, ordinals: Range<Int>, works: [SavedWork], in context: ModelContext
    ) {
        let queue = ReadingQueue(
            id: id(for: library + index), name: "Queue \(index + 1)", kind: kind, sortOrder: index,
            dateCreated: Self.historyEnd, dateUpdated: Self.historyEnd
        )
        queue.keepsWorksOffline = false
        context.insert(queue)
        var memberships: [ReadingQueueMembership] = []
        memberships.reserveCapacity(ordinals.count)
        for (order, ordinal) in ordinals.enumerated() {
            let work = works[ordinal]
            let membership = ReadingQueueMembership(
                id: id(for: 1_000_000 + index * 15_000 + order), queue: nil, work: work,
                queuedAt: Self.historyEnd, sortOrderInQueue: order
            )
            context.insert(membership)
            if !work.queueMemberships.contains(where: { $0.id == membership.id }) {
                work.queueMemberships.append(membership)
            }
            work.isQueuedForLater = true
            memberships.append(membership)
        }
        // Assign the large inverse once so setup avoids the growing queue
        // mutation that the benchmark is intended to measure.
        queue.memberships = memberships
    }
}

@MainActor
private final class LibraryScaleBenchmarkReport {
    private nonisolated struct Sample: Encodable {
        let name: String
        let library: Int
        let seconds: Double
        let counts: [String: Int]

        enum CodingKeys: String, CodingKey {
            case name = "case"
            case library, seconds, counts
        }
    }

    private let output: URL
    private var samples: [Sample] = []

    init(output: URL) { self.output = output }

    func record(
        _ name: String, for fixture: LibraryScaleBenchmarkFixture, seconds: Double, counts: [String: Int]
    ) throws {
        samples.append(Sample(name: name, library: fixture.library, seconds: seconds, counts: counts))
        try write()
    }

    func write() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(samples).write(to: output, options: .atomic)
    }
}

private func benchmarkSeconds(since start: ContinuousClock.Instant) -> Double {
    let duration = start.duration(to: ContinuousClock.now).components
    return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
}
