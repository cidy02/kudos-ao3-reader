import Foundation

/// What a queue's "Keep downloaded" and a collection's "Keep downloads" do (T-276,
/// docs/REDESIGN_DECISIONS.md "Library, queues, history").
///
/// ON: the container's works keep their EPUBs — exempt from freeing
/// (`SavedWork.isProtected`) — and missing ones are fetched when the reader turns
/// it on or adds a work, through the existing paced paths (`ReadingQueueService.preserve`
/// for queues, `DownloadQueue` for collections). No polling, no timers.
/// OFF: a plain list that does not count against storage.
nonisolated enum KeepOffline {
    /// A queue nobody has asked about (`nil`, every queue from before the toggle)
    /// keeps what queues always did: its works stay downloaded.
    static func queueKeeps(_ value: Bool?) -> Bool { value != false }

    /// A collection keeps only when the reader turned it on.
    static func collectionKeeps(_ value: Bool?) -> Bool { value == true }

    /// What a Keep-downloads collection fetches: its AO3 works whose EPUB is
    /// missing, not in Recently Deleted. `DownloadQueue` skips any it finds
    /// already downloaded and fills in the rest (`downloadOverMissingEPUB`).
    @MainActor
    static func downloadItems(for works: [SavedWork]) -> [DownloadQueue.Item] {
        works.compactMap { work in
            guard !work.hasEPUB, !work.isPendingDeletion,
                  let url = URL(string: work.sourceURL),
                  let id = work.ao3WorkID ?? WorkTags.ao3WorkID(from: work.sourceURL)
            else { return nil }
            return DownloadQueue.Item(
                id: id, title: work.title, sourceURL: url,
                isComplete: work.isComplete, seriesURL: ""
            )
        }
    }
}
