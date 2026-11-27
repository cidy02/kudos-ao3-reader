import Foundation

/// Top-level sections in the Writing Studio segmented bar (`Studio-Overview`, `Studio-Offline`).
nonisolated enum StudioSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case overview
    case documents
    case comments
    case stats

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .documents: "Documents"
        case .comments: "Comments"
        case .stats: "Stats"
        }
    }

    /// True for sections that require a signed-in AO3 account (`Studio-Offline`).
    var requiresAccount: Bool {
        switch self {
        case .overview, .documents: false
        case .comments, .stats: true
        }
    }

    var signedOutSymbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .documents: "doc.text"
        case .comments: "bubble.left.and.bubble.right"
        case .stats: "chart.bar"
        }
    }

    var signedOutHeadline: String {
        switch self {
        case .overview: "Writing Studio"
        case .documents: "Documents"
        case .comments: "Comments need an AO3 account"
        case .stats: "Stats need an AO3 account"
        }
    }

    var signedOutDescription: String {
        switch self {
        case .overview, .documents:
            "Your documents, editor, word counts and goals work on this device without an account."
        case .comments:
            "Sign in to AO3 to read reader comments, answer from your inbox, and review moderated threads."
        case .stats:
            "Sign in to AO3 to see kudos, hits, bookmarks, subscriptions and totals across your posted works."
        }
    }
}

/// Persists the last selected Writing Studio section in `UserDefaults`.
nonisolated enum StudioSectionStore {
    static let storageKey = "writingStudioSelectedSection"

    static func load(in defaults: UserDefaults = .standard) -> StudioSection {
        guard let raw = defaults.string(forKey: storageKey),
              let section = StudioSection(rawValue: raw)
        else { return .overview }
        return section
    }

    static func save(_ section: StudioSection, in defaults: UserDefaults = .standard) {
        defaults.set(section.rawValue, forKey: storageKey)
    }
}

/// Lightweight plain-text excerpt extraction from local chapter HTML bodies for the Continue card.
nonisolated enum StudioHTMLText {
    static func excerpt(from html: String, maxCharacters: Int = 360) -> String {
        guard !html.isEmpty else { return "" }
        // Bound scanning on very large chapters so Overview stays responsive.
        let prefixLimit = max(maxCharacters * 8, 2_048)
        let slice = html.count > prefixLimit ? String(html.prefix(prefixLimit)) : html

        var result = String()
        result.reserveCapacity(min(slice.count, maxCharacters + 32))

        var insideTag = false
        var tagBuffer = String()
        var lastWasSpace = true

        func appendSpaceIfNeeded() {
            if !lastWasSpace {
                result.append(" ")
                lastWasSpace = true
            }
        }

        for char in slice {
            if char == "<" {
                insideTag = true
                tagBuffer.removeAll(keepingCapacity: true)
                continue
            }
            if insideTag {
                if char == ">" {
                    insideTag = false
                    let tag = tagBuffer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if tag.hasPrefix("br") || tag.hasPrefix("/p") || tag.hasPrefix("/div")
                        || tag.hasPrefix("/li") || tag.hasPrefix("/blockquote") || tag.hasPrefix("/h") {
                        appendSpaceIfNeeded()
                    }
                } else if tagBuffer.count < 24 {
                    tagBuffer.append(char)
                }
                continue
            }
            if char.isWhitespace {
                appendSpaceIfNeeded()
            } else {
                result.append(char)
                lastWasSpace = false
            }
            if result.count >= maxCharacters * 2 { break }
        }

        let decoded = decodeBasicEntities(result)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard decoded.count > maxCharacters else { return decoded }
        let clipped = decoded.prefix(maxCharacters)
        if let lastSpace = clipped.lastIndex(where: \.isWhitespace) {
            return String(clipped[..<lastSpace]) + "…"
        }
        return String(clipped) + "…"
    }

    private static func decodeBasicEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let replacements: [(String, String)] = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&mdash;", "—"),
            ("&ndash;", "–"),
            ("&hellip;", "…"),
            ("&lsquo;", "‘"),
            ("&rsquo;", "’"),
            ("&ldquo;", "“"),
            ("&rdquo;", "”")
        ]
        var output = text
        for (entity, value) in replacements where output.contains(entity) {
            output = output.replacingOccurrences(of: entity, with: value)
        }
        return output
    }
}

