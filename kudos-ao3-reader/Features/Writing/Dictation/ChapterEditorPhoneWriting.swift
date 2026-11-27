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
    var onUndoPhrase: () -> Void
    var onReturnToKeyboard: () -> Void
    var onSyncKeys: () -> Void

    @Environment(\.scenePhase) private var scenePhase

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
                if !enabled { phoneWriting.dictation.dismiss() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { phoneWriting.dictation.pause() }
            }
            .onDisappear {
                phoneWriting.dictation.dismiss()
                phoneWriting.cancelWordSlide()
            }
        #else
        content
            .environment(\.writingKeysBarPhone, actions)
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
            onUndoPhrase: { self.session?.undo() },
            onReturnToKeyboard: { self.returnToKeyboardFromDictation() },
            onSyncKeys: { self.syncWritingKeysPhoneActions() }
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
        phoneWriting.enqueueWordSlide {
            _ = await session.moveByWord(count, extend: extend)
        }
    }

    func beginDictation() {
        #if os(iOS)
        guard let session, session.owner == .rich, DictationOffer.currentDeviceAllows else { return }
        phoneWriting.dictation.onPhrase = { phrase in
            await DictationPhraseInserter.apply(phrase, to: session)
        }
        phoneWriting.dictation.present()
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
        phoneWriting.dictation.dismiss()
        syncWritingKeysPhoneActions()
        richHost?.webView.becomeFirstResponder()
        #endif
    }

    func syncWritingKeysPhoneActions() {
        #if os(iOS)
        richHost?.webView.keysAccessoryView?.updatePhoneActions(writingKeysPhoneActions)
        #endif
    }
}

#if os(iOS)
enum DictationPhraseInserter {
    static func apply(_ phrase: String, to session: DraftSession) async {
        guard session.owner == .rich else { return }
        let steps = DictationPhrasePlan.steps(
            phrase: phrase,
            italicIsOn: session.formatState.isActive(.italic)
        )
        for step in steps {
            switch step {
            case let .text(text):
                _ = await session.insertDictatedPhrase(text)
            case .newParagraph:
                _ = await session.insertParagraphBreak()
            case .sceneBreak:
                session.apply(.insertSceneBreak(.asterism))
            case .toggleItalic:
                session.apply(.toggleMark(.italic))
            }
        }
    }
}
#endif
