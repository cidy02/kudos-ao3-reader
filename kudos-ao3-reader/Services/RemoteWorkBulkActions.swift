import Foundation
import os
import SwiftData

/// Shared bulk-action resolution for every remote-work selection surface (Browse's
/// FandomWorksView/TagWorksView, Search results) — one place for "resolve each
/// selected AO3WorkSummary to a local work, sequentially, never bursting concurrent
/// requests, one failure doesn't sink the whole batch but is honestly reported."

/// How far to localize each selected remote summary before running the bulk action.
enum RemoteWorkResolveMode {
    /// Metadata row only — instant, no EPUB download. Used for Queue/Collection
    /// pickers and flag flips so sheets open without waiting on the network.
    case metadataOnly
    /// Full EPUB import when no local match exists (legacy "must be on disk" path).
    case withEPUB
}

/// Resolves each selected summary to a local work one at a time, then hands the
/// resolved works to `perform`. Returns a user-facing error message if any resolution
/// failed (nil on full success or on cancellation, which the caller should treat as a
/// silent abandon rather than an error).
@MainActor
func resolveSelectedRemoteWorks(
    _ selected: [AO3WorkSummary],
    in context: ModelContext,
    mode: RemoteWorkResolveMode = .metadataOnly,
    origin: ReadingQueueMembershipOrigin? = nil,
    perform: ([SavedWork]) async -> Void
) async -> String? {
    let importBatch: WorkIdentityBatch? = switch mode {
    case .metadataOnly: nil
    case .withEPUB: WorkIdentityBatch(in: context)
    }
    defer { importBatch?.stopTrackingChanges() }
    var resolved: [SavedWork] = []
    var failureCount = 0
    for summary in selected {
        do {
            switch mode {
            case .metadataOnly:
                resolved.append(try ReadingQueueService.ensureLocalMetadata(
                    for: summary, importSource: WorkImportSource(origin: origin), origin: origin, in: context
                ))
            case .withEPUB:
                resolved.append(try await ReadingQueueService.resolveLocalWork(
                    for: summary, importSource: WorkImportSource(origin: origin), origin: origin,
                    using: importBatch, in: context
                ))
            }
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
func bulkSaveForLaterRemote(
    _ selected: [AO3WorkSummary],
    origin: ReadingQueueMembershipOrigin? = nil,
    in context: ModelContext,
    downloadEPUB: ((Int) async throws -> URL)? = nil
) async -> String? {
    let batch = RemoteSaveForLaterBatch(in: context)
    defer { batch.stopTrackingChanges() }
    var failureCount = 0
    for summary in selected {
        do {
            _ = try await ReadingQueueService.addToSavedForLater(
                summary,
                state: .new,
                origin: origin,
                in: context,
                downloadEPUB: downloadEPUB,
                using: batch
            )
        } catch is CancellationError {
            return nil
        } catch {
            batch.identity.invalidate()
            failureCount += 1
        }
    }
    guard failureCount > 0 else { return nil }
    return failureCount == selected.count
        ? "Couldn't add any of the selected works to Want to Read. Check your connection and try again."
        : "\(failureCount) of \(selected.count) selected works couldn't be added to Want to Read and were skipped."
}

/// Reuses the normalized queue and its append position between downloads.
/// A queue edit interleaved at an await invalidates both before the next add.
@MainActor
final class RemoteSaveForLaterBatch {
    let identity: WorkIdentityBatch
    private let context: ModelContext
    private var queue: ReadingQueue?
    private var nextOrder = 0
    private var adding = false
    private var observers: [any NSObjectProtocol] = []
    private let externalSave = OSAllocatedUnfairLock(initialState: false)

    init(in context: ModelContext) {
        self.context = context
        identity = WorkIdentityBatch(in: context)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: ModelContext.willSave, object: context, queue: nil) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.invalidateForQueueChanges() }
        })
        let contextID = ObjectIdentifier(context)
        let invalidation = externalSave
        let entities: Set<String> = [
            Schema.entityName(for: ReadingQueue.self), Schema.entityName(for: ReadingQueueMembership.self)
        ]
        observers.append(center.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { notice in
            guard let sender = notice.object, ObjectIdentifier(sender as AnyObject) != contextID else { return }
            if WorkIdentityBatch.save(notice, affects: entities) {
                invalidation.withLock { $0 = true }
            }
        })
    }

    func stopTrackingChanges() {
        identity.stopTrackingChanges()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
    }

    func add(_ work: SavedWork, state: ReadingQueueMembershipState, origin: ReadingQueueMembershipOrigin?) throws {
        invalidateForQueueChanges()
        let externallyChanged = externalSave.withLock { dirty in
            let wasDirty = dirty
            dirty = false
            return wasDirty
        }
        adding = true
        defer { adding = false }
        let target: ReadingQueue
        if let queue, !externallyChanged {
            target = queue
        } else {
            target = ReadingQueueService.ensureSavedForLaterQueue(in: context)
            queue = target
            nextOrder = ReadingQueueService.nextMembershipSortOrder(in: target)
        }
        let membership = ReadingQueueService.add(
            work, to: target, state: state, origin: origin, sortOrder: nextOrder, in: context
        )
        if membership.sortOrderInQueue == nextOrder { nextOrder += 1 }
        do {
            try context.save()
        } catch {
            queue = nil
            throw error
        }
    }

    private func invalidateForQueueChanges() {
        guard !adding, queue != nil else { return }
        let changed = context.insertedModelsArray + context.changedModelsArray + context.deletedModelsArray
        if changed.contains(where: { $0 is ReadingQueue || $0 is ReadingQueueMembership }) { queue = nil }
    }
}
