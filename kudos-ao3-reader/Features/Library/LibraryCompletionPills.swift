import SwiftUI

/// 1ad's All / WIP pills, each with its count (`completionPillCounts`), for the
/// front of Reading Now's filter rail on Home and in Library. Neither is
/// selected while the panel has set Complete.
struct LibraryCompletionPills: View {
    @Binding var filters: LibraryFilters
    let works: [SavedWork]
    let palette: SubjectPalette

    var body: some View {
        let counts = filters.completionPillCounts(in: works)
        pill("All \(counts.all)", .any)
        pill("WIP \(counts.wip)", .inProgress)
    }

    private func pill(_ text: String, _ completion: AO3SearchFilters.Completion) -> some View {
        let isSelected = filters.completion == completion
        return Button {
            filters.completion = completion
        } label: {
            SubjectChip(text: text, style: .pill(isSelected: isSelected), palette: palette)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
