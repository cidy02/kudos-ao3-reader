import Foundation

/// De-duplicates remote AO3 lists against the local library, so the same AO3 work
/// never renders as two separate cards (once local, once remote) on any surface.
/// Identity comes from the shared `WorkIdentityIndex` (AO3 work ID → canonical URL).
@MainActor
enum CanonicalWorkMerge {
    /// For remote-defined lists (Subscriptions, Bookmarks, History, My Works,
    /// collection pages): every remote entry, in the remote list's own order —
    /// AO3's ordering is the source of truth there — with matched entries carrying
    /// their local record so the surface can render the richer local card. Works
    /// that are only local are deliberately absent: not being in the remote list
    /// means not being part of it.
    static func remoteLed(remote: [AO3WorkSummary], localLibrary: [SavedWork]) -> [CanonicalWork] {
        let index = WorkIdentityIndex(localLibrary)
        var pairedLocalIDs = Set<UUID>()
        return remote.map { summary in
            // A remote list can mention the same work twice (e.g. re-listed while
            // paginating); only the first mention keeps the local pairing, so two
            // entries never share one local record (and one stable ForEach id).
            guard let match = index.existingWork(for: summary),
                  pairedLocalIDs.insert(match.id).inserted else {
                return CanonicalWork(local: nil, remote: summary)
            }
            return CanonicalWork(local: match, remote: summary)
        }
    }

    /// For hybrid sections that render local works themselves and append a remote
    /// list after (Library's Saved for Later): the remote entries whose work has no
    /// local record anywhere in the library. A matched work already renders as its
    /// single, richer local card — wherever that card lives — so its remote twin
    /// drops out entirely.
    static func remoteOnly(remote: [AO3WorkSummary], localLibrary: [SavedWork]) -> [AO3WorkSummary] {
        let index = WorkIdentityIndex(localLibrary)
        return remote.filter { index.existingWork(for: $0) == nil }
    }
}
