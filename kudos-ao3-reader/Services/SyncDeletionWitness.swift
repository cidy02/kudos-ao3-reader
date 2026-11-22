import Foundation
import os

/// Remembers, in memory, that a Folder Sync / backup merge saw a *different* signed deletion of a
/// record than the one this device already held. The merge keeps only the newest tombstone per
/// record, so an older peer deletion leaves no row behind; Sort New's Undo of a Drop asks this
/// instead, and refuses to resurrect anything a peer also deleted. Echoes of this device's own
/// tombstone (same signature) are not recorded.
nonisolated enum SyncDeletionWitness {
    private struct State {
        var generation = 0
        var seen: [String: Int] = [:]
    }
    private static let state = OSAllocatedUnfairLock(initialState: State())

    private static func key(_ recordTypeRaw: String, _ id: UUID) -> String {
        "\(recordTypeRaw)|\(id.uuidString.lowercased())"
    }

    static func record(recordTypeRaw: String, recordID: UUID) {
        state.withLock { state in
            state.generation += 1
            state.seen[key(recordTypeRaw, recordID)] = state.generation
        }
    }

    /// Opaque position; pass it to `seen(…, after:)` later.
    static var mark: Int { state.withLock { $0.generation } }

    static func seen(recordTypeRaw: String, recordID: UUID, after mark: Int) -> Bool {
        state.withLock { ($0.seen[key(recordTypeRaw, recordID)] ?? 0) > mark }
    }
}
