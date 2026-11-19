import Foundation
import SwiftData

/// AO3 canonical tag categories represented by `TagAlias`.
///
/// Mirrors `Tag::USER_DEFINED` in otwarchive (`Fandom`, `Character`, `Relationship`,
/// `Freeform`) using Insights-Data D13 raw identifiers.
nonisolated enum TagAliasKind: String, Codable, CaseIterable, Sendable {
    case fandom
    case relationship
    case character
    case freeform
}

/// Lightweight, value-typed alias pair returned by AO3 response parsers before
/// persistence on `@MainActor`.
nonisolated struct LearnedTagAlias: Equatable, Hashable, Sendable {
    var name: String
    var canonicalName: String
    var kind: TagAliasKind
    var parentFandoms: [String]

    init(
        name: String,
        canonicalName: String,
        kind: TagAliasKind,
        parentFandoms: [String] = []
    ) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.canonicalName = canonicalName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.kind = kind
        self.parentFandoms = Self.normalizedParentFandoms(parentFandoms)
    }

    nonisolated static func normalizedParentFandoms(_ raw: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for entry in raw {
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }
}

/// Pure, sendable query-time join table built from persisted `TagAlias` rows.
///
/// Insights calculations run `nonisolated` over value snapshots; passing a
/// `TagAliasResolver` keeps Insights deterministic and directly unit-testable
/// without requiring a live `ModelContainer`.
///
/// Unlearned names always resolve to themselves (exact string equality only).
nonisolated struct TagAliasResolver: Equatable, Sendable {
    nonisolated struct Entry: Equatable, Hashable, Sendable {
        var name: String
        var canonicalName: String
        var kind: TagAliasKind
        var parentFandoms: [String]

        init(
            name: String,
            canonicalName: String,
            kind: TagAliasKind,
            parentFandoms: [String] = []
        ) {
            self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            self.canonicalName = canonicalName.trimmingCharacters(in: .whitespacesAndNewlines)
            self.kind = kind
            self.parentFandoms = LearnedTagAlias.normalizedParentFandoms(parentFandoms)
        }
    }

    private nonisolated struct LookupKey: Hashable, Sendable {
        var kind: TagAliasKind
        var name: String
    }

    static let empty = TagAliasResolver(entries: [])

    private let canonicalByKey: [LookupKey: String]
    /// Lowercased names, for `resolveIgnoringCase`. AO3 matches tag names
    /// case-insensitively (otwarchive `tags` uses `utf8mb4_unicode_ci`).
    private let canonicalByFoldedKey: [LookupKey: String]
    private let parentsByFandom: [String: Set<String>]

    init(entries: [Entry]) {
        var canonicalMap: [LookupKey: String] = [:]
        var parentMap: [String: Set<String>] = [:]

        for entry in entries {
            guard !entry.name.isEmpty, !entry.canonicalName.isEmpty else { continue }
            if entry.name != entry.canonicalName {
                canonicalMap[LookupKey(kind: entry.kind, name: entry.name)] = entry.canonicalName
            }
            if entry.kind == .fandom, !entry.parentFandoms.isEmpty {
                let normalizedParents = Set(entry.parentFandoms.filter { !$0.isEmpty })
                if !normalizedParents.isEmpty {
                    parentMap[entry.name, default: []].formUnion(normalizedParents)
                    parentMap[entry.canonicalName, default: []].formUnion(normalizedParents)
                }
            }
        }

        self.canonicalByKey = canonicalMap
        var folded: [LookupKey: String] = [:]
        for (key, canonical) in canonicalMap {
            let lower = LookupKey(kind: key.kind, name: key.name.lowercased())
            if folded[lower] == nil { folded[lower] = canonical }
        }
        self.canonicalByFoldedKey = folded
        self.parentsByFandom = parentMap
    }

    init(aliases: [LearnedTagAlias]) {
        self.init(
            entries: aliases.map {
                Entry(
                    name: $0.name,
                    canonicalName: $0.canonicalName,
                    kind: $0.kind,
                    parentFandoms: $0.parentFandoms
                )
            }
        )
    }

    @MainActor
    init(models: [TagAlias]) {
        self.init(
            entries: models.compactMap { model in
                guard !model.isDeleted else { return nil }
                return Entry(
                    name: model.name,
                    canonicalName: model.canonicalName,
                    kind: model.kind,
                    parentFandoms: model.parentFandoms
                )
            }
        )
    }

    var isEmpty: Bool {
        canonicalByKey.isEmpty && parentsByFandom.isEmpty
    }

    /// Resolves `rawName` for `kind` using learned aliases. Unlearned names
    /// return trimmed exact strings without lowercasing or guessing.
    func resolve(_ rawName: String, kind: TagAliasKind) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !canonicalByKey.isEmpty else { return trimmed }

        var current = trimmed
        var visited: Set<String> = [current]
        for _ in 0..<8 {
            guard let next = canonicalByKey[LookupKey(kind: kind, name: current)],
                  !next.isEmpty,
                  visited.insert(next).inserted
            else {
                break
            }
            current = next
        }
        return current
    }

    /// `resolve`, but a name with no exact-case alias tries one with any case,
    /// so "hp" follows a learned "HP" alias. Exact-case aliases win.
    func resolveIgnoringCase(_ rawName: String, kind: TagAliasKind) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let exact = resolve(trimmed, kind: kind)
        guard exact == trimmed,
              let folded = canonicalByFoldedKey[LookupKey(kind: kind, name: trimmed.lowercased())]
        else { return exact }
        return resolve(folded, kind: kind)
    }

    /// Resolves and deduplicates an ordered list of tag names for `kind`,
    /// preserving first-seen canonical order.
    func resolvedUnique(_ rawNames: [String], kind: TagAliasKind) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for raw in rawNames {
            let resolved = resolve(raw, kind: kind)
            guard !resolved.isEmpty, seen.insert(resolved).inserted else { continue }
            result.append(resolved)
        }
        return result
    }

    /// Learned canonical parent/umbrella fandoms for `fandomName` (e.g., an
    /// adaptation canon linked to its umbrella media-type tag).
    func resolvedParentFandoms(for fandomName: String) -> Set<String> {
        let trimmed = fandomName.trimmingCharacters(in: .whitespacesAndNewlines)
        let canonical = resolve(trimmed, kind: .fandom)
        var rawParents: Set<String> = parentsByFandom[trimmed] ?? []
        rawParents.formUnion(parentsByFandom[canonical] ?? [])

        var resolved: Set<String> = []
        for parent in rawParents {
            let resolvedParent = resolve(parent, kind: .fandom)
            if !resolvedParent.isEmpty, resolvedParent != canonical {
                resolved.insert(resolvedParent)
            }
        }
        return resolved
    }

    /// Counts distinct canons represented by `rawFandoms`, collapsing exact
    /// aliases, learned parent/umbrella fandoms, and optional bare-title
    /// equivalents when no parent relationship has been learned yet.
    func distinctCanonFandomCount(
        for rawFandoms: [String],
        bareTitle: ((String) -> String)? = nil
    ) -> Int {
        let resolvedFandoms = resolvedUnique(rawFandoms, kind: .fandom)
        guard resolvedFandoms.count > 1 else { return resolvedFandoms.count }

        // Drop umbrella tags when a more specific child canon in the same work
        // already names that umbrella via `parentFandoms`.
        var absorbedUmbrellas: Set<String> = []
        for fandom in resolvedFandoms {
            let parents = resolvedParentFandoms(for: fandom)
            for candidate in resolvedFandoms where candidate != fandom {
                if parents.contains(candidate) {
                    absorbedUmbrellas.insert(candidate)
                }
            }
        }

        let remaining = resolvedFandoms.filter { !absorbedUmbrellas.contains($0) }
        guard remaining.count > 1, let bareTitle else {
            return remaining.count
        }

        // Fallback for unlearned canon+umbrella pairs sharing a bare title
        // (e.g. "Fandom (Movies)" and "Fandom - All Media Types").
        var collapsedKeys: Set<String> = []
        for fandom in remaining {
            let title = bareTitle(fandom).trimmingCharacters(in: .whitespacesAndNewlines)
            collapsedKeys.insert(title.isEmpty ? fandom : title)
        }
        return collapsedKeys.count
    }

    /// Returns `true` when `rawFandoms` span two or more distinct canons.
    func isCrossover(
        _ rawFandoms: [String],
        bareTitle: ((String) -> String)? = nil
    ) -> Bool {
        distinctCanonFandomCount(for: rawFandoms, bareTitle: bareTitle) > 1
    }
}

