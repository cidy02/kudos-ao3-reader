import Foundation
import SwiftData

nonisolated enum EPUBPreservationStatus: String, Codable, CaseIterable {
    case notPreserved
    case queued
    case preserving
    case preserved
    case failed
    case missingFile
}

nonisolated enum MetadataSyncStatus: String, Codable, CaseIterable {
    case unknown
    case pending
    case syncing
    case complete
    case incomplete
    case failed
}

nonisolated enum SyncRecordStatus: String, Codable, CaseIterable {
    case localOnly
    case pending
    case syncing
    case synced
    case conflict
    case failed
    case assetsMissing
}

nonisolated enum ReadingQueueKind: String, Codable, CaseIterable {
    case savedForLater
    case custom
}

nonisolated enum SyncTombstoneRecordType: String, Codable, CaseIterable {
    case savedWork
    case workCollection
    case readingQueue
    case readingQueueMembership
    /// A work explicitly removed from a collection. Collection membership has no
    /// first-class join model (unlike ReadingQueueMembership), so `recordID` here is a
    /// deterministic composite of the collection and work IDs — see
    /// `SyncTombstone.collectionMembershipID(collectionID:workID:)`.
    case workCollectionMembership
}

/// Durable marker for an explicit local deletion. Future cloud merge code must treat
/// tombstones as user intent and not resurrect records just because another device
/// still has an older copy.
@Model final class SyncTombstone {
    var id: UUID = UUID()
    var recordID: UUID = UUID()
    var recordTypeRaw: String = SyncTombstoneRecordType.savedWork.rawValue
    var createdAt: Date = Date()
    var lastModifiedAt: Date = Date()
    var sourceURL: String = ""
    var ao3WorkID: Int?
    var deletedOnDeviceID: String = ""
    var deletionReason: String = ""

    init(
        recordID: UUID,
        recordType: SyncTombstoneRecordType,
        sourceURL: String = "",
        ao3WorkID: Int? = nil,
        createdAt: Date = Date(),
        deletedOnDeviceID: String = "",
        deletionReason: String = ""
    ) {
        id = UUID()
        self.recordID = recordID
        recordTypeRaw = recordType.rawValue
        self.sourceURL = sourceURL
        self.ao3WorkID = ao3WorkID
        self.createdAt = createdAt
        lastModifiedAt = createdAt
        self.deletedOnDeviceID = deletedOnDeviceID
        self.deletionReason = deletionReason
    }

    var recordType: SyncTombstoneRecordType {
        get { SyncTombstoneRecordType(rawValue: recordTypeRaw) ?? .savedWork }
        set { recordTypeRaw = newValue.rawValue }
    }

    /// Deterministic, order-independent composite ID for a (collection, work) pair,
    /// used as `recordID` for `.workCollectionMembership` tombstones since that
    /// membership has no first-class join model of its own to carry a stable ID.
    static func collectionMembershipID(collectionID: UUID, workID: UUID) -> UUID {
        let collectionBytes = withUnsafeBytes(of: collectionID.uuid) { Array($0) }
        let workBytes = withUnsafeBytes(of: workID.uuid) { Array($0) }
        var combined = [UInt8](repeating: 0, count: 16)
        for i in 0..<16 { combined[i] = collectionBytes[i] ^ workBytes[i] }
        return UUID(uuid: (
            combined[0], combined[1], combined[2], combined[3],
            combined[4], combined[5], combined[6], combined[7],
            combined[8], combined[9], combined[10], combined[11],
            combined[12], combined[13], combined[14], combined[15]
        ))
    }
}

/// A work the user has saved from AO3, backed by an EPUB file on disk.
@Model final class SavedWork {
    /// Stable identifier; also used as the on-disk EPUB file name.
    var id: UUID = UUID()
    var title: String = ""
    var author: String = ""
    var summary: String = ""
    var sourceURL: String = ""
    var dateAdded: Date = Date()
    var createdAt: Date = Date()
    var lastModifiedAt: Date = Date()
    var deletedAt: Date?
    var isPendingDeletion: Bool = false
    /// When a soft-deleted work's 90-day Recently Deleted window ends and it becomes
    /// eligible for permanent removal (`PreservedWorkService.sweepExpired`). Only
    /// meaningful while `isPendingDeletion == true`.
    var permanentDeletionScheduledAt: Date?

