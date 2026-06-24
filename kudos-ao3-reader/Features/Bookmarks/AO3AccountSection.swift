import SwiftUI

/// The "AO3" segment of the Bookmarks tab: groups the login-gated account lists
/// (Marked for Later, Bookmarks, History) under one sub-picker so the tab's section
/// switcher doesn't overflow. Each list is an `AO3AccountWorksList`; switching tabs
/// remounts it (`.id`) so the newly selected list loads fresh.
struct AO3AccountSection: View {
    @Environment(AO3AuthService.self) private var auth
    @State private var tab: Tab = .markedForLater
    @State private var showLogin = false

    enum Tab: String, CaseIterable, Identifiable {
        case markedForLater = "Later"
        case bookmarks = "Bookmarks"
        case history = "History"
        case subscriptions = "Subs"
        var id: String { rawValue }
    }

    var body: some View {
        if auth.isLoggedIn {
            VStack(spacing: 0) {
                Picker("AO3 list", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                content(for: tab).id(tab)
            }
        } else {
            ContentUnavailableView {
                Label("AO3 Account", systemImage: "person.crop.circle")
            } description: {
                Text("Log in to AO3 to see your reading list, bookmarks, and history.")
            } actions: {
                Button("Log In to AO3") { showLogin = true }
            }
            .sheet(isPresented: $showLogin) { AO3LoginView() }
        }
    }

    @ViewBuilder
    private func content(for tab: Tab) -> some View {
        switch tab {
        case .markedForLater: AO3AccountWorksList(kind: .markedForLater)
        case .bookmarks: AO3AccountWorksList(kind: .bookmarks)
        case .history: AO3AccountWorksList(kind: .history)
        case .subscriptions: AO3AccountWorksList(kind: .subscriptions)
        }
    }
}
