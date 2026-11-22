import Foundation
import SwiftData
import Testing
@testable import Kudos

/// T-528: A reading queue in four states (New, In line, Waiting, Finished),
/// membership origin, single-vs-bulk add states, and derived transitions.
@MainActor
@Suite(.serialized)
struct ReadingQueueSectionsTests {
    private final class BundleAnchor {}

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self, WorkCollection.self,
            ReadingQueue.self, ReadingQueueMembership.self, SavedSearch.self,
            QueueSavedSearchLink.self, SyncTombstone.self, ReadingAnnotation.self,
            ReadingSession.self, ReadingFavorite.self, FandomReadWatermark.self
        ])
        return ModelContext(try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "ReadingQueueSectionsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeWork(
        title: String,
        author: String = "Author",
        chapters: String = "1/1",
        isComplete: Bool = true
    ) -> SavedWork {
        let work = SavedWork(title: title, author: author)
        work.chapters = chapters
        work.isComplete = isComplete
        return work
    }

    private func makeSummary(_ id: Int, chapters: String = "1/1", isComplete: Bool = true) -> AO3WorkSummary {
        AO3WorkSummary(
            id: id,
            title: "Work \(id)",
            authors: ["Writer"],
            fandoms: ["Fandom"],
            rating: "Teen And Up Audiences",
            warnings: [],
            categories: [],
            isComplete: isComplete,
            dateUpdated: "2026-11-16",
            tags: [],
            summary: "Summary",
            language: "English",
            words: 1_500,
            chapters: chapters,
            comments: nil,
            kudos: nil,
            hits: nil,
            seriesTitle: nil,
            seriesURL: nil,
            seriesPosition: nil
        )
    }

    private func copySampleEPUB() throws -> URL {
        let sample = try #require(Bundle(for: BundleAnchor.self).url(forResource: "sample", withExtension: "epub"))
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")
        try FileManager.default.copyItem(at: sample, to: temp)
        return temp
    }

    @Test func existingMembershipDefaultsToInLineAndNoOrigin() throws {
        let context = try makeContext()
        let queue = ReadingQueue(name: "Existing")
        let work = makeWork(title: "Legacy Work")
        let membership = ReadingQueueMembership(queue: queue, work: work)
        context.insert(queue)
        context.insert(work)
        context.insert(membership)

        #expect(membership.stateRaw == "inLine")
        #expect(membership.state == .inLine)
        #expect(!membership.stateWasRecorded)
        #expect(membership.origin == nil)
        #expect(membership.originDisplayLine == nil)

        membership.stateRaw = "unknownFutureState"
        #expect(membership.state == .inLine)

        membership.stateRaw = ReadingQueueMembershipState.inLine.rawValue
        let partition = ReadingQueueFacts.partition(memberships: [membership])
        #expect(partition.new.isEmpty)
        #expect(partition.upNext?.id == work.id)
        #expect(partition.inLineRest.isEmpty)
        #expect(partition.waiting.isEmpty)
        #expect(partition.finished.isEmpty)
    }

    @Test func singleAddStartsInLineWhileBulkAppendAndPickerStartNew() throws {
        let context = try makeContext()
        let queue = ReadingQueue(name: "Casefic")
        queue.keepsWorksOffline = false
        context.insert(queue)

        let savedSearch = SavedSearch(name: "Holmes casefic", filters: AO3SearchFilters(query: "holmes"))
        context.insert(savedSearch)
        let searchOrigin = ReadingQueueMembershipOrigin(
            kind: .search,
            searchID: savedSearch.id,
            label: savedSearch.name
        )

        // Single swipe quickAdd -> In line + search origin.
        let controller = RemoteWorkSelectionController()
        controller.sourceQueueID = queue.id
        controller.origin = searchOrigin
        controller.quickAdd(makeSummary(101), in: context, defaults: try makeDefaults()) { _, _, _ in }

        let singleMembership = try #require(
            ReadingQueueService.orderedMemberships(in: queue).first { $0.work?.ao3WorkID == 101 }
        )
        #expect(singleMembership.state == .inLine)
        #expect(singleMembership.origin == searchOrigin)
        #expect(singleMembership.originDisplayLine == "From Holmes casefic")

        // Single vs bulk AddToQueueView init state.
        let singlePicker = AddToQueueView(work: try #require(singleMembership.work), origin: searchOrigin)
        let bulkPicker = AddToQueueView(works: [try #require(singleMembership.work)], origin: searchOrigin)
        #expect(singlePicker.entryState == .inLine)
        #expect(bulkPicker.entryState == .new)
        #expect(bulkPicker.origin == searchOrigin)

        // Bulk append -> New + origin; repeat add must not demote In line to New.
        let bulkOne = makeWork(title: "Bulk One")
        let bulkTwo = makeWork(title: "Bulk Two")
        context.insert(bulkOne)
        context.insert(bulkTwo)
        ReadingQueueService.append(
            [bulkOne, bulkTwo],
            to: queue,
            state: .new,
            origin: ReadingQueueMembershipOrigin(kind: .search, searchID: nil, label: "“lighthouse”"),
            in: context
        )
        let duplicate = ReadingQueueService.add(
            try #require(singleMembership.work),
            to: queue,
            state: .new,
            in: context
        )
        #expect(duplicate.id == singleMembership.id)
        #expect(duplicate.state == .inLine)

        let partition = ReadingQueueFacts.partition(memberships: ReadingQueueService.orderedMemberships(in: queue))
        #expect(partition.new.map(\.work.title) == ["Bulk One", "Bulk Two"])
        #expect(partition.upNext?.work.ao3WorkID == 101)
    }

    @Test func bulkRemoteSaveSeriesPreserveCreateQueueSeedAndToggleRecordExpectedStates() async throws {
        let context = try makeContext()
        let savedQueue = ReadingQueueService.ensureSavedForLaterQueue(in: context)
        let bulkOrigin = ReadingQueueMembershipOrigin(kind: .search, searchID: nil, label: "Fluff")

        // 1. bulkSaveForLaterRemote -> New + origin.
        let summary202 = makeSummary(202)
        let errorMessage = await bulkSaveForLaterRemote([summary202], origin: bulkOrigin, in: context) { _ in
            try copySampleEPUB()
        }
        #expect(errorMessage == nil)
        let bulkSaved = try #require(
            ReadingQueueService.orderedMemberships(in: savedQueue).first { $0.work?.ao3WorkID == 202 }
        )
        defer { try? FileManager.default.removeItem(at: bulkSaved.work!.fileURL) }
        #expect(bulkSaved.state == .new)
        #expect(bulkSaved.origin == bulkOrigin)

        // 2. preserveSeries -> New + origin (already preserved branch, zero network).
        let seriesQueue = ReadingQueue(name: "Series Queue")
        let seriesWork = makeWork(title: "Series Entry")
        seriesWork.ao3WorkID = 303
        seriesWork.sourceURL = makeSummary(303).workURL.absoluteString
        seriesWork.epubPreservationStatus = .preserved
        context.insert(seriesQueue)
        context.insert(seriesWork)
        let seriesOrigin = ReadingQueueMembershipOrigin(kind: .source, searchID: nil, label: "Series")
        _ = await ReadingQueueService.preserveSeries(
            [makeSummary(303)],
            to: [seriesQueue],
            origin: seriesOrigin,
            in: context,
            pauseNanos: 0
        )
        let seriesMembership = try #require(seriesQueue.memberships.first)
        #expect(seriesMembership.state == .new)
        #expect(seriesMembership.origin == seriesOrigin)

        // 3. createQueue(seedWorkIDs:) -> New + manual origin.
        let libraryWork = makeWork(title: "Library Pick")
        libraryWork.isSaved = true
        context.insert(libraryWork)
        let seededQueue = ReadingQueueService.createQueue(
            named: "Seeded",
            seedWorkIDs: [libraryWork.id],
            in: context
        )
        let seededMembership = try #require(seededQueue.memberships.first)
        #expect(seededMembership.state == .new)
        #expect(seededMembership.origin == ReadingQueueMembershipOrigin(kind: .manual))

        // 4. toggleSavedForLater -> In line + manual origin.
        let singleWork = makeWork(title: "Want Single")
        singleWork.hasEPUB = true
        context.insert(singleWork)
        ReadingQueueService.toggleSavedForLater(singleWork, in: context)
        for _ in 0 ..< 20 where !singleWork.isInSavedForLaterQueue {
            await Task.yield()
        }
        let toggleMembership = try #require(
            singleWork.queueMemberships.first { $0.queue?.id == savedQueue.id }
        )
        #expect(toggleMembership.state == .inLine)
        #expect(toggleMembership.origin == ReadingQueueMembershipOrigin(kind: .manual))
    }

    @Test func sortIntoLineMovesNewToEndOfInLineAndStampsSyncClock() throws {
        let context = try makeContext()
        let queue = ReadingQueue(name: "Queue")
        let first = makeWork(title: "First")
        let second = makeWork(title: "Second")
        let fresh = makeWork(title: "Fresh")
        context.insert(queue)
        context.insert(first)
        context.insert(second)
        context.insert(fresh)

        let m1 = ReadingQueueService.add(first, to: queue, state: .inLine, in: context)
        let mFresh = ReadingQueueService.add(fresh, to: queue, state: .new, in: context)
        let m2 = ReadingQueueService.add(second, to: queue, state: .inLine, in: context)
        m1.syncStatus = .synced
        m2.syncStatus = .synced
        mFresh.syncStatus = .synced

        ReadingQueueService.sortIntoLine(mFresh, in: queue, context: context)

        #expect(mFresh.state == .inLine)
        #expect(mFresh.stateWasRecorded)
        #expect(mFresh.syncStatus == .pending)
        #expect(m1.syncStatus == .synced)
        #expect(m2.syncStatus == .synced)

        let after = ReadingQueueFacts.partition(memberships: ReadingQueueService.orderedMemberships(in: queue))
        #expect(after.new.isEmpty)
        #expect(after.inLineAll.map(\.work.title) == ["First", "Second", "Fresh"])
    }

    @Test func derivedTransitionsBetweenInLineWaitingNewChapterAndFinished() throws {
        let context = try makeContext()
        let queue = ReadingQueue(name: "WIPs")
        context.insert(queue)

        let wip = makeWork(title: "Ongoing Fic", author: "Writer", chapters: "3/?", isComplete: false)
        let doneWork = makeWork(title: "Completed Fic", author: "Writer", chapters: "5/5", isComplete: true)
        let manualWIP = makeWork(title: "Manual WIP", author: "Writer", chapters: "2/?", isComplete: false)
        manualWIP.isFinished = true
        context.insert(wip)
        context.insert(doneWork)
        context.insert(manualWIP)

        let wipMembership = ReadingQueueService.add(wip, to: queue, state: .inLine, in: context)
        #expect(wip.knownChapterCount == 3)

        // 1. Unread WIP sits In line.
        var partition = ReadingQueueFacts.partition(memberships: [wipMembership])
        #expect(partition.upNext?.id == wip.id)
        #expect(partition.waiting.isEmpty)
        #expect(partition.upNext?.hasNewChapter == false)

        // 2. Caught up -> Waiting (derived, never stored).
        wip.lastSpineIndex = 2
        wip.lastScrollFraction = 1.0
        partition = ReadingQueueFacts.partition(memberships: [wipMembership])
        #expect(partition.inLineAll.isEmpty)
        #expect(partition.waiting.map(\.id) == [wip.id])
        #expect(wipMembership.stateRaw == "inLine")

        // 3. New chapter posts -> back to In line with "New chapter".
        wip.chapters = "4/?"
        partition = ReadingQueueFacts.partition(memberships: [wipMembership])
        #expect(partition.waiting.isEmpty)
        #expect(partition.upNext?.id == wip.id)
        #expect(partition.upNext?.hasNewChapter == true)

        // 4. Reader catches up on ch 4 -> back to Waiting, mark clears.
        wip.knownChapterCount = wip.postedChapterCount
        wip.lastSpineIndex = 3
        wip.lastScrollFraction = 1.0
        partition = ReadingQueueFacts.partition(memberships: [wipMembership])
        #expect(partition.waiting.map(\.id) == [wip.id])
        #expect(!partition.waiting[0].hasNewChapter)

        // 5. Complete + finished -> Finished (never includes incomplete works marked finished manually).
        doneWork.isFinished = true
        let doneMembership = ReadingQueueService.add(doneWork, to: queue, state: .inLine, in: context)
        let manualMembership = ReadingQueueService.add(manualWIP, to: queue, state: .inLine, in: context)
        partition = ReadingQueueFacts.partition(memberships: [wipMembership, doneMembership, manualMembership])
        #expect(partition.finished.map(\.id) == [doneWork.id])
        #expect(partition.waiting.map(\.id) == [wip.id])
        #expect(partition.inLineAll.map(\.id) == [manualWIP.id])
    }

    @Test func newWIPReturningFromWaitingEvenWhenFinalChapterCompletesItEntersInLine() throws {
        let context = try makeContext()
        let queue = ReadingQueue(name: "Bulk WIP")
        let completedWIP = makeWork(title: "Now Complete", author: "Writer", chapters: "3/?", isComplete: false)
        completedWIP.knownChapterCount = 3
        completedWIP.lastSpineIndex = 2
        completedWIP.lastScrollFraction = 1.0
        context.insert(queue)
        context.insert(completedWIP)

        let membership = ReadingQueueService.add(completedWIP, to: queue, state: .new, in: context)
        var partition = ReadingQueueFacts.partition(memberships: [membership])
        #expect(partition.waiting.map(\.id) == [completedWIP.id])

        // Chapter 4 posts AND completes the work before the user reads chapter 4 -> must enter In line, not New.
        completedWIP.chapters = "4/4"
        completedWIP.isComplete = true
        partition = ReadingQueueFacts.partition(memberships: [membership])
        #expect(partition.waiting.isEmpty)
        #expect(partition.new.isEmpty)
        #expect(partition.finished.isEmpty)
        #expect(partition.inLineAll.map(\.id) == [completedWIP.id])
        #expect(partition.upNext?.hasNewChapter == true)

        // Finishing the completed work moves it to Finished and clears "New chapter".
        completedWIP.isFinished = true
        partition = ReadingQueueFacts.partition(memberships: [membership])
        #expect(partition.inLineAll.isEmpty)
        #expect(partition.finished.map(\.id) == [completedWIP.id])
        #expect(!partition.finished[0].hasNewChapter)
    }

    @Test func homeAndQueueCardUpNextIgnoresNewAndWaitingAndReorderKeepsTrailingSections() throws {
        let context = try makeContext()
        let queue = ReadingQueue(name: "Mixed")
        let newWork = makeWork(title: "New Item")
        let waitingWIP = makeWork(title: "Waiting WIP", chapters: "3/?", isComplete: false)
        waitingWIP.knownChapterCount = 3
        waitingWIP.lastSpineIndex = 2
        waitingWIP.lastScrollFraction = 1.0
        let inLineFirst = makeWork(title: "In Line First")
        let inLineSecond = makeWork(title: "In Line Second")
        context.insert(queue)
        context.insert(newWork)
        context.insert(waitingWIP)
        context.insert(inLineFirst)
        context.insert(inLineSecond)

        _ = ReadingQueueService.add(newWork, to: queue, state: .new, in: context)
        _ = ReadingQueueService.add(waitingWIP, to: queue, state: .inLine, in: context)
        _ = ReadingQueueService.add(inLineFirst, to: queue, state: .inLine, in: context)
        _ = ReadingQueueService.add(inLineSecond, to: queue, state: .inLine, in: context)

        let memberships = ReadingQueueService.orderedMemberships(in: queue)
        let homeSplit = ReadingQueueFacts.upNext(inMemberships: memberships)
        #expect(homeSplit.upNext?.id == inLineFirst.id)
        #expect(homeSplit.inLine.map(\.id) == [inLineSecond.id])

        // Reorder In line while passing non-In-line items in trailingIDs (ReadingQueueBrowser pattern).
        let partition = ReadingQueueFacts.partition(memberships: memberships)
        let trailingIDs = (partition.new + partition.waiting + partition.finished).map(\.work.id)
        ReadingQueueService.reorder([inLineSecond.id, inLineFirst.id] + trailingIDs, in: queue, context: context)
        let afterSplit = ReadingQueueFacts.upNext(inMemberships: ReadingQueueService.orderedMemberships(in: queue))
        #expect(afterSplit.upNext?.id == inLineSecond.id)
        #expect(afterSplit.inLine.map(\.id) == [inLineFirst.id])
    }

    @Test func queueSearchOriginTracksSavedKeywordsAndFilterOnlySearches() throws {
        let context = try makeContext()
        var savedFilters = AO3SearchFilters()
        savedFilters.fandom = "Sherlock (TV)"
        savedFilters.query = "casefic"
        let savedSearch = SavedSearch(name: "Holmes casefic", filters: savedFilters)
        context.insert(savedSearch)

        let fromSaved = SearchView.queueOrigin(
            filters: savedFilters,
            activeSavedSearch: SearchView.ActiveSavedSearch(
                id: savedSearch.id,
                name: savedSearch.name,
                filters: savedSearch.filters
            ),
            savedSearches: [savedSearch]
        )
        #expect(fromSaved == ReadingQueueMembershipOrigin(
            kind: .search,
            searchID: savedSearch.id,
            label: "Holmes casefic"
        ))
        #expect(fromSaved?.displayLine == "From Holmes casefic")

        let keywordOrigin = SearchView.queueOrigin(
            filters: AO3SearchFilters(query: "lighthouse"),
            activeSavedSearch: nil,
            savedSearches: [savedSearch]
        )
        #expect(keywordOrigin?.kind == .search)
        #expect(keywordOrigin?.displayLine == "From “lighthouse”")

        // Filter-only / multi-fandom search with empty keyword still records `.search` origin.
        var filterOnly = AO3SearchFilters()
        filterOnly.fandom = "Fandom A, Fandom B"
        filterOnly.completion = .complete
        let filterOrigin = SearchView.queueOrigin(
            filters: filterOnly,
            activeSavedSearch: nil,
            savedSearches: [savedSearch]
        )
        #expect(filterOrigin?.kind == .search)
        #expect(filterOrigin?.searchID == nil)
        #expect(filterOrigin?.displayLine == "From Fandom A")

        var facetOnly = AO3SearchFilters()
        facetOnly.completion = .complete
        let facetOrigin = SearchView.queueOrigin(
            filters: facetOnly,
            activeSavedSearch: nil,
            savedSearches: []
        )
        #expect(facetOrigin?.kind == .search)
        #expect(facetOrigin?.label == AO3SearchFilters.Completion.complete.title)
    }
}

