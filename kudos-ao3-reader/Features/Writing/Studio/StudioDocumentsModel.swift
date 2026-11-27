import Foundation

/// View mode switch at the top of the Documents tab (`Studio-Documents` vs `Studio-Files`).
nonisolated enum StudioDocumentsMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case pages
    case files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pages: "Pages"
        case .files: "Files"
        }
    }
}

/// Filter chips on the Pages view (`Studio-Documents`).
nonisolated enum StudioDocumentsFilterChip: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all
    case drafts
    case posted
    case gifts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .drafts: "Drafts"
        case .posted: "Posted"
        case .gifts: "Gifts"
        }
    }
}

/// Sort orders for work folders on the Files view (`Studio-Files`).
nonisolated enum StudioFilesSort: String, CaseIterable, Identifiable, Hashable, Sendable {
    case edited
    case title
    case words

    var id: String { rawValue }

    var title: String {
        switch self {
        case .edited: "Edited"
        case .title: "Title"
        case .words: "Words"
        }
    }
}

/// Where a folder's writing currently lives (`Studio-Files`).
nonisolated enum StudioFolderBadge: String, Hashable, Sendable {
    case posted
    case ao3Draft
    case onDevice

    func title(deviceName: String) -> String {
        switch self {
        case .posted: "Posted"
        case .ao3Draft: "AO3 draft"
        case .onDevice: deviceName
        }
    }

    func legendDescription(deviceName: String) -> String {
        switch self {
        case .posted: "live on AO3"
        case .ao3Draft: "saved as an AO3 draft"
        case .onDevice: "only on this \(deviceName)"
        }
    }
}

/// Snapshot of a single local work loaded from `WritingDocumentStore`.
nonisolated struct StudioLocalWorkSnapshot: Equatable, Sendable {
    var work: WritingWork
    var chapters: [WritingChapter]
    var storyNotes: [WritingStoryNote]
    /// Plain-text excerpt per chapter id, used by the Recent cards on Pages.
    var chapterExcerpts: [UUID: String]

    init(
        work: WritingWork,
        chapters: [WritingChapter],
        storyNotes: [WritingStoryNote] = [],
        chapterExcerpts: [UUID: String] = [:]
    ) {
        self.work = work
        self.chapters = chapters
        self.storyNotes = storyNotes
        self.chapterExcerpts = chapterExcerpts
    }
}

/// Parsed AO3 `"posted/expected"` chapter string (e.g. `"3/8"`, `"3/?"`, `"7/7"`).
nonisolated struct StudioChapterCount: Equatable, Hashable, Sendable {
    var posted: Int?
    var expected: Int?

    static func parse(_ raw: String) -> StudioChapterCount {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return StudioChapterCount(posted: nil, expected: nil) }
        let parts = trimmed.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        let posted = Int(parts[0].trimmingCharacters(in: .whitespaces))
        let expected: Int? = if parts.count > 1 {
            Int(parts[1].trimmingCharacters(in: .whitespaces))
        } else {
            nil
        }
        return StudioChapterCount(posted: posted, expected: expected)
    }
}

