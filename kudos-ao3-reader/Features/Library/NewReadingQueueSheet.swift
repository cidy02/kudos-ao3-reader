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
/// **What 1j still draws that this does not build:** a Tags field, a "Keep works
/// offline" toggle, and a "Start from" seed picker. The first two need their own
/// schema — queues have no tag concept and no per-queue download policy, the gap
/// `ReadingQueueSettingsView` and `ReadingQueueOrganizer` both record in full.
/// "Start from" is closer to real, since `ReadingQueueService.addAndPreserve`
/// could be looped over another queue's works, but `createQueue(named:)` takes
/// only a name today, so seeding is a new capability rather than a control.
struct NewReadingQueueSheet: View {
    @Binding var name: String
    /// 1j: the colour is chosen before the name is typed, so it is committed with
    /// the queue rather than set afterwards. `nil` keeps the name-derived hue.
    @Binding var hue: Double?
    let onCreate: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif
                        .onSubmit(onCreate)
                } header: {
                    SubjectFieldLabel(text: "Name", style: .formGroup)
                }

                Section {
                    QueueHueSwatchRow(selection: $hue, fallbackHue: previewHue)
                } header: {
                    SubjectFieldLabel(text: "Colour", style: .formGroup)
                } footer: {
                    Text(hue == nil
                        ? "Without a colour, the queue takes one from its name — and changes it if you rename it."
                        : "Set once, so renaming the queue keeps its colour.")
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
                    Button("Create", action: onCreate)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium])
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
