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
            AO3AuthorAvatar(
                url: profileModel?.header?.identity.avatarURL,
                name: username
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(username)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .accessibilityAddTraits(.isHeader)

                postingAsMenu

                sessionStatusLine

                HStack(spacing: 8) {
                    Button(action: onViewProfile) {
                        HStack(spacing: 5) {
                            Image(systemName: "person.text.rectangle")
                            Text("View Profile")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    accountMenu
                }
                .padding(.top, 3)
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

    /// One compact line for signed-in state + the last session check, so session
    /// management stays visible without dominating the page.
    @ViewBuilder
    private var sessionStatusLine: some View {
        switch auth.sessionHealth {
        case .unknown:
            Label("Signed in", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .verifying:
            Label("Checking session…", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .healthy(at):
            Label(
                "Signed in · verified \(at.formatted(.relative(presentation: .named)))",
                systemImage: "checkmark.seal.fill"
            )
            .font(.caption)
            .foregroundStyle(.green)
        case .expired:
            Label("Session expired", systemImage: "xmark.seal.fill")
                .font(.caption)
                .foregroundStyle(.red)
        case .unreachable:
            Label("Signed in · couldn't verify", systemImage: "wifi.exclamationmark")
                .font(.caption)
                .foregroundStyle(.orange)
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
                .controlSize(.small)
                .disabled(auth.status == .signingIn)
                .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}

/// One Overview "My AO3" navigation card row: tinted icon tile, title, and the
/// cached list size when one is already known (never fetched for the card).
struct AccountNavCardLabel: View {
    let title: String
    let systemImage: String
    var count: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(.tint)
                .frame(width: 34, height: 34)
                .background(
                    Color.accentColor.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if let count {
                Text(count)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// An account works list (AO3 History / Marked for Later) embeddable as rows in
/// the Account page's own List — the Activity tab's inline counterpart of the
/// pushed `AO3AccountWorksList` screen. Fetches through the same TTL'd page
/// cache as author profiles, so flipping between Activity segments re-renders
/// from cache instead of re-requesting.
struct AccountWorksInlineSection: View {
    let kind: AO3AccountWorksList.Kind
    var expandAll: Bool
    /// Bumped by the host's pull-to-refresh; a change forces a cache bypass.
    var reloadToken: Int

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

    private enum Phase: Equatable {
        case idle, loading, loaded, failed(String)
    }

    private var entries: [CanonicalWork] {
        CanonicalWorkMerge.remoteLed(
            remote: works,
            localLibrary: localWorks.filter { !gate.isHidden($0, enabled: hideMature, mode: matureMode) }
        )
    }

    var body: some View {
        Section {
            switch phase {
            case .idle, .loading:
                if works.isEmpty {
                    AO3AuthorLoadingRows()
                } else {
                    rows
                }
            case let .failed(message):
                AO3ProfileMessageRow(
                    title: "Couldn't load your list",
                    systemImage: "exclamationmark.triangle",
                    message: message,
                    actionTitle: "Try Again",
                    action: { Task { await load(page: currentPage, bypassCache: true) } }
                )
                .cardRow()
            case .loaded where works.isEmpty:
                AO3ProfileMessageRow(
                    title: kind.emptyTitle,
                    systemImage: "bookmark",
                    message: kind.emptyMessage
                )
                .cardRow()
            case .loaded:
                rows
            }
        } header: {
            // The load trigger lives on the header (one stable view) rather than
            // the Section — modifiers on a Section re-apply to every row, which
            // would spawn one task per row.
            Text(kind.title)
                .task(id: "\(auth.username ?? "")|\(reloadToken)") {
                    let bypass = handledReloadToken != nil && handledReloadToken != reloadToken
                    handledReloadToken = reloadToken
                    guard auth.isLoggedIn else {
                        works = []
                        phase = .idle
                        return
                    }
                    if phase == .idle || bypass {
                        await load(page: bypass ? currentPage : 1, bypassCache: bypass)
                    }
                }
        }
    }

    @ViewBuilder
    private var rows: some View {
        ForEach(entries) { entry in
            if let work = entry.local {
                SensitiveWorkRow(work: work, expandAll: expandAll)
                    .cardNavigation(to: work)
                    .cardRow()
            } else if let remote = entry.remote {
                AO3WorkRow(work: remote, expandAll: expandAll)
                    .cardNavigation(to: remote)
                    .cardRow()
            }
        }
        if totalPages > 1 {
            SearchPaginationBar(currentPage: currentPage, totalPages: totalPages) { page in
                Task { await load(page: page) }
            }
            .cardRow()
        }
    }

    private func load(page: Int, bypassCache: Bool = false) async {
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
                at: url, auth: auth, bypassCache: bypassCache
            )
            try Task.checkCancellation()
            let result = try parse(fetched.html, page: page)
            works = result.works
            currentPage = result.currentPage
            totalPages = result.totalPages
            phase = .loaded
            if let countsKind = kind.countsKind {
                AO3AccountListCountsCache.shared.record(
                    page: result,
                    kind: countsKind,
                    authenticationScope: AO3AuthorProfileFetcher.authenticationScope(for: auth)
                )
            }
        } catch is CancellationError {
            return
        } catch AO3Error.authenticationRequired {
            await auth.sessionDidExpire()
            works = []
            phase = .idle
        } catch let error as AO3Error {
            phase = .failed(error.errorDescription ?? "Something went wrong.")
        } catch {
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
        case .markedForLater, .history, .myWorks, .collection:
            try AO3Client.parseSearchPage(html, page: page)
        }
    }
}
