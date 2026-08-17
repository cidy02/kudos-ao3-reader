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

/// Fills a `CanonicalWorkCoverCard`'s remote branch in when its listing was sparse —
/// same mechanism, same reasoning as `AO3AccountWorksList`'s `EnrichingAO3WorkRow`.
/// Subscriptions is this carousel's own sparse source: AO3's subscriptions page
/// lists only title, id and author, so these cards would otherwise carry no tags,
/// no stats and no completion chip while every other Home carousel shows all three.
///
/// The enriched summary (once fetched) is what gets pushed on tap too, so opening
/// the work doesn't cost Work Details a second fetch for data this card already has.
private struct EnrichingAO3WorkCoverCard: View {
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
