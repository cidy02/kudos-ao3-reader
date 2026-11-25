import Foundation
import SwiftData
import Testing
@testable import Kudos

@MainActor
@Suite(.serialized)
struct QueueSourceChecksTests {
    private actor Signal {
        private var fired = false
        private var waiter: CheckedContinuation<Void, Never>?

        func fire() {
            fired = true
            waiter?.resume()
            waiter = nil
        }

        func wait() async {
            if fired { return }
            await withCheckedContinuation { waiter = $0 }
        }
    }

    private func page(_ dates: [String]) -> AO3SearchPage {
        AO3SearchPage(works: dates.enumerated().map { index, date in
            var work = AO3WorkSummary.subscription(id: index + 1, title: "Work", authors: [])
            work.dateUpdated = date
            return work
        }, currentPage: 1, totalPages: 1)
    }

    private func filters(
        sort: AO3SearchFilters.Sort,
        direction: AO3SearchFilters.SortDirection = .descending
    ) -> AO3SearchFilters {
        var value = AO3SearchFilters()
        value.sort = sort
        value.sortDirection = direction
        return value
    }

    @Test func gateAndCapAreOldestFirst() {
        let now = Date(timeIntervalSince1970: 100_000)
        let checks = [now.addingTimeInterval(-30), nil, now.addingTimeInterval(-50_000),
                      now.addingTimeInterval(-40_000), now.addingTimeInterval(-30_000),
                      now.addingTimeInterval(-22_000), now.addingTimeInterval(-21_000),
                      now.addingTimeInterval(-21_601)]
        let selected = QueueSourceChecks.eligible(Array(checks.indices), checkedAt: { checks[$0] }, now: now)
        #expect(selected == [1, 2, 3, 4, 5])
        #expect(QueueSourceChecks.eligible([0], checkedAt: { _ in now.addingTimeInterval(-21_599) }, now: now).isEmpty)
        #expect(QueueSourceChecks.eligible([0], checkedAt: { _ in now.addingTimeInterval(-21_600) }, now: now) == [0])
    }

    @Test func sequentialGapAndFailedAttemptCooldown() async {
        var now = Date(timeIntervalSince1970: 100_000)
        var checked: [Int: Date] = [:]
        var starts: [Date] = []
        await QueueSourceChecks.run(
            sources: [1, 2, 3], checkedAt: { checked[$0] }, now: { now },
            sleep: { now.addTimeInterval($0) },
            attempt: { source, date in checked[source] = date; starts.append(date); return true },
            fetch: { source in
                if source == 1 { throw AO3Error.network("offline") }
                return page([])
            }, received: { _, _ in }
        )
        #expect(starts.count == 3)
        #expect(starts[1].timeIntervalSince(starts[0]) >= 3)
        #expect(starts[2].timeIntervalSince(starts[1]) >= 3)
        #expect(QueueSourceChecks.eligible([1, 2, 3], checkedAt: { checked[$0] }, now: now).isEmpty)
    }

    @Test func rateLimitStopsWithoutRetry() async {
        var fetches: [Int] = []
        await QueueSourceChecks.run(
            sources: [1, 2], checkedAt: { _ in nil }, now: { Date(timeIntervalSince1970: 100_000) },
            sleep: { _ in }, attempt: { _, _ in true },
            fetch: { source in fetches.append(source); throw AO3Error.rateLimited(retryAfter: nil) },
            received: { _, _ in }
        )
        #expect(fetches == [1])
    }

    @Test func cancellationStopsBeforeNextSource() async {
        var fetches: [Int] = []
        await QueueSourceChecks.run(
            sources: [1, 2], checkedAt: { _ in nil }, now: { Date(timeIntervalSince1970: 100_000) },
            sleep: { _ in }, attempt: { _, _ in true },
            fetch: { source in fetches.append(source); throw CancellationError() },
            received: { _, _ in }
        )
        #expect(fetches == [1])
    }

    @Test func cancellingThePageTaskStopsAnInFlightPass() async {
        let started = Signal()
        var fetches: [Int] = []
        let task = Task {
            await QueueSourceChecks.run(
                sources: [1, 2], checkedAt: { _ in nil }, now: Date.init,
                sleep: { _ in }, attempt: { _, _ in true },
                fetch: { source in
                    fetches.append(source)
                    await started.fire()
                    try await Task.sleep(for: .seconds(2))
                    return page([])
                }, received: { _, _ in }
            )
        }
        await started.wait()
        task.cancel()
        await task.value
        #expect(fetches == [1])
    }

