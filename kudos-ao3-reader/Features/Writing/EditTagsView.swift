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
    @State private var addingKind: AO3TagKind?
    /// Told after AO3 accepts the save, before this screen dismisses — so a
    /// work editor that pushed it can refresh the tags it is holding.
    let workTitle: String
    let onSaved: () -> Void

    init(form: AO3EditTagsForm, workTitle: String = "", onSaved: @escaping () -> Void = {}) {
        self._form = State(initialValue: form)
        self._originalTags = State(initialValue: form.tags)
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
                    title: "Edit tags",
                    subtitle: subtitle,
                    palette: accountPalette,
                    gutter: gutter
                )
                .pageBodyRow(top: 20, gutter: selfGuttered)
            }

            // One `List` row per field, as segments of one card. The Tags card
            // was one `VStack` row, and a `List` row fires every
            // `NavigationLink` inside it — tapping Relationships would have
            // pushed all four pickers. The other cards carry no links; they are
            // converted so the screen keeps one card style.
            Section {
                SectionRuleHeader(title: "Rating")
                    .padding(.bottom, 8)
                    .pageBodyRow(top: 18, gutter: selfGuttered)
            }
            Section {
                ratingSlots
            }

            Section {
                SectionRuleHeader(title: "Archive warnings")
                    .padding(.bottom, 8)
                    .pageBodyRow(top: 18, gutter: selfGuttered)
            }
            Section {
                checkSlots(form.warningOptions, values: $form.tags.warnings)
                // "At least one", not the "exactly one of these six" this used
                // to say: otwarchive's `Work` validates `archive_warning_string`
                // for presence only ("Please select at least one warning"), and
                // the rows above are a multi-select.
                Text("AO3 needs at least one of these, and the first is how a "
                    + "creator declines to warn.")

                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Categories")
                    .padding(.bottom, 8)
                    .pageBodyRow(top: 18, gutter: selfGuttered)
            }
            Section {
                checkRows(form.categoryOptions, values: $form.tags.categories)
            }

            Section {
                SectionRuleHeader(title: "Tags")
                    .padding(.bottom, 8)
                    .pageBodyRow(top: 18, gutter: selfGuttered)
            }
            Section {
                tagsRows
                Text("Tags are AO3’s autocomplete: typing offers canonical tags first, and a tag "
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
        // Rows at their own padding, not the List minimum (L3-FORM-1).
        .environment(\.defaultMinListRowHeight, 0)
        .environment(\.writingEditedWorkID, form.workID)
        #if os(macOS)
        .navigationTitle("Edit tags")
        #endif
        .subjectScreenWash(palette: accountPalette)
        .navigationDestination(item: $addingKind) { kind in
            tagsEditor(kind)
        }
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
        }
    }

    /// 1bp: "<title> · changes here do not touch the text". A missing title
    /// keeps the second half alone rather than a leading dot.
    private var subtitle: String {
        let note = "changes here do not touch the text"
        let title = workTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return note }
        return "\(title) · \(note)"
    }

    /// One rating, so a tap selects and a second tap on the same row stays.
    /// The check occupies 15pt either way, which is the slot the row draws.
    private var ratingSlots: some View {
        let options = form.ratingOptions
        return ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
            checkSlotRow(option, isOn: form.tags.rating == option.value) {
                form.tags.rating = option.value
            }
            .panelSegment(index, of: max(options.count, 1), gutter: gutter)
        }
    }

    /// Warnings stay a multi-select. otwarchive checks that at least one is
    /// present, not that exactly one is, so a second check does not clear the
    /// first. Categories keep the switch — this slot is rating and warnings.
    private func checkSlots(
        _ options: [AO3FormOption], values: Binding<[String]>
    ) -> some View {
        ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
            checkSlotRow(option, isOn: values.wrappedValue.contains(option.value)) {
                if values.wrappedValue.contains(option.value) {
                    values.wrappedValue.removeAll { $0 == option.value }
                } else {
                    values.wrappedValue.append(option.value)
                }
            }
            .panelSegment(index, of: max(options.count, 1), gutter: gutter)
        }
    }

    private func checkSlotRow(
        _ option: AO3FormOption, isOn: Bool, action: @escaping () -> Void
    ) -> some View {
        SubjectFormRow(label: option.title, action: action) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accountPalette.accent)
                .opacity(isOn ? 1 : 0)
                .frame(width: 15, height: 15)
                .accessibilityHidden(true)
        }
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    /// A toggle row per option, each its own `List` row. Titled even though
    /// the titles are hidden: `labelsHidden` keeps them for VoiceOver, and the
    /// empty ones announced a bare "switch".
    private func checkRows(_ options: [AO3FormOption], values: Binding<[String]>) -> some View {
        ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
            SubjectFormRow(label: option.title, arrangement: .control) {
                Toggle(option.title, isOn: Binding(
                    get: { values.wrappedValue.contains(option.value) },
                    set: { isOn in
                        if isOn {
                            if !values.wrappedValue.contains(option.value) {
                                values.wrappedValue.append(option.value)
                            }
                        } else {
                            values.wrappedValue.removeAll(where: { $0 == option.value })
                        }
                    }
                ))
                .labelsHidden()
            }
            .panelSegment(index, of: options.count, gutter: gutter)
        }
    }

    @ViewBuilder
    private var tagsRows: some View {
        inlineTags("Fandoms", values: $form.tags.fandoms, kind: .fandom, isRequired: true)
            .panelSegment(0, of: 4, gutter: gutter)
        // 1bp's order, the same as the work form (1bo) and bulk edit (1bn).
        inlineTags("Relationships", values: $form.tags.relationships, kind: .relationship)
            .panelSegment(1, of: 4, gutter: gutter)
        inlineTags("Characters", values: $form.tags.characters, kind: .character)
            .panelSegment(2, of: 4, gutter: gutter)
        inlineTags("Additional tags", values: $form.tags.additionalTags, kind: .freeform)
            .panelSegment(3, of: 4, gutter: gutter)
    }

    private func inlineTags(
        _ title: String,
        values: Binding<[String]>,
        kind: AO3TagKind,
        isRequired: Bool = false
    ) -> some View {
        WritingTagsRow(
            title: title,
            values: values,
            kind: kind,
            isRequired: isRequired,
            showsInlineChips: true,
            onAdd: { addingKind = kind }
        )
    }

    @ViewBuilder
    private func tagsEditor(_ kind: AO3TagKind) -> some View {
        switch kind {
        case .fandom:
            WritingTagsEditor(title: "Fandoms", values: $form.tags.fandoms, options: [], kind: kind)
        case .character:
            WritingTagsEditor(
                title: "Characters", values: $form.tags.characters, options: [], kind: kind
            )
        case .relationship:
            WritingTagsEditor(
                title: "Relationships", values: $form.tags.relationships, options: [], kind: kind
            )
        case .freeform:
            WritingTagsEditor(
                title: "Additional tags", values: $form.tags.additionalTags, options: [], kind: kind
            )
        case .tag:
            EmptyView()
        }
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await auth.editTags(workID: form.workID, current: originalTags, desired: form.tags)
                onSaved()
                dismiss()
            } catch {
                errorMessage = UserFacingError.message(for: error)
                isSaving = false
            }
        }
    }
}
