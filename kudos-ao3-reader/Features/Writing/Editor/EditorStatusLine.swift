import Foundation
import SwiftUI

/// Save and sync indicator shown in `EditorStatusLine` (`Studio-Editor.dc.html`).
nonisolated enum EditorSyncState: Equatable, Hashable, Sendable {
    case saved
    case saving
    case synced(device: String)
    case unsaved
    case localOnly

    var label: String {
        switch self {
        case .saved: "Saved"
        case .saving: "Saving…"
        case let .synced(device): "Synced with your \(device)"
        case .unsaved: "Unsaved"
        case .localOnly: "Saved on this device"
        }
    }
}

/// Pure presentation model for `EditorStatusLine`, shared between the SwiftUI view and unit tests.
nonisolated struct EditorStatusSummary: Equatable, Hashable, Sendable {
    var wordsToday: Int
    var dailyGoal: Int?
    var noteCount: Int
    var tkCount: Int
    var syncState: EditorSyncState
    var ao3DraftDaysLeft: Int?
    var chapterWordCount: Int?

    init(
        wordsToday: Int,
        dailyGoal: Int? = nil,
        noteCount: Int = 0,
        tkCount: Int = 0,
        syncState: EditorSyncState = .saved,
        ao3DraftDaysLeft: Int? = nil,
        chapterWordCount: Int? = nil
    ) {
        self.wordsToday = max(0, wordsToday)
        self.dailyGoal = dailyGoal.flatMap { $0 > 0 ? $0 : nil }
        self.noteCount = max(0, noteCount)
        self.tkCount = max(0, tkCount)
        self.syncState = syncState
        self.ao3DraftDaysLeft = ao3DraftDaysLeft
        self.chapterWordCount = chapterWordCount.map { max(0, $0) }
    }

    var goalProgress: Double {
        guard let dailyGoal, dailyGoal > 0 else { return 0 }
        return min(1, max(0, Double(wordsToday) / Double(dailyGoal)))
    }

    var todayWordsText: String {
        "\(wordsToday.formatted()) today"
    }

    var goalRemainderText: String? {
        guard let dailyGoal, dailyGoal > 0 else { return nil }
        let remaining = dailyGoal - wordsToday
        if remaining > 0 {
            return "\(remaining.formatted()) to your goal"
        }
        return "Goal reached"
    }

    /// Full visible string beside the goal ring (e.g. `"640 today · 360 to your goal"`).
    var goalLineText: String {
        if let remainder = goalRemainderText {
            return "\(todayWordsText) · \(remainder)"
        }
        return todayWordsText
    }

    /// Spoken label combining today's count and remaining goal words.
    var goalAccessibilityLabel: String {
        let wordsLabel = "\(wordsToday.formatted()) \(wordsToday == 1 ? "word" : "words") today"
        guard let dailyGoal, dailyGoal > 0 else { return wordsLabel }
        let remaining = dailyGoal - wordsToday
        if remaining > 0 {
            return "\(wordsLabel), \(remaining.formatted()) to your goal"
        }
        return "\(wordsLabel), goal reached"
    }

    /// Visible trailing metadata (e.g. `"1 note · 1 TK · Saved"`).
    var trailingStatusText: String {
        var parts: [String] = []
        if noteCount > 0 {
            parts.append("\(noteCount.formatted()) \(noteCount == 1 ? "note" : "notes")")
        }
        if tkCount > 0 {
            parts.append("\(tkCount.formatted()) TK")
        }
        parts.append(syncState.label)
        return parts.joined(separator: " · ")
    }

    /// Spoken trailing metadata expanding `TK` for VoiceOver.
    var trailingAccessibilityLabel: String {
        var parts: [String] = []
        if noteCount > 0 {
            parts.append("\(noteCount.formatted()) \(noteCount == 1 ? "note" : "notes")")
        }
        if tkCount > 0 {
            parts.append("\(tkCount.formatted()) \(tkCount == 1 ? "TK marker" : "TK markers")")
        }
        parts.append(syncState.label)
        return parts.joined(separator: ", ")
    }

    /// Chip label for an unposted AO3 draft (reuses `DraftExpiry.chipText`).
    var ao3DraftChipText: String? {
        ao3DraftDaysLeft.map { "AO3 draft · \(DraftExpiry.chipText(daysLeft: $0))" }
    }

    var ao3DraftChipAccessibilityLabel: String? {
        ao3DraftDaysLeft.map { "AO3 draft, \(DraftExpiry.chipText(daysLeft: $0))" }
    }

    var chapterWordCountText: String? {
        chapterWordCount.map { "\($0.formatted()) \($0 == 1 ? "word" : "words")" }
    }
}

/// Compact editor status bar (`Studio-Editor.dc.html`): daily word-goal ring and progress,
/// note/TK counts, saved/sync state, and optional AO3 draft expiry chip.
struct EditorStatusLine: View {
    let summary: EditorStatusSummary
    var onTapNotes: (() -> Void)?
    var onTapDraftChip: (() -> Void)?

