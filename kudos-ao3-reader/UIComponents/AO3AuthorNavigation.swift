import SwiftUI

private struct AO3AuthorNavigationEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var ao3AuthorNavigationEnabled: Bool {
        get { self[AO3AuthorNavigationEnabledKey.self] }
        set { self[AO3AuthorNavigationEnabledKey.self] = newValue }
    }
}

nonisolated struct AO3AuthorBylineToken: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let route: AO3AuthorRoute?
}

nonisolated enum AO3AuthorBylineResolver {
    static func tokens(
        names: [String],
        identities: [AO3AuthorIdentity],
        fallbackText: String
    ) -> [AO3AuthorBylineToken] {
        let displayNames: [String]
        if !names.isEmpty {
            displayNames = names
        } else if !identities.isEmpty {
            displayNames = identities.map(\.displayName)
        } else {
            displayNames = [fallbackText.isEmpty ? "Anonymous" : fallbackText]
        }

        var remaining = identities
        return displayNames.enumerated().map { index, name in
            let match = remaining.firstIndex {
                $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                    .localizedCaseInsensitiveCompare(
                        name.trimmingCharacters(in: .whitespacesAndNewlines)
                    ) == .orderedSame
            }
            let route = match.flatMap { remaining.remove(at: $0).route }
            return AO3AuthorBylineToken(id: index, name: name, route: route)
        }
    }
}

/// Shared byline rendering for remote summaries, verified local works, series, and
/// registered comments. Every tappable name carries an AO3-parsed route; fallback
/// display text is never turned into a guessed profile URL.
struct AO3AuthorBylineView: View {
    let names: [String]
    let identities: [AO3AuthorIdentity]
    var fallbackText = "Anonymous"
    var includesBy = true
    var font: Font = .subheadline
    var compact = false
    var emphasized = false
    private let onOpenRoute: ((AO3AuthorRoute) -> Void)?

    @Environment(AppRouter.self) private var router
    @Environment(\.ao3AuthorNavigationEnabled) private var navigationEnabled

    init(
        names: [String],
        identities: [AO3AuthorIdentity],
        fallbackText: String = "Anonymous",
        includesBy: Bool = true,
        font: Font = .subheadline,
        compact: Bool = false,
        emphasized: Bool = false,
        onOpenRoute: ((AO3AuthorRoute) -> Void)? = nil
    ) {
        self.names = names
        self.identities = identities
        self.fallbackText = fallbackText
        self.includesBy = includesBy
        self.font = font
        self.compact = compact
        self.emphasized = emphasized
        self.onOpenRoute = onOpenRoute
    }

    init(
        displayText: String,
        identities: [AO3AuthorIdentity],
        includesBy: Bool = true,
        font: Font = .subheadline,
        compact: Bool = false,
        emphasized: Bool = false,
        onOpenRoute: ((AO3AuthorRoute) -> Void)? = nil
    ) {
        self.init(
            names: identities.isEmpty ? [] : identities.map(\.displayName),
            identities: identities,
            fallbackText: displayText,
            includesBy: includesBy,
            font: font,
            compact: compact,
            emphasized: emphasized,
            onOpenRoute: onOpenRoute
        )
    }

    var body: some View {
        FlowLayout(spacing: 0, rowSpacing: 0) {
            if includesBy {
                Text("by ")
                    .foregroundStyle(.secondary)
            }
            ForEach(tokens) { token in
                let text = token.name + (token.id == tokens.count - 1 ? "" : ", ")
                if let route = token.route, navigationEnabled {
                    Button {
                        if let onOpenRoute {
                            onOpenRoute(route)
                        } else {
                            router.openAuthorProfile(route)
                        }
                    } label: {
                        Text(text)
                            .fontWeight(emphasized ? .semibold : .regular)
                            .frame(minHeight: compact ? 30 : 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.tint)
                    .accessibilityLabel(token.name)
                    .accessibilityHint("Open AO3 author profile")
                } else {
                    Text(text)
                        .fontWeight(emphasized ? .semibold : .regular)
                        .foregroundStyle(.secondary)
                        .frame(minHeight: compact ? 30 : 44)
                }
            }
        }
        .font(font)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }

    private var tokens: [AO3AuthorBylineToken] {
        AO3AuthorBylineResolver.tokens(
            names: names,
            identities: identities,
            fallbackText: fallbackText
        )
    }
}

private struct AO3AuthorNavigationModifier: ViewModifier {
    @Environment(AppRouter.self) private var router
    @Binding var path: NavigationPath
    let tab: AppTab

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: AO3AuthorRoute.self) { route in
                AuthorProfileView(route: route)
            }
            .navigationDestination(for: AO3SeriesSummary.self) { series in
                AO3SeriesDetailView(series: series)
            }
            .onChange(of: router.pendingAuthorProfile, initial: true) { _, route in
                guard router.selection == tab, let route else { return }
                path.append(route)
                router.pendingAuthorProfile = nil
            }
    }
}

extension View {
    /// Registers the one author/series destination pair and consumes profile links
    /// handed up by nested cards, comments, and readers in this root tab.
    func ao3AuthorNavigation(path: Binding<NavigationPath>, tab: AppTab) -> some View {
        modifier(AO3AuthorNavigationModifier(path: path, tab: tab))
    }
}
