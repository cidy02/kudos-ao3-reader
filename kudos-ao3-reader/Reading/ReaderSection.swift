import Foundation

/// Classification of a single EPUB reading-order (spine) item. AO3's own export
/// (and Calibre's re-splitting of it into per-file EPUBs) puts a Preface and
/// optional Afterword around the real story chapters; neither the reader index
/// nor the progress pill should count those as numbered chapters.
nonisolated enum ReaderSectionKind: Equatable {
    case preface
    case summary
    case chapter
    case afterword
    /// A spine item with no TOC entry that isn't the Preface→Chapter-1 Summary
    /// gap either (e.g. a stray cover/CSS-only fragment). Not shown in the index.
    case other
}

/// One normalized reading-order item, aligned 1:1 with the EPUB's spine —
/// `ReaderSectionBuilder.build` always returns exactly `spineHrefs.count` entries,
/// in spine order, so `sections[spineIndex]` is always valid.
nonisolated struct ReaderSection: Identifiable, Equatable {
    var id: Int { spineIndex }
    let href: String
    let title: String
    let kind: ReaderSectionKind
    let spineIndex: Int
    /// 1-based position among `.chapter`-kind sections only; nil for every other kind.
    let storyChapterIndex: Int?

    /// Bottom-pill label: "P" / "S" / "A" for front/back matter, "<i>/<total>" for a
    /// real story chapter — never a raw spine position. Empty for `.other`, which
    /// isn't part of the story (callers fall back to percent-only display).
    func pillLabel(storyChapterTotal: Int) -> String {
        switch kind {
        case .preface: "P"
        case .summary: "S"
        case .afterword: "A"
        case .chapter: "\(storyChapterIndex ?? 0)/\(max(storyChapterTotal, storyChapterIndex ?? 0))"
        case .other: ""
        }
    }
}

/// Reconciles an EPUB's own (possibly incomplete) table of contents against its
/// full spine into normalized `ReaderSection`s — the shared logic behind both the
/// iOS/Readium reader and the macOS legacy reader's chapter index and progress pill.
/// Pure and platform-agnostic: callers resolve their own TOC representation
/// (Readium `Link`s, or Kudos's own `TOCEntry`) down to spine-index + title pairs
/// before calling `build`.
nonisolated enum ReaderSectionBuilder {
    /// One TOC entry already resolved to the spine index it targets.
    struct RawTOCEntry {
        let title: String
        let spineIndex: Int
    }

    /// - Parameters:
    ///   - tocEntries: the EPUB's own navigation entries, each resolved to a spine
    ///     index. Order doesn't matter (Preface/Afterword recognition uses the
    ///     resulting sections' spine order, not this array's order); duplicates for
    ///     the same spine index keep the last one, matching `EPUBDocument`'s own
    ///     TOC-building convention.
    ///   - spineHrefs: every reading-order item's href, in spine order — the source
    ///     of truth for how many sections exist and what order they're in.
    static func build(tocEntries: [RawTOCEntry], spineHrefs: [String]) -> [ReaderSection] {
        guard !spineHrefs.isEmpty else { return [] }

        var titleBySpineIndex: [Int: String] = [:]
        for entry in tocEntries where spineHrefs.indices.contains(entry.spineIndex) {
            titleBySpineIndex[entry.spineIndex] = entry.title
        }

        var sections: [ReaderSection] = []
        sections.reserveCapacity(spineHrefs.count)
        var storyChapterCounter = 0
        // Only an EPUB that has an actual "Preface"-titled TOC entry can trigger
        // Summary synthesis below — the one AO3-specific signal, so a non-AO3 EPUB
        // (no Preface entry at all) is structurally guaranteed to fall through to
        // the plain "every spine item is a .chapter, numbered by spine position"
        // path, i.e. today's unchanged behavior.
        var sawPreface = false
        // Once true, an untitled gap no longer reads as "the Summary gap" — either
        // a real Summary was already TOC-listed, one was already synthesized, or
        // story content has already started (Summary only ever precedes Chapter 1).
        var summaryGapClosed = false

        for index in spineHrefs.indices {
            let href = spineHrefs[index]
            if let title = titleBySpineIndex[index] {
                let kind = classify(title: title)
                if kind == .preface { sawPreface = true }
                if kind != .preface { summaryGapClosed = true }
                let storyIndex: Int?
                if kind == .chapter {
                    storyChapterCounter += 1
                    storyIndex = storyChapterCounter
                } else {
                    storyIndex = nil
                }
                sections.append(ReaderSection(
                    href: href, title: title, kind: kind,
                    spineIndex: index, storyChapterIndex: storyIndex
                ))
            } else if sawPreface, !summaryGapClosed {
                // AO3's Summary: invisible to the TOC by construction (neither AO3
                // nor Calibre gives it its own navigable heading), but it always
                // sits right after Preface and before Chapter 1.
                summaryGapClosed = true
                sections.append(ReaderSection(
                    href: href, title: "Summary", kind: .summary,
                    spineIndex: index, storyChapterIndex: nil
                ))
            } else {
                sections.append(ReaderSection(
                    href: href, title: "Section \(index + 1)", kind: .other,
                    spineIndex: index, storyChapterIndex: nil
                ))
            }
        }
        return sections
    }

    /// AO3/Calibre's own labels are exact ("Preface", "Summary", "Afterword");
    /// everything else — "Chapter 1", "Epilogue", "Epilogue: Chapter 1" — is real
    /// story content per the spec's explicit instruction to treat epilogues as
    /// chapters unless they're clearly the Afterword.
    private static func classify(title: String) -> ReaderSectionKind {
        switch title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "preface": .preface
        case "summary": .summary
        case "afterword": .afterword
        default: .chapter
        }
    }

    /// Fragment- and path-insensitive comparison key for matching a TOC document's
    /// href (which may carry a `#fragment` or a differently-prefixed relative path)
    /// against a spine item's own href. Mirrors `EPUBDocument.fileKey`'s approach
    /// for the iOS/Readium side, which has no equivalent of its own.
    static func hrefKey(_ href: String) -> String {
        let noFragment = href.split(separator: "#").first.map(String.init) ?? href
        return noFragment.split(separator: "/").last.map(String.init)?.lowercased()
            ?? noFragment.lowercased()
    }
}

