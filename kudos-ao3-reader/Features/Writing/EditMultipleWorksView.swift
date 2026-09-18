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

    private var headerTitle: String {
        form.workIDs.count == 1 ? "Edit 1 work" : "Edit \(form.workIDs.count) works"
    }

    private var gutter: CGFloat { SubjectMetrics.accountGutter }
    private var selfGuttered: CGFloat { 0 }

    var body: some View {
        List {
            Section {
                SubjectHeaderBlock(
                    kicker: "AO3 Account",
                    title: headerTitle,
                    subtitle: form.workTitles.joined(separator: ", "),
                    palette: accountPalette,
                    gutter: gutter
                )
                .pageBodyRow(top: 20, gutter: selfGuttered)

                Text("AO3’s Edit Multiple Works adds and removes tags rather than replacing them, "
                    + "and every field left alone stays untouched on every selected work. That is why "
                    + "this screen has separate Add and Remove groups instead of one tag editor.")

                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .pageBodyRow(top: 14, gutter: gutter)
            }

            // One `List` row per field, as segments of one card. Each card was
            // one `VStack` row, and a `List` row fires every `NavigationLink`
            // inside it — tapping Characters under Tags to add pushed all four
            // pickers, and Remove from collections pushed Add to collections
            // too. Cards without links are converted so the screen keeps one
            // card style.
            groupHeader("Tags to add")
            Section { tagRows($changes.tagsToAdd) }

            groupHeader("Tags to remove")
            Section { tagRows($changes.tagsToRemove) }

            groupHeader("Change on all")
            Section {
                changeOnAllRows
                Text("Rating and language are single values, so setting one overwrites what each "
                    + "work had. Warnings and categories are lists and follow the add-and-remove rule.")

                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .pageBodyRow(top: 8, gutter: gutter)
            }

            groupHeader("Collections and gifts")
            Section { collectionsRows }

            groupHeader("Comments and visibility")
            Section { commentsRows }

            groupHeader("Creators")
            Section {
                creatorsRows
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
        .navigationTitle(headerTitle)
        #endif
        .subjectScreenWash(palette: accountPalette)
        // The error was set and never shown, so a failed save only re-enabled
        // Save and looked like nothing had happened.
        .alert("AO3 could not save the change", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
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

    /// Rating and language are the two fields 1bn's footnote calls out: they are
    /// single values, so setting one **overwrites** whatever each work had. `nil`
    /// is the untouched state, and the picker needs a real option to represent it
    /// — hence the empty-valued "Leave as is" at the head of the list rather than
    /// a separate toggle.
    ///
    /// AO3's own blank is dropped: its selects are `include_blank: true` and
    /// Who can comment opens on a keep-current `""` radio, so prepending ours
    /// without filtering gave each menu two `""` options — a duplicate id, and
    /// an untitled item VoiceOver could not name.
    private func leaveAsIsOptions(_ options: [AO3FormOption]) -> [AO3FormOption] {
        [AO3FormOption(value: "", title: "Leave as is")] + options.filter { !$0.value.isEmpty }
    }

    private func leaveAsIsBinding(
        _ keyPath: WritableKeyPath<AO3BulkEditChanges, String?>
    ) -> Binding<String> {
        Binding(
            get: { changes[keyPath: keyPath] ?? "" },
            set: { changes[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private func groupHeader(_ title: String) -> some View {
        Section {
            SectionRuleHeader(title: title)
                .padding(.bottom, 8)
                .pageBodyRow(top: 18, gutter: selfGuttered)
        }
    }

    /// `WritingTagsRow` rather than a bare `SubjectFormRow`: it draws the same row
    /// — label, count, chevron — and attaches the editor the chevron implies.
    /// These eight rows had a chevron and no destination until this screen became
    /// reachable, at which point a dead row stops being invisible and starts being
    /// a broken control.
    @ViewBuilder
    private func tagRows(_ tags: Binding<AO3WorkTagSet>) -> some View {
        WritingTagsRow(title: "Fandoms", values: tags.fandoms, kind: .fandom)
            .panelSegment(0, of: 4, gutter: gutter)
        WritingTagsRow(
            title: "Relationships",
            values: tags.relationships,
            kind: .relationship
        )
        .panelSegment(1, of: 4, gutter: gutter)
        WritingTagsRow(
            title: "Characters",
            values: tags.characters,
            kind: .character
        )
        .panelSegment(2, of: 4, gutter: gutter)
        WritingTagsRow(
            title: "Additional tags",
            values: tags.additionalTags,
            kind: .freeform
        )
        .panelSegment(3, of: 4, gutter: gutter)
    }

    @ViewBuilder
    private var changeOnAllRows: some View {
        WritingChoiceRow(
            title: "Rating",
            value: leaveAsIsBinding(\.rating),
            options: leaveAsIsOptions(form.ratingOptions)
        )
        .panelSegment(0, of: 4, gutter: gutter)
        bulkStateRow(
            title: "Archive warnings",
            options: form.warningOptions,
            added: $changes.tagsToAdd.warnings,
            removed: $changes.tagsToRemove.warnings
        )
        .panelSegment(1, of: 4, gutter: gutter)
        bulkStateRow(
            title: "Categories",
            options: form.categoryOptions,
            added: $changes.tagsToAdd.categories,
            removed: $changes.tagsToRemove.categories
        )
        .panelSegment(2, of: 4, gutter: gutter)
        WritingChoiceRow(
            title: "Language",
            value: leaveAsIsBinding(\.languageID),
            options: leaveAsIsOptions(form.languageOptions)
        )
        .panelSegment(3, of: 4, gutter: gutter)
    }

    @ViewBuilder
    private var collectionsRows: some View {
        BulkNameListRow(
            title: "Add to collections",
            placeholder: "Collection name",
            names: $changes.collectionsToAdd
        )
        .panelSegment(0, of: 3, gutter: gutter)
        // Only offered when AO3 sent collections to remove from, as
        // `bulkStateRow` does: with none, the chevron opened an empty list.
        if form.currentCollections.isEmpty {
            SubjectFormRow(
                label: "Remove from collections",
                value: "None",
                showsDisclosure: false,
                isDisabled: true
            )
            .panelSegment(1, of: 3, gutter: gutter)
        } else {
            WritingTagsRow(
                title: "Remove from collections",
                values: $changes.collectionsToRemove,
                options: form.currentCollections
            )
            .panelSegment(1, of: 3, gutter: gutter)
        }
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
        .panelSegment(2, of: 3, gutter: gutter)
    }

    /// 1bn draws the first two as switches, but otwarchive's `edit_multiple`
    /// gives each three answers — keep current, on, off (`radio_button_list`
    /// over `""`, `"1"`, `"0"`). A switch has two, so once touched it could
    /// only post `"0"` or `"1"`: turning one on and back off to undo it made
    /// every selected work public, or unmoderated. They take the "Leave as is"
    /// choice the same card already draws for Who can comment.
    @ViewBuilder
    private var commentsRows: some View {
        WritingChoiceRow(
            title: "Only show to registered users",
            value: leaveAsIsBinding(\.restricted),
            options: leaveAsIsOptions(Self.onOffOptions)
        )
        .panelSegment(0, of: 3, gutter: gutter)
        WritingChoiceRow(
            title: "Enable comment moderation",
            value: leaveAsIsBinding(\.moderatedCommenting),
            options: leaveAsIsOptions(Self.onOffOptions)
        )
        .panelSegment(1, of: 3, gutter: gutter)
        WritingChoiceRow(
            title: "Who can comment",
            value: leaveAsIsBinding(\.commentPermissions),
            options: leaveAsIsOptions(form.commentPermissionOptions)
        )
        .panelSegment(2, of: 3, gutter: gutter)
    }

    private static let onOffOptions = [
        AO3FormOption(value: "1", title: "On"),
        AO3FormOption(value: "0", title: "Off"),
    ]

    @ViewBuilder
    private var creatorsRows: some View {
        SubjectFormRow(label: "Add co-creators", arrangement: .control) {
            TextField("Pseud", text: $changes.pseudsToAdd)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
        }
        .panelSegment(0, of: 2, gutter: gutter)
        // AO3's field is `remove_me`: one checkbox taking the signed-in user
        // off the selected works. It never was a list of other people to
        // pick from, which is why this row read a hardcoded "None".
        // Titled even though hidden: `labelsHidden` keeps the title for
        // VoiceOver, and an empty one announced a bare "switch".
        SubjectFormRow(label: "Remove me as a co-creator", arrangement: .control) {
            Toggle("Remove me as a co-creator", isOn: $changes.removesSelfAsCreator)
                .labelsHidden()
        }
        .panelSegment(1, of: 2, gutter: gutter)
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
