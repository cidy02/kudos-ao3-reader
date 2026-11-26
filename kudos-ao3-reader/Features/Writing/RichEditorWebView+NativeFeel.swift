import Foundation
import SwiftUI
import WebKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Native-feel implementation for `RichEditorWebView` (plan §10.3 N2–N8):
/// keys accessory installation, edit menu, hardware keyboard shortcuts,
/// system Find, trait-driven appearance, native scrolling, and undo routing.
extension RichEditorWebView {
    func configureNativeFeel() {
        richUndoManager.configureHandlers(
            onUndo: { [weak self] in self?.emitCommand(.format(.undo)) },
            onRedo: { [weak self] in self?.emitCommand(.format(.redo)) }
        )

        #if os(iOS)
        // N4: WKWebView's own UIScrollView handles scrolling, status-bar-to-top,
        // and interactive keyboard dismissal.
        scrollView.isScrollEnabled = true
        scrollView.alwaysBounceVertical = true
        scrollView.scrollsToTop = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.showsHorizontalScrollIndicator = false

        // N8: native iOS system Find interaction.
        isFindInteractionEnabled = true

        // N5: push appearance whenever Dark Mode, Increase Contrast, Bold Text,
        // or Dynamic Type changes.
        traitChangeRegistration = registerForTraitChanges([
            UITraitUserInterfaceStyle.self,
            UITraitAccessibilityContrast.self,
            UITraitLegibilityWeight.self,
            UITraitPreferredContentSizeCategory.self,
        ]) { (view: RichEditorWebView, _: UITraitCollection) in
            view.notifyAppearanceChanged()
        }
        #endif
    }

    func emitCommand(_ command: RichEditorHostCommand) {
        onCommand?(command)
    }

    /// Updates undo/redo availability, page-supplied step titles (N6), and the
    /// keys bar's live formatting state (N3).
    func syncToolbarState(_ state: RichEditorToolbarState) {
        richUndoManager.update(
            canUndo: state.canUndo,
            canRedo: state.canRedo,
            undoTitle: state.undoTitle,
            redoTitle: state.redoTitle
        )
        #if os(iOS)
        keysAccessoryView?.update(formatState: state.toFormatState())
        #endif
    }

    /// Updates typography defaults and pushes the merged appearance message (N5).
    func updateTypography(fontFamily: String, baseFontSize: Double, lineHeight: Double) {
        typographyFontFamily = fontFamily
        typographyBaseFontSize = baseFontSize
        typographyLineHeight = lineHeight
        notifyAppearanceChanged()
    }

    func notifyAppearanceChanged() {
        onAppearanceChange?(currentAppearance())
    }

    // MARK: N4 scrolling

