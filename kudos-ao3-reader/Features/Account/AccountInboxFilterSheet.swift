import SwiftUI

/// AO3 query values in the app.
struct AccountInboxFilterSheet: View {
    var model: AO3InboxModel

    @Environment(AO3AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    ForEach(model.filterForm?.fields ?? []) { field in
                        VStack(alignment: .leading, spacing: 8) {
                            SubjectFieldLabel(text: field.title, style: .formGroup)

                            VStack(spacing: 0) {
                                ForEach(Array(field.options.enumerated()), id: \.element.id) { index, option in
                                    let isSelected = selectedValue(for: field) == option.value
                                    if index > 0 {
                                        SubjectRowSeparator()
                                    }
                                    SubjectFormRow(
                                        label: option.label,
                                        arrangement: .value,
                                        action: {
                                            model.applyFilter(
                                                fieldName: field.name,
                                                value: option.value,
                                                auth: auth
                                            )
                                            dismiss()
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
                }
                .padding(.top, 20)
                .padding(.bottom, 40)
                .padding(.horizontal, SubjectMetrics.accountGutter)
            }
            .subjectScreenWash(palette: themeManager.appTheme.subjectPalette(hue: themeManager.scopeHue))
            .navigationTitle("Inbox Filters")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { dismiss() } label: {
                            Image(systemName: "checkmark")
                        }
                        .accessibilityLabel("Done")
                    }
                }
        }
    }

    private func selectedValue(for field: AO3InboxFilterField) -> String? {
        model.filterValues[field.name] ?? field.selectedValue
    }
}

/// Mirrors the three-part Library bulk-action arrangement: destructive action on
/// the left, non-destructive actions clustered in the middle, and Done on the
/// right. Inbox delete only removes AO3's notification row; it never touches a
/// local work or its EPUB.