    /// Derived, rebuildable search text: the work's searchable fields (title, author,
    /// tags, rating, language, …) normalized once (lowercased, diacritics folded) by
    /// `WorkSearchIndex.reindex` so Library/Search matching never re-normalizes per
    /// keystroke. Never source of truth, never exported in backups — any record can be
    /// rebuilt from the real fields at any time (see `searchIndexVersion`).
    var searchText: String = ""
    /// Stamp of the `WorkSearchIndex` schema this record was last indexed with. A
    /// mismatch with `WorkSearchIndex.currentVersion` (including 0 for records that
    /// predate indexing or arrived via backup restore) marks it for the launch rebuild.
    var searchIndexVersion: Int = 0

    /// Stable name for the EPUB asset associated with this metadata record. This is
    /// intentionally separate from title/author/source URL so future iCloud Documents
    /// asset lookup can survive AO3 metadata edits and local title changes.
    var assetIdentifier: String = ""
    var syncStatusRaw: String = SyncRecordStatus.localOnly.rawValue
    var lastSyncAttemptAt: Date?
    var lastSyncError: String = ""

    /// Whether the user has marked this work as a favorite.
    var isFavorite: Bool = false

    /// Whether the user explicitly saved this work to keep its EPUB permanently.
    var isSaved: Bool = false

    /// Whether the user has finished reading. When finished and not kept
    /// (`isProtected == false`), the EPUB is freed and the work becomes history.
    var isFinished: Bool = false

    /// Whether the EPUB is currently on disk. False = a history entry whose file
    /// was freed; revisiting re-downloads it.
    var hasEPUB: Bool = true

    /// Whether AO3 marks the work complete (known only for native imports).
    /// Reaching the end auto-finishes only complete works; WIPs need a manual mark.
    var isComplete: Bool = false

    /// Reading Queue membership/protection state. This says the work belongs to at
    /// least one native queue; it does *not* guarantee the EPUB is present.
    var isQueuedForLater: Bool = false

    /// Durable preservation state for queued works. Stored as raw strings so future
    /// app versions and other platforms can decode unknown/default values safely.
    var epubPreservationStatusRaw: String = EPUBPreservationStatus.notPreserved.rawValue
    var metadataSyncStatusRaw: String = MetadataSyncStatus.unknown.rawValue
    var preservedAt: Date?
    var lastPreservationAttemptAt: Date?
    var lastAvailabilityCheck: Date?

    /// Stable AO3 identity, when known. Legacy works can derive it from `sourceURL`.
    var ao3WorkID: Int?

    /// AO3 rating (e.g. "Mature"), read from the EPUB metadata. Used by the
    /// mature-content privacy feature and tag display.
    var rating: String = ""

    /// Human-readable language (e.g. "English"), from the EPUB's `dc:language`
    /// on import and refreshed from AO3's work page. A Library filter facet.
    var language: String = ""

    /// Total word count from AO3's work stats. 0 until refreshed from AO3 (the
    /// EPUB doesn't carry it); used by the Library word-count filter and sort.
    var wordCount: Int = 0

    /// Best-effort AO3/EPUB date text. Remote AO3 summaries already carry their own
    /// dates; these persist dates parsed from a locally imported EPUB.
    var datePublished: String = ""
    var dateUpdated: String = ""

    /// AO3 work stats shown on the Library card, mirroring the Search results.
    /// Both come from the AO3 refresh (the EPUB carries neither): `chapters` is
    /// printed as AO3 shows it (e.g. "5/10"); `kudos` is 0 until known.
    var chapters: String = ""
    var kudos: Int = 0
    /// AO3 comment and hit counts, from the AO3 refresh / native import. 0 = unknown.
    var comments: Int = 0
    var hits: Int = 0

    /// AO3 archive warnings and categories for the work (e.g. "Graphic Depictions
    /// Of Violence", "M/M"). Populated on AO3 refresh; before then the Library
    /// filter derives them from `workTags`, which also include these names.
    var workWarnings: [String] = []
    var workCategories: [String] = []

    /// Series info, when the work belongs to one. Title + position come from the
    /// EPUB (calibre series metadata); the AO3 series URL is set for native imports.
    var seriesTitle: String = ""
    var seriesPosition: Int = 0
    var seriesURL: String = ""
    var ao3SeriesID: Int?

    /// Reading progress so the reader can resume where the user left off. The legacy
    /// WKWebView reader uses spine index + scroll fraction; the Readium reader persists
    /// its richer `Locator` as a JSON string (`readiumLocator`).
    var lastSpineIndex: Int = 0
    var lastScrollFraction: Double = 0
    var readiumLocator: String = ""
    var progressModifiedAt: Date?

