import Foundation
import SwiftUI

/// Publication/drafting state for a chapter shown in `ChapterSwitcherMenu`.
nonisolated enum EditorChapterStatus: String, CaseIterable, Identifiable, Hashable, Sendable {
    case posted
    case ao3Draft
    case writing
    case planned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .posted: "Posted"
        case .ao3Draft: "AO3 draft"
        case .writing: "Writing"
        case .planned: "Planned"
        }
    }
}

/// Lightweight chapter entry displayed in `ChapterSwitcherMenu` (`Editor-Chapters.dc.html`).
nonisolated struct EditorChapterSummary: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let number: Int
    let title: String
    let wordCount: Int
    let status: EditorChapterStatus
    /// Optional contextual detail such as `"Oct 6"` or `"2 scenes planned"`.
    var detailText: String?

    init(
        id: String,
        number: Int,
        title: String,
        wordCount: Int,
        status: EditorChapterStatus,
        detailText: String? = nil
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.wordCount = wordCount
        self.status = status
        self.detailText = detailText
    }

    var resolvedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    /// Row heading inside the chapter menu (e.g. `"4 · Slack Water"`).
    var menuTitle: String {
        "\(number) · \(resolvedTitle)"
    }

    /// Compact trigger title for the editor header (e.g. `"Ch. 4 · Slack Water"`).
    var headerTitle: String {
        "Ch. \(number) · \(resolvedTitle)"
    }

    /// Subtitle combining word count, optional date/scene detail, and status.
    var menuSubtitle: String {
        var parts: [String] = []
        let hasDetail = detailText.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
        if wordCount > 0 || (status != .planned && !hasDetail) {
            parts.append("\(wordCount.formatted()) \(wordCount == 1 ? "word" : "words")")
        }
        if let detailText, !detailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(detailText)
        }
        parts.append(status.title)
        return parts.joined(separator: " · ")
    }
}

/// Callbacks for `ChapterSwitcherMenu`.
struct ChapterSwitcherActions {
    var onSelectChapter: (String) -> Void = { _ in }
    var onNewChapter: () -> Void = {}
    var onReorderChapters: () -> Void = {}
    var onWorkDetails: () -> Void = {}
}

/// Native chapter switcher `Menu` (`Editor-Chapters.dc.html`): lists every chapter with
/// its number, title, word count and status, marks the active chapter with a native
/// checkmark, then offers New Chapter, Reorder Chapters, and Work Details.
struct ChapterSwitcherMenu<LabelContent: View>: View {
    let chapters: [EditorChapterSummary]
    let currentChapterID: String
    let actions: ChapterSwitcherActions
    @ViewBuilder let label: (EditorChapterSummary?) -> LabelContent

    init(
        chapters: [EditorChapterSummary],
        currentChapterID: String,
        actions: ChapterSwitcherActions = ChapterSwitcherActions(),
        @ViewBuilder label: @escaping (EditorChapterSummary?) -> LabelContent
    ) {
        self.chapters = chapters
        self.currentChapterID = currentChapterID
        self.actions = actions
        self.label = label
    }

    private var currentChapter: EditorChapterSummary? {
        chapters.first(where: { $0.id == currentChapterID })
    }

    private var accessibilityTriggerLabel: String {
        if let currentChapter {
            return "Chapter \(currentChapter.number), \(currentChapter.resolvedTitle). Switch chapter"
        }
        return "Switch chapter"
    }

    var body: some View {
        Menu {
            Section {
                ForEach(chapters) { chapter in
                    Toggle(
                        isOn: Binding(
                            get: { chapter.id == currentChapterID },
                            set: { _ in actions.onSelectChapter(chapter.id) }
                        )
                    ) {
                        Text(chapter.menuTitle)
                        Text(chapter.menuSubtitle)
                    }
                }
            }

            Section {
                Button {
                    actions.onNewChapter()
                } label: {
                    Label("New Chapter", systemImage: "plus")
                }

                Button {
                    actions.onReorderChapters()
                } label: {
                    Label("Reorder Chapters", systemImage: "arrow.up.arrow.down")
                }

                Button {
                    actions.onWorkDetails()
                } label: {
                    Label("Work Details", systemImage: "info.circle")
                }
            }
        } label: {
            label(currentChapter)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityTriggerLabel)
    }
}

/// Default trigger matching `Studio-Editor.dc.html`'s chapter title button.
struct ChapterSwitcherTriggerLabel: View {
    let title: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .truncationMode(.tail)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondaryInk)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}

extension ChapterSwitcherMenu where LabelContent == ChapterSwitcherTriggerLabel {
    init(
        chapters: [EditorChapterSummary],
        currentChapterID: String,
        fallbackTitle: String = "Chapters",
        actions: ChapterSwitcherActions = ChapterSwitcherActions()
    ) {
        self.init(
            chapters: chapters,
            currentChapterID: currentChapterID,
            actions: actions,
            label: { current in
                ChapterSwitcherTriggerLabel(title: current?.headerTitle ?? fallbackTitle)
            }
        )
    }
}

#Preview("Chapter Switcher Menu") {
    let sampleChapters: [EditorChapterSummary] = [
        EditorChapterSummary(
            id: "1", number: 1, title: "The Turning", wordCount: 2_410,
            status: .posted, detailText: "Oct 6"
        ),
        EditorChapterSummary(
            id: "2", number: 2, title: "Low Water", wordCount: 1_980,
            status: .posted, detailText: "Oct 13"
        ),
        EditorChapterSummary(
            id: "3", number: 3, title: "Spring Tide", wordCount: 2_210,
            status: .posted, detailText: "Oct 20"
        ),
        EditorChapterSummary(
            id: "4", number: 4, title: "Slack Water", wordCount: 2_060,
            status: .ao3Draft
        ),
        EditorChapterSummary(
            id: "5", number: 5, title: "", wordCount: 0,
            status: .planned, detailText: "2 scenes planned"
        )
    ]
    return EditorHeader(
        workTitle: "What the Tide Keeps",
        onDone: {},
        onNotes: {},
        chapterTrigger: {
            ChapterSwitcherMenu(chapters: sampleChapters, currentChapterID: "4")
        },
        moreTrigger: {
            EditorMoreMenu(savedVersionCount: 14)
        }
    )
    .environment(ThemeManager())
}
