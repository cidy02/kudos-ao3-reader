import OSLog
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Word-slide queue, and on iPhone the dictation session, owned by `ChapterEditorScreen`.
@MainActor
@Observable
final class ChapterEditorPhoneWriting {
    #if os(iOS)
    let dictation = DictationController()
    #endif
    @ObservationIgnored private var wordSlideChain: Task<Void, Never>?

    func enqueueWordSlide(_ work: @escaping @MainActor () async -> Void) {
        let previous = wordSlideChain
        wordSlideChain = Task { @MainActor in
            await previous?.value
            guard !Task.isCancelled else { return }
            await work()
        }
    }

    func cancelWordSlide() {
        wordSlideChain?.cancel()
        wordSlideChain = nil
    }
}

/// Puts the phone actions into the environment and, on iPhone, swaps the keyboard for the dictation panel.
struct ChapterEditorPhoneWritingModifier: ViewModifier {
    var actions: WritingKeysBarPhoneActions
    var phoneWriting: ChapterEditorPhoneWriting
    var sessionID: ObjectIdentifier?
    var onUndoPhrase: () -> Void
    var onReturnToKeyboard: () -> Void
    var onSyncKeys: () -> Void
    var onClearKeys: () -> Void

    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .environment(\.writingKeysBarPhone, actions)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if phoneWriting.dictation.isPresented {
                    DictationPanel(
                        controller: phoneWriting.dictation,
                        onUndoPhrase: onUndoPhrase,
                        onKeyboard: onReturnToKeyboard
                    )
                }
            }
            .onChange(of: phoneWriting.dictation.isPresented) { _, _ in
                onSyncKeys()
            }
            .onChange(of: actions.wordSlideEnabled) { _, enabled in
                if !enabled {
                    phoneWriting.dictation.dismiss(commitPending: false)
                    phoneWriting.cancelWordSlide()
                }
            }
            .onChange(of: sessionID) { _, _ in
                phoneWriting.dictation.dismiss(commitPending: false)
                phoneWriting.cancelWordSlide()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    phoneWriting.dictation.pause()
                } else if phase == .inactive, phoneWriting.dictation.phase == .listening {
                    phoneWriting.dictation.pause()
                }
            }
            .onDisappear {
                phoneWriting.dictation.dismiss(commitPending: false)
                phoneWriting.cancelWordSlide()
                onClearKeys()
            }
        #else
        content
            .environment(\.writingKeysBarPhone, actions)
            .onChange(of: actions.wordSlideEnabled) { _, enabled in
                if !enabled { phoneWriting.cancelWordSlide() }
            }
            .onChange(of: sessionID) { _, _ in
                phoneWriting.cancelWordSlide()
            }
            .onDisappear { phoneWriting.cancelWordSlide() }
        #endif
    }
}

extension ChapterEditorScreen {
    var writingKeysPhoneActions: WritingKeysBarPhoneActions {
        WritingKeysBarPhoneActions(
            wordSlideEnabled: isRichMode,
            showsDictate: showsDictateButton,
            suppressesKeys: dictationPanelVisible,
            onMoveByWord: { count, extend in
                self.enqueueWordMove(count, extend: extend)
            },
            onDictate: { self.beginDictation() }
        )
    }

    var phoneWritingModifier: ChapterEditorPhoneWritingModifier {
        ChapterEditorPhoneWritingModifier(
            actions: writingKeysPhoneActions,
            phoneWriting: phoneWriting,
            sessionID: session.map(ObjectIdentifier.init),
            onUndoPhrase: { self.session?.undo() },
            onReturnToKeyboard: { self.returnToKeyboardFromDictation() },
            onSyncKeys: { self.syncWritingKeysPhoneActions() },
            onClearKeys: { self.clearWritingKeysPhoneActions() }
        )
    }

    var showsDictateButton: Bool {
        #if os(iOS)
        isRichMode && DictationOffer.currentDeviceAllows
        #else
        false
        #endif
    }

    var dictationPanelVisible: Bool {
        #if os(iOS)
        phoneWriting.dictation.isPresented
        #else
        false
        #endif
    }

    func enqueueWordMove(_ count: Int, extend: Bool) {
        guard count != 0, let session, session.owner == .rich else { return }
        let step = count > 0 ? 1 : -1
        let steps = abs(count)
        phoneWriting.enqueueWordSlide {
            for _ in 0..<steps {
                guard !Task.isCancelled else { return }
                let moved = await session.moveByWord(step, extend: extend)
                guard moved else { break }
                Haptics.selection()
            }
        }
    }

    func beginDictation() {
        #if os(iOS)
        guard let session, session.owner == .rich, DictationOffer.currentDeviceAllows else { return }
        phoneWriting.dictation.onPhrase = { [weak session] phrase in
            guard let session else { return }
            await DictationPhraseInserter.apply(phrase, to: session)
        }
        phoneWriting.dictation.present()
        guard phoneWriting.dictation.isPresented else { return }
        syncWritingKeysPhoneActions()
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        #endif
    }

    func returnToKeyboardFromDictation() {
        #if os(iOS)
        phoneWriting.dictation.dismiss(commitPending: true)
        syncWritingKeysPhoneActions()
        richHost?.focusWebView()
        #endif
    }

    func syncWritingKeysPhoneActions() {
        #if os(iOS)
        richHost?.webView.keysAccessoryView?.updatePhoneActions(writingKeysPhoneActions)
        #endif
    }

    func clearWritingKeysPhoneActions() {
        #if os(iOS)
        richHost?.webView.keysAccessoryView?.updatePhoneActions(.disabled)
        #endif
    }
}

enum DictationPhraseInserter {
    static func apply(_ phrase: String, to session: DraftSession) async {
        guard session.state == .richOwned else { return }
        let steps = DictationPhrasePlan.steps(
            phrase: phrase,
            italicIsOn: session.formatState.isActive(.italic)
        )
        for step in steps {
            guard session.state == .richOwned else { return }
            switch step {
            case let .text(text):
                _ = await session.insertDictatedPhrase(text)
            case .newParagraph:
                _ = await session.insertParagraphBreak()
            case .sceneBreak:
                await applyFormatCommand(.insertSceneBreak(.asterism), to: session)
            case .toggleItalic:
                await applyFormatCommand(.toggleMark(.italic), to: session)
            }
        }
    }

    /// Awaits the formatting command on the bridge so subsequent prose/commands never overtake it.
    private static func applyFormatCommand(_ command: FormatCommand, to session: DraftSession) async {
        guard session.state == .richOwned,
              let transport = session.richTransport,
              let args = command.bridgeCommand else { return }
        do {
            _ = try await transport.command(args)
        } catch {
            writingEditorLog.notice(
                "Dictation '\(args.name, privacy: .public)' failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
