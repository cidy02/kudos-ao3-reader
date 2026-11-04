import SwiftUI

/// Quality-Results tone chip (FID40, Quality-Results board).
///
/// A small capsule badge showing the signal's glyph and label, tinted per the board's
/// theme semantics across Light, Sepia, Dark, and OLED.
struct WorkSignalToneChip: View {
    let signal: WorkSignal

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.accentFill) private var accentFill
    @Environment(\.accentInk) private var accentInk

    private var theme: ReaderTheme { themeManager.appTheme }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 10, weight: .bold))
                .accessibilityHidden(true)
            Text(signal.label)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .padding(.vertical, 2)
        .foregroundStyle(foregroundColor)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(backgroundColor)
        )
    }

    private var iconName: String {
        switch signal.tone {
        case .high: "heart.fill"
        case .good: "checkmark"
        case .late: "clock"
        case .neutral: "chart.bar.fill"
        case .unusual: "exclamationmark.triangle.fill"
        }
    }

    private var foregroundColor: Color {
        switch signal.tone {
        case .high:
            themeManager.accentInk
        case .good:
            theme.statusSuccessColor
        case .late:
            theme.favoriteColor
        case .neutral, .unusual:
            Color.secondary
        }
    }

    private var backgroundColor: Color {
        switch signal.tone {
        case .high:
            themeManager.effectiveTint.opacity(0.12)
        case .good:
            theme.statusSuccessColor.opacity(0.15)
        case .late:
            theme.favoriteColor.opacity(0.15)
        case .neutral, .unusual:
            Color(.quaternarySystemFill)
        }
    }
}

/// The row's signal line: tone chip + grey note (Quality-Results board).
///
/// Tapping the chip or note opens the Reader Response sheet. Supports Dynamic Type
/// up to AX5 (reflowing vertically without text clipping) and one VoiceOver announcement.
struct WorkSignalRow: View {
    let signal: WorkSignal
    var onTap: (() -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button {
            onTap?()
        } label: {
            content
        }
        .buttonStyle(.borderless)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(signal.accessibilityText)
        .accessibilityHint(onTap != nil ? "Double-tap to open Reader Response details." : "")
    }

    @ViewBuilder
    private var content: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                WorkSignalToneChip(signal: signal)
                if let note = signal.note, !note.isEmpty {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            HStack(spacing: 6) {
                WorkSignalToneChip(signal: signal)
                if let note = signal.note, !note.isEmpty {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }
}

/// "Not Ranked" with its count (Quality-Results board), in the same bold section header
/// every other list section uses.
struct NotRankedSectionHeader: View {
    let count: Int

    var body: some View {
        SectionRuleHeader(title: "Not Ranked", count: count)
            .textCase(nil)
    }
}
