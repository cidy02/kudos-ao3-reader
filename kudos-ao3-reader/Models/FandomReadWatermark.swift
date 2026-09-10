import Foundation
import SwiftData

/// Per-fandom "last visited" watermark for 1bc new-since-last-visit. `fandomName`
/// is the **raw AO3 tag name**, never a parsed display title.
@Model final class FandomReadWatermark {
    var id: UUID = UUID()
    var fandomName: String = ""
    var lastVisitedAt: Date = Date()
    var newestWorkIDSeen: Int? = nil
    var newestWorkTitleSeen: String = ""
    var lastModifiedAt: Date = Date()

    init(
        id: UUID = UUID(),
        fandomName: String,
        lastVisitedAt: Date = Date(),
        newestWorkIDSeen: Int? = nil,
        newestWorkTitleSeen: String = "",
        lastModifiedAt: Date? = nil
    ) {
        self.id = id
        self.fandomName = fandomName
        self.lastVisitedAt = lastVisitedAt
        self.newestWorkIDSeen = newestWorkIDSeen
        self.newestWorkTitleSeen = newestWorkTitleSeen
        self.lastModifiedAt = lastModifiedAt ?? lastVisitedAt
    }
}
