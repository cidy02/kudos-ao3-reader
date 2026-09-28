import SwiftSoup
import SwiftUI

/// Shared chapter/summary/notes editor. Done updates the parent form; only that
/// form's explicit Save/Post action writes to AO3.
///
/// Typing costs nothing proportional to the chapter
/// (docs/WRITING_EDITOR_ARCHITECTURE.md D8). The form binding, the recovery copy
/// and the word count change only at checkpoints (§8.1): 1.5 s after typing
/// stops, at least every 20 s while it doesn't, and on Done, leaving the screen,
/// restoring a copy, a scene change or a memory warning. Disk work and counting
/// run off the main thread.
struct WritingTextEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(ThemeManager.self) private var theme
    /// 1bv's serif at 15.5, scaled with Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var editorFontSize = 15.5
    @Binding var text: String
    let title: String
    let ruleTitle: String?
    let account: String
    let target: String
    let field: String
    let chapterActions: WritingChapterEditorActions?

    @State private var controller: WritingTextController?
    @State private var checkpoints: WritingCheckpointScheduler?
    @State private var recoveryWriter: WritingRecoveryWriter?
    /// Nil until the first count, made off the main thread, lands.
    @State private var wordCount: Int?
    /// Which checkpoint the shown count belongs to. A count that finishes after
    /// a newer one started is dropped.
    @State private var countedCheckpoint = 0
    @State private var original: String
    @State private var recoveries: [WritingTextRecovery.Copy] = []
    @State private var selectedRecovery: URL?
    @State private var recoveryID = UUID()
    @State private var errorMessage: String?
    @State private var showLink = false
    @State private var link = "https://"
    @State private var showDeleteChapter = false
    /// OD1's read-only preview. The text view stays mounted under it, so the
    /// selection and the undo stack survive a round trip.
    @State private var isPreviewing = false
    /// What the preview shows: nil while the parse for this preview is running.
    @State private var previewState: WritingBufferPreview.State?
    /// Bumped on every entry and exit, so only the parse for the preview on
    /// screen may publish (`WritingBufferPreview.publishes`).
    @State private var previewGeneration = 0
    private let store = WritingTextRecovery()

    init(
        text: Binding<String>, title: String, ruleTitle: String? = nil,
        account: String, target: String, field: String,
        chapterActions: WritingChapterEditorActions? = nil
    ) {
        _text = text
        self.title = title
        self.ruleTitle = ruleTitle
        self.account = account
        self.target = target
        self.field = field
        self.chapterActions = chapterActions
        _original = State(initialValue: text.wrappedValue)
    }

    private var recoveryKey: URL { store.fileURL(account: account, target: target, field: field) }
    private var recoveryURL: URL {
        recoveryKey.deletingPathExtension().appendingPathExtension(recoveryID.uuidString).appendingPathExtension("json")
    }
    private var recovery: WritingTextRecovery.Copy? {
        recoveries.first { $0.id == selectedRecovery } ?? recoveries.first
    }

    var body: some View {
        VStack(spacing: 0) {
            // 1bv's rule: the chapter's name, then the word count as of the last
            // checkpoint (E1 counts off the main thread, never per keystroke).
            SectionRuleHeader(
                title: ruleTitle ?? title,
                countText: wordCount.map { "\($0.formatted()) \($0 == 1 ? "word" : "words")" }
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            ZStack {
                if let controller {
                    WritingNativeTextView(controller: controller)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(isPreviewing ? 0 : 1)
                        .accessibilityHidden(isPreviewing)
                        // Nothing may edit the buffer behind the preview.
                        .allowsHitTesting(!isPreviewing)
                } else { ProgressView() }
                if isPreviewing { preview }
            }
            Text("Local recovery · Save on the work form")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal)
            #if os(iOS)
            // Above the keyboard: the screen avoids it, so the bar rides on top.
            tagBar
            #endif
            // 1bv's footnote under the bar.
            Text("AO3 accepts a limited set of HTML. Anything else is stripped on post, "
                + "so the bar inserts tags rather than styling text.")
                .font(.caption2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal).padding(.bottom, 6)
        }
        .tint(theme.scopePalette.accent)
        .navigationTitle(title)
        .subjectScreenWash(palette: theme.scopePalette)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                #if os(macOS)
                formatMenu
                #endif
                Button(
                    isPreviewing ? "Edit" : "Preview",
                    systemImage: isPreviewing ? "chevron.left.forwardslash.chevron.right" : "eye"
                ) { togglePreview() }
                // Disabled in preview: an undo there would change the buffer
                // under a preview that still shows the old text.
                Button("Undo", systemImage: "arrow.uturn.backward") { controller?.command("undo") }
                    .disabled(isPreviewing)
                Button("Redo", systemImage: "arrow.uturn.forward") { controller?.command("redo") }
                    .disabled(isPreviewing)
                moreMenu
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { close() }
            }
        }
        // 1bo's delete alert shape: named, destructive, never the default.
        .alert(
            "Delete “\(chapterActions?.deleteName ?? "")”?",
            isPresented: $showDeleteChapter
        ) {
            Button("Delete on AO3", role: .destructive) { close(then: chapterActions?.delete) }
            Button("Cancel", role: .cancel) {}
        } message: {
            // chapters/edit.html.erb's own confirmation.
            Text("This will delete all comments on the chapter as well and cannot be undone.")
        }
        .onAppear(perform: start)
        .onChange(of: editorFontSize) { _, value in controller?.setAppearance(theme.appTheme, fontSize: value) }
        .onChange(of: theme.appTheme) { _, value in controller?.setAppearance(value, fontSize: editorFontSize) }
        // Going inactive or to the background checkpoints without touching an
        // IME composition (§7.6): the app may not come back.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { checkpoints?.fireNow() }
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            checkpoints?.fireNow()
        }
        #endif
        .onDisappear(perform: finish)
        .alert("Editor error", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .alert("Insert link", isPresented: $showLink) {
            TextField("https://example.com", text: $link)
            Button("Insert") {
                if WritingMarkup.safeLink(link) { controller?.command("a", link: link) } else { errorMessage = "Enter an HTTP, HTTPS, or mailto link." }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: Binding(
            get: { !recoveries.isEmpty }, set: { if !$0 { recoveries = [] } }
        )) {
            recoverySheet
        }
    }

    /// 1bv's overflow menu, less "Edit tags directly": this buffer is always
    /// the markup (OD1). Preview and Delete are the chapter editor's alone.
    private var moreMenu: some View {
        Menu("More", systemImage: "ellipsis.circle") {
            // ⌥⇧⌘V, the platform's own "paste and match style": plain ⌘V is
            // the text view's paste.
            Button("Paste as plain text", systemImage: "doc.on.clipboard") { controller?.pastePlainText() }
                .keyboardShortcut("v", modifiers: [.command, .option, .shift])
            if let chapterActions {
                Button("Preview on AO3", systemImage: "arrow.up.forward.square") {
                    close(then: chapterActions.preview)
                }
                if chapterActions.deleteName != nil {
                    Button("Delete chapter", systemImage: "trash", role: .destructive) {
                        showDeleteChapter = true
                    }
                }
            }
        }
    }

    /// The buffer through the renderer AO3 HTML already has here
    /// (`AO3RichTextView`, as work summaries and the T-267 preview draw it).
    @ViewBuilder
    private var preview: some View {
        switch previewState {
        case nil:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .rendered(document):
            ScrollView {
                AO3RichTextView(document: document)
                    .font(.system(size: editorFontSize, design: .serif))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 16)
            }
            .accessibilityLabel("Preview")
        case .failed:
            ContentUnavailableView(
                "Couldn't render this HTML",
                systemImage: "exclamationmark.triangle",
                description: Text("Your text is unchanged. Tap Edit to go back to it.")
            )
        }
    }

    /// Into preview: the composition is committed and the keyboard put away,
    /// then the current buffer is parsed off the main thread. Back to edit:
    /// the text view was never removed, so it is exactly as it was left.
    private func togglePreview() {
        guard let controller else { return }
        previewGeneration += 1
        if isPreviewing {
            isPreviewing = false
            return
        }
        controller.commitComposition()
        controller.endEditing()
        let value = controller.text
        let generation = previewGeneration
        previewState = nil
        isPreviewing = true
        Task {
            let state = await Task.detached(priority: .userInitiated) {
                WritingBufferPreview.state(for: value)
            }.value
            guard WritingBufferPreview.publishes(
                generation: generation, current: previewGeneration, isPreviewing: isPreviewing
            ) else { return }
            previewState = state
        }
    }

    /// The tag bar: every AO3-allowed tag, as 1bv draws it (the tag over what it does).
    private var tagBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 16) {
                ForEach(AO3MarkupTag.Group.allCases) { group in
                    HStack(spacing: 6) {
                        Text(group.title).font(.caption).foregroundStyle(.secondary)
                        ForEach(group.tags(in: AO3MarkupTag.writing)) { tag in
                            tagButton(tag)
                        }
                    }
                }
            }
            .buttonStyle(.bordered).padding(.horizontal).padding(.vertical, 6)
        }
        .disabled(isPreviewing)
    }

    #if os(macOS)
    /// The same tags, in the window toolbar.
    private var formatMenu: some View {
        Menu("Format", systemImage: "textformat") {
            ForEach(AO3MarkupTag.Group.allCases) { group in
                Section(group.title) {
                    ForEach(group.tags(in: AO3MarkupTag.writing)) { tag in
                        Button("\(tag.name)  <\(tag.tagLabel)>", systemImage: tag.symbol) { apply(tag) }
                    }
                }
            }
        }
        .disabled(isPreviewing)
    }
    #endif

    /// Done's checkpoint, then `action` — after it, the form holds this text.
    private func close(then action: (() -> Void)? = nil) {
        controller?.commitComposition()
        checkpoints?.fireNow()
        dismiss()
        action?()
    }

    /// Labelled with the tag it writes, as the comment tray prints the tag under
    /// every row: the same teaching idea, on the screen where the writer is
    /// typing real HTML anyway.
    ///
    /// The link is the one tag that cannot be written from a button alone, so it
    /// opens the alert that asks for the URL and validates it. Everything else
    /// goes straight to the buffer.
    private func tagButton(_ tag: AO3MarkupTag) -> some View {
        Button { apply(tag) } label: {
            VStack(spacing: 1) {
                Text("<\(tag.tagLabel)>").font(.caption.monospaced())
                Text(tag.name.lowercased()).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .minimumHitTarget()
        .accessibilityLabel(tag.name)
    }

    private func apply(_ tag: AO3MarkupTag) {
        if tag == .link { showLink = true } else { controller?.command(tag.element) }
    }

    private var recoverySheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recover unfinished text?").font(.headline)
            if let copy = recovery {
                let recovery = copy.entry
                if recoveries.count > 1 {
                    Picker("Local copy", selection: Binding(
                        get: { copy.id }, set: { selectedRecovery = $0 }
                    )) {
                        ForEach(recoveries) { item in
                            Text(item.entry.savedAt.formatted(date: .abbreviated, time: .standard)).tag(item.id)
                        }
                    }
                }
                Text("A local copy was saved \(recovery.savedAt.formatted()).")
                if recovery.originalDigest != WritingTextRecovery.digest(original) {
                    Text("The form text has changed since this copy was started. Review it before replacing the form text.")
                }
                ScrollView { Text(recovery.text).font(.body.monospaced()).textSelection(.enabled) }
                Button("Restore local copy") {
                    controller?.restore(recovery.text)
                    // Straight into the form and a fresh recovery copy, rather
                    // than waiting for the idle timer.
                    checkpoints?.fireNow()
                    self.recoveries = []
                }
                Button("Keep form text", role: .cancel) { self.recoveries = [] }
                Button("Delete this local copy", role: .destructive) {
                    do {
                        try FileManager.default.removeItem(at: copy.url)
                        recoveries.removeAll { $0.id == copy.id }
                    } catch { errorMessage = error.localizedDescription }
                }
            }
        }
        .padding()
        .interactiveDismissDisabled()
    }

    private func start() {
        guard controller == nil else { return }
        let editor = WritingTextController(text: text)
        controller = editor
        editor.setAppearance(theme.appTheme, fontSize: editorFontSize)
        recoveryWriter = WritingRecoveryWriter(store: store, url: recoveryURL, original: original)
        let scheduler = WritingCheckpointScheduler { checkpoint() }
        checkpoints = scheduler
        editor.onEdit = { [weak scheduler] in scheduler?.noteEdit() }
        recount(text, checkpoint: 0)
        loadRecoveries()
    }

    /// One checkpoint (docs/WRITING_EDITOR_ARCHITECTURE.md §8.2): the text,
    /// read once, goes to the form binding, then to the recovery copy and the
    /// word count off the main thread. Nothing happens if it didn't change.
    private func checkpoint() {
        guard let controller, let scheduler = checkpoints,
              let value = controller.takeCheckpoint() else { return }
        text = value
        let sequence = scheduler.checkpointCount
        if let recoveryWriter {
            // The write is queued, and the app can be suspended before it runs
            // (a scene change, or an idle or Done write still in flight when the
            // app backgrounds). The assertion buys the documented finish window;
            // the expiration handler ends it rather than overrunning.
            #if os(iOS)
            var assertion = UIBackgroundTaskIdentifier.invalid
            assertion = UIApplication.shared.beginBackgroundTask(withName: "Writing recovery") {
                UIApplication.shared.endBackgroundTask(assertion)
                assertion = .invalid
            }
            #endif
            Task {
                #if os(iOS)
                defer {
                    if assertion != .invalid { UIApplication.shared.endBackgroundTask(assertion) }
                    assertion = .invalid
                }
                #endif
                do {
                    try await recoveryWriter.write(value, sequence: sequence)
                } catch {
                    errorMessage = "Local recovery could not be saved: \(error.localizedDescription)"
                }
            }
        }
        recount(value, checkpoint: sequence)
    }

    private func recount(_ value: String, checkpoint: Int) {
        countedCheckpoint = checkpoint
        Task {
            let count = await Task.detached(priority: .userInitiated) {
                WritingWordCount.count(value)
            }.value
            guard countedCheckpoint == checkpoint else { return }
            wordCount = count
        }
    }

    /// Earlier sessions' copies, read and decoded off the main thread (§8.5).
    /// This session's own file is left out: it may exist by the time the read
    /// finishes.
    private func loadRecoveries() {
        let store = store
        let key = recoveryKey
        let ownFile = recoveryURL.lastPathComponent
        let formText = text
        Task {
            do {
                recoveries = try await Task.detached(priority: .userInitiated) {
                    try store.copies(for: key).filter {
                        $0.url.lastPathComponent != ownFile && $0.entry.text != formText
                    }
                }.value
            } catch {
                errorMessage = "The local recovery copy could not be read: \(error.localizedDescription)"
            }
        }
    }

    /// Leaving the screen: commit any composition, checkpoint, then break the
    /// editor ↔ controller ↔ scheduler cycle.
    private func finish() {
        controller?.commitComposition()
        checkpoints?.fireNow()
        checkpoints?.cancel()
        checkpoints = nil
        controller?.onEdit = nil
        controller = nil
    }
}

