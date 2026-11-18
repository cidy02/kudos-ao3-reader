import Foundation
import SwiftData
import Testing
@testable import Kudos

/// T-532 (`Queue-TimeFit.dc.html`): time buckets, unread-share calculation,
/// cross-queue deduplication, offline-first ordering, and privacy rules.
@MainActor
@Suite(.serialized)
struct WhatFitsTests {
    @Test func bucketTitlesMatchBoardOrderAndDefault() {
        #expect(WhatFitsBucket.allCases.map(\.title) == ["15 min", "30 min", "1 h", "2 h +"])
        #expect(WhatFitsBucket.defaultSelection == .thirtyMinutes)
    }

    @Test func bucketEdgesIncludeExactMatchAndExcludeOneMinuteOver() throws {
        let context = try makeContext()
        let queue = ReadingQueueService.createQueue(named: "Edges", in: context)

        // 200 wpm: 3,000 = 15 min, 3,200 = 16 min, 6,000 = 30 min, 6,200 = 31 min,
        // 12,000 = 60 min, 12,200 = 61 min, 24,000 = 120 min, 30,000 = 150 min.
        let works = [
            makeWork(in: context, title: "15m", words: 3_000),
            makeWork(in: context, title: "16m", words: 3_200),
            makeWork(in: context, title: "30m", words: 6_000),
            makeWork(in: context, title: "31m", words: 6_200),
            makeWork(in: context, title: "60m", words: 12_000),
            makeWork(in: context, title: "61m", words: 12_200),
            makeWork(in: context, title: "120m", words: 24_000),
            makeWork(in: context, title: "150m", words: 30_000),
        ]
        for work in works {
            ReadingQueueService.add(work, to: queue, in: context)
        }

        func titles(for bucket: WhatFitsBucket) -> [String] {
            WhatFitsPlanner.plan(
                queues: [queue],
                bucket: bucket,
                isVisible: { _ in true },
                fileExists: { _ in true }
            ).startAndFinish.map(\.work.title)
        }

        #expect(titles(for: .fifteenMinutes) == ["15m"])
        #expect(titles(for: .thirtyMinutes) == ["15m", "16m", "30m"])
        #expect(titles(for: .oneHour) == ["15m", "16m", "30m", "31m", "60m"])
        #expect(titles(for: .twoHoursPlus) == ["15m", "16m", "30m", "31m", "60m", "61m", "120m", "150m"])
    }

    @Test func unreadShareSplitsFinishNowFromStartAndFinish() throws {
        let context = try makeContext()
        let queue = ReadingQueueService.createQueue(named: "Mix", in: context)

        // 10,000 words = 50 min total; 70% read => 15.0 min left (fits 15 min despite float 1 - 0.7)
        let exact15Left = makeWork(in: context, title: "Exact15Left", words: 10_000)
        exact15Left.readiumLocator = #"{"href":"c1.xhtml","locations":{"totalProgression":0.7}}"#

        // 10,000 words = 50 min total; 68% read => 16.0 min left (1 min over 15 min)
        let sixteenLeft = makeWork(in: context, title: "SixteenLeft", words: 10_000)
        sixteenLeft.readiumLocator = #"{"href":"c1.xhtml","locations":{"totalProgression":0.68}}"#

        // Legacy chapter progress: 5/10 chapters at spine index 4 => 50% read => 15 min left of 6,000 words
        let legacyHalf = makeWork(in: context, title: "LegacyHalf", words: 6_000)
        legacyHalf.chapters = "5/10"
        legacyHalf.lastSpineIndex = 4

        // Multi-chapter unread work must NOT leak a 1/10 chapter fraction before reading starts
        let unreadMulti = makeWork(in: context, title: "UnreadMulti", words: 3_600)
        unreadMulti.chapters = "5/10"

        // Finished work must never appear
        let finished = makeWork(in: context, title: "Done", words: 1_000)
        finished.isFinished = true

        for work in [exact15Left, sixteenLeft, legacyHalf, unreadMulti, finished] {
            ReadingQueueService.add(work, to: queue, in: context)
        }

        let plan15 = WhatFitsPlanner.plan(
            queues: [queue],
            bucket: .fifteenMinutes,
            isVisible: { _ in true },
            fileExists: { _ in true }
        )
        #expect(plan15.finishInThisSitting.map(\.work.title) == ["Exact15Left", "LegacyHalf"])
        #expect(plan15.startAndFinish.isEmpty)

        let plan30 = WhatFitsPlanner.plan(
            queues: [queue],
            bucket: .thirtyMinutes,
            isVisible: { _ in true },
            fileExists: { _ in true }
        )
        #expect(plan30.finishInThisSitting.map(\.work.title) == ["Exact15Left", "LegacyHalf", "SixteenLeft"])
        #expect(plan30.startAndFinish.map(\.work.title) == ["UnreadMulti"])
    }

