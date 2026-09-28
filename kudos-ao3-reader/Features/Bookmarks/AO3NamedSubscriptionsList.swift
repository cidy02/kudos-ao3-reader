import SwiftUI

/// 1p.4's Works / Series / Authors pills. The same pill row Marked for Later
/// uses, without a Reset: a scope is not a filter.
struct AO3SubscriptionsScopeRail: View {
    @Binding var selection: AO3SubscriptionsScope
    let palette: SubjectPalette

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AO3SubscriptionsScope.allCases) { option in
                    Button {
                        selection = option
                    } label: {
                        SubjectChip(
                            text: option.title,
                            style: .pill(isSelected: selection == option),
                            palette: palette
                        )
                    }
                    .buttonStyle(.plain)
                    .minimumHitTarget(28)
                    .accessibilityAddTraits(selection == option ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

enum AO3NamedSubscriptionsCopy {
    /// "3 series · page 1 of 2". AO3 prints no total, so this is the page.
    static func subtitle(scope: AO3SubscriptionsScope, count: Int, currentPage: Int, totalPages: Int) -> String {
        var line = switch scope {
        case .series: "\(count) series"
        case .users: count == 1 ? "1 author" : "\(count) authors"
        case .works: count == 1 ? "1 work" : "\(count) works"
        }
        if totalPages > 1 { line += " · page \(currentPage) of \(totalPages)" }
        return line
    }

    static func empty(_ scope: AO3SubscriptionsScope) -> (title: String, message: String) {
        switch scope {
        case .series: ("No series subscriptions", "Series you subscribe to on AO3 show up here.")
        case .users: ("No author subscriptions", "Authors you subscribe to on AO3 show up here.")
        case .works: ("No work subscriptions", "Works you subscribe to on AO3 show up here.")
        }
    }
}

/// Series and Authors: one `type=` page of name rows, with the same swipe
/// unsubscribe the Works rows have. A row opens the series or the author.
struct AO3NamedSubscriptionsList: View {
    @Binding var scope: AO3SubscriptionsScope
    let palette: SubjectPalette
    let kicker: String

    @Environment(AO3AuthService.self) private var auth
    @State private var page = 1
    @State private var loaded: AO3NamedSubscriptionsPage?
    @State private var loadError: String?
    @State private var pendingUnsubscribe: AO3NamedSubscription?
    @State private var writeError: String?
    @State private var writeInFlight = false

    /// A new scope, page or session is a new fetch. Rows from the old one
    /// are dropped first, so account A's series never sit under B's header.
    private struct LoadKey: Hashable {
        let scope: AO3SubscriptionsScope
        let page: Int
        let generation: Int
    }

    var body: some View {
        List {
            Section {
                SubjectHeaderBlock(
                    kicker: kicker,
                    title: "Subscriptions",
                    subtitle: loaded.map {
                        AO3NamedSubscriptionsCopy.subtitle(
                            scope: scope, count: $0.rows.count,
                            currentPage: $0.currentPage, totalPages: $0.totalPages
                        )
                    } ?? "",
                    palette: palette,
                    gutter: SubjectMetrics.accountGutter
                )
                .listRowInsets(EdgeInsets(top: 20, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                AO3SubscriptionsScopeRail(selection: $scope, palette: palette)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            content
        }
        .cardList()
        .subjectScreenWash(palette: palette)
        .onChange(of: scope) { page = 1 }
        .task(id: LoadKey(scope: scope, page: page, generation: auth.sessionGeneration)) {
            await load()
        }
        .destructiveConfirmation(
            for: $pendingUnsubscribe,
            title: "Unsubscribe?",
            confirmLabel: "Unsubscribe",
            message: { row in
                "“\(row.name)” will be removed from your AO3 subscriptions. "
                    + "You'll stop getting its update emails."
            },
            perform: { row in Task { await unsubscribe(row) } }
        )
        .alert(
            "Couldn't unsubscribe",
            isPresented: Binding(get: { writeError != nil }, set: { if !$0 { writeError = nil } })
        ) {
            Button("OK", role: .cancel) { writeError = nil }
        } message: {
            Text(writeError ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let loaded {
            if loaded.totalPages > 1 { Section { paginationBar(loaded) } }
            if loaded.rows.isEmpty {
                let copy = AO3NamedSubscriptionsCopy.empty(scope)
                Section {
                    ContentUnavailableView(copy.title, systemImage: "bell", description: Text(copy.message))
                        .bareListRow()
                }
            } else {
                Section {
                    ForEach(loaded.rows) { row in
                        rowLink(row)
                    }
                }
            }
            if loaded.totalPages > 1 { Section { paginationBar(loaded) } }
        } else if let loadError {
            Section {
                ContentUnavailableView {
                    Label("Couldn't load your list", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
                .bareListRow()
            }
        } else {
            Section { ProgressView().frame(maxWidth: .infinity).bareListRow() }
        }
    }

    private func paginationBar(_ loaded: AO3NamedSubscriptionsPage) -> some View {
        SearchPaginationBar(
            currentPage: loaded.currentPage,
            totalPages: loaded.totalPages,
            isLoading: false
        ) { page = $0 }
        .bareListRow()
    }

    @ViewBuilder
    private func rowLink(_ row: AO3NamedSubscription) -> some View {
        Group {
            if let series = row.seriesSummary {
                NavigationLink(value: series) { rowLabel(row) }
            } else if let route = row.authorRoute {
                NavigationLink(value: route) { rowLabel(row) }
            } else {
                rowLabel(row)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if row.unsubscribePath != nil {
                Button(role: .destructive) {
                    pendingUnsubscribe = row
                } label: {
                    Label("Unsubscribe", systemImage: "bell.slash")
                }
            }
        }
        .cardRow()
    }

    private func rowLabel(_ row: AO3NamedSubscription) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(row.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
            if !row.creators.isEmpty {
                Text("by " + row.creators.map(\.displayName).joined(separator: ", "))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        let requested = LoadKey(scope: scope, page: page, generation: auth.sessionGeneration)
        loaded = nil
        loadError = nil
        do {
            let result = try await auth.accountNamedSubscriptions(scope: requested.scope, page: requested.page)
            guard !Task.isCancelled, requested == currentKey else { return }
            loaded = result ?? AO3NamedSubscriptionsPage(rows: [], currentPage: 1, totalPages: 1)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, requested == currentKey else { return }
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private var currentKey: LoadKey {
        LoadKey(scope: scope, page: page, generation: auth.sessionGeneration)
    }

    private func unsubscribe(_ row: AO3NamedSubscription) async {
        guard !writeInFlight, let path = row.unsubscribePath else { return }
        let generation = auth.sessionGeneration
        writeInFlight = true
        defer { writeInFlight = false }
        do {
            _ = try await auth.unsubscribe(path: path, page: page)
            guard auth.sessionGeneration == generation else { return }
            loaded?.rows.removeAll { $0.id == row.id }
        } catch is CancellationError {
            // The session changed between the form GET and the POST. Nothing landed.
        } catch {
            guard auth.sessionGeneration == generation else { return }
            writeError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
