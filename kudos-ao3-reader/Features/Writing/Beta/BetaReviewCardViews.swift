import SwiftUI

// MARK: - Status chip (`Editor-Beta.dc.html`)

struct BetaCopyStatusChip: View {
    let status: BetaCopyStatus

    @Environment(ThemeManager.self) private var themeManager: ThemeManager?

    private var appTheme: ReaderTheme { themeManager?.appTheme ?? .light }

    var body: some View {
        Text(status.chipTitle)
            .font(.caption.weight(.bold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(backgroundColor, in: Capsule())
            .fixedSize()
    }

    private var foregroundColor: Color {
        switch status {
        case .cameBack:
            appTheme.isDarkFamily ? appTheme.statusSuccessColor : Color(red: 0.11, green: 0.37, blue: 0.23)
        case .waiting:
            appTheme.isDarkFamily ? Color.primary : Color(red: 0.23, green: 0.23, blue: 0.24)
        case .reviewed:
            themeManager?.secondaryInk ?? .secondary
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .cameBack:
            appTheme.isDarkFamily
                ? appTheme.statusSuccessColor.opacity(0.22)
                : Color(red: 0.90, green: 0.95, blue: 0.92)
        case .waiting:
            appTheme.glassFill(appTheme.isDarkFamily ? 0.16 : 0.08)
        case .reviewed:
            appTheme.glassFill(0.06)
        }
    }
}

// MARK: - Suggestion card (`Editor-Beta.dc.html`)

struct BetaSuggestionCardView: View {
    let suggestion: BetaSuggestionItem
    let isBusy: Bool
    let wasCopied: Bool
    let onAccept: () -> Void
    let onReject: () -> Void
    let onCopy: () -> Void
    let onDismissUnplaceable: () -> Void

    @Environment(ThemeManager.self) private var themeManager: ThemeManager?
    @Environment(\.accentFill) private var envAccentFill
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var appTheme: ReaderTheme { themeManager?.appTheme ?? .light }
    private var effectiveTint: Color { themeManager?.effectiveTint ?? envAccentFill }

    private var cardFill: Color {
        if appTheme == .light {
            return Color(red: 0.984, green: 0.980, blue: 0.965)
        }
        return appTheme.cardSurface
    }

    private var cardBorder: Color {
        if appTheme == .light {
            return Color(red: 0.898, green: 0.875, blue: 0.824)
        }
        return appTheme.cardBorder
    }

    private var deleteBackground: Color {
        appTheme.isDarkFamily
            ? appTheme.errorColor.opacity(0.24)
            : Color(red: 0.984, green: 0.890, blue: 0.898)
    }

    private var deleteStrikeColor: Color {
        appTheme.isDarkFamily
            ? appTheme.errorColor
            : Color(red: 0.659, green: 0.196, blue: 0.243)
    }

    private var insertBackground: Color {
        appTheme.isDarkFamily
            ? appTheme.statusSuccessColor.opacity(0.24)
            : Color(red: 0.886, green: 0.941, blue: 0.902)
    }

    private var insertUnderlineColor: Color {
        appTheme.isDarkFamily
            ? appTheme.statusSuccessColor
            : Color(red: 0.114, green: 0.369, blue: 0.227)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 12) {
            if suggestion.isWholeParagraphAddition {
                Text("Added paragraph")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondaryInk)
            }

            Text(diffAttributedText)
                .font(.system(.body, design: .serif))
                .lineSpacing(5)
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(diffAccessibilityText)

            if suggestion.state == .unplaceable {
                unplaceableBanner
            }

            footerRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill, in: shape)
        .overlay(shape.strokeBorder(cardBorder, lineWidth: 0.5))
        .opacity(suggestion.state.isHandled ? 0.62 : 1.0)
    }

