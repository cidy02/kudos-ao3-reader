#if DEBUG
import Foundation
import SwiftData
import SwiftUI

/// Simulator-only sample library for design review: launch with
/// `-KudosDemoLibrary YES -hasCompletedOnboarding YES` and Home, Library,
/// Queues and Collections have something to draw. Every work is local only —
/// no AO3 id, no source URL — so nothing here can reach the network, and each
/// gets a placeholder file so the on-device checks treat it as downloaded.
/// Seeds once per install; a work titled like the first sample means done.
@MainActor
enum DemoLibrary {
    static func seedIfRequested(in context: ModelContext) {
        guard UserDefaults.standard.bool(forKey: "KudosDemoLibrary") else { return }
        let existing = (try? context.fetch(FetchDescriptor<SavedWork>())) ?? []
        guard !existing.contains(where: { $0.title == samples[0].title }) else {
            seedRecentlyDeleted(in: context)
            return
        }

        let now = Date()
        var works: [SavedWork] = []
        for (index, sample) in samples.enumerated() {
            let work = SavedWork(title: sample.title, author: sample.author, summary: sample.summary)
            work.workFandoms = sample.fandoms
            work.rating = sample.rating
            work.workWarnings = sample.warnings
            work.workCategories = sample.categories
            work.wordCount = sample.words
            work.chapters = sample.chapters
            work.isComplete = sample.chapters.split(separator: "/").last.map(String.init) != "?"
                && sample.chapters.split(separator: "/").first == sample.chapters.split(separator: "/").last
            work.kudos = sample.words / 40
            work.hits = sample.words / 4
            work.language = "English"
            work.dateAdded = now.addingTimeInterval(-Double(index) * 86_400 * 3)
            work.isFavorite = sample.favorite
            work.isSaved = sample.kept
            if let progress = sample.progress {
                work.legacyReaderProgress = progress
                work.lastReadDate = now.addingTimeInterval(-Double(index) * 3_600 * 7)
                work.lastSpineIndex = 1
            }
            work.isFinished = sample.finished
            if let seen = sample.seenChapters { work.knownChapterCount = seen }
            context.insert(work)
            if sample.onDevice {
                writePlaceholder(for: work)
            } else {
                work.hasEPUB = false
            }
            works.append(work)
        }

        let queues: [DemoQueue] = [
            DemoQueue(name: "Neon reread", hue: 0.78, tags: ["Rereads", "Long fic"], works: [0, 3, 5, 8, 11]),
            DemoQueue(name: "Slow burns", hue: 0.07, tags: ["Comfort", "Long fic"], works: [1, 4, 9, 12]),
            DemoQueue(name: "Case fic pile", hue: 0.52, tags: [], works: [2, 6, 10])
        ]
        var tags: [String: Tag] = [:]
        for (order, entry) in queues.enumerated() {
            let queue = ReadingQueue(name: entry.name, sortOrder: order)
            queue.hue = entry.hue
            queue.keepsWorksOffline = order != 2
            context.insert(queue)
            for name in entry.tags {
                let tag = tags[name] ?? {
                    let made = Tag(name: name)
                    context.insert(made)
                    tags[name] = made
                    return made
                }()
                queue.tags.append(tag)
            }
            for index in entry.works where index < works.count {
                _ = ReadingQueueService.add(works[index], to: queue, in: context)
            }
        }
        let saved = ReadingQueueService.ensureSavedForLaterQueue(in: context)
        for index in [7, 13] where index < works.count {
            _ = ReadingQueueService.add(works[index], to: saved, in: context)
        }

        let shelf = WorkCollection(name: "Comfort reads")
        shelf.hue = 0.33
        shelf.showsOnHome = true
        context.insert(shelf)
        let archive = WorkCollection(name: "To recommend")
        archive.hue = 0.62
        context.insert(archive)
        for index in [1, 4, 7] where index < works.count { works[index].collections.append(shelf) }
        for index in [0, 2] where index < works.count { works[index].collections.append(archive) }

        try? context.save()
        seedRecentlyDeleted(in: context)
    }

