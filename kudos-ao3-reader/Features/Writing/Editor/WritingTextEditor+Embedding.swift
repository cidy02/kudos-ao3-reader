import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Embedded hosting view and command-bridge helpers for `WritingTextEditor` when mounted
/// inside `ChapterEditorScreen`. Keeps standalone `WritingTextEditor` behavior untouched.
extension WritingTextEditor {
    var embeddedBody: some View {
        VStack(spacing: 0) {
            ZStack {
                if let controller {
                    WritingNativeTextView(controller: controller)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(showsSourceView ? 1 : 0)
                        .accessibilityHidden(!showsSourceView)
                        .allowsHitTesting(showsSourceView)
                } else {
                    ProgressView().accentFill()
                }
                richEditorLayers
            }
            .background { richEditorAlerts }
            #if os(iOS)
            if isRichMode {
                if richHost?.usesFallbackAccessoryBar == true {
                    let suggestions = embedOptions?.nameSuggestions ?? []
                    WritingKeysBar(
                        formatState: session?.formatState ?? FormatState(),
                        showsLeadingContent: !suggestions.isEmpty,
                        onAction: { action in
                            handleHostCommand(RichEditorHostCommand.from(action))
                        },
                        leadingSlot: {
                            WritingNameSuggestionChips(suggestions: suggestions) { selected in
                                embedOptions?.onSelectNameSuggestion?(selected)
                            }
                        }
                    )
                }
            } else {
                tagBar
            }
            #endif
        }
        .onAppear(perform: start)
        .onChange(of: richHost != nil) { _, hasHost in
            if hasHost { attachEmbeddedHostCommandBridgeIfNeeded() }
        }
        .onChange(of: session?.owner) { _, _ in
            attachEmbeddedHostCommandBridgeIfNeeded()
        }
        .onChange(of: editorFontSize) { _, value in handleFontSizeChange(value) }
        .onChange(of: theme.appTheme) { _, value in handleThemeChange(value) }
        .onChange(of: scenePhase) { _, phase in handleScenePhaseChange(phase) }
        #if os(iOS)
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
        ) { _ in
            session?.handleMemoryWarning()
        }
        #endif
        .onDisappear(perform: finish)
        .alert("Editor error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Insert link", isPresented: $showLink) {
            TextField("https://example.com", text: $link)
            Button("Insert") { handleLinkInsert(link) }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: Binding(
            get: { !recoveries.isEmpty },
            set: { if !$0 { recoveries = [] } }
        )) {
            recoverySheet
        }
    }

    func startEmbeddedIfNeeded(session createdSession: DraftSession) {
        guard let embedOptions else { return }
        embedOptions.onSessionReady?(createdSession)
        if embedOptions.startsInRichMode,
           RichEditorFeatureFlag.showsRichTextSwitch(field: field, enabled: richEditorFeatureEnabled) {
            Task {
                _ = await createdSession.switchToRich()
                attachEmbeddedHostCommandBridgeIfNeeded()
            }
        }
    }

    /// Hands the host to the embedding screen. Host commands need no rewiring: `handleHostCommand` asks the
    /// embedding first.
    func attachEmbeddedHostCommandBridgeIfNeeded() {
        guard let embedOptions, let host = richHost else { return }
        embedOptions.onRichHostReady?(host)
    }
}
