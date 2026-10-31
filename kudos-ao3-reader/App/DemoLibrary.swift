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
        seedHeldCopy(in: context, existing: all)
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

    /// A finished, un-kept work whose copy waits in Recently Deleted's "Finished,
    /// not kept" section — the only demo work with an AO3 id, because that
    /// section holds AO3 works only (an import is always kept). The id is a
    /// placeholder; the demo blocks AO3 anyway.
    private static func seedHeldCopy(in context: ModelContext, existing: [SavedWork]) {
        let title = "Tea in the Jasmine Dragon"
        guard !existing.contains(where: { $0.title == title }) else { return }
        let work = SavedWork(title: title, author: "uncle_iroh_fan", summary: "")
        work.workFandoms = ["Avatar: The Last Airbender"]
        work.rating = "General Audiences"
        work.wordCount = 8_120
        work.chapters = "3/3"
        work.ao3WorkID = 999_000_001
        context.insert(work)
        writePlaceholder(for: work)
        work.isFinished = true
        work.freedAt = Date().addingTimeInterval(-9 * 86_400)
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

/// One step Browse takes for a `shot:` route. Interpreted only inside `BrowseView`,
/// because `FandomRoute` is private there.
enum DebugBrowseStep: Equatable {
    /// Push a media category's fandom index (`AO3MediaCategory`).
    case media(name: String, fandomsURL: String)
    /// Push that fandom's works, the way a row tap does.
    case fandom(names: [String], title: String)
    /// Push a tag's works page.
    case tag(url: String, title: String)
}

/// `-KudosDebugRoute shot:<name>` (A82). `route` is an existing page route.
/// `sheets` and `pushes` open on top once that page is up. With nothing pending,
/// no screen reads these.
struct DebugShot {
    var route: String
    var sheets: [String] = []
    var pushes: [String] = []
    var manageRow: String?
    var browse: [DebugBrowseStep] = []
}

/// The A82 names, in that audit's order. One map; views only ask `takeSheet` / `takePush`.
enum DebugShots {
    private static let tvShows = DebugBrowseStep.media(
        name: "TV Shows", fandomsURL: "https://archiveofourown.org/media/TV%20Shows/fandoms"
    )
    private static let doctorWho = DebugBrowseStep.fandom(names: ["Doctor Who"], title: "Doctor Who")
    private static let starWars = DebugBrowseStep.tag(
        url: "https://archiveofourown.org/tags/Star%20Wars/works", title: "Star Wars"
    )
    private static let neon = "queue:Neon reread"
    private static let neonDetails = "queue-details:Neon reread"
    private static let sodium = "work:Sodium Lights"
    private static let readSodium = "read:Sodium Lights"
    private static let winter = "acct:ao3collection:winter_exchange"
    private static let posted = "acct:workedit:1001"
    private static let starSearch = "tagsearch:Star Wars"

    static let ordered: [(name: String, shot: DebugShot)] = [
        ("libpicker", DebugShot(route: "library", sheets: ["libpicker"])),
        ("queuesettings", DebugShot(route: neonDetails)),
        ("newqueue", DebugShot(route: "queues", sheets: ["newqueue"])),
        ("editqueue", DebugShot(route: neon, sheets: ["editqueue"])),
        ("addworks", DebugShot(route: neon, sheets: ["addworks"])),
        ("queuetag", DebugShot(route: neonDetails, sheets: ["queuetag"])),
        ("queuetags", DebugShot(route: neonDetails, pushes: ["queuetags"])),
        ("queuetagedit", DebugShot(route: neonDetails, pushes: ["queuetags", "queuetagedit"])),
        ("bulktag", DebugShot(route: "library", sheets: ["bulktag"])),
        ("addtoqueue", DebugShot(route: sodium, sheets: ["addtoqueue"])),
        ("queuestorage", DebugShot(route: "acct:settings:readingQueues", pushes: ["queuestorage"])),
        ("collectiondetails", DebugShot(route: "collection:Comfort reads", sheets: ["collectiondetails"])),
        ("newcollection", DebugShot(route: "library", sheets: ["newcollection"])),
        ("collectionreorder", DebugShot(route: "collection:Comfort reads", sheets: ["collectionreorder"])),
        ("addtocollection", DebugShot(route: sodium, sheets: ["addtocollection"])),
        ("fandomlist", DebugShot(route: "browse", browse: [tvShows])),
        ("fandomworks", DebugShot(route: "browse", browse: [tvShows, doctorWho])),
        ("tagworks", DebugShot(route: "browse", browse: [starWars])),
        ("fandomfilter", DebugShot(route: "browse", sheets: ["fandomfilter"], browse: [tvShows])),
        ("savesearch", DebugShot(route: starSearch, sheets: ["savesearch"])),
        ("pagejump", DebugShot(route: starSearch, sheets: ["pagejump"])),
        ("languagepicker", DebugShot(route: starSearch, pushes: ["languagepicker"])),
        ("tagpicker", DebugShot(route: starSearch, sheets: ["tagpicker"])),
        ("downloaddate", DebugShot(route: sodium, sheets: ["downloaddate"])),
        ("seriespreserve", DebugShot(route: sodium, sheets: ["seriespreserve"])),
        ("bookmarkform", DebugShot(route: sodium, sheets: ["bookmarkform"])),
        ("readercontents", DebugShot(route: readSodium, sheets: ["readercontents"])),
        ("readerfind", DebugShot(route: readSodium, sheets: ["readerfind"])),
        ("readerdisplay", DebugShot(route: readSodium, sheets: ["readerdisplay"])),
        ("readernote", DebugShot(route: readSodium, sheets: ["readernote"])),
        ("pronunciations", DebugShot(route: "acct:settings:listening", pushes: ["pronunciations"])),
        ("pronunciationedit", DebugShot(
            route: "acct:settings:listening", sheets: ["pronunciationedit"], pushes: ["pronunciations"]
        )),
        ("customizetheme", DebugShot(route: "acct:settings:appearance", sheets: ["customizetheme"])),
        ("formattingtray", DebugShot(route: "compose:Sodium Lights", sheets: ["formattingtray"])),
        ("chapterpicker", DebugShot(route: "comments:Sodium Lights", sheets: ["chapterpicker"])),
        ("inboxfilter", DebugShot(route: "acct:inbox", sheets: ["inboxfilter"])),
        ("authorabout", DebugShot(route: "acct:dashboard", sheets: ["authorabout"])),
        // Two screens Android lacked until 3gu (A81 rows 63 and 85); not in A82's list.
        ("authorbookmarks", DebugShot(route: "acct:dashboard", sheets: ["authorbookmarks"])),
        ("readerspeech", DebugShot(route: readSodium, sheets: ["readerspeech"])),
        ("seriesdetail", DebugShot(route: "acct:series", pushes: ["seriesdetail"])),
        ("seriesedit", DebugShot(route: "acct:seriesedit")),
        ("seriesreorder", DebugShot(route: "acct:series", sheets: ["seriesreorder"])),
        ("seriesremove", DebugShot(route: "acct:seriesedit", pushes: ["seriesremove"])),
        ("authorworksfilter", DebugShot(route: "acct:works", sheets: ["authorworksfilter"])),
        ("colitems", DebugShot(route: "acct:collections", sheets: ["colitems"])),
        ("colsfilter", DebugShot(route: "acct:collections", sheets: ["colsfilter"])),
        ("chsettingsedit", DebugShot(route: winter, pushes: ["chsettingsedit"], manageRow: "Challenge Settings")),
        ("chsignupdetail", DebugShot(route: winter, pushes: ["chsignupdetail"], manageRow: "Sign-ups")),
        ("prompttags", DebugShot(route: winter, sheets: ["prompttags"], manageRow: "Your Sign-up")),
        ("tagset", DebugShot(route: winter, pushes: ["tagset"], manageRow: "Challenge Settings")),
        ("tagseteditor", DebugShot(
            route: winter, pushes: ["tagset", "tagseteditor"], manageRow: "Challenge Settings"
        )),
        ("writingpreview", DebugShot(route: "acct:workedit:1002", sheets: ["writingpreview"])),
        ("chapters", DebugShot(route: posted, pushes: ["chapters"])),
        ("chapterform", DebugShot(route: posted, pushes: ["chapterform"])),
        ("edittags", DebugShot(route: posted, pushes: ["edittags"])),
        ("tagseditor", DebugShot(route: posted, pushes: ["edittags", "tagseditor"])),
        ("texteditor", DebugShot(route: posted, pushes: ["texteditor"])),
        ("recovery", DebugShot(route: posted, pushes: ["recovery"])),
        ("seriespicker", DebugShot(route: posted, pushes: ["seriespicker"])),
        ("collectionsgifts", DebugShot(route: posted, pushes: ["collectionsgifts"])),
        ("creatorspicker", DebugShot(route: posted, pushes: ["creatorspicker"])),
        ("parentpicker", DebugShot(route: posted, pushes: ["parentpicker"])),
        ("bulkedit", DebugShot(route: "acct:works", sheets: ["bulkedit"])),
        ("bulktagstate", DebugShot(route: "acct:works", sheets: ["bulkedit"], pushes: ["bulktagstate"])),
        ("bulknames", DebugShot(route: "acct:works", sheets: ["bulkedit"], pushes: ["bulknames"])),
        ("prefhelp", DebugShot(route: "acct:preferences", sheets: ["prefhelp"])),
        ("privacydata", DebugShot(route: "acct:settings:privacy")),
        ("availability", DebugShot(route: "acct:settings:preservation", sheets: ["availability"])),
        ("pairing", DebugShot(route: "acct:settings:syncFolder", sheets: ["pairing"])),
        ("revokedevice", DebugShot(route: "acct:settings:syncFolder", sheets: ["revokedevice"])),
        ("backupimport", DebugShot(route: "acct:settings:backup", sheets: ["backupimport"])),
        ("aboutkudos", DebugShot(route: "acct:settings:about", sheets: ["aboutkudos"])),
    ]

    static var names: [String] { ordered.map(\.name) }
    static let byName: [String: DebugShot] = Dictionary(
        uniqueKeysWithValues: ordered.map { ($0.name, $0.shot) }
    )
}

/// Identity for a debug-only `navigationDestination(item:)`.
struct DebugPresented: Hashable, Identifiable {
    var id: String
}

/// Simulator-only: `-KudosDebugRoute <route>` opens a screen at launch for
/// design review. `library`, `browse`, `account`, `search`,
/// `section:<LibrarySectionKind>`, and on Home's stack `queues`,
/// `queue:<name>`, `queue-details:<name>`. `shot:<name>` is an A82 screen:
/// the same page route, plus the sheet or child page named in `DebugShots`.
@MainActor
enum DebugLaunchRoute {
    #if os(iOS)
    /// `-KudosDebugRotate "8 landscape 16 portrait"`: turns the window at those seconds after launch, so
    /// a shot can catch a screen after a change of size (the Simulator has no rotate command).
    @MainActor static func runRotations() async {
        let steps = (UserDefaults.standard.string(forKey: "KudosDebugRotate") ?? "").split(separator: " ")
        var elapsed = 0.0
        for index in stride(from: 0, to: steps.count - 1, by: 2) {
            guard let seconds = Double(steps[index]) else { return }
            try? await Task.sleep(for: .seconds(max(0, seconds - elapsed)))
            elapsed = seconds
            let mask: UIInterfaceOrientationMask = steps[index + 1] == "portrait" ? .portrait : .landscapeRight
            ReaderOrientationLock.activeScene?.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        }
    }
    #endif

    static var value: String? { UserDefaults.standard.string(forKey: "KudosDebugRoute") }
    static var opensLogin: Bool { value == "login" }
    /// `-KudosDebugOpenFilters YES`: the routed screen opens its filter panel.
    static var opensFilters: Bool { UserDefaults.standard.bool(forKey: "KudosDebugOpenFilters") }

    static var shotName: String? {
        guard let value, value.hasPrefix("shot:") else { return nil }
        let name = String(value.dropFirst("shot:".count))
        return name.isEmpty ? nil : name
    }

    static var shot: DebugShot? { shotName.flatMap { DebugShots.byName[$0] } }

    /// The page an existing helper should open. A shot uses its mapped route;
    /// every other launch is unchanged.
    static var pageRoute: String? { shot?.route ?? value }

    /// `-KudosDebugManageRow <label>`, or the row a shot names.
    static var manageRow: String? {
        if let row = shot?.manageRow { return row }
        return UserDefaults.standard.string(forKey: "KudosDebugManageRow")
    }

    /// True while this id is still pending. Does not consume it, so a parent
    /// can stay open while a child takes a different id.
    private static var taken: Set<String> = []

    static func wantsSheet(_ id: String) -> Bool {
        shot?.sheets.contains(id) == true && !taken.contains("s:\(id)")
    }

    static func takeSheet(_ id: String) -> Bool {
        guard wantsSheet(id) else { return false }
        taken.insert("s:\(id)")
        return true
    }

    static func wantsPush(_ id: String) -> Bool {
        shot?.pushes.contains(id) == true && !taken.contains("p:\(id)")
    }

    static func takePush(_ id: String) -> Bool {
        guard wantsPush(id) else { return false }
        taken.insert("p:\(id)")
        return true
    }

    /// The first still-pending push among `ids`, consumed.
    static func takeFirstPush(_ ids: [String]) -> String? {
        guard let id = ids.first(where: wantsPush) else { return nil }
        taken.insert("p:\(id)")
        return id
    }

    static func takeBrowse() -> [DebugBrowseStep] {
        guard let steps = shot?.browse, !steps.isEmpty, taken.insert("browse").inserted else { return [] }
        return steps
    }

    /// Search filters, for the shots whose sheet or picker lives on that panel.
    static var opensSearchFilters: Bool { opensFilters || wantsSearchFilters }

    static var wantsSearchFilters: Bool {
        wantsSheet("savesearch") || wantsSheet("tagpicker") || wantsPush("languagepicker")
    }

    /// A recovery copy for the notes field of work 1001, only for `shot:recovery`.
    /// The summary editor (`shot:texteditor`) finds nothing. Both account keys:
    /// the editor uses `auth.username ?? ""`.
    static func prepareShot() {
        guard shotName == "recovery" else { return }
        var store = WritingTextRecovery()
        let text = "Demo recovery copy for the notes field."
        for account in ["AO3_Reader", ""] {
            // The posted fixture form (`ao3_work_edit.html`) is work 424242, whatever the route names.
            let key = store.fileURL(account: account, target: "work:424242", field: "notes")
            let url = key.deletingPathExtension()
                .appendingPathExtension("shot-recovery")
                .appendingPathExtension("json")
            if (try? store.load(from: url))?.text == text { continue }
            try? store.save(text: text, original: "form", to: url)
        }
    }

    /// A paired "Demo reading tablet" trusted far enough ago that Revoke shows.
    /// When the keychain will not take the key, the sheet still has a device to name.
    static func revokedDevice() -> TrustedDevice {
        let key = String(repeating: "ab", count: 32)
        let past = Date().addingTimeInterval(-(TombstoneTrustStore.undoTrustWindow + 3_600))
        // Only the demo's own trust store gets the made-up key (A83); elsewhere the sheet still
        // has a device to name.
        if DemoNetworkBlock.isActive {
            let clock = TombstoneSigning.now
            TombstoneSigning.now = { past }
            _ = TombstoneTrustStore.add(key, label: "Demo reading tablet")
            TombstoneSigning.now = clock
        }
        if let stored = TombstoneTrustStore.trustedDevices().first(where: { $0.label == "Demo reading tablet" }) {
            return stored
        }
        return TrustedDevice(publicKeyHex: key, label: "Demo reading tablet", trustedAt: past)
    }

    static func applyTab(_ router: AppRouter) {
        guard let value = pageRoute else { return }
        if value == "queues" || homePrefixRoutes.contains(where: value.hasPrefix) {
            router.selection = .home
        } else if libraryRoutes.contains(where: value.hasPrefix) {
            router.selection = .library
        } else if value.hasPrefix("acct:") {
            let target = String(value.dropFirst("acct:".count))
            if target.hasPrefix("settings:") {
                router.showAccount()
            } else if target.hasPrefix("ao3collection:") || target.hasPrefix("workedit:") {
                router.selection = .writing
            } else if let route = legacyAccountRoute(target) {
                router.openLegacyAccountRoute(route)
            } else {
                router.showAccount()
            }
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
        guard let value = pageRoute else { return nil }
        if value == "queues" { return AllReadingQueuesDestination(initialQueueID: nil) }
        if let prefix = ["queue:", "queue-details:"].first(where: value.hasPrefix) {
            let name = String(value.dropFirst(prefix.count))
            return queues.first { $0.displayName == name }.map { AllReadingQueuesDestination(initialQueueID: $0.id) }
        }
        return nil
    }

    /// `queue-details:<name>` opens the queue page, then its Details.
    static var opensQueueDetails: Bool { pageRoute?.hasPrefix("queue-details:") == true }

    private static let libraryRoutes = ["collections", "collection:", "recentlyDeleted", "insights"]
    /// Resolved against Home's works, so they need Home selected; the app
    /// otherwise restores whichever tab the last launch left.
    private static let workRoutes = ["work:", "mycopy:", "read:", "comments:", "compose:", "thread:"]
    /// Queue routes resolve against Home's queues for the same reason.
    private static let homePrefixRoutes = workRoutes + ["queue:", "queue-details:"]

    /// `acct:<screen>` on the Account tab (pair with `-KudosFixtureDir` and
    /// `-KudosDemoSignedIn YES`): dashboard, drafts, works, series, inbox,
    /// preferences, more, collections, later, bookmarks, history, subscriptions.
    /// Appends by concrete type — navigation matches destinations by type, so
    /// an `AnyHashable` would find none.
    static func applyAccount(to path: inout NavigationPath) {
        // `acct:settings:<page>` — a Settings page by its `SettingsRoute` case name (backup,
        // syncFolder, about, …), for side-by-side screenshots with Android.
        if let value = pageRoute, value.hasPrefix("acct:settings:") {
            let name = String(value.dropFirst("acct:settings:".count))
            if let page = SettingsRoute.allCases.first(where: { "\($0)" == name }) {
                path.append(AccountView.Route.settings)
                path.append(page)
            }
            return
        }
    }

    /// Old Account debug routes keep working after their content moved tabs.
    static func applyWriting(to path: inout NavigationPath) {
        guard let value = pageRoute else { return }
        if value.hasPrefix("acct:ao3collection:") {
            let slug = String(value.dropFirst("acct:ao3collection:".count))
            path.append(AO3CollectionDestination(slug: slug, title: slug))
        }
    }

    /// `acct:workedit:<id>` opens Work Edit for that AO3 work (the fixture
    /// harness serves `/works/<id>/edit`).
    static var accountEditWorkID: Int? {
        guard let value = pageRoute, value.hasPrefix("acct:workedit:") else { return nil }
        return Int(value.dropFirst("acct:workedit:".count))
    }

    private static func legacyAccountRoute(_ target: String) -> LegacyAccountRoute? {
        switch target {
        case "dashboard": .dashboard
        case "drafts": .drafts
        case "works": .works
        case "series", "seriesedit": .series
        case "inbox": .inbox
        case "preferences": .preferences
        case "more": .moreOnAO3
        case "settings": .settings
        case "collections": .collections
        case "later": .markedForLater
        case "bookmarks": .bookmarks
        case "history": .history
        case "subscriptions": .subscriptions
        default: nil
        }
    }

    /// Library's stack: `collections`, `collection:<name>`, `recentlyDeleted`, `insights`.
    static func applyLibrary(to path: inout NavigationPath, collections: [WorkCollection]) {
        guard let value = pageRoute else { return }
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
    static var opensReader: Bool { pageRoute?.hasPrefix("read:") == true }

    /// `homesection:<HomeSectionKind raw value>` pushes that Home section list.
    static func homeSection() -> HomeSectionKind? {
        guard let value = pageRoute, value.hasPrefix("homesection:") else { return nil }
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

    /// `comments:<title>` opens that work's page, then its Comments (fixture-served),
    /// for side-by-side screenshots with Android's `comments/<ao3 id>`; `compose:<title>` opens
    /// the comment composer over them; `thread:<title>` pushes the first conversation's
    /// Thread screen. A demo import has no AO3 id; it borrows Android's demo id
    /// for the same work (the fixture page is the same).
    static func commentsRoute(for work: SavedWork) -> AO3CommentsRoute? {
        guard let value = pageRoute,
              ["comments:", "compose:", "thread:"].contains(where: value.hasPrefix) else { return nil }
        var route = AO3CommentsRoute(workID: work.ao3WorkID ?? 999_000_005, context: AO3CommentsWorkContext(
            title: work.title, authors: [work.author], fandoms: work.workFandoms,
            rating: work.rating, chapters: work.chapters
        ))
        route.composes = value.hasPrefix("compose:")
        return route
    }

    /// Opens the same subtree as the comments list's "Continue thread" action,
    /// after the fixture has loaded, with the real parent view owning its actions.
    static func threadRootID(in model: CommentsModel) -> Int? {
        guard value?.hasPrefix("thread:") == true else { return nil }
        for row in model.conversationRows {
            if case let .continueThread(rootID, _) = row.item { return rootID }
        }
        return model.displayThreads.first(where: { !$0.replies.isEmpty })?.id
            ?? model.displayThreads.first?.id
    }

    /// `author:<username>` opens another reader's AO3 profile (fixture-served) on Home's stack.
    static var authorRoute: AO3AuthorRoute? {
        guard let value = pageRoute, value.hasPrefix("author:") else { return nil }
        return AO3AuthorRoute(username: String(value.dropFirst("author:".count)))
    }

    static func homeWork(in works: [SavedWork]) -> SavedWork? {
        // `mycopy:<title>` opens the same page with its My copy sheet up;
        // `read:<title>` opens the reader instead (see `opensReader`).
        guard let value = pageRoute, let prefix = workRoutes.first(where: value.hasPrefix) else { return nil }
        let title = String(value.dropFirst(prefix.count))
        return works.first { $0.title == title }
    }
}

/// A fresh, unrestored auth service keeps the native form signed out even when
/// the surrounding demo uses `-KudosDemoSignedIn YES`. No stored session is erased.
struct DebugLoginView: View {
    @State private var auth = AO3AuthService()

    var body: some View {
        AO3LoginView().environment(auth)
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
        // Writing's own pages (the same ones Android's demo answers with). Without them "Add
        // chapter", "Chapters" and a series's page each ended at "Couldn't load", and none of
        // the three screens could be looked at.
        ("^/works/\\d+/chapters/new", "ao3_demo_chapter_995006_new"),
        ("^/works/\\d+/chapters/\\d+/edit", "ao3_demo_chapter_995006_posted"),
        ("^/works/\\d+/navigate", "ao3_chapter_navigate"),
        // One work whose form is a draft's: every work opened the posted work's form, so the
        // draft's own sections (Post, Preview, Delete draft) could not be looked at.
        ("^/works/1002/edit", "ao3_demo_work_draft_edit"),
        ("^/works/\\d+/edit", "ao3_work_edit"),
        ("comments", "ao3_comments_page"),
        ("^/works/\\d+", "ao3_work_bookmarked_subscribed"),
        ("edit_multiple", "ao3_edit_multiple"),
        // Collections and challenges (task 5). Most specific first.
        ("^/series/\\d+/edit", "ao3_series_edit"),
        // A series's works in order, for Reorder and Remove works (Android's demo serves the same page).
        ("^/series/\\d+/manage", "ao3_demo_series_manage"),
        ("^/series/\\d+/?$", "ao3_demo_dawn_series"),
        ("^/collections/[^/]+/signups/\\d+", "ao3_challenge_signup"),
        // "Your Sign-up" with none yet asks for the blank form; it got the list, and said
        // "Couldn't load sign-up".
        ("^/collections/[^/]+/signups/new", "ao3_challenge_signup"),
        ("^/collections/[^/]+/signups", "ao3_challenge_signups"),
        ("^/collections/[^/]+/assignments", "ao3_challenge_assignments"),
        ("^/collections/[^/]+/(gift_exchange|prompt_meme)", "ao3_challenge_settings"),
        ("^/collections/[^/]+/items", "ao3_collection_items"),
        ("^/collections/[^/]+/participants", "ao3_collection_participants"),
        // The profile page carries the same Tag Set list as the show page.
        ("^/collections/[^/]+/profile", "ao3_collection_show"),
        ("^/collections/[^/]+/edit", "ao3_collection_edit"),
        ("^/collections/[^/]+/requests", "ao3_challenge_requests"),
        ("^/collections/[^/]+/works", "ao3_tag_works"),
        ("^/collections/[^/]+/?$", "ao3_collection_show"),
        ("^/users/[^/]+/collections", "ao3_collections_index"),
        // "Your items" (the reader's own works in collections) said "Couldn't load collection
        // items": the demo had no page for it. The same page Android's demo answers with.
        ("^/users/[^/]+/collection_items", "ao3_demo_user_collection_items"),
        ("^/tag_sets/\\d+", "ao3_tag_set"),
        ("^/media/[^/]+/fandoms", "ao3_media_fandoms"),
        ("^/media/?$", "ao3_media"),
        // A works index has the same blurb markup wherever it is listed.
        ("^/tags/[^/]+/works", "ao3_tag_works"),
        ("^/works/search", "ao3_tag_works"),
        ("^/users/[^/]+/(pseuds/[^/]+/)?works", "ao3_author_works"),
        // The demo account's own series, by the demo account: with another creator's page the
        // reader was never one of a series's creators, and "Edit series" and "Reorder" were
        // never offered.
        ("^/users/AO3_Reader/(pseuds/[^/]+/)?series", "ao3_demo_author_series"),
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
        // A work's comments are its own page with `show_comments=true`, so the path alone gave the
        // work page and the real Comments screen could never be opened in the demo: it said
        // "Couldn't Load Comments".
        if url.query?.contains("show_comments=true") == true { return "ao3_comments_page" }
        let path = url.path
        return routes.first { path.range(of: $0.pattern, options: .regularExpression) != nil }?.fixture
    }

    override func startLoading() {
        guard let url = request.url, let directory = Self.fixtureDirectory else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let name = Self.isPreview(request) ? "ao3_demo_work_preview" : Self.fixture(for: url)
        let data = name.flatMap { try? Data(contentsOf: directory.appendingPathComponent("\($0).html")) }
        let response = HTTPURLResponse(
            url: url, statusCode: data == nil ? 404 : 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/html; charset=utf-8"]
        )
        if let response { client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
        client?.urlProtocol(self, didLoad: data ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    /// A form's Preview (`preview_button`) is a POST AO3 answers with the preview page. By its
    /// path alone it got the work's own page, and the editor said AO3 returned no preview.
    private static func isPreview(_ request: URLRequest) -> Bool {
        guard request.httpMethod == "POST" else { return false }
        let body = request.httpBody ?? request.httpBodyStream.map(readAll) ?? Data()
        return String(bytes: body, encoding: .utf8)?.contains("preview_button") == true
    }

    private static func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    override func stopLoading() {}
}
#endif
