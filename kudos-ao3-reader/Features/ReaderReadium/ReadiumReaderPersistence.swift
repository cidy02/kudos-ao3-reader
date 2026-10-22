#if os(iOS)
import Foundation
import ReadiumShared
import SwiftData

/// Model mutations shared by the reader's streamed, flush and end-of-book saves.
/// Kept outside the view so their cross-device contract can be regression tested.
@MainActor
enum ReadiumReaderPersistence {
    static func writePosition(
        _ locatorString: String, to work: SavedWork, sections: [ReaderSection], at date: Date = Date()
    ) {
        work.applyDebouncedReadiumLocator(locatorString, at: date)
        guard let locator = Locator(persistenceString: locatorString) else { return }
        let key = ReaderSectionBuilder.hrefKey(locator.href.string)
        guard let index = sections.first(where: {
            ReaderSectionBuilder.hrefKey($0.href) == key
        })?.spineIndex else { return }
        // macOS resumes from this pair, never from the Readium locator.
        work.lastSpineIndex = index
        work.lastScrollFraction = min(max(locator.locations.progression ?? 0, 0), 1)
    }

    static func deleteAnnotation(_ annotation: ReadingAnnotation, in context: ModelContext) {
        SyncTombstones.recordDeletion(of: annotation, in: context, reason: "annotationDeleted")
        context.delete(annotation)
    }
}
#endif
