import SwiftUI

/// The Subscriptions "Following" list: the works you follow on AO3, grouped by whether
/// they can still notify you. Renders what it is handed; the caller owns fetching.
struct FollowingListView: View {
    enum Scope: Equatable {
        case following
        case tidyUp
    }

    let works: [AO3WorkSummary]
    /// Works AO3 no longer serves; the subscriptions page cannot say, so the caller does.
    var deletedIDs: Set<Int> = []
    var scope: Scope = .following
    var sourceNote: String?
    /// The parent owns this. A tab switch rebuilds this view, and a local set would bring the row back.
    @Binding var unfollowed: Set<Int>
    /// Series and author rows from the subscriptions index. Empty leaves the works
    /// list exactly as it was: those sections are omitted, not shown as a zero.
    var series: [AO3FollowedSeries] = []
    var authors: [AO3FollowedAuthor] = []
    var seriesHasMore = false
    var authorsHasMore = false
    var isLoadingMoreSeries = false
    var isLoadingMoreAuthors = false
    /// When true, a loaded Following screen still shows a Series or Authors
    /// header if that list is empty and the other groups are not. Default false
    /// keeps a works-only caller unchanged.
    var showsEmptyFollowGroups = false
    var onLoadMoreSeries: (() -> Void)?
    var onLoadMoreAuthors: (() -> Void)?

    @Environment(AO3AuthService.self) private var auth
    @State private var sort = Sort.title
    @State private var pendingUnfollow: AO3WorkSummary?
    @State private var confirmingUnfollow = false
    @State private var unfollowingID: Int?
    @State private var resultMessage = ""
    @State private var showingResult = false

    private enum Sort: String, CaseIterable, Identifiable {
        case title = "Title"
        case author = "Author"

        var id: String { rawValue }

        func areInOrder(_ lhs: AO3WorkSummary, _ rhs: AO3WorkSummary) -> Bool {
            switch self {
            case .title:
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            case .author:
                let order = lhs.authorText.localizedStandardCompare(rhs.authorText)
                return order == .orderedSame
                    ? lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                    : order == .orderedAscending
            }
        }
    }

    private var visible: [AO3WorkSummary] {
        works.filter { !unfollowed.contains($0.id) }.sorted(by: sort.areInOrder)
    }

    private func isDeleted(_ work: AO3WorkSummary) -> Bool { deletedIDs.contains(work.id) }

    private func isFinished(_ work: AO3WorkSummary) -> Bool { work.isComplete == true && !isDeleted(work) }

    private var stillGoing: [AO3WorkSummary] {
        // nil is deliberately optimistic: the subscriptions page supplies no completion bit, so unknown stays in Still going until a source provides a real one.
        visible.filter { $0.isComplete != true && !isDeleted($0) }
    }

    private var cannotNotify: [AO3WorkSummary] {
        visible.filter { isFinished($0) || isDeleted($0) }
    }

    private var hasVisibleRows: Bool {
        scope == .following ? !visible.isEmpty : !cannotNotify.isEmpty
    }

    /// A zero group is worth showing when something else followed is on screen.
    /// All three empty uses the overlay instead of three "None." headers.
    /// No work rows, but series or authors are on screen: say so, instead of
    /// leaving the works group invisible.
    private var showEmptyWorksGroup: Bool {
        guard scope == .following, showsEmptyFollowGroups, visible.isEmpty else { return false }
        return !series.isEmpty || !authors.isEmpty
    }

    private var showSeriesGroup: Bool {
        guard scope == .following else { return false }
        if !series.isEmpty || seriesHasMore { return true }
        guard showsEmptyFollowGroups else { return false }
        return !visible.isEmpty || !authors.isEmpty
    }

    private var showAuthorsGroup: Bool {
        guard scope == .following else { return false }
        if !authors.isEmpty || authorsHasMore { return true }
        guard showsEmptyFollowGroups else { return false }
        return !visible.isEmpty || !series.isEmpty
    }

    /// Keeps the spec's sentence shape; a clause with a zero count is left out entirely.
    private var cannotNotifySentence: String {
        let finished = cannotNotify.filter(isFinished).count
        let deleted = cannotNotify.filter(isDeleted).count
        var clauses: [String] = []
        if finished > 0 { clauses.append("\(finished) \(finished == 1 ? "work" : "works") reached 100% complete") }
        if deleted > 0 { clauses.append("\(deleted) \(deleted == 1 ? "was" : "were") deleted from AO3") }
        // "None of them" reads wrong for a lone work.
        let tail = finished + deleted == 1 ? "It can't notify you again." : "None of them can notify you again."
        return clauses.joined(separator: " and ") + ". " + tail
    }

