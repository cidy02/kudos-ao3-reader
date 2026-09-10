import Foundation
import SwiftUI

/// Sibling tags that share a parsed display title inside one media category.
///
/// Grouping clusters on the parsed title; identity does not. Search, cache keys,
/// works queries and `filter_ids` all stay on the raw original tag names. A family
/// tap therefore sends every sibling's `original` as an included fandom filter,
/// never the parsed title — splitting is not reversible (1,519 tags / 1.6% do not
/// survive a title + qualifier round trip).
nonisolated struct FandomFamily: Identifiable, Hashable, Sendable {
    /// Stable id that is **not** the parsed title. A sorted join of the member
    /// originals, so two unrelated tags that parse to the same title in different
    /// categories cannot collide in a cache keyed by id.
    var id: String
    /// Display only. Clustering inside one `grouped(fandoms:)` call keys on this;
    /// identity, cache and works queries never do.
    var parsedTitle: String
    var members: [Member]
    var summedWorkCount: Int
    /// Cached union from `AO3ResultSummary.total` after the family search has run.
    var exactWorkCount: Int?

    /// The sum double-counts a work tagged with two siblings, so the figure is
    /// approximate until the exact union has been fetched and cached.
    var showsApproximateCount: Bool { exactWorkCount == nil && members.count > 1 }

    var displayedWorkCount: Int { exactWorkCount ?? summedWorkCount }

    /// Raw original tag names, in member order. A family tap includes all of these.
    var includedFilterNames: [String] { members.map(\.originalName) }

    /// Zoom pairing key: a lone tag keeps the raw name the works screen already
    /// uses; a multi-tag family uses the family id so the pair cannot collide
    /// with any one sibling.
    var zoomKey: String { members.count == 1 ? members[0].originalName : id }

    var memberCount: Int { members.count }

    struct Member: Identifiable, Hashable, Sendable {
        var fandom: AO3Fandom
        var displayName: FandomName
        /// Other `|` segments of the multilingual tag, original-first.
        var aliases: [String]
        /// Qualifier with AO3's delimiter stripped, for the nested member row.
        var qualifierDisplay: String
        var workCount: Int
        var isRPF: Bool
        var isAllMediaTypes: Bool
        var isRelatedFandoms: Bool

        var id: String { fandom.name }
        var originalName: String { fandom.name }

        init(fandom: AO3Fandom) {
            self.fandom = fandom
            let aliases = FandomDisplayName.aliasSegments(of: fandom.name)
            let primary = FandomDisplayName.primarySegment(of: fandom.name)
            let split = FandomDisplayName.split(primary)
            // Identity stays on the raw tag. `split` only saw the last `|`
            // segment, which is the display string, not the query payload.
            self.displayName = FandomName(
                original: fandom.name,
                title: split.title,
                parts: split.parts
            )
            self.aliases = aliases
            self.qualifierDisplay = FandomQualifier.displayText(
                parts: split.parts,
                fallback: split.title
            )
            self.workCount = fandom.workCount ?? 0
            let kinds = Set(split.parts.map(\.kind))
            self.isRPF = kinds.contains(.rpf)
            self.isAllMediaTypes = kinds.contains(.allMediaTypes)
            self.isRelatedFandoms = kinds.contains(.relatedFandoms)
        }
    }

    /// Record separator — a character AO3 tag names do not contain — so a join of
    /// originals cannot collide with a single name that happens to contain the
    /// delimiter.
    static let idSeparator = "\u{1E}"

    static func id(originalNames: [String]) -> String {
        originalNames.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .joined(separator: idSeparator)
    }

    init(parsedTitle: String, members: [Member], exactWorkCount: Int? = nil) {
        let ordered = Self.sortedMembers(members)
        self.id = Self.id(originalNames: ordered.map(\.originalName))
        self.parsedTitle = parsedTitle
        self.members = ordered
        self.summedWorkCount = ordered.reduce(0) { $0 + $1.workCount }
        self.exactWorkCount = exactWorkCount
    }

    func applyingExactCount(_ total: Int?) -> FandomFamily {
        var copy = self
        copy.exactWorkCount = total
        return copy
    }

    static func sortedMembers(_ members: [Member]) -> [Member] {
        members.sorted { lhs, rhs in
            if lhs.workCount != rhs.workCount { return lhs.workCount > rhs.workCount }
            let qualifier = lhs.qualifierDisplay.localizedStandardCompare(rhs.qualifierDisplay)
            if qualifier != .orderedSame { return qualifier == .orderedAscending }
            return lhs.originalName.localizedStandardCompare(rhs.originalName) == .orderedAscending
        }
    }
}