    /// One work and one collection in Recently Deleted, so that screen has rows.
    /// Separate from the main seed so an already-seeded simulator gets it too.
    private static func seedRecentlyDeleted(in context: ModelContext) {
        let title = "Lanterns Over Ba Sing Se"
        let all = (try? context.fetch(FetchDescriptor<SavedWork>())) ?? []
        guard !all.contains(where: { $0.title == title }) else { return }
        let work = SavedWork(title: title, author: "paperlantern", summary: "")
        work.workFandoms = ["Avatar: The Last Airbender"]
        work.rating = "General Audiences"
        work.wordCount = 4_310
        work.chapters = "1/1"
        context.insert(work)
        PreservedWorkService.softDelete(work, in: context)
        let shelf = WorkCollection(name: "Summer 2025")
        context.insert(shelf)
        PreservedWorkService.softDelete(shelf, in: context)
        try? context.save()
    }

    private static func writePlaceholder(for work: SavedWork) {
        let url = work.fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? Data(repeating: 0, count: 2_048).write(to: url)
    }

    private struct DemoQueue {
        let name: String
        let hue: Double
        let tags: [String]
        let works: [Int]
    }

    private struct Sample {
        let title: String
        let author: String
        var summary = ""
        let fandoms: [String]
        let rating: String
        var warnings: [String] = ["No Archive Warnings Apply"]
        var categories: [String] = ["Gen"]
        let words: Int
        let chapters: String
        var progress: Double?
        var finished = false
        var favorite = false
        var kept = false
        var onDevice = true
        /// The chapter count last seen; lower than posted means "new chapters".
        var seenChapters: Int?
    }

    private static let samples: [Sample] = [
        Sample(title: "Sodium Lights", author: "nine_of_wands",
               summary: "The TARDIS lands in a city that never switches its streetlamps off.",
               fandoms: ["Doctor Who (2005)", "Doctor Who"], rating: "Teen And Up Audiences",
               words: 62_004, chapters: "1/1", progress: 0.42, favorite: true),
        Sample(title: "Unanswered Is Not Unread", author: "poknn",
               fandoms: ["Avatar: The Last Airbender", "The Legend of Korra"], rating: "Teen And Up Audiences",
               categories: ["M/M"], words: 8_970, chapters: "2/?", progress: 0.2, seenChapters: 1),
        Sample(title: "Burn my heart, heed my eyes", author: "Kuuakuu",
               fandoms: ["NARUTO (Anime & Manga)"], rating: "Teen And Up Audiences",
               words: 4_820, chapters: "1/?"),
        Sample(title: "Happy Birthday Diya!!", author: "runsonmatcha",
               fandoms: ["僕のヒーローアカデミア | Boku no Hero Academia | My Hero Academia"],
               rating: "Explicit", warnings: ["Graphic Depictions Of Violence"], categories: ["F/M"],
               words: 3_150, chapters: "1/1", progress: 0.0),
        Sample(title: "Ashfall", author: "TempusFugit",
               fandoms: ["Star Wars - All Media Types", "Star Wars: The Clone Wars (2008) - All Media Types"],
               rating: "Mature", categories: ["M/M"], words: 41_780, chapters: "9/?", progress: 0.63,
               kept: true, seenChapters: 7),
        Sample(title: "The Long Way Down", author: "velvetstatic",
               fandoms: ["Cyberpunk 2077 (Video Game)"], rating: "Mature", words: 84_120,
               chapters: "7/18", progress: 0.35),
        Sample(title: "Lighthouse Hours", author: "keeper_of_lamps",
               fandoms: ["Sherlock (TV)"], rating: "General Audiences", words: 12_400,
               chapters: "5/5", finished: true),
        Sample(title: "Paper Cranes", author: "origamist",
               fandoms: ["Haikyuu!!"], rating: "General Audiences", words: 2_210, chapters: "1/1"),
        Sample(title: "Winter Garden", author: "frostbitten",
               fandoms: ["Frozen (Disney Movies)"], rating: "General Audiences", categories: ["F/F"],
               words: 18_020, chapters: "4/6", progress: 0.71, favorite: true, seenChapters: 3),
        Sample(title: "What the River Keeps", author: "undertow",
               fandoms: ["Les Misérables - Victor Hugo"], rating: "Teen And Up Audiences",
               words: 132_500, chapters: "30/30", finished: true, kept: true),
        Sample(title: "Static on Channel Nine", author: "lowfreq",
               fandoms: ["Supernatural"], rating: "Mature", words: 27_600, chapters: "3/?",
               onDevice: false),
        Sample(title: "Every Door in Hades", author: "zagreus_fan",
               fandoms: ["Hades (Video Game 2018)"], rating: "Teen And Up Audiences",
               words: 56_300, chapters: "12/20", progress: 0.55),
        Sample(title: "Night Market", author: "lanternlight",
               fandoms: ["呪術廻戦 | Jujutsu Kaisen (Manga)"], rating: "Teen And Up Audiences",
               words: 9_870, chapters: "2/3"),
        Sample(title: "Stars Over Tatooine", author: "binarysun",
               fandoms: ["Star Wars - All Media Types"], rating: "General Audiences",
               words: 6_540, chapters: "1/1", onDevice: false)
    ]
}

