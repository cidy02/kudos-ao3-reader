#if os(iOS)
import SwiftUI

/// The reader's Contents sheet segments: the chapter list, plus the new
/// in-book Bookmarks and Notes lists.
enum ReaderContentsSegment: String, CaseIterable, Identifiable {
    case chapters, bookmarks, notes
    var id: String { rawValue }

    var title: String {
        switch self {
        case .chapters: "Contents"
        case .bookmarks: "Bookmarks"
        case .notes: "Notes"
        }
    }
}

/// Contents / Bookmarks / Notes, segmented. Bookmarks and Notes are honest empty
/// states until the reading-bookmark/highlight models land — the fan menu's
/// "Bookmarks & Notes" pill already routes here rather than to nothing.
struct ReaderContentsSheet: View {
    @Binding var segment: ReaderContentsSegment
    let sections: [ReaderSection]
    let onSelectChapter: (ReaderSection) -> Void

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
                ContentUnavailableView(
                    "No Bookmarks Yet", systemImage: "bookmark",
                    description: Text("Bookmarks you add while reading will appear here.")
                )
            case .notes:
                ContentUnavailableView(
                    "No Notes Yet", systemImage: "highlighter",
                    description: Text("Highlights and notes you add while reading will appear here.")
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
                    Text(section.title)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
    }
}
#endif