// MARK: - Grouping

extension FandomFamily {
    /// Clusters tags that share a parsed display title. The title is a grouping
    /// key for this input only — never stored as `id`, never shared across
    /// category lists. Call once per category, off the main actor.
    static func grouped(fandoms: [AO3Fandom]) -> [FandomFamily] {
        var buckets: [String: [Member]] = [:]
        var seen = Set<String>()
        buckets.reserveCapacity(fandoms.count)
        for fandom in fandoms {
            guard seen.insert(fandom.name).inserted else { continue }
            let member = Member(fandom: fandom)
            buckets[member.displayName.title, default: []].append(member)
        }
        return buckets.map { title, members in
            FandomFamily(parsedTitle: title, members: members)
        }
        .sorted { lhs, rhs in
            let title = lhs.parsedTitle.localizedStandardCompare(rhs.parsedTitle)
            if title != .orderedSame { return title == .orderedAscending }
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
    }
}

// MARK: - Sort / letter groups

nonisolated enum FandomFamilySort: String, CaseIterable, Hashable, Sendable {
    case alphabetical
    case familyTotal

    var title: String {
        switch self {
        case .alphabetical: "A–Z"
        case .familyTotal: "Most works"
        }
    }
}

extension FandomFamily {
    static func sorted(_ families: [FandomFamily], by sort: FandomFamilySort) -> [FandomFamily] {
        switch sort {
        case .alphabetical:
            families.sorted { lhs, rhs in
                let title = lhs.parsedTitle.localizedStandardCompare(rhs.parsedTitle)
                if title != .orderedSame { return title == .orderedAscending }
                return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
            }
        case .familyTotal:
            families.sorted { lhs, rhs in
                if lhs.summedWorkCount != rhs.summedWorkCount {
                    return lhs.summedWorkCount > rhs.summedWorkCount
                }
                let title = lhs.parsedTitle.localizedStandardCompare(rhs.parsedTitle)
                if title != .orderedSame { return title == .orderedAscending }
                return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
            }
        }
    }

    /// First Latin letter of the parsed title, else `#`. Letter groups drop out
    /// when ranking by family total (artboard 1am).
    static func letterGroup(for title: String) -> String {
        guard let first = title.unicodeScalars.first(where: {
            !CharacterSet.whitespacesAndNewlines.contains($0)
        }) else { return "#" }
        let upper = String(first).uppercased()
        if let ascii = upper.unicodeScalars.first,
           (65 ... 90).contains(Int(ascii.value))
        {
            return String(ascii)
        }
        return "#"
    }

    struct LetterSection: Identifiable, Hashable, Sendable {
        var letter: String
        var families: [FandomFamily]
        var id: String { letter }
    }

