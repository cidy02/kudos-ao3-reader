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
    var onSaved: () -> Void = {}

    init(form: AO3ChapterForm, workTitle: String, onSaved: @escaping () -> Void = {}) {
        self._form = State(initialValue: form)
        self.workTitle = workTitle
        self.onSaved = onSaved
    }

    private var accountPalette: SubjectPalette {
        theme.scopePalette
    }

    private var gutter: CGFloat { SubjectMetrics.accountGutter }
    private var selfGuttered: CGFloat { 0 }

    var body: some View {
        List {
            Section {
                SubjectHeaderBlock(
                    kicker: "AO3 Account",
                    title: form.chapterID == nil ? "Add chapter" : "Edit chapter",
                    subtitle: "\(workTitle) · \(form.title.isEmpty ? "chapter" : form.title)",
                    palette: accountPalette,
                    gutter: gutter
                )
                .pageBodyRow(top: 20, gutter: selfGuttered)
            }

            Section {
                SectionRuleHeader(title: "Chapter")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                chapterPanel.disabled(chapterSaved || isSaving || isPosting).pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Text")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                textPanel.disabled(chapterSaved || isSaving || isPosting).pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Publication")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                publicationPanel.disabled(chapterSaved || isSaving || isPosting).pageBodyRow(top: 8, gutter: gutter)
                Text("The last-chapter switch writes the total on the work rather "
                    + "than a flag of its own, which is how AO3 records a finished work.")

                    .font(.system(size: 11.5))
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
                Text("Subscribers are notified on post, so the draft path exists to write "
                    + "a chapter over several sittings without sending twelve notifications.")

                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .pageBodyRow(top: 8, gutter: gutter)
            }
        }
        .cardList()
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
    }

    private var chapterPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Title", arrangement: .control) {
                TextField("Title", text: $form.title).multilineTextAlignment(.trailing)
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "Expected chapter total", arrangement: .control) {
                TextField("Unknown", text: $form.wipLength).multilineTextAlignment(.trailing)
            }
            if form.includePosition {
                SubjectRowSeparator()
                SubjectFormRow(label: "Position", arrangement: .control) {
                    TextField("Position", text: $form.position).multilineTextAlignment(.trailing)
                }
            }
        }
        .subjectPanel()
    }

    private var recoveryTarget: String { "work:\(form.workID):chapter:\(form.chapterID.map(String.init) ?? "new")" }

    private var textPanel: some View {
        VStack(spacing: 0) {
            WritingTextEditorRow(title: "Chapter text", text: $form.content, target: recoveryTarget, field: "content")
            SubjectRowSeparator()
            WritingTextEditorRow(title: "Summary", text: $form.summary, target: recoveryTarget, field: "summary")
            SubjectRowSeparator()
            WritingTextEditorRow(title: "Beginning notes", text: $form.notes, target: recoveryTarget, field: "notes")
            SubjectRowSeparator()
            WritingTextEditorRow(title: "End notes", text: $form.endnotes, target: recoveryTarget, field: "endnotes")
        }
        .subjectPanel()
    }

    private var publicationDate: Binding<Date> {
        let calendar = Calendar(identifier: .gregorian)
        return Binding(
            get: {
                calendar.date(from: DateComponents(
                    year: Int(form.publishedYear), month: Int(form.publishedMonth), day: Int(form.publishedDay)
                )) ?? Date()
            },
            set: { date in
                let parts = calendar.dateComponents([.year, .month, .day], from: date)
                form.publishedYear = String(parts.year ?? 2000)
                form.publishedMonth = String(parts.month ?? 1)
                form.publishedDay = String(parts.day ?? 1)
            }
        )
    }

    private var publicationPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Set a different publication date", arrangement: .control) {
                Toggle("Custom publication date", isOn: Binding(
                    get: { !form.publishedYear.isEmpty },
                    set: { enabled in
                        if enabled { publicationDate.wrappedValue = Date() } else { form.publishedYear = ""; form.publishedMonth = ""; form.publishedDay = "" }
                    }
                )).labelsHidden()
            }
            if !form.publishedYear.isEmpty {
                DatePicker("Publication date", selection: publicationDate, displayedComponents: .date)
                    .padding()
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "This is the last chapter", arrangement: .control) {
                Toggle("", isOn: $isLastChapter)
                .labelsHidden()
            }
        }
        .subjectPanel()
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
                save(submit: form.chapterID != nil && !form.isDraft ? .update : .postWithoutPreview)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.up.circle.fill")
                        .frame(width: 20)
                    Text(form.chapterID != nil && !form.isDraft ? "Save chapter changes" : "Post chapter now")
                        .font(.system(size: 15))
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
                        .font(.system(size: 15))
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
        guard editingGeneration == auth.sessionGeneration else {
            errorMessage = "Your AO3 session changed. Reopen this form before saving."
            return
        }
        let isPost = submit == .post || submit == .postWithoutPreview
        if isPost { isPosting = true } else { isSaving = true }

        Task {
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
                dismiss()
            } catch {
                errorMessage = (chapterSaved ? "The chapter was saved, but the work total was not updated. " : "")
                    + error.localizedDescription
                if isPost { isPosting = false } else { isSaving = false }
            }
        }
    }
}
