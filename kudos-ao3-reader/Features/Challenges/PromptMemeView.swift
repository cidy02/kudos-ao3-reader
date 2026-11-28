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
    /// Kind already read from the collection page. Nil keeps the gift-then-meme probe.
    var challengeKind: AO3ChallengeKind?

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

    @ScaledMetric(relativeTo: .body) private var cardTitleSize: CGFloat = 17
    @ScaledMetric(relativeTo: .subheadline) private var promptBodySize: CGFloat = 14
    @ScaledMetric(relativeTo: .subheadline) private var loadingSize: CGFloat = 14
    @ScaledMetric(relativeTo: .footnote) private var bodySize: CGFloat = 13
    @ScaledMetric(relativeTo: .footnote) private var failureBodySize: CGFloat = 13
    @ScaledMetric(relativeTo: .footnote) private var subSize: CGFloat = 13
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 12

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
    @State private var showingNewPrompt = false

    enum PromptFilter: String, CaseIterable, Hashable, Sendable {
        case all = "All"
        case unclaimed = "Unclaimed"
        case yours = "Yours"

        var chipTitle: String {
            switch self {
            case .all: "All"
            case .unclaimed: "Unclaimed"
            case .yours: ChallengesBoardCopy.promptMemeClaimedByMeChipLabel
            }
        }
    }

    private enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private var gutter: CGFloat { SubjectMetrics.accountGutter }

    private var palette: SubjectPalette {
        theme.appTheme.subjectPalette(hue: CoverArt.workHue(fandoms: [], title: effectiveTitle))
    }

    private var effectiveTitle: String {
        collectionTitle.isEmpty ? collectionSlug : collectionTitle
    }

    private var yoursCount: Int {
        let loggedInName = auth.username ?? ""
        return prompts.filter { prompt in
            if prompt.claimedByCurrentUser { return true }
            return AO3ChallengeSignUpMatching.owns(
                byline: prompt.displayedOwner ?? "", login: loggedInName
            )
        }.count
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
        promptList
            .toolbar {
                if auth.isLoggedIn {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingNewPrompt = true
                        } label: {
                            Label(ChallengesBoardCopy.promptMemeNewPromptLabel, systemImage: "plus")
                        }
                        .accessibilityLabel(ChallengesBoardCopy.promptMemeNewPromptLabel)
                    }
                }
            }
            .navigationDestination(isPresented: $showingNewPrompt) {
                ChallengeSignUpView(collectionSlug: collectionSlug, collectionTitle: effectiveTitle)
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
                contextCard.pageBodyRow(top: 12, gutter: gutter).id(Self.headerRowID)
                if phase == .loaded, !prompts.isEmpty {
                    ChallengeBoardStatStrip(cells: statCells, surface: .list)
                        .pageBodyRow(top: 14, gutter: gutter)
                }
                filterChipRail.pageBodyRow(top: 14, gutter: 0)
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
        .subjectScreenWash(title: "Prompts", palette: palette, role: .content)
    }

    // MARK: - Header & Filter (`Prompt-Meme.dc.html`)

    private var contextCard: some View {
        let metaParts: [String?] = [
            closeDateText.isEmpty ? nil : closeDateText,
            AO3ChallengeCountText.pageQualifier(page: currentPage, totalPages: totalPages)
        ]
        let meta = metaParts.compactMap { $0 }.joined(separator: " · ")
        return ChallengeBoardContextCard(
            systemImage: "bubble.left",
            kicker: ChallengesBoardCopy.promptMemeContextKicker(fandoms: prompts.map(\.fandoms)),
            title: effectiveTitle,
            meta: meta.isEmpty ? nil : meta,
            palette: palette,
            surface: .list
        )
    }

    private var statCells: [ChallengeBoardStatStrip.Cell] {
        let claimed = prompts.filter(\.isClaimed).count
        return [
            ChallengeBoardStatStrip.Cell(value: prompts.count.formatted(), label: "Prompts"),
            ChallengeBoardStatStrip.Cell(value: claimed.formatted(), label: "Claimed"),
            ChallengeBoardStatStrip.Cell(
                value: yoursCount.formatted(),
                label: "Yours",
                tint: yoursCount > 0 ? theme.accentInk : nil
            )
        ]
    }

    private var filterChipRail: some View {
        AccessibilityChipRail(horizontalPadding: gutter) {
            ForEach(PromptFilter.allCases, id: \.self) { option in
                let selected = filterSelection == option
                Button {
                    filterSelection = option
                } label: {
                    ChallengeBoardChipLabel(text: option.chipTitle, isSelected: selected)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.chipTitle)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    // MARK: - Content Sections

    @ViewBuilder
    private var contentSections: some View {
        Section {
            if filteredPrompts.isEmpty {
                emptyFilteredCard.pageBodyRow(top: 10, gutter: gutter)
            } else {
                ForEach(Array(filteredPrompts.enumerated()), id: \.element.id) { index, prompt in
                    VStack(spacing: 0) {
                        if index > 0 { SubjectRowSeparator(inset: dynamicTypeSize.isAccessibilitySize ? 0 : 56) }
                        promptRow(prompt)
                    }
                    .pageBodyRow(top: 0, gutter: gutter)
                }
            }

            footnoteText.pageBodyRow(top: 10, gutter: gutter)
        }

        if totalPages > 1 {
            Section {
                paginationBar.pageBodyRow(top: 4, gutter: gutter)
            }
        }
    }

    // MARK: - Prompt Rows (`Prompt-Meme.dc.html`)

    private func promptRow(_ prompt: AO3PromptMemePrompt) -> some View {
        let heading = prompt.title.isEmpty ? prompt.promptText : prompt.title
        let showBody = !prompt.title.isEmpty && !prompt.promptText.isEmpty
        let byline = ChallengesBoardCopy.promptMemeByline(
            isAnonymous: prompt.isAnonymous,
            owner: prompt.displayedOwner
        )
        let chips = ChallengesBoardCopy.promptMemeTagChips(
            fandoms: prompt.fandoms,
            tagSummary: prompt.tagSummary,
            limit: 4
        )
        let status = ChallengesBoardCopy.promptMemeStatusMeta(
            claimedByCurrentUser: prompt.claimedByCurrentUser,
            claimantCount: prompt.claimantCount
        )
        let rowLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))

        return rowLayout {
            if !dynamicTypeSize.isAccessibilitySize {
                ChallengeBoardAvatar(
                    text: nil,
                    systemImage: "bubble.left.fill",
                    color: palette.accent,
                    shapeKind: .roundedSquare(size: 44, radius: 10)
                )
                .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(heading)
                    .font(.system(size: cardTitleSize, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(byline)
                    .font(.system(size: subSize))
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)

                if showBody {
                    Text(prompt.promptText)
                        .font(.system(size: promptBodySize))
                        .foregroundStyle(.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }

                if !chips.isEmpty {
                    FlowLayout(spacing: 4, rowSpacing: 4) {
                        ForEach(chips) { chip in
                            ChallengeBoardTagPill(text: chip.label, isTinted: chip.isTinted)
                        }
                    }
                    .padding(.top, 2)
                }

                Text(status.text)
                    .font(.system(size: captionSize, weight: status.isAccent ? .semibold : .regular))
                    .foregroundStyle(status.isAccent ? AnyShapeStyle(theme.accentInk) : AnyShapeStyle(.secondaryInk))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            promptTrailingControl(prompt)
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func promptTrailingControl(_ prompt: AO3PromptMemePrompt) -> some View {
        let isInFlight = promptInFlight == prompt.id
        if prompt.claimedByCurrentUser {
            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 6) {
                ChallengeBoardBadge(text: "Claimed", style: .accentFill)
                ChallengeBoardInlineActionButton(
                    title: "Release",
                    role: .secondary,
                    isBusy: isInFlight,
                    isDisabled: promptInFlight != nil
                ) {
                    Task { await release(prompt) }
                }
            }
        } else if prompt.canClaim {
            ChallengeBoardInlineActionButton(
                title: "Claim",
                role: .softAccent,
                isBusy: isInFlight,
                isDisabled: promptInFlight != nil
            ) {
                Task { await claim(prompt) }
            }
        } else if prompt.isClaimed {
            ChallengeBoardInlineActionButton(
                title: "Fill it",
                systemImage: "safari",
                role: .secondary
            ) {
                router.open(AO3ChallengeURL.promptMeme(slug: collectionSlug))
            }
        }
    }

    private var emptyFilteredCard: some View {
        VStack(spacing: 6) {
            Text(
                ChallengesBoardCopy.promptMemeEmptyTitle(
                    filterName: filterSelection.chipTitle,
                    isAllFilter: filterSelection == .all
                )
            )
            .font(.system(size: cardTitleSize, weight: .semibold))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)

            Text(
                ChallengesBoardCopy.promptMemeEmptyBody(
                    filterName: filterSelection.chipTitle,
                    isAllFilter: filterSelection == .all
                )
            )
            .font(.system(size: bodySize))
            .foregroundStyle(.secondaryInk)
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
                .accentFill()
            Text("Loading prompts…")
                .font(.system(size: loadingSize))
                .foregroundStyle(.secondaryInk)
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
                .foregroundStyle(.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try Again") {
                Task { await loadPrompts(page: currentPage) }
            }
            .buttonStyle(.kudosSecondary)
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
                    .foregroundStyle(.secondaryInk)
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
                    slug: collectionSlug, request: settingsRequest, kind: challengeKind
                ),
                let closeDate = form.settings.signupsCloseAt.dateText {
                closeDateText = ChallengesBoardCopy.promptMemeOpenUntil(closeDate)
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
