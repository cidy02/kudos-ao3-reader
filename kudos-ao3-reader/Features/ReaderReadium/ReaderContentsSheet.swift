#if os(iOS)
import SwiftUI

extension ReadingAnnotationColor {
    /// The swatch drawn over the page and beside a note. Muted on purpose: a
    /// highlight sits *under* body text and has to stay readable in every reader
    /// theme, so these are low-saturation rather than marker-pen bright.
    var tint: Color {
        switch self {
        case .yellow: Color(red: 0.98, green: 0.85, blue: 0.35)
        case .green: Color(red: 0.55, green: 0.85, blue: 0.55)
        case .blue: Color(red: 0.50, green: 0.76, blue: 0.98)
        case .pink: Color(red: 0.98, green: 0.62, blue: 0.76)
        case .purple: Color(red: 0.76, green: 0.64, blue: 0.95)
        // Not a fill — drawn as a rule beneath the words instead.
        case .underline: Color(red: 0.35, green: 0.55, blue: 0.95)
        }
    }
}

extension ReadingAnnotation {
    /// Preset tint, or the exact colour stored from the well.
    var displayTint: Color {
        if let hex = customColorHex, let color = Color(hex: hex) { return color }
        return color.tint
    }
}

/// The reader's Contents sheet segments: the chapter list, plus the in-book
/// Bookmarks and Highlights lists.
nonisolated enum ReaderContentsSegment: String, CaseIterable, Identifiable {
    // Raw case stays `notes` (SwiftData/persistence-adjacent identifiers elsewhere
    // key off it) — only the user-facing `title` changed. This segment lists
    // every highlight, noted or not (a bare highlight needs a sheet-based delete
    // path too), so "Notes" was never an accurate label for what it shows.
    case chapters, bookmarks, notes
    var id: String { rawValue }

    var title: String {
        switch self {
        case .chapters: "Contents"
        case .bookmarks: "Bookmarks"
        case .notes: "Highlights"
        }
    }
}

/// Copy shared by the segmented control and the reader's live-place line.
nonisolated enum ReaderContentsLabels {
    struct ChapterRowPresentation: Equatable, Sendable {
        let number: String
        let isCurrent: Bool
        let state: String
        let accessibilityLabel: String
    }

    static func segmentTitle(_ segment: ReaderContentsSegment, count: Int) -> String {
        guard segment != .chapters, count > 0 else { return segment.title }
        return "\(segment.title) · \(count)"
    }

    static func progress(percent: Int, remainingPositions: Int?) -> String {
        let place = "\(percent)% of the work"
        // Under half a minute rounds to "0 min": say nothing rather than "about 0 min left".
        guard let remainingPositions, ReaderTimeEstimate.minutes(forPositions: remainingPositions) > 0 else {
            return place
        }
        return "\(place) · about \(ReaderTimeEstimate.workRemainingLabel(positions: remainingPositions))"
    }

    static func chapterRow(
        section: ReaderSection,
        currentSpineIndex: Int?,
        currentChapterProgression: Double?,
        storyChapterWords: [Int]?
    ) -> ChapterRowPresentation {
        let isCurrent = currentSpineIndex != nil && section.spineIndex == currentSpineIndex
        let number: String
        if section.kind == .chapter, let storyIndex = section.storyChapterIndex {
            number = "\(storyIndex)"
        } else {
            number = ""
        }

        let state: String
        if isCurrent {
            if let progression = currentChapterProgression {
                let percent = max(0, min(100, Int((progression * 100).rounded())))
                state = "\(percent)% · reading"
            } else {
                state = "0% · reading"
            }
        } else if let currentSpineIndex {
            if section.spineIndex < currentSpineIndex {
                state = section.kind == .chapter ? "read" : ""
            } else {
                if section.kind == .chapter,
                   let storyIndex = section.storyChapterIndex,
                   let words = storyChapterWords,
                   words.indices.contains(storyIndex - 1),
                   words[storyIndex - 1] > 0 {
                    let wordCount = words[storyIndex - 1]
                    let minutes = max(1, Int((Double(wordCount) / ReaderTimeEstimate.readingWordsPerMinute).rounded()))
                    state = ReaderTimeEstimate.durationLabel(minutes: minutes)
                } else {
                    state = ""
                }
            }
        } else {
            state = ""
        }

        let accessibilityLabel: String
        var parts: [String] = []
        if !number.isEmpty {
            parts.append(number)
        }
        parts.append(section.title)
        if !state.isEmpty {
            parts.append(state)
        }
        accessibilityLabel = parts.joined(separator: ", ")

        return ChapterRowPresentation(
            number: number,
            isCurrent: isCurrent,
            state: state,
            accessibilityLabel: accessibilityLabel
        )
    }
}

