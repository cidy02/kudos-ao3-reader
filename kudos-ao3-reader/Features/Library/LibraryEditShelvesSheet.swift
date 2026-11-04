import SwiftUI

/// Edit Shelves. "On the Library page" removes, reorders, and picks Carousel
/// or List. "As shelf buttons" adds and reorders. All Works stays in the header.
struct LibraryEditShelvesSheet: View {
    @Binding var arrangement: LibraryPageArrangement
    var counts: [LibraryShelfID: Int]
    var allWorksCount: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                        LibraryShelfGlyph.allWorks()
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
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("Close")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button { dismiss() } label: {
                            Image(systemName: "checkmark")
                        }
                        .sheetConfirmStyle()
                        .accessibilityLabel("Done")
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
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 10) {
                        removeButton(section, title: title)
                        LibraryShelfGlyph(shelf: section.id)
                        Text(title)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    picker(section, title: title)
                }
                .padding(.vertical, 4)
            } else {
                // Board 10 puts the name and the Carousel/List picker on one line.
                // Both only fit if the row is tight: at spacing 10 the picker was
                // ~20 pt short and truncated its own segments to "Carou…".
                HStack(alignment: .center, spacing: 6) {
                    removeButton(section, title: title)
                    LibraryShelfGlyph(shelf: section.id)
                    Text(title)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Spacer(minLength: 4)
                    picker(section, title: title)
                        .fixedSize()
                }
            }
        }
    }

    private func removeButton(_ section: LibraryPageSection, title: String) -> some View {
        Button {
            arrangement = arrangement.removingFromPage(section.id)
        } label: {
            Image(systemName: "minus.circle.fill")
                .font(.title3)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.red)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Remove \(title) from the Library page")
    }

    private func picker(_ section: LibraryPageSection, title: String) -> some View {
        Picker("\(title) layout", selection: styleBinding(section.id)) {
            ForEach(LibrarySectionStyle.allCases, id: \.self) { style in
                Image(systemName: style.symbolName)
                    .accessibilityLabel(style.title)
                    .tag(style)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("\(title) layout")
    }

    private func buttonRow(_ shelf: LibraryShelfID) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                arrangement = arrangement.addingToPage(shelf)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.green)
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
}
