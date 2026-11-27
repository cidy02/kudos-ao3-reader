import Foundation
import SwiftUI

/// AO3 character limits for chapter summary and author's notes fields
/// (`otwarchive` `config/config.yml` at `452391b6`: `SUMMARY_MAX = 1250`, `NOTES_MAX = 5000`).
nonisolated enum AO3ChapterFieldLimit: Int, CaseIterable, Hashable, Sendable {
    case summary = 1_250
    case notes = 5_000

    var characterLimit: Int { rawValue }
}

/// Visual severity for an AO3 character-limit counter:
/// grey normally, amber within 10% of the limit, red over it.
nonisolated enum CharacterLimitSeverity: Equatable, Hashable, Sendable {
    case normal
    case warning
    case exceeded
}

/// Pure, testable evaluation of a field's character count against AO3's limit.
nonisolated struct CharacterLimitStatus: Equatable, Hashable, Sendable {
    let count: Int
    let limit: Int
    let severity: CharacterLimitSeverity

    var remaining: Int { limit - count }

    var counterText: String {
        "\(count.formatted()) / \(limit.formatted())"
    }

    var overLimitMessage: String? {
        guard severity == .exceeded else { return nil }
        return "AO3 won't accept more than \(limit.formatted()) characters"
    }

    /// Evaluates a raw character count against `limit` using integer arithmetic so the 10%
    /// boundary has no floating-point drift (summary: amber at 1,125…1,250; notes: 4,500…5,000).
    static func evaluate(count: Int, limit: Int) -> CharacterLimitStatus {
        let clampedCount = max(0, count)
        let severity: CharacterLimitSeverity
        if clampedCount > limit {
            severity = .exceeded
        } else if limit > 0, clampedCount * 10 >= limit * 9 {
            severity = .warning
        } else {
            severity = .normal
        }
        return CharacterLimitStatus(count: clampedCount, limit: limit, severity: severity)
    }

    /// Counts Unicode scalar values to match AO3's Ruby `String#length` validation.
    static func evaluate(text: String, field: AO3ChapterFieldLimit) -> CharacterLimitStatus {
        evaluate(count: text.unicodeScalars.count, limit: field.characterLimit)
    }
}

/// Trailing accessory rendered in a `ChapterCollapsibleNoteBlock` header (`Studio-Editor.dc.html`).
nonisolated enum ChapterNoteHeaderTrailing: Equatable, Hashable, Sendable {
    case none
    case counter(String)
    case helper(String)
}

/// Identifies each collapsible metadata block around the chapter text.
nonisolated enum ChapterNoteField: String, CaseIterable, Identifiable, Hashable, Sendable {
    case summary
    case notesBefore
    case notesAfter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summary: "Summary"
        case .notesBefore: "Notes before the chapter"
        case .notesAfter: "Notes after the chapter"
        }
    }

    var placeholder: String {
        switch self {
        case .summary: "Add a summary for this chapter"
        case .notesBefore: "Add notes shown before the chapter"
        case .notesAfter: "Add notes shown after the chapter"
        }
    }

    var limit: AO3ChapterFieldLimit {
        switch self {
        case .summary: .summary
        case .notesBefore, .notesAfter: .notes
        }
    }

    var helperCaption: String? {
        self == .notesAfter ? "Shown at the end on AO3" : nil
    }

    /// Chooses what sits on the trailing side of a collapsible notes header (`Studio-Editor.dc.html`):
    /// warning/exceeded counters always win; a collapsed Summary hides its normal counter so the
    /// preview line breathes; Notes after shows `"Shown at the end on AO3"` while within normal range.
    func headerTrailing(
        isExpanded: Bool,
        showsCollapsedPreview: Bool,
        status: CharacterLimitStatus
    ) -> ChapterNoteHeaderTrailing {
        let charCount = status.count
        if status.severity != .normal {
            return .counter(status.counterText)
        }
        if showsCollapsedPreview, !isExpanded, charCount > 0 {
            return .none
        }
        if let helper = helperCaption {
            return .helper(helper)
        }
        if isExpanded || charCount > 0 {
            return .counter(status.counterText)
        }
        return .none
    }
}

/// Selects which subset of chapter notes blocks to render so callers can place Summary and
/// Notes before above the editing surface and Notes after below it, or render all together.
nonisolated enum ChapterNotesPlacement: Equatable, Hashable, Sendable {
    case beforeChapter
    case afterChapter
    case all
}

/// Summary (collapsible one-liner) and Notes before / after the chapter (`Studio-Editor.dc.html`),
/// each carrying a live AO3 character counter.
struct ChapterNotesBlocks: View {
    @Binding var summary: String
    @Binding var notesBefore: String
    @Binding var notesAfter: String
    var placement: ChapterNotesPlacement = .all

    @State private var isSummaryExpanded: Bool
    @State private var isNotesBeforeExpanded: Bool
    @State private var isNotesAfterExpanded: Bool

    init(
        summary: Binding<String>,
        notesBefore: Binding<String>,
        notesAfter: Binding<String>,
        placement: ChapterNotesPlacement = .all,
        summaryExpanded: Bool = false,
        notesBeforeExpanded: Bool? = nil,
        notesAfterExpanded: Bool? = nil
    ) {
        _summary = summary
        _notesBefore = notesBefore
        _notesAfter = notesAfter
        self.placement = placement
        _isSummaryExpanded = State(initialValue: summaryExpanded)
        _isNotesBeforeExpanded = State(initialValue: notesBeforeExpanded ?? !notesBefore.wrappedValue.isEmpty)
        _isNotesAfterExpanded = State(initialValue: notesAfterExpanded ?? !notesAfter.wrappedValue.isEmpty)
    }