    /// When the work was last opened in the reader. Drives the Library's
    /// "Continue Reading" ordering; nil for works never opened (or pre-migration).
    var lastReadDate: Date?

    /// Update detection (Home → Recently Updated). `knownChapterCount` is the posted
    /// chapter count the user has "seen" — set to the downloaded count on a native
    /// import, or baselined on the first update check. When AO3's live posted count
    /// (parsed from `chapters`) exceeds it, the work has new chapters. `0` = not yet
    /// baselined. `lastUpdateCheck` is when AO3 was last polled for this work.
    var knownChapterCount: Int = 0
    var lastUpdateCheck: Date?

    /// AO3's own tags for this work (fandoms, relationships, characters, freeform),
    /// read from the EPUB on import. These are intrinsic to the work — distinct from
    /// `tags`, which are the user's own organizational tags. Shown read-only and
    /// usable as a Library filter. Kept as the flat union of the categorized lists
    /// below (EPUB subjects are uncategorized, so before an AO3 refresh only this is
    /// populated and the detail view shows it as a single list).
    var workTags: [String] = []

    /// AO3's tags split by type, populated when refreshed from the live work page.
    /// EPUB metadata is uncategorized, so these stay empty until the refresh.
    var workFandoms: [String] = []
    var workCharacters: [String] = []
    var workRelationships: [String] = []
    var workFreeforms: [String] = []

    /// Whether `workTags` have been refreshed from AO3's live work page (the
    /// canonical source). Until then they come from the EPUB; the refresh runs in
    /// the background and retries on failure, so this only flips on success.
    var workTagsFetched: Bool = false

    /// When a tag refresh was last *attempted* (success or not), so locked/failing
    /// works aren't re-fetched every session. Device-local politeness state, not
    /// user data — deliberately NOT carried in `.kudosbackup`.
    var lastTagRefreshAttemptAt: Date?

    /// Set once AO3 returns 404 for this work — it's been deleted (or hidden) on the
    /// site, so the background refresh stops re-fetching it and the work keeps whatever
    /// tags it already has (EPUB-derived or a prior AO3 fetch). Distinct from a locked /
    /// login-gated page, which returns content (no tags) and stays retryable.
    var ao3Unavailable: Bool = false

    /// True once the type-split Work Tags are available (after an AO3 refresh).
    var hasCategorizedWorkTags: Bool {
        !(workFandoms.isEmpty && workCharacters.isEmpty
            && workRelationships.isEmpty && workFreeforms.isEmpty)
    }

    /// Don't re-attempt a tag refresh for the same work more often than this.
    static let tagRefreshMinInterval: TimeInterval = 24 * 3600

    /// Whether an AO3 refresh would still add data the Library filters rely on:
    /// the categorized Work Tags, or the newer warnings/categories/language/word
    /// count. Drives both the on-demand refresh and the Library's background
    /// backfill, so the two never diverge on what counts as "needs refreshing".
    var needsAO3Refresh: Bool {
        // A work deleted from AO3 can't be refreshed — keep the tags we have and stop
        // hitting the site for it.
        guard !ao3Unavailable else { return false }
        // Locked/empty pages stay retryable, but only after a cooldown — otherwise
        // the Library backfill re-fetches every locked work each session forever.
        if let attempt = lastTagRefreshAttemptAt,
           Date().timeIntervalSince(attempt) < Self.tagRefreshMinInterval {
            return false
        }
        return !workTagsFetched || !hasCategorizedWorkTags
            || (workWarnings.isEmpty && workCategories.isEmpty
                && language.isEmpty && wordCount == 0)
            // Backfill the newer card stats for works saved before they existed.
            || chapters.isEmpty
    }

    /// The user's own organizational tags (User Tags), shared across works.
    @Relationship(inverse: \Tag.works) var tags: [Tag] = []

    /// The user's Collections (named shelves) this work belongs to. A work can be in
    /// many collections; a collection holds many works.
    @Relationship(inverse: \WorkCollection.works) var collections: [WorkCollection] = []

    /// Reading Queue memberships this work belongs to. Queue membership protects
    /// preserved EPUBs but remains distinct from Library saved/favorite state.
    @Relationship(deleteRule: .cascade, inverse: \ReadingQueueMembership.work)
    var queueMemberships: [ReadingQueueMembership] = []

