import OSLog
import SwiftUI

/// A dedicated page listing every fandom in a media category (loaded from AO3's
/// `/media/<name>/fandoms` index), sorted most-popular first with work counts and a
/// live filter. Tapping a fandom hands its name back to run a works search.
struct FandomListView: View {
    let category: AO3MediaCategory
    /// Called with the chosen fandom name; the host runs the search and pops back.
    let onSelect: (String) -> Void

    /// The other half of the Browse zoom pair — set by BrowseView on the stack.
    @Environment(\.workCardTransitionNamespace) private var zoomNamespace

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
                    // This row is the source for the next hop: the works list it pushes
                    // zooms out of it. On the Button — the control that performs the
                    // navigation — for the same reason the category card marks its
                    // NavigationLink rather than the card nested inside it.
                    .workCardZoomSource(BrowseZoomKey.fandom(fandom.name), in: zoomNamespace)
                    .cardRow()
                }
                // Card-based list, matching the Media Browser it's pushed from.
                .cardList()
                // Here rather than inside `refresh()`, which `load()` also calls:
                // the initial load has nothing to invalidate and would only evict
                // other screens' entries. `/media/<x>/fandoms` is
                // `max-age=600, public`; it escapes the cache today only because
                // the index is megabytes and overflows `URLCache`'s per-entry
                // ceiling, which is a fact about AO3's page size, not about us.
                .refreshable {
                    await AO3Client.shared.invalidateCachedResponses()
                    await refresh()
                }
                .searchable(text: $query, prompt: "Search \(category.name)")
                // Floats the filter field in the bottom bar instead of the navigation
                // bar, matching Settings and the rest of iOS 26: on a long list your
                // thumb is already down there, and the field stops eating the top of
                // the content. `.searchable` still owns the field and its behaviour —
                // this only says where the system should put it.
                .toolbar { DefaultToolbarItem(kind: .search, placement: .bottomBar) }
                .task(id: query) { await applyFilter() }
            }
        }
        .navigationTitle(category.name)
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .hidesFloatingTabBar()
            // Zooms out of the category card that pushed it. Keyed on the same
            // `category.id` that card advertises — one String on both ends, so
            // there is no cross-type mismatch to get wrong here (see WorkZoomKey
            // for the one that bit the work cards).
            .workCardZoomDestination(BrowseZoomKey.category(category.id), in: zoomNamespace)
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

/// Splits an AO3 fandom name into the part you scan for and the disambiguation
/// AO3 appends to keep tags unique.
///
/// AO3 has two conventions for that suffix and they differ in how safely they can
/// be detected:
///
///   * A trailing parenthetical — "Naruto (Anime & Manga)", "DCU (Comics)". Almost
///     unambiguous: a fandom title that genuinely ends in its own parenthetical is
///     rare enough to accept.
///   * A trailing " - " — "One Piece - All Media Types", but also "Hamilton -
///     Miranda" and "Be More Chill - Iconis/Tracz", where the tail is the creator
///     rather than a medium. Both are disambiguation, so both are demoted.
///
/// The dash rule is the looser of the two: a title that legitimately contains
/// " - " would have its tail greyed. That is cosmetic — the full name is still
/// shown, still searched, and still what gets handed to the works query — so the
/// looser rule is worth it to catch "All Media Types", which is everywhere.
/// Matching is on the LAST separator, so "Spider-Man - All Media Types" keeps its
/// hyphenated title (no spaces around that one) and demotes only the tail.
enum FandomDisplayName {
    static func split(_ name: String) -> (title: String, qualifier: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)

        if trimmed.hasSuffix(")"), let open = trimmed.lastIndex(of: "(") {
            let title = trimmed[trimmed.startIndex ..< open].trimmingCharacters(in: .whitespaces)
            // A name that is nothing but a parenthetical has no title to lead
            // with, so leave it whole rather than rendering an empty row.
            if !title.isEmpty {
                return (title, String(trimmed[open...]))
            }
        }

        if let separator = trimmed.range(of: " - ", options: .backwards) {
            let title = String(trimmed[trimmed.startIndex ..< separator.lowerBound])
            let tail = String(trimmed[separator.upperBound...])
            if !title.isEmpty, !tail.isEmpty {
                return (title, "- " + tail)
            }
        }

        return (trimmed, "")
    }
}

private struct FandomListRow: View {
    let fandom: AO3Fandom

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                // One Text, two runs: the qualifier stays on the title's line and
                // wraps with it, but in footnote grey it stops competing. Splitting
                // it into its own view would cost a line on nearly every row.
                (
                    Text(splitName.title).foregroundStyle(.primary)
                        + Text(splitName.qualifier.isEmpty ? "" : " " + splitName.qualifier)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                )
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

                // The other names this fandom is tagged under, demoted to one
                // quiet line: on a list this long they are context, not what
                // you are scanning for. Joined rather than stacked so a
                // three-name tag costs one extra line instead of two.
                if !aliases.isEmpty {
                    Text(aliases.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let count = fandom.workCount {
                HStack(spacing: 4) {
                    // Secondary, not tinted: the glyph is the same on every row,
                    // so in accent red it competed with the name for attention
                    // while carrying no per-row information.
                    Image(systemName: "doc.text")
                        .font(.caption.weight(.semibold))
                    Text(count.formatted())
                        .monospacedDigit()
                        // Fixed column, trailing-aligned: without it the glyph
                        // slides left or right with the digit count and no two
                        // rows line up. Wide enough for AO3's largest fandoms
                        // (~700k) at this size.
                        .frame(minWidth: 58, alignment: .trailing)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel("\(count.formatted()) works")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// AO3 writes a multilingual fandom tag as `original | romanization |
    /// localized` — "僕のヒーローアカデミア | Boku no Hero Academia | My Hero
    /// Academia (Anime & Manga)" — so the last segment is the one an
    /// English-locale reader is scanning for. Single-segment tags ("Marvel")
    /// are their own primary and have no aliases.
    private var nameParts: [String] {
        let parts = fandom.name
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? [fandom.name] : parts
    }

    private var primaryName: String { nameParts[nameParts.count - 1] }

    private var splitName: (title: String, qualifier: String) { FandomDisplayName.split(primaryName) }

    private var aliases: [String] { Array(nameParts.dropLast()) }
}