    @Test func forbiddenAndMaintenanceStopThePass() async {
        for failure in [AO3Error.forbidden, AO3Error.maintenance] {
            var attempts: [Int] = []
            await QueueSourceChecks.run(
                sources: [1, 2], checkedAt: { _ in nil }, now: Date.init,
                sleep: { _ in }, attempt: { source, _ in attempts.append(source); return true },
                fetch: { _ in throw failure }, received: { _, _ in }
            )
            #expect(attempts == [1])
        }
    }

    @Test func oneRequestIsInFlightAtATime() async {
        var inFlight = 0
        var peak = 0
        await QueueSourceChecks.run(
            sources: [1, 2, 3], checkedAt: { _ in nil }, now: Date.init,
            sleep: { _ in }, attempt: { _, _ in true },
            fetch: { _ in
                inFlight += 1
                peak = max(peak, inFlight)
                await Task.yield()
                inFlight -= 1
                return page([])
            }, received: { _, _ in }
        )
        #expect(peak == 1)
    }

    @Test func countUsesUTCDayAndNilOpenedIsZero() {
        let opened = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01 00:00 UTC
        let midday = opened.addingTimeInterval(12 * 60 * 60)
        #expect(QueueSourceChecks.count(page(["02 Jan 2025", "31 Dec 2024"]), since: opened) == 1)
        #expect(QueueSourceChecks.count(page(["01 Jan 2025"]), since: midday) == 1)
        #expect(QueueSourceChecks.count(page(["31 Dec 2024"]), since: midday) == 0)
        #expect(QueueSourceChecks.count(page(["2025-01-01"]), since: midday) == 1)
        #expect(QueueSourceChecks.count(page(Array(repeating: "02 Jan 2025", count: 20)), since: opened) == 20)
        #expect(QueueSourceChecks.count(page(["02 Jan 2025", "01 Jan 2025"]), since: nil) == 0)
        #expect(QueueSourceChecks.badge(20) == "20+ new")
        #expect(QueueSourceChecks.badge(1) == "1 new")
    }

    @Test func unreachableErrorsStopThePassWithoutStamping() async {
        let codes: [URLError.Code] = [
            .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
            .cannotFindHost, .dnsLookupFailed, .timedOut
        ]
        for code in codes {
            var stamped: [Int: Date] = [:]
            var fetches: [Int] = []
            await QueueSourceChecks.run(
                sources: [1, 2], checkedAt: { stamped[$0] }, now: { Date(timeIntervalSince1970: 100_000) },
                sleep: { _ in },
                attempt: { source, date in stamped[source] = date; return true },
                fetch: { source in fetches.append(source); throw URLError(code) },
                received: { _, _ in }
            )
            #expect(fetches == [1], "code \(code)")
            #expect(stamped.isEmpty, "code \(code)")
        }
    }

    @Test func visitIsRecordedAfterPage1OrImmediatelyWhenCached() {
        #expect(QueueSourceChecks.recordsOpenImmediately(hasCachedPage: true))
        #expect(!QueueSourceChecks.recordsOpenImmediately(hasCachedPage: false))
        #expect(QueueSourceChecks.shouldRecordOpen(page: 1, loadToken: 4, expectedToken: 4))
        #expect(!QueueSourceChecks.shouldRecordOpen(page: 2, loadToken: 4, expectedToken: 4))
        #expect(!QueueSourceChecks.shouldRecordOpen(page: 1, loadToken: 5, expectedToken: 4))
    }

