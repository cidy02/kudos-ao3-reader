import Foundation

/// Editor tag autocomplete (1bp / 1bu). Wraps the existing
/// `AO3Client.autocompleteTags` / `autocompleteURL` — no second URL builder.
///
/// Callers may invoke this after their own 300ms debounce; this API also
/// waits `debounceNanoseconds` so a per-keystroke call site does not fan out
/// a request on every character. The actual fetch is gated on
/// `AO3RequestCoordinator.withSlot`.
///
/// Autocomplete is suggestion, not a whitelist. Free-typed names still POST.
enum AO3TagAutocomplete {
    /// Matches search's `TagSelectField` (300ms).
    static let debounceMilliseconds: UInt64 = 300

    /// Maps AO3's autocomplete names onto editor tags. Live JSON is
    /// `[{"id": name, "name": name}]` with no canonical/count fields, so
    /// suggestions are `isCanonical: true`. Extra keys are parsed when present.
    static func editorTags(fromCanonicalNames names: [String]) -> [AO3EditorTag] {
        names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { AO3EditorTag(name: $0, isCanonical: true, workCount: nil) }
    }

    /// Accept a chip. If `name` is in the last suggestion list, keep that
    /// row's canonical/count flags; otherwise it is free-typed and still
    /// allowed (`isCanonical: false`).
    static func accept(name: String, suggestions: [AO3EditorTag]) -> AO3EditorTag {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = suggestions.first(where: {
            $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return match
        }
        return AO3EditorTag(name: trimmed, isCanonical: false, workCount: nil)
    }

    /// Parse AO3 autocomplete JSON. Uses `id`/`name` like
    /// `AO3Client.parseAutocomplete`; optional `canonical` / `work_count` are
    /// honoured when AO3 includes them.
    static func parseEditorAutocomplete(_ data: Data) throws -> [AO3EditorTag] {
        let rows = try JSONDecoder().decode([Row].self, from: data)
        return rows.compactMap { row in
            let name = (row.name ?? row.id ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let canonical = row.canonical ?? row.isCanonical ?? true
            return AO3EditorTag(
                name: name,
                isCanonical: canonical,
                workCount: row.workCount ?? row.count
            )
        }
    }

    /// Per-keystroke suggest. Debounces, then one coordinator-slotted fetch
    /// through the existing autocomplete endpoint.
    static func suggest(
        kind: AO3TagKind,
        term: String,
        debounceNanoseconds: UInt64 = debounceMilliseconds * 1_000_000
    ) async throws -> [AO3EditorTag] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        // Reuses `autocompleteURL`; a blank term already makes no request.
        guard AO3Client.autocompleteURL(kind: kind, term: trimmed) != nil else {
            return []
        }
        if debounceNanoseconds > 0 {
            try await Task.sleep(nanoseconds: debounceNanoseconds)
        }
        try Task.checkCancellation()
        return try await AO3RequestCoordinator.shared.withSlot {
            let names = try await AO3Client.shared.autocompleteTags(
                kind: kind, term: trimmed
            )
            return editorTags(fromCanonicalNames: names)
        }
    }

    private struct Row: Decodable {
        let id: String?
        let name: String?
        let canonical: Bool?
        let isCanonical: Bool?
        let workCount: Int?
        let count: Int?

        enum CodingKeys: String, CodingKey {
            case id, name, canonical, count
            case isCanonical = "is_canonical"
            case workCount = "work_count"
        }
    }
}
