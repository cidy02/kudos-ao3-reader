import Foundation

/// Refine on the Subscriptions list (1p.6).
///
/// AO3's subscriptions index lists only title, id and author
/// (`AO3WorkSummary.subscription`); the rest of each row arrives later, from its
/// work page (`AO3SubscriptionsPageEnrichment`). A rating, fandom, completion or
/// language facet applied to the bare row fails it for want of data, so the list
/// read "No works on this page match" and the panel "0 of 25", before anything
/// was known about the works at all.
///
/// So each row is judged on what is known of it: its work-page summary once
/// fetched, the index row until then. A row still index-only stays, because a
/// facet cannot yet say no; it is judged when its summary lands. The rows
/// returned are the index rows themselves, so the list draws exactly what it drew
/// before and only the choice of rows changes.
enum AO3SubscriptionsRefine {
    static func visible(
        works: [AO3WorkSummary],
        enriched: [Int: AO3WorkSummary],
        filters: AO3SearchFilters
    ) -> [AO3WorkSummary] {
        works.filter { row in
            let known = enriched[row.id] ?? row
            return isIndexOnly(known) || filters.matchesSummary(known)
        }
    }

    /// Nothing but the index's title, id and author: no rating and no fandom,
    /// which every work page carries.
    static func isIndexOnly(_ work: AO3WorkSummary) -> Bool {
        work.rating.isEmpty && work.fandoms.isEmpty
    }
}
