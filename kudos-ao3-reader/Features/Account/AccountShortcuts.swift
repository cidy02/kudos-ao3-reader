import SwiftUI

/// One tile in the Account page's Shortcuts grid.
///
/// A named set rather than a hardcoded grid, because the grid is the reader's to
/// arrange: with the hub flattened into a single sectioned list, every shortcut
/// duplicates a row further down the same page, and which duplicates are worth
/// having at the top is a matter of what that person actually opens.
nonisolated enum AccountShortcut: String, CaseIterable, Identifiable, Sendable {
    case dashboard
    case markedForLater
    case bookmarks
    case collections
    case subscriptions
    case works
    case series
    case drafts
    case history
    case inbox
    case preferences
    case moreOnAO3

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .markedForLater: "Marked for Later"
        case .bookmarks: "Bookmarks"
        case .collections: "Collections"
        case .subscriptions: "Subscriptions"
        case .works: "Works"
        case .series: "Series"
        case .drafts: "Drafts"
        case .history: "History"
        case .inbox: "Inbox"
        case .preferences: "Preferences"
        case .moreOnAO3: "More on AO3"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .markedForLater: "clock.badge"
        case .bookmarks: "bookmark"
        case .collections: "square.stack"
        case .subscriptions: "bell"
        case .works: "doc.text"
        case .series: "square.stack.3d.up"
        case .drafts: "doc.badge.clock"
        case .history: "clock"
        case .inbox: "tray"
        case .preferences: "slider.horizontal.3"
        case .moreOnAO3: "ellipsis.circle"
        }
    }

    /// The cached list size to print on the tile, where one exists. Dashboard,
    /// Drafts, Inbox, Preferences and More on AO3 have no cached count — and
    /// none is invented for them.
    var countKind: AO3AccountListKind? {
        switch self {
        case .markedForLater: .markedForLater
        case .bookmarks: .bookmarks
        case .collections: .collections
        case .subscriptions: .subscriptions
        case .works: .myWorks
        case .series: .series
        case .history: .history
        case .dashboard, .drafts, .inbox, .preferences, .moreOnAO3: nil
        }
    }

    /// What the grid starts as: the six the hub drew before it was editable.
    static let defaults: [AccountShortcut] = [
        .dashboard, .subscriptions, .works, .bookmarks, .collections, .history
    ]
}

/// The reader's chosen shortcuts, persisted as an ordered list of raw values.
///
/// Stored as one string rather than a collection so it can live in `@AppStorage`
/// without a transformer. An unknown raw value is dropped on read, so removing a
/// case in future degrades to a shorter grid instead of a crash.
@MainActor
enum AccountShortcutStore {
    static let key = "account.shortcuts"

    static func decode(_ raw: String) -> [AccountShortcut] {
        guard !raw.isEmpty else { return AccountShortcut.defaults }
        let chosen = raw.split(separator: ",").compactMap { AccountShortcut(rawValue: String($0)) }
        // An empty result means every stored name is now unknown; the defaults
        // are a better answer than an empty grid the reader cannot refill.
        return chosen.isEmpty ? AccountShortcut.defaults : chosen
    }

    static func encode(_ shortcuts: [AccountShortcut]) -> String {
        shortcuts.map(\.rawValue).joined(separator: ",")
    }
}

/// Add and remove shortcuts, and reorder what is kept.
struct AccountShortcutsEditor: View {
    @Binding var raw: String
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme

    private var chosen: [AccountShortcut] { AccountShortcutStore.decode(raw) }
    private var available: [AccountShortcut] {
        AccountShortcut.allCases.filter { !chosen.contains($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(chosen) { shortcut in
                        row(shortcut, isChosen: true)
                    }
                    .onMove { indices, destination in
                        var next = chosen
                        next.move(fromOffsets: indices, toOffset: destination)
                        raw = AccountShortcutStore.encode(next)
                    }
                } header: {
                    Text("On the grid")
                } footer: {
                    if chosen.isEmpty {
                        Text("With none chosen the grid is hidden, and every destination is "
                            + "still in the sections below it.")
                    }
                }

                if !available.isEmpty {
                    Section("Not on the grid") {
                        ForEach(available) { shortcut in
                            row(shortcut, isChosen: false)
                        }
                    }
                }

                Section {
                    Button("Reset to Default") {
                        raw = AccountShortcutStore.encode(AccountShortcut.defaults)
                    }
                    .disabled(chosen == AccountShortcut.defaults)
                }
            }
            .appThemedRows()
            .appThemedScroll()
            .navigationTitle("Shortcuts")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .environment(\.editMode, .constant(.active))
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }

    private func row(_ shortcut: AccountShortcut, isChosen: Bool) -> some View {
        Button {
            var next = chosen
            if isChosen {
                next.removeAll { $0 == shortcut }
            } else {
                next.append(shortcut)
            }
            raw = AccountShortcutStore.encode(next)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isChosen ? "minus.circle.fill" : "plus.circle.fill")
                    .foregroundStyle(isChosen ? Color.red : Color.green)
                Label(shortcut.title, systemImage: shortcut.systemImage)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isChosen ? "Remove \(shortcut.title)" : "Add \(shortcut.title)")
    }
}
