import SwiftUI
import SwiftData

struct EditTagsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme
    @Environment(AO3AuthService.self) private var auth

    @State private var form: AO3EditTagsForm
    @State private var originalTags: AO3WorkTagSet
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(form: AO3EditTagsForm) {
        self._form = State(initialValue: form)
        self._originalTags = State(initialValue: form.tags)
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
                    title: "Edit tags",
                    subtitle: "changes here do not touch the text",
                    palette: accountPalette,
                    gutter: gutter
                )
                .pageBodyRow(top: 20, gutter: selfGuttered)
            }

            Section {
                SectionRuleHeader(title: "Rating")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                ratingPanel.pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Archive warnings")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                warningsPanel.pageBodyRow(top: 8, gutter: gutter)
                Text("AO3 requires exactly one of these six, and the first is"
                    + "how a creator declines to warn. None of them can be left blank.")

                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Categories")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                categoriesPanel.pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Tags")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                tagsPanel.pageBodyRow(top: 8, gutter: gutter)
                Text("Tags are AO3’s autocomplete: typing offers canonical tags first, and a tag"
                    + "that is not canonical still posts. Removing a tag here never deletes it from AO3.")

                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .pageBodyRow(top: 8, gutter: gutter)
            }
        }
        .cardList()
        #if os(macOS)
        .navigationTitle("Edit tags")
        #endif
        .subjectScreenWash(palette: accountPalette)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
                .disabled(isSaving)
            }
        }
    }

    private var ratingPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Rating",
    value: form.tags.rating.isEmpty ? "None" : form.tags.rating,
    showsDisclosure: true)
        }
        .subjectPanel()
    }

    private var warningsPanel: some View {
        VStack(spacing: 0) {
            ForEach(form.warningOptions) { option in
                SubjectFormRow(label: option.title, arrangement: .control) {
                    Toggle("", isOn: Binding(
                        get: { form.tags.warnings.contains(option.value) },
                        set: { isOn in
                            if isOn {
                                if !form.tags.warnings.contains(option.value) {
                                    form.tags.warnings.append(option.value)
                                }
                            } else {
                                form.tags.warnings.removeAll(where: { $0 == option.value })
                            }
                        }
                    ))
                    .labelsHidden()
                }
                if option.id != form.warningOptions.last?.id {
                    SubjectRowSeparator()
                }
            }
        }
        .subjectPanel()
    }

    private var categoriesPanel: some View {
        VStack(spacing: 0) {
            ForEach(form.categoryOptions) { option in
                SubjectFormRow(label: option.title, arrangement: .control) {
                    Toggle("", isOn: Binding(
                        get: { form.tags.categories.contains(option.value) },
                        set: { isOn in
                            if isOn {
                                if !form.tags.categories.contains(option.value) {
                                    form.tags.categories.append(option.value)
                                }
                            } else {
                                form.tags.categories.removeAll(where: { $0 == option.value })
                            }
                        }
                    ))
                    .labelsHidden()
                }
                if option.id != form.categoryOptions.last?.id {
                    SubjectRowSeparator()
                }
            }
        }
        .subjectPanel()
    }

    private var tagsPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Fandoms",
    value: form.tags.fandoms.isEmpty ? "Add" : "\(form.tags.fandoms.count)",
    showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "Relationships",
    value: form.tags.relationships.isEmpty ? "Add" : "\(form.tags.relationships.count)",
    showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "Characters",
    value: form.tags.characters.isEmpty ? "Add" : "\(form.tags.characters.count)",
    showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "Additional tags",
    value: form.tags.additionalTags.isEmpty ? "Add" : "\(form.tags.additionalTags.count)",
    showsDisclosure: true)
        }
        .subjectPanel()
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await auth.editTags(workID: form.workID, current: originalTags, desired: form.tags)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}
