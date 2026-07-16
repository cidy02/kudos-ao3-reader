import SwiftData
import SwiftUI

// Building blocks for the redesigned Account tab: the profile identity card,
// the Overview "My AO3" navigation cards, and the embeddable account-list
// sections the Activity tab renders inline. Visual language matches Author
// Profiles (square `AO3AuthorAvatar`, `.cardRow()` surfaces, native segmented
// Pickers) — the page should read as the user's own profile, not Settings.

/// The Account page's profile identity card: avatar, username, "Posting As"
/// pseud selection, session state, and the profile-level actions.
struct AccountProfileCard: View {
    var profileModel: AO3AuthorProfileModel?
    @Binding var postingPseudName: String?
    var onViewProfile: () -> Void
    var onLogin: () -> Void

    @Environment(AO3AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @State private var showSessionDetail = false

    var body: some View {
        switch auth.status {
        case .restoring:
            skeleton
        case let .signedIn(username):
            signedInCard(username: username)
        case .signedOut, .signingIn, .usingFallback:
            signedOutCard
        }
    }

    private var skeleton: some View {
        HStack(spacing: 14) {
            SkeletonBlock(height: 72, width: 72, cornerRadius: 8)
            VStack(alignment: .leading, spacing: 9) {
                SkeletonTextLine(height: 20, width: 150)
                SkeletonTextLine(width: 110)
                SkeletonTextLine(width: 180)
            }
        }
        .padding(.vertical, 4)
        .skeletonShimmer()
        .accessibilityLabel("Restoring AO3 session")
    }

    private func signedInCard(username: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Button(action: onViewProfile) {
                AO3AuthorAvatar(
                    url: profileModel?.header?.identity.avatarURL,
                    name: username
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View Profile")
            .accessibilityHint("Opens your AO3 author profile")

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 8) {
                    Text(username)
                        .font(.title2.weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .accessibilityAddTraits(.isHeader)

                    Spacer(minLength: 4)

                    sessionStatusButton
                }

                HStack(alignment: .center, spacing: 8) {
                    postingAsMenu

                    Spacer(minLength: 4)

                    // Trailing edge matches the session checkmark above.
                    accountMenu
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    /// "Posting as <pseud>" — the identity comments are submitted under. The
    /// choices come from the loaded profile header; "Account Default" clears the
    /// preference so AO3's own default pseud applies.
    private var postingAsMenu: some View {
        Menu {
            Button {
                setPostingPseud(nil)
            } label: {
                Label(
                    "Account Default",
                    systemImage: postingPseudName == nil ? "checkmark" : "person"
                )
            }
            ForEach(availablePseuds) { pseud in
                Button {
                    setPostingPseud(pseud.name)
                } label: {
                    Label(
                        pseud.name,
                        systemImage: isSelectedPseud(pseud.name) ? "checkmark" : "person"
                    )
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("Posting as \(postingPseudName ?? "Account Default")")
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .font(.subheadline)
            .foregroundStyle(.tint)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: AccountControlMetrics.inlineCornerRadius))
        .controlSize(.small)
        .accessibilityLabel("Posting as")
        .accessibilityValue(postingPseudName ?? "Account Default")
    }

    private var availablePseuds: [AO3AuthorPseud] {
        var pseuds = profileModel?.header?.pseuds ?? []
        // A stored preference should stay visible (and clearable) even before the
        // profile header loads its pseud list.
        if let chosen = postingPseudName,
           !pseuds.contains(where: { $0.name.localizedCaseInsensitiveCompare(chosen) == .orderedSame }),
           let username = auth.username,
           let route = AO3AuthorRoute(username: username, pseud: chosen) {
            pseuds.append(AO3AuthorPseud(name: chosen, route: route, avatarURL: nil))
        }
        return pseuds
    }

    private func isSelectedPseud(_ name: String) -> Bool {
        postingPseudName?.localizedCaseInsensitiveCompare(name) == .orderedSame
    }

    private func setPostingPseud(_ name: String?) {
        postingPseudName = name
        auth.setPreferredPostingPseudName(name)
    }

    /// Compact session indicator pinned top-trailing next to the username.
    /// Detail text lives in a popover so the card stays dense.
    private var sessionStatusButton: some View {
        Button {
            showSessionDetail = true
        } label: {
            sessionStatusIcon
                .font(.body)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(sessionStatusDetailText)
        .accessibilityHint("Shows session verification details")
        .popover(isPresented: $showSessionDetail, arrowEdge: .bottom) {
            Text(sessionStatusDetailText)
                .font(.subheadline)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minWidth: 180, alignment: .leading)
                .presentationCompactAdaptation(.popover)
        }
    }

    @ViewBuilder
    private var sessionStatusIcon: some View {
        // Same SF Symbols as the former inline sessionStatusLine.
        switch auth.sessionHealth {
        case .unknown:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .verifying:
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case .healthy:
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
        case .expired:
            Image(systemName: "xmark.seal.fill")
                .foregroundStyle(.red)
        case .unreachable:
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.orange)
        }
    }

    private var sessionStatusDetailText: String {
        switch auth.sessionHealth {
        case .unknown:
            "Signed in"
        case .verifying:
            "Checking session…"
        case let .healthy(at):
            "Signed in · verified \(at.formatted(.relative(presentation: .named)))"
        case .expired:
            "Session expired"
        case .unreachable:
            "Signed in · couldn't verify"
        }
    }

    private var accountMenu: some View {
        Menu {
            Button {
                Task { await auth.verifySession() }
            } label: {
                Label(
                    auth.sessionHealth.isChecking ? "Checking…" : "Verify Session",
                    systemImage: "arrow.clockwise"
                )
            }
            .disabled(auth.sessionHealth.isChecking)

            if let username = auth.username,
               let route = AO3AuthorRoute(username: username) {
                Button {
                    router.open(route.dashboardURL)
                } label: {
                    Label("Open on AO3", systemImage: "safari")
                }
            }

            Divider()

            Button(role: .destructive) {
                Task { await auth.logout() }
            } label: {
                Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: AccountControlMetrics.inlineCornerRadius))
        .controlSize(.small)
        .accessibilityLabel("Account actions")
    }

    private var signedOutCard: some View {
        HStack(alignment: .top, spacing: 14) {
            AO3AuthorAvatar(url: nil, name: "AO3 account")

            VStack(alignment: .leading, spacing: 5) {
                Text("Not signed in")
                    .font(.title2.weight(.semibold))
                Text("Log in to use your AO3 works, bookmarks, subscriptions, "
                    + "history, and inbox. Your session stays on this device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onLogin) {
                    HStack(spacing: 5) {
                        Image(systemName: "person.badge.key")
                        Text(auth.status == .signingIn ? "Logging In…" : "Log In to AO3")
                    }
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: AccountControlMetrics.inlineCornerRadius))
                .controlSize(.small)
                .disabled(auth.status == .signingIn)
                .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}

/// Secondary scope control for Account (Reading / Writing / Activity lists).
/// Visual design matches Comments' chapter dropdown: leading `Label` (icon +
/// current value), trailing single `chevron.down`, full-width hit target in a card.
/// The leading icon always reflects the **selected subsection**, not the parent tab.
struct AccountScopeMenu<Tab: Hashable & RawRepresentable & CaseIterable & Identifiable>: View
where Tab.RawValue == String, Tab.AllCases: RandomAccessCollection {
    /// Accessibility name for the control (“Show”, “List”, …).
    var prompt: String = "Show"
    /// SF Symbol for each subsection option (and the closed label).
    var systemImage: (Tab) -> String
    @Binding var selection: Tab

    var body: some View {
        Menu {
            ForEach(Array(Tab.allCases)) { tab in
                Button {
                    selection = tab
                } label: {
                    // Icon per option so the open menu matches the closed control.
                    if tab == selection {
                        Label(tab.rawValue, systemImage: "checkmark")
                    } else {
                        Label(tab.rawValue, systemImage: systemImage(tab))
                    }
                }
            }
        } label: {
            // Same structure as `CommentsView.chapterSection` — icon + title, then
            // a quiet down-chevron (not the up/down pair, not a trailing value).
            HStack {
                Label(selection.rawValue, systemImage: systemImage(selection))
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(prompt)
        .accessibilityValue(selection.rawValue)
        .accessibilityHint("Chooses which list to show")
    }
}

/// Card chrome matching `.cardRow()` when content lives outside a `List`
/// (Account compact ScrollView shell). Same side margin, inner padding, radius,
/// and surface as detailed-mode list cards so scope/fandom controls align.
struct AccountScrollChromeCard<Content: View>: View {
    @Environment(ThemeManager.self) private var theme
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, CardListMetrics.innerHorizontal)
            .padding(.vertical, AccountControlMetrics.verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AccountControlMetrics.cornerRadius, style: .continuous)
                    .fill(theme.appTheme.cardSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: AccountControlMetrics.cornerRadius, style: .continuous)
                            .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, CardListMetrics.sideMargin)
    }
}

/// One Overview navigation card row: tinted leading icon, title, optional
/// cached list size, and a trailing chevron (in-app) or external-open glyph
/// (AO3 website destinations).
struct AccountNavCardLabel: View {
    let title: String
    let systemImage: String
    var count: String?
    /// When true, shows the "open outside" glyph instead of a disclosure chevron.
    var opensExternally: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(.tint)
                .frame(width: 22, alignment: .center)
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if let count {
                Text(count)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: opensExternally ? "arrow.up.forward.square" : "chevron.right")
                .font(opensExternally ? .body : .caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// One free-standing shortcut icon for Overview's 3×2 grid. Each tile owns its
/// own card chrome so the six destinations read as separate controls, not one
/// shared panel of symbols.
struct AccountShortcutGridTile: View {
    @Environment(ThemeManager.self) private var theme

    let title: String
    let systemImage: String
    var count: String?
    var opensExternally: Bool = false

    private let cornerRadius: CGFloat = 14

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.tint)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                    )
                if opensExternally {
                    Image(systemName: "arrow.up.forward")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(3)
                        .background(Circle().fill(theme.appTheme.cardSurface))
                        .offset(x: 6, y: -4)
                }
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            if let count {
                Text(count)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 88)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(theme.appTheme.cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
                )
                .shadow(
                    color: theme.appTheme.cardShadow.color,
                    radius: theme.appTheme.cardShadow.radius,
                    x: 0,
                    y: theme.appTheme.cardShadow.y
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(opensExternally ? "Opens on AO3 in Browse" : "Opens in Account")
    }
}

/// Apple Books-style two-up cover grid for Account work lists — same pattern as
/// Library/Home compact mode (`ScrollView` + `NavigationLink` label, not a stack
/// of background `cardNavigation` links inside one List row).
///
/// **Host in a `ScrollView` (or other non-List container).** Embedding many
/// `NavigationLink`s in a single List cell re-breaks tap targeting.
struct AccountWorksCompactGrid: View {
    let entries: [CanonicalWork]

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(entries) { entry in
                compactCard(for: entry)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func compactCard(for entry: CanonicalWork) -> some View {
        if let work = entry.local {
            // Account destinations use `SavedWork` → WorkDetailView (not LocalWorkDestination).
            NavigationLink(value: work) {
                SensitiveWorkCoverCard(work: work, progress: work.readingProgress)
            }
            .buttonStyle(.plain)
            .localWorkContextMenu(work: work)
        } else if let remote = entry.remote {
            NavigationLink(value: remote) {
                AO3WorkCoverCard(work: remote)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Compact two-up grid for bookmark lists — Library-style `NavigationLink` labels.
struct AccountBookmarksCompactGrid: View {
    let bookmarks: [AO3AuthorBookmark]

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(bookmarks) { bookmark in
                NavigationLink(value: bookmark.work) {
                    AO3WorkCoverCard(work: bookmark.work)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }
}

/// How Account hosts this section.
enum AccountWorksLayout: Equatable {
    /// Inside Account's `List` (detailed rows only for work cards).
    case list
    /// Library-style `ScrollView` host — required for compact `NavigationLink` grids.
    case scroll
}

/// Cross-remount snapshot of one `AccountWorksInlineSection`'s pagination
/// state, keyed by list kind + session. `AccountWorksInlineSection` is plain
/// `@State`, which SwiftUI discards whenever Account swaps between its List
/// (Detailed) and ScrollView (Compact) roots, or between any two branches that
/// re-instantiate it — without this, toggling display mode (or just tapping to
/// a different subsection and back) silently snapped the list back to page 1
/// and lost its scroll position. Session-scoped, in-memory only, matching the
/// pattern of `AO3AccountListCountsCache`/`AO3AuthorPageCache` elsewhere.
@MainActor
private final class AccountWorksInlineSectionCache {
    static let shared = AccountWorksInlineSectionCache()

    struct Key: Hashable {
        let kind: AO3AccountWorksList.Kind
        let sessionUsername: String
        /// Splits two sessions of the same username (logout/relogin) so a
        /// cross-remount restore can never hand this account a snapshot fetched
        /// under a prior, since-replaced session (T91-RF3/RF5 parity).
        let sessionGeneration: Int
    }

    struct Snapshot {
        var works: [AO3WorkSummary]
        var currentPage: Int
        var totalPages: Int
    }

    private var snapshots: [Key: Snapshot] = [:]

    func snapshot(for key: Key) -> Snapshot? { snapshots[key] }
    func store(_ snapshot: Snapshot, for key: Key) { snapshots[key] = snapshot }
}

/// An account works list (AO3 History / Marked for Later) embeddable as rows in
/// the Account page's own List — the Activity tab's inline counterpart of the
/// pushed `AO3AccountWorksList` screen. Fetches through the same TTL'd page
/// cache as author profiles, so flipping between Activity segments re-renders
/// from cache instead of re-requesting.
struct AccountWorksInlineSection: View {
    let kind: AO3AccountWorksList.Kind
    var expandAll: Bool
    var displayMode: WorkListDisplayMode = .detailed
    var layout: AccountWorksLayout = .list
    /// Bumped by the host's pull-to-refresh; a change forces a cache bypass.
    var reloadToken: Int
    /// Reports whether this page's rendered canonical entries include a local
    /// Mature/Explicit work before Hide mode omits it.
    var onAdultContentVisibilityChange: (Bool) -> Void = { _ in }
    /// Pushes the full `AO3AccountWorksList(kind:)` screen — this inline section
    /// is a lightweight preview with no refine-filter panel or Mature-content
    /// reveal toggle of its own, so those stay reachable one tap away.
    var onRefine: () -> Void

    @Environment(AO3AuthService.self) private var auth
    @Environment(PrivacyGate.self) private var gate
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure
    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }) private var localWorks: [SavedWork]

    @State private var works: [AO3WorkSummary] = []
    @State private var currentPage = 1
    @State private var totalPages = 1
    @State private var phase: Phase = .idle
    @State private var handledReloadToken: Int?
    /// Cancelled and replaced on every load so a fast double-tap (retry, or two
    /// pagination taps in a row) can't race two `load()` calls against the same
    /// @State — mirrors the `launch()` pattern in AO3InboxModel/AO3AuthorProfileModel.
    @State private var activeTask: Task<Void, Never>?

    private enum Phase: Equatable {
        case idle, loading, loaded, failed(String)
    }

    private var entries: [CanonicalWork] {
        canonicalEntries(
            localLibrary: localWorks.filter {
                !gate.isHidden($0, enabled: hideMature, mode: matureMode)
            }
        )
    }

    private var hasVisibleAdultContent: Bool {
        canonicalEntries(localLibrary: localWorks)
            .contains { $0.local?.isAdult == true }
    }

    private func canonicalEntries(localLibrary: [SavedWork]) -> [CanonicalWork] {
        CanonicalWorkMerge.remoteLed(remote: works, localLibrary: localLibrary)
    }

    private var loadTaskID: String {
        "\(auth.username ?? "")|\(reloadToken)"
    }

    var body: some View {
        Group {
            if layout == .scroll {
                scrollBody
            } else {
                listBody
            }
        }
        .task(id: loadTaskID) { await runLoadTask() }
        .onChange(of: hasVisibleAdultContent, initial: true) { _, hasVisibleAdultContent in
            onAdultContentVisibilityChange(hasVisibleAdultContent)
        }
    }

    private var listBody: some View {
        Section {
            phaseContent(useCardRow: true)
        } header: {
            sectionHeader
        }
    }

    private var scrollBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Match detailed List section header + card row alignment.
            sectionHeader
                .padding(.horizontal, CardListMetrics.sideMargin + CardListMetrics.innerHorizontal)
            phaseContent(useCardRow: false)
        }
    }

    private var sectionHeader: some View {
        HStack {
            Text(kind.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onRefine) {
                Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.footnote)
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: AccountControlMetrics.inlineCornerRadius))
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func phaseContent(useCardRow: Bool) -> some View {
        switch phase {
        case .idle, .loading:
            if works.isEmpty {
                if useCardRow {
                    AO3AuthorLoadingRows()
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            } else {
                rows(useCardRow: useCardRow)
            }
        case let .failed(message):
            AO3ProfileMessageRow(
                title: "Couldn't load your list",
                systemImage: "exclamationmark.triangle",
                message: message,
                actionTitle: "Try Again",
                action: { launch(page: currentPage, bypassCache: true) }
            )
            .modifier(OptionalCardRow(enabled: useCardRow))
        case .loaded where works.isEmpty:
            AO3ProfileMessageRow(
                title: kind.emptyTitle,
                systemImage: "bookmark",
                message: kind.emptyMessage
            )
            .modifier(OptionalCardRow(enabled: useCardRow))
        case .loaded:
            rows(useCardRow: useCardRow)
        }
    }

    private var cacheKey: AccountWorksInlineSectionCache.Key {
        .init(
            kind: kind,
            sessionUsername: auth.username ?? "",
            sessionGeneration: auth.sessionGeneration
        )
    }

    private func runLoadTask() async {
        let bypass = handledReloadToken != nil && handledReloadToken != reloadToken
        handledReloadToken = reloadToken
        guard auth.isLoggedIn else {
            works = []
            phase = .idle
            return
        }
        if phase == .idle, !bypass,
           let cached = AccountWorksInlineSectionCache.shared.snapshot(for: cacheKey),
           !cached.works.isEmpty {
            // This is a freshly (re)constructed instance — e.g. Account just
            // swapped between its Detailed (List) and Compact (ScrollView) roots,
            // or the user switched subsections and back. Restore the page it was
            // on instead of silently snapping back to page 1.
            works = cached.works
            currentPage = cached.currentPage
            totalPages = cached.totalPages
            phase = .loaded
            return
        }
        if phase == .idle || bypass {
            await load(page: bypass ? currentPage : 1, bypassCache: bypass)
        }
    }

    /// Cancels any in-flight load before starting a new one — see `activeTask`.
    private func launch(page: Int, bypassCache: Bool = false) {
        activeTask?.cancel()
        activeTask = Task { await load(page: page, bypassCache: bypassCache) }
    }

    @ViewBuilder
    private func rows(useCardRow: Bool) -> some View {
        if displayMode == .compact {
            AccountWorksCompactGrid(entries: entries)
            if totalPages > 1 {
                SearchPaginationBar(currentPage: currentPage, totalPages: totalPages) { page in
                    launch(page: page)
                }
                .padding(.horizontal, CardListMetrics.sideMargin)
            }
        } else {
            ForEach(entries) { entry in
                if let work = entry.local {
                    SensitiveWorkRow(work: work, expandAll: expandAll)
                        .cardNavigation(to: work)
                        .modifier(OptionalCardRow(enabled: useCardRow))
                } else if let remote = entry.remote {
                    AO3WorkRow(work: remote, expandAll: expandAll)
                        .cardNavigation(to: remote)
                        .modifier(OptionalCardRow(enabled: useCardRow))
                }
            }
            if totalPages > 1 {
                SearchPaginationBar(currentPage: currentPage, totalPages: totalPages) { page in
                    launch(page: page)
                }
                .modifier(OptionalCardRow(enabled: useCardRow))
            }
        }
    }

    private func load(page: Int, bypassCache: Bool = false) async {
        let expectedSessionGeneration = auth.sessionGeneration
        guard let username = auth.username,
              let url = kind.url(username: username, page: page)
        else {
            works = []
            phase = .idle
            return
        }
        phase = works.isEmpty ? .loading : .loaded
        do {
            let fetched = try await AO3AuthorProfileFetcher.page(
                at: url,
                auth: auth,
                cacheScope: AO3AuthorProfileFetcher.sessionScopedCacheScope(for: auth),
                isCurrent: { auth.sessionGeneration == expectedSessionGeneration },
                bypassCache: bypassCache
            )
            try Task.checkCancellation()
            guard auth.sessionGeneration == expectedSessionGeneration else { return }
            let result = try parse(fetched.html, page: page)
            works = result.works
            currentPage = result.currentPage
            totalPages = result.totalPages
            phase = .loaded
            AccountWorksInlineSectionCache.shared.store(
                .init(works: works, currentPage: currentPage, totalPages: totalPages),
                for: cacheKey
            )
            if let countsKind = kind.countsKind {
                AO3AccountListCountsCache.shared.record(
                    page: result,
                    kind: countsKind,
                    authenticationScope: AO3AuthorProfileFetcher.sessionScopedCacheScope(for: auth)
                )
            }
        } catch is CancellationError {
            // The header task cancels if it scrolls away mid-load; drop back to
            // .idle so its next appearance actually reloads instead of leaving
            // permanent skeletons behind the stale .loading phase.
            if auth.sessionGeneration == expectedSessionGeneration, works.isEmpty { phase = .idle }
            return
        } catch AO3Error.authenticationRequired {
            guard await auth.sessionDidExpire(expectedGeneration: expectedSessionGeneration) else { return }
            works = []
            phase = .idle
        } catch let error as AO3Error {
            guard auth.sessionGeneration == expectedSessionGeneration else { return }
            phase = .failed(error.errorDescription ?? "Something went wrong.")
        } catch {
            guard auth.sessionGeneration == expectedSessionGeneration else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    /// Same parser per list shape as `AO3AccountWorksList.Kind.fetch`, over the
    /// cached-page HTML instead of a fresh request.
    private func parse(_ html: String, page: Int) throws -> AO3SearchPage {
        switch kind {
        case .bookmarks:
            try AO3Client.parseBookmarksPage(html, page: page)
        case .subscriptions:
            try AO3Client.parseSubscriptionsPage(html, page: page)
        case .markedForLater, .history, .collection:
            try AO3Client.parseSearchPage(html, page: page)
        }
    }
}

/// Applies `.cardRow()` only when embedding in Account's List.
private struct OptionalCardRow: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.cardRow()
        } else {
            content
                .padding(.horizontal, CardListMetrics.sideMargin)
        }
    }
}
