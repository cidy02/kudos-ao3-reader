import SwiftUI

/// Fills the Search tab's idle state with a live browse of AO3's media categories
/// (scraped from `/media`). On iOS, tapping a category pushes a dedicated fandom
/// list; on macOS it expands inline to the featured fandoms.
struct MediaBrowserView: View {
    var onSelectFandom: (String) -> Void

    @State private var categories: [AO3MediaCategory] = []
    @State private var phase: Phase = .loading
    #if os(macOS)
    /// Tracked explicitly (keyed by category name) so a row's expansion can't be
    /// recycled onto a different category as the List scrolls.
    @State private var expanded: Set<String> = []
    #endif

    private enum Phase: Equatable { case loading, loaded, failed(String) }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView("Loading fandoms…")
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't load fandoms", systemImage: "wifi.slash")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            case .loaded:
                categoryList
            }
        }
        .task { if categories.isEmpty { await load() } }
    }

    private var categoryList: some View {
        List {
            Section {
                ForEach(categories) { category in
                    #if os(iOS)
                    NavigationLink(value: category) {
                        categoryLabel(category)
                    }
                    #else
                    DisclosureGroup(isExpanded: expansionBinding(for: category.id)) {
                        ForEach(category.fandoms) { fandom in
                            Button {
                                onSelectFandom(fandom.name)
                            } label: {
                                Text(fandom.name)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } label: {
                        categoryLabel(category)
                    }
                    #endif
                }
                // Cards only on the category rows — not the Section — so the header
                // and footer render as plain instructional text, not in a card.
                .cardRow()
            } header: {
                Text("Browse by fandom")
            } footer: {
                #if os(iOS)
                Text("Browse fandoms from AO3. Tap a category to see its fandoms.")
                #else
                Text("Popular fandoms from AO3. Tap one to search its works.")
                #endif
            }
        }
        .cardList()
    }

    /// A category row label. The leading glyph is rendered in the primary label
    /// colour (rather than the default full accent-blue) so it matches the app's
    /// tab-bar / sidebar icons instead of standing out.
    private func categoryLabel(_ category: AO3MediaCategory) -> some View {
        Label {
            Text(category.name)
        } icon: {
            Image(systemName: category.symbol)
                .foregroundStyle(.primary)
        }
        .font(.headline)
    }

    #if os(macOS)
    private func expansionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isOpen in
                if isOpen { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }
    #endif

    private func load() async {
        phase = .loading
        do {
            categories = try await AO3Client.shared.mediaCategories()
            phase = .loaded
        } catch let error as AO3Error {
            phase = .failed(error.errorDescription ?? "Something went wrong.")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