    var epubPreservationStatus: EPUBPreservationStatus {
        get { EPUBPreservationStatus(rawValue: epubPreservationStatusRaw) ?? .notPreserved }
        set { epubPreservationStatusRaw = newValue.rawValue }
    }

    var metadataSyncStatus: MetadataSyncStatus {
        get { MetadataSyncStatus(rawValue: metadataSyncStatusRaw) ?? .unknown }
        set { metadataSyncStatusRaw = newValue.rawValue }
    }

    var syncStatus: SyncRecordStatus {
        get { SyncRecordStatus(rawValue: syncStatusRaw) ?? .localOnly }
        set { syncStatusRaw = newValue.rawValue }
    }

    var effectiveAssetIdentifier: String {
        assetIdentifier.isEmpty ? Storage.defaultEPUBAssetIdentifier(for: id) : assetIdentifier
    }

    /// Queue-only works are preserved/readable but intentionally hidden from normal
    /// Library shelves until the user explicitly saves or favorites them.
    var isQueueOnlyWork: Bool {
        isQueuedForLater && !isSaved && !isFavorite
    }

    /// Kept works (saved, favorited, or queued) never have their EPUB freed. A work
    /// with no known AO3 origin is also always protected — freeing only makes sense
    /// when the EPUB can be re-downloaded, and a plain (non-AO3) import has no way
    /// back if its only copy is deleted.
    var isProtected: Bool {
        isSaved || isFavorite || isQueuedForLater || ao3WorkID == nil
    }

    var isInSavedForLaterQueue: Bool {
        queueMemberships.contains { $0.queue?.kind == .savedForLater }
    }

    /// The posted-chapter count parsed from the `chapters` stats string ("5/10" → 5).
    var postedChapterCount: Int {
        Self.postedChapterCount(from: chapters)
    }

    /// AO3 has new chapters the user hasn't seen (live posted count exceeds the
    /// baseline). Drives Home → Recently Updated.
    var hasUpdate: Bool {
        knownChapterCount > 0 && postedChapterCount > knownChapterCount
    }

    /// Overall reading fraction (0…1) persisted by the Readium reader, parsed from
    /// its stored locator JSON. Pure Foundation parsing, so it needs no Readium
    /// dependency (and works on macOS). `nil` when never read in the Readium reader.
    var readiumProgress: Double? {
        guard !readiumLocator.isEmpty,
              let data = readiumLocator.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let locations = object["locations"] as? [String: Any],
              let total = locations["totalProgression"] as? Double
        else { return nil }
        return total
    }

    /// The user has opened this work in either reader. The Readium reader records a
    /// `readiumLocator`; the legacy reader records a spine index / scroll fraction.
    /// Both stamp `lastReadDate`, which also covers works restored from a backup.
    var hasStartedReading: Bool {
        lastReadDate != nil || !readiumLocator.isEmpty
            || lastSpineIndex > 0 || lastScrollFraction > 0
    }

    /// The single reading-lifecycle state, folding `isFinished` / `hasEPUB` /
    /// `hasStartedReading` into one partition so shelf filters, statistics, and
    /// (eventually) Library/History filter facets can't drift on the definitions.
    /// Exactly one case is true for every work.
    ///
    /// Orthogonal concerns stay out on purpose: AO3's posted status (`isComplete`,
    /// the WIP-vs-complete search filter), queue membership, privacy, and
    /// soft-deletion (`isPendingDeletion`) are separate axes callers still filter on.
    /// Note SwiftData `#Predicate`s can't call computed properties — @Query sites
    /// (e.g. reading history) keep the equivalent stored-field predicate instead.
    enum ReadingState: String, CaseIterable {
        /// EPUB on disk, never opened in a reader.
        case unread
        /// Started but not finished, with its EPUB on disk (the "Reading Now" state).
        case inProgress
        /// Marked finished by the user — wins even after the EPUB is freed.
        case finished
        /// EPUB freed without being finished: a history-only record; revisiting
        /// re-downloads it.
        case freedHistory
    }

    var readingState: ReadingState {
        if isFinished { return .finished }
        if !hasEPUB { return .freedHistory }
        return hasStartedReading ? .inProgress : .unread
    }

    /// Started but not finished, with its EPUB on disk — the in-progress / "Reading
    /// Now" state shared by the Home and Library shelves.
    var isInProgress: Bool {
        readingState == .inProgress
    }