/// Simulator-only: `-KudosDebugRoute <route>` opens a screen at launch for
/// design review. `library`, `browse`, `account`, `search`,
/// `section:<LibrarySectionKind>`, and on Home's stack `queues`,
/// `queue:<name>`, `queue-details:<name>`.
@MainActor
enum DebugLaunchRoute {
    static var value: String? { UserDefaults.standard.string(forKey: "KudosDebugRoute") }

    static func applyTab(_ router: AppRouter) {
        guard let value else { return }
        if libraryRoutes.contains(where: value.hasPrefix) {
            router.selection = .library
        } else if value.hasPrefix("acct:") {
            router.selection = .account
        } else if value.hasPrefix("section:"),
           let kind = LibrarySectionKind(rawValue: String(value.dropFirst("section:".count))) {
            router.showLibrarySection(kind)
        } else if value.hasPrefix("tagsearch:") {
            // `tagsearch:<fandom>` — Search's results for a fandom tag.
            router.searchAO3(.fandom, String(value.dropFirst("tagsearch:".count)))
        } else if let tab = AppTab(rawValue: value) {
            router.selection = tab
        }
    }

    /// Home's stack, once its queries have loaded.
    static func homeDestination(queues: [ReadingQueue]) -> AllReadingQueuesDestination? {
        guard let value else { return nil }
        if value == "queues" { return AllReadingQueuesDestination(initialQueueID: nil) }
        if let prefix = ["queue:", "queue-details:"].first(where: value.hasPrefix) {
            let name = String(value.dropFirst(prefix.count))
            return queues.first { $0.displayName == name }.map { AllReadingQueuesDestination(initialQueueID: $0.id) }
        }
        return nil
    }

    /// `queue-details:<name>` opens the queue page, then its Details.
    static var opensQueueDetails: Bool { value?.hasPrefix("queue-details:") == true }

    private static let libraryRoutes = ["collections", "collection:", "recentlyDeleted", "insights"]

    /// `acct:<screen>` on the Account tab (pair with `-KudosFixtureDir` and
    /// `-KudosDemoSignedIn YES`): dashboard, drafts, works, series, inbox,
    /// preferences, more, collections, later, bookmarks, history, subscriptions.
    /// Appends by concrete type — navigation matches destinations by type, so
    /// an `AnyHashable` would find none.
    static func applyAccount(to path: inout NavigationPath) {
        switch accountTarget() {
        case let route as AccountView.Route: path.append(route)
        case let kind as AO3AccountWorksList.Kind: path.append(kind)
        default: break
        }
    }

    /// `acct:workedit:<id>` opens Work Edit for that AO3 work (the fixture
    /// harness serves `/works/<id>/edit`).
    static var accountEditWorkID: Int? {
        guard let value, value.hasPrefix("acct:workedit:") else { return nil }
        return Int(value.dropFirst("acct:workedit:".count))
    }

    private static func accountTarget() -> Any? {
        guard let value, value.hasPrefix("acct:") else { return nil }
        switch String(value.dropFirst("acct:".count)) {
        case "dashboard": return AccountView.Route.dashboard
        case "drafts": return AccountView.Route.drafts
        case "works": return AccountView.Route.myWorks
        case "series", "seriesedit": return AccountView.Route.mySeries
        case "inbox": return AccountView.Route.inbox
        case "preferences": return AccountView.Route.preferences
        case "more": return AccountView.Route.moreOnAO3
        case "settings": return AccountView.Route.settings
        case "collections": return AccountView.Route.myCollections
        case "later": return AO3AccountWorksList.Kind.markedForLater
        case "bookmarks": return AO3AccountWorksList.Kind.bookmarks
        case "history": return AO3AccountWorksList.Kind.history
        case "subscriptions": return AO3AccountWorksList.Kind.subscriptions
        default: return nil
        }
    }