    /// `families` must already be in A–Z order.
    static func letterSections(_ families: [FandomFamily]) -> [LetterSection] {
        var sections: [LetterSection] = []
        for family in families {
            let letter = letterGroup(for: family.parsedTitle)
            if sections.last?.letter == letter {
                sections[sections.count - 1].families.append(family)
            } else {
                sections.append(LetterSection(letter: letter, families: [family]))
            }
        }
        return sections
    }
}

// MARK: - Qualifier display

extension FandomQualifier {
    /// The qualifier as a member-row label: AO3's delimiter stripped so
    /// "(Anime & Manga)" reads "Anime & Manga" and "- All Media Types" reads
    /// "All Media Types".
    var displayText: String {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("- ") { text = String(text.dropFirst(2)) }
        if text.hasPrefix("& ") { text = String(text.dropFirst(2)) }
        if text.lowercased().hasPrefix("and ") {
            text = String(text.dropFirst(4))
        }
        if (text.hasPrefix("(") && text.hasSuffix(")"))
            || (text.hasPrefix("（") && text.hasSuffix("）"))
        {
            text = String(text.dropFirst().dropLast())
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func displayText(parts: [FandomQualifier], fallback: String) -> String {
        let joined = parts.map(\.displayText).filter { !$0.isEmpty }.joined(separator: " ")
        return joined.isEmpty ? fallback : joined
    }
}

// MARK: - Browse filter options (artboard 1an)

nonisolated struct FandomListFilterOptions: Equatable, Sendable {
    enum MinimumWorks: Int, CaseIterable, Hashable, Sendable {
        case any = 0
        case ten = 10
        case hundred = 100
        case thousand = 1_000

        var title: String {
            switch self {
            case .any: "Any"
            case .ten: "10+"
            case .hundred: "100+"
            case .thousand: "1,000+"
            }
        }
    }

    var minimumWorks: MinimumWorks = .any
    var hideRPF = false
    var hideAllMediaTypes = false
    var hideRelatedFandoms = false
    var favouritedOnly = false
    var downloadsOnly = false
    var multiTagOnly = false

    var hasActiveFilters: Bool {
        minimumWorks != .any
            || hideRPF
            || hideAllMediaTypes
            || hideRelatedFandoms
            || favouritedOnly
            || downloadsOnly
            || multiTagOnly
    }

    var activeFilterCount: Int {
        var count = 0
        if minimumWorks != .any { count += 1 }
        if hideRPF { count += 1 }
        if hideAllMediaTypes { count += 1 }
        if hideRelatedFandoms { count += 1 }
        if favouritedOnly { count += 1 }
        if downloadsOnly { count += 1 }
        if multiTagOnly { count += 1 }
        return count
    }
}

/// Lowercased original tag names present on the reader's favourite / downloaded
/// works. Built on the main actor from `SavedWork`, then passed into the pure
/// filter pass.
nonisolated struct FandomLibraryIndex: Equatable, Sendable {
    var favouriteNamesLowercased: Set<String>
    var downloadNamesLowercased: Set<String>

    static let empty = FandomLibraryIndex(
        favouriteNamesLowercased: [],
        downloadNamesLowercased: []
    )

    func isFavourited(_ originalName: String) -> Bool {
        favouriteNamesLowercased.contains(originalName.lowercased())
    }

    func hasDownload(_ originalName: String) -> Bool {
        downloadNamesLowercased.contains(originalName.lowercased())
    }
}

nonisolated enum FandomFamilyFilters {
    /// Applies member-level hides first, drops empty families, then the
    /// family-level "more than one tag" switch.
    static func apply(
        _ families: [FandomFamily],
        options: FandomListFilterOptions,
        library: FandomLibraryIndex = .empty
    ) -> [FandomFamily] {
        families.compactMap { family in
            let kept = family.members.filter { member in
                matches(member, options: options, library: library)
            }
            guard !kept.isEmpty else { return nil }
            if options.multiTagOnly, kept.count < 2 { return nil }
            let exact = kept.count == family.members.count ? family.exactWorkCount : nil
            return FandomFamily(
                parsedTitle: family.parsedTitle,
                members: kept,
                exactWorkCount: exact
            )
        }
    }

    /// How many rows the given switch would remove from `families`. Tag-kind
    /// and library switches count tags; `multiTagOnly` counts families.
    static func countRemovedBy(
        _ families: [FandomFamily],
        hidingRPF: Bool = false,
        hidingAllMediaTypes: Bool = false,
        hidingRelatedFandoms: Bool = false,
        favouritedOnly: Bool = false,
        downloadsOnly: Bool = false,
        multiTagOnly: Bool = false,
        minimumWorks: FandomListFilterOptions.MinimumWorks = .any,
        library: FandomLibraryIndex = .empty
    ) -> Int {
        let options = FandomListFilterOptions(
            minimumWorks: minimumWorks,
            hideRPF: hidingRPF,
            hideAllMediaTypes: hidingAllMediaTypes,
            hideRelatedFandoms: hidingRelatedFandoms,
            favouritedOnly: favouritedOnly,
            downloadsOnly: downloadsOnly,
            multiTagOnly: multiTagOnly
        )
        if multiTagOnly && !hidingRPF && !hidingAllMediaTypes && !hidingRelatedFandoms
            && !favouritedOnly && !downloadsOnly && minimumWorks == .any
        {
            return families.reduce(0) { $0 + ($1.memberCount < 2 ? 1 : 0) }
        }
        let before = tagCount(in: families)
        let after = tagCount(in: apply(families, options: options, library: library))
        return max(0, before - after)
    }

    static func tagCount(in families: [FandomFamily]) -> Int {
        families.reduce(0) { $0 + $1.memberCount }
    }

    static func familyCount(in families: [FandomFamily]) -> Int {
        families.count
    }

    static func tallies(
        _ families: [FandomFamily],
        library: FandomLibraryIndex = .empty
    ) -> FandomFamilyFilterTallies {
        var rpf = 0
        var allMedia = 0
        var related = 0
        var favourited = 0
        var downloads = 0
        var multi = 0
        var single = 0
        var works: [Int] = []
        works.reserveCapacity(tagCount(in: families))
        for family in families {
            if family.memberCount > 1 { multi += 1 } else { single += 1 }
            for member in family.members {
                if member.isRPF { rpf += 1 }
                if member.isAllMediaTypes { allMedia += 1 }
                if member.isRelatedFandoms { related += 1 }
                if library.isFavourited(member.originalName) { favourited += 1 }
                if library.hasDownload(member.originalName) { downloads += 1 }
                works.append(member.workCount)
            }
        }
        return FandomFamilyFilterTallies(
            rpfTags: rpf,
            allMediaTypesTags: allMedia,
            relatedFandomsTags: related,
            favouritedTags: favourited,
            downloadTags: downloads,
            multiTagFamilies: multi,
            singleTagFamilies: single,
            memberWorkCounts: works
        )
    }

    private static func matches(
        _ member: FandomFamily.Member,
        options: FandomListFilterOptions,
        library: FandomLibraryIndex
    ) -> Bool {
        if member.workCount < options.minimumWorks.rawValue { return false }
        if options.hideRPF, member.isRPF { return false }
        if options.hideAllMediaTypes, member.isAllMediaTypes { return false }
        if options.hideRelatedFandoms, member.isRelatedFandoms { return false }
        if options.favouritedOnly, !library.isFavourited(member.originalName) { return false }
        if options.downloadsOnly, !library.hasDownload(member.originalName) { return false }
        return true
    }
}

nonisolated struct FandomFamilyFilterTallies: Equatable, Sendable {
    var rpfTags: Int
    var allMediaTypesTags: Int
    var relatedFandomsTags: Int
    var favouritedTags: Int
    var downloadTags: Int
    var multiTagFamilies: Int
    var singleTagFamilies: Int
    var memberWorkCounts: [Int]

    func tagsBelowMinimumWorks(_ minimum: FandomListFilterOptions.MinimumWorks) -> Int {
        guard minimum != .any else { return 0 }
        return memberWorkCounts.reduce(0) { $0 + ($1 < minimum.rawValue ? 1 : 0) }
    }
}

// MARK: - Exact union cache

/// Per-launch cache of `AO3ResultSummary.total` for a family search. Keyed by
/// family id (sorted originals), never by parsed title. Once a family has been
/// opened, the list drops the tilde on its figure.
@MainActor
@Observable
final class FandomFamilyExactCountCache {
    static let shared = FandomFamilyExactCountCache()

    /// Matches the 128-entry ceiling `AO3AuthorPageCache` and the Inbox cache
    /// use — the networking policy names that number for both. A category can
    /// hold thousands of families and this lives for the whole process, so
    /// without a bound a long browse grows a dictionary keyed by joined fandom
    /// names and never gives it back.
    static let entryLimit = 128

    private(set) var totals: [String: Int] = [:]
    /// Insertion order, oldest first, so eviction drops the least recently
    /// stored. Deliberately **no TTL**, unlike the caches this borrows its
    /// ceiling from: those hold page HTML that goes stale or is private to a
    /// session, while this holds a work count that is neither. Expiring it
    /// mid-browse would put the tilde back on a figure the reader just resolved,
    /// which is the opposite of what the cache is for.
    private var insertionOrder: [String] = []

    func exactCount(for familyID: String) -> Int? { totals[familyID] }

    func store(_ total: Int, for familyID: String) {
        if totals[familyID] == nil {
            insertionOrder.append(familyID)
        }
        totals[familyID] = total
        while insertionOrder.count > Self.entryLimit {
            let evicted = insertionOrder.removeFirst()
            totals[evicted] = nil
        }
    }
}

// MARK: - Category card work total

/// Sum of per-tag work counts for a media category. Double-counts a work tagged
/// with two fandoms in the category, so the figure is approximate — the same
/// lie as a family's summed total, a level up.
nonisolated enum CategoryWorkTotal {
    struct Result: Equatable, Sendable {
        var workCount: Int
        var isApproximate: Bool
    }

    static func summedTagCounts(_ fandoms: [AO3Fandom]) -> Result {
        Result(
            workCount: fandoms.reduce(0) { $0 + ($1.workCount ?? 0) },
            isApproximate: true
        )
    }
}

// MARK: - Search haystack

extension FandomFamily {
    /// Pre-normalized concatenation so a live filter is a substring pass.
    func searchHaystack() -> String {
        var parts: [String] = [parsedTitle]
        parts.append(contentsOf: members.map(\.originalName))
        parts.append(contentsOf: members.map(\.qualifierDisplay))
        parts.append(contentsOf: members.flatMap(\.aliases))
        return WorkSearchIndex.normalize(parts.joined(separator: " "))
    }
}
