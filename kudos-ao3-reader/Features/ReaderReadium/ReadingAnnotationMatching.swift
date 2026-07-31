import Foundation

/// Pure helpers for deciding when two highlight anchors mean the same passage.
/// Kept free of Readium/UI so unit tests don't need the toolkit.
enum ReadingAnnotationMatching {
    /// True when a new selection should reuse (or toggle off) an existing
    /// highlight rather than insert a second row for the same words.
    ///
    /// **Locator-only:** exact equality of the stored Readium locator string.
    /// Loose text/position fallbacks were removed — they false-positive on
    /// repeated short phrases ("yes", names) in the same page bucket and
    /// wrongly toggle off the wrong mark.
    static func isSamePassage(
        existingLocator: String,
        selectionLocator: String
    ) -> Bool {
        !existingLocator.isEmpty
            && !selectionLocator.isEmpty
            && existingLocator == selectionLocator
    }
}