    /// Reading progress in 0…1 for the Reading Now shelves. Prefers the Readium
    /// reader's exact fraction; falls back to the legacy reader's chapter position
    /// over the work's AO3 chapter count ("5/10") or its in-chapter scroll fraction.
    /// `nil` when there's nothing meaningful to show.
    var readingProgress: Double? {
        if let readium = readiumProgress { return readium }
        let parts = chapters.split(separator: "/")
        if parts.count == 2, let total = Int(parts[1].trimmingCharacters(in: .whitespaces)), total > 1 {
            return min(1, Double(lastSpineIndex + 1) / Double(total))
        }
        return lastScrollFraction > 0 ? lastScrollFraction : nil
    }

    /// Short progress label for the Reading Now / Recently Opened cards: the legacy
    /// reader's chapter, else the Readium reader's overall percent.
    var readingProgressLabel: String? {
        if lastSpineIndex > 0 { return "Ch \(lastSpineIndex + 1)" }
        if let readium = readiumProgress { return "\(Int((readium * 100).rounded()))%" }
        return nil
    }

    init(
        id: UUID = UUID(),
        title: String,
        author: String,
        summary: String = "",
        sourceURL: String = ""
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.summary = summary
        self.sourceURL = sourceURL
        dateAdded = Date()
        createdAt = dateAdded
        lastModifiedAt = dateAdded
        assetIdentifier = Storage.defaultEPUBAssetIdentifier(for: id)
    }

    /// Location of the stored EPUB on disk.
    var fileURL: URL {
        Storage.workAssetURL(identifier: effectiveAssetIdentifier, fallbackID: id)
    }

    func markModified(_ date: Date = Date()) {
        lastModifiedAt = date
        if syncStatus == .synced { syncStatus = .pending }
    }

    func markProgressModified(_ date: Date = Date()) {
        lastReadDate = date
        progressModifiedAt = date
        markModified(date)
    }
}

/// A user-defined tag used to organize the library.
@Model final class Tag {
    @Attribute(.unique) var name: String = ""
    var works: [SavedWork] = []

    init(name: String) {
        self.name = name
    }
}

/// A saved AO3 link the user can reopen in the Browse tab.
@Model final class Bookmark {
    var title: String = ""
    var urlString: String = ""
    var dateAdded: Date = Date()

    init(title: String, urlString: String) {
        self.title = title
        self.urlString = urlString
        dateAdded = Date()
    }

    var url: URL? {
        URL(string: urlString)
    }
}

/// A font file the user imported for use in the reader.
@Model final class CustomFont {
    /// Display name shown in the font picker.
    var name: String = ""
    /// File name within the fonts directory.
    var fileName: String = ""
    var dateAdded: Date = Date()

    init(name: String, fileName: String) {
        self.name = name
        self.fileName = fileName
        dateAdded = Date()
    }

    var fileURL: URL {
        Storage.fontsDirectory.appendingPathComponent(fileName)
    }

    /// Stable identifier used to persist the reader's font selection.
    var selectionID: String {
        "custom:\(fileName)"
    }
}

/// A user-named Collection (shelf) grouping works in the Library. Many-to-many with
/// `SavedWork` (a work can live in several collections). Named `WorkCollection` to
/// avoid shadowing Swift's `Collection` protocol.
@Model final class WorkCollection {
    var id: UUID = UUID()
    var name: String = ""
    var dateAdded: Date = Date()
    var createdAt: Date = Date()
    var lastModifiedAt: Date = Date()
    var deletedAt: Date?
    var isPendingDeletion: Bool = false
    /// See `SavedWork.permanentDeletionScheduledAt`.
    var permanentDeletionScheduledAt: Date?
    var syncStatusRaw: String = SyncRecordStatus.localOnly.rawValue
    var lastSyncAttemptAt: Date?
    var lastSyncError: String = ""

    /// The works in this collection (inverse of `SavedWork.collections`).
    var works: [SavedWork] = []

    init(name: String) {
        self.name = name
        dateAdded = Date()
        createdAt = dateAdded
        lastModifiedAt = dateAdded
    }

    var syncStatus: SyncRecordStatus {
        get { SyncRecordStatus(rawValue: syncStatusRaw) ?? .localOnly }
        set { syncStatusRaw = newValue.rawValue }
    }

    func markModified(_ date: Date = Date()) {
        lastModifiedAt = date
        if syncStatus == .synced { syncStatus = .pending }
    }
}

