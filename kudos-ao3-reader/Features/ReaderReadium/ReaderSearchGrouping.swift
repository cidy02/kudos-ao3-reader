import Foundation

/// Groups Find in Work results by chapter for display: the reader's current
/// chapter first (labelled "This Chapter"), then every other chapter that has a
/// match, in ascending order (chapter 1 first, working forward).
///
/// Generic over `Result` and takes an `hrefKey` extractor rather than importing
/// Readium directly, so the grouping/sort logic stays pure and unit-testable
/// without a live navigator — the same shape as `ReaderSectionBuilder`.
nonisolated enum ReaderSearchGrouping {
    struct Group<Result>: Identifiable {
        var id: Int { spineIndex }
        /// -1 for a result whose resource doesn't match any known section
        /// (shouldn't happen with a well-formed EPUB, but search shouldn't
        /// silently drop a hit over it either).
        let spineIndex: Int
        let title: String
        let results: [Result]
    }

    static func grouped<Result>(
        _ results: [Result],
        hrefKey: (Result) -> String,
        sections: [ReaderSection],
        currentSpineIndex: Int?
    ) -> [Group<Result>] {
        guard !results.isEmpty else { return [] }

        var sectionByKey: [String: ReaderSection] = [:]
        for section in sections {
            sectionByKey[ReaderSectionBuilder.hrefKey(section.href)] = section
        }

        var bucketOrder: [Int] = []
        var buckets: [Int: (section: ReaderSection?, results: [Result])] = [:]
        for result in results {
            let section = sectionByKey[hrefKey(result)]
            let index = section?.spineIndex ?? -1
            if buckets[index] == nil {
                bucketOrder.append(index)
                buckets[index] = (section, [])
            }
            buckets[index]?.results.append(result)
        }

        return bucketOrder
            .sorted { a, b in
                if a == currentSpineIndex { return true }
                if b == currentSpineIndex { return false }
                return a < b
            }
            .compactMap { index in
                guard let bucket = buckets[index] else { return nil }
                let title: String
                if index == currentSpineIndex {
                    let suffix = bucket.section.map(placeSuffix) ?? ""
                    title = "This Chapter" + suffix
                } else {
                    title = bucket.section?.title ?? "This Work"
                }
                return Group(spineIndex: index, title: title, results: bucket.results)
            }
    }

    /// " (Ch. 5)" / " (Preface)" / "" — never a bare "(Ch. x)" for AO3's own
    /// front/back matter, the same honesty rule `ReaderPositionSummary.Place`
    /// applies to the position card.
    private static func placeSuffix(for section: ReaderSection) -> String {
        switch section.kind {
        case .chapter:
            guard let index = section.storyChapterIndex else { return "" }
            return " (Ch. \(index))"
        case .preface: return " (Preface)"
        case .summary: return " (Summary)"
        case .afterword: return " (Afterword)"
        case .other: return ""
        }
    }
}
