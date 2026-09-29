#if DEBUG
import Foundation
import SwiftData

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
        guard !existing.contains(where: { $0.title == samples[0].title }) else { return }

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
        if value.hasPrefix("section:"),
           let kind = LibrarySectionKind(rawValue: String(value.dropFirst("section:".count))) {
            router.showLibrarySection(kind)
        } else if let tab = AppTab(rawValue: value) {
            router.selection = tab
        }
    }

    /// Home's stack, once its queries have loaded.
    static func homeDestination(queues: [ReadingQueue]) -> AllReadingQueuesDestination? {
        guard let value else { return nil }
        if value == "queues" { return AllReadingQueuesDestination(initialQueueID: nil) }
        if value.hasPrefix("queue:") {
            let name = String(value.dropFirst("queue:".count))
            return queues.first { $0.displayName == name }.map { AllReadingQueuesDestination(initialQueueID: $0.id) }
        }
        return nil
    }
}
#endif
