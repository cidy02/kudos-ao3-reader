import SwiftUI

/// A nav card that opens `archiveofourown.org/users/<username>/<pathSuffix>` (or
/// a site-wide `/path`) in Browse. Disabled when signed out for user-scoped
/// paths. Shared by `AccountView`'s own external-nav cards and
/// `AccountMoreOnAO3View`'s long-tail AO3 destinations.
struct AccountExternalNavCard: View {
    enum Target: Equatable, Sendable {
        case user(pathSuffix: String)
        case site(path: String)

        var requiresAuth: Bool {
            switch self {
            case .user: true
            case .site: false
            }
        }
    }

    let title: String
    var systemImage: String?
    let target: Target
    var isFormRow: Bool

    @Environment(AO3AuthService.self) private var auth
    @Environment(AppRouter.self) private var router

    init(
        title: String,
        systemImage: String? = nil,
        pathSuffix: String,
        isFormRow: Bool = false
    ) {
        self.title = title
        self.systemImage = systemImage
        self.target = .user(pathSuffix: pathSuffix)
        self.isFormRow = isFormRow
    }

    init(
        title: String,
        systemImage: String? = nil,
        sitePath: String,
        isFormRow: Bool = false
    ) {
        self.title = title
        self.systemImage = systemImage
        self.target = .site(path: sitePath)
        self.isFormRow = isFormRow
    }

    init(
        title: String,
        systemImage: String? = nil,
        target: Target,
        isFormRow: Bool = false
    ) {
        self.title = title
        self.systemImage = systemImage
        self.target = target
        self.isFormRow = isFormRow
    }

    private var isDisabled: Bool {
        target.requiresAuth && auth.username == nil
    }

    @ViewBuilder
    var body: some View {
        let button = Button {
            open()
        } label: {
            AccountNavCardLabel(
                title: title,
                systemImage: systemImage,
                opensExternally: true
            )
            .padding(.horizontal, isFormRow ? 14 : 0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)

        if isFormRow {
            button
        } else {
            button.accountControlCardRow()
        }
    }

    private func open() {
        switch target {
        case let .user(pathSuffix):
            Self.openUserPath(pathSuffix, username: auth.username, router: router)
        case let .site(path):
            Self.openSiteWidePath(path, router: router)
        }
    }

    /// Builds an archiveofourown.org URL for a user-scoped path (`/users/<username>/<suffix>`).
    static func userURL(suffix: String, username: String?) -> URL? {
        guard let username else { return nil }
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let path = suffix.isEmpty ? "/users/\(encoded)" : "/users/\(encoded)/\(suffix)"
        return URL(string: "https://archiveofourown.org\(path)")
    }

    /// Builds an archiveofourown.org URL for a site-wide path (`/<path>`).
    static func siteWideURL(path: String) -> URL? {
        let normalized = path.hasPrefix("/") ? path : "/\(path)"
        return URL(string: "https://archiveofourown.org\(normalized)")
    }

    static func openUserPath(_ suffix: String, username: String?, router: AppRouter) {
        guard let url = userURL(suffix: suffix, username: username) else { return }
        router.open(url)
    }

    static func openSiteWidePath(_ path: String, router: AppRouter) {
        guard let url = siteWideURL(path: path) else { return }
        router.open(url)
    }
}
