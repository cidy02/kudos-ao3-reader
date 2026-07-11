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
            // readingProgress is nil until there's something meaningful to show,
            // so a freshly-saved work keeps the clean cover.
            SensitiveWorkCoverCard(work: work, progress: work.readingProgress)
                .cardNavigation(
                    to: LocalWorkDestination.reader(work),
                    accessibilityLabel: work.title
                )
                .localWorkContextMenu(work: work)
        } else if let remote = entry.remote {
            // AO3WorkCoverCard applies the remote context menu itself.
            AO3WorkCoverCard(work: remote)
                .cardNavigation(to: remote, accessibilityLabel: remote.title)
        }
    }
}
