import SwiftUI

/// Shared chapter/summary/notes editor. Done updates the parent form; only that
/// form's explicit Save/Post action writes to AO3.
struct WritingTextEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme
    @ScaledMetric(relativeTo: .body) private var editorFontSize = 17.0
    @Binding var text: String
    let title: String
    let account: String
    let target: String
    let field: String

    @State private var controller: WritingHTMLController?
    @State private var sourceMode: Bool
    @State private var original: String
    @State private var recoveries: [WritingTextRecovery.Copy] = []
    @State private var selectedRecovery: URL?
    @State private var recoveryID = UUID()
    @State private var errorMessage: String?
    @State private var showLink = false
    @State private var link = "https://"
    private let store = WritingTextRecovery()

    init(text: Binding<String>, title: String, account: String, target: String, field: String) {
        _text = text
        self.title = title
        self.account = account
        self.target = target
        self.field = field
        _original = State(initialValue: text.wrappedValue)
        _sourceMode = State(initialValue: !WritingHTMLDocument.supportsRichEditing(text.wrappedValue))
    }

    private var recoveryKey: URL { store.fileURL(account: account, target: target, field: field) }
    private var recoveryURL: URL {
        recoveryKey.deletingPathExtension().appendingPathExtension(recoveryID.uuidString).appendingPathExtension("json")
    }
    private var recovery: WritingTextRecovery.Copy? {
        recoveries.first { $0.id == selectedRecovery } ?? recoveries.first
    }
    private var supportsRich: Bool { WritingHTMLDocument.supportsRichEditing(text) }

    private var wordCount: Int { text.strippingHTML().split(whereSeparator: \.isWhitespace).count }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Editing mode", selection: $sourceMode) {
                Text("Formatted").tag(false)
                Text("HTML").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .disabled(!supportsRich)
            if !supportsRich {
                Text("This text contains markup that needs HTML mode. It is kept intact.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            }
            if let controller { WebView(webView: controller.webView) }
            else { ProgressView() }
            HStack {
                Text("\(wordCount) words")
                Spacer()
                Text("Local recovery · Save on the work form")
            }
            .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            ScrollView(.horizontal) {
                HStack {
                    tagButton("em", label: "Italic")
                    tagButton("strong", label: "Bold")
                    tagButton("p", label: "Paragraph")
                    tagButton("br", label: "Line break")
                    tagButton("hr", label: "Rule")
                    Button("Link") { showLink = true }
                    tagButton("blockquote", label: "Quote")
                }
                .buttonStyle(.bordered).padding()
            }
        }
        .tint(theme.appTheme.subjectPalette(hue: theme.scopeHue).accent)
        .navigationTitle(title)
        .subjectScreenWash(palette: theme.appTheme.subjectPalette(hue: theme.scopeHue))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Undo", systemImage: "arrow.uturn.backward") { controller?.command("undo") }
                Button("Redo", systemImage: "arrow.uturn.forward") { controller?.command("redo") }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    Task {
                        do { try await controller?.flush(); dismiss() }
                        catch { errorMessage = error.localizedDescription }
                    }
                }
            }
        }
        .onAppear(perform: start)
        .onChange(of: editorFontSize) { _, value in controller?.setAppearance(theme.appTheme, fontSize: value) }
        .onChange(of: theme.appTheme) { _, value in controller?.setAppearance(value, fontSize: editorFontSize) }
        .onDisappear {
            guard let closing = controller else { return }
            controller = nil
            Task {
                do { try await closing.flush() }
                catch { errorMessage = error.localizedDescription }
                closing.stop()
            }
        }
        .onChange(of: sourceMode) { _, value in controller?.set(text: text, sourceMode: value) }
        .alert("Editor error", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .alert("Insert link", isPresented: $showLink) {
            TextField("https://example.com", text: $link)
            Button("Insert") {
                if WritingHTMLDocument.safeLink(link) { controller?.command("a", link: link) }
                else { errorMessage = "Enter an HTTP, HTTPS, or mailto link." }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: Binding(
            get: { !recoveries.isEmpty }, set: { if !$0 { recoveries = [] } }
        )) {
            recoverySheet
        }
    }

    private func tagButton(_ tag: String, label: String) -> some View {
        Button("<\(tag)>") { controller?.command(tag) }
            .accessibilityLabel(label)
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
                    text = recovery.text
                    sourceMode = !WritingHTMLDocument.supportsRichEditing(text)
                    controller?.set(text: text, sourceMode: sourceMode)
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
        let editor = WritingHTMLController(text: text)
        controller = editor
        editor.setAppearance(theme.appTheme, fontSize: editorFontSize)
        editor.onChange = { value in
            text = value
            do { try store.save(text: value, original: original, to: recoveryURL) }
            catch { errorMessage = "Local recovery could not be saved: \(error.localizedDescription)" }
        }
        editor.onError = { errorMessage = $0 }
        controller?.set(text: text, sourceMode: sourceMode)
        do {
            recoveries = try store.copies(for: recoveryKey).filter { $0.entry.text != text }
        } catch { errorMessage = "The local recovery copy could not be read: \(error.localizedDescription)" }
    }
}

struct WritingTextEditorRow: View {
    @Environment(AO3AuthService.self) private var auth
    let title: String
    @Binding var text: String
    let target: String
    let field: String

    var body: some View {
        NavigationLink {
            WritingTextEditor(text: $text, title: title, account: auth.username ?? "", target: target, field: field)
        } label: {
            SubjectFormRow(label: title, value: text.isEmpty ? "Empty" : "Set", showsDisclosure: true)
        }
        .buttonStyle(.plain)
    }
}
