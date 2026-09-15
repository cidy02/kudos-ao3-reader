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
        theme.scopePalette
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
                Text("Rating and language are single values, so setting one overwrites what each "
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
                Text("Co-creator additions send an invitation on AO3; the "
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

    /// `WritingTagsRow` rather than a bare `SubjectFormRow`: it draws the same row
    /// — label, count, chevron — and attaches the editor the chevron implies.
    /// These eight rows had a chevron and no destination until this screen became
    /// reachable, at which point a dead row stops being invisible and starts being
    /// a broken control.
    /// Rating and language are the two fields 1bn's footnote calls out: they are
    /// single values, so setting one **overwrites** whatever each work had. `nil`
    /// is the untouched state, and the picker needs a real option to represent it
    /// — hence the empty-valued "Leave as is" at the head of the list rather than
    /// a separate toggle.
    private func leaveAsIsOptions(_ options: [AO3FormOption]) -> [AO3FormOption] {
        [AO3FormOption(value: "", title: "Leave as is")] + options
    }

    private func leaveAsIsBinding(
        _ keyPath: WritableKeyPath<AO3BulkEditChanges, String?>
    ) -> Binding<String> {
        Binding(
            get: { changes[keyPath: keyPath] ?? "" },
            set: { changes[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private var tagsToAddPanel: some View {
        VStack(spacing: 0) {
            WritingTagsRow(title: "Fandoms", values: $changes.tagsToAdd.fandoms, kind: .fandom)
            SubjectRowSeparator()
            WritingTagsRow(
                title: "Relationships",
                values: $changes.tagsToAdd.relationships,
                kind: .relationship
            )
            SubjectRowSeparator()
            WritingTagsRow(
                title: "Characters",
                values: $changes.tagsToAdd.characters,
                kind: .character
            )
            SubjectRowSeparator()
            WritingTagsRow(
                title: "Additional tags",
                values: $changes.tagsToAdd.additionalTags,
                kind: .freeform
            )
        }
        .subjectPanel()
    }

    private var tagsToRemovePanel: some View {
        VStack(spacing: 0) {
            WritingTagsRow(title: "Fandoms", values: $changes.tagsToRemove.fandoms, kind: .fandom)
            SubjectRowSeparator()
            WritingTagsRow(
                title: "Relationships",
                values: $changes.tagsToRemove.relationships,
                kind: .relationship
            )
            SubjectRowSeparator()
            WritingTagsRow(
                title: "Characters",
                values: $changes.tagsToRemove.characters,
                kind: .character
            )
            SubjectRowSeparator()
            WritingTagsRow(
                title: "Additional tags",
                values: $changes.tagsToRemove.additionalTags,
                kind: .freeform
            )
        }
        .subjectPanel()
    }

    private var changeOnAllPanel: some View {
        VStack(spacing: 0) {
            WritingChoiceRow(
                title: "Rating",
                value: leaveAsIsBinding(\.rating),
                options: leaveAsIsOptions(form.ratingOptions)
            )
            SubjectRowSeparator()
            bulkStateRow(
                title: "Archive warnings",
                options: form.warningOptions,
                added: $changes.tagsToAdd.warnings,
                removed: $changes.tagsToRemove.warnings
            )
            SubjectRowSeparator()
            bulkStateRow(
                title: "Categories",
                options: form.categoryOptions,
                added: $changes.tagsToAdd.categories,
                removed: $changes.tagsToRemove.categories
            )
            SubjectRowSeparator()
            WritingChoiceRow(
                title: "Language",
                value: leaveAsIsBinding(\.languageID),
                options: leaveAsIsOptions(form.languageOptions)
            )
        }
        .subjectPanel()
    }

    private var collectionsPanel: some View {
        VStack(spacing: 0) {
            BulkNameListRow(
                title: "Add to collections",
                placeholder: "Collection name",
                names: $changes.collectionsToAdd
            )
            SubjectRowSeparator()
            WritingTagsRow(
                title: "Remove from collections",
                values: $changes.collectionsToRemove,
                options: form.currentCollections
            )
            SubjectRowSeparator()
            // 1bn draws this row, so it stays on the page — but AO3's own
            // edit_multiple form carries no gift-recipient field, so there is
            // nothing for a chevron to open. Disabled and explained beats a
            // control that opens nothing and can only ever read "None".
            SubjectFormRow(
                label: "Gift recipients",
                value: "Per work",
                showsDisclosure: false,
                isDisabled: true
            )
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
            WritingChoiceRow(
                title: "Who can comment",
                value: leaveAsIsBinding(\.commentPermissions),
                options: leaveAsIsOptions(form.commentPermissionOptions)
            )
        }
        .subjectPanel()
    }

    private var creatorsPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Add co-creators", arrangement: .control) {
                TextField("Pseud", text: $changes.pseudsToAdd)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }
            SubjectRowSeparator()
            // AO3's field is `remove_me`: one checkbox taking the signed-in user
            // off the selected works. It never was a list of other people to
            // pick from, which is why this row read a hardcoded "None".
            SubjectFormRow(label: "Remove me as a co-creator", arrangement: .control) {
                Toggle("", isOn: $changes.removesSelfAsCreator)
                    .labelsHidden()
            }
        }
        .subjectPanel()
    }

    /// Only drawn when AO3 actually sent options for the field — a row that
    /// opens an empty list is the dead chevron in a new coat.
    @ViewBuilder
    private func bulkStateRow(
        title: String,
        options: [AO3FormOption],
        added: Binding<[String]>,
        removed: Binding<[String]>
    ) -> some View {
        let row = SubjectFormRow(
            label: title,
            value: listLabel(added: added.wrappedValue.count, removed: removed.wrappedValue.count),
            showsDisclosure: !options.isEmpty,
            isDisabled: options.isEmpty
        )
        if options.isEmpty {
            row
        } else {
            row.subjectRowNavigation(accessibilityLabel: title) {
                BulkTagStatePicker(title: title, options: options, added: added, removed: removed)
            }
        }
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
