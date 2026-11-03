import SwiftData
import SwiftUI

/// The four confirmations behind Privacy and local data's clear actions, shared by
/// that page and the Privacy settings page (board 51) so a clear asks the same
/// question, with the same words, wherever it is started from.
struct LocalDataClearDialogs: ViewModifier {
    let works: [SavedWork]
    @Binding var confirmHistory: Bool
    @Binding var confirmDownloads: Bool
    @Binding var confirmPositions: Bool
    @Binding var confirmBrowseCache: Bool
    @Binding var browseCacheCleared: Bool
    /// The cache size as the host prints it ("118 MB", or an em dash before the scan).
    let cacheLabel: String
    /// Re-measure after a clear that changes bytes on disk.
    let onMeasure: () -> Void

    @Environment(\.modelContext) private var context

    /// Works whose file was already freed — the local reading history the
    /// "Clear Reading History" action moves to Recently Deleted. Gated on
    /// `isProtected`: saved, favourited, imported and AO3-404'd works are not
    /// history and the dialog promises they stay.
    static func freedHistory(from works: [SavedWork]) -> [SavedWork] {
        works.filter { !$0.hasEPUB && !$0.isProtected }
    }

    private var freedHistory: [SavedWork] { Self.freedHistory(from: works) }
    private var freeable: [SavedWork] { LocalDataClearing.selectFreeableDownloads(from: works) }
    private var positioned: [SavedWork] { LocalDataClearing.selectReadingPositions(from: works) }

    private func countLabel(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Clear Reading History?",
                isPresented: $confirmHistory,
                titleVisibility: .visible
            ) {
                Button("Clear \(countLabel(freedHistory.count, "Work"))", role: .destructive) {
                    for work in freedHistory {
                        PreservedWorkService.softDelete(work, in: context)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Moves works that only remain in your reading history to Recently Deleted for "
                    + "\(PreservedWorkService.recoveryWindowText). Your saved and downloaded works "
                    + "stay where they are, and you can download these works from AO3 again.")
            }
            .confirmationDialog(
                "Free Up Space?",
                isPresented: $confirmDownloads,
                titleVisibility: .visible
            ) {
                Button("Free \(countLabel(freeable.count, "File"))", role: .destructive) {
                    LocalDataClearing.clearFreeableDownloads(from: works, in: context)
                    onMeasure()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes the copies of works you've finished reading and didn't download, "
                    + "favourite or queue. Kudos gets them again from AO3 if you open them.")
            }
            .confirmationDialog(
                "Clear Reading Positions?",
                isPresented: $confirmPositions,
                titleVisibility: .visible
            ) {
                Button("Clear \(countLabel(positioned.count, "Position"))", role: .destructive) {
                    LocalDataClearing.clearReadingPositions(from: works, in: context)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Clears your place in every work. Your works and their order in Continue Reading "
                    + "stay the same.")
            }
            .confirmationDialog(
                "Clear Browse Cache?",
                isPresented: $confirmBrowseCache,
                titleVisibility: .visible
            ) {
                Button("Clear \(cacheLabel)", role: .destructive) {
                    FandomCatalog.shared.clearCache()
                    browseCacheCleared = true
                    onMeasure()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes saved fandom and category lists. Your reading, saved works, and "
                    + "downloads stay untouched; Browse rebuilds the lists next time you open it.")
            }
    }
}
