import Foundation
import OSLog
import SwiftSoup

extension AO3Client {
    /// UserDefaults key for the process-wide 429 hold on followed-tag feeds.
    nonisolated static let followedTagHoldKey = "followedTags.retryAfterUntil"
    /// Default 429 cooldown when AO3 sends 429 without a `Retry-After` header.
    nonisolated static let defaultFollowedTagRateLimitHold: TimeInterval = 6 * 60 * 60

    nonisolated static func tagFeedURL(tagID: Int) -> URL? {
        guard tagID > 0 else { return nil }
        return URL(string: "https://archiveofourown.org/tags/\(tagID)/feed.atom")
    }

    private nonisolated static func followedTagHoldRemaining(
        now: Date,
        defaults: UserDefaults
    ) -> TimeInterval? {
        guard let until = defaults.object(forKey: followedTagHoldKey) as? Date,
              until > now
        else { return nil }
        return until.timeIntervalSince(now)
    }

    nonisolated static func isFollowedTagHeld(
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> Bool {
        followedTagHoldRemaining(now: now, defaults: defaults) != nil
    }

    nonisolated static func throwIfFollowedTagHeld(
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) throws {
        if let remaining = followedTagHoldRemaining(now: now, defaults: defaults) {
            throw AO3Error.rateLimited(retryAfter: remaining)
        }
    }

    nonisolated static func recordFollowedTagRateLimit(
        retryAfter: TimeInterval?,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) {
        let delay = retryAfter.flatMap { $0.isFinite ? max($0, 0) : nil }
            ?? defaultFollowedTagRateLimitHold
        let until = now.addingTimeInterval(delay)
        let current = defaults.object(forKey: followedTagHoldKey) as? Date ?? .distantPast
        defaults.set(max(until, current), forKey: followedTagHoldKey)
    }

    nonisolated static func clearFollowedTagRateLimit(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: followedTagHoldKey)
    }

    /// Fetches one followed tag's public `/tags/<id>/feed.atom` Atom feed.
    ///
    /// Rules enforced here (and in `FollowedTagChecks`):
    /// - Anonymous request (`httpShouldHandleCookies = false`, never attaches session cookies).
    /// - Own `User-Agent` tag (`feature=followed-tag-feeds`).
    /// - Strictly serialized through `followedTagCoordinator` and `AO3RequestCoordinator.shared`,
    ///   plus both the normal pacer and the 3-second followed-tag floor.
    /// - No automatic retries: any 429 / 403 / 5xx / maintenance / parse failure throws out.
    func followedTagFeed(
        tagID: Int,
        defaults: UserDefaults = .standard,
        now: @Sendable () -> Date = Date.init
    ) async throws -> AO3TagFeed {
        guard let url = Self.tagFeedURL(tagID: tagID) else {
            throw AO3Error.network("Invalid AO3 tag feed ID.")
        }
        try Self.rejectIfUntrusted(url)
        try Self.throwIfFollowedTagHeld(now: now(), defaults: defaults)
        do {
            return try await Self.followedTagCoordinator.withSlot { [self] in
                try await AO3RequestCoordinator.shared.withSlot {
                    try Self.throwIfFollowedTagHeld(now: now(), defaults: defaults)
                    try await pace()
                    try await paceFollowedTag()
                    try Task.checkCancellation()
                    try Self.throwIfFollowedTagHeld(now: now(), defaults: defaults)
                    do {
                        var request = URLRequest(url: url)
                        request.httpShouldHandleCookies = false
                        request.setValue(
                            AO3RequestDefaults.userAgent(feature: .followedTagFeeds),
                            forHTTPHeaderField: "User-Agent"
                        )
                        request.setValue(
                            "application/atom+xml, application/xml;q=0.9",
                            forHTTPHeaderField: "Accept"
                        )
                        let (body, response) = try await session.data(for: request)
                        defer {
                            Self.purgeSessionCookie(
                                from: session.configuration.httpCookieStorage,
                                url: url
                            )
                        }
                        try checkStatus(response) { body }
                        return try Self.parseTagFeed(body)
                    } catch let error as AO3Error {
                        if case let .rateLimited(retryAfter) = error {
                            Self.recordFollowedTagRateLimit(
                                retryAfter: retryAfter,
                                now: now(),
                                defaults: defaults
                            )
                        }
                        throw error
                    }
                }
            }
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        }
    }

