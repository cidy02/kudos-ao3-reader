import SwiftData
import SwiftUI

/// Review screen for a D8 anomaly hold: ≥10 unsigned `isDeleted` hides arrived
/// in one sync/restore batch and were not applied.
struct UnsignedDeletionReviewView: View {
    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var themeManager

    let hold: UnsignedDeletionReview.Hold
    let onDismiss: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(
                        "\(hold.count) works from \(hold.sourceLabel) want to be hidden. "
                            + "Review before applying. Hidden works stay in Recently Deleted "
                            + "and are not scheduled for permanent deletion."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Section("Works") {
                    ForEach(Array(hold.titles.enumerated()), id: \.offset) { _, title in
                        Text(title)
                            .lineLimit(2)
                    }
                }
            }
            .cardList()
            .appThemedScroll()
            .appThemedRows()
            .navigationTitle("Review Hidden Works")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Keep Visible") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hide \(hold.count)") { onConfirm() }
                }
            }
        }
        .background((themeManager.appTheme.appBaseBackground ?? Color.clear).ignoresSafeArea())
    }
}