    /// Library's stack: `collections`, `collection:<name>`, `recentlyDeleted`, `insights`.
    static func applyLibrary(to path: inout NavigationPath, collections: [WorkCollection]) {
        guard let value else { return }
        switch value {
        case "collections": path.append(AllCollectionsDestination())
        case "recentlyDeleted": path.append(RecentlyDeletedDestination())
        case "insights": path.append(ReadingInsightsDestination())
        default:
            if value.hasPrefix("collection:"),
               let collection = collections.first(where: { $0.name == String(value.dropFirst("collection:".count)) }) {
                path.append(collection)
            }
        }
    }

    /// `work:<title>` opens that work's detail page on Home's stack.
    static var opensReader: Bool { value?.hasPrefix("read:") == true }

    /// `homesection:<HomeSectionKind raw value>` pushes that Home section list.
    static func homeSection() -> HomeSectionKind? {
        guard let value, value.hasPrefix("homesection:") else { return nil }
        return HomeSectionKind(rawValue: String(value.dropFirst("homesection:".count)))
    }

    /// With `-KudosFixtureDir`, demo works get the fixture EPUB in place of the
    /// zero-filled placeholder, so the reader has a real book to open.
    static func installFixtureEPUBs(in works: [SavedWork]) {
        guard let directory = DemoNetworkBlock.fixtureDirectory else { return }
        // A well-formed XHTML book; `sample.epub` is bare XML and renders unstyled.
        let source = directory.appendingPathComponent("demo_work.epub")
        guard let epub = try? Data(contentsOf: source) else { return }
        for work in works {
            let url = work.fileURL
            // Demo works only ever hold a placeholder or this book.
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size != epub.count else { continue }
            try? epub.write(to: url)
        }
    }

    static func homeWork(in works: [SavedWork]) -> SavedWork? {
        // `mycopy:<title>` opens the same page with its My copy sheet up;
        // `read:<title>` opens the reader instead (see `opensReader`).
        guard let value, let prefix = ["work:", "mycopy:", "read:"].first(where: value.hasPrefix) else { return nil }
        let title = String(value.dropFirst(prefix.count))
        return works.first { $0.title == title }
    }
}
/// `-KudosDebugRoute comments`: real comment rows over sample data, for
/// checking the byline against the avatar without contacting AO3.
struct CommentsDemoView: View {
    @State private var swipeTracker = CommentSwipeTracker()
    private func comment(_ id: Int, _ author: String, chapter: String? = nil, _ body: String) -> AO3Comment {
        var comment = AO3Comment(id: id, author: author, isGuest: false)
        comment.userPath = "/users/\(author)"
        comment.postedText = "Wed 08 Jul 2026 02:38PM UTC"
        comment.chapterLabel = chapter
        comment.bodyText = body
        comment.canReply = true
        return comment
    }

    var body: some View {
        List {
            row(.post(comment: comment(1, "nine_of_wands", chapter: "Chapter 3", "Root with replies."),
                      parentAuthor: nil, depth: 0),
                depth: 0, starts: true, next: 1, collapse: CommentCollapseState(isCollapsed: false, replyCount: 2))
            row(.post(comment: comment(2, "frostbitten", "A reply."), parentAuthor: "nine_of_wands", depth: 1),
                depth: 1, starts: false, next: 2, ancestors: [1])
            row(.post(comment: comment(3, "undertow", "A reply to the reply."), parentAuthor: "frostbitten",
                      depth: 2), depth: 2, starts: false, next: 0, ancestors: [1, 2])
            row(.post(comment: comment(4, "lanternlight", chapter: "Chapter 1", "Root without replies."),
                      parentAuthor: nil, depth: 0), depth: 0, starts: true, next: nil)
        }
        .cardList()
        .coordinateSpace(.named(CommentThreadGeometry.listSpace))
        .environment(swipeTracker)
        .background(.background)
    }

