import SwiftUI

/// Pure copy and default-value helpers for `AccountInboxFilterSheet` (`Inbox-Filter` board).
nonisolated enum InboxFilterSheetCopy {
    static let title = "Filter Inbox"
    static let applyTitle = "Apply"
    static let cancelAccessibilityLabel = "Cancel"
    static let resetTitle = "Reset Filters"

    static func rowLabel(for field: AO3InboxFilterField) -> String {
        switch field.name {
        case AO3InboxPill.readField: "Read"
        case AO3InboxPill.repliedField: "Replied"
        case "filters[date]": "Sort"
        default: field.title
        }
    }

    static func segmentLabel(for option: AO3InboxFilterOption, in fieldName: String) -> String {
        switch (fieldName, option.value) {
        case (AO3InboxPill.readField, "all"): "All"
        case (AO3InboxPill.readField, "false"): "Unread"
        case (AO3InboxPill.readField, "true"): "Read"
        case (AO3InboxPill.repliedField, "all"): "All"
        case (AO3InboxPill.repliedField, "false"): "Unreplied"
        case (AO3InboxPill.repliedField, "true"): "Replied"
        case ("filters[date]", "desc"): "Newest"
        case ("filters[date]", "asc"): "Oldest"
        default: option.label
        }
    }

    static func defaultValues(for form: AO3InboxFilterForm) -> [String: String] {
        var defaults: [String: String] = [:]
        for field in form.fields {
            let preferred: String? = switch field.name {
            case AO3InboxPill.readField, AO3InboxPill.repliedField: "all"
            case "filters[date]": "desc"
            default: nil
            }
            if let preferred, field.options.contains(where: { $0.value == preferred }) {
                defaults[field.name] = preferred
            } else if let first = field.options.first?.value {
                defaults[field.name] = first
            }
        }
        return defaults
    }

    static func canReset(draftValues: [String: String], form: AO3InboxFilterForm?) -> Bool {
        guard let form else { return false }
        let defaults = defaultValues(for: form)
        guard !defaults.isEmpty else { return false }
        return defaults.contains { name, defaultValue in
            (draftValues[name] ?? form.selectedValues[name]) != defaultValue
        }
    }
}

/// Filter sheet for AO3's parsed Inbox GET filters (`Inbox-Filter` board).
/// Presents only the options AO3's loaded form renders, staging changes locally
/// until Apply so multi-field edits issue a single AO3 GET.
struct AccountInboxFilterSheet: View {
    var model: AO3InboxModel

    @Environment(AO3AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var themeManager
    @State private var draftValues: [String: String]

    init(model: AO3InboxModel) {
        self.model = model
        _draftValues = State(initialValue: Self.currentValues(for: model))
    }

    private static func currentValues(for model: AO3InboxModel) -> [String: String] {
        var values = model.currentFilterValues
        for (name, value) in model.filterValues {
            values[name] = value
        }
        return values
    }

    private var fields: [AO3InboxFilterField] {
        model.filterForm?.fields ?? []
    }

    private var segmentedFields: [AO3InboxFilterField] {
        guard !dynamicTypeSize.isAccessibilitySize else { return [] }
        return fields.filter { (2 ... 3).contains($0.options.count) }
    }

    private var listFields: [AO3InboxFilterField] {
        guard !dynamicTypeSize.isAccessibilitySize else { return fields }
        return fields.filter { !(2 ... 3).contains($0.options.count) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !segmentedFields.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(segmentedFields.enumerated()), id: \.element.id) { index, field in
                                if index > 0 {
                                    SubjectRowSeparator()
                                }
                                segmentedRow(for: field)
                            }
                        }
                        .subjectPanel()
                    }

                    ForEach(listFields) { field in
                        VStack(alignment: .leading, spacing: 8) {
                            SubjectFieldLabel(
                                text: InboxFilterSheetCopy.rowLabel(for: field),
                                style: .formGroup
                            )

                            VStack(spacing: 0) {
                                ForEach(Array(field.options.enumerated()), id: \.element.id) { index, option in
                                    let isSelected = selectedValue(for: field) == option.value
                                    if index > 0 {
                                        SubjectRowSeparator()
                                    }
                                    SubjectFormRow(
                                        label: InboxFilterSheetCopy.segmentLabel(for: option, in: field.name),
                                        arrangement: .value,
                                        action: {
                                            draftValues[field.name] = option.value
                                        }
                                    ) {
                                        HStack {
                                            if isSelected {
                                                Image(systemName: "checkmark")
                                                    .foregroundStyle(.tint)
                                                    .accessibilityHidden(true)
                                            }
                                        }
                                    }
                                    // Matches LibraryFilterPanel's `selectableRow` (X5) — without
                                    // this, VoiceOver announces the row but never says whether it's
                                    // currently selected (UI-2/T91-RF10).
                                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                                }
                            }
                            .subjectPanel()
                        }
                    }

                    if let form = model.filterForm {
                        let isResettable = InboxFilterSheetCopy.canReset(draftValues: draftValues, form: form)
                        Button {
                            draftValues = InboxFilterSheetCopy.defaultValues(for: form)
                        } label: {
                            Text(InboxFilterSheetCopy.resetTitle)
                                .font(.body)
                                .foregroundStyle(
                                    isResettable
                                        ? AnyShapeStyle(themeManager.accentInk)
                                        : AnyShapeStyle(.secondaryInk)
                                )
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!isResettable)
                        .subjectPanel()
                        .accessibilityLabel(InboxFilterSheetCopy.resetTitle)
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 40)
                .padding(.horizontal, SubjectMetrics.accountGutter)
            }
            // Inside the wash, which empties the title for pages with a header
            // block: the innermost title wins (as Save Search's).
            .navigationTitle(InboxFilterSheetCopy.title)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .subjectScreenWash(palette: themeManager.scopePalette)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(InboxFilterSheetCopy.cancelAccessibilityLabel)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(InboxFilterSheetCopy.applyTitle) {
                            applyAndDismiss()
                        }
                        .fontWeight(.semibold)
                        .sheetConfirmStyle()
                        .disabled(model.isPerformingBulkAction)
                    }
                }
                .onAppear {
                    draftValues = Self.currentValues(for: model)
                }
        }
    }

    private func segmentedRow(for field: AO3InboxFilterField) -> some View {
        let selection = Binding<String>(
            get: { selectedValue(for: field) ?? field.options.first?.value ?? "" },
            set: { draftValues[field.name] = $0 }
        )
        return SubjectFormRow(
            label: InboxFilterSheetCopy.rowLabel(for: field),
            arrangement: .control
        ) {
            SubjectSegmentedControl(
                options: field.options.map(\.value),
                title: { value in
                    if let option = field.options.first(where: { $0.value == value }) {
                        return InboxFilterSheetCopy.segmentLabel(for: option, in: field.name)
                    }
                    return value
                },
                selection: selection
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel(InboxFilterSheetCopy.rowLabel(for: field))
        }
    }

    private func selectedValue(for field: AO3InboxFilterField) -> String? {
        draftValues[field.name] ?? model.filterValues[field.name] ?? field.selectedValue
    }

    private func applyAndDismiss() {
        let initial = Self.currentValues(for: model)
        if !draftValues.isEmpty, draftValues != initial {
            model.applyFilters(draftValues, auth: auth)
        }
        dismiss()
    }
}

/// Mirrors the three-part Library bulk-action arrangement: destructive action on
/// the left, non-destructive actions clustered in the middle, and Done on the
/// right. Inbox delete only removes AO3's notification row; it never touches a
/// local work or its EPUB.