    @Test func onlyDateDescendingSortsCount() {
        #expect(!QueueSourceChecks.countsNewResults(AO3SearchFilters()))
        #expect(QueueSourceChecks.countsNewResults(filters(sort: .dateUpdated)))
        #expect(QueueSourceChecks.countsNewResults(filters(sort: .datePosted)))
        #expect(!QueueSourceChecks.countsNewResults(filters(sort: .dateUpdated, direction: .ascending)))
        #expect(!QueueSourceChecks.countsNewResults(filters(sort: .kudos)))
        #expect(!QueueSourceChecks.countsNewResults(filters(sort: .relevance)))
        #expect(QueueSourceChecks.displayedCount(3, filters: filters(sort: .dateUpdated)) == 3)
        #expect(QueueSourceChecks.displayedCount(3, filters: filters(sort: .kudos)) == nil)
        #expect(QueueSourceChecks.displayedCount(0, filters: filters(sort: .dateUpdated)) == nil)
        #expect(QueueSourceChecks.savedSearchAccessibilityLabel(
            name: "Unlinked", count: nil, isLinked: false, filters: AO3SearchFilters()
        ) == "Open saved search Unlinked")
        #expect(QueueSourceChecks.cachedPageForFindMore(page(["01 Jan 2025"]), isSignedOut: false) == nil)
        #expect(QueueSourceChecks.cachedPageForFindMore(page(["01 Jan 2025"]), isSignedOut: true) != nil)
    }

    private func testContext() throws -> ModelContext {
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

    @Test func noRequestWithoutQueueOpenTrigger() {
        #expect(QueueSourceChecks.shouldCheckOnOpen(
            isPageVisible: true, isAppActive: true, isSelectedTab: true,
            isSmartQueue: false, hasVisibleSources: true
        ))
        #expect(!QueueSourceChecks.shouldCheckOnOpen(
            isPageVisible: false, isAppActive: true, isSelectedTab: true,
            isSmartQueue: false, hasVisibleSources: true
        ))
        #expect(!QueueSourceChecks.shouldCheckOnOpen(
            isPageVisible: true, isAppActive: false, isSelectedTab: true,
            isSmartQueue: false, hasVisibleSources: true
        ))
        #expect(!QueueSourceChecks.shouldCheckOnOpen(
            isPageVisible: true, isAppActive: true, isSelectedTab: false,
            isSmartQueue: false, hasVisibleSources: true
        ))
        #expect(!QueueSourceChecks.shouldCheckOnOpen(
            isPageVisible: true, isAppActive: true, isSelectedTab: true,
            isSmartQueue: true, hasVisibleSources: true
        ))
        #expect(!QueueSourceChecks.shouldCheckOnOpen(
            isPageVisible: true, isAppActive: true, isSelectedTab: true,
            isSmartQueue: false, hasVisibleSources: false
        ))
        #expect(!QueueSourceChecks.countsNewResults(kind: nil))
        #expect(QueueSourceChecks.countsNewResults(kind: .author))
        #expect(QueueSourceChecks.countsNewResults(kind: .series))
        #expect(QueueSourceChecks.countsNewResults(kind: .tag))
    }

    @Test func fiveSourceCapAndOldestFirstSpanAllFourKindsAndSkipUnknown() throws {
        let context = try testContext()
        let queue = ReadingQueue(name: "Mixed Sources")
        context.insert(queue)

        let searchA = SavedSearch(name: "Search A", filters: filters(sort: .dateUpdated))
        let searchB = SavedSearch(name: "Search B", filters: filters(sort: .datePosted))
        let searchKudos = SavedSearch(name: "Search Kudos", filters: filters(sort: .kudos))
        for search in [searchA, searchB, searchKudos] { context.insert(search) }

        let now = Date(timeIntervalSince1970: 200_000)
        let linkSearchA = QueueSavedSearchLink(queue: queue, search: searchA)
        linkSearchA.lastCheckedAt = now.addingTimeInterval(-60_000)
        let linkSearchB = QueueSavedSearchLink(queue: queue, search: searchB)
        linkSearchB.lastCheckedAt = now.addingTimeInterval(-25_000)
        let linkKudos = QueueSavedSearchLink(queue: queue, search: searchKudos)
        let linkAuthor1 = QueueSavedSearchLink(
            queue: queue, kindRaw: QueueSourceKind.author.rawValue,
            targetKey: "user:alice", displayName: "alice", authorUsername: "alice",
            lastOpenedAt: now, lastCheckedAt: nil
        )
        let linkAuthor2 = QueueSavedSearchLink(
            queue: queue, kindRaw: QueueSourceKind.author.rawValue,
            targetKey: "user:bob/pseud:pen", displayName: "pen (bob)",
            authorUsername: "bob", authorPseud: "pen",
            lastOpenedAt: now, lastCheckedAt: now.addingTimeInterval(-100) // inside 6h gate
        )
        let linkSeries = QueueSavedSearchLink(
            queue: queue, kindRaw: QueueSourceKind.series.rawValue,
            targetKey: "series:42", displayName: "Grand Arc", ao3SeriesID: 42,
            lastOpenedAt: now, lastCheckedAt: now.addingTimeInterval(-50_000)
        )
        let linkTag1 = QueueSavedSearchLink(
            queue: queue, kindRaw: QueueSourceKind.tag.rawValue,
            targetKey: "tag:slow burn", displayName: "Slow Burn", tagName: "Slow Burn",
            lastOpenedAt: now, lastCheckedAt: now.addingTimeInterval(-40_000)
        )
        let linkTag2 = QueueSavedSearchLink(
            queue: queue, kindRaw: QueueSourceKind.tag.rawValue,
            targetKey: "tag:angst", displayName: "Angst", tagName: "Angst",
            lastOpenedAt: now, lastCheckedAt: now.addingTimeInterval(-30_000)
        )
        let linkUnknown = QueueSavedSearchLink(
            queue: queue, kindRaw: "collection", targetKey: "collection:fest",
            displayName: "Fest", lastOpenedAt: now, lastCheckedAt: nil
        )
        for link in [
            linkSearchA, linkSearchB, linkKudos, linkAuthor1, linkAuthor2,
            linkSeries, linkTag1, linkTag2, linkUnknown
        ] {
            context.insert(link)
        }
        try context.save()

        #expect(!queue.allVisibleSources.contains(where: { $0.id == linkUnknown.id }))
        #expect(!queue.countableSources.contains(where: { $0.id == linkUnknown.id }))
        #expect(!queue.countableSources.contains(where: { $0.id == linkKudos.id }))

        let selected = QueueSourceChecks.eligible(
            queue.countableSources, checkedAt: \.lastCheckedAt, now: now
        )
        let expected: [UUID] = [linkAuthor1.id, linkSearchA.id, linkSeries.id, linkTag1.id, linkTag2.id]
        let selectedIDs: [UUID] = selected.map(\.id)
        #expect(selectedIDs == expected)
    }

    @Test func runFetchedEnforcesSequentialSpacingAndStrictlyOneRequestAtATime() async throws {
        var now = Date(timeIntervalSince1970: 100_000)
        var starts: [Date] = []
        var inFlight = 0
        var peak = 0
        var receivedIDs: [Int] = []
        let url = try #require(URL(string: "https://archiveofourown.org/series/99"))
        let sample = QueueSourceFetchedPage(url: url, page: page(["02 Jan 2025"]), html: "<ol></ol>")

        await QueueSourceChecks.runFetched(
            sources: [1, 2, 3],
            checkedAt: { _ in nil },
            now: { now },
            sleep: { now.addTimeInterval($0) },
            attempt: { _, date in starts.append(date); return true },
            fetch: { _ in
                inFlight += 1
                peak = max(peak, inFlight)
                await Task.yield()
                inFlight -= 1
                return sample
            },
            received: { id, _ in receivedIDs.append(id) }
        )
        #expect(peak == 1)
        #expect(receivedIDs == [1, 2, 3])
        #expect(starts.count == 3)
        #expect(starts[1].timeIntervalSince(starts[0]) >= 3)
        #expect(starts[2].timeIntervalSince(starts[1]) >= 3)

    }

    @Test func findMoreReusesACountedPageOnlyWhenFreshMatchingAndSignedOut() throws {
        let url = try #require(URL(string: "https://archiveofourown.org/series/99?page=1"))
        let other = try #require(URL(string: "https://archiveofourown.org/series/98?page=1"))
        let fetchedAt = Date(timeIntervalSince1970: 50_000)
        var sample = QueueSourceFetchedPage(url: url, page: page(["02 Jan 2025"]), html: "<ol></ol>")
        sample.fetchedAt = fetchedAt
        let soon = fetchedAt.addingTimeInterval(60)
        #expect(QueueSourceChecks.cachedFetchForFindMore(
            sample, listingURL: url, isSignedOut: true, now: soon
        )?.html == "<ol></ol>")
        // Signed in, signing in, restoring: never.
        #expect(QueueSourceChecks.cachedFetchForFindMore(
            sample, listingURL: url, isSignedOut: false, now: soon
        ) == nil)
        // Older than the TTL.
        #expect(QueueSourceChecks.cachedFetchForFindMore(
            sample, listingURL: url, isSignedOut: true,
            now: fetchedAt.addingTimeInterval(QueueSourceChecks.findMoreReuseTTL + 1)
        ) == nil)
        #expect(QueueSourceChecks.findMoreReuseTTL <= QueueSourceChecks.cooldown)
        // The source's listing changed since the count.
        #expect(QueueSourceChecks.cachedFetchForFindMore(
            sample, listingURL: other, isSignedOut: true, now: soon
        ) == nil)
        #expect(QueueSourceChecks.cachedFetchForFindMore(
            sample, listingURL: nil, isSignedOut: true, now: soon
        ) == nil)
    }

    @Test func aRemovedSourceIsNeitherFetchedNorStampedAndPassContinues() async throws {
        let now = Date(timeIntervalSince1970: 100_000)
        var removed: Set<Int> = []
        var fetched: [Int] = []
        var stamped: [Int] = []
        var received: [Int] = []
        let url = try #require(URL(string: "https://archiveofourown.org/series/99"))
        let sample = QueueSourceFetchedPage(url: url, page: page(["02 Jan 2025"]), html: "")
        await QueueSourceChecks.runFetched(
            sources: [1, 2, 3],
            checkedAt: { _ in nil },
            now: { now },
            sleep: { _ in },
            isCurrent: { !removed.contains($0) },
            attempt: { id, _ in stamped.append(id); return true },
            fetch: { id in
                fetched.append(id)
                // Source 1 is removed while its own request is in flight, 2 while it waits.
                if id == 1 { removed.insert(1); removed.insert(2) }
                return sample
            },
            received: { id, _ in received.append(id) }
        )
        #expect(fetched == [1, 3])
        #expect(stamped == [3])
        #expect(received == [3])
    }

    @Test func leavingTheQueueCancelsTheWaitingPass() async throws {
        var fetched: [Int] = []
        var stamped: [Int] = []
        let url = try #require(URL(string: "https://archiveofourown.org/series/99"))
        let sample = QueueSourceFetchedPage(url: url, page: page(["02 Jan 2025"]), html: "")
        let task = Task { @MainActor in
            await QueueSourceChecks.runFetched(
                sources: [1, 2, 3],
                checkedAt: { _ in nil },
                now: Date.init,
                sleep: { _ in try await Task.sleep(for: .seconds(60)) },
                attempt: { id, _ in stamped.append(id); return true },
                fetch: { id in fetched.append(id); return sample },
                received: { _, _ in }
            )
        }
        while fetched.isEmpty { await Task.yield() }
        task.cancel()
        await task.value
        #expect(fetched == [1])
        #expect(stamped == [1])
    }

    @Test func pageOneListingGuardNormalisesTheQuery() throws {
        func ok(_ raw: String) throws -> Bool {
            QueueSourceChecks.isPageOneListing(try #require(URL(string: raw)))
        }
        let base = "https://archiveofourown.org/series/1"
        #expect(try ok(base))
        #expect(try ok(base + "?page=1"))
        #expect(try !ok(base + "?page=2"))
        #expect(try !ok(base + "?page=1&page=2"))
        #expect(try !ok(base + "?PAGE=2"))
        #expect(try !ok(base + "?Page=1&pAge=3"))
        #expect(try !ok(base + "?page"))
        #expect(try !ok(base + "?page="))
        #expect(try !ok("https://archiveofourown.org:8443/series/1?page=1"))
    }

    @Test func tagSourcesAcceptOnlyTagWorksPathsOnTheDefaultPort() throws {
        func accepted(_ raw: String) -> String? {
            QueueSourceDraft.tag(name: "Fluff", url: URL(string: raw))?.urlString
        }
        let works = "https://archiveofourown.org/tags/Fluff/works"
        #expect(accepted(works) == works)
        let fallback = "https://archiveofourown.org/tags/Fluff/works"
        #expect(accepted("https://archiveofourown.org/tags/Fluff") == fallback)
        #expect(accepted("https://archiveofourown.org/works/123") == fallback)
        #expect(accepted("https://archiveofourown.org:8443/tags/Fluff/works") == fallback)
        #expect(accepted("http://archiveofourown.org/tags/Fluff/works") == fallback)
        #expect(accepted("https://archiveofourown.org/tags/Fluff/works/extra") == fallback)
        #expect(accepted("https://archiveofourown.org/tags/../works") == fallback)
        #expect(accepted("https://archiveofourown.org/tags/%2e%2e/works") == fallback)
        #expect(accepted("https://archiveofourown.org/tags/Fluff/works?PAGE=2") == fallback)
        #expect(accepted("https://archiveofourown.org/tags/Fluff/works#x") == fallback)

        // A stored row (restored from a backup) is held to the same rule.
        let context = try testContext()
        let queue = ReadingQueue(name: "Tags")
        context.insert(queue)
        let link = QueueSavedSearchLink(
            queue: queue, kindRaw: "tag", targetKey: "tag:fluff", tagName: "Fluff",
            urlString: "https://archiveofourown.org/works/123"
        )
        context.insert(link)
        #expect(link.tagWorksRequest?.url.absoluteString == fallback)
        #expect(link.listingURL?.path == "/tags/Fluff/works")
    }

    @Test func pastedLinksParseOnlyToRealSources() throws {
        func draft(_ raw: String) -> QueueSourceDraft? { QueueSourceDraft.fromAO3URL(raw) }
        #expect(draft("https://archiveofourown.org/users/alice/works")?.authorUsername == "alice")
        #expect(draft("https://archiveofourown.org/users/alice")?.kind == .author)
        let pseud = try #require(draft("https://archiveofourown.org/users/alice/pseuds/pen/works"))
        #expect(pseud.authorPseud == "pen")
        // Not a works listing: bookmarks, the series list, the profile.
        #expect(draft("https://archiveofourown.org/users/alice/bookmarks") == nil)
        #expect(draft("https://archiveofourown.org/users/alice/series") == nil)
        #expect(draft("https://archiveofourown.org/users/alice/profile") == nil)
        #expect(draft("https://archiveofourown.org/users/alice/pseuds/pen/bookmarks") == nil)
        // One decode: %2520 is a literal "%20".
        #expect(draft("https://archiveofourown.org/users/foo/pseuds/Literal%2520Name/works")?
            .authorPseud == "Literal%20Name")
        // ao3.org, http and no scheme are all AO3.
        #expect(draft("https://ao3.org/series/77")?.ao3SeriesID == 77)
        #expect(draft("http://archiveofourown.org/tags/Fluff/works")?.tagName == "Fluff")
        #expect(draft("ao3.org/users/alice")?.authorUsername == "alice")
        #expect(draft("archiveofourown.org/series/5")?.ao3SeriesID == 5)
        // Other hosts, other ports, other routes.
        #expect(draft("example.com/users/alice") == nil)
        #expect(draft("https://archiveofourown.org:8443/users/alice") == nil)
        #expect(draft("https://archiveofourown.org/works/123") == nil)
        #expect(draft("https://archiveofourown.org/works/search?work_search[query]=x") == nil)
        #expect(draft("https://archiveofourown.org/tags/AU*s*Coffee*d*Shop")?.tagName == "AU/Coffee.Shop")
        #expect(QueueSourceDraft.isURLInput("ao3.org/tags/Fluff/works"))
        #expect(!QueueSourceDraft.isURLInput("Fluff"))
    }

    @Test func aRestoredRowWithoutATargetKeyKeepsItsIdentityAndSurvivesEditQueue() throws {
        let context = try testContext()
        let queue = ReadingQueue(name: "Edit")
        context.insert(queue)
        let link = QueueSavedSearchLink(
            queue: queue, kindRaw: "author", targetKey: "", authorUsername: "Alice"
        )
        let orphan = QueueSavedSearchLink(queue: queue, kindRaw: "author", targetKey: "")
        context.insert(link)
        context.insert(orphan)
        let draft = try #require(link.sourceDraft)
        #expect(draft.targetKey == "user:alice")
        #expect(link.dedupKey == draft.dedupKey)
        // A row with nothing to derive a key from cannot be shown in Edit Queue, so Save must not delete it.
        #expect(orphan.sourceDraft == nil)
        ReadingQueueService.syncNonSearchSources(for: queue, drafts: [draft], in: context)
        try context.save()
        #expect(queue.nonSearchSources.count == 2)
    }
    @Test func openingSourceResetsCountWithoutAddingAnyWork() throws {
        let context = try testContext()
        let queue = ReadingQueue(name: "Sources Queue")
        context.insert(queue)
        let draft = try #require(QueueSourceDraft.series(id: 555, title: "Long Fic Series"))
        #expect(ReadingQueueService.addSource(draft, to: queue, in: context))
        let link = try #require(queue.visibleNonSearchSources.first)
        let baseline = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01 00:00 UTC
        link.lastOpenedAt = baseline
        link.newResultCount = QueueSourceChecks.count(
            page(Array(repeating: "02 Jan 2025", count: 20)),
            since: link.effectiveLastOpenedAt
        )
        #expect(link.newResultCount == 20)
        #expect(QueueSourceChecks.badge(20) == "20+ new")
        #expect(ReadingQueueService.orderedWorks(in: queue).isEmpty)

        let visited = baseline.addingTimeInterval(3_600)
        ReadingQueueService.recordSourceOpen(link, at: visited, in: context)
        #expect(link.lastOpenedAt == visited)
        #expect(link.newResultCount == 0)
        #expect(link.displayedNewCount == nil)
        #expect(ReadingQueueService.orderedWorks(in: queue).isEmpty)
    }

    @Test func sourceDraftURLParsingAndListingURLsCoverAllKindsAndRejectUntrusted() throws {
        let context = try testContext()
        let queue = ReadingQueue(name: "URLs")
        context.insert(queue)

        let author = try #require(
            QueueSourceDraft.fromAO3URL("https://archiveofourown.org/users/writer/pseuds/pen/works")
        )
        #expect(author.kind == .author)
        #expect(author.authorUsername == "writer")
        #expect(author.authorPseud == "pen")

        let series = try #require(
            QueueSourceDraft.fromAO3URL("https://archiveofourown.org/series/7777", fallbackTitle: "Seven")
        )
        #expect(series.kind == .series)
        #expect(series.ao3SeriesID == 7777)

        let tag = try #require(
            QueueSourceDraft.fromAO3URL("https://archiveofourown.org/tags/Coffee%20Shop%20AU/works")
        )
        #expect(tag.kind == .tag)
        #expect(tag.tagName == "Coffee Shop AU")

        #expect(QueueSourceDraft.fromAO3URL("https://archiveofourown.org.evil.com/series/7777") == nil)
        #expect(QueueSourceDraft.fromAO3URL("https://example.com/users/writer") == nil)

        for draft in [author, series, tag] {
            #expect(ReadingQueueService.addSource(draft, to: queue, in: context))
        }
        let byKind = Dictionary(
            uniqueKeysWithValues: queue.visibleNonSearchSources.compactMap { link in
                link.knownSourceKind.map { ($0, link) }
            }
        )
        #expect(byKind[.author]?.listingURL?.absoluteString
            == "https://archiveofourown.org/users/writer/pseuds/pen/works")
        #expect(byKind[.series]?.listingURL?.absoluteString
            == "https://archiveofourown.org/series/7777")
        #expect(byKind[.tag]?.listingURL?.path.contains("/tags/") == true)
        #expect(byKind[.tag]?.listingURL?.query?.contains("page=1") == true)

        #expect(QueueSourceChecks.sourceAccessibilityLabel(
            name: "pen (writer)", kind: .author, count: 3
        ) == "Open author pen (writer), 3 new on AO3")
        #expect(QueueSourceChecks.sourceAccessibilityLabel(
            name: "Seven", kind: .series, count: 20
        ) == "Open series Seven, 20+ new on AO3")
        #expect(QueueSourceChecks.sourceAccessibilityLabel(
            name: "Coffee Shop AU", kind: .tag, count: 0
        ) == "Open tag Coffee Shop AU on AO3")
    }
}
