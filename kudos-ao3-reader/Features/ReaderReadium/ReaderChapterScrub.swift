import Foundation

/// Pure helpers for the chapter position slider: map a 0…1 thumb position to a
/// 1-based page, and format the live scrub label. Shared by the position card
/// preview and the seek-on-release navigation so they can't drift.
nonisolated enum ReaderChapterScrub {
    /// 1-based page for a continuous slider value within a chapter of `pageCount` pages.
    static func page(sliderValue: Double, pageCount: Int) -> Int {
        guard pageCount > 1 else { return max(1, pageCount) }
        let index = Int((sliderValue.clamped01 * Double(pageCount - 1)).rounded())
        return min(pageCount, max(1, index + 1))
    }

    /// "Page 3 of 12" for the live scrub preview.
    static func pageLabel(sliderValue: Double, pageCount: Int) -> String {
        let page = page(sliderValue: sliderValue, pageCount: pageCount)
        return "Page \(page) of \(max(1, pageCount))"
    }

    /// Zero-based index into `currentChapterPositions` (same rounding as page).
    static func positionIndex(sliderValue: Double, pageCount: Int) -> Int {
        guard pageCount > 1 else { return 0 }
        return min(pageCount - 1, max(0, page(sliderValue: sliderValue, pageCount: pageCount) - 1))
    }

    /// Snap `value` to `origin` as soon as the rounded page matches the origin
    /// page — same boundary as the page label / selection haptic, so the thumb
    /// locks to the `|` the moment “Page N” returns to the start page.
    static func snapped(
        value: Double,
        toOrigin origin: Double?,
        pageCount: Int
    ) -> Double {
        let value = value.clamped01
        guard let origin, pageCount > 1 else { return value }
        let pinned = origin.clamped01
        if page(sliderValue: value, pageCount: pageCount)
            == page(sliderValue: pinned, pageCount: pageCount)
        {
            return pinned
        }
        return value
    }

    /// Whether the scrub preview page differs from the page under the origin `|`.
    static func isDeviatedFromOrigin(
        sliderValue: Double,
        origin: Double?,
        pageCount: Int
    ) -> Bool {
        guard let origin, pageCount > 0 else { return false }
        return page(sliderValue: sliderValue, pageCount: pageCount)
            != page(sliderValue: origin, pageCount: pageCount)
    }
}

private extension Double {
    var clamped01: Double { min(1, max(0, self)) }
}
