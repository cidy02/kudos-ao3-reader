import SwiftUI

/// Searchable destination for AO3's language list. A menu is right for the
/// panel's 3-to-8 option pickers and wrong for 82 languages;
/// `.pickerStyle(.navigationLink)` would push without a search field, so this
/// is the part that has to be written.
///
/// Order is AO3's own: "Any language" first as the cleared state, then each
/// language by its native name (`Language.allCases`).
struct FilterLanguagePicker: View {
    @Binding var selection: AO3SearchFilters.Language
    @State private var query = ""

    var body: some View {
        List {
            Group {
                ForEach(Self.matching(query)) { language in
                    Button {
                        selection = language
                    } label: {
                        HStack {
                            Text(language.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if language == selection {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(language == selection ? .isSelected : [])
                }
            }
            .appThemedRows()
        }
        .appThemedScroll()
        .navigationTitle("Language")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: searchPrompt
            )
        #else
            .searchable(text: $query, prompt: searchPrompt)
        #endif
    }

    private var searchPrompt: String {
        "Search \(Self.selectableCount) languages"
    }

    /// Languages AO3 actually filters on — `allCases` minus the cleared state.
    static var selectableCount: Int {
        AO3SearchFilters.Language.allCases.count - 1
    }

    /// Native-name (and id) substring match, case- and diacritic-insensitive.
    /// Empty query returns AO3's full list, with "Any language" still first.
    static func matching(_ query: String) -> [AO3SearchFilters.Language] {
        let all = AO3SearchFilters.Language.allCases
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        let needle = WorkSearchIndex.normalize(trimmed)
        return all.filter { language in
            WorkSearchIndex.normalize(language.title).contains(needle)
                || WorkSearchIndex.normalize(language.id).contains(needle)
        }
    }
}
