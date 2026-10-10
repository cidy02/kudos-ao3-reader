import SwiftUI

/// Artboard **1cc** — Prompt Meme prompts.
///
/// AO3's other challenge type: no sign-ups, no matching, no assignments —
/// prompts are posted and claimed freely, so this screen replaces 1bz/1cb
/// entirely for a collection whose challenge `kind` is `.promptMeme` rather
/// than sitting alongside them. Each card reads as prose, the way a prompt
/// actually is, with only the claim state as chrome (no cover art, no stat
/// strip). Claim and release are real writes (`AO3ChallengeActions.claimPrompt`
/// / `releasePrompt`). A prompt-meme prompt is a request on the poster's
/// sign-up, so "New prompt" opens the sign-up form (1ca), which AO3 serves as
/// requests only and redirects to the existing sign-up for a returning poster.
/// "Fill it" means posting a whole new work, which this screen doesn't
/// attempt, so it opens the meme on AO3 instead.
struct PromptMemeView: View {
    let collectionSlug: String
    var collectionTitle: String = ""
    /// Whether to ask AO3 for the close date at all. It is on the challenge's
    /// settings form, which AO3 serves to the collection's owners and refuses
    /// to everyone else, moderators included; the callers already know.
    var viewerIsOwner: Bool = false

    /// Whether this load asks AO3 for the close date: only for an owner (AO3
    /// refuses the settings form to anyone else), only until a date is known,
    /// and once per opening or refresh. Android follows the same rule.
    nonisolated static func readsSchedule(viewerIsOwner: Bool, attempted: Bool, hasDate: Bool) -> Bool {
        viewerIsOwner && !attempted && !hasDate
    }

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .headline) private var cardTitleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .body) private var promptBodySize: CGFloat = 14.5
    @ScaledMetric(relativeTo: .subheadline) private var buttonLabelSize: CGFloat = 14
    @ScaledMetric(relativeTo: .subheadline) private var loadingSize: CGFloat = 14
    @ScaledMetric(relativeTo: .footnote) private var bodySize: CGFloat = 12.5
    @ScaledMetric(relativeTo: .footnote) private var failureBodySize: CGFloat = 13
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 11.5

    @State private var prompts: [AO3PromptMemePrompt] = []
    @State private var currentPage: Int = 1
    @State private var totalPages: Int = 1
    @State private var filterSelection: PromptFilter = .all
    @State private var closeDateText: String = ""
    /// Set once the close date has been asked for, whatever came back.
    @State private var scheduleAttempted = false
    @State private var phase: Phase = .idle
    @State private var promptInFlight: Int?
    @State private var actionErrorMessage: String?

    enum PromptFilter: String, CaseIterable, Hashable, Sendable {
        case all = "All"
        case unclaimed = "Unclaimed"
        case yours = "Yours"
    }

    private enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private var gutter: CGFloat { SubjectMetrics.accountGutter }
    private var selfGuttered: CGFloat { 0 }

    private var palette: SubjectPalette {
        theme.appTheme.subjectPalette(hue: CoverArt.workHue(fandoms: [], title: effectiveTitle))
    }

    private var effectiveTitle: String {
        collectionTitle.isEmpty ? collectionSlug : collectionTitle
    }

    private var unclaimedCount: Int {
        prompts.filter { !$0.isClaimed }.count
    }

    private var filteredPrompts: [AO3PromptMemePrompt] {
        switch filterSelection {
        case .all:
            return prompts
        case .unclaimed:
            return prompts.filter { !$0.isClaimed }
        case .yours:
            // claimedByCurrentUser is exactly what it's for; the owner-name match
            // is a fallback so a prompt you posted (but haven't claimed) still
            // shows up here, since AO3 has no other signal for "mine" on this page.
            let loggedInName = auth.username ?? ""
            return prompts.filter { prompt in
                if prompt.claimedByCurrentUser { return true }
                return AO3ChallengeSignUpMatching.owns(
                    byline: prompt.displayedOwner ?? "", login: loggedInName
                )
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            promptList
            if auth.isLoggedIn {
                newPromptBar
            }
        }
        .task { await loadPromptsIfNeeded() }
        .refreshable {
            // A refresh is the reader's way to try for a date that did not load.
            scheduleAttempted = false
            await loadPrompts(page: 1)
        }
            .screenTint(palette)
    }

    private var promptList: some View {
        // A refused Claim or Release says so under the header. Tapped from a card
        // further down, that sentence was out of sight and the reader saw nothing
        // happen (T-360): the list returns to it. Android does the same.
        ScrollViewReader { proxy in
            promptRows
                .onChange(of: actionErrorMessage) { _, message in
                    guard message != nil else { return }
                    withAnimation { proxy.scrollTo(Self.headerRowID, anchor: .top) }
                }
        }
    }

    private static let headerRowID = "prompt-meme-header"

    private var promptRows: some View {
        List {
            Section {
                header.pageBodyRow(top: 20, gutter: selfGuttered).id(Self.headerRowID)
                filterSegment.pageBodyRow(top: 14, gutter: gutter)
            }

            if let actionErrorMessage {
                Section {
                    actionErrorCard(actionErrorMessage).pageBodyRow(top: 8, gutter: gutter)
                }
            }

            // A failed page change keeps the page already shown (`currentPage`
            // moves only on success) and says so above it.
            if case let .failed(message) = phase, !prompts.isEmpty {
                Section {
                    Label {
                        Text("Couldn't load that page: \(message)")
                            .font(.system(size: captionSize))
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 11.5))
                    }
                        .foregroundStyle(Color.secondary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                        .pageBodyRow(top: 8, gutter: gutter)
                }
            }

            switch phase {
            case .loading where prompts.isEmpty:
                Section {
                    loadingRow.pageBodyRow(top: 20, gutter: gutter)
                }
            case let .failed(message) where prompts.isEmpty:
                Section {
                    failureCard(message).pageBodyRow(top: 14, gutter: gutter)
                }
            default:
                contentSections
            }
        }
        .cardList()
        // Rows at their own padding, not the List minimum (L3-FORM-1).
        .environment(\.defaultMinListRowHeight, 0)
        #if os(macOS)
        .navigationTitle("Prompts")
        #endif
        .subjectScreenWash(palette: palette)
    }

    /// The spec's bottom-bar "New prompt": AO3's sign-up form for this meme.
    private var newPromptBar: some View {
        NavigationLink {
            ChallengeSignUpView(collectionSlug: collectionSlug, collectionTitle: effectiveTitle)
        } label: {
            Text("New prompt")
                .font(.system(size: buttonLabelSize, weight: .semibold))
                .foregroundStyle(palette.labelOnAccent)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.accent))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 26)
        .background(
            LinearGradient(
                colors: [
                    theme.appTheme.cardBackdrop,
                    theme.appTheme.cardBackdrop.opacity(0.96),
                    theme.appTheme.cardBackdrop.opacity(0.0)
                ],
                startPoint: .bottom,
                endPoint: .top
            )
        )
    }

    // MARK: - Header & Filter

    /// The counts are this page's, so a multi-page meme says which page.
    private var subtitleText: String {
        var line = AO3ChallengeCountText.plural(prompts.count, "prompt") + " · \(unclaimedCount) unclaimed"
        if let page = AO3ChallengeCountText.pageQualifier(page: currentPage, totalPages: totalPages) {
            line += " \(page)"
        }
        if !closeDateText.isEmpty {
            line += " · \(closeDateText)"
        }
        return line
    }

    private var header: some View {
        SubjectHeaderBlock(
            kicker: effectiveTitle,
            title: "Prompts",
            subtitle: subtitleText,
            palette: palette,
            gutter: SubjectMetrics.accountGutter
        )
    }

    private var filterSegment: some View {
        SubjectSegmentedControl(
            options: PromptFilter.allCases,
            title: \.rawValue,
            selection: $filterSelection
        )
    }

    // MARK: - Content Sections

    @ViewBuilder
    private var contentSections: some View {
        Section {
            SectionRuleHeader(title: filterSelection.rawValue, count: filteredPrompts.count)
                .pageBodyRow(top: 18, gutter: selfGuttered)

            if filteredPrompts.isEmpty {
                emptyFilteredCard.pageBodyRow(top: 8, gutter: gutter)
            } else {
                promptsList.pageBodyRow(top: 8, gutter: gutter)
            }

            footnoteText.pageBodyRow(top: 8, gutter: gutter)
        }

        if totalPages > 1 {
            Section {
                paginationBar.pageBodyRow(top: 4, gutter: gutter)
            }
        }

        // Room for the floating "New prompt" bar.
        Section {
            Spacer(minLength: 70)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
    }

    // MARK: - Prompt Cards

    private var promptsList: some View {
        VStack(spacing: 9) {
            ForEach(filteredPrompts) { prompt in
                promptCard(prompt)
            }
        }
    }

    private func promptCard(_ prompt: AO3PromptMemePrompt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // The spec's kicker is the fandom; a multi-fandom prompt adds "+N".
            HStack(spacing: 7) {
                if let fandom = prompt.fandoms.first {
                    Text(FandomDisplayName.bareTitle(fandom).uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .tracking(9 * 0.11)
                        .foregroundStyle(palette.accent)
                        .lineLimit(1)
                    if prompt.fandoms.count > 1 {
                        Text("+\(prompt.fandoms.count - 1)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.accent.opacity(0.6))
                    }
                }

                Text(prompt.isClaimed ? "claimed" : "unclaimed")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(9 * 0.05)
                    .foregroundStyle(Color.secondary.opacity(0.6))
            }

            if !prompt.title.isEmpty {
                Text(prompt.title)
                    .font(.system(size: cardTitleSize, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(prompt.promptText)
                .font(.system(size: promptBodySize))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !prompt.tagSummary.isEmpty {
                Text(prompt.tagSummary)
                    .font(.system(size: captionSize))
                    .foregroundStyle(Color.secondary.opacity(0.65))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(prompt.isAnonymous ? "Posted anonymously" : (prompt.displayedOwner ?? "Unknown poster"))
                .font(.system(size: captionSize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            promptActionRow(prompt)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .subjectPanel()
    }

    @ViewBuilder
    private func promptActionRow(_ prompt: AO3PromptMemePrompt) -> some View {
        let isInFlight = promptInFlight == prompt.id

        HStack {
            if prompt.claimedByCurrentUser {
                Text("Claimed by you")
                    .font(.system(size: bodySize, weight: .medium))
                    .foregroundStyle(palette.accent)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                promptActionButton(title: "Release", isProminent: false, isInFlight: isInFlight) {
                    Task { await release(prompt) }
                }
            } else if prompt.canClaim {
                // AO3 printed Claim for this viewer; a prompt meme takes several claims.
                Spacer()

                promptActionButton(title: "Claim", isProminent: true, isInFlight: isInFlight) {
                    Task { await claim(prompt) }
                }
            } else if prompt.isClaimed {
                Spacer()

                promptActionButton(title: "Fill it", systemImage: "safari", isProminent: false, isInFlight: false) {
                    router.open(AO3ChallengeURL.promptMeme(slug: collectionSlug))
                }
            }
        }
        .padding(.top, 2)
    }

    private func promptActionButton(
        title: String,
        systemImage: String? = nil,
        isProminent: Bool,
        isInFlight: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isInFlight {
                    ProgressView()
                        .controlSize(.small)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: bodySize, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(isProminent ? palette.labelOnAccent : palette.accent)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(
                Capsule().fill(isProminent ? palette.accent : palette.accent.opacity(0.14))
            )
        }
        .buttonStyle(.plain)
        .disabled(isInFlight || promptInFlight != nil)
        .layoutFreeHitTarget {
            if !isInFlight, promptInFlight == nil { action() }
        }
    }

    private var emptyFilteredCard: some View {
        VStack(spacing: 6) {
            Text(filterSelection == .all ? "No prompts yet" : "No \(filterSelection.rawValue.lowercased()) prompts")
                .font(.system(size: cardTitleSize, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(filterSelection == .all
                ? "Prompts will appear here once someone posts one."
                : "No prompts on this page match the \"\(filterSelection.rawValue)\" filter.")
                .font(.system(size: bodySize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .subjectPanel()
    }

    private var footnoteText: some View {
        Text("A Prompt Meme has no matching or assignments. You can claim a prompt here and release it "
            + "later. Add a new prompt through your sign-up, and post fills on AO3.")
            .font(.system(size: captionSize))
            .foregroundStyle(Color.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    private var paginationBar: some View {
        SearchPaginationBar(
            currentPage: currentPage,
            totalPages: totalPages,
            isLoading: phase == .loading,
            palette: palette
        ) { page in
            Task { await loadPrompts(page: page) }
        }
    }
}

// MARK: - State Cards and actions

private extension PromptMemeView {
    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Loading prompts…")
                .font(.system(size: loadingSize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }

    private func failureCard(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text("Couldn't load prompts")
                .font(.system(size: cardTitleSize, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.system(size: failureBodySize))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try Again") {
                Task { await loadPrompts(page: currentPage) }
            }
            .buttonStyle(.bordered)
            .tint(palette.tint)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .subjectPanel()
    }

    private func actionErrorCard(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Color.red)
            Text(message)
                .font(.system(size: bodySize))
                .foregroundStyle(Color.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                actionErrorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss error")
            .buttonStyle(.plain)
        }
        .padding(12)
        .subjectPanel()
    }

    // MARK: - Actions

    private func loadPromptsIfNeeded() async {
        guard phase == .idle else { return }
        await loadPrompts(page: 1)
    }

    private func loadPrompts(page: Int) async {
        phase = .loading

        // Best-effort schedule read, same fields Gift Exchange calls sign-ups —
        // AO3's prompt_meme form reuses `signups_open_at`/`signups_close_at` for
        // when prompts and claims are open, so this is genuinely the close date,
        // not a mislabelled sign-up date. Asked for once: it doesn't change page
        // to page or after a claim/release. This used to test only whether a
        // date had arrived, so a lookup that could not succeed (anyone but an
        // owner, or a challenge with no close date) was sent again with every
        // page and every claim: two signed-in requests each time, for nothing.
        if Self.readsSchedule(
            viewerIsOwner: viewerIsOwner, attempted: scheduleAttempted, hasDate: !closeDateText.isEmpty
        ) {
            scheduleAttempted = true
            if let settingsRequest = try? auth.authenticatedRequest(
                for: AO3ChallengeURL.promptMemeEdit(slug: collectionSlug)
            ),
                let form = try? await AO3Client.shared.challengeSettings(
                    slug: collectionSlug, request: settingsRequest
                ),
                let closeDate = form.settings.signupsCloseAt.dateText {
                closeDateText = "open until \(closeDate)"
            }
        }

        do {
            // Public listing: goes through the signed-in session when there is
            // one (claim state is only known when logged in) and anonymously
            // otherwise, same as AO3CollectionDetailView's own loader.
            let request: URLRequest? = {
                guard auth.isLoggedIn else { return nil }
                return try? auth.authenticatedRequest(
                    for: AO3ChallengeURL.requests(slug: collectionSlug, page: page)
                )
            }()
            let promptsPage = try await AO3Client.shared.promptMemePrompts(
                slug: collectionSlug, page: page, request: request
            )
            prompts = promptsPage.prompts
            currentPage = promptsPage.currentPage
            totalPages = promptsPage.totalPages
            phase = .loaded
        } catch {
            phase = .failed(UserFacingError.message(for: error))
        }
    }

    private func claim(_ prompt: AO3PromptMemePrompt) async {
        promptInFlight = prompt.id
        actionErrorMessage = nil
        do {
            try await auth.claimPrompt(slug: collectionSlug, promptID: prompt.id)
            await loadPrompts(page: currentPage)
        } catch {
            actionErrorMessage = "Couldn't claim that prompt: \(UserFacingError.message(for: error))"
        }
        promptInFlight = nil
    }

    private func release(_ prompt: AO3PromptMemePrompt) async {
        guard let claimID = prompt.claimID else { return }
        promptInFlight = prompt.id
        actionErrorMessage = nil
        do {
            try await auth.releasePrompt(slug: collectionSlug, claimID: claimID)
            await loadPrompts(page: currentPage)
        } catch {
            actionErrorMessage = "Couldn't release that prompt: \(UserFacingError.message(for: error))"
        }
        promptInFlight = nil
    }
}
