#if os(iOS)
import Foundation
import Testing
@testable import Kudos

/// Builds a TTS test corpus using **the app's own `AO3Client`**, so every
/// request carries the app's identity and politeness policy rather than a
/// hand-rolled one:
///
/// - the shared `AO3RequestDefaults.userAgent` — browser-like base plus an
///   honest `KudosReader/<version>` product token and contact URL, so AO3
///   admins can identify and reach the app
/// - `pace()`, a 0.6 s floor between requests
/// - `withRetry` with backoff, honouring `Retry-After` on 429
/// - Cloudflare challenge-cookie handling
///
/// Hand-rolled `curl` against AO3's kudos-sorted listings timed out and then
/// returned 525; that is an expensive query for them and it deserves the app's
/// pacing, not a tight loop.
///
/// **Network test. Skipped unless a destination is set**, so it never runs in a
/// normal suite:
///
///     TEST_RUNNER_KOKORO_HARVEST_DIR=/path/to/epubs xcodebuild test \
///       -only-testing:KudosTests/KokoroCorpusHarvestTests
///
/// Targets are declared in `targets` below. Downloaded works are third-party
/// fiction: they stay local, are never committed, and only aggregate
/// statistics about them are ever recorded.
@Suite("Kokoro corpus harvest", .serialized)
struct KokoroCorpusHarvestTests {
    private static var destination: String {
        let env = ProcessInfo.processInfo.environment
        return env["TEST_RUNNER_KOKORO_HARVEST_DIR"] ?? env["KOKORO_HARVEST_DIR"] ?? ""
    }

    /// One corpus target. `fandom` and/or `additionalTags` narrow it; `sort`
    /// decides *which* work comes back, and that choice is load-bearing.
    struct Target: Sendable {
        var label: String
        var fandom: String = ""
        var additionalTags: String = ""
        var sort: AO3SearchFilters.Sort = .kudos
        var wordsFrom: String = "150000"
    }

    /// Two deliberately different sampling strategies.
    ///
    /// **By kudos** finds well-liked work — which is also, reliably, *cleanly
    /// typeset* work. Sorting by kudos selects against exactly the formatting
    /// problems a reader app has to survive, so it can never be the whole
    /// corpus.
    ///
    /// **By AO3's own convention tags** finds the rest: `Not Beta Read` is the
    /// archive's marker for unedited prose (typos, inconsistent punctuation),
    /// and `Chat Fic` / `Epistolary` / `Social Media` are non-prose layouts
    /// full of timestamps, speaker labels, and fragments. These are sorted by
    /// date rather than kudos on purpose — the goal is *typical*, not *best*.
    ///
    /// Fandom picks target specific conventions: quirk typing (Homestuck),
    /// transcript framing (Magnus Archives), broadcast script (Night Vale),
    /// multilingual dialogue (Hetalia), footnotes (Good Omens), and military
    /// acronyms (Halo) — the one place letter-spelling is *correct* and must
    /// keep working after the `NOOO` fix.
    private static var targets: [Target] {
        [
            // Formatting conventions
            .init(label: "homestuck-quirk", fandom: "Homestuck", wordsFrom: "80000"),
            .init(label: "magnus-transcript", fandom: "The Magnus Archives (Podcast)", wordsFrom: "80000"),
            .init(label: "nightvale-broadcast", fandom: "Welcome to Night Vale", wordsFrom: "40000"),
            .init(label: "hetalia-multilingual", fandom: "Hetalia (Anime & Manga)", wordsFrom: "80000"),
            .init(label: "goodomens-footnotes", fandom: "Good Omens (TV)", wordsFrom: "150000"),
            .init(label: "halo-acronyms", fandom: "Halo (Video Games) & Related Fandoms", wordsFrom: "80000"),
            .init(label: "undertale-typography", fandom: "Undertale (Video Game)", wordsFrom: "80000"),

            // Messy by construction — note the sort is NOT kudos
            .init(label: "messy-not-beta-read", additionalTags: "Not Beta Read",
                  sort: .dateUpdated, wordsFrom: "40000"),
            .init(label: "messy-chat-fic", additionalTags: "Chat Fic",
                  sort: .dateUpdated, wordsFrom: "30000"),
            .init(label: "messy-epistolary", additionalTags: "Epistolary",
                  sort: .dateUpdated, wordsFrom: "30000"),
            .init(label: "messy-social-media", additionalTags: "Social Media",
                  sort: .dateUpdated, wordsFrom: "30000"),
            .init(label: "messy-texting", additionalTags: "Texting",
                  sort: .dateUpdated, wordsFrom: "20000"),
        ]
    }

    @Test func harvestCorpusAcrossFormattingConventions() async throws {
        let dir = Self.destination
        try #require(!dir.isEmpty, "set TEST_RUNNER_KOKORO_HARVEST_DIR to run this")
        try FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )

        let client = AO3Client.shared
        var log: [String] = []

        for target in Self.targets {
            var filters = AO3SearchFilters()
            filters.fandom = target.fandom
            filters.additionalTags = target.additionalTags
            filters.sort = target.sort
            filters.sortDirection = .descending
            filters.completion = .complete
            filters.language = .init(id: "en")
            filters.wordsFrom = target.wordsFrom

            do {
                let page = try await client.search(filters: filters, page: 1)
                guard let work = page.works.first else {
                    log.append("\(target.label): no results")
                    continue
                }
                let epub = try await client.downloadEPUB(workID: work.id)
                let slug = work.title
                    .replacingOccurrences(of: "[^A-Za-z0-9]+", with: "-",
                                          options: .regularExpression)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
                    .lowercased()
                    .prefix(48)
                let dest = URL(fileURLWithPath: dir)
                    .appendingPathComponent("\(target.label)--\(slug)-\(work.id).epub")
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: epub, to: dest)
                let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path)
                let size = (attrs?[.size] as? Int) ?? 0
                log.append("\(target.label): \(work.id) \"\(work.title)\" -> \(dest.lastPathComponent) (\(size) bytes)")
            } catch {
                // One fandom failing must not lose the others already fetched.
                log.append("\(target.label): FAILED \(error)")
            }
        }

        let summary = log.joined(separator: "\n")
        try summary.write(
            toFile: URL(fileURLWithPath: dir)
                .appendingPathComponent("HARVEST.txt").path,
            atomically: true,
            encoding: .utf8
        )
        #expect(!log.isEmpty)
    }
}
#endif
