import Foundation
import SwiftUI
import Testing
import WebKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif
@testable import Kudos

@MainActor
struct RichEditorNativeFeelTests {
    @Test func keysBarActionsMapToFormatCommandsAndCaretMoves() {
        #expect(RichEditorHostCommand.from(.toggleBold) == .format(.toggleMark(.bold)))
        #expect(RichEditorHostCommand.from(.toggleItalic) == .format(.toggleMark(.italic)))
        #expect(
            RichEditorHostCommand.from(.insertSceneBreak)
                == .format(.insertSceneBreak(.asterism))
        )
        #expect(RichEditorHostCommand.from(.undo) == .format(.undo))
        #expect(RichEditorHostCommand.from(.redo) == .format(.redo))
        #expect(RichEditorHostCommand.from(.moveCursorLeft) == .moveCaret(.left))
        #expect(RichEditorHostCommand.from(.moveCursorRight) == .moveCaret(.right))
        #expect(RichEditorHostCommand.from(.insertEmDash) == .insertEmDash)
        #expect(RichEditorHostCommand.from(.insertQuotationMarks) == .insertQuotationMarks)
        #expect(RichEditorHostCommand.from(.openFormat) == .openFormatPanel)
    }

    @Test func fallbackLogOnceFiresAtMostOncePerLaunch() {
        RichEditorInputAccessoryInstaller.resetFallbackLogForTesting()
        defer { RichEditorInputAccessoryInstaller.resetFallbackLogForTesting() }

        var messages: [String] = []
        let first = RichEditorInputAccessoryInstaller.logFallbackOnce(reason: "test-first") {
            messages.append($0)
        }
        let second = RichEditorInputAccessoryInstaller.logFallbackOnce(reason: "test-second") {
            messages.append($0)
        }

        #expect(first)
        #expect(!second)
        #expect(messages.count == 1)
        #expect(messages.first?.contains("test-first") == true)
    }

    @Test func keyCommandCatalogCoversAllSevenN7Shortcuts() {
        let specs = RichEditorKeyCommandSpec.all
        #expect(specs.count == 7)
        let expected: [(String, Bool, RichEditorHostCommand)] = [
            ("b", false, .format(.toggleMark(.bold))),
            ("i", false, .format(.toggleMark(.italic))),
            ("u", false, .format(.toggleMark(.underline))),
            ("k", false, .requestLink),
            ("f", false, .presentFind),
            ("z", false, .format(.undo)),
            ("z", true, .format(.redo)),
        ]
        for (input, shift, command) in expected {
            #expect(specs.contains {
                $0.input == input && $0.requiresShift == shift && $0.command == command
            })
        }
    }

    @Test func systemUndoManagerRoutesToSinkAndFormatsPageSuppliedTitles() {
        let host = RichEditorHost(backgroundColor: .white)
        defer { host.teardown() }

        var received: [RichEditorHostCommand] = []
        host.onCommand = { received.append($0) }

        // While HTML owns the text, the web view does not hijack system undo (U1).
        #expect(host.webView.undoManager !== host.webView.richUndoManager)

        host.setOwnsRichUndo(true)
        #expect(host.webView.undoManager === host.webView.richUndoManager)

        host.syncToolbarState(RichEditorToolbarState(
            marks: ["strong"],
            block: "paragraph",
            align: nil,
            dir: nil,
            canUndo: true,
            canRedo: true,
            undoTitle: "Bold",
            redoTitle: "Typing"
        ))
        #expect(host.webView.richUndoManager.canUndo)
        #expect(host.webView.richUndoManager.canRedo)
        #expect(host.webView.richUndoManager.undoMenuItemTitle == "Undo Bold")
        #expect(host.webView.richUndoManager.redoMenuItemTitle == "Redo Typing")

        host.webView.undoManager?.undo()
        host.webView.undoManager?.redo()
        #expect(received == [.format(.undo), .format(.redo)])

        // Nil/blank titles fall back to plain "Undo" / "Redo"; pre-prefixed titles don't double-prefix.
        #expect(RichEditorUndoTitleFormatter.undoMenuTitle(for: nil) == "Undo")
        #expect(RichEditorUndoTitleFormatter.undoMenuTitle(for: "  ") == "Undo")
        #expect(RichEditorUndoTitleFormatter.undoMenuTitle(for: "Undo Paste") == "Undo Paste")
        #expect(RichEditorUndoTitleFormatter.redoMenuTitle(for: "Format") == "Redo Format")
    }

    #if os(iOS)
    @Test func inputAccessoryReplacementVerifiesOverrideOnTargetView() {
        RichEditorInputAccessoryInstaller.resetFallbackLogForTesting()
        defer { RichEditorInputAccessoryInstaller.resetFallbackLogForTesting() }

        let target = UIView()
        let accessory = WritingKeysInputAccessoryView(onAction: { _ in })
        var logged: [String] = []

        let status = RichEditorInputAccessoryInstaller.install(
            accessoryView: accessory,
            onTarget: target,
            fallbackLogSink: { logged.append($0) }
        )

        #expect(status == .replaced)
        #expect(!status.usesFallbackBar)
        #expect(target.inputAccessoryView === accessory)
        #expect(logged.isEmpty)
    }

    @Test func inputAccessoryMissingContentViewOrFailedVerificationFallsBackAndLogsOnce() {
        RichEditorInputAccessoryInstaller.resetFallbackLogForTesting()
        defer { RichEditorInputAccessoryInstaller.resetFallbackLogForTesting() }

        let host = RichEditorHost(backgroundColor: .white)
        defer { host.teardown() }

        var logged: [String] = []
        let missingStatus = host.webView.installKeysAccessory(
            contentViewProvider: { _ in nil },
            fallbackLogSink: { logged.append($0) }
        )
        #expect(missingStatus == .fallback(reason: "content-view-missing"))
        #expect(missingStatus.usesFallbackBar)
        #expect(logged.count == 1)

        // A second failure in the same launch falls back without spamming logs.
        let target = UIView()
        let failedVerify = RichEditorInputAccessoryInstaller.install(
            accessoryView: WritingKeysInputAccessoryView(onAction: { _ in }),
            onTarget: target,
            verify: { _, _ in false },
            fallbackLogSink: { logged.append($0) }
        )
        #expect(failedVerify == .fallback(reason: "verification-mismatch"))
        #expect(failedVerify.usesFallbackBar)
        #expect(logged.count == 1)
    }

    @Test func editMenuAddsBoldItalicUnderlineLinkRemovesBrowserMenusAndReflectsUndoTitle() throws {
        let host = RichEditorHost(backgroundColor: .white)
        defer { host.teardown() }

        var received: [RichEditorHostCommand] = []
        host.onCommand = { received.append($0) }
        host.setOwnsRichUndo(true)
        host.syncToolbarState(RichEditorToolbarState(
            marks: [],
            block: "paragraph",
            align: nil,
            dir: nil,
            canUndo: true,
            canRedo: false,
            undoTitle: "Typing",
            redoTitle: nil
        ))

        let builder = FakeMenuBuilder(presentMenus: [.standardEdit, .undoRedo, .share, .lookup, .open, .textStyle])
        host.webView.configureEditMenu(using: builder)

        // Browser-style and duplicate WebKit formatting menus were removed.
        #expect(builder.removedMenus == RichEditorMenuID.removedBrowserMenus)

        // Formatting menu was inserted right after `.standardEdit` with Bold/Italic/Underline/Link.
        let inserted = try #require(builder.insertedAfter[.standardEdit])
        #expect(inserted.identifier == RichEditorMenuID.formatting)
        let formatCommands = inserted.children.compactMap { $0 as? UICommand }
        #expect(formatCommands.map(\.title) == ["Bold", "Italic", "Underline", "Link"])

        for command in formatCommands {
            _ = host.webView.perform(command.action, with: command)
        }
        #expect(received == [
            .format(.toggleMark(.bold)),
            .format(.toggleMark(.italic)),
            .format(.toggleMark(.underline)),
            .requestLink,
        ])

        // Undo/Redo menu reflects page-supplied undo title and enabled/disabled state (N6).
        let undoItems = try #require(builder.replacedChildren[.undoRedo]?.compactMap { $0 as? UICommand })
        #expect(undoItems.map(\.title) == ["Undo Typing", "Redo"])
        #expect(undoItems[0].attributes == [])
        #expect(undoItems[1].attributes == .disabled)
        _ = host.webView.perform(undoItems[0].action, with: undoItems[0])
        #expect(received.last == .format(.undo))
    }

    @Test func hardwareKeyCommandsAreDiscoverableEnableFindAndEmitToSink() throws {
        let host = RichEditorHost(backgroundColor: .white)
        defer { host.teardown() }

        #expect(host.webView.isFindInteractionEnabled)

        var received: [RichEditorHostCommand] = []
        host.onCommand = { received.append($0) }
        host.setOwnsRichUndo(true)
        host.syncToolbarState(RichEditorToolbarState(
            marks: [],
            block: "paragraph",
            align: nil,
            dir: nil,
            canUndo: true,
            canRedo: true,
            undoTitle: "Bold",
            redoTitle: "Italic"
        ))

        let commands = try #require(host.webView.keyCommands)
        #expect(commands.count == 7)
        for command in commands {
            #expect(command.discoverabilityTitle?.isEmpty == false)
            #expect(command.wantsPriorityOverSystemBehavior)
        }

        let undoCmd = try #require(commands.first { $0.input == "z" && $0.modifierFlags == .command })
        let redoCmd = try #require(commands.first { $0.input == "z" && $0.modifierFlags == [.command, .shift] })
        #expect(undoCmd.discoverabilityTitle == "Undo Bold")
        #expect(redoCmd.discoverabilityTitle == "Redo Italic")

        for command in commands {
            let uiCommand: UICommand = command
            _ = host.webView.perform(uiCommand.action, with: command)
        }
        #expect(received == [
            .format(.toggleMark(.bold)),
            .format(.toggleMark(.italic)),
            .format(.toggleMark(.underline)),
            .requestLink,
            .presentFind,
            .format(.undo),
            .format(.redo),
        ])
    }
    #endif
}

