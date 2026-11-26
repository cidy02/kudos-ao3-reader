import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Actions emitted by `WritingKeysBar` (`Editor-Typing.dc.html`).
nonisolated enum WritingKeyAction: Equatable, Hashable, Sendable {
    case toggleItalic
    case toggleBold
    case insertSceneBreak
    case insertEmDash
    case insertQuotationMarks
    case moveCursorLeft
    case moveCursorRight
    case undo
    case redo
    case openFormat

    /// Maps formatting keys straight to `FormatCommand`; cursor/punctuation/sheet keys return `nil`.
    var formatCommand: FormatCommand? {
        switch self {
        case .toggleItalic: .toggleMark(.italic)
        case .toggleBold: .toggleMark(.bold)
        case .insertSceneBreak: .insertSceneBreak(.asterism)
        case .undo: .undo
        case .redo: .redo
        case .insertEmDash, .insertQuotationMarks, .moveCursorLeft, .moveCursorRight, .openFormat:
            nil
        }
    }
}

/// Ordered keys on `WritingKeysBar` matching `Editor-Typing.dc.html` left to right.
nonisolated enum WritingKeyID: String, CaseIterable, Identifiable, Hashable, Sendable {
    case italic
    case bold
    case sceneBreak
    case emDash
    case quotationMarks
    case cursorLeft
    case cursorRight
    case undo
    case format

    var id: String { rawValue }

    var accessibilityLabel: String {
        switch self {
        case .italic: "Italic"
        case .bold: "Bold"
        case .sceneBreak: "Scene break"
        case .emDash: "Em dash"
        case .quotationMarks: "Quotation marks"
        case .cursorLeft: "Move cursor left"
        case .cursorRight: "Move cursor right"
        case .undo: "Undo"
        case .format: "Format"
        }
    }

    func accessibilityHint(for state: FormatState) -> String? {
        if self == .undo, state.canRedo {
            return "Press and hold for redo"
        }
        return nil
    }

    func isHighlighted(in state: FormatState) -> Bool {
        switch self {
        case .italic: state.isActive(.italic)
        case .bold: state.isActive(.bold)
        default: false
        }
    }

    func isEnabled(in state: FormatState) -> Bool {
        switch self {
        case .undo: state.canUndo || state.canRedo
        default: true
        }
    }

    /// Action emitted by tapping this key given the editor's current `FormatState`.
    func tapAction(in state: FormatState) -> WritingKeyAction? {
        switch self {
        case .italic: .toggleItalic
        case .bold: .toggleBold
        case .sceneBreak: .insertSceneBreak
        case .emDash: .insertEmDash
        case .quotationMarks: .insertQuotationMarks
        case .cursorLeft: .moveCursorLeft
        case .cursorRight: .moveCursorRight
        case .undo: state.canUndo ? .undo : nil
        case .format: .openFormat
        }
    }

    /// Action emitted by long-pressing this key (Undo long-presses to Redo).
    func longPressAction(in state: FormatState) -> WritingKeyAction? {
        if self == .undo, state.canRedo {
            return .redo
        }
        return nil
    }
}

/// Keyboard accessory bar (`Editor-Typing.dc.html`): italic, bold, scene break, em dash,
/// quotation marks, cursor left/right, undo (long-press for redo), and Format (`Aa`), with
/// a leading slot reserved for story-note name suggestions (`Editor-Names.dc.html`).
struct WritingKeysBar<LeadingSlot: View>: View {
    let formatState: FormatState
    let showsLeadingContent: Bool
    let onAction: (WritingKeyAction) -> Void
    @ViewBuilder let leadingSlot: () -> LeadingSlot

    @Environment(ThemeManager.self) private var themeManager: ThemeManager?
    @Environment(\.accentFill) private var envAccentFill
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var appTheme: ReaderTheme { themeManager?.appTheme ?? .light }
    private var effectiveTint: Color { themeManager?.effectiveTint ?? envAccentFill }
    private var accentInk: Color { themeManager?.accentInk ?? effectiveTint }

