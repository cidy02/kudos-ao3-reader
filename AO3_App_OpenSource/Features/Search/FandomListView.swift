import SwiftUI

/// A dedicated page listing every fandom in a media category (loaded from AO3's
/// `/media/<name>/fandoms` index), sorted most-popular first with work counts and a
/// live filter. Tapping a fandom hands its name back to run a works search.
struct FandomListView: View {
    let category: AO3MediaCategory
    /// Called with the chosen fandom name; the host runs the search and pops back.
    let onSelect: (String) -> Void

    @State private var fandoms: [AO3Fandom] = []
    @State private var phase: Phase = .loading
    @State private var query = ""

    private enum Phase: Equatable { case loading, loaded, failed(String) }

    private var filtered: [AO3Fandom] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return fandoms }
        return fandoms.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                FandomRowSkeletonList()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't load fandoms", systemImage: "wifi.slash")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            case .loaded:
                List(filtered) { fandom in
                    Button {
                        onSelect(fandom.name)
                    } label: {
                        HStack(spacing: 12) {
                            Text(fandom.name)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let count = fandom.workCount {
                                Text(count.formatted())
                                    .font(.footnote)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .cardRow()
                }
                // Card-based list, matching the Media Browser it's pushed from.
                .cardList()
                .searchable(text: $query, prompt: "Filter \(category.name)")
            }
        }
        .navigationTitle(category.name)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { if fandoms.isEmpty { await load() } }
    }

    private func load() async {
        phase = .loading
        do {
            var list = try await AO3Client.shared.fandoms(atPath: category.fandomsURL)
            // Surface the biggest fandoms first; the index arrives alphabetically.
            list.sort { ($0.workCount ?? 0) > ($1.workCount ?? 0) }
            fandoms = list
            phase = .loaded
        } catch let error as AO3Error {
            phase = .failed(error.errorDescription ?? "Something went wrong.")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