/// Contents / Bookmarks / Highlights, segmented. All three navigate by tapping a
/// row; annotations additionally swipe to delete.
struct ReaderContentsSheet: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var segment: ReaderContentsSegment
    let sections: [ReaderSection]
    var currentSpineIndex: Int? = nil
    var currentChapterProgression: Double? = nil
    var chapterLengths: ChapterLengths? = nil
    let bookmarks: [ReadingAnnotation]
    let notes: [ReadingAnnotation]
    let progressLabel: String?
    /// How far into the work a chapter starts, as a whole percent, when the
    /// position list knows it yet.
    ///
    /// Apple Books prints a page number in this slot. This reader can't: its
    /// pages are per-chapter *visual* swipe measurements that only exist once a
    /// chapter has actually been laid out in the web view, so a book-wide page
    /// number for an unopened chapter would be invented. Percent comes straight
    /// from the chapter's first Readium position and is known for every chapter
    /// up front — and it's already the unit the position card and the
    /// annotation rows show, so the sheet stays internally consistent.
    let chapterStartPercent: (ReaderSection) -> Int?
    let onSelectChapter: (ReaderSection) -> Void
    let onBookmarkChapter: (ReaderSection) -> Void
    let onAddNoteToChapter: (ReaderSection) -> Void
    let onSelectAnnotation: (ReadingAnnotation) -> Void
    let onDeleteAnnotation: (ReadingAnnotation) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $segment) {
                ForEach(ReaderContentsSegment.allCases) { segment in
                    Text(ReaderContentsLabels.segmentTitle(segment, count: count(for: segment)))
                        .tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .accentFill()
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            if let progressLabel {
                Text(progressLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            switch segment {
            case .chapters:
                chapterList
            case .bookmarks:
                annotationList(
                    bookmarks,
                    emptyTitle: "No Bookmarks Yet",
                    emptyIcon: "bookmark",
                    emptyMessage: "Bookmarks you add while reading will appear here."
                )
            case .notes:
                annotationList(
                    notes,
                    emptyTitle: "No Highlights Yet",
                    emptyIcon: "highlighter",
                    emptyMessage: "Highlights and notes you add while reading will appear here. "
                        + "Swipe a row to delete, or tap to edit."
                )
            }
        }
    }

    private func count(for segment: ReaderContentsSegment) -> Int {
        switch segment {
        case .chapters: 0
        case .bookmarks: bookmarks.count
        case .notes: notes.count
        }
    }

    // .other sections have no navigable heading of their own (AO3/Calibre never
    // gave them one) and aren't part of the story — not shown here, matching the
    // reader index's documented Preface/Summary/Chapter/Afterword-only contract.
    // Still reachable by normal page-turning.
    private var chapterList: some View {
        List {
            ForEach(sections.filter { $0.kind != .other }) { section in
                let presentation = ReaderContentsLabels.chapterRow(
                    section: section,
                    currentSpineIndex: currentSpineIndex,
                    currentChapterProgression: currentChapterProgression,
                    storyChapterWords: chapterLengths?.words
                )
                Button {
                    onSelectChapter(section)
                } label: {
                    chapterRowContent(section: section, presentation: presentation)
                }
                .buttonStyle(.plain)
                .listRowBackground(presentation.isCurrent ? theme.effectiveTint.opacity(0.08) : nil)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    // Full swipe takes the first action — Go, matching the tap.
                    // Go only needs the spine index, so it always works.
                    Button {
                        onSelectChapter(section)
                    } label: {
                        Label("Go", systemImage: "arrow.forward.circle")
                    }
                    .tint(theme.effectiveTint)

                    // Bookmark and Add Note both anchor to the chapter's first
                    // Readium position, which arrives asynchronously *after*
                    // the section list does. During that window there is no
                    // anchor to write, so offer the actions only once there is
                    // one — a swipe action that silently does nothing is worse
                    // than one that isn't there yet. `chapterStartPercent` is
                    // derived from the same position, so it doubles as the
                    // readiness signal rather than needing a second flag.
                    if chapterStartPercent(section) != nil {
                        Button {
                            onBookmarkChapter(section)
                        } label: {
                            Label("Bookmark", systemImage: "bookmark")
                        }
                        .tint(.orange)

                        Button {
                            onAddNoteToChapter(section)
                        } label: {
                            Label("Add Note", systemImage: "note.text")
                        }
                        .tint(.gray)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func chapterRowContent(
        section: ReaderSection,
        presentation: ReaderContentsLabels.ChapterRowPresentation
    ) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if !presentation.number.isEmpty {
                        Text(presentation.number)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(section.title)
                        .font(.body.weight(presentation.isCurrent ? .semibold : .regular))
                        .foregroundStyle(presentation.isCurrent ? theme.accentInk : Color.primary)
                        .lineLimit(5)
                }
                if !presentation.state.isEmpty {
                    Text(presentation.state)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.accessibilityLabel)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(presentation.number.isEmpty ? " " : presentation.number)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 26, alignment: .leading)

                Text(section.title)
                    .font(.body.weight(presentation.isCurrent ? .semibold : .regular))
                    .foregroundStyle(presentation.isCurrent ? theme.accentInk : Color.primary)
                    .lineLimit(2)

                Spacer(minLength: 8)

                if !presentation.state.isEmpty {
                    Text(presentation.state)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.accessibilityLabel)
        }
    }

    @ViewBuilder
    private func annotationList(
        _ items: [ReadingAnnotation],
        emptyTitle: String, emptyIcon: String, emptyMessage: String
    ) -> some View {
        if items.isEmpty {
            ContentUnavailableView(
                emptyTitle, systemImage: emptyIcon, description: Text(emptyMessage)
            )
        } else {
            List {
                ForEach(items) { annotation in
                    Button {
                        onSelectAnnotation(annotation)
                    } label: {
                        ReaderAnnotationRow(annotation: annotation)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) {
                            onDeleteAnnotation(annotation)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

/// One saved mark: where it sits, how far into the work it is, and — for a
/// highlight — the passage and any note beneath it.
private struct ReaderAnnotationRow: View {
    let annotation: ReadingAnnotation

    /// A bookmark row *is* its chapter line — there's no quoted passage under
    /// it, and usually no note either — so that line is the row's actual
    /// content and reads at the same size and weight as a Contents row. On a
    /// highlight the same line is only a caption above the quote, which is the
    /// real content, so it stays small and recedes.
    private var isBookmark: Bool { annotation.kind == .bookmark }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(annotation.chapterTitle.isEmpty ? "In this work" : annotation.chapterTitle)
                    // Deliberately not `.tint`: theme-coloured chapter labels on
                    // every row made both lists read as clutter rather than as
                    // a hierarchy. Colour in these rows now means one thing —
                    // the highlight's own swatch on the quote bar below.
                    .font(isBookmark ? .body : .caption)
                    .foregroundStyle(isBookmark ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text("\(Int((annotation.progression * 100).rounded()))%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            if !annotation.selectedText.isEmpty {
                Text(annotation.selectedText)
                    .font(.callout)
                    .lineLimit(3)
                    // A quote bar, the way the design shows highlights — in the
                    // mark's own colour, not the reader theme tint, so it reads
                    // as "this is what I marked" rather than a generic accent.
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        Capsule().fill(annotation.displayTint).frame(width: 3)
                    }
            }

            if annotation.hasNote {
                Text(annotation.note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
#endif
