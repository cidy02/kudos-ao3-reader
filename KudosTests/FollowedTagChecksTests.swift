import Foundation
import SwiftData
import Testing
@testable import Kudos

private final class FollowedTagProbe: URLProtocol, @unchecked Sendable {
    struct StubResponse: Sendable {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
    }

    private static let lock = NSLock()
    private static var requests: [URLRequest] = []
    private static var handler: ((URLRequest, Int) -> StubResponse)?

    static func reset(handler: @escaping (URLRequest, Int) -> StubResponse) {
        lock.lock()
        requests = []
        self.handler = handler
        lock.unlock()
    }

    static var sent: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let index = Self.requests.count
        let handler = Self.handler
        Self.lock.unlock()

        let stub = handler?(request, index) ?? StubResponse(statusCode: 200, headers: [:], body: Data())
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
@MainActor
struct FollowedTagChecksTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self, WorkCollection.self,
            ReadingQueue.self, ReadingQueueMembership.self, SavedSearch.self,
            QueueSavedSearchLink.self, SyncTombstone.self, ReadingAnnotation.self,
            ReadingSession.self, ReadingFavorite.self, FandomReadWatermark.self,
            FollowedTag.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func sampleFeed(entries: [AO3TagFeedEntry] = []) -> AO3TagFeed {
        AO3TagFeed(
            feedID: "tag:archiveofourown.org,2005:/tags/27785/feed",
            title: "AO3 works tagged 'Doctor Who (2005)'",
            updatedAt: entries.first?.publishedAt,
            entries: entries
        )
    }

    private func makeEntry(
        workID: Int,
        publishedAt: Date,
        chapters: String = "1/1",
        rating: String = "Teen And Up Audiences",
        title: String? = nil
    ) -> AO3TagFeedEntry {
        AO3TagFeedEntry(
            id: "tag:archiveofourown.org,2005:Work/\(workID)",
            workID: workID,
            title: title ?? "Work \(workID)",
            authors: ["author_\(workID)"],
            authorIdentities: [],
            publishedAt: publishedAt,
            updatedAt: publishedAt,
            url: URL(string: "https://archiveofourown.org/works/\(workID)"),
            summary: "Summary",
            words: 1500,
            chapters: chapters,
            isComplete: AO3TagFeedEntry.isCompleteChapters(chapters),
            language: "English",
            rating: rating,
            warnings: [],
            categories: [],
            fandoms: ["Fandom"],
            characters: [],
            relationships: [],
            freeforms: []
        )
    }

    private func isolatedDefaults() throws -> (defaults: UserDefaults, name: String) {
        let name = "FollowedTagChecksTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    @Test func noRequestUnlessHomeOrSubscriptionsIsShowingAndHomeRespectsSwitch() async {
        struct MockTag {
            let id: Int
            let showOnHome: Bool
            var lastCheckedAt: Date?
        }

        let tags = [
            MockTag(id: 1, showOnHome: true, lastCheckedAt: nil),
            MockTag(id: 2, showOnHome: false, lastCheckedAt: nil)
        ]

        // Neither screen visible -> 0 fetches.
        var inactiveFetches: [Int] = []
        await FollowedTagChecks.run(
            tags: tags,
            screen: .home,
            showOnHome: \.showOnHome,
            checkedAt: \.lastCheckedAt,
            isScreenActive: { false },
            isRateLimitHeld: { _ in false },
            now: Date.init,
            sleep: { _ in },
            attempt: { _, _ in true },
            fetch: { tag in inactiveFetches.append(tag.id); return sampleFeed() },
            received: { _, _, _ in }
        )
        #expect(inactiveFetches.isEmpty)

        // Home screen only fetches tags with showOnHome == true.
        var homeFetches: [Int] = []
        await FollowedTagChecks.run(
            tags: tags,
            screen: .home,
            showOnHome: \.showOnHome,
            checkedAt: \.lastCheckedAt,
            isScreenActive: { true },
            isRateLimitHeld: { _ in false },
            now: Date.init,
            sleep: { _ in },
            attempt: { _, _ in true },
            fetch: { tag in homeFetches.append(tag.id); return sampleFeed() },
            received: { _, _, _ in }
        )
        #expect(homeFetches == [1])

        // Subscriptions screen checks all tags regardless of showOnHome.
        var subscriptionsFetches: [Int] = []
        await FollowedTagChecks.run(
            tags: tags,
            screen: .subscriptions,
            showOnHome: \.showOnHome,
            checkedAt: \.lastCheckedAt,
            isScreenActive: { true },
            isRateLimitHeld: { _ in false },
            now: Date.init,
            sleep: { _ in },
            attempt: { _, _ in true },
            fetch: { tag in subscriptionsFetches.append(tag.id); return sampleFeed() },
            received: { _, _, _ in }
        )
        #expect(subscriptionsFetches == [1, 2])
    }

