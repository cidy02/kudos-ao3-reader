import Foundation

/// T-573: a work's own choice between the generated cover and the art inside its EPUB.
/// Stored as `SavedWork.coverArtPreferenceRaw` (a plain optional string, never a composite).
/// nil follows the global "Use art from the work" setting; an unknown value (a newer build or
/// Android wrote it) is kept as-is and read as nil.
enum CoverArtPreference: String, CaseIterable {
    case generated
    case embedded

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
        guard coverArtPreferenceRaw != preference?.rawValue else { return }
        coverArtPreferenceRaw = preference?.rawValue
        markModified()
        FolderSyncService.markDirty()
        NotificationCenter.default.post(name: .kudosSyncRelevantSettingChanged, object: nil)
    }
}
