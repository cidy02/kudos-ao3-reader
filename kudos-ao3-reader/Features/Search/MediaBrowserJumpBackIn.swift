import Foundation

/// Jump Back In's ranking, kept apart from the view so it stays pure and testable.
extension MediaBrowserView {
    /// A fandom page opened from Browse: its raw AO3 name and when
    /// (`FandomReadWatermark.lastVisitedAt`).
    nonisolated struct FandomVisit: Sendable {
        let fandom: String
        let at: Date
    }

    /// Jump Back In, ranked across every category (1g.6): each fandom's latest
    /// visit or read, newest first (owner, 2026-10-01: "ordered by which fandom
    /// you have most recently visited"), the first `limit` that belong to a
    /// category, in the library's own spelling when it has one. `categoryFor`
    /// and `workCountFor` take a lowercased name. Pure, so the order can be
    /// tested without a catalog.
    nonisolated static func jumpBackInFandoms(
        works: [LibraryWorkSnapshot],
        visits: [FandomVisit] = [],
        categoryFor: (String) -> String?,
        workCountFor: (String) -> Int?,
        limit: Int
    ) -> [JumpBackInPick] {
        struct Seen {
            let display: String
            let at: Date
            let order: Int
            let isFavorite: Bool
        }
        var latest: [String: Seen] = [:]
        var order = 0
        for work in works.filter(\.hasBeenRead).sorted(by: { $0.recency > $1.recency }) {
            for index in work.fandomsLower.indices {
                let lower = work.fandomsLower[index]
                if let known = latest[lower] {
                    if work.isFavorite && !known.isFavorite {
                        latest[lower] = Seen(display: known.display, at: known.at, order: known.order, isFavorite: true)
                    }
                } else {
                    latest[lower] = Seen(
                        display: work.fandomsDisplay[index],
                        at: work.recency,
                        order: order,
                        isFavorite: work.isFavorite
                    )
                    order += 1
                }
            }
        }
        for visit in visits {
            let lower = visit.fandom.lowercased()
            if let known = latest[lower] {
                if visit.at > known.at {
                    latest[lower] = Seen(display: known.display, at: visit.at, order: known.order, isFavorite: known.isFavorite)
                }
            } else {
                latest[lower] = Seen(display: visit.fandom, at: visit.at, order: order, isFavorite: false)
                order += 1
            }
        }
        let ranked = latest.sorted { lhs, rhs in
            lhs.value.at != rhs.value.at ? lhs.value.at > rhs.value.at : lhs.value.order < rhs.value.order
        }
        var picks: [JumpBackInPick] = []
        for (lower, entry) in ranked {
            guard let categoryID = categoryFor(lower) else { continue }
            picks.append(JumpBackInPick(
                fandom: entry.display,
                categoryID: categoryID,
                workCount: workCountFor(lower),
                isFavorite: entry.isFavorite,
                lastVisitedAt: entry.at
            ))
            if picks.count == limit { break }
        }
        return picks
    }
}
