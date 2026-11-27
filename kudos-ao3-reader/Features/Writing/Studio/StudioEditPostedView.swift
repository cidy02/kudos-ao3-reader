import SwiftUI

/// Inline comparison view shown inside `ChapterEditorScreen` when editing a posted
/// chapter and the writer toggles **Changes** (`Studio-Edit-Posted.dc.html`).
///
/// Renders struck-through deletions and highlighted additions directly in the chapter's
/// reading typography, plus any changed chapter metadata (title, summary, notes) and
/// the bottom change-summary footer. Works in Light, Sepia, Dark, and OLED themes and
/// at AX5 Dynamic Type sizes.
struct StudioEditPostedChangesView: View {
    let diff: StudioPostedChapterDiff

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var appTheme: ReaderTheme { theme.appTheme }

    private var deleteBackground: Color {
        switch appTheme {
        case .light:
            Color(red: 0.984, green: 0.890, blue: 0.898)
        case .sepia:
            Color(red: 0.945, green: 0.840, blue: 0.835)
        case .dark, .oled:
            appTheme.errorColor.opacity(0.24)
        }
    }

    private var deleteStrikeColor: Color {
        appTheme.isDarkFamily
            ? appTheme.errorColor
            : Color(red: 0.659, green: 0.196, blue: 0.243)
    }

    private var insertBackground: Color {
        switch appTheme {
        case .light:
            Color(red: 0.886, green: 0.941, blue: 0.902)
        case .sepia:
            Color(red: 0.855, green: 0.905, blue: 0.850)
        case .dark, .oled:
            appTheme.statusSuccessColor.opacity(0.24)
        }
    }

    private var horizontalPadding: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? SubjectMetrics.gutter : 24
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if diff.baselineSource == .editorSessionStart {
                        baselineNotice
                    }

                    if !diff.metadataDiffs.isEmpty {
                        metadataChangesCard
                    }

                    if !diff.hasAnyChanges {
                        noChangesCallout
                    }

                    ForEach(diff.paragraphs) { paragraph in
                        Text(attributedText(for: paragraph))
                            .font(.system(.body, design: .serif))
                            .lineSpacing(6)
                            .foregroundStyle(Color.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel(paragraph.accessibilityLabel)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Chapter text with changes")
            }

            summaryFooter
        }
        .background(appTheme.contentBackdrop)
    }

    // MARK: - Subviews

    private var baselineNotice: some View {
        Text("Comparing with the text when the editor opened.")
            .font(.caption)
            .foregroundStyle(.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var noChangesCallout: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondaryInk)
                .accessibilityHidden(true)
            Text(diff.summaryLine)
                .font(.footnote)
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .subjectPanel()
    }

    private var metadataChangesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(diff.metadataDiffs.enumerated()), id: \.element.id) { index, field in
                if index > 0 { SubjectRowSeparator() }
                VStack(alignment: .leading, spacing: 4) {
                    Text(field.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondaryInk)
                    Text(attributedMetadataDiff(for: field))
                        .font(.subheadline)
                        .foregroundStyle(Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(metadataAccessibilityLabel(for: field))
            }
        }
        .subjectPanel()
    }

    private var summaryFooter: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(appTheme.appSeparator ?? appTheme.glassStroke(0.14))
                .frame(height: 0.5)
                .accessibilityHidden(true)

            Text(diff.summaryLine)
                .font(.caption)
                .foregroundStyle(.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .accessibilityLabel(diff.accessibilitySummary)
        }
        .background(footerBackground)
    }

    @ViewBuilder
    private var footerBackground: some View {
        if let base = appTheme.appBaseBackground {
            base.opacity(0.96)
        } else {
            Rectangle().fill(.bar)
        }
    }

    // MARK: - Attributed diff formatting

    private func attributedText(for paragraph: StudioPostedParagraphDiff) -> AttributedString {
        var output = AttributedString()
        for span in paragraph.spans {
            guard !span.text.isEmpty else { continue }
            var run = AttributedString(span.text)
            switch span.kind {
            case .unchanged:
                break
            case .deleted:
                run.strikethroughStyle = Text.LineStyle(pattern: .solid, color: deleteStrikeColor)
                run.backgroundColor = deleteBackground
            case .inserted:
                run.backgroundColor = insertBackground
            }
            output.append(run)
        }
        return output
    }

    private func attributedMetadataDiff(for field: StudioPostedFieldDiff) -> AttributedString {
        var output = AttributedString()
        let beforeTrimmed = field.before.trimmingCharacters(in: .whitespacesAndNewlines)
        let afterTrimmed = field.after.trimmingCharacters(in: .whitespacesAndNewlines)
        if !beforeTrimmed.isEmpty {
            var oldRun = AttributedString(beforeTrimmed)
            oldRun.strikethroughStyle = Text.LineStyle(pattern: .solid, color: deleteStrikeColor)
            oldRun.backgroundColor = deleteBackground
            output.append(oldRun)
            if !afterTrimmed.isEmpty {
                output.append(AttributedString(" "))
            }
        }
        if !afterTrimmed.isEmpty {
            var newRun = AttributedString(afterTrimmed)
            newRun.backgroundColor = insertBackground
            output.append(newRun)
        } else {
            var removed = AttributedString("Cleared")
            removed.foregroundColor = .secondary
            output.append(removed)
        }
        return output
    }

    private func metadataAccessibilityLabel(for field: StudioPostedFieldDiff) -> String {
        let before = field.before.trimmingCharacters(in: .whitespacesAndNewlines)
        let after = field.after.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (before.isEmpty, after.isEmpty) {
        case (true, false):
            return "\(field.label) added: \(after)"
        case (false, true):
            return "\(field.label) cleared. Was: \(before)"
        case (false, false):
            return "\(field.label) changed from \(before) to \(after)"
        case (true, true):
            return "\(field.label) unchanged"
        }
    }
}
