import Foundation
import SwiftUI

/// Direct, form-free controls inside `FormatPanel` (`Editor-Format.dc.html`), mapping each
/// interactive control straight to its `FormatCommand`. Shared by the view and unit tests so
/// every command path stays verified.
nonisolated enum FormatPanelControl: Hashable, Sendable {
    case block(FormatBlock)
    case mark(FormatMark)
    case alignment(FormatAlignment)
    case direction(FormatDirection)
    case sceneBreak(SceneBreakStyle)
    case footnote
    case foldOutInsert
    case table
    case undo
    case redo
    case clearFormatting

    var command: FormatCommand {
        switch self {
        case let .block(block): .setBlock(block)
        case let .mark(mark): .toggleMark(mark)
        case let .alignment(alignment): .setAlignment(alignment)
        case let .direction(direction): .setDirection(direction)
        case let .sceneBreak(style): .insertSceneBreak(style)
        case .footnote: .insertFootnote
        case .foldOutInsert: .setBlock(.foldOut)
        case .table: .openTableInHTML
        case .undo: .undo
        case .redo: .redo
        case .clearFormatting: .clearFormatting
        }
    }

    static var allDirectControls: [FormatPanelControl] {
        FormatBlock.allCases.map(FormatPanelControl.block)
            + FormatMark.allCases.map(FormatPanelControl.mark)
            + FormatAlignment.allCases.map(FormatPanelControl.alignment)
            + FormatDirection.allCases.map(FormatPanelControl.direction)
            + SceneBreakStyle.allCases.map(FormatPanelControl.sceneBreak)
            + [.footnote, .foldOutInsert, .table, .undo, .redo, .clearFormatting]
    }
}

/// Native Format sheet (`Editor-Format.dc.html`): reflects a live `FormatState` and emits
/// `FormatCommand`s covering AO3's entire Rich Text feature set (§3.5).
struct FormatPanel: View {
    let state: FormatState
    let onCommand: (FormatCommand) -> Void
    let onAddNote: (() -> Void)?
    let onDismiss: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager: ThemeManager?
    @Environment(\.accentFill) private var envAccentFill
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showingLinkForm = false
    @State private var showingImageForm = false

    private var appTheme: ReaderTheme { themeManager?.appTheme ?? .light }
    private var effectiveTint: Color { themeManager?.effectiveTint ?? envAccentFill }
    private var accentInk: Color { themeManager?.accentInk ?? effectiveTint }

