import Foundation
import SwiftData

/// Records the reader's own AO3 actions on the saved work (Insights D11): a bookmark, a
/// comment, kudos. It only reads what the app already did or already fetched: no request,
/// no write to AO3.
///
/// The models that perform AO3 writes (`AO3WorkActionsModel`, `CommentsModel`) hold no store, so
/// the app root installs one context here; with none installed (tests, previews) a call
/// records nothing. A work Kudos does not hold is skipped: these are facts about a saved copy.
@MainActor
enum OwnAO3ActionLog {
    private static var context: ModelContext?

    static func install(_ context: ModelContext?) {
        self.context = context
    }

    /// Returns whether a saved work was changed. `context` is the test seam; otherwise the
    /// installed one is used.
    @discardableResult
    static func record(
        _ action: OwnAO3Action,
        ao3WorkID: Int,
        at date: Date = Date(),
        in context: ModelContext? = nil
    ) -> Bool {
        apply(ao3WorkID: ao3WorkID, in: context) { $0.recordOwnAction(action, at: date) }
    }

    /// A bookmark visible on a work page the app fetched for another reason.
    @discardableResult
    static func recordSeenBookmark(
        isPrivate: Bool,
        ao3WorkID: Int,
        at date: Date = Date(),
        in context: ModelContext? = nil
    ) -> Bool {
        apply(ao3WorkID: ao3WorkID, in: context) { $0.recordSeenBookmark(isPrivate: isPrivate, at: date) }
    }

    private static func apply(
        ao3WorkID: Int,
        in explicit: ModelContext?,
        _ change: (SavedWork) -> Bool
    ) -> Bool {
        guard let context = explicit ?? self.context else { return false }
        let target = ao3WorkID
        let matches = (try? context.fetch(FetchDescriptor<SavedWork>(
            predicate: #Predicate { $0.ao3WorkID == target && !$0.isPendingDeletion }
        ))) ?? []
        var changed = false
        for work in matches where change(work) {
            work.markModified()
            changed = true
        }
        if changed {
            context.saveBestEffort(reason: "Saving an AO3 action failed")
            FolderSyncService.markDirty()
        }
        return changed
    }
}