/// A native reading queue. The built-in Saved for Later queue is identified by
/// `kind == .savedForLater`; names are display labels, not stable identities.
@Model final class ReadingQueue {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = ReadingQueueKind.custom.rawValue
    var sortOrder: Int = 0
    var dateCreated: Date = Date()
    var dateUpdated: Date = Date()
    var lastMembershipChangedAt: Date = Date()
    var deletedAt: Date?
    var isPendingDeletion: Bool = false
    /// See `SavedWork.permanentDeletionScheduledAt`.
    var permanentDeletionScheduledAt: Date?
    var syncStatusRaw: String = SyncRecordStatus.localOnly.rawValue
    var lastSyncAttemptAt: Date?
    var lastSyncError: String = ""

    @Relationship(deleteRule: .cascade, inverse: \ReadingQueueMembership.queue)
    var memberships: [ReadingQueueMembership] = []

    init(
        id: UUID = UUID(),
        name: String,
        kind: ReadingQueueKind = .custom,
        sortOrder: Int = 0,
        dateCreated: Date = Date(),
        dateUpdated: Date = Date()
    ) {
        self.id = id
        self.name = name
        kindRaw = kind.rawValue
        self.sortOrder = sortOrder
        self.dateCreated = dateCreated
        self.dateUpdated = dateUpdated
        lastMembershipChangedAt = dateUpdated
    }

    var kind: ReadingQueueKind {
        get { ReadingQueueKind(rawValue: kindRaw) ?? .custom }
        set { kindRaw = newValue.rawValue }
    }

    var syncStatus: SyncRecordStatus {
        get { SyncRecordStatus(rawValue: syncStatusRaw) ?? .localOnly }
        set { syncStatusRaw = newValue.rawValue }
    }

    var displayName: String {
        kind == .savedForLater ? "Saved for Later" : name
    }

    func markModified(_ date: Date = Date()) {
        dateUpdated = date
        if syncStatus == .synced { syncStatus = .pending }
    }

    func markMembershipChanged(_ date: Date = Date()) {
        lastMembershipChangedAt = date
        markModified(date)
    }
}

/// Join record between a work and a reading queue. Duplicate queue/work pairs are
/// prevented in `ReadingQueueService` rather than with a fragile unique attribute.
@Model final class ReadingQueueMembership {
    var id: UUID = UUID()
    var queuedAt: Date = Date()
    var lastModifiedAt: Date = Date()
    var deletedAt: Date?
    var isPendingDeletion: Bool = false
    var sortOrderInQueue: Int = 0
    var note: String = ""
    var syncStatusRaw: String = SyncRecordStatus.localOnly.rawValue
    var lastSyncAttemptAt: Date?
    var lastSyncError: String = ""

    var queue: ReadingQueue?
    var work: SavedWork?

    init(
        id: UUID = UUID(),
        queue: ReadingQueue,
        work: SavedWork,
        queuedAt: Date = Date(),
        sortOrderInQueue: Int = 0,
        note: String = ""
    ) {
        self.id = id
        self.queue = queue
        self.work = work
        self.queuedAt = queuedAt
        lastModifiedAt = queuedAt
        self.sortOrderInQueue = sortOrderInQueue
        self.note = note
    }

    var syncStatus: SyncRecordStatus {
        get { SyncRecordStatus(rawValue: syncStatusRaw) ?? .localOnly }
        set { syncStatusRaw = newValue.rawValue }
    }

    func markModified(_ date: Date = Date()) {
        lastModifiedAt = date
        if syncStatus == .synced { syncStatus = .pending }
    }
}

extension SavedWork {
    /// Parses AO3's "5/10" chapter stat into the posted-chapter count (the "5" side).
    /// Shared by `postedChapterCount` and the queue's metadata baseline.
    static func postedChapterCount(from chapters: String) -> Int {
        Int(chapters.split(separator: "/").first?.trimmingCharacters(in: .whitespaces) ?? "") ?? 0
    }

    /// Cleans an EPUB subject list into display-ready Work Tags: trims whitespace,
    /// drops blanks and the rating (shown separately), and removes duplicates while
    /// preserving order. Shared by import and the lazy backfill.
    static func normalizedWorkTags(_ subjects: [String], excludingRating rating: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in subjects {
            let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty, tag != rating, seen.insert(tag).inserted else { continue }
            result.append(tag)
        }
        return result
    }
}