    init(
        state: FormatState,
        onCommand: @escaping (FormatCommand) -> Void,
        onAddNote: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.state = state
        self.onCommand = onCommand
        self.onAddNote = onAddNote
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    paragraphSection
                    textSection
                    insertSection
                    historyAndClearRow
                    footerNote
                }
                .padding(.horizontal, SubjectMetrics.gutter)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .background(appTheme.cardBackdrop.ignoresSafeArea())
            .navigationTitle("Format")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let onDismiss {
                            onDismiss()
                        } else {
                            dismiss()
                        }
                    }
                    .accessibilityLabel("Done")
                }
            }
        }
        .sheet(isPresented: $showingLinkForm) {
            FormatLinkFormSheet(
                initialDraft: FormatLinkDraft(
                    address: state.currentLinkURL ?? "",
                    isInLink: state.isInLink
                ),
                onCommand: onCommand
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingImageForm) {
            FormatImageFormSheet(onCommand: onCommand)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Paragraph section

    private var paragraphSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Paragraph")
            FlowLayout(spacing: 8, rowSpacing: 8) {
                ForEach(FormatBlock.allCases) { block in
                    blockChip(block)
                }
            }
        }
    }

    private func blockChip(_ block: FormatBlock) -> some View {
        let isSelected = state.block == block
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button {
            emit(.block(block))
        } label: {
            Text(block.title)
                .font(font(for: block))
                .foregroundStyle(isSelected ? ThemeManager.label(on: effectiveTint) : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(minHeight: 40)
                .background(isSelected ? effectiveTint : appTheme.cardSurface, in: shape)
                .overlay(
                    shape.strokeBorder(isSelected ? Color.clear : appTheme.cardBorder, lineWidth: 0.5)
                )
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(block.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func font(for block: FormatBlock) -> Font {
        switch block {
        case .body: .system(.subheadline, design: .serif)
        case .heading: .system(.headline, design: .serif).weight(.bold)
        case .subheading: .system(.subheadline, design: .serif).weight(.semibold)
        case .quote: .system(.subheadline, design: .serif).italic()
        case .centred, .bulletedList, .numberedList, .foldOut: .subheadline.weight(.medium)
        }
    }

    // MARK: - Text section

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Text")
            marksGrid
            alignmentBar
            directionBar
        }
    }

    private var marksGrid: some View {
        let columnCount = dynamicTypeSize.isAccessibilitySize ? 4 : 8
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: columnCount)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(FormatMark.allCases) { mark in
                markButton(mark)
            }
        }
        .padding(3)
        .background(appTheme.cardSurface, in: shape)
        .overlay(shape.strokeBorder(appTheme.cardBorder, lineWidth: 0.5))
    }

    private func markButton(_ mark: FormatMark) -> some View {
        let isActive = state.isActive(mark)
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return Button {
            emit(.mark(mark))
        } label: {
            markGlyphView(mark)
                .foregroundStyle(isActive ? accentInk : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(
                    isActive
                        ? effectiveTint.opacity(appTheme.isDarkFamily ? 0.28 : 0.14)
                        : Color.clear,
                    in: shape
                )
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mark.accessibilityLabel)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    @ViewBuilder
    private func markGlyphView(_ mark: FormatMark) -> some View {
        switch mark {
        case .bold:
            Text(mark.buttonGlyph).font(.body.weight(.heavy))
        case .italic:
            Text(mark.buttonGlyph).font(.system(.body, design: .serif).italic().weight(.semibold))
        case .underline:
            Text(mark.buttonGlyph).font(.body.weight(.semibold)).underline()
        case .strikethrough:
            Text(mark.buttonGlyph).font(.body.weight(.semibold)).strikethrough()
        case .superscript, .`subscript`:
            Text(mark.buttonGlyph).font(.subheadline.weight(.semibold))
        case .smaller:
            Text(mark.buttonGlyph).font(.footnote.weight(.semibold))
        case .code:
            Text(mark.buttonGlyph).font(.subheadline.weight(.semibold).monospaced())
        }
    }

    private var alignmentBar: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return HStack(spacing: 2) {
            ForEach(FormatAlignment.allCases) { alignment in
                let isSelected = state.alignment == alignment
                let itemShape = RoundedRectangle(cornerRadius: 9, style: .continuous)
                Button {
                    emit(.alignment(alignment))
                } label: {
                    Image(systemName: alignment.systemImage)
                        .font(.body.weight(.medium))
                        .foregroundStyle(isSelected ? accentInk : Color.primary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(
                            isSelected ? appTheme.glassFill(0.14) : Color.clear,
                            in: itemShape
                        )
                        .contentShape(itemShape)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(alignment.accessibilityLabel)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(appTheme.cardSurface, in: shape)
        .overlay(shape.strokeBorder(appTheme.cardBorder, lineWidth: 0.5))
    }

    private var directionBar: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 4))
            : AnyLayout(HStackLayout(spacing: 2))
        return layout {
            ForEach(FormatDirection.allCases) { direction in
                let isSelected = state.direction == direction
                let itemShape = RoundedRectangle(cornerRadius: 9, style: .continuous)
                Button {
                    emit(.direction(direction))
                } label: {
                    Text(direction.decoratedTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? accentInk : Color.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .padding(.horizontal, 8)
                        .background(
                            isSelected ? appTheme.glassFill(0.14) : Color.clear,
                            in: itemShape
                        )
                        .contentShape(itemShape)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(direction.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(appTheme.cardSurface, in: shape)
        .overlay(shape.strokeBorder(appTheme.cardBorder, lineWidth: 0.5))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote)
            .textCase(.uppercase)
            .foregroundStyle(.secondaryInk)
            .padding(.leading, 16)
            .accessibilityAddTraits(.isHeader)
    }

    private func emit(_ control: FormatPanelControl) {
        onCommand(control.command)
    }
}

// MARK: - Insert, history & footer sections

extension FormatPanel {
    private var insertSection: some View {
        let shape = RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Insert")
            VStack(spacing: 0) {
                sceneBreakRow
                rowDivider
                insertButtonRow(
                    title: "Link",
                    subtitle: state.isInLink
                        ? "Edit or remove this link"
                        : "Add, edit or remove a link",
                    systemImage: "link"
                ) {
                    showingLinkForm = true
                }
                rowDivider
                insertButtonRow(
                    title: "Footnote",
                    subtitle: "A numbered link to a note at the end, and back",
                    systemImage: "note.text"
                ) {
                    emit(.footnote)
                }
                rowDivider
                insertButtonRow(
                    title: "Image from a Web Address",
                    subtitle: "Address, description and size; AO3 doesn’t host images",
                    systemImage: "photo"
                ) {
                    showingImageForm = true
                }
                rowDivider
                insertButtonRow(
                    title: "Fold-out Section",
                    subtitle: "Readers tap to open it, e.g. a content note",
                    systemImage: "chevron.down.square"
                ) {
                    emit(.foldOutInsert)
                }
                rowDivider
                insertButtonRow(
                    title: "Table",
                    subtitle: "Opens in HTML view",
                    systemImage: "tablecells"
                ) {
                    emit(.table)
                }
                if let onAddNote {
                    rowDivider
                    insertButtonRow(
                        title: "Note",
                        subtitle: "Private note anchored to the selected text; never posted to AO3",
                        systemImage: "note.text.badge.plus",
                        action: onAddNote
                    )
                }
            }
            .background(appTheme.cardSurface, in: shape)
            .overlay(shape.strokeBorder(appTheme.cardBorder, lineWidth: 0.5))
        }
    }

    private var sceneBreakRow: some View {
        Menu {
            ForEach(SceneBreakStyle.allCases) { style in
                Button {
                    emit(.sceneBreak(style))
                } label: {
                    Text(style.title)
                }
                .accessibilityLabel(style.accessibilityLabel)
            }
        } label: {
            insertRowChrome(
                title: "Scene Break",
                subtitle: "Or * * *, or a line",
                systemImage: "ellipsis",
                trailingText: "⁂"
            )
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .accessibilityLabel("Scene Break. Choose asterism, asterisks, or a line")
    }

    private func insertButtonRow(
        title: String,
        subtitle: String,
        systemImage: String,
        trailingText: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            insertRowChrome(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage,
                trailingText: trailingText
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(subtitle)")
    }

    private func insertRowChrome(
        title: String,
        subtitle: String,
        systemImage: String,
        trailingText: String?
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(accentInk)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let trailingText {
                Text(trailingText)
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(.secondaryInk)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(appTheme.appSeparator ?? appTheme.glassStroke(0.10))
            .frame(height: 0.5)
            .padding(.leading, 50)
            .accessibilityHidden(true)
    }

    private var historyAndClearRow: some View {
        FlowLayout(spacing: 10, rowSpacing: 10) {
            historyButton(
                systemImage: "arrow.uturn.backward",
                label: "Undo",
                isEnabled: state.canUndo,
                control: .undo
            )
            historyButton(
                systemImage: "arrow.uturn.forward",
                label: "Redo",
                isEnabled: state.canRedo,
                control: .redo
            )
            clearFormattingButton
        }
    }

    private func historyButton(
        systemImage: String,
        label: String,
        isEnabled: Bool,
        control: FormatPanelControl
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button {
            emit(control)
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.primary)
                .frame(minWidth: 44, minHeight: 44)
                .background(appTheme.cardSurface, in: shape)
                .overlay(shape.strokeBorder(appTheme.cardBorder, lineWidth: 0.5))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }

    private var clearFormattingButton: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button {
            emit(.clearFormatting)
        } label: {
            Text("Clear Formatting")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(appTheme.cardSurface, in: shape)
                .overlay(shape.strokeBorder(appTheme.cardBorder, lineWidth: 0.5))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear Formatting")
    }

    private var footerNote: some View {
        Text(
            "Everything AO3’s own editor offers, item for item, and the HTML view for anything else "
                + "AO3 accepts. Nothing here gets removed when you post."
        )
        .font(.caption)
        .foregroundStyle(.secondaryInk)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 4)
    }
}

#Preview("Format Panel") {
    FormatPanel(
        state: FormatState(
            activeMarks: [.italic],
            block: .quote,
            alignment: .left,
            direction: .leftToRight,
            canUndo: true,
            canRedo: false,
            isInLink: true,
            currentLinkURL: "https://archiveofourown.org"
        ),
        onCommand: { _ in }
    )
    .environment(ThemeManager())
}
