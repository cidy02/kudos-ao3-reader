import SwiftUI
import SwiftData

struct WorkEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme
    @Environment(AO3AuthService.self) private var auth

    @State private var form: AO3WorkForm
    @State private var isSaving = false
    @State private var isPosting = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var deleteImplications: AO3DeleteImplications?
    @State private var isCheckingDelete = false

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
                Text("Editing only the tags is its own AO3 page, kept at...")
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
                publicationPanel.pageBodyRow(top: 8, gutter: gutter)
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
        #if os(macOS)
        .navigationTitle(form.kind == .new ? "New work" : "Edit work")
        #endif
        .subjectScreenWash(palette: accountPalette)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save(submit: form.isPosted ? .update : .saveDraft)
                }
                .disabled(isSaving || isPosting)
            }
            if !form.isPosted && form.kind != .new {
                ToolbarItem(placement: .primaryAction) {
                    Button("Post") {
                        save(submit: .postWithoutPreview)
                    }
                    .disabled(isSaving || isPosting)
                }
            }
        }
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
            SubjectFormRow(label: "Title", value: form.title.isEmpty ? "None" : form.title, showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "Rating", value: form.rating.isEmpty ? "None" : form.rating, showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "Archive warnings",
    value: form.warnings.isEmpty ? "None" : "\(form.warnings.count)",
    showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "Fandoms",
    value: form.fandoms.isEmpty ? "None" : "\(form.fandoms.count)",
    showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "Language",
    value: form.languageID.isEmpty ? "None" : form.languageID,
    showsDisclosure: true)
        }
        .subjectPanel()
    }

    private var tagsPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Categories",
    value: form.categories.isEmpty ? "None" : "\(form.categories.count)",
    showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "Relationships",
    value: form.relationships.isEmpty ? "None" : "\(form.relationships.count)",
    showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "Characters",
    value: form.characters.isEmpty ? "None" : "\(form.characters.count)",
    showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "Additional tags",
    value: form.additionalTags.isEmpty ? "None" : "\(form.additionalTags.count)",
    showsDisclosure: true)
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

    private var textPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Summary", value: form.summary.isEmpty ? "Empty" : "Set", showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "Beginning notes",
    value: form.notes.isEmpty ? "Empty" : "Set",
    showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "End notes", value: form.endnotes.isEmpty ? "Empty" : "Set", showsDisclosure: true)
            if form.kind == .new || form.isDraft {
                SubjectRowSeparator()
                SubjectFormRow(label: "Work text",
    value: (form.chapter?.content.isEmpty ?? true) ? "Empty" : "Set",
    showsDisclosure: true)
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
        let isPost = submit == .post || submit == .postWithoutPreview
        if isPost { isPosting = true } else { isSaving = true }

        Task {
            do {
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
