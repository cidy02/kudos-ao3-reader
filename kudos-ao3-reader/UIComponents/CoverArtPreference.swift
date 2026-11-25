import Foundation

/// T-573: a work's own choice between the generated cover and the art inside its EPUB.
/// Stored as `SavedWork.coverArtPreferenceRaw` (a plain optional string, never a composite).
/// nil follows the global "Use art from the work" setting; so does `followRaw`, which a reader's
/// reset writes so the reset reaches other devices (an absent key never clears a choice in merge).
/// An unknown value (a newer build or Android wrote it) is kept as-is and read as nil.
enum CoverArtPreference: String, CaseIterable {
    case generated
    case embedded

    /// Stored when a reader goes back to Follow Settings after choosing; read like nil.
    static let followRaw = "follow"

    static func resolved(_ raw: String?) -> CoverArtPreference? { raw.flatMap(Self.init(rawValue:)) }

    /// Whether the work's own art is wanted. A work with no art draws the generated cover either way.
    static func wantsEmbeddedArt(override raw: String?, global: Bool) -> Bool {
        switch resolved(raw) {
        case .generated: false
        case .embedded: true
        case nil: global
        }
    }

    /// What is actually drawn: the work's art only when it is wanted and the work has some.
    static func showsEmbeddedArt(override raw: String?, global: Bool, hasArt: Bool) -> Bool {
        hasArt && wantsEmbeddedArt(override: raw, global: global)
    }
}

extension SavedWork {
    /// A reader's edit: stamps `coverArtPreferenceChangedAt` (the merge clock for this field, monotonic
    /// so a slow clock cannot lose to its own earlier edit) and wakes Folder Sync. Choosing what is
    /// already selected writes nothing, so an unknown future value is kept.
    @MainActor
    func setCoverArtPreference(_ preference: CoverArtPreference?) {
        let raw: String?
        if let preference {
            raw = preference.rawValue
        } else {
            // Follow Settings: already selected when nothing resolves; after a choice write "follow",
            // an explicit newer edit, since an absent key never clears on other devices.
            guard CoverArtPreference.resolved(coverArtPreferenceRaw) != nil else { return }
            raw = CoverArtPreference.followRaw
        }
        guard coverArtPreferenceRaw != raw else { return }
        coverArtPreferenceRaw = raw
        let now = Date()
        coverArtPreferenceChangedAt = max(now, coverArtPreferenceChangedAt.map { $0.addingTimeInterval(0.001) } ?? now)
        markModified()
        FolderSyncService.markDirty()
        NotificationCenter.default.post(name: .kudosSyncRelevantSettingChanged, object: nil)
    }
}