    /// Scrolls the web view's own scroll view so `caret` remains visible (or stays
    /// pinned at `typewriterAnchorFraction` in `.typewriter` mode).
    @discardableResult
    func scrollCaretIntoView(_ caret: RichEditorCaretRect, animated: Bool = true) -> Bool {
        #if os(iOS)
        let insets = scrollView.adjustedContentInset
        guard let targetY = RichEditorScrollCalculator.targetOffsetY(
            caret: caret,
            currentOffsetY: Double(scrollView.contentOffset.y),
            viewportHeight: Double(scrollView.bounds.height),
            contentHeight: Double(scrollView.contentSize.height),
            topInset: Double(insets.top),
            bottomInset: Double(insets.bottom),
            mode: scrollMode,
            typewriterFraction: typewriterAnchorFraction
        ) else {
            return false
        }
        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: CGFloat(targetY)),
            animated: animated
        )
        return true
        #else
        guard let clipView = enclosingScrollView?.contentView else { return false }
        let contentHeight = Double(enclosingScrollView?.documentView?.bounds.height ?? bounds.height)
        guard let targetY = RichEditorScrollCalculator.targetOffsetY(
            caret: caret,
            currentOffsetY: Double(clipView.bounds.origin.y),
            viewportHeight: Double(clipView.bounds.height),
            contentHeight: contentHeight,
            mode: scrollMode,
            typewriterFraction: typewriterAnchorFraction
        ) else {
            return false
        }
        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: CGFloat(targetY)))
        enclosingScrollView?.reflectScrolledClipView(clipView)
        return true
        #endif
    }

    // MARK: N5 appearance

    func currentAppearance() -> RichEditorAppearance {
        #if os(iOS)
        Self.appearance(
            for: traitCollection,
            fontFamily: typographyFontFamily,
            baseFontSize: typographyBaseFontSize,
            lineHeight: typographyLineHeight
        )
        #else
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return RichEditorAppearance(
            fontFamily: typographyFontFamily,
            fontSizePx: typographyBaseFontSize,
            lineHeight: typographyLineHeight,
            contentSizeCategory: "macOS",
            isAccessibilityCategory: false,
            colorScheme: isDark ? "dark" : "light",
            increaseContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
            boldText: false
        )
        #endif
    }

    // MARK: N8 Find

    /// Presents the system Find navigator (N8) and notifies the command sink.
    func presentFindNavigator(showingReplace: Bool = false) {
        #if os(iOS)
        if isFindInteractionEnabled {
            findInteraction?.presentFindNavigator(showingReplace: showingReplace)
        }
        #endif
        emitCommand(.presentFind)
    }

    // MARK: Shared Objective-C command selectors (N2, N6, N7, N8)

    @objc func editorToggleBold(_: Any?) {
        emitCommand(.format(.toggleMark(.bold)))
    }

    @objc func editorToggleItalic(_: Any?) {
        emitCommand(.format(.toggleMark(.italic)))
    }

    @objc func editorToggleUnderline(_: Any?) {
        emitCommand(.format(.toggleMark(.underline)))
    }

    @objc func editorInsertLink(_: Any?) {
        emitCommand(.requestLink)
    }

    @objc func editorAddNote(_: Any?) {
        emitCommand(.requestNote)
    }

    @objc func editorPresentFind(_: Any?) {
        presentFindNavigator(showingReplace: false)
    }

    @objc func editorUndo(_: Any?) {
        emitCommand(.format(.undo))
    }

    @objc func editorRedo(_: Any?) {
        emitCommand(.format(.redo))
    }

    #if os(iOS)
    /// Pure iOS trait-collection mapping for N5 (supports Dynamic Type up to AX5).
    static func appearance(
        for traits: UITraitCollection,
        fontFamily: String = RichEditorTheme.defaultFontFamily,
        baseFontSize: Double = 15.5,
        lineHeight: Double = RichEditorTheme.defaultLineHeight
    ) -> RichEditorAppearance {
        let category = traits.preferredContentSizeCategory
        let scaledSize = Double(
            UIFontMetrics(forTextStyle: .body)
                .scaledValue(for: CGFloat(baseFontSize), compatibleWith: traits)
        )
        return RichEditorAppearance(
            fontFamily: fontFamily,
            fontSizePx: scaledSize,
            lineHeight: lineHeight,
            contentSizeCategory: category.rawValue,
            isAccessibilityCategory: category.isAccessibilityCategory,
            colorScheme: traits.userInterfaceStyle == .dark ? "dark" : "light",
            increaseContrast: traits.accessibilityContrast == .high,
            boldText: traits.legibilityWeight == .bold
        )
    }

    /// Installs `WritingKeysInputAccessoryView` over WebKit's form bar (N3).
    @discardableResult
    func installKeysAccessory(
        themeManager: ThemeManager? = nil,
        contentViewProvider: ((WKWebView) -> UIView?)? = nil,
        verify: ((UIView, UIView) -> Bool)? = nil,
        fallbackLogSink: ((String) -> Void)? = nil
    ) -> RichEditorInputAccessoryStatus {
        let accessory = keysAccessoryView ?? WritingKeysInputAccessoryView(
            themeManager: themeManager,
            onAction: { [weak self] action in
                self?.emitCommand(RichEditorHostCommand.from(action))
            }
        )
        keysAccessoryView = accessory
        let status = RichEditorInputAccessoryInstaller.install(
            accessoryView: accessory,
            on: self,
            undoOwner: self,
            contentViewProvider: contentViewProvider,
            verify: verify,
            fallbackLogSink: fallbackLogSink
        )
        inputAccessoryStatus = status
        return status
    }

    // MARK: N7 hardware keyboard commands

    func makeEditorKeyCommands() -> [UIKeyCommand] {
        RichEditorKeyCommandSpec.all.map { spec in
            let title: String
            let selector: Selector
            switch spec.command {
            case .format(.toggleMark(.bold)):
                title = spec.title
                selector = #selector(editorToggleBold(_:))
            case .format(.toggleMark(.italic)):
                title = spec.title
                selector = #selector(editorToggleItalic(_:))
            case .format(.toggleMark(.underline)):
                title = spec.title
                selector = #selector(editorToggleUnderline(_:))
            case .requestLink:
                title = spec.title
                selector = #selector(editorInsertLink(_:))
            case .presentFind:
                title = spec.title
                selector = #selector(editorPresentFind(_:))
            case .format(.undo):
                title = richUndoManager.undoMenuItemTitle
                selector = #selector(editorUndo(_:))
            case .format(.redo):
                title = richUndoManager.redoMenuItemTitle
                selector = #selector(editorRedo(_:))
            default:
                title = spec.title
                selector = #selector(editorToggleBold(_:))
            }
            let modifiers: UIKeyModifierFlags = spec.requiresShift ? [.command, .shift] : .command
            let command = UIKeyCommand(
                title: title,
                action: selector,
                input: spec.input,
                modifierFlags: modifiers
            )
            command.discoverabilityTitle = title
            command.wantsPriorityOverSystemBehavior = true
            return command
        }
    }

    // MARK: N2 edit menu & N6 undo titles

    func configureEditMenu(using builder: any RichEditorMenuBuilding) {
        for identifier in RichEditorMenuID.removedBrowserMenus {
            builder.remove(menu: identifier)
        }

        var formattingItems: [UIMenuElement] = [
            UICommand(
                title: "Bold",
                image: UIImage(systemName: "bold"),
                action: #selector(editorToggleBold(_:))
            ),
            UICommand(
                title: "Italic",
                image: UIImage(systemName: "italic"),
                action: #selector(editorToggleItalic(_:))
            ),
            UICommand(
                title: "Underline",
                image: UIImage(systemName: "underline"),
                action: #selector(editorToggleUnderline(_:))
            ),
            UICommand(
                title: "Link",
                image: UIImage(systemName: "link"),
                action: #selector(editorInsertLink(_:))
            ),
        ]
        if offersNoteCommand {
            formattingItems.append(UICommand(
                title: "Note",
                image: UIImage(systemName: "note.text.badge.plus"),
                action: #selector(editorAddNote(_:))
            ))
        }
        let formattingMenu = UIMenu(
            title: "",
            image: nil,
            identifier: RichEditorMenuID.formatting,
            options: .displayInline,
            children: formattingItems
        )

        if builder.hasMenu(for: .standardEdit) {
            builder.insertSibling(formattingMenu, afterMenu: .standardEdit)
        } else if builder.hasMenu(for: .format) {
            builder.insertChild(formattingMenu, atStartOfMenu: .format)
        } else if builder.hasMenu(for: .root) {
            builder.insertChild(formattingMenu, atEndOfMenu: .root)
        }

        if ownsRichUndo, builder.hasMenu(for: .undoRedo) {
            let undoCommand = UICommand(
                title: richUndoManager.undoMenuItemTitle,
                image: UIImage(systemName: "arrow.uturn.backward"),
                action: #selector(editorUndo(_:))
            )
            if !richUndoManager.canUndo { undoCommand.attributes = .disabled }

            let redoCommand = UICommand(
                title: richUndoManager.redoMenuItemTitle,
                image: UIImage(systemName: "arrow.uturn.forward"),
                action: #selector(editorRedo(_:))
            )
            if !richUndoManager.canRedo { redoCommand.attributes = .disabled }

            builder.replaceChildren(ofMenu: .undoRedo) { _ in
                [undoCommand, redoCommand]
            }
        }
    }

    func canPerformEditorAction(_ action: Selector) -> Bool? {
        switch action {
        case #selector(editorToggleBold(_:)),
             #selector(editorToggleItalic(_:)),
             #selector(editorToggleUnderline(_:)),
             #selector(editorInsertLink(_:)),
             #selector(editorPresentFind(_:)):
            return true
        case #selector(editorAddNote(_:)):
            return offersNoteCommand
        case #selector(editorUndo(_:)):
            return ownsRichUndo && richUndoManager.canUndo
        case #selector(editorRedo(_:)):
            return ownsRichUndo && richUndoManager.canRedo
        default:
            return nil
        }
    }

    func validateEditorCommand(_ command: UICommand) {
        if command.action == #selector(editorUndo(_:)) {
            command.title = richUndoManager.undoMenuItemTitle
            command.attributes = (ownsRichUndo && richUndoManager.canUndo) ? [] : .disabled
        } else if command.action == #selector(editorRedo(_:)) {
            command.title = richUndoManager.redoMenuItemTitle
            command.attributes = (ownsRichUndo && richUndoManager.canRedo) ? [] : .disabled
        }
    }
    #endif
}