    @Test func workInMultipleQueuesAppearsOnceWithCombinedQueueNames() throws {
        let context = try makeContext()
        let savedForLater = ReadingQueueService.ensureSavedForLaterQueue(in: context)
        let first = ReadingQueueService.createQueue(named: "Summer Reading", in: context)
        first.sortOrder = 0
        let second = ReadingQueueService.createQueue(named: "For the Train", in: context)
        second.sortOrder = 1

        let shared = makeWork(in: context, title: "Shared", words: 2_000) // 10 min
        ReadingQueueService.add(shared, to: savedForLater, in: context)
        ReadingQueueService.add(shared, to: first, in: context)
        ReadingQueueService.add(shared, to: second, in: context)

        let plan = WhatFitsPlanner.plan(
            queues: [savedForLater, second, first],
            bucket: .thirtyMinutes,
            isVisible: { _ in true },
            fileExists: { _ in true }
        )

        #expect(plan.queueCount == 3)
        #expect(plan.finishInThisSitting.isEmpty)
        #expect(plan.startAndFinish.count == 1)
        #expect(plan.startAndFinish[0].work.id == shared.id)
        // Custom queues precede Want to Read in queue-name attribution
        #expect(plan.startAndFinish[0].queueNames == ["Summer Reading", "For the Train", "Want to Read"])
    }

    @Test func worksWithoutWordCountAreExcludedRatherThanGuessed() throws {
        let context = try makeContext()
        let queue = ReadingQueueService.createQueue(named: "NoWords", in: context)

        let unstartedNoWords = makeWork(in: context, title: "Unstarted", words: 0)
        let startedNoWords = makeWork(in: context, title: "Started", words: 0)
        startedNoWords.readiumLocator = #"{"href":"c1.xhtml","locations":{"totalProgression":0.5}}"#
        let known = makeWork(in: context, title: "Known", words: 2_000)

        for work in [unstartedNoWords, startedNoWords, known] {
            ReadingQueueService.add(work, to: queue, in: context)
        }

        let plan = WhatFitsPlanner.plan(
            queues: [queue],
            bucket: .twoHoursPlus,
            isVisible: { _ in true },
            fileExists: { _ in true }
        )

        #expect(plan.finishInThisSitting.isEmpty)
        #expect(plan.startAndFinish.map(\.work.title) == ["Known"])
    }