/// Canonical AO3 tag alias learned passively from AO3 redirect responses.
///
/// Never triggers network requests on its own. Used by Insights at query time
/// to unify counts for tag synonyms without rewriting stored `SavedWork` or
/// `ReadingSession` snapshots.
@Model
final class TagAlias {
    typealias Kind = TagAliasKind

    /// Stable UUID used for cross-device backup and tombstone tracking.
    var id: UUID = UUID()

    /// The tag name as requested or encountered before canonical resolution.
    var name: String = ""

    /// The canonical tag name AO3 redirected to.
    var canonicalName: String = ""

    /// Raw `TagAliasKind` value (`fandom`, `relationship`, `character`, `freeform`).
    var kindRaw: String = TagAliasKind.freeform.rawValue

    /// Optional canonical parent/umbrella fandom names (used to avoid counting
    /// a canon + its umbrella tag as a crossover).
    var parentFandoms: [String] = []

    /// Timestamp when this alias was last observed or refreshed.
    var learnedAt: Date = Date()

    /// Sync modification timestamp for deterministic merge resolution.
    var lastModifiedAt: Date = Date()

    var kind: TagAliasKind {
        get { TagAliasKind(rawValue: kindRaw) ?? .freeform }
        set { kindRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        canonicalName: String,
        kind: TagAliasKind,
        parentFandoms: [String] = [],
        learnedAt: Date = Date(),
        lastModifiedAt: Date? = nil
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.canonicalName = canonicalName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.kindRaw = kind.rawValue
        self.parentFandoms = LearnedTagAlias.normalizedParentFandoms(parentFandoms)
        self.learnedAt = learnedAt
        self.lastModifiedAt = lastModifiedAt ?? learnedAt
    }

    /// Composite natural key (`kind|name`) enforcing per-(name, kind) uniqueness.
    static func normalizedKey(name: String, kind: TagAliasKind) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(kind.rawValue)|\(trimmed)"
    }
}

