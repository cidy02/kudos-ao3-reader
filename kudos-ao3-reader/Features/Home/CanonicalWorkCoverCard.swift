import SwiftUI

/// A carousel cover card for a `CanonicalWork`: the richer local card when a local
/// record exists (reading progress, saved/favorite state, the local context menu,
/// straight-to-reader navigation), the remote AO3 card otherwise. The host's
/// navigation stack must register `LocalWorkDestination` and `AO3WorkSummary`
/// destinations — every current host (Home, Library) already does.
struct CanonicalWorkCoverCard: View {
    let entry: CanonicalWork

    var body: some View {
        if let work = entry.local {
            NavigationLink(value: LocalWorkDestination.reader(work)) {
                // readingProgress is nil until there's something meaningful to show,
                // so a freshly-saved work keeps the clean cover.
                SensitiveWorkCoverCard(work: work, progress: work.readingProgress)
            }
            .buttonStyle(.plain)
            .localWorkContextMenu(work: work)
        } else if let remote = entry.remote {
            // AO3WorkCoverCard applies the remote context menu itself.
            EnrichingAO3WorkCoverCard(work: remote)
        }
    }
}

/// Fills a remote work's cover card in when its listing was sparse — same
/// mechanism, same reasoning as `AO3AccountWorksList`'s `EnrichingAO3WorkRow`.
/// Subscriptions is the sparse source this exists for: AO3's subscriptions page
/// lists only title, id and author, so a card built straight off that listing
/// would otherwise carry no tags, no stats and no completion chip while every
/// other card in the app shows all three. `AO3SparseWorkEnricher.enrich` no-ops
/// immediately for an already-complete summary, so this is safe to use for every
/// remote cover card, not just ones known to come from Subscriptions — shared by
/// `CanonicalWorkCoverCard` (Home) and `AccountWorksCompactGrid` (Account/
/// Bookmarks' compact grid, including "My Subscriptions" itself).
///
/// The enriched summary (once fetched) is what gets pushed on tap too, so opening
/// the work doesn't cost Work Details a second fetch for data this card already has.
struct EnrichingAO3WorkCoverCard: View {
    let work: AO3WorkSummary

    @State private var enriched: AO3WorkSummary?

    private var displayed: AO3WorkSummary { enriched ?? work }

    var body: some View {
        NavigationLink(value: WorkCardTap.destination(for: displayed)) {
            AO3WorkCoverCard(work: displayed)
        }
        .buttonStyle(.plain)
        .task(id: work.id) {
            enriched = await AO3SparseWorkEnricher.shared.enrich(work)
        }
    }
}
