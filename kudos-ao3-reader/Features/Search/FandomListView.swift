import OSLog
import SwiftUI

/// A dedicated page listing every fandom in a media category (loaded from AO3's
/// `/media/<name>/fandoms` index), sorted most-popular first with work counts and a
/// live filter. Tapping a fandom hands its name back to run a works search.
struct FandomListView: View {
    let category: AO3MediaCategory
    /// Called with the chosen fandom name; the host runs the search and pops back.
    let onSelect: (String) -> Void

    @State private var fandoms: [AO3Fandom] = []
    /// Names normalized once per load (`WorkSearchIndex.normalize`) so the live
    /// filter is a plain substring pass — a category holds up to tens of
    /// thousands of fandoms, and locale-collating every name on every keystroke
    /// (the old `localizedCaseInsensitiveContains` filter) froze typing.
    @State private var searchEntries: [FandomCatalog.SearchEntry] = []
    /// The rows the List renders. Refreshed by the debounced filter task instead
    /// of recomputed per keystroke render — re-diffing a many-thousand-row list
    /// on every letter was the other half of the freeze.
    @State private var filtered: [AO3Fandom] = []
    @State private var phase: Phase = .loading
    @State private var query = ""

    private enum Phase: Equatable { case loading, loaded, failed(String) }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                FandomRowSkeletonList()
            case let .failed(message):
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
                        FandomListRow(fandom: fandom)
                    }
                    .buttonStyle(.plain)
                    .cardRow()
                }
                // Card-based list, matching the Media Browser it's pushed from.
                .cardList()
                .refreshable { await refresh() }
                .searchable(text: $query, prompt: "Filter \(category.name)")
                .task(id: query) { await applyFilter() }
            }
        }
        .navigationTitle(category.name)
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .hidesFloatingTabBar()
            .task { if fandoms.isEmpty { await load() } }
    }

    /// One pass over the precomputed normalized names — case- and
    /// diacritic-insensitive (matching Global Search's folding, so "pokemon"
    /// finds "Pokémon"), preserving the list's most-popular-first order.
    private func matchedFandoms(for trimmedQuery: String) -> [AO3Fandom] {
        guard !trimmedQuery.isEmpty else { return fandoms }
        let normalizedQuery = WorkSearchIndex.normalize(trimmedQuery)
        return searchEntries.filter { $0.normalizedName.contains(normalizedQuery) }.map(\.fandom)
    }

    /// Debounced filter: coalesces a keystroke burst into one scan + one List
    /// diff. An emptied query restores the full list instantly.
    private func applyFilter() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            filtered = fandoms
            return
        }
        // Sleep throws when a newer keystroke restarts the task — just stop.
        guard (try? await Task.sleep(for: .milliseconds(120))) != nil else { return }
        filtered = matchedFandoms(for: trimmed)
    }

    private func load() async {
        phase = .loading
        await refresh()
    }

    private func refresh() async {
        do {
            var list = try await AO3Client.shared.fandoms(atPath: category.fandomsURL)
            // Surface the biggest fandoms first; the index arrives alphabetically.
            list.sort { ($0.workCount ?? 0) > ($1.workCount ?? 0) }
            fandoms = list
            searchEntries = list.map {
                FandomCatalog.SearchEntry(normalizedName: WorkSearchIndex.normalize($0.name), fandom: $0)
            }
            // Re-apply any active filter against the fresh list right away — the
            // debounced task only reruns on query changes, not data changes.
            filtered = matchedFandoms(for: query.trimmingCharacters(in: .whitespaces))
            phase = .loaded
        } catch let error as AO3Error {
            if fandoms.isEmpty {
                phase = .failed(error.errorDescription ?? "Something went wrong.")
            } else {
                Log.network.notice("Fandom list refresh failed: \(error.localizedDescription, privacy: .public)")
            }
        } catch {
            if fandoms.isEmpty {
                phase = .failed(error.localizedDescription)
            } else {
                Log.network.notice("Fandom list refresh failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

private struct FandomListRow: View {
    let fandom: AO3Fandom

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(nameLines, id: \.offset) { line in
                    Text(line.text)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let count = fandom.workCount {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                    Text(count.formatted())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel("\(count.formatted()) works")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var nameLines: [(offset: Int, text: String)] {
        let parts = fandom.name
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let lines = parts.isEmpty ? [fandom.name] : parts
        return lines.enumerated().map { ($0.offset, $0.element) }
    }
}