@MainActor
struct RichEditorScrollingAndAppearanceTests {
    @Test func appearanceMessageEncodesAllTraitFieldsAsJSONWithoutSplicingScriptSource() throws {
        let appearance = RichEditorAppearance(
            fontFamily: "'New York', ui-serif, Georgia, serif",
            fontSizePx: 28.0,
            lineHeight: 1.62,
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
            isAccessibilityCategory: true,
            colorScheme: "dark",
            increaseContrast: true,
            boldText: true
        )

        let call = RichEditorBridgeCall.setAppearance(appearance)
        #expect(call.name == "setAppearance")
        #expect(call.timeout == .seconds(1))

        let invocation = try RichEditorBridgeEncoder.encode(call)
        #expect(invocation.script == RichEditorBridgeEncoder.callScript)
        #expect(!invocation.script.contains("New York"))
        #expect(!invocation.script.contains("AccessibilityExtra"))

        let jsArgs = try invocation.javaScriptArguments()
        #expect(jsArgs["name"] as? String == "setAppearance")
        let payload = try #require(jsArgs["args"] as? [String: Any])
        #expect(payload["fontFamily"] as? String == "'New York', ui-serif, Georgia, serif")
        #expect(payload["fontSizePx"] as? Double == 28.0)
        #expect(payload["lineHeight"] as? Double == 1.62)
        #expect(
            payload["contentSizeCategory"] as? String
                == "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        )
        #expect(payload["isAccessibilityCategory"] as? Bool == true)
        #expect(payload["colorScheme"] as? String == "dark")
        #expect(payload["increaseContrast"] as? Bool == true)
        #expect(payload["boldText"] as? Bool == true)
    }