    var body: some View {
        List {
            // Group so .appThemedRows() reaches every section's rows — it doesn't
            // propagate from the List container, only from a Group/Section/ForEach.
            Group {
                if let sourceNote {
                    Section {
                        Text(sourceNote)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if scope == .following, !stillGoing.isEmpty {
                    Section {
                        ForEach(stillGoing) { work in row(for: work) }
                    } header: {
                        FollowingGroupHeader(title: "Still going", count: stillGoing.count)
                    }
                }

                if !cannotNotify.isEmpty {
                    Section {
                        Text(cannotNotifySentence)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 6)
                            .listRowSeparator(.hidden)
                        ForEach(cannotNotify) { work in row(for: work) }
                    } header: {
                        FollowingGroupHeader(title: "Finished or gone", count: cannotNotify.count)
                    }
                }

                if showEmptyWorksGroup {
                    Section {
                        Text("None.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } header: {
                        FollowingGroupHeader(title: "Works", count: 0)
                    }
                }

                if showSeriesGroup {
                    Section {
                        if series.isEmpty {
                            Text("None.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(series) { item in seriesRow(item) }
                        if seriesHasMore {
                            loadMoreButton(
                                "Load more series",
                                isLoading: isLoadingMoreSeries,
                                action: onLoadMoreSeries
                            )
                        }
                    } header: {
                        FollowingGroupHeader(title: "Series", count: series.count)
                    }
                }

                if showAuthorsGroup {
                    Section {
                        if authors.isEmpty {
                            Text("None.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(authors) { item in authorRow(item) }
                        if authorsHasMore {
                            loadMoreButton(
                                "Load more authors",
                                isLoading: isLoadingMoreAuthors,
                                action: onLoadMoreAuthors
                            )
                        }
                    } header: {
                        FollowingGroupHeader(title: "Authors", count: authors.count)
                    }
                }
            }
            .appThemedRows()
        }
        .listStyle(.plain)
        .appThemedScroll()
        .overlay {
            if scope == .tidyUp, cannotNotify.isEmpty {
                ContentUnavailableView(
                    visible.isEmpty ? "Nothing to tidy up" : "Status unavailable",
                    systemImage: visible.isEmpty ? "checkmark.circle" : "questionmark.circle",
                    description: Text(
                        visible.isEmpty
                            ? "There are no followed works on this AO3 page."
                            : "AO3's subscriptions page doesn't include completion or deletion status, "
                                + "so no works can be identified for cleanup yet."
                    )
                )
            } else if visible.isEmpty && series.isEmpty && authors.isEmpty {
                ContentUnavailableView(
                    "Nothing followed",
                    systemImage: "bell",
                    description: Text(
                        "Works, series, and authors you subscribe to on AO3 show up here."
                    )
                )
            }
        }
        .navigationTitle(scope == .following ? "You follow" : "Tidy up")
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                if hasVisibleRows {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Picker("Sort", selection: $sort) {
                                ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                            }
                        } label: {
                            Label("Sort", systemImage: "arrow.up.arrow.down")
                        }
                    }
                }
            }
            .confirmationDialog(
                "Unfollow \(pendingUnfollow?.title ?? "this work")?",
                isPresented: $confirmingUnfollow,
                titleVisibility: .visible
            ) {
                Button("Unfollow", role: .destructive) {
                    if let work = pendingUnfollow { Task { await unfollow(work) } }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This unsubscribes you from the work on AO3.")
            }
            .alert("AO3", isPresented: $showingResult) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(resultMessage)
            }
    }

    /// Series and authors have no Unfollow. `unsubscribe(workID:)` loads `/works/<id>`
    /// and posts that page's delete form. Series and user pages share the form
    /// partial, but this function has no type argument, so calling it would hit
    /// the wrong page. The index has its own delete form; using it would be a new write.
    @ViewBuilder
    private func seriesRow(_ item: AO3FollowedSeries) -> some View {
        let row = FollowedNameRow(
            title: item.title,
            subtitle: item.creatorNames.isEmpty ? nil : item.creatorNames.joined(separator: ", ")
        )
        if let summary = item.navigationSummary {
            row.cardNavigation(to: summary, accessibilityLabel: item.title)
                .accessibilityHint("Opens this series")
        } else {
            row
        }
    }

    @ViewBuilder
    private func authorRow(_ item: AO3FollowedAuthor) -> some View {
        let row = FollowedNameRow(title: item.name, subtitle: nil)
        if let route = item.route {
            row.cardNavigation(to: route, accessibilityLabel: item.name)
                .accessibilityHint("Opens this author's profile")
        } else {
            row
        }
    }

    private func loadMoreButton(
        _ title: String,
        isLoading: Bool,
        action: (() -> Void)?
    ) -> some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 6) {
                if isLoading { ProgressView().controlSize(.small) }
                Text(isLoading ? "Loading…" : title)
            }
            .frame(minHeight: 44)
        }
        .disabled(isLoading || action == nil)
    }

