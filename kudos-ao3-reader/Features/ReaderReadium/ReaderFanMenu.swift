#if os(iOS)
import SwiftUI

/// One labelled row in the fanned-out menu (Contents, Bookmarks & Notes, Find,
/// Themes & Settings).
struct ReaderFanMenuPill: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    /// False for capabilities not yet wired up (e.g. Find in Work before its
    /// search integration lands) — shown, but inert and visibly dimmed rather
    /// than silently doing nothing.
    var isEnabled = true
    let action: () -> Void
}

/// One round action button in the fan's bottom row (share, kudos, read aloud,
/// bookmark).
struct ReaderFanRoundAction: Identifiable {
    let id: String
    let systemImage: String
    let tint: Color
    let accessibilityLabel: String
    var isEnabled = true
    /// When true, the capsule is filled with `tint` and the glyph uses a
    /// contrasting colour so on/off is obvious at a glance (rotation lock).
    /// Outline-vs-fill alone is too subtle for some symbols.
    var isEmphasized = false
    let action: () -> Void
    /// Optional long-press. Used by Read Aloud to reach its settings without
    /// first starting playback — the mini-player's waveform is the other way
    /// in, and that only exists once something is already being read.
    var longPressAction: (() -> Void)?

    /// Attach a long press without repeating the whole initialiser at the call
    /// site, which is already long enough to obscure what it configures.
    func withLongPress(_ handler: @escaping () -> Void) -> ReaderFanRoundAction {
        var copy = self
        copy.longPressAction = handler
        return copy
    }
}

/// The top-right "more" menu for the reader. Features a MenuTopRow with
/// Find, Comments, Read Aloud, Share, followed by rows for Contents,
/// Bookmarks & Highlights, Themes & Settings, etc.
/// (Spec board 27 and component `Menu top row`).
struct ReaderFanMenu: View {
    @Binding var isOpen: Bool
    let pills: [ReaderFanMenuPill]
    /// The work's AO3 URL, shared via a native `ShareLink`. nil for works with no AO3 origin (imported EPUBs).
    let shareURL: URL?
    let roundActions: [ReaderFanRoundAction]
    /// The reader theme's own control colour (`ThemeManager.effectiveTint`), so an
    /// active toggle and any system-tinted chrome inside the menu read as the
    /// current theme — Sepia's warm brown rather than the raw AO3 red.
    let accentColor: Color
    let reduceMotion: Bool

    var body: some View {
        Menu {
            MenuTopRow {
                if let find = pills.first(where: { $0.id == "find" }) {
                    Button(action: find.action) {
                        Label(find.title, systemImage: find.systemImage)
                    }
                    .disabled(!find.isEnabled)
                }

                if let comments = pills.first(where: { $0.id == "comments" }) {
                    Button(action: comments.action) {
                        Label(comments.title, systemImage: comments.systemImage)
                    }
                    .disabled(!comments.isEnabled)
                }

                if let readAloud = roundActions.first(where: { $0.id == "readAloud" }) {
                    Button(action: readAloud.action) {
                        Label("Read Aloud", systemImage: MenuTopRowRules.readAloudSymbol(isActive: readAloud.isEmphasized))
                    }
                    .disabled(!readAloud.isEnabled)
                }

                if let shareURL {
                    ShareLink(item: shareURL) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }

            ForEach(pills.filter { $0.id != "find" && $0.id != "comments" }) { pill in
                Button(action: pill.action) {
                    Label(pill.title, systemImage: pill.systemImage)
                }
                .disabled(!pill.isEnabled)
            }

            ForEach(roundActions.filter { $0.id != "readAloud" }) { action in
                Button(action: action.action) {
                    Label(action.accessibilityLabel.isEmpty ? action.id : action.accessibilityLabel, systemImage: action.systemImage)
                }
                .disabled(!action.isEnabled)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: Circle())
        .accessibilityLabel("More actions")
        .tint(accentColor)
    }
}

extension ReaderFanMenu {
    /// Reader menus don't dim the page (TASKS.md, Board 27). Native Menu handles dismissal on tap-outside.
    @ViewBuilder
    static func dismissBackdrop(isOpen: Binding<Bool>, reduceMotion: Bool) -> some View {
        EmptyView()
    }
}
#endif