/// Summary of one local manuscript loaded from `WritingDocumentStore` for Overview.
nonisolated struct StudioLocalDocumentSummary: Identifiable, Equatable, Sendable {
    let workID: UUID
    let chapterID: UUID
    let workTitle: String
    let chapterTitle: String
    let chapterNumber: Int
    let totalChapters: Int
    let wordCount: Int
    let totalWordCount: Int
    let updatedAt: Date
    let excerpt: String
    let ao3WorkID: Int?

    var id: UUID { workID }

    var displayWorkTitle: String {
        let trimmed = workTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    var target: StudioLocalDocumentTarget {
        StudioLocalDocumentTarget(
            workID: workID,
            chapterID: chapterID,
            title: workTitle
        )
    }
}

/// An item in the Overview "Continue" hero or "Recent" horizontal strip.
enum StudioContinueItem: Equatable, Identifiable, Sendable {
    case local(StudioLocalDocumentSummary)
    case ao3Draft(work: AO3WorkSummary, deletion: DateComponents?)

    var id: String {
        switch self {
        case let .local(doc): "local:\(doc.workID.uuidString):\(doc.chapterID.uuidString)"
        case let .ao3Draft(work, _): "ao3-draft:\(work.id)"
        }
    }

    var sortDate: Date {
        switch self {
        case let .local(doc): doc.updatedAt
        case let .ao3Draft(work, _): WorkStat.date(from: work.dateUpdated) ?? .distantPast
        }
    }
}

/// One paper-card entry in the Overview "Recent" strip (local docs + AO3 drafts).
struct StudioRecentEntry: Identifiable, Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case local(StudioLocalDocumentTarget)
        case ao3Draft(Int)
        case ao3Work(AO3WorkSummary)
    }

    let id: String
    let title: String
    let subtitle: String
    let wordCount: Int?
    let editedAt: Date?
    let editedFallback: String?
    let lineWidths: [Double]
    let action: Action

    static func lineWidths(forWordCount words: Int?) -> [Double] {
        let count = words ?? 0
        switch count {
        case ..<1: return [0.72, 0.45]
        case 1 ..< 500: return [0.96, 1.0, 0.70]
        case 500 ..< 2_000: return [1.0, 0.92, 1.0, 0.84, 0.96, 0.60]
        default: return [1.0, 1.0, 0.88, 1.0, 0.94, 1.0, 0.72]
        }
    }
}

/// Loads local document summaries off the main actor from `WritingDocumentStore`.
enum StudioLocalLibraryLoader {
    static func loadRecent(
        from store: WritingDocumentStore = WritingDocumentStore(root: WritingDocumentStore.defaultRoot),
        limit: Int = 8
    ) async throws -> [StudioLocalDocumentSummary] {
        let works = try await store.listWorks()
        var results: [StudioLocalDocumentSummary] = []
        results.reserveCapacity(min(works.count, limit))

        for work in works.prefix(limit) {
            let chapters = (try? await store.listChapters(workID: work.id)) ?? []
            guard let latest = chapters.max(by: { $0.updatedAt < $1.updatedAt }) else {
                continue
            }
            let chapterNumber = (chapters.firstIndex(where: { $0.id == latest.id }) ?? 0) + 1
            let totalWords = chapters.reduce(0) { $0 + $1.wordCount }
            let excerpt: String
            if results.isEmpty,
               let loaded = try? await store.loadChapter(workID: work.id, chapterID: latest.id) {
                excerpt = StudioHTMLText.excerpt(from: loaded.bodyHTML)
            } else {
                excerpt = ""
            }
            results.append(StudioLocalDocumentSummary(
                workID: work.id,
                chapterID: latest.id,
                workTitle: work.title,
                chapterTitle: latest.title,
                chapterNumber: chapterNumber,
                totalChapters: chapters.count,
                wordCount: latest.wordCount,
                totalWordCount: totalWords,
                updatedAt: max(work.updatedAt, latest.updatedAt),
                excerpt: excerpt,
                ao3WorkID: work.ao3WorkID
            ))
        }
        return results.sorted { $0.updatedAt > $1.updatedAt }
    }
}
