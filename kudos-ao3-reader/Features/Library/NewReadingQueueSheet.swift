import SwiftUI

/// Artboard **1j**'s "New Queue" sheet — shared by the queue organizer
/// (`AllReadingQueuesGridView`) and the per-queue browser
/// (`ReadingQueueBrowserView`), which each opened their own near-identical
/// plain `Form` before this.
///
/// **What 1j draws that this does not build, and why:** a colour swatch
/// picker, a Tags field, a "Keep works offline" toggle, and a "Start from"
/// seed picker (Empty / copy another queue's works). 1j's own footnote under
/// the colour swatches says why the first is out of reach here: "Set once
/// instead of derived from the name" — the mock is describing a *different*
/// colour model than the one this app has. Every queue's colour is
/// `CoverArt.hue(for: queue.displayName)`, derived fresh from the name every
/// time (see `ReadingQueueBrowserView.subjectPalette`'s note) — adding an
/// independent, storable colour would be a schema change, not a restyle, and
/// this task is the latter. Tags and the offline toggle have no backing for
/// the same reason `ReadingQueueSettingsView` already gives in full. "Start
/// from" is closer to real — `ReadingQueueService.addAndPreserve` could be
/// looped over another queue's works — but it is still a new capability
/// (`createQueue(named:)` takes only a name today), not a restyle of an
/// existing one, so it was left for whoever picks up that feature rather than
/// folded in here.
///
/// So this sheet stays exactly what the app can honestly back: a name field,
/// styled in the redesign's own form vocabulary, and Cancel/Create.
struct NewReadingQueueSheet: View {
    @Binding var name: String
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
}
