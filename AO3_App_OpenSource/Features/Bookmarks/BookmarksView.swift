import SwiftUI
import SwiftData

/// The Bookmarks tab: saved AO3 links (reopen in Browse) and favorited works.
struct BookmarksView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(PrivacyGate.self) private var gate
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure

    @Query(sort: \Bookmark.dateAdded, order: .reverse) private var bookmarks: [Bookmark]
    @Query(
        filter: #Predicate<SavedWork> { $0.isFavorite },
        sort: \SavedWork.dateAdded,
        order: .reverse
    ) private var favorites: [SavedWork]
    @Query(
        filter: #Predicate<SavedWork> { !$0.hasEPUB },
        sort: \SavedWork.dateAdded,
        order: .reverse
    ) private var history: [SavedWork]

    private enum Segment: String, CaseIterable, Identifiable {
        case links = "Links"
        case history = "History"
        case favorites = "Favorites"
        var id: String { rawValue }
    }

    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete = true

    @State private var segment: Segment = .links
    @State private var pendingDelete: SavedWork?

    var body: some View {
        NavigationStack {
            Group {
                switch segment {
                case .links: linksList
                case .history: historyList
                case .favorites: favoritesList
                }
            }
            .navigationTitle("Bookmarks")
            .navigationDestination(for: SavedWork.self) { work in
                WorkDetailView(work: work)
            }
            .toolbar {
                ToolbarItem(placement: .principal) { segmentControl }
                if hideMature && currentSegmentHasAdult {
                    ToolbarItem { MatureRevealToggle() }
                }
            }
            .deleteConfirmation(
                for: $pendingDelete,
                title: "Remove from History?",
                confirmLabel: "Remove",
                message: { "“\($0.title)” will be removed from your History." },
                perform: { removeFromHistory($0) }
            )
        }
    }

    /// The section switcher. iOS uses a single connected segmented control;
    /// macOS keeps the Liquid Glass pill buttons.
    private var segmentControl: some View {
        #if os(iOS)
        Picker("Section", selection: $segment) {
            ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        #else
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Segment.allCases) { seg in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { segment = seg }
                    } label: {
                        Text(seg.rawValue)
                            .font(.subheadline.weight(segment == seg ? .semibold : .regular))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .foregroundStyle(segment == seg ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        segment == seg ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
                        in: .capsule
                    )
                }
            }
            // Keep the end segments off the surrounding toolbar pill's edges.
            .padding(.horizontal, 4)
        }
        #endif
    }

    // MARK: Links

    @ViewBuilder
    private var linksList: some View {
        if bookmarks.isEmpty {
            ContentUnavailableView {
                Label("No bookmarks", systemImage: "bookmark")
            } description: {
                Text("Tap the bookmark button while browsing AO3 to save a link here.")
            } actions: {
                Button("Browse AO3") { router.selection = .browse }
            }
        } else {
            List {
                ForEach(bookmarks) { bookmark in
                    Button {
                        if let url = bookmark.url { router.open(url) }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(bookmark.title).font(.headline).lineLimit(2)
                            Text(bookmark.urlString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteBookmarks)
                .appThemedRows()
            }
            .appThemedScroll()
        }
    }

    // MARK: Favorites

    @ViewBuilder
    private var favoritesList: some View {
        if favorites.isEmpty {
            ContentUnavailableView {
                Label("No favorites", systemImage: "star")
            } description: {
                Text("Swipe a work in your Library, or tap the star on its page, to favorite it.")
            } actions: {
                Button("Go to Library") { router.selection = .library }
            }
        } else if favorites.filter(passesPrivacy).isEmpty {
            MatureContentHiddenView()
        } else {
            List {
                ForEach(favorites.filter(passesPrivacy)) { work in
                    SensitiveWorkRow(work: work)
                        .swipeActions(edge: .trailing) {
                            Button {
                                work.isFavorite = false
                                try? context.save()
                            } label: {
                                Label("Unfavorite", systemImage: "star.slash")
                            }
                            .tint(.yellow)
                        }
                }
                .appThemedRows()
            }
            .appThemedScroll()
        }
    }

    // MARK: History

    @ViewBuilder
    private var historyList: some View {
        if history.isEmpty {
            ContentUnavailableView {
                Label("No history", systemImage: "clock.arrow.circlepath")
            } description: {
                Text("Works you finish without saving land here. Their files are freed, but you can re-download and revisit them anytime.")
            }
        } else if history.filter(passesPrivacy).isEmpty {
            MatureContentHiddenView()
        } else {
            List {
                ForEach(history.filter(passesPrivacy)) { work in
                    SensitiveWorkRow(work: work)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                if confirmBeforeDelete { pendingDelete = work } else { removeFromHistory(work) }
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }
                .appThemedRows()
            }
            .appThemedScroll()
        }
    }

    // MARK: Content privacy

    private func passesPrivacy(_ work: SavedWork) -> Bool {
        !gate.isHidden(work, enabled: hideMature, mode: matureMode)
    }

    private var currentSegmentHasAdult: Bool {
        switch segment {
        case .links: false
        case .history: history.contains(where: \.isAdult)
        case .favorites: favorites.contains(where: \.isAdult)
        }
    }

    private func removeFromHistory(_ work: SavedWork) {
        context.delete(work)
        try? context.save()
    }

    private func deleteBookmarks(at offsets: IndexSet) {
        for index in offsets {
            context.delete(bookmarks[index])
        }
        try? context.save()
    }
}
