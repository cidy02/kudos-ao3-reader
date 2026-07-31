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

/// The reader's Contents sheet segments: the chapter list, plus the in-book
/// Bookmarks and Highlights lists.
enum ReaderContentsSegment: String, CaseIterable, Identifiable {
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

/// Contents / Bookmarks / Highlights, segmented. All three navigate by tapping a
/// row; annotations additionally swipe to delete.
struct ReaderContentsSheet: View {
    @Binding var segment: ReaderContentsSegment
    let sections: [ReaderSection]
    let bookmarks: [ReadingAnnotation]
    let notes: [ReadingAnnotation]
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
                ForEach(ReaderContentsSegment.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

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

    // .other sections have no navigable heading of their own (AO3/Calibre never
    // gave them one) and aren't part of the story — not shown here, matching the
    // reader index's documented Preface/Summary/Chapter/Afterword-only contract.
    // Still reachable by normal page-turning.
    private var chapterList: some View {
        List {
            ForEach(sections.filter { $0.kind != .other }) { section in
                Button {
                    onSelectChapter(section)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(section.title)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        if let percent = chapterStartPercent(section) {
                            Text("\(percent)%")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    // `.buttonStyle(.plain)` keeps the label `.primary` instead
                    // of accent-tinted, but it also draws no background — so
                    // without claiming the full width and an explicit shape,
                    // only the glyphs themselves are tappable and the rest of
                    // the row does nothing. Same pitfall the reader chrome
                    // documents for every one of its buttons.
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    // Full swipe takes the first action — Go, matching the tap.
                    // Go only needs the spine index, so it always works.
                    Button {
                        onSelectChapter(section)
                    } label: {
                        Label("Go", systemImage: "arrow.forward.circle")
                    }
                    .tint(.accentColor)

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
                        Capsule().fill(annotation.color.tint).frame(width: 3)
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