    init(
        formatState: FormatState = FormatState(),
        showsLeadingContent: Bool = false,
        onAction: @escaping (WritingKeyAction) -> Void,
        @ViewBuilder leadingSlot: @escaping () -> LeadingSlot
    ) {
        self.formatState = formatState
        self.showsLeadingContent = showsLeadingContent
        self.onAction = onAction
        self.leadingSlot = leadingSlot
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        leadingSlot()
                        if showsLeadingContent {
                            leadingSeparator
                        }
                        ForEach(WritingKeyID.allCases) { key in
                            keyControl(key, fillsWidth: false)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
            } else if showsLeadingContent {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        leadingSlot()
                        leadingSeparator
                        ForEach(WritingKeyID.allCases) { key in
                            keyControl(key, fillsWidth: false)
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .frame(height: 48)
            } else {
                HStack(spacing: 2) {
                    leadingSlot()
                    ForEach(WritingKeyID.allCases) { key in
                        keyControl(key, fillsWidth: true)
                    }
                }
                .padding(.horizontal, 4)
                .frame(height: 48)
            }
        }
        .background(barBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(appTheme.appSeparator ?? appTheme.glassStroke(0.16))
                .frame(height: 0.5)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Writing keys")
    }

    private var leadingSeparator: some View {
        Rectangle()
            .fill(appTheme.appSeparator ?? appTheme.glassStroke(0.22))
            .frame(width: 0.5, height: 22)
            .padding(.horizontal, 2)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var barBackground: some View {
        if let elevated = appTheme.appElevatedBackground {
            elevated
        } else {
            Rectangle().fill(.bar)
        }
    }

    @ViewBuilder
    private func keyControl(_ key: WritingKeyID, fillsWidth: Bool) -> some View {
        if key == .undo {
            undoKeyButton(fillsWidth: fillsWidth)
        } else {
            standardKeyButton(key, fillsWidth: fillsWidth)
        }
    }

    private func standardKeyButton(_ key: WritingKeyID, fillsWidth: Bool) -> some View {
        let highlighted = key.isHighlighted(in: formatState)
        return Button {
            if let action = key.tapAction(in: formatState) {
                trigger(action)
            }
        } label: {
            keyChrome(key, highlighted: highlighted, fillsWidth: fillsWidth)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(key.accessibilityLabel)
        .accessibilityAddTraits(highlighted ? .isSelected : [])
    }

    private func undoKeyButton(fillsWidth: Bool) -> some View {
        let enabled = WritingKeyID.undo.isEnabled(in: formatState)
        return Button {
            if let action = WritingKeyID.undo.tapAction(in: formatState) {
                trigger(action)
            }
        } label: {
            keyChrome(.undo, highlighted: false, fillsWidth: fillsWidth)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in
                    if let action = WritingKeyID.undo.longPressAction(in: formatState) {
                        trigger(action)
                    }
                },
            isEnabled: formatState.canRedo
        )
        .accessibilityLabel(WritingKeyID.undo.accessibilityLabel)
        .accessibilityHint(WritingKeyID.undo.accessibilityHint(for: formatState) ?? "")
        .accessibilityAction(named: "Redo") {
            if let action = WritingKeyID.undo.longPressAction(in: formatState) {
                trigger(action)
            }
        }
    }

    private func keyChrome(_ key: WritingKeyID, highlighted: Bool, fillsWidth: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return keyGlyph(key)
            .foregroundStyle(highlighted ? accentInk : Color.primary)
            .padding(.horizontal, fillsWidth ? 2 : 10)
            .frame(
                minWidth: fillsWidth ? nil : 44,
                maxWidth: fillsWidth ? .infinity : nil,
                minHeight: fillsWidth ? 38 : 44
            )
            .background(
                highlighted
                    ? effectiveTint.opacity(appTheme.isDarkFamily ? 0.28 : 0.14)
                    : Color.clear,
                in: shape
            )
            .contentShape(shape)
    }

    @ViewBuilder
    private func keyGlyph(_ key: WritingKeyID) -> some View {
        switch key {
        case .italic:
            Text("I")
                .font(.system(.title3, design: .serif).italic().weight(.semibold))
        case .bold:
            Text("B")
                .font(.title3.weight(.heavy))
        case .sceneBreak:
            Text("⁂")
                .font(.system(.title3, design: .serif))
        case .emDash:
            Text("—")
                .font(.title3)
        case .quotationMarks:
            Text("“ ”")
                .font(.system(.body, design: .serif))
        case .cursorLeft:
            Image(systemName: "chevron.left")
                .font(.body.weight(.medium))
        case .cursorRight:
            Image(systemName: "chevron.right")
                .font(.body.weight(.medium))
        case .undo:
            Image(systemName: "arrow.uturn.backward")
                .font(.body.weight(.medium))
        case .format:
            Text("Aa")
                .font(.system(.body, design: .serif).weight(.semibold))
        }
    }

    private func trigger(_ action: WritingKeyAction) {
        #if os(iOS)
        UIDevice.current.playInputClick()
        #endif
        onAction(action)
    }
}

extension WritingKeysBar where LeadingSlot == EmptyView {
    /// Default keys bar with an empty leading slot (reserved for story-note name suggestions).
    init(
        formatState: FormatState = FormatState(),
        onAction: @escaping (WritingKeyAction) -> Void
    ) {
        self.init(formatState: formatState, onAction: onAction, leadingSlot: { EmptyView() })
    }
}

#if os(iOS)
/// `UIInputView` wrapper hosting `WritingKeysBar` so the WebView/text editor host can install
/// it directly as an `inputAccessoryView` (plan §10.3 N3).
@MainActor
final class WritingKeysInputAccessoryView: UIInputView, UIInputViewAudioFeedback {
    // fileprivate, not private: @Observable's generated conformance extension sits at file scope.
    @Observable
    fileprivate final class StateBox {
        var formatState: FormatState
        var onAction: (WritingKeyAction) -> Void
        var leadingSlotView: AnyView
        var hasLeadingContent: Bool

        init(
            formatState: FormatState,
            onAction: @escaping (WritingKeyAction) -> Void,
            leadingSlotView: AnyView,
            hasLeadingContent: Bool
        ) {
            self.formatState = formatState
            self.onAction = onAction
            self.leadingSlotView = leadingSlotView
            self.hasLeadingContent = hasLeadingContent
        }
    }

    private struct HostedBar: View {
        let stateBox: StateBox

        var body: some View {
            WritingKeysBar(
                formatState: stateBox.formatState,
                showsLeadingContent: stateBox.hasLeadingContent,
                onAction: { action in stateBox.onAction(action) },
                leadingSlot: { stateBox.leadingSlotView }
            )
        }
    }

    private let stateBox: StateBox
    private let hostingController: UIViewController

    var enableInputClicksWhenVisible: Bool { true }

    var formatState: FormatState {
        get { stateBox.formatState }
        set { update(formatState: newValue) }
    }

    var hasLeadingContent: Bool {
        stateBox.hasLeadingContent
    }

    convenience init<LeadingSlot: View>(
        formatState: FormatState = FormatState(),
        themeManager: ThemeManager? = nil,
        onAction: @escaping (WritingKeyAction) -> Void,
        @ViewBuilder leadingSlot: () -> LeadingSlot
    ) {
        self.init(
            formatState: formatState,
            themeManager: themeManager,
            onAction: onAction,
            leadingSlotView: AnyView(leadingSlot()),
            hasLeadingContent: LeadingSlot.self != EmptyView.self
        )
    }

    init(
        formatState: FormatState = FormatState(),
        themeManager: ThemeManager? = nil,
        onAction: @escaping (WritingKeyAction) -> Void,
        leadingSlotView: AnyView = AnyView(EmptyView()),
        hasLeadingContent: Bool = false
    ) {
        let box = StateBox(
            formatState: formatState,
            onAction: onAction,
            leadingSlotView: leadingSlotView,
            hasLeadingContent: hasLeadingContent
        )
        self.stateBox = box

        let rootView = HostedBar(stateBox: box)
        let host: UIHostingController<AnyView>
        if let themeManager {
            host = UIHostingController(rootView: AnyView(rootView.environment(themeManager)))
        } else {
            host = UIHostingController(rootView: AnyView(rootView))
        }
        host.sizingOptions = [.intrinsicContentSize]
        host.view.backgroundColor = .clear
        self.hostingController = host

        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 48), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        autoresizingMask = [.flexibleWidth, .flexibleHeight]

        host.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.view.topAnchor.constraint(equalTo: topAnchor),
            host.view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Updates active marks and undo/redo availability in place without rebuilding the view.
    func update(formatState: FormatState) {
        stateBox.formatState = formatState
        invalidateIntrinsicContentSize()
    }

    /// Updates the keys bar's leading slot (e.g. story-note name chips) in place.
    func updateLeadingSlot<LeadingSlot: View>(
        hasContent: Bool = true,
        @ViewBuilder _ content: () -> LeadingSlot
    ) {
        stateBox.hasLeadingContent = hasContent
        stateBox.leadingSlotView = AnyView(content())
        invalidateIntrinsicContentSize()
    }

    /// Removes any leading slot content so the standard writing keys fill the bar again.
    func clearLeadingSlot() {
        guard stateBox.hasLeadingContent else { return }
        stateBox.hasLeadingContent = false
        stateBox.leadingSlotView = AnyView(EmptyView())
        invalidateIntrinsicContentSize()
    }
}
#endif

#Preview("Writing Keys Bar") {
    VStack {
        Spacer()
        WritingKeysBar(
            formatState: FormatState(activeMarks: [.italic], canUndo: true, canRedo: true),
            onAction: { _ in }
        )
    }
    .environment(ThemeManager())
}
