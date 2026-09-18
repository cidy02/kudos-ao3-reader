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
    /// Told after AO3 accepts the save, before this screen dismisses — so a
    /// work editor that pushed it can refresh the tags it is holding.
    let onSaved: () -> Void

    init(form: AO3EditTagsForm, onSaved: @escaping () -> Void = {}) {
        self._form = State(initialValue: form)
        self._originalTags = State(initialValue: form.tags)
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
                    subtitle: "changes here do not touch the text",
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
                WritingChoiceRow(title: "Rating", value: $form.tags.rating, options: form.ratingOptions)
                    .panelSegment(0, of: 1, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Archive warnings")
                    .padding(.bottom, 8)
                    .pageBodyRow(top: 18, gutter: selfGuttered)
            }
            Section {
                checkRows(form.warningOptions, values: $form.tags.warnings)
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
        #if os(macOS)
        .navigationTitle("Edit tags")
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
        }
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
        WritingTagsRow(title: "Fandoms", values: $form.tags.fandoms, kind: .fandom)
            .panelSegment(0, of: 4, gutter: gutter)
        WritingTagsRow(title: "Relationships", values: $form.tags.relationships, kind: .relationship)
            .panelSegment(1, of: 4, gutter: gutter)
        WritingTagsRow(title: "Characters", values: $form.tags.characters, kind: .character)
            .panelSegment(2, of: 4, gutter: gutter)
        WritingTagsRow(title: "Additional tags", values: $form.tags.additionalTags, kind: .freeform)
            .panelSegment(3, of: 4, gutter: gutter)
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await auth.editTags(workID: form.workID, current: originalTags, desired: form.tags)
                onSaved()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}