/// What the chapter form lends its text editor. Both run after the editor has
/// checkpointed into the form and closed, so they act on the text just typed.
struct WritingChapterEditorActions {
    var preview: () -> Void
    /// Names the chapter in the delete alert; nil leaves Delete chapter out.
    var deleteName: String?
    var delete: () -> Void = {}
}

struct WritingTextEditorRow: View {
    @Environment(AO3AuthService.self) private var auth
    let title: String
    @Binding var text: String
    let target: String
    let field: String
    /// 1bo/1br: the text itself under the label, in place of "Set".
    var previewsText = false
    /// 1bq: what an empty row opens, read as "Empty — <hint>" under the label.
    var emptyHint: String?
    /// The editor's section rule — 1bv's "Chapter 13". Defaults to `title`.
    var ruleTitle: String?
    /// The chapter text row's menu items; nil on every other row.
    var chapterActions: WritingChapterEditorActions?

    var body: some View {
        Group {
            if let detail = Self.detail(text: text, previewsText: previewsText, emptyHint: emptyHint) {
                // The spec's two-line row: label and chevron, then the detail
                // 4pt under it. The row's own 12pt bottom padding is taken back
                // so the pair reads as one row, not a row and a caption.
                VStack(alignment: .leading, spacing: 0) {
                    SubjectFormRow(label: title, showsDisclosure: true) { EmptyView() }
                    Text(detail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.top, -8)
                        .padding(.bottom, 11)
                }
            } else {
                SubjectFormRow(label: title, value: text.isEmpty ? "Empty" : "Set", showsDisclosure: true)
            }
        }
        .subjectRowNavigation(accessibilityLabel: title) {
            WritingTextEditor(
                text: $text, title: title, ruleTitle: ruleTitle,
                account: auth.username ?? "", target: target, field: field,
                chapterActions: chapterActions
            )
        }
    }

