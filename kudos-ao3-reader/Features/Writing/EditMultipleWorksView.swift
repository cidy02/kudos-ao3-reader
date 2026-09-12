import SwiftUI
import SwiftData

struct EditMultipleWorksView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme
    @Environment(AO3AuthService.self) private var auth

    @State private var form: AO3BulkEditForm
    @State private var changes: AO3BulkEditChanges
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(form: AO3BulkEditForm) {
        self._form = State(initialValue: form)
        var initialChanges = AO3BulkEditChanges()
        initialChanges.workIDs = form.workIDs
        self._changes = State(initialValue: initialChanges)
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
                    title: "Edit \(form.workIDs.count) works",
                    subtitle: form.workTitles.joined(separator: ", "),
                    palette: accountPalette,
                    gutter: gutter
                )
                .pageBodyRow(top: 20, gutter: selfGuttered)

                Text("AO3’s Edit Multiple Works adds and removes tags rather than replacing them, "
                    + "and every field left alone stays untouched on all three works. That is why "
                    + "this screen has separate Add and Remove groups instead of one tag editor.")

                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .pageBodyRow(top: 14, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Tags to add")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                tagsToAddPanel.pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Tags to remove")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                tagsToRemovePanel.pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Change on all")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                changeOnAllPanel.pageBodyRow(top: 8, gutter: gutter)
                Text("Rating and language are single values, so setting one overwrites what each"
                    + "work had. Warnings and categories are lists and follow the add-and-remove rule.")

                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Collections and gifts")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                collectionsPanel.pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Comments and visibility")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                commentsPanel.pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Creators")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                creatorsPanel.pageBodyRow(top: 8, gutter: gutter)
                Text("Co-creator additions send an invitation on AO3; the"
                    + "work is not changed until the other account accepts.")

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
        .navigationTitle("Edit \(form.workIDs.count) works")
        #endif
        .subjectScreenWash(palette: accountPalette)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
                .disabled(isSaving)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) { dismiss() }
            }
        }
    }

    private var tagsToAddPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Fandoms", value: countLabel(changes.tagsToAdd.fandoms.count), showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "Relationships",
    value: countLabel(changes.tagsToAdd.relationships.count),
    showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "Characters",
    value: countLabel(changes.tagsToAdd.characters.count),
    showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "Additional tags",
    value: countLabel(changes.tagsToAdd.additionalTags.count),
    showsDisclosure: true)
        }
        .subjectPanel()
    }

    private var tagsToRemovePanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Fandoms",
    value: countLabel(changes.tagsToRemove.fandoms.count),
    showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "Relationships",
    value: countLabel(changes.tagsToRemove.relationships.count),
    showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "Characters",
    value: countLabel(changes.tagsToRemove.characters.count),
    showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "Additional tags",
    value: countLabel(changes.tagsToRemove.additionalTags.count),
    showsDisclosure: true)
        }
        .subjectPanel()
    }

    private var changeOnAllPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Rating", value: changes.rating ?? "Leave as is", showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "Archive warnings",
    value: listLabel(added: changes.tagsToAdd.warnings.count, removed: changes.tagsToRemove.warnings.count),
    showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "Categories",
    value: listLabel(added: changes.tagsToAdd.categories.count, removed: changes.tagsToRemove.categories.count),
    showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "Language", value: changes.languageID ?? "Leave as is", showsDisclosure: true)
        }
        .subjectPanel()
    }

    private var collectionsPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Add to collections",
    value: countLabel(changes.collectionsToAdd.count),
    showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "Remove from collections",
    value: countLabel(changes.collectionsToRemove.count),
    showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "Gift recipients", value: "None", showsDisclosure: true)
        }
        .subjectPanel()
    }

    private var commentsPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Only show to registered users", arrangement: .control) {
                Toggle("", isOn: Binding(
                    get: { changes.restricted == "1" },
                    set: { changes.restricted = $0 ? "1" : "0" }
                ))
                .labelsHidden()
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "Enable comment moderation", arrangement: .control) {
                Toggle("", isOn: Binding(
                    get: { changes.moderatedCommenting == "1" },
                    set: { changes.moderatedCommenting = $0 ? "1" : "0" }
                ))
                .labelsHidden()
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "Who can comment",
    value: changes.commentPermissions ?? "Leave as is",
    showsDisclosure: true)
        }
        .subjectPanel()
    }

    private var creatorsPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Add co-creators",
    value: changes.pseudsToAdd.isEmpty ? "None" : "1",
    showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "Remove co-creators", value: "None", showsDisclosure: true)
        }
        .subjectPanel()
    }

    private func countLabel(_ count: Int) -> String {
        count == 0 ? "None" : "\(count)"
    }

    private func listLabel(added: Int, removed: Int) -> String {
        if added == 0 && removed == 0 { return "Leave as is" }
        return "+\(added), -\(removed)"
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await auth.bulkEditWorks(changes)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}
