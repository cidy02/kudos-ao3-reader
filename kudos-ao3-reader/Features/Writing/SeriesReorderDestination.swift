import SwiftUI

/// Loads the series manage page, then hands the works to `SeriesReorderView`.
///
/// 1w's Reorder swipe cannot open `SeriesReorderView` directly: that screen
/// wants the works already in hand, and a series blurb does not carry them.
/// `loadSeriesManagePage` is the same GET `SeriesEditDestination` already makes
/// while loading the edit form. Saving stays inside `SeriesReorderView`.
struct SeriesReorderDestination: View {
    @Environment(AO3AuthService.self) private var auth
    /// An id and title rather than an `AO3SeriesSummary`: 1bw's series picker
    /// opens this from a work form's series option, which carries only those.
    let seriesID: Int
    let seriesTitle: String

    @State private var rows: [AO3SeriesWorkRow]?
    @State private var loadedGeneration: Int?
    @State private var errorMessage: String?
    @State private var retry = 0

    var body: some View {
        Group {
            if let rows, loadedGeneration == auth.sessionGeneration {
                SeriesReorderView(
                    seriesID: seriesID,
                    seriesTitle: seriesTitle,
                    rows: rows
                )
                .id(auth.sessionGeneration)
            } else {
                WritingLoaderPage(title: "Reorder series", message: errorMessage) { retry += 1 }
            }
        }
        .task(id: "\(auth.sessionGeneration):\(retry)") {
            if rows != nil, loadedGeneration == auth.sessionGeneration { return }
            rows = nil
            errorMessage = nil
            let generation = auth.sessionGeneration
            do {
                let loaded = try await auth.loadSeriesManagePage(seriesID: seriesID)
                guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
                loadedGeneration = generation
                rows = loaded
            } catch {
                guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
                errorMessage = UserFacingError.message(for: error)
            }
        }
    }
}