    /// Parses AO3's `/tags/:id/feed.atom` Atom XML into an `AO3TagFeed`.
    /// Rejects empty payloads, malformed XML, and non-Atom HTML redirects (which AO3
    /// sends for tags without feeds) with `AO3Error.parse`. Empty valid Atom `<feed>`
    /// documents return zero entries.
    nonisolated static func parseTagFeed(_ data: Data) throws -> AO3TagFeed {
        guard !data.isEmpty else { throw AO3Error.parse }
        let delegate = AO3AtomFeedParserDelegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(),
              !delegate.rejectedNonAtomRoot,
              delegate.sawFeedRoot,
              !delegate.hadMalformedEntry
        else {
            if let error = parser.parserError {
                Log.network.error("Tag feed XML parse error: \(error.localizedDescription, privacy: .public)")
            }
            throw AO3Error.parse
        }
        return AO3TagFeed(
            feedID: delegate.feedID,
            title: delegate.feedTitle,
            updatedAt: delegate.feedUpdatedAt,
            entries: delegate.entries
        )
    }

    nonisolated static func parseAtomTimestamp(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: trimmed) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: trimmed)
    }
}

private final class AO3AtomFeedParserDelegate: NSObject, XMLParserDelegate {
    private static let atomNamespace = "http://www.w3.org/2005/Atom"

    private struct MutableAuthor {
        var name = ""
        var uri = ""
    }

    private struct MutableEntry {
        var id = ""
        var title = ""
        var publishedRaw = ""
        var updatedRaw = ""
        var alternateLink = ""
        var summaryHTML = ""
        var authors: [MutableAuthor] = []
    }

    var sawFeedRoot = false
    var rejectedNonAtomRoot = false
    var hadMalformedEntry = false

    var feedID = ""
    var feedTitle = ""
    var feedUpdatedAt: Date?
    var entries: [AO3TagFeedEntry] = []

