import Foundation
import SwiftSoup

// A small native AO3 client: it fetches AO3's normal HTML pages over the network
// and reads the data out of them with SwiftSoup. The page structure (which CSS
// classes hold the title, stats, etc.) and the search parameters are ported from
// the open-source ao3_api project (github.com/ArmindoFlores/ao3_api) and verified
// against live AO3 HTML. AO3 has no official API, so this is HTML scraping — kept
// polite and personal.

/// Serialized network access to AO3 (one request at a time keeps us polite).
actor AO3Client {
    static let shared = AO3Client()

    private let base = "https://archiveofourown.org"
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        // A browser-like User-Agent; AO3 throttles unfamiliar clients harder.
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        ]
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    // MARK: Requests

    private func getHTML(_ url: URL) async throws -> String {
        let data = try await fetchData(from: url)
        return String(decoding: data, as: UTF8.self)
    }

    /// Fetches a URL's body, validating the HTTP status and retrying transient
    /// failures with backoff (see `withRetry`).
    private func fetchData(from url: URL) async throws -> Data {
        try await withRetry {
            let (data, response) = try await session.data(from: url)
            try Self.check(response)
            return data
        }
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AO3Error.network("No response from AO3.")
        }
        switch http.statusCode {
        case 200...299: return
        case 429: throw AO3Error.rateLimited(retryAfter: retryAfter(from: http))
        case 404: throw AO3Error.notFound
        case 500...599: throw AO3Error.server(status: http.statusCode)
        default: throw AO3Error.http(status: http.statusCode)
        }
    }

    /// Parses a `Retry-After` header (seconds, or an HTTP-date) into a delay.
    private static func retryAfter(from http: HTTPURLResponse) -> TimeInterval? {
        guard let value = http.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if let seconds = TimeInterval(value) { return seconds }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: value) { return max(0, date.timeIntervalSinceNow) }
        return nil
    }

    // MARK: Retry

    /// Runs `operation`, retrying up to `maxRetries` times on *transient* failures
    /// with exponential backoff (~0.5s, then 1s). Network drop-outs/timeouts,
    /// HTTP 5xx, and 429 (honouring Retry-After) are retried; 404 / other 4xx and
    /// parse errors are not. Cancellation propagates immediately.
    private func withRetry<T>(maxRetries: Int = 2, _ operation: () async throws -> T) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await operation()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                attempt += 1
                guard attempt <= maxRetries,
                      let delay = Self.retryDelay(for: error, attempt: attempt)
                else { throw error }
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    /// Backoff (seconds) before retrying a transient error, or nil if it should
    /// not be retried. Base 0.5s, doubled per attempt; 429 respects Retry-After.
    private static func retryDelay(for error: Error, attempt: Int) -> TimeInterval? {
        let backoff = 0.5 * pow(2, Double(attempt - 1))   // 0.5, 1.0, 2.0…
        switch error {
        case AO3Error.rateLimited(let retryAfter):
            return max(retryAfter ?? 0, backoff)
        case AO3Error.server:
            return backoff
        case let urlError as URLError where transientURLErrorCodes.contains(urlError.code):
            return backoff
        default:
            return nil
        }
    }

    /// URLSession transport failures worth retrying (transient connectivity).
    private static let transientURLErrorCodes: Set<URLError.Code> = [
        .timedOut, .cannotConnectToHost, .cannotFindHost, .networkConnectionLost,
        .notConnectedToInternet, .dnsLookupFailed, .secureConnectionFailed, .badServerResponse
    ]

    /// Runs a works search for the given filters. `page` is 1-based.
    func search(filters: AO3SearchFilters, page: Int = 1) async throws -> AO3SearchPage {
        var components = URLComponents(string: "\(base)/works/search")!
        var items: [URLQueryItem] = []

        func add(_ name: String, _ value: String?) {
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            items.append(URLQueryItem(name: name, value: value))
        }

        // AO3's structured search has no "exclude tag" field, so fold excluded
        // tags into the query with AO3's `-"tag"` exclusion syntax.
        var query = filters.query.trimmingCharacters(in: .whitespacesAndNewlines)
        for tag in commaList(filters.excludeTags) {
            query += (query.isEmpty ? "" : " ") + "-\"\(tag)\""
        }
        add("work_search[query]", query)

        add("work_search[fandom_names]", filters.fandom)
        add("work_search[character_names]", filters.characters)
        add("work_search[relationship_names]", filters.relationships)
        add("work_search[freeform_names]", filters.additionalTags)

        add("work_search[rating_ids]", filters.rating.ao3ID)
        for warning in filters.warnings {
            items.append(URLQueryItem(name: "work_search[archive_warning_ids][]", value: warning.ao3ID))
        }
        for category in filters.categories {
            items.append(URLQueryItem(name: "work_search[category_ids][]", value: category.ao3ID))
        }
        add("work_search[crossover]", filters.crossover.value)
        add("work_search[complete]", filters.completion.value)
        add("work_search[word_count]", wordCountExpression(filters))
        add("work_search[revised_at]", filters.updated.value)
        add("work_search[language_id]", filters.language.code)
        add("work_search[sort_column]", filters.sort.column)

        items.append(URLQueryItem(name: "page", value: String(page)))
        components.queryItems = items

        guard let url = components.url else { throw AO3Error.network("Bad search URL.") }
        let html = try await getHTML(url)
        return try Self.parseSearchPage(html, page: page)
    }

    /// Builds AO3's `word_count` expression from the from/to fields.
    private func wordCountExpression(_ filters: AO3SearchFilters) -> String? {
        let from = filters.wordsFrom.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = filters.wordsTo.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (from.isEmpty, to.isEmpty) {
        case (false, false): return "\(from)-\(to)"
        case (false, true): return "> \(from)"
        case (true, false): return "< \(to)"
        case (true, true): return nil
        }
    }

    /// Splits a comma-separated field into trimmed, non-empty entries.
    private func commaList(_ field: String) -> [String] {
        field.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Downloads a work's EPUB to a temp file. AO3 accepts any filename slug, so
    /// we don't need to scrape the exact link — the work id is enough.
    func downloadEPUB(workID: Int) async throws -> URL {
        guard let url = URL(string: "\(base)/downloads/\(workID)/work.epub") else {
            throw AO3Error.network("Bad download URL.")
        }
        let tempURL = try await withRetry { () -> URL in
            let (tempURL, response) = try await session.download(from: url)
            try Self.check(response)
            return tempURL
        }
        let destination = Storage.tempDownloadURL(suggestedName: "\(workID).epub")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }

    /// Fetches a work's canonical tags from its AO3 page (fandoms, relationships,
    /// characters, freeform, warnings, categories — the rating is stored separately).
    /// `view_adult=true` clears the adult interstitial; works locked to registered
    /// users return no tags, which the caller treats as "leave the EPUB tags".
    func workTags(workID: Int) async throws -> AO3WorkTagGroups {
        guard let url = URL(string: "\(base)/works/\(workID)?view_adult=true") else {
            throw AO3Error.network("Bad work URL.")
        }
        let html = try await getHTML(url)
        return try Self.parseWorkTags(from: html)
    }

    /// Parses a work page's canonical tag groups + stats from its HTML. Split out
    /// from `workTags(workID:)` so it can be unit-tested against fixture HTML
    /// without a network round-trip.
    static func parseWorkTags(from html: String) throws -> AO3WorkTagGroups {
        let doc = try SwiftSoup.parse(html)

        func tags(_ kind: String) throws -> [String] {
            var seen = Set<String>()
            var result: [String] = []
            for element in try doc.select("dd.\(kind).tags a.tag").array() {
                let tag = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
                if !tag.isEmpty, seen.insert(tag).inserted { result.append(tag) }
            }
            return result
        }

        // Language is plain text in `dd.language`; word count is `dd.words` (e.g.
        // "12,345") in the stats block — strip the grouping separators before parsing.
        let language = (try? doc.select("dd.language").first()?.text())?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let wordsText = (try? doc.select("dd.words").first()?.text()) ?? ""
        let words = Int(wordsText.filter(\.isNumber))
        // Chapters read as printed ("5/10"); kudos is a count in `dd.kudos`.
        let chapters = (try? doc.select("dd.chapters").first()?.text())?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let kudosText = (try? doc.select("dd.kudos").first()?.text()) ?? ""
        let kudos = Int(kudosText.filter(\.isNumber))

        return AO3WorkTagGroups(
            fandoms: try tags("fandom"),
            relationships: try tags("relationship"),
            characters: try tags("character"),
            freeforms: try tags("freeform"),
            warnings: try tags("warning"),
            categories: try tags("category"),
            language: language,
            words: words,
            chapters: chapters,
            kudos: kudos
        )
    }

    /// Live tag search via AO3's autocomplete endpoints (returns canonical tag
    /// names for the given kind). Used by the filter tag pickers.
    func autocompleteTags(kind: AO3TagKind, term: String) async throws -> [String] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var components = URLComponents(string: "\(base)/autocomplete/\(kind.rawValue)")!
        components.queryItems = [URLQueryItem(name: "term", value: trimmed)]
        guard let url = components.url else { return [] }
        let data = try await fetchData(from: url)
        return (try JSONDecoder().decode([AutocompleteItem].self, from: data)).map(\.name)
    }

    private struct AutocompleteItem: Decodable { let id: String; let name: String }

    /// The most-used tags of a kind for a fandom, read from that fandom's works-page
    /// filter sidebar (AO3 lists the top ~10 with work counts). Used to seed the tag
    /// pickers with fandom-relevant suggestions before the user searches. Returns an
    /// empty list (rather than throwing) when the fandom page can't be loaded.
    func popularTags(forFandom fandom: String, kind: AO3TagKind) async throws -> [String] {
        let field: String
        switch kind {
        case .character: field = "character_ids"
        case .relationship: field = "relationship_ids"
        case .freeform, .tag: field = "freeform_ids"
        case .fandom: return []   // no parent-fandom context for the fandom field
        }
        guard let url = fandomWorksURL(fandom) else { return [] }
        let html = try await getHTML(url)
        let doc = try SwiftSoup.parse(html)

        let target = "include_work_search[\(field)][]"
        var seen = Set<String>()
        var result: [String] = []
        for input in try doc.select("input[type=checkbox]").array() {
            guard (try? input.attr("name")) == target, let label = input.parent() else { continue }
            // The label reads "Tag Name (12345)" — strip only a trailing numeric count
            // (tag names can themselves contain parentheses, e.g. "Naruto (Anime...)").
            let name = Self.strippingTrailingCount(try label.text().trimmingCharacters(in: .whitespacesAndNewlines))
            if !name.isEmpty, seen.insert(name).inserted { result.append(name) }
        }
        return result
    }

    /// Builds a fandom's `/tags/<escaped>/works` URL, applying AO3's tag escaping
    /// (`&`→`*a*`, `/`→`*s*`, `.`→`*d*`, `?`→`*q*`, `#`→`*h*`) before percent-encoding.
    private func fandomWorksURL(_ fandom: String) -> URL? {
        var escaped = fandom
        for (from, to) in [("/", "*s*"), ("&", "*a*"), (".", "*d*"), ("?", "*q*"), ("#", "*h*")] {
            escaped = escaped.replacingOccurrences(of: from, with: to)
        }
        guard let encoded = escaped.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "\(base)/tags/\(encoded)/works")
    }

    private static func strippingTrailingCount(_ text: String) -> String {
        guard let range = text.range(of: #"\s*\(\d[\d,]*\)\s*$"#, options: .regularExpression) else { return text }
        return String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Fetches AO3's `/media` page: each media category with its featured fandoms.
    /// The fandom link text is the canonical tag name, ready for a fandom search.
    func mediaCategories() async throws -> [AO3MediaCategory] {
        guard let url = URL(string: "\(base)/media") else {
            throw AO3Error.network("Bad media URL.")
        }
        let html = try await getHTML(url)
        let doc = try SwiftSoup.parse(html)
        var categories: [AO3MediaCategory] = []
        for li in try doc.select("ul.media.fandom.index.group li.medium.listbox.group").array() {
            let heading = try li.select("h3.heading a").first()
            let name = try heading?.text().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // The heading link points at the category's full fandom index page.
            let fandomsURL = (try heading?.attr("href")) ?? ""
            // The category-name link in the heading isn't an `a.tag`, so this picks
            // up only the featured fandom links.
            let fandoms = try li.select("a.tag").array().compactMap { element -> AO3Fandom? in
                let fandom = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
                return fandom.isEmpty ? nil : AO3Fandom(name: fandom)
            }
            if !name.isEmpty, !fandoms.isEmpty {
                categories.append(AO3MediaCategory(name: name, fandoms: fandoms, fandomsURL: fandomsURL))
            }
        }
        guard !categories.isEmpty else { throw AO3Error.parse }
        return categories
    }

    /// Fetches the full fandom index for a media category (every fandom plus its
    /// work count), from the category's `/media/<name>/fandoms` page. `path` is the
    /// relative href captured in `mediaCategories()`.
    func fandoms(atPath path: String) async throws -> [AO3Fandom] {
        let absolute = path.hasPrefix("http") ? path : base + path
        guard let url = URL(string: absolute) else { throw AO3Error.network("Bad fandoms URL.") }
        let html = try await getHTML(url)
        let doc = try SwiftSoup.parse(html)
        var result: [AO3Fandom] = []
        var seen = Set<String>()
        for li in try doc.select("ol.fandom.index li").array() {
            guard let link = try li.select("a.tag").first() else { continue }
            let name = try link.text().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name).inserted else { continue }
            // The li's own text after the link is the work count, e.g. "(1,234)".
            let count = Int((try li.ownText()).filter(\.isNumber))
            result.append(AO3Fandom(name: name, workCount: count))
        }
        guard !result.isEmpty else { throw AO3Error.parse }
        return result
    }

    // MARK: Parsing (ported selectors)

    /// Parses a works-search results page (works list + pagination). `static` and
    /// internal so it can be unit-tested against fixture HTML without a network call.
    static func parseSearchPage(_ html: String, page: Int) throws -> AO3SearchPage {
        let doc = try SwiftSoup.parse(html)
        let blurbs = try doc.select("li.work.blurb").array()
        // Skip any single malformed blurb rather than failing the whole search.
        let works = blurbs.compactMap { try? Self.parseBlurb($0) }
        // AO3's pagination lists every page number (… 27); the largest is the
        // total. Falls back to the current page when there's no pagination.
        var totalPages = page
        for li in try doc.select("ol.pagination li").array() {
            if let n = Int((try li.text()).trimmingCharacters(in: .whitespaces)), n > totalPages {
                totalPages = n
            }
        }
        return AO3SearchPage(works: works, currentPage: page, totalPages: totalPages)
    }

    private static func parseBlurb(_ el: Element) throws -> AO3WorkSummary {
        let idDigits = el.id().replacingOccurrences(of: "work_", with: "")
        guard let id = Int(idDigits) else { throw AO3Error.parse }

        let title = try el.select("h4.heading a").first()?.text() ?? "Untitled"
        let authors = try el.select("h4.heading a[rel=author]").array().map { try $0.text() }
        let fandoms = try el.select("h5.fandoms a.tag").array().map { try $0.text() }

        let rating = try el.select("ul.required-tags .rating .text").first()?.text() ?? ""
        let warnings = try el.select("ul.required-tags .warnings .text").array().map { try $0.text() }
        let categories = try el.select("ul.required-tags .category .text").array().map { try $0.text() }
        let wipText = try el.select("ul.required-tags .iswip .text").first()?.text() ?? ""
        let isComplete: Bool? = wipText.isEmpty ? nil : wipText.lowercased().contains("complete")

        let date = try el.select("p.datetime").first()?.text() ?? ""
        let tags = try el.select("ul.tags li a.tag").array().map { try $0.text() }
        let summary = try el.select("blockquote.userstuff.summary").first()?.text() ?? ""

        func stat(_ cls: String) -> String {
            (try? el.select("dl.stats dd.\(cls)").first()?.text() ?? "") ?? ""
        }
        func statInt(_ cls: String) -> Int? { Int(stat(cls).replacingOccurrences(of: ",", with: "")) }

        // Series block: "Part <strong>N</strong> of <a href="/series/ID">Title</a>".
        let seriesLink = try el.select("ul.series li a").first()
        let seriesTitle = try seriesLink?.text()
        let seriesURL = (try seriesLink?.attr("href")).map { "https://archiveofourown.org\($0)" }
        let seriesPosition = Int((try? el.select("ul.series li strong").first()?.text() ?? "") ?? "")

        return AO3WorkSummary(
            id: id,
            title: title,
            authors: authors,
            fandoms: fandoms,
            rating: rating,
            warnings: warnings,
            categories: categories,
            isComplete: isComplete,
            dateUpdated: date,
            tags: tags,
            summary: summary,
            language: stat("language"),
            words: statInt("words"),
            chapters: stat("chapters"),
            comments: statInt("comments"),
            kudos: statInt("kudos"),
            hits: statInt("hits"),
            seriesTitle: seriesTitle?.isEmpty == false ? seriesTitle : nil,
            seriesURL: seriesURL,
            seriesPosition: seriesPosition
        )
    }
}