    private func row(for work: AO3WorkSummary) -> some View {
        FollowingRow(
            work: work,
            badge: isDeleted(work) ? "Deleted" : (isFinished(work) ? "Complete" : nil),
            // shortcut: a deleted work cannot be unfollowed here, because the unsubscribe
            // path is read from the work's own page and AO3 no longer serves it; add an
            // unsubscribe driven by the subscriptions page itself once one exists
            canUnfollow: !isDeleted(work),
            isUnfollowing: unfollowingID == work.id,
            isBusy: unfollowingID != nil
        ) {
            pendingUnfollow = work
            confirmingUnfollow = true
        }
    }

    private func unfollow(_ work: AO3WorkSummary) async {
        unfollowingID = work.id
        defer { unfollowingID = nil }
        do {
            // `unsubscribe`, not `toggleSubscribe`: the toggle subscribes when the
            // work page shows no subscription, so a stale row would re-follow on a
            // tap labelled Unfollow. This one can only ever remove.
            let message = try await auth.unsubscribe(workID: work.id)
            // Either outcome leaves the user not following, so the row goes in both
            // cases; only the already-gone case is worth a word.
            unfollowed.insert(work.id)
            if message != "Unsubscribed." {
                resultMessage = message
                showingResult = true
            }
        } catch {
            resultMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            showingResult = true
        }
    }
}

private struct FollowedNameRow: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FollowingGroupHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text("\(count)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
        }
        .textCase(nil)
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(count)")
    }
}

private struct FollowingRow: View {
    let work: AO3WorkSummary
    let badge: String?
    let canUnfollow: Bool
    let isUnfollowing: Bool
    let isBusy: Bool
    let onUnfollow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(work.title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(spacing: 12, rowSpacing: 4) {
                if let badge {
                    Text(badge)
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                        .fixedSize()
                }
                if !work.authors.isEmpty {
                    // Truncating: a pseud is free text, unlike the bounded stats below.
                    WorkStatLabel(text: work.authorText, symbol: "person", truncates: true)
                }
                if !work.chapters.isEmpty { WorkStatLabel(text: work.chapters, symbol: "book") }
                if let words = work.words { WorkStatLabel(text: words.formatted(), symbol: "textformat.size") }
                if !work.dateUpdated.isEmpty { WorkStatLabel(text: work.dateUpdated, symbol: "calendar") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button(action: onUnfollow) {
                HStack(spacing: 5) {
                    if isUnfollowing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "bell.slash")
                    }
                    Text("Unfollow")
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .foregroundStyle(.accentInk)
            .disabled(!canUnfollow || isBusy)
            .accessibilityLabel("Unfollow \(work.title)")
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    func work(
        _ id: Int, _ title: String, _ author: String, complete: Bool? = nil, chapters: String = ""
    ) -> AO3WorkSummary {
        var summary = AO3WorkSummary.subscription(id: id, title: title, authors: [author])
        summary.isComplete = complete
        summary.chapters = chapters
        return summary
    }

    let going = [
        work(1, "The Lantern Keeper", "saltwindow", complete: false, chapters: "9/?"),
        work(2, "A Quiet Harbour", "marrowlight")
    ]
    let finished = [
        work(3, "Salt and Ember", "quietfern", complete: true, chapters: "24/24"),
        work(4, "Paper Boats", "a pseud long enough to need truncating at the ideal width", complete: true),
        work(5, "Winter Court", "wrenfield", complete: true),
        work(6, "Low Tide", "marrowlight", complete: true)
    ]
    let deleted = work(7, "Gone Dark", "someone")
    let series = [
        AO3FollowedSeries(
            subscriptionID: 11,
            title: "The Lantern Cycle",
            creatorNames: ["saltwindow"],
            creatorIdentities: [],
            seriesID: 50,
            url: URL(string: "https://archiveofourown.org/series/50")
        )
    ]
    let authors = [
        AO3FollowedAuthor(
            subscriptionID: 12,
            name: "marrowlight",
            route: AO3AuthorRoute(username: "marrowlight")
        )
    ]

    return TabView {
        NavigationStack {
            FollowingListView(
                works: going + finished + [deleted],
                deletedIDs: [7],
                unfollowed: .constant([]),
                series: series,
                authors: authors
            )
        }
        .tabItem { Text("Both groups") }
        NavigationStack { FollowingListView(works: going, unfollowed: .constant([])) }
            .tabItem { Text("Still going") }
        NavigationStack { FollowingListView(works: [], unfollowed: .constant([])) }
            .tabItem { Text("Empty") }
    }
    .environment(ThemeManager())
    .environment(AppRouter())
}
