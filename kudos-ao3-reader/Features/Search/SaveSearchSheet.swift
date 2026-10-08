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
    @ScaledMetric(relativeTo: .body) private var nameFieldSize: CGFloat = 17
    @ScaledMetric(relativeTo: .caption) private var footnoteSize: CGFloat = 11.5
    @ScaledMetric(relativeTo: .footnote) private var emptySummarySize: CGFloat = 12.5

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
                        .font(.system(size: nameFieldSize))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .subjectPanel()
                        .pageBodyRow(top: 14, gutter: SubjectMetrics.accountGutter)

                    Text("The name comes from your search. You can change it to anything.")
                        .font(.system(size: footnoteSize))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .pageBodyRow(top: 6, gutter: SubjectMetrics.accountGutter)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        if summary.isEmpty {
                            Text("You haven't chosen any filters, so only the name will be saved.")
                                .font(.system(size: emptySummarySize))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .subjectPanel()
                        } else {
                            FlowLayout(spacing: 6, rowSpacing: 6) {
                                ForEach(summary) { item in
                                    SaveSearchSummaryChip(text: item.text, kind: item.kind)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .subjectPanel()
                        }

                        Text("Only the choices you changed are saved.")
                            .font(.system(size: footnoteSize))
                            .foregroundStyle(.secondary)
                    }
                    .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
                } header: {
                    SectionRuleHeader(title: "What gets saved")
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
            .screenTint(palette)
    }

    // MARK: What gets saved

    private struct SummaryItem: Identifiable {
        let id: String
        let text: String
        let kind: SaveSearchSummaryKind
    }

    /// The filters as the artboard lists them: included terms plainly, excluded
    /// terms prefixed with a minus and drawn dashed, then the faceted choices.
    ///
    /// Deliberately built from the filter values rather than from a stored
    /// description — a saved search is only worth trusting if this list is the
    /// same data that gets persisted, and a parallel summary would drift.
    private var summary: [SummaryItem] {
        var items: [SummaryItem] = []
        let query = filters.query.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            items.append(SummaryItem(id: "query", text: "\u{201C}\(query)\u{201D}", kind: .included))
        }
        // 1ax: everything the saved search will run with — the same labels the
        // results rail prints, warnings, ranges, language and the sort included.
        // A partial copy here is how the sheet came to hide half the search.
        for (index, label) in filters.summaryLabels().enumerated() {
            items.append(SummaryItem(
                id: "\(index)-\(label.text)",
                text: label.text,
                kind: label.text.hasPrefix("−") ? .excluded : (label.symbol == nil ? .facet : .included)
            ))
        }
        return items
    }
}

private enum SaveSearchSummaryKind {
    case included
    case excluded
    case facet
}

private struct SaveSearchSummaryChip: View {
    let text: String
    let kind: SaveSearchSummaryKind

    @Environment(ThemeManager.self) private var theme
    @ScaledMetric(relativeTo: .caption) private var chipTextSize: CGFloat = 12

    var body: some View {
        Text(text)
            .font(.system(size: chipTextSize))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(foreground)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(stroke, lineWidth: 0.5))
    }

    private var foreground: Color {
        switch kind {
        case .included: .green
        case .excluded: .red
        case .facet: .primary
        }
    }

    private var fill: Color {
        switch kind {
        case .included: .green.opacity(0.15)
        case .excluded: .red.opacity(0.15)
        case .facet: theme.appTheme.glassFill(0.10)
        }
    }

    private var stroke: Color {
        switch kind {
        case .included: .green.opacity(0.35)
        case .excluded: .red.opacity(0.35)
        case .facet: theme.appTheme.glassStroke(0.16)
        }
    }
}
