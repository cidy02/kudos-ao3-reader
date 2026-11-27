import SwiftUI

/// AO3 action callbacks provided by `AddChapterView` or `WorkEditView`.
/// Any omitted callback hides its corresponding item in `EditorMoreMenu` and
/// `ChapterSwitcherMenu` rather than leaving a disabled placeholder.
struct ChapterEditorAO3Actions {
    var ao3WorkID: Int?
    var ao3ChapterID: Int?
    var isPosted: Bool = false
    var isAO3Draft: Bool = false
    var isChapterOne: Bool = false
    var ao3DraftDaysLeft: Int?
    var postOrUpdate: (() -> Void)?
    var saveAsAO3Draft: (() -> Void)?
    var preview: (() -> Void)?
    var openWorkDetails: (() -> Void)?
    var pushesWorkDetailsDestination: Bool = false
    var canEditTags: Bool = false
    var deleteChapterName: String?
    var deleteChapter: (() -> Void)?
}

/// Whole-chapter Rich Text editor screen (`Studio-Editor.dc.html`), gated behind
/// `RichEditorFeatureFlag`. Composes `EditorHeader`, `ChapterSwitcherMenu`,
/// `EditorMoreMenu`, `ChapterNotesBlocks`, an embedded `WritingTextEditor`
/// (reusing its `DraftSession`, `RichEditorHost`, checkpoints, and recovery),
/// `FormatPanel`, `PasteReportCard`, and `EditorStatusLine`, while mirroring
/// every save into `WritingDocumentStore` on this device.
struct ChapterEditorScreen: View {
    let workTitle: String
    let chapterNumber: Int?
    @Binding var chapterTitle: String
    @Binding var summary: String
    @Binding var notesBefore: String
    @Binding var notesAfter: String
    @Binding var content: String
    let account: String
    let recoveryTarget: String
    let ao3Actions: ChapterEditorAO3Actions?
    let localDocumentTarget: ChapterEditorDocumentTarget?
    let onSwitchLocalChapter: ((UUID) -> Void)?
    let onNewLocalChapter: (() -> Void)?
    let onDeleteLocalChapter: (() -> Void)?

    @Environment(\.dismiss) var dismiss
    @Environment(ThemeManager.self) var theme
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    @State var documentBridge: ChapterEditorDocumentBridge
    @State var session: DraftSession?
    @State var richHost: RichEditorHost?
    @State var pasteTracker = ChapterEditorPasteTracker()
    @State var initialSnapshot: InitialSnapshot
    @State var initialWordCount: Int?
    @State var fallbackWordCount: Int?
    @State var showingFormatPanel = false
    @State var pendingAddNoteAfterFormatDismiss = false
    @State var showingLinkSheet = false
    @State var notesSheetTab: ChapterEditorNotesTab?
    @State var activeAnnotationSheet: ChapterEditorAnnotationSheet?
    @State var tkTracker = ChapterEditorTKTracker()
    @State var annotationTapTracker = ChapterEditorAnnotationTapTracker()
    @State var tkDescriptionText = ""
    @State var latestAnnotationHTML = ""
    @State var showingDeleteConfirmation = false
    @State var showingWhatChanged = false
    @State var showingWorkDetailsDestination = false
    @State var showingEditTagsDestination = false
    @State var transientStatusMessage: String?
    @State var metadataSaveTask: Task<Void, Never>?
    @State var statusClearTask: Task<Void, Never>?
    @State var annotationSyncTask: Task<Void, Never>?
    @State var annotationSyncGeneration = 0
    @State var isClosing = false
    @State var sprintController = SprintController(outside: .system)

    struct InitialSnapshot: Equatable {
        let title: String
        let summary: String
        let notesBefore: String
        let notesAfter: String
        let content: String
    }

