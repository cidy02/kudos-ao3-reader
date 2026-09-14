import SwiftUI

/// Artboard **1ax** — Save search.
///
/// Replaces a bare naming alert. The alert could take a name and nothing else,
/// which asks the reader to commit to a saved search on the strength of
/// remembering what they had just typed into a filter panel they can no longer
/// see. The artboard's answer is "What gets saved": the filters themselves,
/// listed, before the save happens.
///
/// The spec's own note on the name field is the other half — *"Named from what
/// the search is of. Rename it to anything."* The default name is derived, and
/// saying so is what makes it obviously editable rather than official.
struct SaveSearchSheet: View {
    let filters: AO3SearchFilters
    @Binding var name: String
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme

    private var palette: SubjectPalette {
        theme.appTheme.subjectPalette(hue: CoverArt.workHue(fandoms: [], title: name))
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Name", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 17))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .subjectPanel()
                        .pageBodyRow(top: 14, gutter: SubjectMetrics.accountGutter)

                    Text("Named from what the search is of. Rename it to anything.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .pageBodyRow(top: 6, gutter: SubjectMetrics.accountGutter)
                }

                Section {
                    if summary.isEmpty {
                        Text("This search has no filters yet — only its name will be saved.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .subjectPanel()
                            .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
                    } else {
                        FlowLayout(spacing: 8, rowSpacing: 8) {
                            ForEach(summary) { item in
                                SubjectChip(
                                    text: item.text,
                                    style: item.isExcluded ? .dashed : .neutral
                                )
                            }
                        }
                        .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
                    }
                } header: {
                    SectionRuleHeader(title: "What gets saved", count: summary.isEmpty ? nil : summary.count)
                        .pageBodyRow(top: 20, gutter: 0)
                }
            }
            .cardList()
            .subjectScreenWash(palette: palette)
            .navigationTitle("Save Search")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    // MARK: What gets saved

    struct SummaryItem: Identifiable {
        let id: String
        let text: String
        let isExcluded: Bool
    }

    /// The filters as the artboard lists them: included terms plainly, excluded
    /// terms prefixed with a minus and drawn dashed, then the faceted choices.
    ///
    /// Deliberately built from the filter values rather than from a stored
    /// description — a saved search is only worth trusting if this list is the
    /// same data that gets persisted, and a parallel summary would drift.
    private var summary: [SummaryItem] {
        var items: [SummaryItem] = []

        func appendTags(_ raw: String, isExcluded: Bool) {
            for tag in raw.split(separator: ",") {
                let text = tag.trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { continue }
                items.append(SummaryItem(
                    id: "\(isExcluded ? "-" : "+")\(text)",
                    text: isExcluded ? "−\(text)" : text,
                    isExcluded: isExcluded
                ))
            }
        }

        let query = filters.query.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            items.append(SummaryItem(id: "query", text: "\u{201C}\(query)\u{201D}", isExcluded: false))
        }
        let title = filters.title.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty {
            items.append(SummaryItem(id: "title", text: "Title: \(title)", isExcluded: false))
        }
        let creators = filters.creators.trimmingCharacters(in: .whitespaces)
        if !creators.isEmpty {
            items.append(SummaryItem(id: "creators", text: "By \(creators)", isExcluded: false))
        }

        appendTags(filters.fandom, isExcluded: false)
        appendTags(filters.relationships, isExcluded: false)
        appendTags(filters.characters, isExcluded: false)
        appendTags(filters.additionalTags, isExcluded: false)
        appendTags(filters.excludedFandoms, isExcluded: true)
        appendTags(filters.excludedRelationships, isExcluded: true)
        appendTags(filters.excludedCharacters, isExcluded: true)
        appendTags(filters.excludedAdditionalTags, isExcluded: true)

        if filters.rating != .any {
            // "Teen And Up+" in the artboard: the rating, and whether the search
            // takes that rating exactly or that rating and above.
            let suffix = filters.ratingMatch == .exact ? "" : "+"
            items.append(SummaryItem(
                id: "rating",
                text: "\(filters.rating.title)\(suffix)",
                isExcluded: false
            ))
        }

        return items
    }
}
