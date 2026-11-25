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
    /// A reader's edit: stamps `lastModifiedAt` (a newer edit wins in backup/sync merge) and wakes Folder Sync.
    @MainActor
    func setCoverArtPreference(_ preference: CoverArtPreference?) {
        // Back to Follow Settings: an explicit value, so the newer edit wins on other devices too.
        let raw = preference?.rawValue ?? (coverArtPreferenceRaw == nil ? nil : CoverArtPreference.followRaw)
        guard coverArtPreferenceRaw != raw else { return }
        coverArtPreferenceRaw = raw
        markModified()
        FolderSyncService.markDirty()
        NotificationCenter.default.post(name: .kudosSyncRelevantSettingChanged, object: nil)
    }
}
