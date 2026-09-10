import Foundation
import SwiftData

/// Local star (1aj). Never written to AO3. Unique on (`kind`, `targetKey`) at
/// application level — see `ReadingLogService`.
nonisolated enum ReadingFavoriteKind: String, Codable, CaseIterable {
    case work
    case author
    case fandom
    case tag
}

@Model final class ReadingFavorite {
    var id: UUID = UUID()
    var kindRaw: String = ReadingFavoriteKind.work.rawValue
    /// Work UUID.uuidString / author identity route / raw fandom tag / raw tag name.
    var targetKey: String = ""
    var displayName: String = ""
    var createdAt: Date = Date()
    var lastModifiedAt: Date = Date()

    var kind: ReadingFavoriteKind {
        get { ReadingFavoriteKind(rawValue: kindRaw) ?? .work }
        set { kindRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        kind: ReadingFavoriteKind,
        targetKey: String,
        displayName: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        kindRaw = kind.rawValue
        self.targetKey = targetKey
        self.displayName = displayName
        self.createdAt = createdAt
        lastModifiedAt = createdAt
    }

    static func workTargetKey(_ work: SavedWork) -> String {
        work.id.uuidString
    }
}