/// Persistence helpers for `TagAlias` uniqueness, tombstones, and query-time
/// resolver construction.
@MainActor
enum TagAliasStore {
    /// Builds a `TagAliasResolver` from all persisted aliases in `context`.
    static func resolver(in context: ModelContext) -> TagAliasResolver {
        let aliases = (try? context.fetch(FetchDescriptor<TagAlias>())) ?? []
        return TagAliasResolver(models: aliases)
    }

    /// Inserts or updates a learned alias on `(name, kind)`, keeping one row
    /// and updating `learnedAt`, `canonicalName`, `parentFandoms`, and `lastModifiedAt`.
    ///
    /// Self-aliases (`name == canonicalName`) and empty names are ignored.
    @discardableResult
    static func upsert(
        _ learned: LearnedTagAlias,
        in context: ModelContext,
        now: Date = Date()
    ) -> TagAlias? {
        upsert(
            name: learned.name,
            canonicalName: learned.canonicalName,
            kind: learned.kind,
            parentFandoms: learned.parentFandoms,
            in: context,
            now: now
        )
    }

    /// Inserts or updates a learned alias on `(name, kind)`, keeping one row
    /// and updating `learnedAt`, `canonicalName`, `parentFandoms`, and `lastModifiedAt`.
    ///
    /// Self-aliases (`name == canonicalName`) and empty names are ignored.
    @discardableResult
    static func upsert(
        name rawName: String,
        canonicalName rawCanonicalName: String,
        kind: TagAliasKind,
        parentFandoms rawParentFandoms: [String] = [],
        in context: ModelContext,
        now: Date = Date()
    ) -> TagAlias? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let canonicalName = rawCanonicalName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !canonicalName.isEmpty, name != canonicalName else {
            return nil
        }
        let normalizedParents = LearnedTagAlias.normalizedParentFandoms(rawParentFandoms)

        let targetKindRaw = kind.rawValue
        let descriptor = FetchDescriptor<TagAlias>(
            predicate: #Predicate {
                $0.kindRaw == targetKindRaw && $0.name == name
            }
        )
        let matches = (try? context.fetch(descriptor))?.filter { !$0.isDeleted } ?? []

        let row: TagAlias
        if let existing = matches.first {
            existing.canonicalName = canonicalName
            if !normalizedParents.isEmpty {
                existing.parentFandoms = LearnedTagAlias.normalizedParentFandoms(
                    existing.parentFandoms + normalizedParents
                )
            }
            existing.learnedAt = now
            existing.lastModifiedAt = now
            // Deduplicate any pre-existing duplicate rows from cloud/sync races.
            for duplicate in matches.dropFirst() {
                existing.parentFandoms = LearnedTagAlias.normalizedParentFandoms(
                    existing.parentFandoms + duplicate.parentFandoms
                )
                context.delete(duplicate)
            }
            row = existing
        } else {
            let created = TagAlias(
                name: name,
                canonicalName: canonicalName,
                kind: kind,
                parentFandoms: normalizedParents,
                learnedAt: now,
                lastModifiedAt: now
            )
            context.insert(created)
            row = created
        }

        try? context.save()
        FolderSyncService.markDirty()
        return row
    }

    /// Deletes `alias`, records its `.tagAlias` sync tombstone first, and marks sync dirty.
    static func delete(_ alias: TagAlias, in context: ModelContext) {
        guard !alias.isDeleted else { return }
        SyncTombstones.recordDeletion(of: alias, in: context)
        context.delete(alias)
        try? context.save()
        FolderSyncService.markDirty()
    }
}