    private var elementStack: [String] = []
    private var currentText = ""
    private var currentEntry: MutableEntry?
    private var currentAuthor: MutableAuthor?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementStack.isEmpty {
            let ns = (namespaceURI ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard elementName == "feed", ns == Self.atomNamespace else {
                rejectedNonAtomRoot = true
                parser.abortParsing()
                return
            }
            sawFeedRoot = true
        }
        elementStack.append(elementName)
        currentText = ""

        if elementStack == ["feed", "entry"] {
            currentEntry = MutableEntry()
        } else if elementStack == ["feed", "entry", "author"] {
            currentAuthor = MutableAuthor()
        } else if elementStack == ["feed", "entry", "link"], currentEntry != nil {
            let rel = attributeDict["rel"] ?? "alternate"
            if rel == "alternate", let href = attributeDict["href"], !href.isEmpty {
                currentEntry?.alternateLink = href
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText.append(string)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let text = String(data: CDATABlock, encoding: .utf8) {
            currentText.append(text)
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Check entry subtrees (including ["feed", "entry"] itself) before top-level
        // <feed> children so closing </entry> builds/validates the entry instead of
        // falling into `handleFeedEndElement("entry", ...)`.
        if elementStack.starts(with: ["feed", "entry"]) {
            handleEntryEndElement(text: text)
        } else if elementStack.count == 2, elementStack[0] == "feed" {
            handleFeedEndElement(elementStack[1], text: text)
        }
        currentText = ""
        if !elementStack.isEmpty {
            elementStack.removeLast()
        }
    }

    private func handleFeedEndElement(_ tag: String, text: String) {
        switch tag {
        case "id": feedID = text
        case "title": feedTitle = text
        case "updated": feedUpdatedAt = AO3Client.parseAtomTimestamp(text)
        default: break
        }
    }

    private func handleEntryEndElement(text: String) {
        switch elementStack.dropFirst(2) {
        case ["id"]:
            currentEntry?.id = text
        case ["title"]:
            currentEntry?.title = text
        case ["published"]:
            currentEntry?.publishedRaw = text
        case ["updated"]:
            currentEntry?.updatedRaw = text
        case ["summary"]:
            currentEntry?.summaryHTML = currentText
        case ["author", "name"]:
            currentAuthor?.name = text
        case ["author", "uri"]:
            currentAuthor?.uri = text
        case ["author"]:
            if let author = currentAuthor {
                currentEntry?.authors.append(author)
            }
            currentAuthor = nil
        case []:
            if let entry = currentEntry {
                if let built = buildEntry(from: entry) {
                    entries.append(built)
                } else {
                    hadMalformedEntry = true
                }
            }
            currentEntry = nil
        default:
            break
        }
    }

    private func buildEntry(from raw: MutableEntry) -> AO3TagFeedEntry? {
        guard !raw.id.isEmpty,
              let publishedAt = AO3Client.parseAtomTimestamp(raw.publishedRaw),
              let workID = extractWorkID(link: raw.alternateLink, atomID: raw.id)
        else { return nil }

        let parsedSummary = parseSummaryHTML(raw.summaryHTML)
        let title = raw.title.isEmpty ? "Work #\(workID)" : raw.title

        var authors: [String] = []
        var identities: [AO3AuthorIdentity] = []
        for author in raw.authors {
            let name = author.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            authors.append(name)
            if !author.uri.isEmpty, let identity = AO3AuthorIdentity(displayName: name, href: author.uri) {
                identities.append(identity)
            } else if name.caseInsensitiveCompare("Anonymous") == .orderedSame {
                identities.append(.nonNavigable(name, kind: .anonymous))
            }
        }
        if authors.isEmpty, !parsedSummary.bylineAuthors.isEmpty {
            authors = parsedSummary.bylineAuthors
        }

        let workURL = URL(string: raw.alternateLink)
            ?? URL(string: "https://archiveofourown.org/works/\(workID)")

        return AO3TagFeedEntry(
            id: raw.id,
            workID: workID,
            title: title,
            authors: authors,
            authorIdentities: identities,
            publishedAt: publishedAt,
            updatedAt: AO3Client.parseAtomTimestamp(raw.updatedRaw),
            url: workURL,
            summary: parsedSummary.summary,
            words: parsedSummary.words,
            chapters: parsedSummary.chapters,
            isComplete: AO3TagFeedEntry.isCompleteChapters(parsedSummary.chapters),
            language: parsedSummary.language,
            rating: parsedSummary.rating,
            warnings: parsedSummary.warnings,
            categories: parsedSummary.categories,
            fandoms: parsedSummary.fandoms,
            characters: parsedSummary.characters,
            relationships: parsedSummary.relationships,
            freeforms: parsedSummary.freeforms
        )
    }

    private func extractWorkID(link: String, atomID: String) -> Int? {
        if let range = link.range(of: #"/works/([0-9]+)"#, options: .regularExpression),
           let id = Int(link[range].replacingOccurrences(of: "/works/", with: "")), id > 0 {
            return id
        }
        if let range = atomID.range(of: #"Work/([0-9]+)$"#, options: .regularExpression),
           let id = Int(atomID[range].replacingOccurrences(of: "Work/", with: "")), id > 0 {
            return id
        }
        return nil
    }

    private struct SummaryMetadata {
        var bylineAuthors: [String] = []
        var summary = ""
        var words = 0
        var chapters = ""
        var language = ""
        var rating: String?
        var warnings: [String] = []
        var categories: [String] = []
        var fandoms: [String] = []
        var characters: [String] = []
        var relationships: [String] = []
        var freeforms: [String] = []
    }

    private func parseSummaryHTML(_ html: String) -> SummaryMetadata {
        var result = SummaryMetadata()
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let doc = try? SwiftSoup.parseBodyFragment(html),
              let body = doc.body()
        else { return result }

        // Parse <ul><li>Label: a, b, c</li></ul> from `works_helper.rb:191-197`.
        if let list = try? body.select("ul").last() {
            applyTagListItems(in: list, into: &result)
            try? list.remove()
        }

        // Scan <p> blocks built by `works_helper.rb:185-190`.
        let paragraphs = (try? body.select("p").array()) ?? []
        var summaryParagraphs: [String] = []
        for (index, paragraph) in paragraphs.enumerated() {
            let text = ((try? paragraph.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if index == 0, text.hasPrefix("by ") {
                result.bylineAuthors = parseCSVList(String(text.dropFirst(3)))
                continue
            }
            if parseStatsLine(text, into: &result) || text.hasPrefix("Series: Part ") {
                continue
            }
            if !text.isEmpty {
                summaryParagraphs.append(text)
            }
        }
        result.summary = summaryParagraphs.joined(separator: "\n")
        return result
    }

    private func applyTagListItems(in list: Element, into result: inout SummaryMetadata) {
        let items = (try? list.select("li").array()) ?? []
        for item in items {
            guard let text = try? item.text(),
                  let colon = text.firstIndex(of: ":") else { continue }
            let label = text[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
            let rawValue = text[text.index(after: colon)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let listValues = parseCSVList(rawValue)
            switch label {
            case "Fandoms": result.fandoms = listValues
            case "Rating": result.rating = rawValue.isEmpty ? nil : rawValue
            case "Warnings": result.warnings = listValues
            case "Categories": result.categories = listValues
            case "Characters": result.characters = listValues
            case "Relationships": result.relationships = listValues
            case "Additional Tags": result.freeforms = listValues
            default: break
            }
        }
    }

    private func parseCSVList(_ rawValue: String) -> [String] {
        rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func parseStatsLine(_ text: String, into metadata: inout SummaryMetadata) -> Bool {
        // Matches AO3 `Words: 2345, Chapters: 1/1, Language: English`
        let pattern = #"^Words:\s*([0-9,]+),\s*Chapters:\s*([^,]+),\s*Language:\s*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges == 4
        else { return false }

        if let wordsRange = Range(match.range(at: 1), in: text) {
            let digits = text[wordsRange].replacingOccurrences(of: ",", with: "")
            metadata.words = Int(digits) ?? 0
        }
        if let chaptersRange = Range(match.range(at: 2), in: text) {
            metadata.chapters = text[chaptersRange].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let languageRange = Range(match.range(at: 3), in: text) {
            metadata.language = text[languageRange].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return true
    }
}
