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

    /// The global "Use art from the work" setting (default on).
    static func globalUsesEmbeddedArt(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: "useEmbeddedCoverArt") as? Bool ?? true
    }

    /// Whether a work's resolved choice wants its own art (export and drawing agree).
    static func wantsEmbeddedArt(for work: SavedWork, defaults: UserDefaults = .standard) -> Bool {
        wantsEmbeddedArt(override: work.coverArtPreferenceRaw, global: globalUsesEmbeddedArt(defaults))
    }

    /// Merge (Merge / Reconcile / Folder Sync) for a present incoming value, per the contract table.
    /// Stamps beyond `now + maxFutureTimestampSkew` are clamped. An absent key never reaches here.
    static func incomingWins(localRaw: String?, localStamp: Date?, incomingRaw: String,
                             incomingStamp: Date?, now: Date = Date()) -> Bool {
        let local = localStamp.map { KudosBackupContents.clampedArchiveDate($0, now: now) }
        let incoming = incomingStamp.map { KudosBackupContents.clampedArchiveDate($0, now: now) }
        switch (local, incoming) {
        case (nil, nil): return localRaw == nil || incomingRaw > localRaw!
        case (nil, _?): return true
        case (_?, nil): return false
        case let (l?, i?): return i != l ? i > l : incomingRaw > (localRaw ?? "")
        }
    }

    /// What is actually drawn: the work's art only when it is wanted and the work has some.
    static func showsEmbeddedArt(override raw: String?, global: Bool, hasArt: Bool) -> Bool {
        hasArt && wantsEmbeddedArt(override: raw, global: global)
    }
}

extension SavedWork {
    /// A reader's edit: stamps `coverArtPreferenceChangedAt` (the merge clock for this field) and wakes
    /// Folder Sync. It never touches `lastModifiedAt`, so a cover tap cannot override another device's
    /// concurrent edits to the work. The stamp is max(now, previous + 2 ms), capped at now + the
    /// allowed skew; a previous stamp beyond that cap counts as now (a fast clock heals on the next
    /// edit). Choosing what is already selected writes nothing, so an unknown future value is kept.
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
        let ceiling = now.addingTimeInterval(KudosBackupContents.maxFutureTimestampSkew)
        let previous = coverArtPreferenceChangedAt.map { $0 > ceiling ? now : $0 }
        coverArtPreferenceChangedAt = min(max(now, previous?.addingTimeInterval(0.002) ?? now), ceiling)
        FolderSyncService.markDirty()
        NotificationCenter.default.post(name: .kudosSyncRelevantSettingChanged, object: nil)
    }
}
