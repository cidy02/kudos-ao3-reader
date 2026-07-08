import SwiftData

/// Shared bulk-action resolution for every remote-work selection surface (Browse's
/// FandomWorksView/TagWorksView, Search results) — one place for "resolve each
/// selected AO3WorkSummary to a local work, sequentially, never bursting concurrent
/// requests, one failure doesn't sink the whole batch but is honestly reported."

/// Resolves each selected summary to a local work one at a time, then hands the
/// resolved works to `perform`. Returns a user-facing error message if any resolution
/// failed (nil on full success or on cancellation, which the caller should treat as a
/// silent abandon rather than an error).
@MainActor
func resolveSelectedRemoteWorks(
    _ selected: [AO3WorkSummary],
    in context: ModelContext,
    perform: ([SavedWork]) async -> Void
) async -> String? {
    var resolved: [SavedWork] = []
    var failureCount = 0
    for summary in selected {
        do {
            resolved.append(try await ReadingQueueService.resolveLocalWork(for: summary, in: context))
        } catch is CancellationError {
            return nil
        } catch {
            failureCount += 1
        }
    }
    let errorMessage: String? = failureCount > 0
        ? (failureCount == selected.count
            ? "Couldn't save any of the selected works. Check your connection and try again."
            : "\(failureCount) of \(selected.count) selected works couldn't be saved and were skipped.")
        : nil
    // Don't hand an empty list to `perform` — for the Add to Collection/Queue sheets,
    // presenting with zero works would otherwise show every row as a false checkmark
    // (an empty selection vacuously satisfies "all works are members").
    guard !resolved.isEmpty else { return errorMessage }
    await perform(resolved)
    return errorMessage
}

/// Save for Later goes straight through the service (it downloads/creates the local
/// work itself), not via `resolveSelectedRemoteWorks`.
@MainActor
func bulkSaveForLaterRemote(_ selected: [AO3WorkSummary], in context: ModelContext) async -> String? {
    var failureCount = 0
    for summary in selected {
        do {
            _ = try await ReadingQueueService.addToSavedForLater(summary, in: context)
        } catch is CancellationError {
            return nil
        } catch {
            failureCount += 1
        }
    }
    guard failureCount > 0 else { return nil }
    return failureCount == selected.count
        ? "Couldn't save any of the selected works for later. Check your connection and try again."
        : "\(failureCount) of \(selected.count) selected works couldn't be saved for later and were skipped."
}
