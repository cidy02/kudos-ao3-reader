import Foundation
import SwiftSoup

extension AO3Client {
    /// Extracts the unmunged tag name from a trusted AO3 `/tags/<name>/works`
    /// or `/collections/<collection>/tags/<name>/works` URL.
    ///
    /// Returns `nil` for non-works tag pages (e.g. `/tags/<name>`, which is what
    /// AO3 redirects a non-canonical tag *without* a merger to) or any other path.
    nonisolated static func tagWorksName(from url: URL) -> String? {
        guard AO3RequestDefaults.isTrustedURL(url) else { return nil }
        let encodedPath = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? url.path
        let segments = encodedPath.split(separator: "/", omittingEmptySubsequences: true)
        let rawSegment: Substring
        switch segments.count {
        case 3 where segments[0] == "tags" && segments[2] == "works":
            rawSegment = segments[1]
        case 5 where segments[0] == "collections" && segments[2] == "tags" && segments[4] == "works":
            rawSegment = segments[3]
        default:
            return nil
        }

        let percentDecoded = String(rawSegment).removingPercentEncoding ?? String(rawSegment)
        let tagName = AO3Link.unmungeTag(percentDecoded).trimmingCharacters(in: .whitespacesAndNewlines)
        return tagName.isEmpty ? nil : tagName
    }

    /// Infers a canonical tag alias when a requested tag works URL was served
    /// from a *different* canonical tag's works URL.
    ///
    /// Zero network calls are ever made here; tag kind comes strictly from
    /// `hintKind` (when the caller already knows it, e.g. `fandomWorksPage`) or
    /// the work blurbs / filter sidebar already present in `doc`.
    nonisolated static func learnedTagAlias(
        requestedURL: URL,
        finalURL: URL,
        in doc: Document? = nil,
        facets: AO3SearchFacets = AO3SearchFacets(),
        works: [AO3WorkSummary] = [],
        hintKind: TagAliasKind? = nil
    ) -> LearnedTagAlias? {
        guard let requestedName = tagWorksName(from: requestedURL),
              let canonicalName = tagWorksName(from: finalURL),
              requestedName != canonicalName
        else {
            return nil
        }

        let kind = hintKind ?? inferTagKind(
            requestedName: requestedName,
            canonicalName: canonicalName,
            in: doc,
            facets: facets,
            works: works
        )
        return LearnedTagAlias(name: requestedName, canonicalName: canonicalName, kind: kind)
    }

    private nonisolated static func inferTagKind(
        requestedName: String,
        canonicalName: String,
        in doc: Document?,
        facets: AO3SearchFacets,
        works: [AO3WorkSummary]
    ) -> TagAliasKind {
        let targets: Set<String> = [requestedName, canonicalName]

        // Every work blurb on `/tags/<canonical>/works` places the tag in its
        // category (`h5.fandoms`, `li.relationships`, `li.characters`, `ul.tags`).
        // Synonyms appear in blurbs verbatim as authored while the page URL holds
        // the canonical merger, so matching both names handles every case.
        var blurbVotes: [TagAliasKind: Int] = [:]
        let containsTarget: ([String]) -> Bool = { list in
            list.contains { targets.contains($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        for work in works {
            if containsTarget(work.fandoms) {
                blurbVotes[.fandom, default: 0] += 1
            }
            if containsTarget(work.relationships) {
                blurbVotes[.relationship, default: 0] += 1
            }
            if containsTarget(work.characters) {
                blurbVotes[.character, default: 0] += 1
            }
            if containsTarget(work.tags) {
                blurbVotes[.freeform, default: 0] += 1
            }
        }

        let preferredOrder: [TagAliasKind] = [.fandom, .relationship, .character, .freeform]
        if let best = preferredOrder.max(by: { lhs, rhs in
            let leftCount = blurbVotes[lhs, default: 0]
            let rightCount = blurbVotes[rhs, default: 0]
            if leftCount != rightCount {
                return leftCount < rightCount
            }
            let leftIndex = preferredOrder.firstIndex(of: lhs) ?? 0
            let rightIndex = preferredOrder.firstIndex(of: rhs) ?? 0
            return leftIndex > rightIndex
        }), blurbVotes[best, default: 0] > 0 {
            return best
        }

        if let doc,
           let fandomLabels = try? doc.select("dd#include_fandom_tags li label").array(),
           fandomLabels.contains(where: { label in
               guard let rawText = try? label.text(),
                     let parsed = Self.parseFacetLabel(rawText)
               else { return false }
               return targets.contains(parsed.name)
           }) {
            return .fandom
        }
        if facets.relationships.contains(where: { targets.contains($0.name) }) {
            return .relationship
        }
        if facets.characters.contains(where: { targets.contains($0.name) }) {
            return .character
        }
        if facets.freeforms.contains(where: { targets.contains($0.name) }) {
            return .freeform
        }

        return .freeform
    }
}
