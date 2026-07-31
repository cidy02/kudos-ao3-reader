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
    /// Whether a navigable name takes the accent.
    ///
    /// Defaults to true, which is right where a byline names *the* author of the
    /// thing on screen — one accented name, and it means something. It is wrong in
    /// a comment section: accenting every commenter puts the loudest colour in the
    /// app on the most repeated element, so the tint stops marking importance and
    /// just marks "a person". Comments pass false for everyone except the work's
    /// own author. The name stays tappable either way — avatar, hit box and the
    /// button trait are unchanged.
    var tinted = true
    /// Whether a navigable name carries its own 28pt hit target.
    ///
    /// Defaults to true. Set false only where something else already offers a
    /// large target for the same destination *and* the extra box would be visible
    /// as layout: the frame is top-aligned so it grows downward, which is invisible
    /// beside inline text but shows as a gap under a name that has something
    /// stacked beneath it. A guest's name takes the non-navigable branch and has no
    /// such frame, so leaving this on makes registered and guest bylines sit
    /// differently for no reason a reader could name.
    var expandsHitTarget = true
    private let onOpenRoute: ((AO3AuthorRoute) -> Void)?

    @Environment(AppRouter.self) private var router
    @Environment(\.ao3AuthorNavigationEnabled) private var navigationEnabled
    /// Which co-author token currently holds hardware-keyboard focus (macOS/iPadOS).
    /// Keyed by `AO3AuthorBylineToken.id`, not a Bool, since a byline can hold several
    /// independently-focusable names.
    @FocusState private var focusedTokenID: Int?

    init(
        names: [String],
        identities: [AO3AuthorIdentity],
        fallbackText: String = "Anonymous",
        includesBy: Bool = true,
        font: Font = .subheadline,
        compact: Bool = false,
        emphasized: Bool = false,
        tinted: Bool = true,
        expandsHitTarget: Bool = true,
        onOpenRoute: ((AO3AuthorRoute) -> Void)? = nil
    ) {
        self.names = names
        self.identities = identities
        self.fallbackText = fallbackText
        self.includesBy = includesBy
        self.font = font
        self.compact = compact
        self.emphasized = emphasized
        self.tinted = tinted
        self.expandsHitTarget = expandsHitTarget
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
        // HStack + firstTextBaseline keeps "by" and names on one line. Avoid:
        // (1) minHeight on only the name (dropped it below "by"),
        // (2) negative-padding hit expansion (zeroed the button hit rect in List
        //     rows so taps fell through to card NavigationLink),
        // (3) FlowLayout for this byline (custom Layout hit-testing is less reliable
        //     for nested borderless Buttons inside List + background NavigationLink).
        // Coauthors almost always fit one line; rare overflow truncates at the end.
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if includesBy {
                Text("by ")
                    .foregroundStyle(.secondary)
            }
            ForEach(tokens) { token in
                let text = token.name + (token.id == tokens.count - 1 ? "" : ", ")
                if let route = token.route, navigationEnabled {
                    // highPriorityGesture (not a nested Button): List rows that use
                    // background `cardNavigation` NavigationLinks still activate on
                    // borderless Button taps, stacking the work/reader on top of the
                    // author profile — profile only appeared after Back. Priority
                    // gesture claims the touch so the row link does not fire. A real
                    // Button was tried here before and reverted for the same reason —
                    // don't reintroduce one; hardware-keyboard support below is added
                    // via .focusable/.onKeyPress instead, not by becoming a Button.
                    //
                    // frame + contentShape are established BEFORE highPriorityGesture
                    // is attached (not after) so the gesture is unambiguously scoped to
                    // the full enlarged region from the moment it exists — relying on a
                    // later outer contentShape to retroactively extend an
                    // already-attached gesture is exactly the kind of ordering risk that
                    // needs a runtime check, not just a plausible reading of the docs;
                    // this ordering sidesteps the question instead of resting on it.
                    // NOT .minimumHitTarget() here: that modifier's plain
                    // .frame(minHeight:) centers its content vertically, which shifts
                    // this Text's baseline and reproduces the exact "dropped it below
                    // 'by'" regression noted above (1) — the frame must stay top-aligned
                    // so the enlarged hit box only grows downward, off the baseline.
                    Text(text)
                        .fontWeight(emphasized ? .semibold : .regular)
                        .foregroundStyle(tinted ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                        .frame(
                            minWidth: expandsHitTarget ? 28 : 0,
                            minHeight: expandsHitTarget ? 28 : 0,
                            alignment: .top
                        )
                        .contentShape(Rectangle())
                        .highPriorityGesture(TapGesture().onEnded { activate(route) })
                        .accessibilityLabel(token.name)
                        .accessibilityHint("Open AO3 author profile")
                        .accessibilityAddTraits(.isButton)
                        .focusable(true)
                        .focused($focusedTokenID, equals: token.id)
                        .onKeyPress(keys: [.return, .space]) { _ in
                            activate(route)
                            return .handled
                        }
                        .overlay {
                            if focusedTokenID == token.id {
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.accentColor, lineWidth: 2)
                            }
                        }
                } else {
                    Text(text)
                        .fontWeight(emphasized ? .semibold : .regular)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(font)
        .lineLimit(compact ? 1 : 2)
        // Compact (comment bylines) hugs the name so sibling Author/Guest chips
        // aren't pushed to zero width. Full-width remains for work-row bylines.
        .frame(
            maxWidth: compact ? nil : .infinity,
            alignment: .leading
        )
        .accessibilityElement(children: .contain)
    }

    private var tokens: [AO3AuthorBylineToken] {
        AO3AuthorBylineResolver.tokens(
            names: names,
            identities: identities,
            fallbackText: fallbackText
        )
    }

    /// Shared by the tap gesture and the keyboard-activation path below so both
    /// trigger identically.
    private func activate(_ route: AO3AuthorRoute) {
        if let onOpenRoute {
            onOpenRoute(route)
        } else {
            router.openAuthorProfile(route)
        }
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
            // Compact work cards open the work everywhere in the app, downloading it
            // first when the library does not have it. Registered here because every
            // tab's stack applies this modifier, and a card can appear in any of them
            // (carousels, Account's lists, an author profile pushed from anywhere) —
            // a stack that missed the registration would leave those cards inert.
            .navigationDestination(for: RemoteWorkReaderRoute.self) { route in
                RemoteWorkReaderDestination(summary: route.work)
            }
            // Observe the epoch (not the Optional route): @Observable + Optional
            // equality skips same-route re-taps. Epoch always changes; only the
            // selected tab consumes.
            .onChange(of: router.authorProfileNavigationEpoch, initial: true) { _, epoch in
                guard epoch > 0, router.selection == tab,
                      let route = router.consumePendingAuthorProfile() else { return }
                // Wait out the same-touch row NavigationLink (and its deferred
                // dismiss). Then push author so it ends up on top of the stack —
                // not under reader/detail, and not lost if dismiss races path.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    guard router.selection == tab else { return }
                    var next = path
                    next.append(route)
                    path = next
                }
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