    /// The second line, or nil for the one-line "Empty"/"Set" row. A preview is
    /// the text with its markup stripped; markup with no words falls back to
    /// "Set" rather than previewing an empty line.
    static func detail(text: String, previewsText: Bool, emptyHint: String?) -> String? {
        if text.isEmpty { return emptyHint.map { "Empty — \($0)" } }
        guard previewsText else { return nil }
        let plain = text.strippingHTML().trimmingCharacters(in: .whitespacesAndNewlines)
        return plain.isEmpty ? nil : plain
    }
}

/// OD1's preview model: the buffer parsed as AO3 HTML and reduced to the blocks
/// `AO3RichTextView` draws, with the same parser AO3's pages use here.
nonisolated enum WritingBufferPreview {
    enum State: Equatable {
        case rendered(AO3RichText)
        /// The HTML did not parse: said so, never drawn as an empty chapter.
        case failed
    }

    static func state(for html: String) -> State {
        guard let body = try? SwiftSoup.parseBodyFragment(html).body(),
              let document = try? AO3Client.parseRichText(body)
        else { return .failed }
        return .rendered(document)
    }

    /// A parse publishes only if it belongs to the preview still on screen:
    /// leaving preview, or entering it again, starts a new generation.
    static func publishes(generation: Int, current: Int, isPreviewing: Bool) -> Bool {
        isPreviewing && generation == current
    }
}
