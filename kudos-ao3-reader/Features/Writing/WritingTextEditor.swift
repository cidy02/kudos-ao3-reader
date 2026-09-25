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
    private let store = WritingTextRecovery()

    init(
        text: Binding<String>, title: String, ruleTitle: String? = nil,
        account: String, target: String, field: String
    ) {
        _text = text
        self.title = title
        self.ruleTitle = ruleTitle
        self.account = account
        self.target = target
        self.field = field
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
            if let controller {
                WritingNativeTextView(controller: controller)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { ProgressView() }
            Text("Local recovery · Save on the work form")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal)
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
                .buttonStyle(.bordered).padding()
            }
        }
        .tint(theme.scopePalette.accent)
        .navigationTitle(title)
        .subjectScreenWash(palette: theme.scopePalette)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Undo", systemImage: "arrow.uturn.backward") { controller?.command("undo") }
                Button("Redo", systemImage: "arrow.uturn.forward") { controller?.command("redo") }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    controller?.commitComposition()
                    checkpoints?.fireNow()
                    dismiss()
                }
            }
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

    /// Labelled with the tag it writes, as the comment tray prints the tag under
    /// every row: the same teaching idea, on the screen where the writer is
    /// typing real HTML anyway.
    ///
    /// The link is the one tag that cannot be written from a button alone, so it
    /// opens the alert that asks for the URL and validates it. Everything else
    /// goes straight to the buffer.
    private func tagButton(_ tag: AO3MarkupTag) -> some View {
        Button("<\(tag.tagLabel)>") {
            if tag == .link { showLink = true } else { controller?.command(tag.element) }
        }
        .accessibilityLabel(tag.name)
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
            Task {
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
                account: auth.username ?? "", target: target, field: field
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