    @Test func sixHourCooldownAppliesAfterFailureAndRefreshOverridesCooldown() async {
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        var currentNow = base
        var checkedAt: [Int: Date] = [:]
        var fetchedIDs: [Int] = []

        // Pass 1 fails on 503 and stamps lastCheckedAt.
        await FollowedTagChecks.run(
            tags: [10],
            screen: .subscriptions,
            showOnHome: { _ in true },
            checkedAt: { checkedAt[$0] },
            isScreenActive: { true },
            isRateLimitHeld: { _ in false },
            now: { currentNow },
            sleep: { _ in },
            attempt: { id, started in checkedAt[id] = started; return true },
            fetch: { id in fetchedIDs.append(id); throw AO3Error.server(status: 503) },
            received: { _, _, _ in }
        )
        #expect(fetchedIDs == [10])
        #expect(checkedAt[10] == base)

        // 5h59m later -> skipped due to failed attempt stamp.
        currentNow = base.addingTimeInterval(6 * 3600 - 60)
        await FollowedTagChecks.run(
            tags: [10],
            screen: .subscriptions,
            showOnHome: { _ in true },
            checkedAt: { checkedAt[$0] },
            isScreenActive: { true },
            isRateLimitHeld: { _ in false },
            now: { currentNow },
            sleep: { _ in },
            attempt: { id, started in checkedAt[id] = started; return true },
            fetch: { id in fetchedIDs.append(id); return sampleFeed() },
            received: { _, _, _ in }
        )
        #expect(fetchedIDs == [10])

        // Pull to refresh overrides cooldown inside the 6h window.
        await FollowedTagChecks.run(
            tags: [10],
            screen: .subscriptions,
            showOnHome: { _ in true },
            checkedAt: { checkedAt[$0] },
            ignoringCooldown: true,
            isScreenActive: { true },
            isRateLimitHeld: { _ in false },
            now: { currentNow },
            sleep: { _ in },
            attempt: { id, started in checkedAt[id] = started; return true },
            fetch: { id in fetchedIDs.append(id); return sampleFeed() },
            received: { _, _, _ in }
        )
        #expect(fetchedIDs == [10, 10])

        // Regular check waits until >= 6h since last stamp.
        currentNow = currentNow.addingTimeInterval(6 * 3600)
        await FollowedTagChecks.run(
            tags: [10],
            screen: .subscriptions,
            showOnHome: { _ in true },
            checkedAt: { checkedAt[$0] },
            isScreenActive: { true },
            isRateLimitHeld: { _ in false },
            now: { currentNow },
            sleep: { _ in },
            attempt: { id, started in checkedAt[id] = started; return true },
            fetch: { id in fetchedIDs.append(id); return sampleFeed() },
            received: { _, _, _ in }
        )
        #expect(fetchedIDs == [10, 10, 10])
    }

