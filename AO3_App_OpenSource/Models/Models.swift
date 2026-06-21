import Foundation
import SwiftData

/// A work the user has saved from AO3, backed by an EPUB file on disk.
@Model final class SavedWork {
    /// Stable identifier; also used as the on-disk EPUB file name.
    var id: UUID = UUID()
    var title: String = ""
    var author: String = ""
    var summary: String = ""
    var sourceURL: String = ""
    var dateAdded: Date = Date()

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

    /// AO3 rating (e.g. "Mature"), read from the EPUB metadata. Used by the
    /// mature-content privacy feature and tag display.
    var rating: String = ""

    /// Human-readable language (e.g. "English"), from the EPUB's `dc:language`
    /// on import and refreshed from AO3's work page. A Library filter facet.
    var language: String = ""

    /// Total word count from AO3's work stats. 0 until refreshed from AO3 (the
    /// EPUB doesn't carry it); used by the Library word-count filter and sort.
    var wordCount: Int = 0

    /// AO3 work stats shown on the Library card, mirroring the Search results.
    /// Both come from the AO3 refresh (the EPUB carries neither): `chapters` is
    /// printed as AO3 shows it (e.g. "5/10"); `kudos` is 0 until known.
    var chapters: String = ""
    var kudos: Int = 0

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

    /// Reading progress so the reader can resume where the user left off.
    var lastSpineIndex: Int = 0
    var lastScrollFraction: Double = 0

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

    /// True once the type-split Work Tags are available (after an AO3 refresh).
    var hasCategorizedWorkTags: Bool {
        !(workFandoms.isEmpty && workCharacters.isEmpty
          && workRelationships.isEmpty && workFreeforms.isEmpty)
    }

    /// Whether an AO3 refresh would still add data the Library filters rely on:
    /// the categorized Work Tags, or the newer warnings/categories/language/word
    /// count. Drives both the on-demand refresh and the Library's background
    /// backfill, so the two never diverge on what counts as "needs refreshing".
    var needsAO3Refresh: Bool {
        !workTagsFetched || !hasCategorizedWorkTags
            || (workWarnings.isEmpty && workCategories.isEmpty
                && language.isEmpty && wordCount == 0)
            // Backfill the newer card stats for works saved before they existed.
            || chapters.isEmpty
    }

    /// The user's own organizational tags (User Tags), shared across works.
    @Relationship(inverse: \Tag.works) var tags: [Tag] = []

    /// Kept works (explicitly saved or favorited) never have their EPUB freed.
    var isProtected: Bool { isSaved || isFavorite }

    /// The posted-chapter count parsed from the `chapters` stats string ("5/10" → 5).
    var postedChapterCount: Int {
        Int(chapters.split(separator: "/").first?.trimmingCharacters(in: .whitespaces) ?? "") ?? 0
    }

    /// AO3 has new chapters the user hasn't seen (live posted count exceeds the
    /// baseline). Drives Home → Recently Updated.
    var hasUpdate: Bool {
        knownChapterCount > 0 && postedChapterCount > knownChapterCount
    }

    /// Started but not finished, with its EPUB on disk — the in-progress / "Reading
    /// Now" state shared by the Home and Library shelves.
    var isInProgress: Bool {
        hasEPUB && !isFinished && (lastSpineIndex > 0 || lastScrollFraction > 0)
    }

    /// Reading progress in 0…1 for the Reading Now shelves: chapter position over the
    /// work's AO3 chapter count ("5/10"), falling back to the in-chapter scroll
    /// fraction. `nil` when there's nothing meaningful to show.
    var readingProgress: Double? {
        let parts = chapters.split(separator: "/")
        if parts.count == 2, let total = Int(parts[1].trimmingCharacters(in: .whitespaces)), total > 1 {
            return min(1, Double(lastSpineIndex + 1) / Double(total))
        }
        return lastScrollFraction > 0 ? lastScrollFraction : nil
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
        self.dateAdded = Date()
    }

    /// Location of the stored EPUB on disk.
    var fileURL: URL {
        Storage.worksDirectory.appendingPathComponent("\(id.uuidString).epub")
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
        self.dateAdded = Date()
    }

    var url: URL? { URL(string: urlString) }
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
        self.dateAdded = Date()
    }

    var fileURL: URL { Storage.fontsDirectory.appendingPathComponent(fileName) }

    /// Stable identifier used to persist the reader's font selection.
    var selectionID: String { "custom:\(fileName)" }
}

extension SavedWork {
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
