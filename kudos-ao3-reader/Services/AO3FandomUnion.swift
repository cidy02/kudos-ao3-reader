import Foundation

/// A family page asks for works in **any** of its sibling fandoms. AO3 has no
/// "or" over `work_search[fandom_names]` — that field ANDs, so joining the
/// siblings asks for works tagged with every era of Doctor Who at once and
/// returns their intersection.
///
/// The union AO3 does support runs through resolved tag ids in the query field.
/// Verified live on 2026-09-11 against archiveofourown.org:
///
///   `work_search[query]=filter_ids:(27785 OR 99117)`  →  68,057 works
///   Doctor Who (2005) alone 61,248 · (1963) alone 9,958 · both 3,149
///   61,248 + 9,958 − 3,149 = 68,057, exactly.
///
/// and the same search through `fandom_names` returns the 3,149 intersection.
/// The clause also composes with the rest of `searchQuery` — AO3's query field
/// ANDs its clauses — so `filter_ids:(A OR B) -category_ids:23` narrows the
/// union rather than replacing it.
///
/// **An autocomplete `id` is not this id.** `/autocomplete/fandom` answers with
/// `{"id": "Doctor Who (2005)", "name": "Doctor Who (2005)"}` — both fields are
/// the tag's name. The numeric filter id lives on the tag's own works page, in
/// the feed link (`/tags/27785/feed.atom`) and in the filter sidebar's
/// checkboxes. That cost this branch two wrong attempts written from reasoning.
nonisolated enum AO3FandomUnion {
    /// `filter_ids:(A OR B)` for a family, `filter_ids:A` for one tag, nil for none.
    /// Parenthesised even for two ids because the query field's default operator
    /// is AND: without the group, `filter_ids:A OR filter_ids:B` parses as
    /// `filter_ids:A` OR'd with the *rest* of the clause list.
    static func queryClause(filterIDs: [Int]) -> String? {
        let ids = filterIDs.uniqued()
        guard !ids.isEmpty else { return nil }
        guard ids.count > 1 else { return "filter_ids:\(ids[0])" }
        return "filter_ids:(\(ids.map(String.init).joined(separator: " OR ")))"
    }

    /// The numeric filter id from a tag's works page. AO3 prints it in the Atom
    /// feed link; the filter sidebar's `include_work_search[fandom_ids][]`
    /// checkboxes carry the same number for the page's own tag, and are the
    /// fallback when the feed link is absent (a tag with no works has none).
    static func filterID(fromTagWorksPage html: String, tagName: String) -> Int? {
        if let match = html.range(of: #"/tags/(\d+)/feed\.atom"#, options: .regularExpression) {
            let digits = html[match].drop(while: { !$0.isNumber }).prefix(while: \.isNumber)
            return Int(digits)
        }
        return nil
    }
}

private extension Array where Element == Int {
    /// Order-preserving, because the query string is a cache key: the same
    /// family must always produce the same URL.
    func uniqued() -> [Int] {
        var seen = Set<Int>()
        return filter { seen.insert($0).inserted }
    }
}
