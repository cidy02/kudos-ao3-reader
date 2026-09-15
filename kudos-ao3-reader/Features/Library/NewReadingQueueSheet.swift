import SwiftUI

/// Artboard **1j**'s "New Queue" sheet — shared by the queue organizer
/// (`AllReadingQueuesGridView`) and the per-queue browser
/// (`ReadingQueueBrowserView`), which each opened their own near-identical
/// plain `Form` before this.
///
/// **The colour swatches are built.** They were not, and the note that used to
/// sit here explained why: 1j wants a colour "set once instead of derived from
/// the name", every queue's colour was `CoverArt.hue(for: queue.displayName)`,
/// and storing one independently "would be a schema change, not a restyle".
/// That was the right call for a restyling task. `ReadingQueue.hue` is that
/// schema change, made by the sweep that was chartered for missing
/// functionality rather than layout, and it fixes a real defect on the way:
/// renaming a queue used to silently repaint it.
///
/// **Keep works offline and the seed step are built too.** The note that used to
/// sit here said they needed schema that did not exist — queues now have a
/// per-queue download policy (`ReadingQueue.keepsWorksOffline`), and
/// `createQueue` takes a seed.
///
/// **What 1j still draws that this does not build:** the Tags field. Queues do
/// have tags now, but adding them here would be a second tag-entry surface
/// beside `QueueTagSheet`, which already edits exactly this relationship from
/// Queue Details — so it is left to that one rather than duplicated.
struct NewReadingQueueSheet: View {
    @Binding var name: String
    /// 1j: the colour is chosen before the name is typed, so it is committed with
    /// the queue rather than set afterwards. `nil` keeps the name-derived hue.
    @Binding var hue: Double?
    /// Owned by the sheet rather than the three hosts: they each held `name` and
    /// `hue` already, and two more bindings apiece would be three identical
    /// copies of state that only this sheet reads.
    let onCreate: (NewQueueOptions) -> Void
    let onCancel: () -> Void

    @State private var options = NewQueueOptions()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif
                        .onSubmit { onCreate(options) }
                } header: {
                    SubjectFieldLabel(text: "Name", style: .formGroup)
                }

                Section {
                    SubjectHueSwatchRow(selection: $hue, fallbackHue: previewHue)
                } header: {
                    SubjectFieldLabel(text: "Colour", style: .formGroup)
                } footer: {
                    Text(hue == nil
                        ? "Without a colour, the queue takes one from its name — and changes it if you rename it."
                        : "Set once, so renaming the queue keeps its colour.")
                }
                .appThemedRows()

                Section {
                    Toggle("Keep works offline", isOn: $options.keepsWorksOffline)
                } header: {
                    SubjectFieldLabel(text: "Offline", style: .formGroup)
                } footer: {
                    Text("Works in this queue keep their download even after they "
                        + "leave it, so they stay readable offline.")
                }
                .appThemedRows()

                Section {
                    Picker("Start from", selection: $options.seed) {
                        ForEach(NewQueueSeed.allCases) { seed in
                            Text(seed.title).tag(seed)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } header: {
                    SubjectFieldLabel(text: "Start from", style: .formGroup)
                } footer: {
                    Text(options.seed == .empty
                        ? "An empty queue, ready to add to."
                        : "Copies what is in Saved for Later, in the same order. "
                            + "Those works stay in Saved for Later too.")
                }
                .appThemedRows()
            }
            .appThemedScroll()
            .navigationTitle("New Queue")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { onCreate(options) }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(iOS)
        // Taller than .medium now: 1j's sheet carries four groups, and a medium
        // detent hid the seed step below the fold — the one decision the board
        // says you never actually want to miss.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }

    /// What the name would give this queue if no swatch is picked — the same hash
    /// `ReadingQueue.displayHue` falls back to, so the preview cannot disagree
    /// with the queue that gets created.
    private var previewHue: Double {
        CoverArt.hue(for: name.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// 1j's "Start from". Two cases, because those are the two the app can honour:
/// the board also imagines seeding from a fandom, which needs the featured-fandom
/// parse 1g describes and this app does not have. Offering a third option that
/// silently produced an empty queue would be worse than not offering it.
nonisolated enum NewQueueSeed: String, CaseIterable, Identifiable, Sendable {
    case empty
    case savedForLater

    var id: String { rawValue }

    var title: String {
        switch self {
        case .empty: "Empty"
        case .savedForLater: "Saved for Later"
        }
    }
}

/// What the sheet collects beyond name and colour.
nonisolated struct NewQueueOptions: Equatable, Sendable {
    var keepsWorksOffline = false
    var seed: NewQueueSeed = .empty
}
