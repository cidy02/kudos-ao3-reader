import SwiftData
import SwiftUI

/// Artboard **1bk** — creating a local collection.
///
/// A sheet rather than the bare name alert this replaced. 1bk draws two groups:
/// **Collection** (name, an optional description, colour) and **Behaviour**
/// (keep downloads, show on Home), each with its consequence written under it.
///
/// Colour is picked here rather than assigned, which is the board's own point:
/// a hue derived from the name silently repaints a collection when it is
/// renamed. `nil` still means "take it from the name", so nothing forces a
/// choice — it just stops being the only option.
struct NewCollectionSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme

    @State private var name = ""
    @State private var collectionDescription = ""
    @State private var hue: Double?
    @State private var keepsWorksOffline = false
    @State private var showsOnHome = false

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SubjectFieldLabel(text: "Collection", style: .formGroup)
                        .pageBodyRow(top: 18, gutter: SubjectMetrics.gutter)
                    collectionPanel
                        .pageBodyRow(top: 8, gutter: SubjectMetrics.gutter)
                }

                Section {
                    SubjectFieldLabel(text: "Behaviour", style: .formGroup)
                        .pageBodyRow(top: 18, gutter: SubjectMetrics.gutter)
                    behaviourPanel
                        .pageBodyRow(top: 8, gutter: SubjectMetrics.gutter)
                    footnote("Keep downloads exempts these works from the cache sweep. "
                        + "Show on Home adds a shelf above Recently Updated.")
                }

                Section {
                    footnote("Local collections live on this device only. AO3 never "
                        + "sees them, and they do not sync between your devices.")
                }
            }
            .cardList()
            .navigationTitle("New collection")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .subjectScreenWash(palette: theme.scopePalette)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create", action: create)
                            .disabled(trimmedName.isEmpty)
                    }
                }
        }
    }

    private var collectionPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Name", arrangement: .control) {
                TextField("Comfort reads", text: $name)
                    .multilineTextAlignment(.trailing)
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "Description", arrangement: .control) {
                TextField("Optional", text: $collectionDescription)
                    .multilineTextAlignment(.trailing)
            }
            SubjectRowSeparator()
            // The ring shows "derived from the name" as a visible state, so the
            // fallback has to be the hue that name would actually produce.
            SubjectHueSwatchRow(
                selection: $hue,
                fallbackHue: CoverArt.hue(for: trimmedName)
            )
        }
        .subjectPanel()
    }

    private var behaviourPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Keep downloads", arrangement: .control) {
                Toggle("", isOn: $keepsWorksOffline).labelsHidden()
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "Show on Home", arrangement: .control) {
                Toggle("", isOn: $showsOnHome).labelsHidden()
            }
        }
        .subjectPanel()
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .pageBodyRow(top: 8, gutter: SubjectMetrics.gutter)
    }

    /// The description is stored on `collectionDescription`, which already
    /// existed to keep Android's field alive across a restore. 1bk gives it a
    /// UI, so it stops being parity-only storage.
    ///
    /// Both toggles are written as real choices — the reader was asked here, so
    /// "off" is an answer rather than the absence of one.
    private func create() {
        let trimmed = trimmedName
        guard !trimmed.isEmpty else { return }
        let collection = WorkCollection(name: trimmed)
        collection.hue = hue
        collection.collectionDescription = collectionDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
        collection.keepsWorksOffline = keepsWorksOffline
        collection.showsOnHome = showsOnHome
        context.insert(collection)
        context.saveBestEffort(reason: "Creating collection failed")
        dismiss()
    }
}
