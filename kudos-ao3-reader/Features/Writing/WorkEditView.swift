import SwiftUI
import SwiftData

struct WorkEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme
    @Environment(AO3AuthService.self) private var auth

    @State private var form: AO3WorkForm
    @State private var editingGeneration: Int?
    @State private var isSaving = false
    @State private var isPosting = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var deleteImplications: AO3DeleteImplications?
    @State private var isCheckingDelete = false
    @State private var needsPublicationRefresh = false
    @State private var publicationRetry = 0

    init(form: AO3WorkForm) {
        self._form = State(initialValue: form)
    }

    private var accountPalette: SubjectPalette {
        theme.appTheme.subjectPalette(hue: theme.scopeHue)
    }

    private var gutter: CGFloat { SubjectMetrics.accountGutter }
    private var selfGuttered: CGFloat { 0 }

    var body: some View {
        List {
            Section {
                SubjectHeaderBlock(
                    kicker: "AO3 Account",
                    title: form.kind == .new ? "New work" : "Edit work",
                    subtitle: form.title.isEmpty ? "Untitled" : form.title,
                    palette: accountPalette,
                    gutter: gutter
                )
                .pageBodyRow(top: 20, gutter: selfGuttered)
            }

            Section {
                SectionRuleHeader(title: "Required")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                requiredPanel.pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Tags")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                tagsPanel.pageBodyRow(top: 8, gutter: gutter)
                Text("Tags can also be edited separately from the work text.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Association")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                associationPanel.pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Text")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                textPanel.pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Publication")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                publicationPanel.disabled(needsPublicationRefresh).pageBodyRow(top: 8, gutter: gutter)
                if needsPublicationRefresh {
                    Button("Reload chapter totals") { publicationRetry += 1 }
                        .pageBodyRow(top: 8, gutter: gutter)
                }
                Text("Chapters posted of total is AO3’s own field — setting a total above what is"
                    + "posted is what marks a work in progress, and Complete writes the same value.")

                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .pageBodyRow(top: 8, gutter: gutter)
            }

            if form.workID != nil {
                Section {
                    SectionRuleHeader(title: "Delete")
                        .pageBodyRow(top: 18, gutter: selfGuttered)
                    deletePanel.pageBodyRow(top: 8, gutter: gutter)
                }
            }
        }
        .cardList()
        .disabled(isSaving || isPosting)
        .onAppear { if editingGeneration == nil { editingGeneration = auth.sessionGeneration } }
        #if os(macOS)
        .navigationTitle(form.kind == .new ? "New work" : "Edit work")
        #endif
        .subjectScreenWash(palette: accountPalette)
        .task(id: "\(needsPublicationRefresh):\(publicationRetry)") {
            guard needsPublicationRefresh, let workID = form.workID else { return }
            let generation = auth.sessionGeneration
            do {
                let fresh = try await auth.loadWorkForm(workID: workID)
                guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
                form.chapterTotal = fresh.chapterTotal
                form.chaptersPosted = fresh.chaptersPosted
                form.isChaptered = fresh.isChaptered
                needsPublicationRefresh = false
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = "Reload chapter totals before saving this work. " + error.localizedDescription
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save(submit: form.isPosted ? .update : .saveDraft)
                }
                .disabled(isSaving || isPosting || needsPublicationRefresh)
            }
            if !form.isPosted {
                ToolbarItem(placement: .primaryAction) {
                    Button("Post") {
                        save(submit: .postWithoutPreview)
                    }
                    .disabled(isSaving || isPosting)
                }
            }
        }
        .alert("AO3 could not save the change", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .confirmationDialog(
            "Delete Work?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete work on AO3", role: .destructive) {
                deleteWork()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let imp = deleteImplications {
                Text(imp.cautionText)
            }
        }
    }

    private var requiredPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Title", arrangement: .control) {
                TextField("Title", text: $form.title).multilineTextAlignment(.trailing)
            }
            SubjectRowSeparator()
            WritingChoiceRow(title: "Rating", value: $form.rating, options: form.ratingOptions)
            SubjectRowSeparator()
            WritingTagsRow(title: "Archive warnings", values: $form.warnings, options: form.warningOptions)
            SubjectRowSeparator()
            WritingTagsRow(title: "Fandoms", values: $form.fandoms, kind: .fandom)
            SubjectRowSeparator()
            WritingChoiceRow(title: "Language", value: $form.languageID, options: form.languageOptions)
        }
        .subjectPanel()
    }

    private var tagsPanel: some View {
        VStack(spacing: 0) {
            WritingTagsRow(title: "Categories", values: $form.categories, options: form.categoryOptions)
            SubjectRowSeparator()
            WritingTagsRow(title: "Relationships", values: $form.relationships, kind: .relationship)
            SubjectRowSeparator()
            WritingTagsRow(title: "Characters", values: $form.characters, kind: .character)
            SubjectRowSeparator()
            WritingTagsRow(title: "Additional tags", values: $form.additionalTags, kind: .freeform)
        }
        .subjectPanel()
    }

    private var associationPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Series",
    value: form.series.isEmpty ? "None" : "\(form.series.count)",
    showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "Add to collections",
    value: form.collections.isEmpty ? "None" : "\(form.collections.count)",
    showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "Gift recipients",
    value: form.gifts.isEmpty ? "None" : "\(form.gifts.count)",
    showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "Co-creators",
    value: form.creators.selectedPseudIDs.isEmpty ? "None" : "\(form.creators.selectedPseudIDs.count)",
    showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "Inspired by",
    value: form.parentWork.url.isEmpty ? "None" : "1",
    showsDisclosure: true)
        }
        .subjectPanel()
    }

    private var recoveryTarget: String { form.workID.map { "work:\($0)" } ?? "work:new" }

    private var textPanel: some View {
        VStack(spacing: 0) {
            WritingTextEditorRow(title: "Summary", text: $form.summary, target: recoveryTarget, field: "summary")
            SubjectRowSeparator()
            WritingTextEditorRow(title: "Beginning notes", text: $form.notes, target: recoveryTarget, field: "notes")
            SubjectRowSeparator()
            WritingTextEditorRow(title: "End notes", text: $form.endnotes, target: recoveryTarget, field: "endnotes")
            if form.kind == .new || form.isDraft {
                SubjectRowSeparator()
                WritingTextEditorRow(title: "Work text", text: Binding(
                    get: { form.chapter?.content ?? "" },
                    set: { value in
                        if form.chapter == nil { form.chapter = AO3WorkChapterDraft() }
                        form.chapter?.content = value
                    }
                ), target: recoveryTarget, field: "content")
            }
            if let workID = form.workID, form.isPosted {
                SubjectRowSeparator()
                NavigationLink {
                    WritingChapterDestination(workID: workID, workTitle: form.title) {
                        needsPublicationRefresh = true
                    }
                } label: {
                    SubjectFormRow(label: "Add chapter", value: "", showsDisclosure: true)
                }.buttonStyle(.plain)
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "Work skin",
    value: form.workSkinID.isEmpty ? "Default" : form.workSkinID,
    showsDisclosure: true)
        }
        .subjectPanel()
    }

    private var publicationPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Chapters posted",
    value: "\(form.chaptersPosted ?? 1) of \(form.chapterTotal.isEmpty ? "?" : form.chapterTotal)",
    showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "Work is complete", arrangement: .control) {
                Toggle("", isOn: Binding(
                    get: { form.chapterTotal == "\(form.chaptersPosted ?? 1)" },
                    set: { form.chapterTotal = $0 ? "\(form.chaptersPosted ?? 1)" : "" }
                ))
                .labelsHidden()
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "Set a different publication date", arrangement: .control) {
                Toggle("", isOn: $form.backdate)
                    .labelsHidden()
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "Only show to registered users", arrangement: .control) {
                Toggle("", isOn: $form.restricted)
                    .labelsHidden()
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "Enable comment moderation", arrangement: .control) {
                Toggle("", isOn: $form.moderatedCommenting)
                    .labelsHidden()
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "Who can comment",
    value: form.commentPermissions.isEmpty ? "Leave as is" : form.commentPermissions,
    showsDisclosure: true)
        }
        .subjectPanel()
    }

    private var deletePanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Delete work on AO3", value: "", isDestructive: true) {
                Task {
                    guard let workID = form.workID else { return }
                    isCheckingDelete = true
                    do {
                        deleteImplications = try await auth.loadDeleteImplications(workID: workID)
                        showDeleteConfirmation = true
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                    isCheckingDelete = false
                }
            }
        }
        .subjectPanel()
    }

    private func save(submit: AO3WorkSubmitAction) {
        guard !isSaving && !isPosting && !needsPublicationRefresh else { return }
        guard editingGeneration == auth.sessionGeneration else {
            errorMessage = "Your AO3 session changed. Reopen this form before saving."
            return
        }
        let isPost = submit == .post || submit == .postWithoutPreview
        if isPost { isPosting = true } else { isSaving = true }

        Task {
            do {
                guard editingGeneration == auth.sessionGeneration else { throw AO3WorkWriteError.notSignedIn }
                try await auth.saveWork(form, submit: submit)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                if isPost { isPosting = false } else { isSaving = false }
            }
        }
    }

    private func deleteWork() {
        guard let workID = form.workID else { return }
        Task {
            do {
                guard editingGeneration == auth.sessionGeneration else { throw AO3WorkWriteError.notSignedIn }
                if form.isDraft {
                    try await auth.deleteDraft(workID: workID)
                } else {
                    try await auth.deleteWork(workID: workID)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
