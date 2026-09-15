import Foundation
import SwiftSoup

/// One row's reading metadata on `/users/:id/readings` — artboard **1t**.
///
/// AO3 renders this page with `readings/_reading_blurb`, which wraps the
/// ordinary `works/work_module` in a `li.reading.work` and then adds a
/// `div.user.module` the plain work blurb never has. Everything in this type
/// lives in that extra block, which is why routing history through the generic
/// blurb parser silently discarded all of it.
nonisolated struct AO3ReadingEntry: Equatable, Sendable {
    /// What AO3 knows about the version you read versus the one posted now.
    enum VersionStatus: Equatable, Sendable {
        case updateAvailable
        case minorEdits
        case latestVersion
        /// The row said none of the three — never guess which.
        case unknown
    }

    var workID: Int?
    /// AO3's own wording, kept rather than re-derived: `set_format_for_date`
    /// gives `time_ago_in_words` ("2 days") within 30 days and an rfc822 date
    /// ("04 Mar 2024") beyond it, so there is no single timestamp to parse back
    /// out. Storing the text means the screen can never disagree with the site.
    var lastVisited: String = ""
    var visitCount: Int?
    var versionStatus: VersionStatus = .unknown
    var isMarkedForLater = false
    var isFlaggedToSkip = false
    /// AO3 keeps the reading after the work goes: the row has no `id` and no
    /// work module, only "(Deleted work, last visited …)".
    var isDeletedWork = false

    /// "2 days" needs "ago"; "04 Mar 2024" must not get it. The rfc822 form is
    /// the only one shaped `DD Mon YYYY`, so anything else is a duration.
    var lastVisitedIsRelative: Bool {
        lastVisited.range(of: #"^\d{1,2} \w{3} \d{4}$"#, options: .regularExpression) == nil
    }

    /// 1t's line: "Last visited 2d ago".
    var lastVisitedDisplay: String? {
        guard !lastVisited.isEmpty else { return nil }
        return lastVisitedIsRelative
            ? "Last visited \(lastVisited) ago"
            : "Last visited \(lastVisited)"
    }

    /// 1t draws "Visited once" / "Visited twice" / "Visited 7 times". AO3 itself
    /// only special-cases 1 and writes "Visited 2 times"; the board's "twice" is
    /// the nicety, and the tree is what this screen follows.
    var visitCountDisplay: String? {
        guard let visitCount, visitCount > 0 else { return nil }
        switch visitCount {
        case 1: return "Visited once"
        case 2: return "Visited twice"
        default: return "Visited \(visitCount.formatted()) times"
        }
    }

    var versionDisplay: String? {
        switch versionStatus {
        case .updateAvailable: "Update available"
        case .minorEdits: "Minor edits since then"
        case .latestVersion: "Latest version"
        case .unknown: nil
        }
    }
}

extension AO3Client {
    /// Parse the per-row reading metadata from a readings page.
    ///
    /// Returned in page order. Rows for deleted works carry no `workID` — AO3
    /// omits the `id` attribute when the work is gone — so a caller keying by
    /// work id will not find them; that is the same reason they have no blurb to
    /// attach to either.
    ///
    /// Scoped to `ol.reading.work` and then to each row's own `div.user.module`,
    /// because the work module above it has headings of its own.
    static func parseReadingEntries(from html: String) throws -> [AO3ReadingEntry] {
        let doc = try SwiftSoup.parse(html)
        guard let list = try doc.select("ol.reading.work").first() else { return [] }
        var entries: [AO3ReadingEntry] = []
        for row in try list.select("> li").array() {
            guard let heading = try row.select("div.user.module h4.viewed").first() else { continue }
            let text = try heading.text()
            var entry = AO3ReadingEntry()
            entry.workID = Int((try? row.attr("id"))?
                .replacingOccurrences(of: "work_", with: "") ?? "")
            entry.isDeletedWork = try row.hasClass("deleted") || text.contains("Deleted work")
            entry.lastVisited = Self.lastVisitedText(in: text)
            entry.visitCount = Self.visitCount(in: text)
            entry.versionStatus = Self.versionStatus(in: text)
            entry.isMarkedForLater = text.contains("Marked for Later")
            entry.isFlaggedToSkip = text.contains("Flagged to skip")
            entries.append(entry)
        }
        return entries
    }

    /// Two shapes: "Last visited: 2 days (Latest version.) …" and, for a work
    /// AO3 no longer has, "(Deleted work, last visited 04 Mar 2024)".
    private static func lastVisitedText(in text: String) -> String {
        if let range = text.range(of: "last visited", options: .caseInsensitive) {
            let tail = text[range.upperBound...]
                .trimmingCharacters(in: CharacterSet(charactersIn: ": "))
            // Stops at the parenthesis that opens the version note, or at the
            // closing one on the deleted-work sentence.
            let cut = tail.prefix { $0 != "(" && $0 != ")" }
            return cut.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private static func visitCount(in text: String) -> Int? {
        if text.contains("Visited once") { return 1 }
        guard let match = text.range(
            of: #"Visited ([\d,]+) times"#,
            options: .regularExpression
        ) else { return nil }
        let digits = text[match].filter(\.isNumber)
        return Int(digits)
    }

    private static func versionStatus(in text: String) -> AO3ReadingEntry.VersionStatus {
        if text.contains("Update available") { return .updateAvailable }
        if text.contains("Minor edits") { return .minorEdits }
        if text.contains("Latest version") { return .latestVersion }
        return .unknown
    }
}