    init(
        workTitle: String,
        chapterNumber: Int? = nil,
        chapterTitle: Binding<String>,
        summary: Binding<String>,
        notesBefore: Binding<String>,
        notesAfter: Binding<String>,
        content: Binding<String>,
        account: String = "",
        recoveryTarget: String,
        ao3Actions: ChapterEditorAO3Actions? = nil,
        localDocumentTarget: ChapterEditorDocumentTarget? = nil,
        documentStore: WritingDocumentStore = WritingDocumentStore(
            root: WritingDocumentStore.defaultRoot
        ),
        documentBridge: ChapterEditorDocumentBridge? = nil,
        onSwitchLocalChapter: ((UUID) -> Void)? = nil,
        onNewLocalChapter: (() -> Void)? = nil,
        onDeleteLocalChapter: (() -> Void)? = nil
    ) {
        self.workTitle = workTitle
        self.chapterNumber = chapterNumber
        _chapterTitle = chapterTitle
        _summary = summary
        _notesBefore = notesBefore
        _notesAfter = notesAfter
        _content = content
        self.account = account
        self.recoveryTarget = recoveryTarget
        self.ao3Actions = ao3Actions
        self.localDocumentTarget = localDocumentTarget
        self.onSwitchLocalChapter = onSwitchLocalChapter
        self.onNewLocalChapter = onNewLocalChapter
        self.onDeleteLocalChapter = onDeleteLocalChapter
        _documentBridge = State(
            initialValue: documentBridge ?? ChapterEditorDocumentBridge(store: documentStore)
        )
        _initialSnapshot = State(
            initialValue: InitialSnapshot(
                title: chapterTitle.wrappedValue,
                summary: summary.wrappedValue,
                notesBefore: notesBefore.wrappedValue,
                notesAfter: notesAfter.wrappedValue,
                content: content.wrappedValue
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            noticeBanner
            chapterPageBody
            tkPromptBanner
            bottomFooter
        }
        .background(appTheme.contentBackdrop.ignoresSafeArea())
        .hidesFloatingTabBarInEditor()
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #else
        .navigationBarBackButtonHidden(true)
        #endif
        .task(id: recoveryTarget) {
            await openDocumentBridge()
        }
        .onChange(of: session?.lastPaste) { _, newPaste in
            withAnimationUnlessReduced(.snappy(duration: 0.2), reduceMotion: reduceMotion) {
                _ = pasteTracker.receive(newPaste)
            }
        }
        .onChange(of: session?.wordCount) { _, newCount in
            guard let newCount else { return }
            if initialWordCount == nil { initialWordCount = newCount }
            fallbackWordCount = newCount
        }
        .onChange(of: session?.owner) { _, newOwner in
            if newOwner == .rich {
                scheduleAnnotationSync(useCurrentHTML: false)
                syncKeysAccessorySuggestions()
            } else {
                cancelPendingTK()
                clearKeysAccessorySuggestions()
            }
        }
        .onChange(of: session?.lastAnnotationTap) { _, newTap in
            handleAnnotationTap(newTap)
        }
        .onChange(of: session?.lastTypedTK) { _, newTK in
            handleTypedTK(newTK)
        }
        .onChange(of: nameSuggestions) { _, _ in
            syncKeysAccessorySuggestions()
        }
        #if os(iOS)
        .onChange(of: richHost?.webViewGeneration) { _, _ in
            syncKeysAccessorySuggestions()
        }
        #endif
        .onChange(of: notesSheetTab) { _, newTab in
            if newTab == .chapterNotes {
                refreshChapterAnnotationsForNotesSheet()
            }
        }
        .onChange(of: content) { _, _ in scheduleLocalSave() }
        .onChange(of: chapterTitle) { _, _ in scheduleLocalSave() }
        .onChange(of: summary) { _, _ in scheduleLocalSave() }
        .onChange(of: notesBefore) { _, _ in scheduleLocalSave() }
        .onChange(of: notesAfter) { _, _ in scheduleLocalSave() }
        .sprintHost(sprintController, words: currentWordCount, workID: documentBridge.workID, isClosing: isClosing)
        // the Lock Screen widget's "what you're writing" (T-576e)
        .onAppear { KudosWidgetBridge.noteEditing(work: workTitle, chapter: chapterTitle) }
        .onDisappear { KudosWidgetBridge.noteEditing(work: workTitle, chapter: chapterTitle) }
        .onDisappear {
            metadataSaveTask?.cancel()
            statusClearTask?.cancel()
            annotationSyncTask?.cancel()
            clearKeysAccessorySuggestions()
        }
        .sheet(
            isPresented: $showingFormatPanel,
            onDismiss: {
                if pendingAddNoteAfterFormatDismiss {
                    pendingAddNoteAfterFormatDismiss = false
                    beginAddingNote()
                }
            }
        ) {
            FormatPanel(
                state: session?.formatState ?? FormatState(),
                onCommand: { command in handleFormatCommand(command) },
                onAddNote: isRichMode ? {
                    pendingAddNoteAfterFormatDismiss = true
                    showingFormatPanel = false
                } : nil,
                onDismiss: { showingFormatPanel = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingLinkSheet) {
            FormatLinkFormSheet(
                initialDraft: FormatLinkDraft(
                    address: session?.formatState.currentLinkURL ?? "",
                    isInLink: session?.formatState.isInLink ?? false
                ),
                onCommand: { command in handleFormatCommand(command) }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $notesSheetTab) { tab in
            ChapterEditorNotesSheet(
                chapterTitle: $chapterTitle,
                summary: $summary,
                notesBefore: $notesBefore,
                notesAfter: $notesAfter,
                documentBridge: documentBridge,
                chapterHTML: currentAnnotationHTML,
                initialTab: tab,
                onAnnotationsChanged: {
                    scheduleAnnotationSync(useCurrentHTML: true)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $activeAnnotationSheet) { sheet in
            annotationSheetView(for: sheet)
        }
        .navigationDestination(isPresented: $showingWorkDetailsDestination) {
            if let workID = ao3Actions?.ao3WorkID {
                WritingWorkDestination(workID: workID)
            }
        }
        .navigationDestination(isPresented: $showingEditTagsDestination) {
            if let workID = ao3Actions?.ao3WorkID {
                WritingTagsDestination(workID: workID, workTitle: workTitle)
            }
        }
        .alert(
            deleteAlertTitle,
            isPresented: $showingDeleteConfirmation
        ) {
            Button(isLocalOnly ? "Delete Chapter" : "Delete on AO3", role: .destructive) {
                confirmDeleteChapter()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteAlertMessage)
        }
        .alert("What Changed", isPresented: $showingWhatChanged) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(session?.lastSwitchChanges?.nonBlockingChangesSummary ?? "")
        }
    }
}

// MARK: - Derived state

extension ChapterEditorScreen {
    var appTheme: ReaderTheme { theme.appTheme }
    var isLocalOnly: Bool { ao3Actions == nil }
    var isPosted: Bool { ao3Actions?.isPosted == true }
    var isRichMode: Bool { session?.owner == .rich }

    var hasUnpostedChanges: Bool {
        let liveContent = session?.text ?? content
        let hasUncheckpointedEdits = session.map { $0.revision != $0.lastCheckpointedRevision } ?? false
        return hasUncheckpointedEdits
            || chapterTitle != initialSnapshot.title
            || summary != initialSnapshot.summary
            || notesBefore != initialSnapshot.notesBefore
            || notesAfter != initialSnapshot.notesAfter
            || liveContent != initialSnapshot.content
    }

    var resolvedChapterNumber: Int {
        if let chapterNumber, chapterNumber > 0 { return chapterNumber }
        if let activeID = documentBridge.chapterID,
           let index = documentBridge.chapters.firstIndex(where: { $0.id == activeID }) {
            return index + 1
        }
        return 1
    }

    var currentWordCount: Int {
        session?.wordCount ?? fallbackWordCount ?? 0
    }

    var chapterDisplayTitle: String {
        let trimmed = chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    var headerChapterTitle: String {
        "Ch. \(resolvedChapterNumber) · \(chapterDisplayTitle)"
    }

    var resolvedWorkTitle: String {
        let trimmed = workTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    var canOpenWorkDetails: Bool {
        if ao3Actions?.openWorkDetails != nil { return true }
        return ao3Actions?.pushesWorkDetailsDestination == true && ao3Actions?.ao3WorkID != nil
    }

    var canDeleteChapter: Bool {
        if ao3Actions?.deleteChapterName != nil, ao3Actions?.deleteChapter != nil {
            return true
        }
        return isLocalOnly && onDeleteLocalChapter != nil && documentBridge.chapters.count > 1
    }

    var supportsHostFind: Bool {
        #if os(iOS)
        return isRichMode && richHost != nil
        #else
        return false
        #endif
    }

    var menuCapabilities: ChapterEditorMenuCapabilities {
        ChapterEditorMenuCapabilities(
            isPosted: isPosted,
            hasUnpostedChanges: hasUnpostedChanges,
            canPostOrUpdate: ao3Actions?.postOrUpdate != nil,
            canSaveAsAO3Draft: ao3Actions?.saveAsAO3Draft != nil && !isPosted,
            canPreview: ao3Actions?.preview != nil,
            canFind: supportsHostFind,
            canAddNote: isRichMode,
            canFormat: isRichMode,
            canEditChapterMetadata: true,
            canOpenWorkDetails: canOpenWorkDetails,
            canEditTags: ao3Actions?.canEditTags == true && ao3Actions?.ao3WorkID != nil,
            canCopyAsAO3HTML: true,
            availableExportFormats: [],
            canDeleteChapter: canDeleteChapter,
            savedVersionCount: documentBridge.versionCount > 0 ? documentBridge.versionCount : nil,
            canStartSprint: session != nil,
            isSprintRunning: sprintController.active != nil
        )
    }

    var switcherChapters: [EditorChapterSummary] {
        if isLocalOnly, !documentBridge.chapters.isEmpty {
            return documentBridge.chapterSummaries
        }
        let status: EditorChapterStatus
        if isPosted {
            status = .posted
        } else if ao3Actions?.isAO3Draft == true {
            status = .ao3Draft
        } else {
            status = .writing
        }
        return [
            EditorChapterSummary(
                id: currentSwitcherChapterID,
                number: resolvedChapterNumber,
                title: chapterTitle,
                wordCount: currentWordCount,
                status: status
            )
        ]
    }

    var currentSwitcherChapterID: String {
        if isLocalOnly, let id = documentBridge.chapterID {
            return id.uuidString
        }
        return ao3Actions?.ao3ChapterID.map(String.init) ?? recoveryTarget
    }

    var currentChapterStatus: WritingChapterStatus {
        if isPosted { return .posted }
        if ao3Actions?.isAO3Draft == true { return .ao3Draft }
        return .local
    }

    var currentDocumentTarget: ChapterEditorDocumentTarget {
        if let localDocumentTarget { return localDocumentTarget }
        return .ao3Mirror(
            ao3WorkID: ao3Actions?.ao3WorkID,
            ao3ChapterID: ao3Actions?.ao3ChapterID,
            isChapterOne: ao3Actions?.isChapterOne ?? (chapterNumber == 1)
        )
    }

    var statusSummary: EditorStatusSummary {
        let baseline = initialWordCount ?? currentWordCount
        let wordsToday = max(0, currentWordCount - baseline)
        return EditorStatusSummary(
            wordsToday: wordsToday,
            dailyGoal: nil,
            noteCount: documentBridge.annotationCount,
            tkCount: documentBridge.tkCount,
            syncState: documentBridge.syncState,
            ao3DraftDaysLeft: ao3Actions?.ao3DraftDaysLeft,
            chapterWordCount: currentWordCount,
            sprint: sprintController.statusInfo
        )
    }
}

// MARK: - Subviews

extension ChapterEditorScreen {
    var headerView: some View {
        EditorHeader(
            workTitle: resolvedWorkTitle,
            showsNotes: true,
            showsChangesToggle: false,
            isComparingChanges: false,
            onDone: { commitAndClose() },
            onNotes: { notesSheetTab = .storyNotes },
            chapterTrigger: {
                ChapterSwitcherMenu(
                    chapters: switcherChapters,
                    currentChapterID: currentSwitcherChapterID,
                    fallbackTitle: headerChapterTitle,
                    showsNewChapter: isLocalOnly && onNewLocalChapter != nil,
                    showsReorderChapters: false,
                    showsWorkDetails: canOpenWorkDetails,
                    actions: ChapterSwitcherActions(
                        onSelectChapter: { selectedID in
                            guard isLocalOnly,
                                  let uuid = UUID(uuidString: selectedID),
                                  uuid != documentBridge.chapterID
                            else { return }
                            Task {
                                _ = await commitAndPersist(kind: .edit)
                                onSwitchLocalChapter?(uuid)
                            }
                        },
                        onNewChapter: {
                            guard let onNewLocalChapter else { return }
                            Task {
                                _ = await commitAndPersist(kind: .edit)
                                onNewLocalChapter()
                            }
                        },
                        onWorkDetails: { openWorkDetails() }
                    )
                )
            },
            moreTrigger: {
                EditorMoreMenu(
                    isPosted: isPosted,
                    hasUnpostedChanges: hasUnpostedChanges,
                    savedVersionCount: menuCapabilities.savedVersionCount,
                    visibleActions: menuCapabilities.visibleActions,
                    availableExportFormats: menuCapabilities.availableExportFormats,
                    actions: makeMoreMenuActions()
                )
            }
        )
    }

    @ViewBuilder
    var noticeBanner: some View {
        VStack(spacing: 0) {
            if isPosted, hasUnpostedChanges {
                let bannerFill = appTheme.isDarkFamily
                    ? Color.subjectAmber.opacity(0.18)
                    : Color(red: 1.0, green: 0.96, blue: 0.90)
                let bannerInk = appTheme.isDarkFamily
                    ? Color.subjectAmber
                    : Color(red: 0.42, green: 0.23, blue: 0.0)
                Text(
                    "Your edits stay on this \(ThisDevice.name) until you choose "
                        + "Update on AO3 in the ••• menu."
                )
                .font(.footnote)
                .foregroundStyle(bannerInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(bannerFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            if let session, session.owner == .source {
                htmlModeStrip(session: session)
            } else if isRichMode, session?.lastSwitchChanges != nil {
                HStack {
                    Button("What changed") { showingWhatChanged = true }
                        .font(.caption.weight(.medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(.accentInk)
                    Spacer()
                }
                .padding(.horizontal, SubjectMetrics.gutter)
                .padding(.top, 6)
            }

            if let message = transientStatusMessage {
                Text(message)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SubjectMetrics.gutter)
                    .padding(.top, 6)
            }
        }
    }

    func htmlModeStrip(session: DraftSession) -> some View {
        HStack(spacing: 8) {
            Text(
                session.isRichAvailable
                    ? "Editing HTML"
                    : (session.isRichPermanentlyDisabled
                        ? "Rich Text unavailable until you reopen"
                        : "Rich Text recovering…")
            )
            .font(.caption)
            .foregroundStyle(.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Rich Text") {
                Task { _ = await session.switchToRich() }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(theme.effectiveTint)
            .disabled(!session.isRichAvailable || session.isHandingOff)
            .accessibilityLabel("Switch to Rich Text")
        }
        .padding(.horizontal, SubjectMetrics.gutter)
        .padding(.vertical, 6)
        .background(appTheme.glassFill(0.06))
    }

    @ViewBuilder
    var chapterPageBody: some View {
        if dynamicTypeSize.isAccessibilitySize {
            // At AX5 let the whole chapter page scroll so title, notes, live counters,
            // and the editing surface remain reachable without squeezing out the body.
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    chapterHeadingAndBeforeNotes
                    embeddedEditorSurface
                        .frame(minHeight: 300)
                    afterNotesBlock
                }
                .padding(.horizontal, SubjectMetrics.gutter)
                .padding(.vertical, 12)
            }
            .overlay(alignment: .bottom) { pasteOverlay }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                chapterHeadingAndBeforeNotes
                    .padding(.horizontal, SubjectMetrics.gutter)
                    .padding(.top, 10)

                embeddedEditorSurface
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)

                afterNotesBlock
                    .padding(.horizontal, SubjectMetrics.gutter)
                    .padding(.bottom, 8)
            }
            .overlay(alignment: .bottom) { pasteOverlay }
        }
    }

    var chapterHeadingAndBeforeNotes: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CHAPTER \(resolvedChapterNumber)")
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(.secondaryInk)
                TextField(
                    "Chapter title",
                    text: $chapterTitle,
                    prompt: appTheme.sepiaPrompt("Chapter title")
                )
                .font(.system(.title2, design: .serif).weight(.semibold))
                .foregroundStyle(Color.primary)
                .accessibilityLabel("Chapter title")
            }

            ChapterNotesBlocks(
                summary: $summary,
                notesBefore: $notesBefore,
                notesAfter: $notesAfter,
                placement: .beforeChapter,
                summaryExpanded: false,
                notesBeforeExpanded: false,
                notesAfterExpanded: false
            )
        }
    }

    var afterNotesBlock: some View {
        ChapterNotesBlocks(
            summary: $summary,
            notesBefore: $notesBefore,
            notesAfter: $notesAfter,
            placement: .afterChapter,
            summaryExpanded: false,
            notesBeforeExpanded: false,
            notesAfterExpanded: false
        )
    }

    var embeddedEditorSurface: some View {
        WritingTextEditor(
            text: $content,
            title: chapterDisplayTitle,
            account: account,
            target: recoveryTarget,
            field: "content",
            embedOptions: WritingTextEditorEmbedOptions(
                startsInRichMode: true,
                onSessionReady: { createdSession in
                    session = createdSession
                    if initialWordCount == nil, let count = createdSession.wordCount {
                        initialWordCount = count
                    }
                    if createdSession.owner == .rich {
                        scheduleAnnotationSync(useCurrentHTML: false)
                    }
                },
                onRichHostReady: { host in
                    richHost = host
                    host.webView.offersNoteCommand = true // this screen stores notes (T-576d)
                    syncKeysAccessorySuggestions()
                },
                onHostCommand: { command in
                    handleHostCommand(command)
                },
                nameSuggestions: nameSuggestions,
                onSelectNameSuggestion: { selected in
                    applyNameSuggestion(selected)
                }
            )
        )
        .id(recoveryTarget)
    }

    @ViewBuilder
    var pasteOverlay: some View {
        if let report = pasteTracker.activeReport {
            PasteReportCard(
                report: report,
                onUndoPaste: {
                    session?.apply(.undo)
                    withAnimationUnlessReduced(.snappy(duration: 0.2), reduceMotion: reduceMotion) {
                        pasteTracker.dismiss()
                    }
                    Task {
                        try? await Task.sleep(for: .milliseconds(150))
                        _ = await commitAndPersist(kind: .destructive)
                    }
                },
                onDismiss: {
                    withAnimationUnlessReduced(.snappy(duration: 0.2), reduceMotion: reduceMotion) {
                        pasteTracker.dismiss()
                    }
                }
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
