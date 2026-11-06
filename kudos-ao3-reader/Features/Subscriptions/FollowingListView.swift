import SwiftUI

/// The Subscriptions "Following" list: the works you follow on AO3, grouped by whether
/// they can still notify you. Renders what it is handed; the caller owns fetching.
struct FollowingListView: View {
    let works: [AO3WorkSummary]
    /// Works AO3 no longer serves; the subscriptions page cannot say, so the caller does.
    var deletedIDs: Set<Int> = []

    @Environment(AO3AuthService.self) private var auth
    @State private var sort = Sort.title
    @State private var unfollowed = Set<Int>()
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

    // An unknown completion state (nil) still counts as going: only a known finish stops notifications.
    private func isFinished(_ work: AO3WorkSummary) -> Bool { work.isComplete == true && !isDeleted(work) }

    private var stillGoing: [AO3WorkSummary] {
        visible.filter { !isFinished($0) && !isDeleted($0) }
    }

    private var cannotNotify: [AO3WorkSummary] {
        visible.filter { isFinished($0) || isDeleted($0) }
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
                if !stillGoing.isEmpty {
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
            }
            .appThemedRows()
        }
        .listStyle(.plain)
        .appThemedScroll()
        .overlay {
            if visible.isEmpty {
                ContentUnavailableView(
                    "No works followed",
                    systemImage: "bell",
                    description: Text("Works you subscribe to on AO3 show up here.")
                )
            }
        }
        .navigationTitle("Works you follow")
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                if !visible.isEmpty {
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

    return TabView {
        NavigationStack { FollowingListView(works: going + finished + [deleted], deletedIDs: [7]) }
            .tabItem { Text("Both groups") }
        NavigationStack { FollowingListView(works: going) }
            .tabItem { Text("Still going") }
        NavigationStack { FollowingListView(works: []) }
            .tabItem { Text("Empty") }
    }
    .environment(ThemeManager())
}
