import SwiftUI

/// Loads the series manage page, then hands the works to `SeriesReorderView`.
///
/// 1w's Reorder swipe cannot open `SeriesReorderView` directly: that screen
/// wants the works already in hand, and a series blurb does not carry them.
/// `loadSeriesManagePage` is the same GET `SeriesEditDestination` already makes
/// while loading the edit form. Saving stays inside `SeriesReorderView`.
struct SeriesReorderDestination: View {
    @Environment(AO3AuthService.self) private var auth
    let series: AO3SeriesSummary

    @State private var rows: [AO3SeriesWorkRow]?
    @State private var loadedGeneration: Int?
    @State private var errorMessage: String?
    @State private var retry = 0

    var body: some View {
        Group {
            if let rows, loadedGeneration == auth.sessionGeneration {
                SeriesReorderView(
                    seriesID: series.id,
                    seriesTitle: series.title,
                    rows: rows
                )
                .id(auth.sessionGeneration)
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Text(errorMessage)
                    Button("Retry") { retry += 1 }
                }
                .padding()
            } else {
                ProgressView("Loading series…")
            }
        }
        .task(id: "\(auth.sessionGeneration):\(retry)") {
            if rows != nil, loadedGeneration == auth.sessionGeneration { return }
            rows = nil
            errorMessage = nil
            let generation = auth.sessionGeneration
            do {
                let loaded = try await auth.loadSeriesManagePage(seriesID: series.id)
                guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
                loadedGeneration = generation
                rows = loaded
            } catch {
                guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}