    @Environment(ThemeManager.self) private var themeManager: ThemeManager?
    @Environment(\.accentFill) private var envAccentFill
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var ringSize: CGFloat = 16

    private var appTheme: ReaderTheme { themeManager?.appTheme ?? .light }
    private var effectiveTint: Color { themeManager?.effectiveTint ?? envAccentFill }
    private var accentInk: Color { themeManager?.accentInk ?? effectiveTint }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if summary.ao3DraftChipText != nil || summary.chapterWordCountText != nil {
                topMetaRow
            }
            goalAndSyncRow
        }
        .font(.caption)
        .monospacedDigit()
    }

    @ViewBuilder
    private var topMetaRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                draftChipView
                chapterWordsView
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 8) {
                draftChipView
                Spacer(minLength: 4)
                chapterWordsView
            }
        }
    }

    @ViewBuilder
    private var goalAndSyncRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                goalBadge
                trailingStatusView
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 8) {
                goalBadge
                Spacer(minLength: 8)
                trailingStatusView
            }
        }
    }

    private var goalBadge: some View {
        HStack(spacing: 6) {
            if summary.dailyGoal != nil {
                goalRing
            }
            goalText
        }
        .combinedAccessibilityRow(summary.goalAccessibilityLabel)
    }

    private var goalRing: some View {
        let clampedRing = min(ringSize, 28)
        let strokeWidth = max(2, clampedRing * 0.16)
        return ZStack {
            Circle()
                .stroke(appTheme.glassStroke(0.22), lineWidth: strokeWidth)
            Circle()
                .trim(from: 0, to: summary.goalProgress)
                .stroke(
                    accentInk,
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(unlessReduced: .smooth, value: summary.goalProgress)
        }
        .frame(width: clampedRing, height: clampedRing)
        .accessibilityHidden(true)
    }

    private var goalText: some View {
        Group {
            if let remainder = summary.goalRemainderText {
                let todayPart = Text(summary.todayWordsText)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.primary)
                let remainderPart = Text(" · \(remainder)")
                    .foregroundStyle(.secondaryInk)
                Text("\(todayPart)\(remainderPart)")
            } else {
                Text(summary.todayWordsText)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.primary)
            }
        }
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
    }

    @ViewBuilder
    private var trailingStatusView: some View {
        let text = Text(summary.trailingStatusText)
            .foregroundStyle(.secondaryInk)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
        if let onTapNotes, summary.noteCount > 0 || summary.tkCount > 0 {
            Button(action: onTapNotes) {
                text
            }
            .buttonStyle(.plain)
            .minimumHitTarget(32)
            .accessibilityLabel(summary.trailingAccessibilityLabel)
        } else {
            text.combinedAccessibilityRow(summary.trailingAccessibilityLabel)
        }
    }

    @ViewBuilder
    private var draftChipView: some View {
        if let chipText = summary.ao3DraftChipText, let daysLeft = summary.ao3DraftDaysLeft {
            let chipColor = draftChipColor(daysLeft: daysLeft)
            let pill = Text(chipText)
                .font(.caption.weight(.bold))
                .foregroundStyle(chipColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(chipColor.opacity(appTheme.isDarkFamily ? 0.22 : 0.12), in: Capsule())
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)

            if let onTapDraftChip {
                Button(action: onTapDraftChip) {
                    pill
                }
                .buttonStyle(.plain)
                .minimumHitTarget(32)
                .accessibilityLabel(summary.ao3DraftChipAccessibilityLabel ?? chipText)
            } else {
                pill.combinedAccessibilityRow(summary.ao3DraftChipAccessibilityLabel ?? chipText)
            }
        }
    }

    @ViewBuilder
    private var chapterWordsView: some View {
        if let chapterWordCountText = summary.chapterWordCountText {
            Text(chapterWordCountText)
                .foregroundStyle(.secondaryInk)
                .lineLimit(1)
        }
    }

    private func draftChipColor(daysLeft: Int) -> Color {
        switch daysLeft {
        case ...3:
            appTheme.errorColor
        case ...7:
            appTheme.isDarkFamily ? .subjectAmber : Color(red: 0.68, green: 0.40, blue: 0.0)
        default:
            accentInk
        }
    }
}

#Preview("Editor Status Line") {
    VStack(spacing: 16) {
        EditorStatusLine(
            summary: EditorStatusSummary(
                wordsToday: 640,
                dailyGoal: 1_000,
                noteCount: 1,
                tkCount: 1,
                syncState: .saved,
                ao3DraftDaysLeft: 22,
                chapterWordCount: 2_060
            )
        )
        EditorStatusLine(
            summary: EditorStatusSummary(
                wordsToday: 1_200,
                dailyGoal: 1_000,
                noteCount: 0,
                tkCount: 0,
                syncState: .synced(device: "Mac"),
                ao3DraftDaysLeft: 2
            )
        )
    }
    .padding()
    .environment(ThemeManager())
}