    #if os(iOS)
    @Test func traitCollectionMapsDynamicTypeDarkModeContrastAndBoldText() {
        let traits = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: .dark),
            UITraitCollection(accessibilityContrast: .high),
            UITraitCollection(legibilityWeight: .bold),
            UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge),
        ])

        let appearance = RichEditorWebView.appearance(
            for: traits,
            fontFamily: RichEditorTheme.defaultFontFamily,
            baseFontSize: 15.5,
            lineHeight: 1.62
        )

        #expect(appearance.colorScheme == "dark")
        #expect(appearance.increaseContrast)
        #expect(appearance.boldText)
        #expect(appearance.isAccessibilityCategory)
        #expect(
            appearance.contentSizeCategory
                == UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue
        )
        #expect(appearance.fontSizePx > 15.5)
    }
    #endif

    @Test func scrollCalculatorFollowsCaretAndClampsToContentBounds() {
        // Caret comfortably inside viewport produces no jump.
        let inView = RichEditorScrollCalculator.targetOffsetY(
            caret: RichEditorCaretRect(x: 12, y: 200, width: 2, height: 22),
            currentOffsetY: 0,
            viewportHeight: 600,
            contentHeight: 2000,
            mode: .followCaret
        )
        #expect(inView == nil)

        // Caret pushed beneath the keyboard (bottomInset = 300 → visible height 300).
        let belowKeyboard = RichEditorScrollCalculator.targetOffsetY(
            caret: RichEditorCaretRect(x: 12, y: 400, width: 2, height: 22),
            currentOffsetY: 0,
            viewportHeight: 600,
            contentHeight: 2000,
            bottomInset: 300,
            mode: .followCaret,
            margin: 36
        )
        // caretBottom (422) + margin (36) - visibleHeight (300) = 158
        #expect(belowKeyboard == 158)

        // Caret above current scroll position scrolls back up with margin.
        let aboveViewport = RichEditorScrollCalculator.targetOffsetY(
            caret: RichEditorCaretRect(x: 12, y: 80, width: 2, height: 22),
            currentOffsetY: 400,
            viewportHeight: 600,
            contentHeight: 2000,
            mode: .followCaret,
            margin: 36
        )
        #expect(aboveViewport == 44)
    }

    @Test func scrollCalculatorTypewriterModePinsCaretAtFixedHeight() {
        let pinned = RichEditorScrollCalculator.targetOffsetY(
            caret: RichEditorCaretRect(x: 12, y: 800, width: 2, height: 20),
            currentOffsetY: 200,
            viewportHeight: 600,
            contentHeight: 2500,
            bottomInset: 200,
            mode: .typewriter,
            typewriterFraction: 0.4
        )
        // visibleHeight = 400; caretMidY = 810; desiredY = 160 → offset = 650
        #expect(pinned == 650)

        // Clamped to top when caret is near start of document.
        let clampedTop = RichEditorScrollCalculator.targetOffsetY(
            caret: RichEditorCaretRect(x: 12, y: 20, width: 2, height: 20),
            currentOffsetY: 120,
            viewportHeight: 600,
            contentHeight: 2500,
            mode: .typewriter,
            typewriterFraction: 0.4
        )
        #expect(clampedTop == 0)
    }

    @Test func caretRectAndStubPageSupportNativeFeelMessages() throws {
        let decoded = try RichEditorEvent.decode(from: [
            "type": "caretRect", "x": 16, "y": 420, "width": 2, "height": 24,
        ])
        #expect(decoded == .caretRect(RichEditorCaretRect(x: 16, y: 420, width: 2, height: 24)))

        let handler = RichEditorURLSchemeHandler(bundle: .main)
        let html = try handler.resolve(url: RichEditorBundleLocation.entryURL).get()
        let htmlString = String(decoding: html.data, as: UTF8.self)
        #expect(htmlString.contains("overflow-y: visible"))

        let script = try handler.resolve(url: URL(string: "kudos-editor://editor/editor-stub.js")).get()
        let scriptString = String(decoding: script.data, as: UTF8.self)
        #expect(scriptString.contains("setAppearance"))
        #expect(scriptString.contains("mirrorBlocks"))
        #expect(scriptString.contains("caretRect"))
        #expect(scriptString.contains("undoTitle"))
    }
}

