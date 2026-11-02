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

    var body: some View {
        Menu {
            MenuTopRow {
                if let find = pills.first(where: { $0.id == "find" }) {
                    Button(action: find.action) {
                        Label("Find", systemImage: find.systemImage)
                    }
                    .disabled(!find.isEnabled)
                    .accessibilityLabel(find.title)
                }

                if let comments = pills.first(where: { $0.id == "comments" }) {
                    Button(action: comments.action) {
                        Label(comments.title, systemImage: comments.systemImage)
                    }
                    .disabled(!comments.isEnabled)
                }

                if let readAloud = roundActions.first(where: { $0.id == "readAloud" }) {
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

            ForEach(pills.filter {
                $0.id != "find" && $0.id != "comments" && $0.id != "rebuild"
            }) { pill in
                Button(action: pill.action) {
                    Label(pill.title, systemImage: pill.systemImage)
                }
                .disabled(!pill.isEnabled)
            }

            ForEach(roundActions.filter { $0.id != "readAloud" }) { action in
                Button(action: action.action) {
                    Label(rowTitle(for: action), systemImage: action.systemImage)
                }
                .disabled(!action.isEnabled)
                .tint(action.isEmphasized ? accentColor : Color.primary)
                .accessibilityLabel(action.accessibilityLabel)
                .accessibilityAddTraits(action.isEmphasized ? [.isSelected] : [])
            }

            if let readAloud = roundActions.first(where: { $0.id == "readAloud" }),
               readAloud.isEnabled,
               let settings = readAloud.settingsAction {
                Button(action: settings) {
                    Label("Read Aloud Settings", systemImage: "gearshape")
                }
            }

            if let rebuild = pills.first(where: { $0.id == "rebuild" }) {
                Divider()
                Button(action: rebuild.action) {
                    Label(rebuild.title, systemImage: rebuild.systemImage)
                }
                .disabled(!rebuild.isEnabled)
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
        .tint(Color.primary)
    }

    private func rowTitle(for action: ReaderFanRoundAction) -> String {
        switch action.id {
        case "kudos": return "Kudos"
        case "original": return "Original File"
        case "rotationLock": return "Rotation Lock"
        case "bookmark": return "Bookmark"
        default: return action.accessibilityLabel
        }
    }
}
#endif
