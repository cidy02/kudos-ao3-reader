import SwiftUI
import SwiftData

struct AddChapterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme
    @Environment(AO3AuthService.self) private var auth

    @State private var form: AO3ChapterForm
    @State private var editingGeneration: Int?
    @State private var isSaving = false
    @State private var isPosting = false
    @State private var errorMessage: String?
    @State private var isLastChapter = false
    @State private var chapterSaved = false
    @State private var savedTotal: Int?
    @State private var workTitle: String
    /// 1bq's switch, drawn off: posting goes by AO3's preview first.
    @State private var postWithoutPreview = false
    @State private var preview: AO3PreviewHTML?
    /// The work's chapter count when opened from its Chapters list; nil from
    /// Add chapter. Gates Delete chapter.
    let chapterCount: Int?
    var onSaved: () -> Void = {}

    init(
        form: AO3ChapterForm, workTitle: String, chapterCount: Int? = nil,
        onSaved: @escaping () -> Void = {}
    ) {
        self._form = State(initialValue: form)
        self.workTitle = workTitle
        self.chapterCount = chapterCount
        self.onSaved = onSaved
    }

    /// Whether the main button posts (a new or draft chapter) rather than
    /// updates a posted one. Only a post has a preview-first choice to make.
    private var posts: Bool { form.chapterID == nil || form.isDraft }

    private var accountPalette: SubjectPalette {
        theme.scopePalette
    }

    @ScaledMetric(relativeTo: .subheadline) private var actionTitleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .caption) private var footnoteSize: CGFloat = 11.5

    private var gutter: CGFloat { SubjectMetrics.accountGutter }
    private var selfGuttered: CGFloat { 0 }

    var body: some View {
        List {
            Section {
                SubjectHeaderBlock(
                    kicker: "AO3 Account",
                    title: form.chapterID == nil ? "Add chapter" : "Edit chapter",
                    subtitle: Self.subtitle(workTitle: workTitle, chapterTitle: form.title, position: form.position),
                    palette: accountPalette,
                    gutter: gutter
                )
                .pageBodyRow(top: 20, gutter: selfGuttered)
            }

            // One `List` row per field, as segments of one card. The Text card
            // was one `VStack` row, and a `List` row fires every
            // `NavigationLink` inside it — tapping Summary would have pushed all
            // four editors. The other two cards carry no links; they are
            // converted so the screen keeps one card style.
            Section {
                SectionRuleHeader(title: "Chapter")
                    .padding(.bottom, 8)
                    .pageBodyRow(top: 18, gutter: selfGuttered)
            }
            Section {
                Group { chapterRows }.disabled(chapterSaved || isSaving || isPosting)
            }

            Section {
                SectionRuleHeader(title: "Text")
                    .padding(.bottom, 8)
                    .pageBodyRow(top: 18, gutter: selfGuttered)
            }
            Section {
                Group { textRows }.disabled(chapterSaved || isSaving || isPosting)
            }

            Section {
                SectionRuleHeader(title: "Publication")
                    .padding(.bottom, 8)
                    .pageBodyRow(top: 18, gutter: selfGuttered)
            }
            Section {
                Group { publicationRows }.disabled(chapterSaved || isSaving || isPosting)
                Text("When you turn on Last chapter, Kudos sets the work's total to this chapter's "
                    + "position. AO3 marks the work complete when its posted and total chapters match.")

                    .font(.system(size: footnoteSize))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Post")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                postPanel.pageBodyRow(top: 8, gutter: gutter)
                Text("Posting a chapter notifies your subscribers. Save it as a draft if you want to "
                    + "work on it over several sittings without sending a notification.")

                    .font(.system(size: footnoteSize))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .pageBodyRow(top: 8, gutter: gutter)
            }
        }
        .cardList()
        // Rows at their own padding, not the List minimum (L3-FORM-1).
        .environment(\.defaultMinListRowHeight, 0)
        .onAppear { if editingGeneration == nil { editingGeneration = auth.sessionGeneration } }
        #if os(macOS)
        .navigationTitle(form.chapterID == nil ? "Add chapter" : "Edit chapter")
        #endif
        .subjectScreenWash(palette: accountPalette)
        .alert("AO3 could not save the chapter", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .navigationDestination(isPresented: Binding(
            get: { preview != nil }, set: { if !$0 { preview = nil } }
        )) {
            if let preview {
                WritingPreviewView(
                    preview: preview,
                    subtitle: Self.subtitle(workTitle: workTitle, chapterTitle: form.title, position: form.position),
                    postTitle: posts ? "Post chapter" : "Update",
                    // AO3's preview page names its buttons `post_button` /
                    // `update_button`; `chapters#update` takes either post name.
                    post: { try await perform(submit: posts ? .post : .update) }
                )
            }
        }
    }

    @ViewBuilder
    private var chapterRows: some View {
        let count = form.includePosition ? 3 : 2
        SubjectFormRow(label: "Title", arrangement: .control) {
            TextField("Title", text: $form.title).multilineTextAlignment(.trailing)
        }
        .panelSegment(0, of: count, gutter: gutter)
        // 1bq's "13 of 13", the way Edit work's "Chapters posted" row reads:
        // the number is the position, the total stays the writer's to type.
        let number = form.includePosition ? Self.chapterNumber(form.position) : nil
        SubjectFormRow(label: number == nil ? "Expected chapter total" : "Chapter number", arrangement: .control) {
            HStack(spacing: 6) {
                if let number {
                    Text("\(number) of").foregroundStyle(.secondary)
                }
                TextField(number == nil ? "Unknown" : "?", text: $form.wipLength)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: number == nil ? .infinity : 64)
                    .accessibilityLabel("Expected chapter total")
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
            }
        }
        .panelSegment(1, of: count, gutter: gutter)
        if form.includePosition {
            // 1bq's "After chapter 12". Only the words around the field change:
            // it still edits, and posts, the same position value.
            SubjectFormRow(label: "Position", arrangement: .control) {
                HStack(spacing: 6) {
                    Text("After chapter").foregroundStyle(.secondary)
                    TextField("?", text: Binding(
                        get: { Self.afterChapterText(position: form.position) },
                        set: { form.position = Self.position(afterChapterText: $0) }
                    ))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 64)
                    .accessibilityLabel("Position, after chapter")
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                }
            }
            .panelSegment(2, of: count, gutter: gutter)
        }
    }

    /// The chapter's own number, when AO3's form gave it a numeric position.
    static func chapterNumber(_ position: String) -> Int? {
        Int(position.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil }
    }

    /// 1bq's header: "The Weight of Water · chapter 13". Falls back to the
    /// chapter's title, then to "chapter", when there is no position to name.
    static func subtitle(workTitle: String, chapterTitle: String, position: String) -> String {
        if let number = chapterNumber(position) { return "\(workTitle) · chapter \(number)" }
        return "\(workTitle) · \(chapterTitle.isEmpty ? "chapter" : chapterTitle)"
    }

    /// Position 13 reads "12" after "After chapter". Anything that is not a
    /// positive number is shown as typed, so nothing the writer entered is hidden.
    static func afterChapterText(position: String) -> String {
        chapterNumber(position).map { String($0 - 1) } ?? position
    }

    /// The inverse: "12" after "After chapter" is position 13. Non-numbers pass
    /// through untouched, which is what the plain Position field posted.
    static func position(afterChapterText text: String) -> String {
        guard let after = Int(text.trimmingCharacters(in: .whitespaces)), after >= 0 else { return text }
        return String(after + 1)
    }

    private var recoveryTarget: String { "work:\(form.workID):chapter:\(form.chapterID.map(String.init) ?? "new")" }

    @ViewBuilder
    private var textRows: some View {
        WritingTextEditorRow(
            title: "Chapter text", text: $form.content, target: recoveryTarget, field: "content",
            emptyHint: "opens the editor with plain text, AO3’s HTML tags, or a paste from elsewhere.",
            ruleTitle: Self.chapterNumber(form.position).map { "Chapter \($0)" },
            chapterActions: WritingChapterEditorActions(
                preview: { openPreview() },
                deleteName: Self.offersDelete(chapterID: form.chapterID, chapterCount: chapterCount)
                    ? Self.chapterName(position: form.position, title: form.title) : nil,
                delete: { deleteChapter() }
            )
        )
        .panelSegment(0, of: 4, gutter: gutter)
        WritingTextEditorRow(title: "Summary", text: $form.summary, target: recoveryTarget, field: "summary")
            .panelSegment(1, of: 4, gutter: gutter)
        WritingTextEditorRow(title: "Beginning notes", text: $form.notes, target: recoveryTarget, field: "notes")
            .panelSegment(2, of: 4, gutter: gutter)
        WritingTextEditorRow(title: "End notes", text: $form.endnotes, target: recoveryTarget, field: "endnotes")
            .panelSegment(3, of: 4, gutter: gutter)
    }

    private var publicationDate: Binding<Date> {
        Binding(
            get: {
                AO3PublicationDate.date(
                    year: form.publishedYear, month: form.publishedMonth, day: form.publishedDay
                ) ?? Date()
            },
            set: { date in
                let fields = AO3PublicationDate.fields(for: date)
                form.publishedYear = fields.year
                form.publishedMonth = fields.month
                form.publishedDay = fields.day
            }
        )
    }

    @ViewBuilder
    private var publicationRows: some View {
        let showsDate = !form.publishedYear.isEmpty
        let count = (showsDate ? 3 : 2) + (posts ? 1 : 0)
        SubjectFormRow(label: "Set a different publication date", arrangement: .control) {
            Toggle("Custom publication date", isOn: Binding(
                get: { !form.publishedYear.isEmpty },
                set: { enabled in
                    if enabled { publicationDate.wrappedValue = Date() } else { form.publishedYear = ""; form.publishedMonth = ""; form.publishedDay = "" }
                }
            )).labelsHidden()
        }
        .panelSegment(0, of: count, gutter: gutter)
        if showsDate {
            SubjectFormRow(label: "Publication date", arrangement: .control) {
                DatePicker("Publication date", selection: publicationDate, displayedComponents: .date)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .panelSegment(1, of: count, gutter: gutter)
        }
        // Titled even though hidden: `labelsHidden` keeps the title for
        // VoiceOver, and an empty one announced a bare "switch".
        if posts {
            SubjectFormRow(label: "Post without preview", arrangement: .control) {
                Toggle("Post without preview", isOn: $postWithoutPreview).labelsHidden()
            }
            .panelSegment(count - 2, of: count, gutter: gutter)
        }
        SubjectFormRow(label: "This is the last chapter", arrangement: .control) {
            Toggle("This is the last chapter", isOn: $isLastChapter)
                .labelsHidden()
        }
        .panelSegment(count - 1, of: count, gutter: gutter)
    }

    private var postPanel: some View {
        VStack(spacing: 0) {
            if chapterSaved {
                Button("Retry updating the work total") { save(submit: .update) }
                    .padding().disabled(isSaving || isPosting)
                Text("The chapter was saved. Only the work total will be retried.")
                    .font(.caption).foregroundStyle(.secondary).padding()
            } else {
            Button {
                // AO3's two buttons on this form: `post_without_preview_button`
                // posts at once, `preview_button` goes by the preview page.
                if posts && !postWithoutPreview { openPreview() } else {
                    save(submit: posts ? .postWithoutPreview : .update)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.up.circle.fill")
                        .frame(width: 20)
                    Text(form.chapterID != nil && !form.isDraft ? "Save chapter changes" : "Post chapter now")
                        .font(.system(size: actionTitleSize))
                    Spacer()
                }
                .foregroundStyle(theme.appTheme.statusSuccessColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isSaving || isPosting)

            if form.chapterID == nil || form.isDraft {
            SubjectRowSeparator()

            Button {
                save(submit: .saveDraft)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text.fill")
                        .frame(width: 20)
                    Text("Save as draft")
                        .font(.system(size: actionTitleSize))
                    Spacer()
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isSaving || isPosting)
            }
            }
        }
        .subjectPanel()
    }

    private func save(submit: AO3WorkSubmitAction) {
        guard !isSaving && !isPosting else { return }
        Task {
            do { try await perform(submit: submit) } catch { errorMessage = UserFacingError.message(for: error) }
        }
    }

    /// The one save path, run by this form's buttons and by the preview's
    /// Post alike. Closes the form — and a preview above it — on success.
    private func perform(submit: AO3WorkSubmitAction) async throws {
        // Checked here, not only in `save`: its Task starts a beat after the
        // tap, and a second tap in that beat must not post twice.
        guard !isSaving && !isPosting else { return }
        guard editingGeneration == auth.sessionGeneration else {
            throw AO3WorkWriteError.rejected("Your AO3 session changed. Reopen this form before saving.")
        }
        let isPost = submit == .post || submit == .postWithoutPreview
        if isPost { isPosting = true } else { isSaving = true }

        defer { if chapterSaved { onSaved() } }
        do {
            if !chapterSaved {
                savedTotal = nil
                if isLastChapter {
                    guard let total = Int(form.position), total > 0 else {
                        throw AO3WorkWriteError.rejected("Enter this chapter’s position to mark it as the last chapter.")
                    }
                    savedTotal = total
                }
                try await AO3RequestCoordinator.shared.withSlot {
                    guard editingGeneration == auth.sessionGeneration else { throw AO3WorkWriteError.notSignedIn }
                    if form.chapterID == nil { return try await auth.createChapter(form, submit: submit) } else { return try await auth.updateChapter(form, submit: submit) }
                }
                chapterSaved = true
            }
            if let savedTotal {
                guard editingGeneration == auth.sessionGeneration else { throw AO3WorkWriteError.notSignedIn }
                try await AO3RequestCoordinator.shared.withSlot {
                    guard editingGeneration == auth.sessionGeneration else { throw AO3WorkWriteError.notSignedIn }
                    return try await auth.updateWorkTotals(workID: form.workID, posted: nil, total: savedTotal)
                }
            }
            preview = nil
            dismiss()
        } catch {
            if isPost { isPosting = false } else { isSaving = false }
            throw AO3WorkWriteError.rejected(
                (chapterSaved ? "The chapter was saved, but the work total was not updated. " : "")
                    + UserFacingError.message(for: error)
            )
        }
    }
}

// MARK: - 1bq preview path, 1bv chapter menu

extension AddChapterView {
    /// AO3 saves a NEW chapter as a draft to preview it (`chapters#create`
    /// redirects to its preview), so the form adopts that draft before
    /// anything else is sent — Post from the preview then updates it rather
    /// than creating a second chapter. A chapter AO3 already has only renders.
    private func openPreview() {
        guard !isSaving && !isPosting else { return }
        guard editingGeneration == auth.sessionGeneration else {
            errorMessage = "Your AO3 session changed. Reopen this form before saving."
            return
        }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let wasNew = form.chapterID == nil
                let page = try await AO3RequestCoordinator.shared.withSlot {
                    guard editingGeneration == auth.sessionGeneration else { throw AO3WorkWriteError.notSignedIn }
                    return try await auth.previewChapter(form)
                }
                form = try form.adopting(page)
                if wasNew { onSaved() }
                preview = page
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
        }
    }

    /// Asked for in the editor, whose alert names the chapter.
    private func deleteChapter() {
        guard let chapterID = form.chapterID, let generation = editingGeneration,
              !isSaving, !isPosting else { return }
        isSaving = true
        Task {
            do {
                try await AO3RequestCoordinator.shared.withSlot {
                    try await auth.deleteChapter(
                        workID: form.workID, chapterID: chapterID, expectedGeneration: generation
                    )
                }
                onSaved()
                dismiss()
            } catch is CancellationError {
                errorMessage = "Your AO3 session changed, so nothing was deleted."
                isSaving = false
            } catch {
                errorMessage = "The chapter was not deleted. " + UserFacingError.message(for: error)
                isSaving = false
            }
        }
    }

    /// AO3 deletes neither a work's only chapter nor its only posted one
    /// (`chapters#destroy`, and `chapters/manage` draws Delete only past one
    /// chapter). The second needs each chapter's posted state, which the
    /// chapter index doesn't carry — AO3's refusal flash covers that case.
    static func offersDelete(chapterID: Int?, chapterCount: Int?) -> Bool {
        chapterID != nil && (chapterCount ?? 0) > 1
    }

    /// otwarchive's `chapter_header` ("Chapter 3") plus the title, as its
    /// `full_chapter_title` joins them.
    static func chapterName(position: String, title: String) -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = chapterNumber(position) else { return title.isEmpty ? "this chapter" : title }
        return title.isEmpty ? "Chapter \(number)" : "Chapter \(number): \(title)"
    }
}
