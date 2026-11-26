import SwiftUI

/// Rich Text mode toggle, loss confirmation & notice alerts, WebView host
/// lifecycle, and markup-tag command mapping for `WritingTextEditor`.
extension WritingTextEditor {
    var showsModeSwitch: Bool {
        RichEditorFeatureFlag.showsRichTextSwitch(field: field, enabled: richEditorFeatureEnabled)
            && !isPreviewing
    }

    var isRichMode: Bool { session?.owner == .rich }
    var isHandingOff: Bool { session?.isHandingOff ?? false }
    var showsSourceView: Bool { !isPreviewing && !isRichMode }
    var showsRichView: Bool { !isPreviewing && isRichMode }

    var richEditorTheme: RichEditorTheme {
        RichEditorTheme(
            background: theme.appTheme.backgroundHex,
            text: theme.appTheme.textHex,
            accent: theme.accentInk.hexString,
            link: theme.appTheme.linkHex,
            fontFamily: RichEditorTheme.defaultFontFamily,
            fontSizePx: Double(editorFontSize),
            lineHeight: RichEditorTheme.defaultLineHeight
        )
    }

    @ViewBuilder
    var modeSwitchBar: some View {
        if let session {
            VStack(alignment: .leading, spacing: 4) {
                Picker(
                    "Editor Mode",
                    selection: Binding(
                        get: { session.displayedMode },
                        set: { next in
                            Task {
                                if next == .rich {
                                    await session.switchToRich()
                                } else {
                                    await session.switchToSource()
                                }
                            }
                        }
                    )
                ) {
                    Text("Rich Text").tag(DraftEditorMode.rich)
                    Text("HTML").tag(DraftEditorMode.source)
                }
                .pickerStyle(.segmented)
                .accentFill()
                .labelsHidden()
                .accessibilityLabel("Editor mode")
                .disabled(session.isHandingOff || (!session.isRichAvailable && session.owner == .source))

                if !session.isRichAvailable, session.owner == .source {
                    Text(session.isRichPermanentlyDisabled
                        ? "Rich Text is unavailable until you reopen this editor."
                        : "Rich Text is temporarily unavailable while it recovers.")
                        .font(.caption2)
                        .foregroundStyle(.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                } else if isRichMode, let changes = session.lastSwitchChanges {
                    Button("What changed") { showWhatChanged = true }
                        .font(.caption2)
                        .buttonStyle(.plain)
                        .foregroundStyle(.accentInk)
                        .alert("What Changed", isPresented: $showWhatChanged) {
                            Button("OK", role: .cancel) {}
                        } message: {
                            Text(changes.nonBlockingChangesSummary)
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    var richEditorLayers: some View {
        if let richHost {
            RichEditorWebViewContainer(webView: richHost.webView)
                .id(richHost.webViewGeneration)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(showsRichView ? 1 : 0)
                .accessibilityHidden(!showsRichView)
                .allowsHitTesting(showsRichView)
        }
        if session?.isShowingSwitchTransition == true {
            ProgressView("Switching to Rich Text…")
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accentFill()
        }
    }

    /// Hosted on separate empty views so SwiftUI never drops one alert for a sibling.
    var richEditorAlerts: some View {
        ZStack {
            Color.clear
                .alert("Switch to Rich Text?", isPresented: Binding(
                    get: { session?.pendingLossConfirmation != nil },
                    set: { if !$0 { session?.cancelPendingRichSwitch() } }
                )) {
                    Button("Switch Anyway") {
                        Task { await session?.confirmLossAndCompleteSwitchToRich() }
                    }
                    Button("Cancel", role: .cancel) {
                        session?.cancelPendingRichSwitch()
                    }
                } message: {
                    Text(session?.pendingLossConfirmation?.message ?? "")
                }
            Color.clear
                .alert("Rich Text", isPresented: Binding(
                    get: { session?.noticeMessage != nil },
                    set: { if !$0 { session?.noticeMessage = nil } }
                )) {
                    Button("OK", role: .cancel) { session?.noticeMessage = nil }
                } message: {
                    Text(session?.noticeMessage ?? "")
                }
        }
        .accessibilityHidden(true)
    }

    func makeDraftSession(
        editor: WritingTextController,
        writer: WritingRecoveryWriter
    ) -> DraftSession {
        DraftSession(
            initialText: text,
            fieldVariant: DraftFieldVariant.from(field: field),
            source: editor,
            recoveryWriter: writer,
            makeRichTransport: {
                if let existing = richHost { return existing }
                let host = RichEditorHost(backgroundColor: theme.appTheme.backgroundColor)
                richHost = host
                return host
            },
            themeProvider: { richEditorTheme },
            onCheckpointText: { value in text = value },
            onRecoveryError: { message in errorMessage = message }
        )
    }

    /// Done's checkpoint, then `action` — after it, the form holds this text.
    func closeEditor(then action: (() -> Void)? = nil) {
        if let session, session.owner == .rich {
            Task {
                await session.commit()
                dismiss()
                action?()
            }
        } else {
            session?.commitSynchronouslyIfSource()
            dismiss()
            action?()
        }
    }

    /// Leaving the screen: commit any composition, checkpoint, then break cycles.
    func teardownEditor() {
        let activeSession = session
        let activeHost = richHost
        session = nil
        richHost = nil
        controller = nil
        if let activeSession, activeSession.owner == .rich {
            Task {
                await activeSession.commit()
                activeSession.teardown()
                activeHost?.teardown()
            }
        } else {
            activeSession?.commitSynchronouslyIfSource()
            activeSession?.teardown()
            activeHost?.teardown()
        }
    }
}

extension AO3MarkupTag {
    var richCommandName: String {
        switch self {
        case .bold: "strong"
        case .italic: "em"
        case .underline: "underline"
        case .strike: "strike"
        case .superscript: "sup"
        case .`subscript`: "sub"
        case .small: "small"
        case .code: "code"
        case .paragraph: "paragraph"
        case .lineBreak: "hard_break"
        case .quote: "blockquote"
        case .bullets: "bullet_list"
        case .numbers: "ordered_list"
        case .heading: "heading"
        case .divider: "horizontal_rule"
        case .link: "link"
        case .spoiler: "details"
        }
    }

    var richCommandAttrs: [String: RichEditorJSONValue] {
        self == .heading ? ["level": .int(3)] : [:]
    }
}