extension Array where Element == ReaderSection {
    /// The real story-chapter count derived purely from the normalized sections —
    /// the fallback source when AO3's own "Chapters: X/Y" stat isn't available.
    var storyChapterCount: Int {
        count(where: { $0.kind == .chapter })
    }

    /// The 1-based AO3 **story-chapter** number a reader position maps to — for
    /// chapter-aware features like opening comments on the chapter you're reading.
    /// Uses the normalized sections (never a raw `spineIndex + 1`, which AO3 EPUBs'
    /// Preface/Summary/Afterword would offset):
    /// - a real `.chapter` → its own `storyChapterIndex`;
    /// - front matter (Preface / Summary / any `.other` before Chapter 1) → **1**;
    /// - back matter (Afterword / any `.other` after the last chapter) → the **last**
    ///   story chapter (nearest preceding `.chapter`).
    /// Falls back to **1** when `spineIndex` is out of range or the work has no story
    /// chapters at all (front-matter-only) — the safe default the caller can hand to
    /// the comments layer, which itself clamps to the live AO3 chapter index.
    func ao3StoryChapter(forSpineIndex spineIndex: Int) -> Int {
        guard indices.contains(spineIndex) else { return 1 }
        if let storyIndex = self[spineIndex].storyChapterIndex { return storyIndex }
        // Non-chapter section: the nearest preceding real chapter (so an Afterword or
        // any post-story matter lands on the final chapter); if none precedes it, it's
        // front matter → Chapter 1.
        return self[...spineIndex].last(where: { $0.kind == .chapter })?.storyChapterIndex ?? 1
    }
}

extension SavedWork {
    /// The total story-chapter count from AO3's "Chapters: X/Y" stat (the "Y"
    /// side) — the preferred source for the reader pill's denominator over
    /// counting normalized sections, per the AO3 EPUB indexing spec. `nil` when Y
    /// is unknown ("5/?", a WIP AO3 hasn't posted a final count for) or `chapters`
    /// hasn't been captured yet.
    static func totalChapterCount(from chapters: String) -> Int? {
        let parts = chapters.split(separator: "/")
        guard parts.count == 2 else { return nil }
        return Int(parts[1].trimmingCharacters(in: .whitespaces))
    }
}