    var body: some View {
        VStack(spacing: 8) {
            if placement == .beforeChapter || placement == .all {
                ChapterCollapsibleNoteBlock(
                    field: .summary,
                    text: $summary,
                    isExpanded: $isSummaryExpanded,
                    showsCollapsedPreview: true
                )
                ChapterCollapsibleNoteBlock(
                    field: .notesBefore,
                    text: $notesBefore,
                    isExpanded: $isNotesBeforeExpanded,
                    showsCollapsedPreview: false
                )
            }
            if placement == .afterChapter || placement == .all {
                ChapterCollapsibleNoteBlock(
                    field: .notesAfter,
                    text: $notesAfter,
                    isExpanded: $isNotesAfterExpanded,
                    showsCollapsedPreview: false
                )
            }
        }
    }
}

/// One collapsible chapter metadata card (Summary, Notes before, or Notes after) with its live
/// AO3 character counter and over-limit error message.
struct ChapterCollapsibleNoteBlock: View {
    let field: ChapterNoteField
    @Binding var text: String
    @Binding var isExpanded: Bool
    var showsCollapsedPreview: Bool = false

    @Environment(ThemeManager.self) private var themeManager: ThemeManager?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var appTheme: ReaderTheme { themeManager?.appTheme ?? .light }
    private var status: CharacterLimitStatus {
        CharacterLimitStatus.evaluate(text: text, field: field.limit)
    }

    /// Readable amber on Light/Sepia paper, `Color.subjectAmber` on Dark/OLED.
    private var warningAmber: Color {
        appTheme.isDarkFamily ? .subjectAmber : AO3TagPalette.teenTextOnLight
    }

    private var counterColor: Color {
        switch status.severity {
        case .normal: themeManager?.secondaryInk ?? .secondary
        case .warning: warningAmber
        case .exceeded: appTheme.errorColor
        }
    }

    private var headerTrailing: ChapterNoteHeaderTrailing {
        field.headerTrailing(
            isExpanded: isExpanded,
            showsCollapsedPreview: showsCollapsedPreview,
            status: status
        )
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            headerButton

            if isExpanded {
                TextField(
                    field.placeholder,
                    text: $text,
                    prompt: appTheme.sepiaPrompt(field.placeholder),
                    axis: .vertical
                )
                .font(.subheadline)
                .foregroundStyle(Color.primary)
                .lineLimit(2 ... 12)
                .accessibilityLabel(field.title)
            }

            if let errorMessage = status.overLimitMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(appTheme.errorColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(errorMessage)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(appTheme.glassFill(0.08), in: shape)
        .overlay(
            shape.strokeBorder(
                status.severity == .exceeded ? appTheme.errorColor.opacity(0.6) : appTheme.glassStroke(0.10),
                lineWidth: status.severity == .exceeded ? 1 : 0.5
            )
        )
    }

    private var headerButton: some View {
        Button {
            withAnimationUnlessReduced(.snappy(duration: 0.2), reduceMotion: reduceMotion) {
                isExpanded.toggle()
            }
        } label: {
            headerContent
                .frame(minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(headerAccessibilityLabel)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }

    @ViewBuilder
    private var headerContent: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    chevron
                    Text(field.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.leading)
                }
                if showsCollapsedPreview, !isExpanded, !text.isEmpty {
                    Text(text)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                headerTrailingView
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 8) {
                chevron
                Text(field.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)

                if showsCollapsedPreview, !isExpanded, !text.isEmpty {
                    Text(text)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer(minLength: 4)
                }

                headerTrailingView
            }
        }
    }

    @ViewBuilder
    private var headerTrailingView: some View {
        switch headerTrailing {
        case .none:
            EmptyView()
        case let .counter(text):
            Text(text)
                .font(.caption.weight(status.severity == .normal ? .regular : .semibold))
                .monospacedDigit()
                .foregroundStyle(counterColor)
                .fixedSize()
        case let .helper(text):
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondaryInk)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
        }
    }

    private var chevron: some View {
        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondaryInk)
            .frame(width: 12)
            .accessibilityHidden(true)
    }

    private var headerAccessibilityLabel: String {
        var parts = [field.title, "\(status.count.formatted()) of \(status.limit.formatted()) characters"]
        if let error = status.overLimitMessage {
            parts.append(error)
        }
        return parts.joined(separator: ", ")
    }
}

private struct ChapterNotesPreviewHost: View {
    @State var summary: String
    @State var notesBefore: String
    @State var notesAfter: String
    var summaryExpanded = false
    var notesBeforeExpanded: Bool?

    var body: some View {
        ScrollView {
            ChapterNotesBlocks(
                summary: $summary,
                notesBefore: $notesBefore,
                notesAfter: $notesAfter,
                summaryExpanded: summaryExpanded,
                notesBeforeExpanded: notesBeforeExpanded
            )
            .padding()
        }
        .environment(ThemeManager())
    }
}

#Preview("Chapter Notes Blocks") {
    ChapterNotesPreviewHost(
        summary: "Ines waits for the tide; Marta waits for Ines.",
        notesBefore:
            "Thank you for the comments on chapter 3. This one is quieter, and I promise the boat matters.",
        notesAfter: "Next chapter Friday. Come and shout at me on Tumblr about Marta."
    )
}

#Preview("Notes Warning & Over Limit") {
    ChapterNotesPreviewHost(
        summary: String(repeating: "a", count: 1_260),
        notesBefore: String(repeating: "b", count: 4_600),
        notesAfter: "",
        summaryExpanded: true,
        notesBeforeExpanded: true
    )
}
