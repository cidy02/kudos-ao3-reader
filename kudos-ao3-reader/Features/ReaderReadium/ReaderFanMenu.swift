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

/// One of the reader's existing quick actions, retained when the old fan is
/// presented as a native menu.
struct ReaderFanRoundAction: Identifiable {
    let id: String
    let systemImage: String
    let accessibilityLabel: String
    var isEnabled = true
    /// When true, the symbol is filled and uses the app colour.
    var isEmphasized = false
    let action: () -> Void
    /// Optional companion command. Read Aloud uses it for settings.
    var settingsAction: (() -> Void)?

    func withSettingsAction(_ handler: @escaping () -> Void) -> ReaderFanRoundAction {
        var copy = self
        copy.settingsAction = handler
        return copy
    }
}

/// The top-right "more" menu for the reader. Features a MenuTopRow with
/// Find, Comments, Read Aloud, Share, followed by rows for Contents,
/// Bookmarks & Highlights, Themes & Settings, etc.
/// (Spec board 27 and component `Menu top row`).
struct ReaderFanMenu: View {
    let pills: [ReaderFanMenuPill]
    /// The work's AO3 URL, shared via a native `ShareLink`. nil for works with no AO3 origin (imported EPUBs).
    let shareURL: URL?
    let roundActions: [ReaderFanRoundAction]
    /// The app control colour (`ThemeManager.effectiveTint`), kept independent
    /// of the work, fandom, queue, and reader paper colours.
    let accentColor: Color
    /// Set when the button sits in the Duo action group (rail or top bar) at this
    /// size: the group already holds Contents, Themes & Settings, Bookmark and Read
    /// Aloud, so the menu drops them, and the button takes the group's glass.
    var groupButtonSize: CGSize?

    /// Items the Duo action group shows itself (T-562a, Duo boards).
    static let groupItemIDs: Set<String> = ["contents", "settings", "bookmark", "readAloud"]

    /// Resolved menu entries for either the standard menu or the Duo rail/top-bar
    /// menu. Extracted so tests exercise the exact filtering `body` renders.
    struct ResolvedItems {
        let find: ReaderFanMenuPill?
        let comments: ReaderFanMenuPill?
        let readAloud: ReaderFanRoundAction?
        let pillRows: [ReaderFanMenuPill]
        let roundActionRows: [ReaderFanRoundAction]
        let readAloudSettings: (() -> Void)?
        let rebuild: ReaderFanMenuPill?
    }

    static func resolvedItems(
        pills: [ReaderFanMenuPill],
        roundActions: [ReaderFanRoundAction],
        inGroup: Bool
    ) -> ResolvedItems {
        let shown: (String) -> Bool = { !inGroup || !Self.groupItemIDs.contains($0) }
        let readAloudEntry = roundActions.first { $0.id == "readAloud" }
        return ResolvedItems(
            find: pills.first { $0.id == "find" },
            comments: pills.first { $0.id == "comments" },
            readAloud: shown("readAloud") ? readAloudEntry : nil,
            pillRows: pills.filter {
                $0.id != "find" && $0.id != "comments" && $0.id != "rebuild" && shown($0.id)
            },
            roundActionRows: roundActions.filter { $0.id != "readAloud" && shown($0.id) },
            // Shown even while Read Aloud can't start: since T-562b this and the mini
            // player are the reader's only ways to the voice settings (the Themes &
            // Settings form no longer carries them), and a missing voice is exactly
            // when they are needed.
            readAloudSettings: readAloudEntry?.settingsAction,
            rebuild: pills.first { $0.id == "rebuild" }
        )
    }

    var body: some View {
        let resolved = Self.resolvedItems(
            pills: pills, roundActions: roundActions, inGroup: groupButtonSize != nil
        )
        Menu {
            MenuTopRow {
                if let find = resolved.find {
                    Button(action: find.action) {
                        Label("Find", systemImage: find.systemImage)
                    }
                    .disabled(!find.isEnabled)
                    .accessibilityLabel("Find")
                }

                if let comments = resolved.comments {
                    Button(action: comments.action) {
                        Label(comments.title, systemImage: comments.systemImage)
                    }
                    .disabled(!comments.isEnabled)
                }

                if let readAloud = resolved.readAloud {
                    Button(action: readAloud.action) {
                        Label(
                            readAloud.isEmphasized ? "Stop Read Aloud" : "Read Aloud",
                            systemImage: MenuTopRowRules.readAloudSymbol(
                                isActive: readAloud.isEmphasized
                            )
                        )
                    }
                    .disabled(!readAloud.isEnabled)
                    .tint(readAloud.isEmphasized ? accentColor : Color.primary)
                    .accessibilityLabel(readAloud.accessibilityLabel)
                    .accessibilityAddTraits(readAloud.isEmphasized ? [.isSelected] : [])
                }

                if let shareURL {
                    ShareLink(item: shareURL) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }

            ForEach(resolved.pillRows) { pill in
                Button(action: pill.action) {
                    Label(pill.title, systemImage: pill.systemImage)
                }
                .disabled(!pill.isEnabled)
            }

            ForEach(resolved.roundActionRows) { action in
                Button(action: action.action) {
                    Label(rowTitle(for: action), systemImage: action.systemImage)
                }
                .disabled(!action.isEnabled)
                .tint(action.isEmphasized ? accentColor : Color.primary)
                .accessibilityLabel(action.accessibilityLabel)
                .accessibilityAddTraits(action.isEmphasized ? [.isSelected] : [])
            }

            if let settings = resolved.readAloudSettings {
                Button(action: settings) {
                    Label("Read Aloud Settings", systemImage: "gearshape")
                }
            }

            if let rebuild = resolved.rebuild {
                Divider()
                Button(action: rebuild.action) {
                    Label(rebuild.title, systemImage: rebuild.systemImage)
                }
                .disabled(!rebuild.isEnabled)
            }
        } label: {
            Image(systemName: "ellipsis")
                // Match `ReaderDuoActionGroup`'s fixed 18 pt glyphs inside the Duo
                // rail/bar slot so AX5 does not spill past the 48×44 capsule.
                .font(groupButtonSize == nil ? .headline : .system(size: 18, weight: .regular))
                .foregroundStyle(Color.primary)
                .frame(width: groupButtonSize?.width ?? 44, height: groupButtonSize?.height ?? 44)
                .contentShape(groupButtonSize == nil ? AnyShape(Circle()) : AnyShape(Capsule()))
        }
        .buttonStyle(.plain)
        .glassEffect(groupButtonSize == nil ? .regular : .identity, in: Circle())
        .accessibilityLabel("More")
        .accessibilityShowsLargeContentViewer {
            Label("More", systemImage: "ellipsis")
        }
        .tint(Color.primary)
        // The rail's menu opens upward from low on the screen; keep the board's
        // order (top row first) instead of the system's mirrored one.
        .menuOrder(groupButtonSize == nil ? .automatic : .fixed)
    }

    private func rowTitle(for action: ReaderFanRoundAction) -> String {
        switch action.id {
        case "kudos": return ReaderEndCopy.kudosButtonTitle(given: action.isEmphasized)
        case "original": return "Original File"
        case "rotationLock": return "Rotation Lock"
        case "bookmark": return "Bookmark"
        default: return action.accessibilityLabel
        }
    }
}
#endif