#if os(iOS)
@MainActor
private final class FakeMenuBuilder: RichEditorMenuBuilding {
    var presentMenus: Set<UIMenu.Identifier>
    private(set) var removedMenus: [UIMenu.Identifier] = []
    private(set) var insertedAfter: [UIMenu.Identifier: UIMenu] = [:]
    private(set) var insertedAtStart: [UIMenu.Identifier: UIMenu] = [:]
    private(set) var insertedAtEnd: [UIMenu.Identifier: UIMenu] = [:]
    private(set) var replacedChildren: [UIMenu.Identifier: [UIMenuElement]] = [:]

    init(presentMenus: Set<UIMenu.Identifier>) {
        self.presentMenus = presentMenus
    }

    func hasMenu(for identifier: UIMenu.Identifier) -> Bool {
        presentMenus.contains(identifier)
    }

    func remove(menu identifier: UIMenu.Identifier) {
        removedMenus.append(identifier)
        presentMenus.remove(identifier)
    }

    func insertSibling(_ siblingMenu: UIMenu, afterMenu siblingIdentifier: UIMenu.Identifier) {
        insertedAfter[siblingIdentifier] = siblingMenu
    }

    func insertChild(_ childMenu: UIMenu, atStartOfMenu parentIdentifier: UIMenu.Identifier) {
        insertedAtStart[parentIdentifier] = childMenu
    }

    func insertChild(_ childMenu: UIMenu, atEndOfMenu parentIdentifier: UIMenu.Identifier) {
        insertedAtEnd[parentIdentifier] = childMenu
    }

    func replaceChildren(
        ofMenu parentIdentifier: UIMenu.Identifier,
        from childrenBlock: ([UIMenuElement]) -> [UIMenuElement]
    ) {
        replacedChildren[parentIdentifier] = childrenBlock([])
    }
}
#endif