/// One merged work entry combining any local `WritingDocumentStore` folder with
/// its AO3 posted work and/or AO3 draft when linked by `ao3WorkID`.
nonisolated struct StudioWorkItem: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    var localWork: WritingWork?
    var localChapters: [WritingChapter]
    var storyNotes: [WritingStoryNote]
    var chapterExcerpts: [UUID: String]
    var ao3PostedWork: AO3WorkSummary?
    var ao3DraftWork: AO3WorkSummary?
    var ao3DraftDaysLeft: Int?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var ao3WorkID: Int? {
        ao3PostedWork?.id ?? ao3DraftWork?.id ?? localWork?.ao3WorkID
    }

    var title: String {
        for candidate in [localWork?.title, ao3PostedWork?.title, ao3DraftWork?.title] {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        return "Untitled"
    }

    var isPostedOnAO3: Bool { ao3PostedWork != nil }
    var isAO3Draft: Bool { ao3DraftWork != nil }
    var isLocalOnly: Bool { ao3WorkID == nil && localWork != nil }
    var hasLocalCopy: Bool { localWork != nil }

    var hasPostedBadge: Bool {
        ao3PostedWork != nil || localChapters.contains { $0.status == .posted }
    }

    var hasAO3DraftBadge: Bool {
        ao3DraftWork != nil || localChapters.contains { $0.status == .ao3Draft }
    }

    var hasOnDeviceBadge: Bool {
        guard localWork != nil else { return false }
        if !hasPostedBadge && !hasAO3DraftBadge { return true }
        return localChapters.contains { $0.status == .local }
    }

    var folderBadges: [StudioFolderBadge] {
        var badges: [StudioFolderBadge] = []
        if hasPostedBadge { badges.append(.posted) }
        if hasAO3DraftBadge { badges.append(.ao3Draft) }
        if hasOnDeviceBadge { badges.append(.onDevice) }
        return badges
    }

    var hasDraftContent: Bool {
        ao3DraftWork != nil
            || isLocalOnly
            || localChapters.contains { $0.status == .ao3Draft || $0.status == .local }
    }

    var isGift: Bool {
        !(ao3PostedWork?.giftRecipients.isEmpty ?? true)
            || !(ao3DraftWork?.giftRecipients.isEmpty ?? true)
    }

    /// A single-chapter local document with no AO3 work and no story notes lives
    /// under Loose Drafts; multi-chapter works, works with story notes, and AO3
    /// works live under Manuscripts.
    var isLooseDraft: Bool {
        ao3WorkID == nil && localWork != nil && localChapters.count <= 1 && storyNotes.isEmpty
    }

    var isCompleteOnAO3: Bool {
        guard let posted = ao3PostedWork else { return false }
        if let complete = posted.isComplete { return complete }
        let counts = StudioChapterCount.parse(posted.chapters)
        if let postedCount = counts.posted, let expected = counts.expected {
            return postedCount >= expected && expected > 0
        }
        return false
    }

    var parsedAO3Chapters: StudioChapterCount {
        StudioChapterCount.parse(ao3PostedWork?.chapters ?? ao3DraftWork?.chapters ?? "")
    }

    var totalWordCount: Int {
        let localTotal = localChapters.reduce(0) { $0 + $1.wordCount }
        if let ao3Words = ao3PostedWork?.words {
            let hasPostedLocal = localChapters.contains { $0.status == .posted }
            if hasPostedLocal { return max(ao3Words, localTotal) }
            let unpostedLocal = localChapters
                .filter { $0.status != .posted }
                .reduce(0) { $0 + $1.wordCount }
            return max(localTotal, ao3Words + unpostedLocal)
        }
        if let draftWords = ao3DraftWork?.words {
            return max(draftWords, localTotal)
        }
        return localTotal
    }

    var chapterCountForDisplay: Int {
        let ao3Count = max(parsedAO3Chapters.expected ?? 0, parsedAO3Chapters.posted ?? 0)
        let combined = max(ao3Count, localChapters.count)
        if combined > 0 { return combined }
        return ao3DraftWork != nil ? 1 : 0
    }

    var lastEditedDate: Date {
        var candidates: [Date] = []
        if let workDate = localWork?.updatedAt { candidates.append(workDate) }
        candidates.append(contentsOf: localChapters.map(\.updatedAt))
        if let postedDate = ao3PostedWork.flatMap({ WorkStat.date(from: $0.dateUpdated) }) {
            candidates.append(postedDate)
        }
        if let draftDate = ao3DraftWork.flatMap({ WorkStat.date(from: $0.dateUpdated) }) {
            candidates.append(draftDate)
        }
        return candidates.max() ?? .distantPast
    }

    var primaryFandom: String? {
        let fandoms = ao3PostedWork?.fandoms ?? ao3DraftWork?.fandoms ?? []
        return fandoms.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func manuscriptStateLine(deviceName: String) -> String {
        if let posted = ao3PostedWork {
            return postedStateLine(posted)
        }
        if let draft = ao3DraftWork {
            var parts = ["AO3 draft"]
            if let days = ao3DraftDaysLeft {
                parts.append(days == 1 ? "1 day left" : "\(days) days left")
            }
            let words = max(draft.words ?? 0, localChapters.reduce(0) { $0 + $1.wordCount })
            if words > 0 { parts.append(Self.wordCountLabel(words)) }
            return parts.joined(separator: " · ")
        }
        var parts = ["On this \(deviceName)"]
        if !localChapters.isEmpty { parts.append(Self.chapterCountLabel(localChapters.count)) }
        let words = totalWordCount
        if words > 0 { parts.append(Self.wordCountLabel(words)) }
        return parts.joined(separator: " · ")
    }

    func looseDraftMetaLine(deviceName: String) -> String {
        let words = totalWordCount
        if words == 0 { return "Not started · only on this \(deviceName)" }
        return "\(Self.wordCountLabel(words)) · only on this \(deviceName)"
    }

    func folderMetaLine() -> String {
        var parts: [String] = []
        if isLooseDraft {
            parts.append("1 document")
            if totalWordCount > 0 { parts.append(Self.wordCountLabel(totalWordCount)) }
        } else {
            let chapters = chapterCountForDisplay
            parts.append(chapters > 0 ? Self.chapterCountLabel(chapters) : "Empty folder")
            if !storyNotes.isEmpty {
                let count = storyNotes.count
                parts.append(count == 1 ? "1 note" : "\(count) notes")
            }
        }
        return parts.joined(separator: " · ")
    }

    func selectMetaLine(deviceName: String) -> String {
        if ao3PostedWork != nil {
            var parts = ["Posted"]
            let counts = parsedAO3Chapters
            if isCompleteOnAO3 {
                parts.append("complete")
                if let posted = counts.posted, posted > 0 {
                    parts.append(Self.chapterCountLabel(posted))
                }
            } else if let posted = counts.posted, let expected = counts.expected {
                parts.append("\(posted) of \(expected) chapters")
            } else if let posted = counts.posted {
                parts.append(Self.chapterCountLabel(posted))
            }
            if let fandom = primaryFandom { parts.append(fandom) }
            return parts.joined(separator: " · ")
        }
        if ao3DraftWork != nil {
            if let days = ao3DraftDaysLeft {
                return "AO3 draft · \(days == 1 ? "1 day left" : "\(days) days left")"
            }
            return "AO3 draft"
        }
        return "On this \(deviceName) only"
    }

    private func postedStateLine(_ posted: AO3WorkSummary) -> String {
        let counts = StudioChapterCount.parse(posted.chapters)
        let ao3Words = posted.words ?? totalWordCount
        var parts: [String] = []
        if isCompleteOnAO3 {
            parts.append("Complete")
            if let count = counts.posted ?? counts.expected, count > 0 {
                parts.append(Self.chapterCountLabel(count))
            }
            if ao3Words > 0 { parts.append(Self.wordCountLabel(ao3Words)) }
        } else {
            parts.append("In progress")
            if let postedCount = counts.posted, let expected = counts.expected {
                parts.append("\(postedCount) of \(expected) posted")
            } else if let postedCount = counts.posted {
                parts.append("\(postedCount) posted")
            }
            if ao3Words > 0 { parts.append("\(Self.wordCountLabel(ao3Words)) on AO3") }
        }
        return parts.joined(separator: " · ")
    }

    static func chapterCountLabel(_ count: Int) -> String {
        count == 1 ? "1 chapter" : "\(count) chapters"
    }

    static func wordCountLabel(_ words: Int) -> String {
        words == 1 ? "1 word" : "\(words.formatted()) words"
    }
}

/// One paper-preview card in the Recent grid on `Studio-Documents`.
nonisolated struct StudioRecentDocumentItem: Identifiable, Equatable, Hashable, Sendable {
    enum BadgeTone: Equatable, Hashable, Sendable {
        case none
        case draft
        case onDevice
    }

    enum Target: Equatable, Hashable, Sendable {
        case localChapter(workID: UUID, chapterID: UUID, workTitle: String)
        case localWork(workID: UUID, workTitle: String)
        case ao3Draft(workID: Int)
        case ao3PostedWork(workID: Int, workTitle: String)
    }

    let id: String
    let workItemID: String
    let title: String
    let paperHeading: String
    let excerpt: String
    let badgeText: String?
    let badgeTone: BadgeTone
    let metaLine: String
    let editedAt: Date
    let target: Target
}

/// Same 15-minute window as `WritingView.isStale`. Duplicated here because that
/// helper is not on this branch; a later merge can call the shared one.
nonisolated enum StudioAO3Freshness {
    static let freshFor: TimeInterval = 15 * 60

    static func isStale(_ lastLoad: Date?, now: Date = Date()) -> Bool {
        guard let lastLoad else { return true }
        return now.timeIntervalSince(lastLoad) >= freshFor || now < lastLoad
    }
}

/// Process cache so leaving Documents (S1 destroys the view) or opening a work
/// does not hit AO3 again while the last load is still fresh.
@MainActor
final class StudioAO3LoadCache {
    static let shared = StudioAO3LoadCache()

    struct DocumentsEntry {
        var sessionGeneration: Int
        var username: String
        var posted: [AO3WorkSummary]
        var drafts: AO3DraftsPage?
        var loadedAt: Date
        var error: String?
    }

    struct ChaptersEntry {
        var sessionGeneration: Int
        var chapters: [AO3ChapterRef]
        var loadedAt: Date
        var error: String?
    }

    private var documentsEntry: DocumentsEntry?
    private var chapterEntries: [String: ChaptersEntry] = [:]

    func documents(session: Int, username: String) -> DocumentsEntry? {
        guard let documentsEntry,
              documentsEntry.sessionGeneration == session,
              documentsEntry.username.localizedCaseInsensitiveCompare(username) == .orderedSame
        else { return nil }
        return documentsEntry
    }

    /// `posted == nil` keeps the previous successful list. `draftsLoaded == false`
    /// keeps the previous drafts page. A failed reload must not blank what is shown.
    func storeDocuments(
        session: Int,
        username: String,
        posted: [AO3WorkSummary]?,
        drafts: AO3DraftsPage?,
        draftsLoaded: Bool,
        error: String?,
        loadedAt: Date
    ) {
        let previous = documents(session: session, username: username)
        documentsEntry = DocumentsEntry(
            sessionGeneration: session,
            username: username,
            posted: posted ?? previous?.posted ?? [],
            drafts: draftsLoaded ? drafts : previous?.drafts,
            loadedAt: loadedAt,
            error: error
        )
    }

    func chapters(workID: Int, session: Int) -> ChaptersEntry? {
        chapterEntries["\(session)|\(workID)"]
    }

    /// `chapters == nil` keeps the previous index.
    func storeChapters(
        workID: Int,
        session: Int,
        chapters: [AO3ChapterRef]?,
        error: String?,
        loadedAt: Date
    ) {
        let key = "\(session)|\(workID)"
        let previous = chapterEntries[key]
        chapterEntries[key] = ChaptersEntry(
            sessionGeneration: session,
            chapters: chapters ?? previous?.chapters ?? [],
            loadedAt: loadedAt,
            error: error
        )
    }

    func clear() {
        documentsEntry = nil
        chapterEntries.removeAll()
    }
}

/// Where Add Chapter should land. Looks up an existing local work before creating
/// another folder for the same `ao3WorkID`.
nonisolated enum StudioAddChapterTarget: Equatable, Sendable {
    case localChapter(workID: UUID)
    case ao3NewChapter(workID: Int)
    case createLocal(ao3WorkID: Int?, title: String)
}

nonisolated enum StudioAddChapterOutcome: Equatable, Sendable {
    case openedLocal(workID: UUID, chapterID: UUID, workTitle: String)
    case openAO3(workID: Int, workTitle: String, chapterCount: Int?)
}

nonisolated enum StudioAddChapterPlanner {
    static func target(
        work: StudioWorkItem,
        isSignedIn: Bool,
        existingLocalWorkID: UUID?
    ) -> StudioAddChapterTarget {
        if let localID = work.localWork?.id {
            return .localChapter(workID: localID)
        }
        if let existingLocalWorkID {
            return .localChapter(workID: existingLocalWorkID)
        }
        if let ao3WorkID = work.ao3WorkID, work.isPostedOnAO3, isSignedIn {
            return .ao3NewChapter(workID: ao3WorkID)
        }
        return .createLocal(ao3WorkID: work.ao3WorkID, title: work.title)
    }

    /// Newest local folder already linked to this AO3 work, if one exists.
    static func existingLocalWorkID(ao3WorkID: Int?, in works: [WritingWork]) -> UUID? {
        guard let ao3WorkID else { return nil }
        return works
            .filter { $0.ao3WorkID == ao3WorkID }
            .max { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
                return lhs.id.uuidString > rhs.id.uuidString
            }?
            .id
    }

    static func perform(
        work: StudioWorkItem,
        isSignedIn: Bool,
        store: WritingDocumentStore,
        ao3ChapterCount: Int?
    ) async throws -> StudioAddChapterOutcome {
        let existing: UUID?
        if work.localWork == nil, work.ao3WorkID != nil {
            existing = existingLocalWorkID(
                ao3WorkID: work.ao3WorkID,
                in: try await store.listWorks()
            )
        } else {
            existing = nil
        }
        switch target(work: work, isSignedIn: isSignedIn, existingLocalWorkID: existing) {
        case let .localChapter(workID):
            let chapter = try await store.addChapter(workID: workID, title: "")
            let title = work.localWork?.title ?? work.title
            return .openedLocal(workID: workID, chapterID: chapter.id, workTitle: title)
        case let .ao3NewChapter(workID):
            return .openAO3(
                workID: workID,
                workTitle: work.title,
                chapterCount: ao3ChapterCount ?? work.chapterCountForDisplay
            )
        case let .createLocal(ao3WorkID, title):
            let created = try await store.createWork(title: title, ao3WorkID: ao3WorkID)
            let chapter = try await store.addChapter(workID: created.id, title: "")
            return .openedLocal(
                workID: created.id,
                chapterID: chapter.id,
                workTitle: created.title
            )
        }
    }
}