    private var unplaceableBanner: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(appTheme.isDarkFamily ? Color.subjectAmber : Color(red: 0.68, green: 0.40, blue: 0.0))
                .accessibilityHidden(true)
            Text("Couldn’t place this one. Copy it to apply by hand.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var footerRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                attributionLabel
                actionControls
            }
        } else {
            HStack(alignment: .center, spacing: 8) {
                attributionLabel
                Spacer(minLength: 8)
                actionControls
            }
        }
    }

    private var attributionLabel: some View {
        Text("Suggested by \(suggestion.author)")
            .font(.footnote)
            .foregroundStyle(.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var actionControls: some View {
        switch suggestion.state {
        case .pending:
            FlowLayout(spacing: 8, rowSpacing: 8) {
                pillButton(
                    title: "Reject",
                    accessibilityLabel: "Reject suggestion by \(suggestion.author)",
                    isPrimary: false,
                    action: onReject
                )
                pillButton(
                    title: "Accept",
                    accessibilityLabel: "Accept suggestion by \(suggestion.author)",
                    isPrimary: true,
                    action: onAccept
                )
            }
        case .unplaceable:
            FlowLayout(spacing: 8, rowSpacing: 8) {
                pillButton(
                    title: "Dismiss",
                    accessibilityLabel: "Dismiss unplaced suggestion by \(suggestion.author)",
                    isPrimary: false,
                    action: onDismissUnplaceable
                )
                pillButton(
                    title: wasCopied ? "Copied" : "Copy",
                    accessibilityLabel: "Copy suggested text by \(suggestion.author)",
                    isPrimary: true,
                    action: onCopy
                )
            }
        case .accepted:
            Label("Accepted", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(appTheme.statusSuccessColor)
        case .rejected:
            Text("Rejected")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondaryInk)
        case .dismissed:
            Text("Handled")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondaryInk)
        }
    }

    private func pillButton(
        title: String,
        accessibilityLabel: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let shape = SubjectMetrics.controlShape(dynamicTypeSize)
        let foreground = isPrimary ? ThemeManager.label(on: effectiveTint) : Color.primary
        let background = isPrimary ? effectiveTint : appTheme.glassFill(appTheme.isDarkFamily ? 0.18 : 0.11)
        return Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(foreground)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .frame(minHeight: 34)
                .background(background, in: shape)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .minimumHitTarget(44)
        .disabled(isBusy)
        .opacity(isBusy ? 0.5 : 1)
        .accessibilityLabel(accessibilityLabel)
    }

    private var diffAttributedText: AttributedString {
        let slices = paragraphContextSlices()
        var output = AttributedString()
        if !slices.before.isEmpty {
            output.append(AttributedString(slices.before))
        }
        if !suggestion.deletedText.isEmpty {
            var deleted = AttributedString(suggestion.deletedText)
            deleted.strikethroughStyle = Text.LineStyle(pattern: .solid, color: deleteStrikeColor)
            deleted.backgroundColor = deleteBackground
            output.append(deleted)
            if !suggestion.insertedText.isEmpty {
                output.append(AttributedString(" "))
            }
        }
        if !suggestion.insertedText.isEmpty {
            var inserted = AttributedString(suggestion.insertedText)
            inserted.underlineStyle = Text.LineStyle(pattern: .solid, color: insertUnderlineColor)
            inserted.backgroundColor = insertBackground
            output.append(inserted)
        }
        if !slices.after.isEmpty {
            output.append(AttributedString(slices.after))
        }
        return output
    }

    private var diffAccessibilityText: String {
        var parts: [String] = []
        if !suggestion.deletedText.isEmpty {
            parts.append("Delete: \(suggestion.deletedText)")
        }
        if !suggestion.insertedText.isEmpty {
            parts.append("Insert: \(suggestion.insertedText)")
        }
        return parts.isEmpty ? suggestion.paragraphText : parts.joined(separator: ". ")
    }

    private func paragraphContextSlices() -> (before: String, after: String) {
        guard !suggestion.paragraphText.isEmpty else { return ("", "") }
        let para = suggestion.paragraphText
        let total = para.utf16.count
        let start = max(0, min(suggestion.editStartUTF16, total))
        let end = max(start, min(suggestion.editEndUTF16, total))
        let startIdx = para.utf16.index(para.utf16.startIndex, offsetBy: start)
        let endIdx = para.utf16.index(para.utf16.startIndex, offsetBy: end)
        let beforeFull = String.Index(startIdx, within: para).map { String(para[..<$0]) } ?? ""
        let afterFull = String.Index(endIdx, within: para).map { String(para[$0...]) } ?? ""

        // Keep ordinary paragraphs intact; clamp only very long walls of text around the edit.
        let maxSideChars = 260
        let before = beforeFull.count > maxSideChars
            ? "…" + String(beforeFull.suffix(maxSideChars))
            : beforeFull
        let after = afterFull.count > maxSideChars
            ? String(afterFull.prefix(maxSideChars)) + "…"
            : afterFull
        return (before, after)
    }
}

// MARK: - Comment card (`Editor-Beta.dc.html`)

struct BetaCommentCardView: View {
    let comment: BetaCommentItem
    let isBusy: Bool
    let onMarkDone: () -> Void

    @Environment(ThemeManager.self) private var themeManager: ThemeManager?
    @Environment(\.accentFill) private var envAccentFill
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var appTheme: ReaderTheme { themeManager?.appTheme ?? .light }
    private var effectiveTint: Color { themeManager?.effectiveTint ?? envAccentFill }
    private var accentInk: Color { themeManager?.accentInk ?? effectiveTint }