    @Test func sequentialOrderEnforcesAtLeastThreeSecondGapAndCancelsOnExit() async {
        let t0 = Date(timeIntervalSince1970: 1_750_000_000)
        var currentNow = t0
        var sleepWaits: [TimeInterval] = []
        var fetchedIDs: [Int] = []
        var inFlight = 0
        var peakInFlight = 0

        let items: [(id: Int, checked: Date?)] = [
            (1, t0.addingTimeInterval(-8 * 3600)),
            (2, nil),
            (3, t0.addingTimeInterval(-10 * 3600))
        ]

        await FollowedTagChecks.run(
            tags: items,
            screen: .subscriptions,
            showOnHome: { _ in true },
            checkedAt: \.checked,
            isScreenActive: { true },
            isRateLimitHeld: { _ in false },
            now: { currentNow },
            sleep: { seconds in
                sleepWaits.append(seconds)
                currentNow = currentNow.addingTimeInterval(seconds)
            },
            attempt: { _, _ in true },
            fetch: { item in
                inFlight += 1
                peakInFlight = max(peakInFlight, inFlight)
                fetchedIDs.append(item.id)
                currentNow = currentNow.addingTimeInterval(0.5)
                await Task.yield()
                inFlight -= 1
                return sampleFeed()
            },
            received: { _, _, _ in }
        )

        #expect(peakInFlight == 1)
        #expect(fetchedIDs == [2, 3, 1])
        #expect(sleepWaits.count == 2)
        #expect(sleepWaits.allSatisfy { $0 >= 2.5 }) // 0.5s simulated fetch + 2.5s sleep = 3.0s start-to-start.

        // Leaving the screen after tag 1 cancels the remaining unstarted tags.
        var active = true
        var exitFetches: [Int] = []
        var stampedAfterExit: [Int] = []
        await FollowedTagChecks.run(
            tags: items,
            screen: .subscriptions,
            showOnHome: { _ in true },
            checkedAt: \.checked,
            isScreenActive: { active },
            isRateLimitHeld: { _ in false },
            now: { currentNow },
            sleep: { _ in active = false },
            attempt: { item, _ in stampedAfterExit.append(item.id); return true },
            fetch: { item in
                exitFetches.append(item.id)
                return sampleFeed()
            },
            received: { _, _, _ in }
        )
        #expect(exitFetches == [2])
        #expect(stampedAfterExit == [2])
    }

    @Test func requestSendsZeroCookiesUsesFeatureUAStopsAfter429AndHonorsRetryAfter() async throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let sessionURL = try #require(AO3Client.tagFeedURL(tagID: 27785))
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [FollowedTagProbe.self]
        if let sessionCookie = HTTPCookie(properties: [
            .domain: "archiveofourown.org",
            .path: "/",
            .name: "_otwarchive_session",
            .value: "secret-cookie-must-never-leak"
        ]) {
            sessionConfig.httpCookieStorage?.setCookie(sessionCookie)
            HTTPCookieStorage.shared.setCookie(sessionCookie)
        }
        defer {
            HTTPCookieStorage.shared.cookies(for: sessionURL)?.forEach {
                HTTPCookieStorage.shared.deleteCookie($0)
            }
        }

        let client = AO3Client(
            session: URLSession(configuration: sessionConfig),
            paceSleep: { _ in }
        )

        var currentNow = Date(timeIntervalSince1970: 1_750_100_000)
        FollowedTagProbe.reset { _, _ in
            FollowedTagProbe.StubResponse(
                statusCode: 429,
                headers: ["Retry-After": "180"],
                body: Data()
            )
        }

        var checkedAt: [Int: Date] = [:]
        await FollowedTagChecks.run(
            tags: [27785, 99117],
            screen: .subscriptions,
            showOnHome: { _ in true },
            checkedAt: { checkedAt[$0] },
            isScreenActive: { true },
            isRateLimitHeld: { now in
                AO3Client.isFollowedTagHeld(now: now, defaults: defaults)
            },
            now: { currentNow },
            sleep: { _ in },
            attempt: { id, started in checkedAt[id] = started; return true },
            fetch: { tagID in
                try await client.followedTagFeed(tagID: tagID, defaults: defaults, now: { currentNow })
            },
            received: { _, _, _ in }
        )