    private func row(
        _ item: CommentConversationItem, depth: Int, starts: Bool, next: Int?,
        collapse: CommentCollapseState? = nil, ancestors: [Int] = []
    ) -> some View {
        CommentConversationRow(
            item: item, workAuthors: ["nine_of_wands"], showChapterBadge: true,
            startsConversation: starts, depth: depth, isLastSibling: true,
            ancestorLines: Array(repeating: false, count: depth), nextDepth: next, collapse: collapse,
            ancestorIDs: ancestors
        )
        .commentSwipeActions(comment: item.actionableComment)
    }
}
/// With the demo library on, every request to AO3 fails at once, on every
/// session — the design-review simulator must never touch the real site, even
/// when a screen it opens would normally fetch (owner rule: never contact
/// archiveofourown.org). Off, this is inert.
final class DemoNetworkBlock: URLProtocol {
    static var isActive: Bool { UserDefaults.standard.bool(forKey: "KudosDemoLibrary") }

    /// For a session built from its own configuration (the AO3 client, auth).
    static func install(into configuration: URLSessionConfiguration) {
        guard isActive else { return }
        configuration.protocolClasses = [DemoNetworkBlock.self] + (configuration.protocolClasses ?? [])
    }

    /// For `URLSession.shared` (AsyncImage avatars and covers).
    static func installGlobally() {
        guard isActive else { return }
        URLProtocol.registerClass(DemoNetworkBlock.self)
    }

    override static func canInit(with request: URLRequest) -> Bool {
        guard isActive, let host = request.url?.host?.lowercased() else { return false }
        return host == "archiveofourown.org" || host.hasSuffix(".archiveofourown.org")
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    /// `-KudosFixtureDir <path>` (simulator only reads the host path): answer
    /// AO3 from the test fixtures instead of failing, so AO3 screens can be
    /// reviewed without the network. Local stub — AO3 is never contacted.
    static var fixtureDirectory: URL? {
        UserDefaults.standard.string(forKey: "KudosFixtureDir").map { URL(fileURLWithPath: $0) }
    }

    /// `-KudosDemoSignedIn YES` with the demo library: a local demo session.
    static var demoSignedIn: Bool { isActive && UserDefaults.standard.bool(forKey: "KudosDemoSignedIn") }

    /// Path pattern → fixture file, first match wins.
    private static let routes: [(pattern: String, fixture: String)] = [
        ("^/works/new", "ao3_work_new_draft"),
        ("^/works/\\d+/edit", "ao3_work_edit"),
        ("comments", "ao3_comments_page"),
        ("^/works/\\d+", "ao3_work_bookmarked_subscribed"),
        ("edit_multiple", "ao3_edit_multiple"),
        ("^/media/[^/]+/fandoms", "ao3_media_fandoms"),
        ("^/media/?$", "ao3_media"),
        // A works index has the same blurb markup wherever it is listed.
        ("^/tags/[^/]+/works", "ao3_tag_works"),
        ("^/works/search", "ao3_tag_works"),
        ("^/users/[^/]+/(pseuds/[^/]+/)?works", "ao3_author_works"),
        ("^/users/[^/]+/(pseuds/[^/]+/)?series", "ao3_author_series"),
        ("^/users/[^/]+/(pseuds/[^/]+/)?bookmarks", "ao3_author_bookmarks"),
        ("^/users/[^/]+/readings", "ao3_readings"),
        ("^/users/[^/]+/subscriptions", "ao3_subscriptions"),
        ("^/users/[^/]+/inbox", "ao3_inbox_manage"),
        ("^/users/[^/]+/preferences", "ao3_preferences"),
        ("^/users/[^/]+/stats", "ao3_user_stats"),
        ("^/users/[^/]+/profile", "ao3_author_profile"),
        ("^/users/[^/]+/pseuds/[^/]+/?$", "ao3_author_pseud_dashboard"),
        ("^/users/[^/]+/?$", "ao3_author_dashboard_demo"),
        ("^/help/preferences_privacy", "ao3_help_preferences_privacy"),
        ("^/?$", "ao3_logged_in")
    ]

    static func fixture(for url: URL) -> String? {
        let path = url.path
        return routes.first { path.range(of: $0.pattern, options: .regularExpression) != nil }?.fixture
    }

    override func startLoading() {
        guard let url = request.url, let directory = Self.fixtureDirectory else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let name = Self.fixture(for: url)
        let data = name.flatMap { try? Data(contentsOf: directory.appendingPathComponent("\($0).html")) }
        let response = HTTPURLResponse(
            url: url, statusCode: data == nil ? 404 : 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/html; charset=utf-8"]
        )
        if let response { client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
        client?.urlProtocol(self, didLoad: data ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
#endif
