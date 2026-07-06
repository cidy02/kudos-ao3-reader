import Foundation

/// A query-time pairing of the two ways the same AO3 work can reach the UI: a
/// local `SavedWork` record and/or a remote `AO3WorkSummary` (subscription,
/// bookmark, Marked for Later, …). Not a SwiftData model — built per render by
/// `CanonicalWorkMerge` so the same work never shows as two separate cards.
///
/// At least one side is always non-nil. When both are present the local side is
/// the richer one (progress, saved/favorite state, download status), so cards
/// render from it and the remote side just records where the pairing came from.
struct CanonicalWork: Identifiable {
    let local: SavedWork?
    let remote: AO3WorkSummary?

    /// Stable across re-merges: the local record's UUID when one exists (it
    /// survives refreshes), otherwise the AO3 work id.
    var id: String {
        if let local { return "local-\(local.id.uuidString)" }
        if let remote { return "remote-\(remote.id)" }
        return "empty" // unreachable: merge never builds a double-nil entry
    }

    var title: String {
        local?.title ?? remote?.title ?? ""
    }

    var ao3WorkID: Int? {
        local?.ao3WorkID ?? remote?.id
    }

    /// Whether the local side sits in Recently Deleted. The standard list queries
    /// already exclude pending-deletion records, so merged surfaces normally never
    /// see this true — it exists for callers that fetch unfiltered.
    var isLocallyDeleted: Bool {
        local?.isPendingDeletion ?? false
    }
}