// Nested under PersistenceGateSuites: `KudosBackupService.restore` acquires
// `PersistenceOperationGate`, so restore tests must serialize under it.
extension PersistenceGateSuites {
    @MainActor
    @Suite(.serialized)
    struct ReadingQueueSectionsBackupTests {
        private func makeContext() throws -> ModelContext {
            let schema = Schema([
                SavedWork.self, Tag.self, Bookmark.self, CustomFont.self, WorkCollection.self,
                ReadingQueue.self, ReadingQueueMembership.self, SavedSearch.self,
                QueueSavedSearchLink.self, SyncTombstone.self, ReadingAnnotation.self,
                ReadingSession.self, ReadingFavorite.self, FandomReadWatermark.self
            ])
            return ModelContext(try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            ))
        }

        private func makeDefaults() throws -> UserDefaults {
            let suite = "ReadingQueueSectionsBackupTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defaults.removePersistentDomain(forName: suite)
            return defaults
        }

        private func makeWork(title: String, author: String, chapters: String, isComplete: Bool) -> SavedWork {
            let work = SavedWork(title: title, author: author)
            work.chapters = chapters
            work.isComplete = isComplete
            return work
        }

        private func strippingMembershipKeys(from contents: KudosBackupContents) throws -> KudosBackupContents {
            var root = try #require(
                JSONSerialization.jsonObject(with: contents.manifestData()) as? [String: Any]
            )
            let rawMemberships = try #require(root["readingQueueMemberships"] as? [[String: Any]])
            root["readingQueueMemberships"] = rawMemberships.map { entry in
                var stripped = entry
                stripped.removeValue(forKey: "stateRaw")
                stripped.removeValue(forKey: "stateWasRecorded")
                stripped.removeValue(forKey: "originKindRaw")
                stripped.removeValue(forKey: "originSearchID")
                stripped.removeValue(forKey: "originLabel")
                return stripped
            }
            let strippedData = try JSONSerialization.data(withJSONObject: root)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let manifest = try decoder.decode(KudosBackupManifest.self, from: strippedData)
            return KudosBackupContents(manifest: manifest)
        }

        @Test func defaultArchiveOmitsStateAndOriginAndLegacyArchiveRestoresInLine() throws {
            let source = try makeContext()
            let queue = ReadingQueue(name: "DefaultOnly")
            let work = makeWork(title: "Default", author: "A", chapters: "1/1", isComplete: true)
            source.insert(queue)
            source.insert(work)
            let membership = ReadingQueueService.add(work, to: queue, state: .inLine, origin: nil, in: source)
            try source.save()

            let contents = try KudosBackupService.makeContents(
                works: [work],
                bookmarks: [],
                fonts: [],
                readingQueues: [queue],
                savedSearches: [],
                defaults: try makeDefaults()
            )
            #expect(contents.manifest.version == 8)

            let rawJSON = try #require(
                JSONSerialization.jsonObject(with: contents.manifestData()) as? [String: Any]
            )
            let rawMemberships = try #require(rawJSON["readingQueueMemberships"] as? [[String: Any]])
            let rawDefault = try #require(
                rawMemberships.first { ($0["id"] as? String) == membership.id.uuidString }
            )
            #expect(rawDefault["stateRaw"] == nil)
            #expect(rawDefault["stateWasRecorded"] == nil)
            #expect(rawDefault["originKindRaw"] == nil)
            #expect(rawDefault["originSearchID"] == nil)
            #expect(rawDefault["originLabel"] == nil)

            let target = try makeContext()
            let stripped = try strippingMembershipKeys(from: contents)
            _ = try KudosBackupService.restore(
                stripped,
                into: target,
                defaults: try makeDefaults(),
                mode: .replaceLibrary
            )
            let restored = try #require(try target.fetch(FetchDescriptor<ReadingQueueMembership>()).first)
            #expect(restored.state == .inLine)
            #expect(!restored.stateWasRecorded)
            #expect(restored.origin == nil)
        }

        @Test func reconcileWithStrippedKeysPreservesNewStateAndOrigin() throws {
            let target = try makeContext()
            let queue = ReadingQueue(name: "Synced")
            let search = SavedSearch(name: "Holmes casefic", filters: AO3SearchFilters(query: "holmes"))
            let work = makeWork(title: "Mystery", author: "B", chapters: "2/2", isComplete: true)
            target.insert(queue)
            target.insert(search)
            target.insert(work)

            let origin = ReadingQueueMembershipOrigin(
                kind: .search,
                searchID: search.id,
                label: search.name
            )
            let localMembership = ReadingQueueService.add(
                work,
                to: queue,
                state: .new,
                origin: origin,
                in: target
            )
            let t1 = Date(timeIntervalSince1970: 1_000)
            localMembership.lastModifiedAt = t1
            work.lastModifiedAt = t1
            queue.lastMembershipChangedAt = t1
            try target.save()

            // Device B (Android / older iOS) edits note at T2 > T1 and strips new membership keys.
            let t2 = Date(timeIntervalSince1970: 2_000)
            let androidSource = try makeContext()
            let androidQueue = ReadingQueue(id: queue.id, name: queue.name, kind: .custom, sortOrder: 0)
            let androidWork = makeWork(title: work.title, author: work.author, chapters: "2/2", isComplete: true)
            androidWork.id = work.id
            androidSource.insert(androidQueue)
            androidSource.insert(androidWork)
            let androidMembership = ReadingQueueMembership(
                id: localMembership.id,
                queue: androidQueue,
                work: androidWork,
                queuedAt: localMembership.queuedAt,
                sortOrderInQueue: 0,
                note: "Edited on Android"
            )
            androidMembership.lastModifiedAt = t2
            androidWork.lastModifiedAt = t2
            androidQueue.lastMembershipChangedAt = t2
            androidSource.insert(androidMembership)
            try androidSource.save()

            let androidRawContents = try KudosBackupService.makeContents(
                works: [androidWork],
                bookmarks: [],
                fonts: [],
                readingQueues: [androidQueue],
                savedSearches: [],
                defaults: try makeDefaults()
            )
            let strippedManifest = try strippingMembershipKeys(from: androidRawContents)

            _ = try KudosBackupService.restore(
                strippedManifest,
                into: target,
                defaults: try makeDefaults(),
                mode: .reconcile
            )
            let afterAndroidSync = try #require(
                try target.fetch(FetchDescriptor<ReadingQueueMembership>()).first { $0.id == localMembership.id }
            )
            // Newer note won via LWW, while `.new`, `stateWasRecorded`, and `origin` survived stripped keys.
            #expect(afterAndroidSync.note == "Edited on Android")
            #expect(afterAndroidSync.state == .new)
            #expect(afterAndroidSync.stateWasRecorded)
            #expect(afterAndroidSync.origin == origin)
        }

        @Test func reconcileWithRecordedSortAppliesInLineAndPreservesOrigin() throws {
            let target = try makeContext()
            let queue = ReadingQueue(name: "Synced")
            let search = SavedSearch(name: "Holmes casefic", filters: AO3SearchFilters(query: "holmes"))
            let work = makeWork(title: "Mystery", author: "B", chapters: "2/2", isComplete: true)
            target.insert(queue)
            target.insert(search)
            target.insert(work)

            let origin = ReadingQueueMembershipOrigin(
                kind: .search,
                searchID: search.id,
                label: search.name
            )
            let localMembership = ReadingQueueService.add(
                work,
                to: queue,
                state: .new,
                origin: origin,
                in: target
            )
            let t1 = Date(timeIntervalSince1970: 1_000)
            localMembership.lastModifiedAt = t1
            work.lastModifiedAt = t1
            queue.lastMembershipChangedAt = t1
            try target.save()

            // A T-528 peer explicitly runs `sortIntoLine` at T2 > T1 -> records stateRaw + stateWasRecorded.
            let t2 = Date(timeIntervalSince1970: 2_000)
            let peerSource = try makeContext()
            let peerQueue = ReadingQueue(id: queue.id, name: queue.name, kind: .custom, sortOrder: 0)
            let peerWork = makeWork(title: work.title, author: work.author, chapters: "2/2", isComplete: true)
            peerWork.id = work.id
            let peerSearch = SavedSearch(name: search.name, filters: search.filters)
            peerSearch.id = search.id
            peerSource.insert(peerQueue)
            peerSource.insert(peerWork)
            peerSource.insert(peerSearch)
            let peerMembership = ReadingQueueService.add(
                peerWork,
                to: peerQueue,
                state: .new,
                origin: origin,
                in: peerSource
            )
            peerMembership.id = localMembership.id
            ReadingQueueService.sortIntoLine(peerMembership, in: peerQueue, context: peerSource)
            peerMembership.lastModifiedAt = t2
            peerQueue.lastMembershipChangedAt = t2
            try peerSource.save()

            let peerContents = try KudosBackupService.makeContents(
                works: [peerWork],
                bookmarks: [],
                fonts: [],
                readingQueues: [peerQueue],
                savedSearches: [peerSearch],
                defaults: try makeDefaults()
            )
            _ = try KudosBackupService.restore(
                peerContents,
                into: target,
                defaults: try makeDefaults(),
                mode: .reconcile
            )
            let afterRecordedSort = try #require(
                try target.fetch(FetchDescriptor<ReadingQueueMembership>()).first { $0.id == localMembership.id }
            )
            #expect(afterRecordedSort.state == .inLine)
            #expect(afterRecordedSort.stateWasRecorded)
            #expect(afterRecordedSort.origin == origin)
        }
    }
}