    @Test func offlineWorksOrderBeforeDownloadsThenShortestFirst() throws {
        let context = try makeContext()
        let queue = ReadingQueueService.createQueue(named: "Order", in: context)

        let offlineLong = makeWork(in: context, title: "Offline25", words: 5_000, hasEPUB: true)
        let offlineShort = makeWork(in: context, title: "Offline8", words: 1_600, hasEPUB: true)
        let needsDownloadShort = makeWork(in: context, title: "Remote5", words: 1_000, hasEPUB: false)
        let missingOnDisk = makeWork(in: context, title: "Missing10", words: 2_000, hasEPUB: true)

        for work in [offlineLong, needsDownloadShort, missingOnDisk, offlineShort] {
            ReadingQueueService.add(work, to: queue, in: context)
        }

        let plan = WhatFitsPlanner.plan(
            queues: [queue],
            bucket: .thirtyMinutes,
            isVisible: { _ in true },
            fileExists: { url in url != missingOnDisk.fileURL }
        )

        #expect(plan.startAndFinish.map(\.work.title) == [
            "Offline8", "Offline25", "Remote5", "Missing10",
        ])
        #expect(plan.startAndFinish.map(\.isOffline) == [true, true, false, false])
    }

    @Test func queueHeaderAndWhatFitsReadTheSameTimeLeftValue() throws {
        let context = try makeContext()
        let queue = ReadingQueueService.createQueue(named: "SharedRule", in: context)

        let finished = makeWork(in: context, title: "Finished", words: 12_000)
        finished.isFinished = true
        let reading = makeWork(in: context, title: "Reading", words: 10_000) // 50 min * 0.4 = 20 min left
        reading.readiumLocator = #"{"href":"c1.xhtml","locations":{"totalProgression":0.6}}"#
        let unread = makeWork(in: context, title: "Unread", words: 8_000) // 40 min left

        for work in [finished, reading, unread] {
            ReadingQueueService.add(work, to: queue, in: context)
        }

        let plan = WhatFitsPlanner.plan(
            queues: [queue],
            bucket: .twoHoursPlus,
            isVisible: { _ in true },
            fileExists: { _ in true }
        )
        let whatFitsTotal = plan.allEntries.reduce(0.0) { $0 + $1.minutesLeft }
        let queueWorks = ReadingQueueService.orderedWorks(in: queue)
        let headerMinutes = ReadingQueueFacts.remainingMinutes(for: queueWorks)

        #expect(headerMinutes == whatFitsTotal)
        #expect(headerMinutes == 60)
        #expect(ReadingQueueFacts.headerDetail(for: queueWorks, offlineCount: 3)
            == "3 works · about 1 h · all offline")
    }

    @Test func privacyHideModeExcludesUnrevealedMatureWorksAndFlagsHiddenFits() throws {
        let context = try makeContext()
        let queue = ReadingQueueService.createQueue(named: "Privacy", in: context)

        let mature = makeWork(in: context, title: "Mature", words: 2_000)
        mature.rating = "Explicit"
        let teen = makeWork(in: context, title: "Teen", words: 4_000)
        teen.rating = "Teen And Up Audiences"

        ReadingQueueService.add(mature, to: queue, in: context)
        ReadingQueueService.add(teen, to: queue, in: context)

        let gate = PrivacyGate()
        let hiddenPlan = WhatFitsPlanner.plan(
            queues: [queue],
            bucket: .fifteenMinutes,
            isVisible: { !gate.isHidden($0, enabled: true, mode: .hide) },
            fileExists: { _ in true }
        )
        #expect(hiddenPlan.isEmpty)
        #expect(hiddenPlan.hasHiddenMatureFits)

        let blurPlan = WhatFitsPlanner.plan(
            queues: [queue],
            bucket: .thirtyMinutes,
            isVisible: { !gate.isHidden($0, enabled: true, mode: .obscure) },
            fileExists: { _ in true }
        )
        #expect(blurPlan.startAndFinish.map(\.work.title) == ["Mature", "Teen"])
        #expect(!blurPlan.hasHiddenMatureFits)
    }

    @Test func deletedQueuesAndMembershipsAreExcluded() throws {
        let context = try makeContext()
        let active = ReadingQueueService.createQueue(named: "Active", in: context)
        let deletedQueue = ReadingQueueService.createQueue(named: "DeletedQueue", in: context)
        deletedQueue.isPendingDeletion = true

        let deletedWork = makeWork(in: context, title: "DeletedWork", words: 2_000)
        deletedWork.isPendingDeletion = true
        let deletedMembershipWork = makeWork(in: context, title: "RemovedMembership", words: 2_000)
        let deletedQueueWork = makeWork(in: context, title: "InDeletedQueue", words: 2_000)
        let liveWork = makeWork(in: context, title: "LiveWork", words: 2_000)

        ReadingQueueService.add(deletedWork, to: active, in: context)
        let removedMembership = ReadingQueueService.add(deletedMembershipWork, to: active, in: context)
        removedMembership.isPendingDeletion = true
        ReadingQueueService.add(liveWork, to: active, in: context)
        ReadingQueueService.add(deletedQueueWork, to: deletedQueue, in: context)

        let plan = WhatFitsPlanner.plan(
            queues: [active, deletedQueue],
            bucket: .thirtyMinutes,
            isVisible: { _ in true },
            fileExists: { _ in true }
        )

        #expect(plan.queueCount == 1)
        #expect(plan.startAndFinish.map(\.work.title) == ["LiveWork"])
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, QueueSavedSearchLink.self, SyncTombstone.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func makeWork(
        in context: ModelContext,
        title: String,
        words: Int,
        hasEPUB: Bool = true
    ) -> SavedWork {
        let work = SavedWork(title: title, author: "Writer")
        work.wordCount = words
        work.hasEPUB = hasEPUB
        context.insert(work)
        return work
    }
}
