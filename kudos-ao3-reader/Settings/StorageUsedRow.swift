import SwiftUI

/// Artboard **1ab**'s "Storage used", the one row of its Downloads group that
/// corresponds to something the app can actually answer.
///
/// The board's other two rows — "Download on subscribe" and "Keep downloads
/// for 30 days" — describe behaviour that does not exist: there is no
/// subscription-triggered download and no retention sweep anywhere in the
/// project. Drawing them would be three controls that change nothing, which is
/// worse than an honest gap, so they are left out until the behaviour is real.
///
/// The number itself is the same one Privacy and local data breaks down, so the
/// two can never disagree.
struct StorageUsedRow: View {
    @State private var footprint: LocalStorageFootprint?

    var body: some View {
        LabeledContent("Storage used") {
            if let footprint {
                Text(LocalStorageFootprint.formatted(bytes: footprint.totalBytes))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                // Measuring walks several directories, so the row says it is
                // working rather than showing a zero that is about to change.
                ProgressView().controlSize(.small)
            }
        }
        .task {
            if footprint == nil { footprint = await LocalDataFootprintScanner.measure() }
        }
        .accessibilityLabel("Storage used")
        .accessibilityValue(
            footprint.map { LocalStorageFootprint.formatted(bytes: $0.totalBytes) } ?? "Measuring"
        )
    }
}
