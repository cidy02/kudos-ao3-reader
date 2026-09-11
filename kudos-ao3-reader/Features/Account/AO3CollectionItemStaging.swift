import Foundation

/// Artboard **1s**'s staging: what the reader has changed but not yet sent.
///
/// The spec is explicit that *"changes stage rather than apply: the toolbar counts
/// them and the checkmark submits."* That is the right shape for this screen —
/// AO3 takes the whole items form in one POST, and four settings across a dozen
/// works would otherwise be a dozen round trips, each one able to fail on its own.
///
/// Everything here is a rule about what counts as a change, which is why it is a
/// value type with tests rather than a pile of `@State` in the view.
nonisolated struct AO3CollectionItemStaging: Equatable, Sendable {
    private var drafts: [Int: AO3CollectionItemDraft] = [:]

    /// Staged edits that would actually change something, ready to POST.
    ///
    /// A draft that merely restates the item's current values is **not** a change
    /// and is dropped: a reader who taps Approve and then taps it back has changed
    /// nothing, and submitting that would write a value AO3 already holds while the
    /// toolbar counted it as work.
    func pendingDrafts(for items: [AO3CollectionItem]) -> [AO3CollectionItemDraft] {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return drafts.values.compactMap { draft -> AO3CollectionItemDraft? in
            guard let item = byID[draft.itemID] else { return nil }
            return changes(draft, against: item) ? draft : nil
        }
        .sorted { $0.itemID < $1.itemID }
    }

    func pendingCount(for items: [AO3CollectionItem]) -> Int {
        pendingDrafts(for: items).count
    }

    /// Whether this draft differs from the item as AO3 currently has it.
    private func changes(_ draft: AO3CollectionItemDraft, against item: AO3CollectionItem) -> Bool {
        if draft.remove { return true }
        if let approval = draft.creatorApproval, approval != item.creatorApproval { return true }
        if let approval = draft.moderatorApproval, approval != item.moderatorApproval { return true }
        if let unrevealed = draft.isUnrevealed, unrevealed != item.isUnrevealed { return true }
        if let anonymous = draft.isAnonymous, anonymous != item.isAnonymous { return true }
        return false
    }

    // MARK: What the rows show

    /// The value a row should draw: what is staged, else what AO3 has.
    func creatorApproval(for item: AO3CollectionItem) -> AO3CollectionItemApproval {
        drafts[item.id]?.creatorApproval ?? item.creatorApproval
    }

    func moderatorApproval(for item: AO3CollectionItem) -> AO3CollectionItemApproval {
        drafts[item.id]?.moderatorApproval ?? item.moderatorApproval
    }

    func isUnrevealed(for item: AO3CollectionItem) -> Bool {
        drafts[item.id]?.isUnrevealed ?? item.isUnrevealed
    }

    func isAnonymous(for item: AO3CollectionItem) -> Bool {
        drafts[item.id]?.isAnonymous ?? item.isAnonymous
    }

    func isRemoved(_ item: AO3CollectionItem) -> Bool {
        drafts[item.id]?.remove ?? false
    }

    /// Whether this row has anything staged on it, for the card's own marker.
    func hasChanges(for item: AO3CollectionItem) -> Bool {
        guard let draft = drafts[item.id] else { return false }
        return changes(draft, against: item)
    }

    // MARK: Staging

    mutating func setCreatorApproval(
        _ approval: AO3CollectionItemApproval, for item: AO3CollectionItem
    ) {
        mutate(item) { $0.creatorApproval = approval }
    }

    mutating func setModeratorApproval(
        _ approval: AO3CollectionItemApproval, for item: AO3CollectionItem
    ) {
        mutate(item) { $0.moderatorApproval = approval }
    }

    mutating func setUnrevealed(_ isUnrevealed: Bool, for item: AO3CollectionItem) {
        mutate(item) { $0.isUnrevealed = isUnrevealed }
    }

    mutating func setAnonymous(_ isAnonymous: Bool, for item: AO3CollectionItem) {
        mutate(item) { $0.isAnonymous = isAnonymous }
    }

    /// Removal is exclusive: a row staged for removal has nothing else worth
    /// staging, and sending both would ask AO3 to approve something and then delete
    /// it in the same POST.
    mutating func setRemoved(_ remove: Bool, for item: AO3CollectionItem) {
        if remove {
            drafts[item.id] = AO3CollectionItemDraft(itemID: item.id, remove: true)
        } else {
            mutate(item) { $0.remove = false }
        }
    }

    mutating func clear(_ item: AO3CollectionItem) {
        drafts[item.id] = nil
    }

    mutating func clearAll() {
        drafts.removeAll()
    }

    private mutating func mutate(
        _ item: AO3CollectionItem,
        _ change: (inout AO3CollectionItemDraft) -> Void
    ) {
        var draft = drafts[item.id] ?? AO3CollectionItemDraft(itemID: item.id)
        change(&draft)
        drafts[item.id] = draft
    }
}
