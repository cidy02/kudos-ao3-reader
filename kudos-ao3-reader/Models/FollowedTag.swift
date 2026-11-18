import Foundation
import SwiftData

/// A tag followed locally through AO3's public `/tags/:id/feed.atom` feeds.
///
/// AO3 has no tag subscriptions of its own and omits Atom feeds for tags outside
/// Fandom, Character, Relationship, and category `"F/F"`. Every field stored
/// here is a plain primitive (or optional primitive) rather than a SwiftData
/// composite attribute so store migration and backups stay trivial and lossless.
@Model final class FollowedTag {
    /// Local hard limit matching AO3 networking policy for foreground feed checks.
    nonisolated static let maxFollowedCount = 20
    /// Minimum spacing between two check attempts for the same tag.
    nonisolated static let checkInterval: TimeInterval = 6 * 60 * 60
    /// How many seen work IDs are kept per tag to prevent repeated alerts as newer
    /// works rotate through the top 25 feed entries.
    nonisolated static let seenIDRetentionLimit = 100

    var id: UUID = UUID()
    /// AO3's numeric `Tag.id` used in `/tags/<id>/feed.atom`.
    var ao3TagID: Int = 0
    /// Display name of the tag (typically canonical, e.g. `"Doctor Who (2005)"`).
    var name: String = ""
    /// Optional AO3 tag kind label (`"Fandom"`, `"Character"`, `"Relationship"`, `"Category"`).
    var tagCategoryRaw: String?
    /// Optional AO3 `/tags/<slug>/works` URL string captured when following.
    var tagURLString: String?

    /// Feed switches configured in the Follow Tag sheet; applied locally.
    var showOnHome: Bool = true
    var completeOnly: Bool = false
    var hideExplicit: Bool = false

    /// When the tag was followed locally.
    var followedAt: Date = Date()
    /// When Kudos last attempted a feed check (stamped on failure as well as success).
    var lastCheckedAt: Date?
    /// Highest / newest seen work ID from an Atom feed entry.
    var lastSeenWorkID: Int?
    /// Publication timestamp (`<published>`) of the newest seen feed entry.
    var lastSeenPublishedAt: Date?
    /// Plain comma-separated ASCII work IDs seen in prior checks (capped at 100).
    var seenWorkIDsRaw: String?
    /// Last user/sync modification timestamp for LWW backup & folder sync merge.
    var lastModifiedAt: Date = Date()

    init(
        id: UUID = UUID(),
        ao3TagID: Int,
        name: String,
        tagCategoryRaw: String? = nil,
        tagURLString: String? = nil,
        showOnHome: Bool = true,
        completeOnly: Bool = false,
        hideExplicit: Bool = false,
        followedAt: Date = Date(),
        lastCheckedAt: Date? = nil,
        lastSeenWorkID: Int? = nil,
        lastSeenPublishedAt: Date? = nil,
        seenWorkIDs: [Int] = [],
        lastModifiedAt: Date? = nil
    ) {
        self.id = id
        self.ao3TagID = ao3TagID
        self.name = name
        let trimmedCategory = tagCategoryRaw?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tagCategoryRaw = trimmedCategory?.isEmpty == true ? nil : trimmedCategory
        let trimmedURL = tagURLString?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tagURLString = trimmedURL?.isEmpty == true ? nil : trimmedURL
        self.showOnHome = showOnHome
        self.completeOnly = completeOnly
        self.hideExplicit = hideExplicit
        self.followedAt = followedAt
        self.lastCheckedAt = lastCheckedAt
        self.lastSeenWorkID = lastSeenWorkID
        self.lastSeenPublishedAt = lastSeenPublishedAt
        self.lastModifiedAt = lastModifiedAt ?? followedAt
        self.seenWorkIDsRaw = Self.encodeSeenWorkIDs(seenWorkIDs)
    }

    var seenWorkIDs: [Int] {
        get { Self.decodeSeenWorkIDs(seenWorkIDsRaw) }
        set { seenWorkIDsRaw = Self.encodeSeenWorkIDs(newValue) }
    }

