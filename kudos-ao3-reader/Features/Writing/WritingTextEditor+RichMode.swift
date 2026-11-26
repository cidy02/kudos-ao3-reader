import SwiftUI

/// Rich Text mode toggle, §7.10 two-views HTML mirror, N3 fallback keys bar,
/// loss confirmation & notice alerts, WebView host lifecycle, and command routing
/// for `WritingTextEditor`.
extension WritingTextEditor {
    var showsModeSwitch: Bool {
        RichEditorFeatureFlag.showsRichTextSwitch(field: field, enabled: richEditorFeatureEnabled)
            && !isPreviewing
    }

    var isRichMode: Bool { session?.owner == .rich }
    var isHandingOff: Bool { session?.isHandingOff ?? false }
    var showsSourceView: Bool { !isPreviewing && !isRichMode }
    var showsRichView: Bool { !isPreviewing && isRichMode }

    var isRegularWidthForTwoViews: Bool {
        #if os(iOS)
        horizontalSizeClass == .regular
        #else
        true
        #endif
    }

    var showsSideBySideToggle: Bool {
        RichEditorTwoViewPolicy.supportsSideBySide(isRegularWidth: isRegularWidthForTwoViews)
            && isRichMode
    }

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
                HStack(spacing: 8) {
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

                    if showsSideBySideToggle {
                        Button {
                            showsHTMLMirror.toggle()
                        } label: {
                            Label("HTML Mirror", systemImage: "sidebar.right")
                                .labelStyle(.iconOnly)
                                .padding(7)
                        }
                        .buttonStyle(.bordered)
                        .tint(showsHTMLMirror ? theme.effectiveTint : .secondary)
                        .accessibilityLabel(showsHTMLMirror ? "Hide HTML mirror" : "Show HTML mirror")
                    }
                }

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
            HStack(spacing: 0) {
                RichEditorWebViewContainer(webView: richHost.webView)
                    .id(richHost.webViewGeneration)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showsSideBySideToggle, showsHTMLMirror, let session {
                    Rectangle()
                        .fill(theme.appTheme.glassStroke(0.14))
                        .frame(width: 0.5)
                        .accessibilityHidden(true)
                    RichEditorHTMLMirrorView(
                        document: session.mirrorDocument,
                        fontSize: editorFontSize,
                        onTapOffset: { offset in
                            Task { await session.switchToSourceFromMirrorTap(atUTF16Offset: offset) }
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
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

    #if os(iOS)
    /// N3 / §7.7 fallback: rendered natively above WebKit's bar only if replacing
    /// `WKContentView.inputAccessoryView` failed its launch-time check.
    var richFallbackKeysBar: some View {
        WritingKeysBar(
            formatState: session?.toolbarState.toFormatState() ?? FormatState(),
            onAction: { action in
                handleHostCommand(RichEditorHostCommand.from(action))
            }
        )
    }
    #endif

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
        let preloadEnabled = RichEditorFeatureFlag.showsRichTextSwitch(
            field: field,
            enabled: richEditorFeatureEnabled
        )
        return DraftSession(
            initialText: text,
            fieldVariant: DraftFieldVariant.from(field: field),
            source: editor,
            recoveryWriter: writer,
            makeRichTransport: {
                if let existing = richHost { return existing }
                // §9.3: claim a pre-warmed host when available so opening costs no page load.
                let host = RichEditorPrewarmPool.shared.takeOrCreateRichEditorHost(
                    backgroundColor: theme.appTheme.backgroundColor
                )
                host.installKeysAccessory(themeManager: theme)
                host.updateTypography(
                    fontFamily: RichEditorTheme.defaultFontFamily,
                    baseFontSize: Double(editorFontSize),
                    lineHeight: RichEditorTheme.defaultLineHeight
                )
                host.onCommand = { command in
                    handleHostCommand(command)
                }
                richHost = host
                return host
            },
            themeProvider: { richEditorTheme },
            isRichPreloadEnabled: preloadEnabled,
            onCheckpointText: { value in text = value },
            onRecoveryError: { message in errorMessage = message }
        )
    }

    func handleFontSizeChange(_ value: CGFloat) {
        controller?.setAppearance(theme.appTheme, fontSize: value)
        richHost?.updateTypography(
            fontFamily: RichEditorTheme.defaultFontFamily,
            baseFontSize: Double(value),
            lineHeight: RichEditorTheme.defaultLineHeight
        )
        session?.updateTheme(richEditorTheme)
    }

    func handleThemeChange(_ value: ReaderTheme) {
        controller?.setAppearance(value, fontSize: editorFontSize)
        richHost?.applyNativeBackgroundColor(value.backgroundColor)
        session?.updateTheme(richEditorTheme)
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        if phase == .active {
            session?.handleSceneActive()
        } else {
            session?.handleSceneInactiveOrBackground()
        }
    }

    func handleLinkInsert(_ rawLink: String) {
        if WritingMarkup.safeLink(rawLink) {
            if isRichMode {
                session?.applyRichCommand(name: "link", attrs: ["href": .string(rawLink)])
            } else {
                controller?.command("a", link: rawLink)
            }
        } else {
            errorMessage = "Enter an HTTP, HTTPS, or mailto link."
        }
    }

    func handleHostCommand(_ command: RichEditorHostCommand) {
        switch command {
        case .format(.undo):
            session?.undo()
        case .format(.redo):
            session?.redo()
        case let .format(.toggleMark(mark)):
            session?.applyRichCommand(name: mark.richCommandName)
        case let .format(.setLink(url)):
            session?.applyRichCommand(name: "link", attrs: ["href": .string(url)])
        case .format(.unlink):
            session?.applyRichCommand(name: "unlink")
        case .format(.insertSceneBreak):
            session?.applyRichCommand(name: "horizontal_rule")
        case .format(.clearFormatting):
            session?.applyRichCommand(name: "clear_formatting")
        case .requestLink:
            showLink = true
        case .format, .moveCaret, .insertEmDash, .insertQuotationMarks, .openFormatPanel, .presentFind:
            // Full page wiring arrives at integration with `editor-core`.
            break
        }
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

private extension FormatMark {
    var richCommandName: String {
        switch self {
        case .bold: "strong"
        case .italic: "em"
        case .underline: "underline"
        case .strikethrough: "strike"
        case .superscript: "sup"
        case .`subscript`: "sub"
        case .smaller: "small"
        case .code: "code"
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
