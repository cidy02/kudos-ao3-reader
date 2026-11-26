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
            // §7.10: the page sends mirror blocks only while the mirror is on screen.
            .onChange(of: showsSideBySideToggle && showsHTMLMirror, initial: true) { _, visible in
                session?.setMirrorVisible(visible)
            }
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
                session?.apply(.setLink(url: rawLink))
            } else {
                controller?.command("a", link: rawLink)
            }
        } else {
            errorMessage = "Enter an HTTP, HTTPS, or mailto link."
        }
    }

    func handleHostCommand(_ command: RichEditorHostCommand) {
        // An embedding screen (ChapterEditorScreen) takes the native-UI commands (Format panel, Find, the table
        // view) and anything else it wants first; what it leaves comes here.
        if embedOptions?.onHostCommand?(command) == true { return }
        switch command {
        case .requestLink:
            showLink = true
        case .openFormatPanel, .presentFind, .format(.openTableInHTML):
            // Native UI: the chapter editor screen presents these; this field editor has no panel.
            break
        default:
            session?.apply(command)
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

extension AO3MarkupTag {
    /// The page command for this toolbar tag in Rich Text (the `FormatCommand` it stands for; §7.2 `command`).
    /// Nil for the link, which opens the link sheet first.
    var richCommand: RichEditorCommandArgs? {
        let format: FormatCommand? = switch self {
        case .bold: .toggleMark(.bold)
        case .italic: .toggleMark(.italic)
        case .underline: .toggleMark(.underline)
        case .strike: .toggleMark(.strikethrough)
        case .superscript: .toggleMark(.superscript)
        case .`subscript`: .toggleMark(.`subscript`)
        case .small: .toggleMark(.smaller)
        case .code: .toggleMark(.code)
        case .paragraph: .setBlock(.body)
        case .quote: .setBlock(.quote)
        case .bullets: .setBlock(.bulletedList)
        case .numbers: .setBlock(.numberedList)
        case .heading: .setBlock(.heading)
        case .spoiler: .setBlock(.foldOut)
        case .divider: .insertSceneBreak(.line)
        case .lineBreak, .link: nil
        }
        if let format { return format.bridgeCommand }
        return self == .lineBreak ? RichEditorCommandArgs(name: "insertLineBreak") : nil
    }
}