        // Called only ONCE (no retry after 429, and second tag aborted).
        #expect(FollowedTagProbe.sent.count == 1)
        let req = try #require(FollowedTagProbe.sent.first)
        #expect(req.httpShouldHandleCookies == false)
        #expect(req.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(req.value(forHTTPHeaderField: "User-Agent")?.contains(AO3AutomatedFeature.followedTagFeeds.token) == true)
        #expect(checkedAt[27785] == currentNow)
        #expect(checkedAt[99117] == nil)

        // Inside Retry-After window (120s < 180s): second tag does not hit URLSession.
        currentNow = currentNow.addingTimeInterval(120)
        await FollowedTagChecks.run(
            tags: [99117],
            screen: .subscriptions,
            showOnHome: { _ in true },
            checkedAt: { checkedAt[$0] },
            isScreenActive: { true },
            isRateLimitHeld: { now in
                AO3Client.isFollowedTagHeld(now: now, defaults: defaults)
            },
            now: { currentNow },
            sleep: { _ in },
            attempt: { id, started in checkedAt[id] = started; return true },
            fetch: { tagID in
                try await client.followedTagFeed(tagID: tagID, defaults: defaults, now: { currentNow })
            },
            received: { _, _, _ in }
        )
        #expect(FollowedTagProbe.sent.count == 1)
    }

    @Test func heldMaintenanceWindowLeavesEveryTagUnstampedAndSendsNothing() async throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FollowedTagProbe.self]
        let maintenanceBody = Data("<h2>The archive is down for maintenance.</h2>".utf8)
        FollowedTagProbe.reset { _, _ in
            FollowedTagProbe.StubResponse(statusCode: 418, headers: [:], body: maintenanceBody)
        }
        let client = AO3Client(
            session: URLSession(configuration: config),
            paceSleep: { _ in }
        )

        // An earlier request hits AO3's maintenance page and starts the 60-second hold.
        await #expect(throws: AO3Error.maintenance) {
            _ = try await client.getHTML(URL(string: "https://archiveofourown.org/works/1")!)
        }
        #expect(await client.isHeldForMaintenance)

        // Reset probe to count any outgoing tag feed requests during the held window.
        FollowedTagProbe.reset { _, _ in
            FollowedTagProbe.StubResponse(
                statusCode: 200,
                headers: [:],
                body: Data(
                    """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <feed xmlns="http://www.w3.org/2005/Atom">
                      <id>tag:archiveofourown.org,2005:/tags/101/feed</id>
                      <title>Tag</title>
                    </feed>
                    """.utf8
                )
            )
        }

        let container = try makeContainer()
        let context = container.mainContext
        let oldCheckedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let tagNeverChecked = FollowedTag(ao3TagID: 101, name: "Tag 101", showOnHome: true)
        let tagPreviouslyChecked = FollowedTag(
            ao3TagID: 202,
            name: "Tag 202",
            showOnHome: true,
            lastCheckedAt: oldCheckedAt
        )
        context.insert(tagNeverChecked)
        context.insert(tagPreviouslyChecked)
        try context.save()

        let storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FollowedTagMaintenanceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let store = FollowedTagUpdateStore(directory: storeDir, client: client)

        // Automatic foreground pass during maintenance hold sends nothing and leaves stamps untouched.
        await store.checkIfNeeded(
            screen: .subscriptions,
            in: context,
            ignoringCooldown: false,
            isScreenActive: { true },
            defaults: defaults,
            sleep: { _ in }
        )
        #expect(FollowedTagProbe.sent.isEmpty)
        #expect(tagNeverChecked.lastCheckedAt == nil)
        #expect(tagPreviouslyChecked.lastCheckedAt == oldCheckedAt)

        // Even ignoring cooldown without clearing the hold must not stamp tags or send.
        await store.checkIfNeeded(
            screen: .home,
            in: context,
            ignoringCooldown: true,
            isScreenActive: { true },
            defaults: defaults,
            sleep: { _ in }
        )
        #expect(FollowedTagProbe.sent.isEmpty)
        #expect(tagNeverChecked.lastCheckedAt == nil)
        #expect(tagPreviouslyChecked.lastCheckedAt == oldCheckedAt)

        // Direct pure runner check also skips fetch and attempt when maintenance hold is active.
        var directFetched: [Int] = []
        var directStamped: [Int] = []
        await FollowedTagChecks.run(
            tags: [101, 202],
            screen: .subscriptions,
            showOnHome: { _ in true },
            checkedAt: { _ in nil },
            isScreenActive: { true },
            isRateLimitHeld: { _ in false },
            isMaintenanceHeld: { true },
            now: Date.init,
            sleep: { _ in },
            attempt: { id, _ in directStamped.append(id); return true },
            fetch: { id in directFetched.append(id); return sampleFeed() },
            received: { _, _, _ in }
        )
        #expect(directFetched.isEmpty)
        #expect(directStamped.isEmpty)

        // Pull-to-refresh invalidates the hold so the next check sends a probe.
        await client.invalidateCachedResponses()
        await store.checkIfNeeded(
            screen: .subscriptions,
            in: context,
            ignoringCooldown: true,
            isScreenActive: { true },
            defaults: defaults,
            sleep: { _ in }
        )
        #expect(FollowedTagProbe.sent.count == 2)
        #expect(tagNeverChecked.lastCheckedAt != nil)
        #expect(tagPreviouslyChecked.lastCheckedAt != oldCheckedAt)
    }

    @Test func forbidden5xxAndMaintenanceStopThePassWithoutTouchingStoredWorks() async throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let container = try makeContainer()
        let context = container.mainContext
        let baselineDate = Date(timeIntervalSince1970: 1_750_000_000)
        let saved = SavedWork(title: "Keep Me Intact", author: "Author", summary: "Existing summary")
        saved.ao3WorkID = 9123456
        saved.sourceURL = "https://archiveofourown.org/works/9123456"
        saved.chapters = "2/5"
        saved.wordCount = 4321
        saved.rating = "Mature"
        saved.isFavorite = true
        saved.lastModifiedAt = baselineDate
        let savedID = saved.id
        context.insert(saved)

        let tag1InitialCheckedAt = baselineDate.addingTimeInterval(-10 * 3600)
        let tag2InitialCheckedAt = baselineDate.addingTimeInterval(-8 * 3600)
        let tag1 = FollowedTag(
            ao3TagID: 1,
            name: "Tag 1",
            followedAt: baselineDate.addingTimeInterval(-24 * 3600),
            lastCheckedAt: tag1InitialCheckedAt
        )
        let tag2 = FollowedTag(
            ao3TagID: 2,
            name: "Tag 2",
            followedAt: baselineDate.addingTimeInterval(-24 * 3600),
            lastCheckedAt: tag2InitialCheckedAt
        )
        context.insert(tag1)
        context.insert(tag2)
        try context.save()

        let storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FollowedTagStoreErrorTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let store = FollowedTagUpdateStore(directory: storeDir)

        let stopErrors: [any Error] = [
            AO3Error.forbidden,
            AO3Error.server(status: 502),
            AO3Error.maintenance,
            URLError(.notConnectedToInternet)
        ]
        var checkNow = baselineDate
        for error in stopErrors {
            tag1.lastCheckedAt = tag1InitialCheckedAt
            tag2.lastCheckedAt = tag2InitialCheckedAt
            checkNow = checkNow.addingTimeInterval(60)
            var fetched: [Int] = []

            await store.checkIfNeeded(
                screen: .subscriptions,
                in: context,
                isScreenActive: { true },
                defaults: defaults,
                now: { checkNow },
                sleep: { _ in },
                fetch: { tag in
                    fetched.append(tag.ao3TagID)
                    throw error
                }
            )
            #expect(fetched == [1])
            #expect(tag1.lastCheckedAt == checkNow)
            #expect(tag2.lastCheckedAt == tag2InitialCheckedAt)
            #expect(store.updates.isEmpty)
        }

        // Cancelling the enclosing Task mid-sleep aborts unstarted tags cleanly.
        var taskFetched: [Int] = []
        var taskStamped: [Int] = []
        var checkTask: Task<Void, Never>?
        checkTask = Task { @MainActor in
            await FollowedTagChecks.run(
                tags: [1, 2],
                screen: .subscriptions,
                showOnHome: { _ in true },
                checkedAt: { _ in nil },
                isScreenActive: { true },
                isRateLimitHeld: { _ in false },
                now: Date.init,
                sleep: { _ in
                    checkTask?.cancel()
                    try Task.checkCancellation()
                },
                attempt: { id, _ in taskStamped.append(id); return true },
                fetch: { id in taskFetched.append(id); return sampleFeed() },
                received: { _, _, _ in }
            )
        }
        await checkTask?.value
        #expect(taskFetched == [1])
        #expect(taskStamped == [1])

        // Consecutive live client calls invoke the 3-second pacer floor between requests.
        final class PaceRecorder: @unchecked Sendable {
            private let lock = NSLock()
            var waits: [TimeInterval] = []
            func append(_ wait: TimeInterval) {
                lock.lock()
                waits.append(wait)
                lock.unlock()
            }
        }
        let recorder = PaceRecorder()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FollowedTagProbe.self]
        let validFeed = Data(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <feed xmlns="http://www.w3.org/2005/Atom">
              <id>tag:archiveofourown.org,2005:/tags/1/feed</id>
              <title>Tag</title>
            </feed>
            """.utf8
        )
        FollowedTagProbe.reset { _, _ in
            FollowedTagProbe.StubResponse(statusCode: 200, headers: [:], body: validFeed)
        }
        let client = AO3Client(
            session: URLSession(configuration: config),
            paceSleep: { wait in recorder.append(wait) }
        )
        _ = try await client.followedTagFeed(tagID: 1, defaults: defaults)
        _ = try await client.followedTagFeed(tagID: 2, defaults: defaults)
        #expect(recorder.waits.contains { $0 >= 2.5 })

        let remaining = try context.fetch(FetchDescriptor<SavedWork>())
        #expect(remaining.count == 1)
        let untouched = try #require(remaining.first)
        #expect(untouched.id == savedID)
        #expect(untouched.title == "Keep Me Intact")
        #expect(untouched.author == "Author")
        #expect(untouched.ao3WorkID == 9123456)
        #expect(untouched.sourceURL == "https://archiveofourown.org/works/9123456")
        #expect(untouched.summary == "Existing summary")
        #expect(untouched.chapters == "2/5")
        #expect(untouched.wordCount == 4321)
        #expect(untouched.rating == "Mature")
        #expect(untouched.isFavorite)
        #expect(untouched.lastModifiedAt == baselineDate)
        #expect(untouched.deletedAt == nil)
        #expect(!untouched.isPendingDeletion)
    }

    @Test func capOfTwentyTagsIsEnforced() throws {
        let container = try makeContainer()
        let context = container.mainContext

        for i in 1 ... FollowedTag.maxFollowedCount {
            try FollowedTagStore.followOrUpdate(
                ao3TagID: i,
                name: "Tag \(i)",
                tagCategoryRaw: "Fandom",
                tagURLString: "https://archiveofourown.org/tags/Tag%20\(i)/works",
                showOnHome: true,
                completeOnly: false,
                hideExplicit: false,
                in: context
            )
        }

        let current = try context.fetch(FetchDescriptor<FollowedTag>())
        #expect(current.count == 20)
        #expect(!FollowedTagStore.canFollow(existing: current, ao3TagID: 21))
        #expect(FollowedTagStore.canFollow(existing: current, ao3TagID: 1))

        #expect(throws: FollowedTagStore.FollowError.limitReached(20)) {
            try FollowedTagStore.followOrUpdate(
                ao3TagID: 21,
                name: "Tag 21",
                tagCategoryRaw: "Fandom",
                tagURLString: nil,
                showOnHome: true,
                completeOnly: false,
                hideExplicit: false,
                in: context
            )
        }
        #expect(try context.fetch(FetchDescriptor<FollowedTag>()).count == 20)

        // Updating one of the 20 existing followed tags still succeeds.
        let updated = try FollowedTagStore.followOrUpdate(
            ao3TagID: 1,
            name: "Tag 1",
            tagCategoryRaw: "Fandom",
            tagURLString: nil,
            showOnHome: false,
            completeOnly: true,
            hideExplicit: true,
            in: context
        )
        #expect(!updated.showOnHome)
        #expect(updated.completeOnly)
        #expect(updated.hideExplicit)
    }

    @Test func threeSwitchesFilterEntriesAndBusyTagProducesAndMoreUpdate() throws {
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let container = try makeContainer()
        let context = container.mainContext

        let homeTag = try FollowedTagStore.followOrUpdate(
            ao3TagID: 100,
            name: "Home Fandom",
            tagCategoryRaw: "Fandom",
            tagURLString: "https://archiveofourown.org/tags/Home%20Fandom/works",
            showOnHome: true,
            completeOnly: true,
            hideExplicit: true,
            in: context,
            now: base
        )
        let subOnlyTag = try FollowedTagStore.followOrUpdate(
            ao3TagID: 200,
            name: "Hidden Fandom",
            tagCategoryRaw: "Character",
            tagURLString: "https://archiveofourown.org/tags/Hidden%20Fandom/works",
            showOnHome: false,
            completeOnly: false,
            hideExplicit: false,
            in: context,
            now: base
        )

        let completeTeen = makeEntry(
            workID: 1, publishedAt: base.addingTimeInterval(60), chapters: "2/2", rating: "Teen And Up Audiences"
        )
        let incompleteTeen = makeEntry(
            workID: 2, publishedAt: base.addingTimeInterval(70), chapters: "2/?", rating: "Teen And Up Audiences"
        )
        let completeExplicit = makeEntry(
            workID: 3, publishedAt: base.addingTimeInterval(80), chapters: "1/1", rating: "Explicit"
        )

        let homeEval = FollowedTagFeedEvaluator.evaluate(
            feed: sampleFeed(entries: [completeTeen, incompleteTeen, completeExplicit]),
            followedAt: base,
            priorSeenWorkIDs: [],
            isInitialCheck: true,
            completeOnly: homeTag.completeOnly,
            hideExplicit: homeTag.hideExplicit
        )
        #expect(homeEval.matchingEntries.map(\.workID) == [1])
        #expect(!homeEval.isBusy)

        // Store records updates and honours `homeOnly` via live FollowedTag switches.
        let storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FollowedTagUpdateStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let store = FollowedTagUpdateStore(directory: storeDir)

        store.apply(evaluation: homeEval, to: homeTag, in: context)

        let twentyFive = (1000 ..< 1025).map { idx in
            makeEntry(workID: idx, publishedAt: base.addingTimeInterval(Double(idx)), chapters: "1/1")
        }
        let busyEval = FollowedTagFeedEvaluator.evaluate(
            feed: sampleFeed(entries: twentyFive),
            followedAt: base,
            priorSeenWorkIDs: [],
            isInitialCheck: true,
            completeOnly: subOnlyTag.completeOnly,
            hideExplicit: subOnlyTag.hideExplicit
        )
        #expect(busyEval.isBusy)
        store.apply(evaluation: busyEval, to: subOnlyTag, in: context)

        let allTags = [homeTag, subOnlyTag]
        let subsUpdates = store.visibleUpdates(for: allTags, homeOnly: false)
        let homeUpdates = store.visibleUpdates(for: allTags, homeOnly: true)
        #expect(subsUpdates.count == 2)
        #expect(homeUpdates.count == 1)

        if case let .tag(source) = homeUpdates[0].source {
            #expect(source.tagID == 100)
        } else {
            Issue.record("Expected .tag update")
        }

        let busyUpdate = subsUpdates.first {
            if case let .tag(src) = $0.source { return src.tagID == 200 }
            return false
        }
        if case let .tag(busySource) = try #require(busyUpdate).source {
            #expect(busySource.isBusy)
            #expect(busySource.count == 25)
            #expect(busyUpdate?.source.tagWorksRequest?.url.absoluteString == "https://archiveofourown.org/tags/Hidden%20Fandom/works")
        } else {
            Issue.record("Expected busy .tag update")
        }
    }
}
