import Foundation

/// Facts the collections index actually prints, and which item edits AO3 will
/// store. Both are decisions the views draw from, so a test can call them
/// without a screen.
enum AO3CollectionCardCopy {
    /// "You moderate" only when AO3 marked the blurb `own`. Otherwise the
    /// first maintainer name, then whatever byline text survived parsing.
    static func eyebrow(
        viewerIsOwner: Bool,
        maintainerNames: [String],
        byline: String
    ) -> String {
        if viewerIsOwner { return "You moderate" }
        if let name = maintainerNames.first(where: { !$0.isEmpty }) { return name }
        return byline.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Works, bookmarks, and the flags AO3 prints on the type line. Moderation
    /// is one of those facts. Approval queues and "your works" are not on the
    /// blurb, so this never invents them.
    static func metaFacts(
        worksCount: Int?,
        bookmarksCount: Int?,
        isModerated: Bool,
        isClosed: Bool,
        isUnrevealed: Bool,
        challengeName: String?
    ) -> [String] {
        var parts: [String] = []
        if let worksCount {
            parts.append("\(worksCount) work\(worksCount == 1 ? "" : "s")")
        }
        if let bookmarksCount, bookmarksCount > 0 {
            parts.append("\(bookmarksCount) bookmark\(bookmarksCount == 1 ? "" : "s")")
        }
        if isModerated { parts.append("Moderated") }
        if isClosed { parts.append("Closed") }
        if isUnrevealed { parts.append("Unrevealed") }
        if let challengeName, !challengeName.isEmpty { parts.append(challengeName) }
        return parts
    }
}

enum AO3CollectionItemSubmission {
    /// Rows on this page whose creator or moderators have not decided.
    static func decisionsNeeded(_ items: [AO3CollectionItem]) -> Int {
        items.reduce(into: 0) { count, item in
            let waiting = item.creatorApproval == .unreviewed
                || item.moderatorApproval == .unreviewed
            if waiting { count += 1 }
        }
    }

    /// "1 needs a decision" / "3 need a decision". Nil when nothing is waiting,
    /// so a subtitle does not claim a decision the page does not have.
    static func decisionPhrase(for count: Int) -> String? {
        switch count {
        case ..<1: return nil
        case 1: return "1 needs a decision"
        default: return "\(count) need a decision"
        }
    }

    /// Drops every field the page's controls cannot post. A successful submit
    /// must not clear a change AO3's strong params would ignore.
    static func draftAO3WillStore(
        _ draft: AO3CollectionItemDraft,
        item: AO3CollectionItem
    ) -> AO3CollectionItemDraft {
        var copy = draft
        if !item.creatorApprovalIsEditable { copy.creatorApproval = nil }
        if !item.moderatorApprovalIsEditable { copy.moderatorApproval = nil }
        if !item.unrevealedIsEditable { copy.isUnrevealed = nil }
        if !item.anonymousIsEditable { copy.isAnonymous = nil }
        if !item.removeIsEditable { copy.remove = false }
        return copy
    }

    static func isSubmittable(_ draft: AO3CollectionItemDraft) -> Bool {
        if draft.remove { return true }
        if draft.creatorApproval != nil { return true }
        if draft.moderatorApproval != nil { return true }
        if draft.isUnrevealed != nil { return true }
        if draft.isAnonymous != nil { return true }
        return false
    }
}