    var displayCategory: String? {
        guard let trimmed = tagCategoryRaw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    var worksURL: URL? {
        if let raw = tagURLString, let parsed = URL(string: raw),
           AO3RequestDefaults.isTrustedURL(parsed) {
            return parsed
        }
        return AO3Client.tagWorksURL(tagName: name)
    }

    var feedURL: URL? {
        AO3Client.tagFeedURL(tagID: ao3TagID)
    }

    func isEligibleForCheck(at now: Date, ignoringCooldown: Bool = false) -> Bool {
        if ignoringCooldown { return true }
        guard let lastCheckedAt else { return true }
        return now.timeIntervalSince(lastCheckedAt) >= Self.checkInterval
    }

    var settingsSummary: String {
        var parts: [String] = []
        parts.append(showOnHome ? "On Home" : "Subscriptions only")
        if completeOnly { parts.append("Complete only") }
        if hideExplicit { parts.append("Hide Explicit") }
        return parts.joined(separator: " · ")
    }

    static func decodeSeenWorkIDs(_ raw: String?) -> [Int] {
        guard let raw, !raw.isEmpty else { return [] }
        var seen = Set<Int>()
        var result: [Int] = []
        for token in raw.split(separator: ",") {
            guard let id = Int(token), id > 0, seen.insert(id).inserted else { continue }
            result.append(id)
            if result.count >= seenIDRetentionLimit { break }
        }
        return result
    }

    static func encodeSeenWorkIDs(_ ids: [Int]) -> String? {
        guard !ids.isEmpty else { return nil }
        var seen = Set<Int>()
        var ordered: [String] = []
        for id in ids where id > 0 {
            guard seen.insert(id).inserted else { continue }
            ordered.append(String(id))
            if ordered.count >= seenIDRetentionLimit { break }
        }
        return ordered.isEmpty ? nil : ordered.joined(separator: ",")
    }
}

/// Pure helpers and SwiftData persistence operations for `FollowedTag`.
enum FollowedTagStore {
    enum FollowError: LocalizedError, Equatable {
        case limitReached(Int)
        case invalidTag

        var errorDescription: String? {
            switch self {
            case let .limitReached(limit):
                "You can follow up to \(limit) tags at a time. Unfollow one to add another."
            case .invalidTag:
                "This tag does not provide an AO3 Atom feed."
            }
        }
    }

    /// True if already followed (editing) or strictly below the cap of 20.
    nonisolated static func canFollow(existingCount: Int, isAlreadyFollowed: Bool) -> Bool {
        isAlreadyFollowed || existingCount < FollowedTag.maxFollowedCount
    }

    /// Pure limit check over fetched tags.
    static func canFollow(existing: [FollowedTag], ao3TagID: Int) -> Bool {
        let alreadyFollowed = existing.contains { $0.ao3TagID == ao3TagID }
        return canFollow(existingCount: existing.count, isAlreadyFollowed: alreadyFollowed)
    }

    @MainActor
    @discardableResult
    // swiftlint:disable:next function_parameter_count
    static func followOrUpdate(
        ao3TagID: Int,
        name: String,
        tagCategoryRaw: String?,
        tagURLString: String?,
        showOnHome: Bool,
        completeOnly: Bool,
        hideExplicit: Bool,
        in context: ModelContext,
        now: Date = Date()
    ) throws -> FollowedTag {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ao3TagID > 0, !trimmedName.isEmpty else { throw FollowError.invalidTag }

        let all = (try? context.fetch(FetchDescriptor<FollowedTag>())) ?? []
        if let existing = all.first(where: { $0.ao3TagID == ao3TagID }) {
            existing.name = trimmedName
            if let tagCategoryRaw, !tagCategoryRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                existing.tagCategoryRaw = tagCategoryRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let tagURLString, !tagURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                existing.tagURLString = tagURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            existing.showOnHome = showOnHome
            existing.completeOnly = completeOnly
            existing.hideExplicit = hideExplicit
            existing.lastModifiedAt = now
            FolderSyncService.markDirty()
            context.saveBestEffort(reason: "Updating followed tag failed")
            return existing
        }

        guard all.count < FollowedTag.maxFollowedCount else {
            throw FollowError.limitReached(FollowedTag.maxFollowedCount)
        }

        let tag = FollowedTag(
            ao3TagID: ao3TagID,
            name: trimmedName,
            tagCategoryRaw: tagCategoryRaw,
            tagURLString: tagURLString,
            showOnHome: showOnHome,
            completeOnly: completeOnly,
            hideExplicit: hideExplicit,
            followedAt: now,
            lastModifiedAt: now
        )
        context.insert(tag)
        FolderSyncService.markDirty()
        context.saveBestEffort(reason: "Following tag failed")
        return tag
    }

    @MainActor
    static func unfollow(
        _ tag: FollowedTag,
        in context: ModelContext,
        updateStore: FollowedTagUpdateStore? = nil
    ) {
        let tagID = tag.ao3TagID
        SyncTombstones.recordDeletion(of: tag, in: context)
        context.delete(tag)
        updateStore?.clearUpdates(forTagID: tagID)
        FolderSyncService.markDirty()
        context.saveBestEffort(reason: "Unfollowing tag failed")
    }
}
