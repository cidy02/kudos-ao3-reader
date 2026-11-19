import Foundation
import SwiftData
import Testing
@testable import Kudos

/// T-528: A reading queue in four states (New, In line, Waiting, Finished),
/// membership origin, single-vs-bulk add states, and derived transitions.
@MainActor
@Suite(.serialized)
struct ReadingQueueSectionsTests {
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
        #expect(membership.origin == nil)
        #expect(membership.originDisplayLine == nil)

        membership.stateRaw = "unknownFutureState"
        #expect(membership.state == .inLine)

        membership.state = .inLine
        let partition = ReadingQueueFacts.partition(memberships: [membership])
        #expect(partition.new.isEmpty)
        #expect(partition.upNext?.id == work.id)
        #expect(partition.inLineRest.isEmpty)
        #expect(partition.waiting.isEmpty)
        #expect(partition.finished.isEmpty)
    }

    @Test func singleAddStartsInLineWhileBulkAddStartsNewWithOrigin() throws {
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

        // Single add via swipe quickAdd -> In line + origin.
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

        // Bulk append -> New + preserves origin and existing In line items.
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

        let bulkMembership = try #require(
            ReadingQueueService.orderedMemberships(in: queue).first { $0.work?.id == bulkOne.id }
        )
        #expect(bulkMembership.state == .new)
        #expect(bulkMembership.originDisplayLine == "From “lighthouse”")

        // Repeat add must not demote an already In line item back to New.
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

        let before = ReadingQueueFacts.partition(memberships: ReadingQueueService.orderedMemberships(in: queue))
        #expect(before.new.map(\.work.title) == ["Fresh"])
        #expect(before.inLineAll.map(\.work.title) == ["First", "Second"])

        ReadingQueueService.sortIntoLine(mFresh, in: queue, context: context)

        #expect(mFresh.state == .inLine)
        #expect(mFresh.syncStatus == .pending)
        // Untouched items keep their sync state clean.
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
        let manuallyFinishedWIP = makeWork(title: "Manual WIP", author: "Writer", chapters: "2/?", isComplete: false)
        manuallyFinishedWIP.isFinished = true
        context.insert(wip)
        context.insert(doneWork)
        context.insert(manuallyFinishedWIP)

        let wipMembership = ReadingQueueService.add(wip, to: queue, state: .inLine, in: context)
        #expect(wip.knownChapterCount == 3)

        // 1. Unread WIP sits In line.
        var partition = ReadingQueueFacts.partition(memberships: [wipMembership])
        #expect(partition.upNext?.id == wip.id)
        #expect(partition.waiting.isEmpty)
        #expect(partition.upNext?.hasNewChapter == false)

        // 2. Reader reaches the end of all 3 posted chapters -> Waiting (derived, never stored).
        wip.lastSpineIndex = 2
        wip.lastScrollFraction = 1.0
        partition = ReadingQueueFacts.partition(memberships: [wipMembership])
        #expect(partition.inLineAll.isEmpty)
        #expect(partition.waiting.map(\.id) == [wip.id])
        #expect(wipMembership.stateRaw == "inLine")
        #expect(!partition.waiting[0].hasNewChapter)

        // 3. New chapter posts (`postedChapterCount` grows 3 -> 4) -> returns to In line with "New chapter".
        wip.chapters = "4/?"
        partition = ReadingQueueFacts.partition(memberships: [wipMembership])
        #expect(partition.waiting.isEmpty)
        #expect(partition.upNext?.id == wip.id)
        #expect(partition.upNext?.hasNewChapter == true)
        #expect(wipMembership.stateRaw == "inLine")

        // 4. Reader sees/updates EPUB and finishes chapter 4 -> back to Waiting, mark clears.
        wip.knownChapterCount = wip.postedChapterCount
        wip.lastSpineIndex = 3
        wip.lastScrollFraction = 1.0
        partition = ReadingQueueFacts.partition(memberships: [wipMembership])
        #expect(partition.inLineAll.isEmpty)
        #expect(partition.waiting.map(\.id) == [wip.id])
        #expect(!partition.waiting[0].hasNewChapter)

        // 5. Complete + finished -> Finished (never includes incomplete works marked finished manually).
        doneWork.isFinished = true
        let doneMembership = ReadingQueueService.add(doneWork, to: queue, state: .inLine, in: context)
        let manualMembership = ReadingQueueService.add(manuallyFinishedWIP, to: queue, state: .inLine, in: context)
        partition = ReadingQueueFacts.partition(memberships: [wipMembership, doneMembership, manualMembership])
        #expect(partition.finished.map(\.id) == [doneWork.id])
        #expect(partition.waiting.map(\.id) == [wip.id])
        #expect(partition.inLineAll.map(\.id) == [manuallyFinishedWIP.id])
    }

    @Test func newWIPWithNewChapterReturnsFromWaitingToInLineByDerivation() throws {
        let context = try makeContext()
        let queue = ReadingQueue(name: "Bulk WIP")
        let wip = makeWork(title: "Caught Up Then New", author: "Writer", chapters: "2/?", isComplete: false)
        wip.knownChapterCount = 2
        wip.lastSpineIndex = 2 // 1 front-matter spine + 2 chapters
        wip.lastScrollFraction = 1.0
        context.insert(queue)
        context.insert(wip)

        let membership = ReadingQueueService.add(wip, to: queue, state: .new, in: context)
        var partition = ReadingQueueFacts.partition(memberships: [membership])
        #expect(partition.waiting.map(\.id) == [wip.id])

        // Chapter 3 posts while lastSpineIndex + 1 == 3 would match chapter count without `!hasUpdate`.
        wip.chapters = "3/?"
        partition = ReadingQueueFacts.partition(memberships: [membership])
        #expect(partition.waiting.isEmpty)
        #expect(partition.new.isEmpty)
        #expect(partition.inLineAll.map(\.id) == [wip.id])
        #expect(partition.upNext?.hasNewChapter == true)
    }

    @Test func queueSearchOriginTracksSavedSearchesAndAdHocQueries() throws {
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
        #expect(keywordOrigin?.searchID == nil)
        #expect(keywordOrigin?.displayLine == "From “lighthouse”")
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
            #expect(rawDefault["originKindRaw"] == nil)
            #expect(rawDefault["originSearchID"] == nil)
            #expect(rawDefault["originLabel"] == nil)

            let legacyJSON = """
            {
              "id": "\(UUID().uuidString)",
              "queueID": "\(queue.id.uuidString)",
              "workID": "\(work.id.uuidString)",
              "queuedAt": "2026-10-01T00:00:00Z",
              "sortOrderInQueue": 0,
              "note": ""
            }
            """
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decodedLegacy = try decoder.decode(
                KudosBackupReadingQueueMembership.self,
                from: Data(legacyJSON.utf8)
            )
            #expect(decodedLegacy.restoredState == .inLine)
            #expect(decodedLegacy.restoredOrigin == nil)
        }

        @Test func stateAndOriginRoundTripThroughBackupAndReconcileSync() throws {
            let source = try makeContext()
            let queue = ReadingQueue(name: "Synced")
            let search = SavedSearch(name: "Lighthouses", filters: AO3SearchFilters(query: "lighthouse"))
            let newWork = makeWork(title: "New", author: "B", chapters: "2/2", isComplete: true)
            source.insert(queue)
            source.insert(search)
            source.insert(newWork)

            let origin = ReadingQueueMembershipOrigin(
                kind: .search,
                searchID: search.id,
                label: search.name
            )
            let newMembership = ReadingQueueService.add(
                newWork,
                to: queue,
                state: .new,
                origin: origin,
                in: source
            )
            newMembership.lastModifiedAt = Date(timeIntervalSince1970: 1_000)
            try source.save()

            let contents = try KudosBackupService.makeContents(
                works: [newWork],
                bookmarks: [],
                fonts: [],
                readingQueues: [queue],
                savedSearches: [search],
                defaults: try makeDefaults()
            )

            let target = try makeContext()
            _ = try KudosBackupService.restore(
                contents,
                into: target,
                defaults: try makeDefaults(),
                mode: .replaceLibrary
            )
            let restored = try #require(
                try target.fetch(FetchDescriptor<ReadingQueueMembership>()).first { $0.id == newMembership.id }
            )
            #expect(restored.state == .new)
            #expect(restored.origin == origin)

            // Reconcile LWW applies newer `.inLine` sort update over local `.new` membership.
            ReadingQueueService.sortIntoLine(newMembership, in: queue, context: source)
            newMembership.lastModifiedAt = Date(timeIntervalSince1970: 2_000)
            try source.save()
            let sortedContents = try KudosBackupService.makeContents(
                works: [newWork],
                bookmarks: [],
                fonts: [],
                readingQueues: [queue],
                savedSearches: [search],
                defaults: try makeDefaults()
            )
            _ = try KudosBackupService.restore(
                sortedContents,
                into: target,
                defaults: try makeDefaults(),
                mode: .reconcile
            )
            let reconciled = try #require(
                try target.fetch(FetchDescriptor<ReadingQueueMembership>()).first { $0.id == newMembership.id }
            )
            #expect(reconciled.state == .inLine)
            #expect(reconciled.origin == origin)
        }
    }
}
