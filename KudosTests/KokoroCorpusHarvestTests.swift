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
/// Optionally override the fandom list with `TEST_RUNNER_KOKORO_FANDOMS`
/// (comma-separated). Downloaded works are third-party fiction: they stay
/// local, are never committed, and are used only to measure what the packer
/// does to real prose.
@Suite("Kokoro corpus harvest", .serialized)
struct KokoroCorpusHarvestTests {
    private static var destination: String {
        let env = ProcessInfo.processInfo.environment
        return env["TEST_RUNNER_KOKORO_HARVEST_DIR"] ?? env["KOKORO_HARVEST_DIR"] ?? ""
    }

    /// Deliberately spread across categories and prose conventions — anime and
    /// manga (romaji, honorifics), Western TV, book fandom, and military SF
    /// (acronyms, which are the one place letter-spelling is *correct*).
    private static var fandoms: [String] {
        let env = ProcessInfo.processInfo.environment
        if let raw = env["TEST_RUNNER_KOKORO_FANDOMS"] ?? env["KOKORO_FANDOMS"],
           !raw.isEmpty
        {
            return raw.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
        }
        return [
            "Naruto",
            "Bleach",
            "Supergirl (TV 2015)",
            "Supernatural",
            "Harry Potter - J. K. Rowling",
            "Criminal Minds (US TV)",
            "Halo (Video Games)",
        ]
    }

    @Test func harvestOneLongWellLikedWorkPerFandom() async throws {
        let dir = Self.destination
        try #require(!dir.isEmpty, "set TEST_RUNNER_KOKORO_HARVEST_DIR to run this")
        try FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )

        let client = AO3Client.shared
        var log: [String] = []

        for fandom in Self.fandoms {
            var filters = AO3SearchFilters()
            filters.fandom = fandom
            filters.sort = .kudos
            filters.sortDirection = .descending
            filters.completion = .complete
            filters.language = .init(id: "en")
            // Long enough to exercise chapter-scale packing, not so long that a
            // single work dominates the corpus.
            filters.wordsFrom = "150000"

            do {
                let page = try await client.search(filters: filters, page: 1)
                guard let work = page.works.first else {
                    log.append("\(fandom): no results")
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
                    .appendingPathComponent("\(slug)-\(work.id).epub")
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: epub, to: dest)
                let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path)
                let size = (attrs?[.size] as? Int) ?? 0
                log.append("\(fandom): \(work.id) \"\(work.title)\" -> \(dest.lastPathComponent) (\(size) bytes)")
            } catch {
                // One fandom failing must not lose the others already fetched.
                log.append("\(fandom): FAILED \(error)")
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
