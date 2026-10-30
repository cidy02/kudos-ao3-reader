import SwiftUI

/// Edit Shelves. "On the Library page" removes, reorders, and picks Carousel
/// or List. "As shelf buttons" adds and reorders. All Works stays in the header.
struct LibraryEditShelvesSheet: View {
    @Binding var arrangement: LibraryPageArrangement
    var counts: [LibraryShelfID: Int]
    var allWorksCount: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if arrangement.sections.isEmpty {
                        Text("Nothing is on the page. Add a shelf below.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(arrangement.sections) { section in
                        sectionRow(section)
                    }
                    .onMove(perform: moveSections)
                } header: {
                    Text("On the Library page")
                }
                .appThemedRows()

                Section {
                    if arrangement.buttons.isEmpty {
                        Text("Every shelf is on the page.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(arrangement.buttons) { shelf in
                        buttonRow(shelf)
                    }
                    .onMove(perform: moveButtons)
                } header: {
                    Text("As shelf buttons")
                }
                .appThemedRows()

                Section {
                    HStack(alignment: .center, spacing: 12) {
                        allWorksGlyph
                        VStack(alignment: .leading, spacing: 2) {
                            Text("All Works")
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Always in the Library header")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Text(allWorksCount.compactCount)
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("All Works, \(allWorksCount). Always in the Library header")
                }
                .appThemedRows()
            }
            .appThemedScroll()
            // Reorder handles stay up: this sheet exists to move shelves.
            // `editMode` is iOS-only; macOS lists reorder without it.
            #if os(iOS)
                .environment(\.editMode, .constant(.active))
            #endif
            .navigationTitle("Edit Shelves")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private func sectionRow(_ section: LibraryPageSection) -> some View {
        let title = section.id.title
        return HStack(alignment: .center, spacing: 10) {
            Button {
                arrangement = arrangement.removingFromPage(section.id)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.accentFill)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove \(title) from the Library page")

            LibraryShelfGlyph(shelf: section.id)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("\(title) layout", selection: styleBinding(section.id)) {
                    ForEach(LibrarySectionStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("\(title) layout")
            }
        }
        .padding(.vertical, 4)
    }

    private func buttonRow(_ shelf: LibraryShelfID) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                arrangement = arrangement.addingToPage(shelf)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.accentFill)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Show \(shelf.title) on the Library page")

            LibraryShelfGlyph(shelf: shelf)
            Text(shelf.title)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text((counts[shelf] ?? 0).compactCount)
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(counts[shelf] ?? 0)")
        }
    }

    private func styleBinding(_ id: LibraryShelfID) -> Binding<LibrarySectionStyle> {
        Binding(
            get: { arrangement.style(of: id) ?? .carousel },
            set: { arrangement = arrangement.settingStyle(id, to: $0) }
        )
    }

    private func moveSections(from offsets: IndexSet, to destination: Int) {
        arrangement = arrangement.movingSections(from: offsets, to: destination)
    }

    private func moveButtons(from offsets: IndexSet, to destination: Int) {
        arrangement = arrangement.movingButtons(from: offsets, to: destination)
    }

    /// All Works uses the same grey grid glyph the board gives it. It is not a
    /// shelf, so it has no add or remove.
    private var allWorksGlyph: some View {
        Image(systemName: "square.grid.2x2.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background {
                Circle().fill(Color(hex: "#6C6C70") ?? Color.gray)
            }
            .accessibilityHidden(true)
    }
}