    private var avatarBackground: Color {
        appTheme.isDarkFamily
            ? Color(red: 0.34, green: 0.54, blue: 0.38)
            : Color(red: 0.243, green: 0.357, blue: 0.227)
    }

    private var initialLetter: String {
        let trimmed = comment.author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "B" }
        return String(first).uppercased()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    commentTextColumn
                    doneControl
                }
            } else {
                HStack(alignment: .center, spacing: 10) {
                    avatarCircle
                    commentTextColumn
                        .frame(maxWidth: .infinity, alignment: .leading)
                    doneControl
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appTheme.cardSurface, in: shape)
        .overlay(shape.strokeBorder(appTheme.cardBorder, lineWidth: 0.5))
        .opacity(comment.isDone ? 0.62 : 1.0)
    }

    private var avatarCircle: some View {
        Text(initialLetter)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.white)
            .frame(width: 32, height: 32)
            .background(avatarBackground, in: Circle())
            .accessibilityHidden(true)
    }

    private var commentTextColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            headerLine
            Text(comment.text)
                .font(.subheadline)
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headerLine: some View {
        let trimmedQuote = comment.quote.trimmingCharacters(in: .whitespacesAndNewlines)
        let authorText = Text(comment.author).fontWeight(.semibold).foregroundStyle(Color.primary)
        return Group {
            if trimmedQuote.isEmpty {
                authorText
            } else {
                let preview = trimmedQuote.count > 80
                    ? String(trimmedQuote.prefix(80)) + "…"
                    : trimmedQuote
                let suffix = Text(" on “\(preview)”").foregroundStyle(.secondaryInk)
                Text("\(authorText)\(suffix)")
            }
        }
        .font(.footnote)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var doneControl: some View {
        if comment.isDone {
            Label("Done", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(appTheme.statusSuccessColor)
        } else {
            let shape = SubjectMetrics.controlShape(dynamicTypeSize)
            Button(action: onMarkDone) {
                Text("Done")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accentInk)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(minHeight: 34)
                    .background(
                        effectiveTint.opacity(appTheme.isDarkFamily ? 0.24 : 0.12),
                        in: shape
                    )
                    .contentShape(shape)
            }
            .buttonStyle(.plain)
            .minimumHitTarget(44)
            .disabled(isBusy)
            .opacity(isBusy ? 0.5 : 1)
            .accessibilityLabel("Mark \(comment.author)’s comment done")
        }
    }
}

// MARK: - Beta name prompt sheet (offers names used before)

struct BetaNamePromptSheet: View {
    let format: BetaCopyFormat
    let recentNames: [String]
    let onSend: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager: ThemeManager?
    @Environment(\.accentFill) private var envAccentFill
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var betaName = ""

    private var appTheme: ReaderTheme { themeManager?.appTheme ?? .light }
    private var effectiveTint: Color { themeManager?.effectiveTint ?? envAccentFill }
    private var trimmedName: String { betaName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "Beta reader’s name",
                        text: $betaName,
                        prompt: appTheme.sepiaPrompt("e.g. Lark")
                    )
                    .accessibilityLabel("Beta reader’s name")
                    .onSubmit {
                        if !trimmedName.isEmpty { submit() }
                    }
                } header: {
                    Text("Who is this copy for?")
                } footer: {
                    Text("Each beta gets their own copy (\(format.rowTitle)) so their notes stay separate.")
                }
                .listRowBackground(appTheme.appElevatedBackground)

                if !recentNames.isEmpty {
                    Section("Used Before") {
                        FlowLayout(spacing: 8, rowSpacing: 8) {
                            ForEach(recentNames, id: \.self) { name in
                                recentNameChip(name)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(appTheme.appElevatedBackground)
                }
            }
            .scrollContentBackground(appTheme.appBaseBackground == nil ? .automatic : .hidden)
            .background((appTheme.appBaseBackground ?? Color.clear).ignoresSafeArea())
            .navigationTitle("Send a Copy")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { submit() }
                        .disabled(trimmedName.isEmpty)
                        .accessibilityLabel("Send copy to \(trimmedName.isEmpty ? "beta" : trimmedName)")
                }
            }
        }
    }

    private func recentNameChip(_ name: String) -> some View {
        let isSelected = trimmedName.caseInsensitiveCompare(name) == .orderedSame
        let shape = SubjectMetrics.controlShape(dynamicTypeSize)
        return Button {
            betaName = name
        } label: {
            Text(name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? ThemeManager.label(on: effectiveTint) : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(minHeight: 36)
                .background(
                    isSelected ? effectiveTint : appTheme.glassFill(0.10),
                    in: shape
                )
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Use beta name \(name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func submit() {
        let name = trimmedName
        guard !name.isEmpty else { return }
        dismiss()
        onSend(name)
    }
}
