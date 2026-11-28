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
    /// True when rendered inside the docked Duo Filters pane so its search field and
    /// title stay pane-local instead of attaching to Search's outer navigation bar.
    var isInlinePane = false
    @Environment(ThemeManager.self) private var themeManager
    @State private var query = ""

    var body: some View {
        if isInlinePane {
            VStack(spacing: 0) {
                inlineSearchBar
                languageList
            }
        } else {
            languageList
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
    }

    private var inlineSearchBar: some View {
        let field = GlassFieldBar(text: $query, placeholder: searchPrompt) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondaryInk)
        } trailing: {
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.caption)
                }
                .accessibilityLabel("Clear search")
                .buttonStyle(.plain)
                .foregroundStyle(.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 40)

        return Group {
            #if os(iOS)
            field.glassEffect(.regular.interactive(), in: .capsule)
            #else
            field
                .background(themeManager.appTheme.cardSurface, in: Capsule())
                .overlay(Capsule().strokeBorder(themeManager.appTheme.cardBorder, lineWidth: 0.5))
            #endif
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var languageList: some View {
        List {
            Section {
                ForEach(Self.matching(query)) { language in
                    Button {
                        selection = language
                    } label: {
                        HStack {
                            Text(language.title)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            if language == selection {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.tint)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(language == selection ? .isSelected : [])
                }
            } header: {
                Text("All languages").textCase(nil)
            }
            .appThemedRows()
        }
        .appThemedScroll()
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
