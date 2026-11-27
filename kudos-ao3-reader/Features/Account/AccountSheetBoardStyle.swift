import SwiftUI

/// Pure copy and formatting rules for the Account sheet (`Account-Sheet.dc.html`),
/// kept out of view bodies so tests pin the board's exact words.
enum AccountSheetCopy {
    static let signedOutTitle = "Not logged in"
    static let signedOutLoginTitle = "Log In to AO3"
    static let signedOutLoggingInTitle = "Logging In…"
    static let onAO3SectionTitle = "On AO3"
    static let kudosSectionTitle = "Kudos"
    static let openAO3Title = "Open AO3 in Kudos"
    static let aboutKudosTitle = "About Kudos"
    static let editProfileAccessibilityLabel = "Edit your profile on AO3"
    static let accountCountsAccessibilityLabel = "Your AO3 account"

    static func signedOutSubtitle(deviceName: String) -> String {
        "Your library and reading stay on this \(deviceName) either way."
    }

    static func sessionFootnote(deviceName: String) -> String {
        "Logged in to archiveofourown.org. Kudos keeps the session on this \(deviceName) only."
    }

    static func inboxHeaderAccessibilityLabel(unreadCount: Int?) -> String {
        guard let unreadCount, unreadCount > 0 else { return "Inbox" }
        return "Inbox, \(unreadCount.formatted()) unread"
    }

    static func inboxUnreadAccessibilityValue(_ unreadCount: Int?) -> String? {
        guard let unreadCount, unreadCount > 0 else { return nil }
        return "\(unreadCount.formatted()) unread"
    }

    /// Trailing detail for the Account sheet's Backup & Sync row. Manual backup
    /// exports store no timestamp, so this reflects Folder Sync's live snapshot
    /// and stays nil when no folder is connected.
    static func backupSyncDetail(
        _ sync: FolderSyncSnapshot,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> String? {
        guard sync.isConnected else { return nil }
        if !sync.lastError.isEmpty { return "Error" }
        if let date = sync.lastSyncAt {
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            if sameYear {
                let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                    .month(.abbreviated)
                    .day()
                return date.formatted(style)
            }
            return WorkStat.displayDate(date, locale: locale, timeZone: calendar.timeZone)
        }
        return sync.autoSyncEnabled ? "On" : "Paused"
    }
}

/// Elevated grouped card surface for the Account sheet (`Account-Sheet.dc.html`),
/// lifting off `cardBackdrop` (`#F2F2F7` in Light) across Light, Dark, OLED and Sepia.
private struct AccountSheetPanelModifier: ViewModifier {
    var cornerRadius: CGFloat = SubjectMetrics.cornerRadius

    @Environment(ThemeManager.self) private var theme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(shape.fill(theme.appTheme.cardSurface))
            .clipShape(shape)
            .overlay(shape.strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5))
    }
}

extension View {
    func accountSheetPanel(cornerRadius: CGFloat = SubjectMetrics.cornerRadius) -> some View {
        modifier(AccountSheetPanelModifier(cornerRadius: cornerRadius))
    }
}

/// Grouped section heading on the Account sheet (`Account-Sheet.dc.html`: 15 pt semibold,
/// inset 16 pt from the card's leading edge).
struct AccountSheetGroupHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondaryInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SubjectMetrics.accountGutter + 16)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One grouped row on the Account sheet (`Account-Sheet.dc.html`): 29 pt coloured
/// icon tile, 17 pt label, optional unread pill badge or trailing detail, and chevron.
struct AccountSheetRow: View {
    /// Leading inset to align row hairlines under the title (`16` padding + `29` tile + `12` gap).
    static let separatorInset: CGFloat = 57

    let title: String
    let systemImage: String
    let tileColor: Color
    var titleWeight: Font.Weight = .regular
    var detail: String?
    var badge: String?
    var badgeAccessibilityText: String?
    var showsChevron: Bool = true

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accentFill) private var accentFill

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                standardLayout
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValueText)
    }

    private var standardLayout: some View {
        HStack(spacing: 12) {
            SettingsIconTile(color: tileColor, systemImage: systemImage)
            Text(title)
                .font(.body.weight(titleWeight))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            trailingContent
        }
    }

    private var accessibilityLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            SettingsIconTile(color: tileColor, systemImage: systemImage)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(titleWeight))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let badge {
                    badgePill(badge)
                }
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron {
                chevron
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private var trailingContent: some View {
        if let badge {
            badgePill(badge)
        }
        if let detail, !detail.isEmpty {
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondaryInk)
                .lineLimit(1)
        }
        if showsChevron {
            chevron
        }
    }

    private func badgePill(_ text: String) -> some View {
        Text(text)
            .font(.footnote.monospacedDigit().weight(.bold))
            .foregroundStyle(ThemeManager.label(on: accentFill))
            .padding(.horizontal, 7)
            .frame(minWidth: 22, minHeight: 22)
            .background(accentFill, in: Capsule())
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    private var accessibilityValueText: String {
        let parts: [String?] = [
            badgeAccessibilityText ?? badge,
            detail?.isEmpty == false ? detail : nil
        ]
        return parts.compactMap { $0 }.joined(separator: ", ")
    }
}

/// View Profile / Share / Edit button row on the signed-in Account sheet (`Account-Sheet.dc.html`).
struct AccountSheetProfileActions: View {
    let dashboardURL: URL
    let profileEditURL: URL?
    let onViewProfile: () -> Void
    let onEditProfile: (URL) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        layout {
            // Board 35 gives this one more room (1.4 : 1 : 1); sized to its
            // label it no longer wraps "View / Profile" onto two lines.
            Button(action: onViewProfile) {
                Label("View Profile", systemImage: "person")
                    // Pressed for room, the adaptive label style drops the
                    // title and leaves a bare icon; this button needs both.
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
                    .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
            }
            .buttonStyle(.kudos(variant: .primary, dense: true))

            ShareLink(item: dashboardURL) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.kudos(variant: .secondary, dense: true))

            Button {
                if let profileEditURL { onEditProfile(profileEditURL) }
            } label: {
                Label("Edit", systemImage: "pencil")
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.kudos(variant: .secondary, dense: true))
            .accessibilityLabel(AccountSheetCopy.editProfileAccessibilityLabel)
            .disabled(profileEditURL == nil)
        }
    }
}

/// Centered destructive Log Out card and device-local session note (`Account-Sheet.dc.html`).
struct AccountSheetLogOutCard: View {
    @Binding var confirmingLogOut: Bool
    let onLogOut: () -> Void

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(role: .destructive) {
                confirmingLogOut = true
            } label: {
                Text("Log Out")
                    .font(.body)
                    .foregroundStyle(theme.appTheme.errorColor)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accountSheetPanel()
            .logOutConfirmation(isPresented: $confirmingLogOut, perform: onLogOut)

            Text(AccountSheetCopy.sessionFootnote(deviceName: ThisDevice.name))
                .font(.footnote)
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
        }
    }
}
