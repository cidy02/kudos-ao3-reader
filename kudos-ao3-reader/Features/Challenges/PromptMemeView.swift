import SwiftUI

/// Artboard **1cc** — Prompt Meme prompts.
///
/// AO3's other challenge type: no sign-ups, no matching, no assignments —
/// prompts are posted and claimed freely, so this screen replaces 1bz/1cb
/// entirely for a collection whose challenge `kind` is `.promptMeme` rather
/// than sitting alongside them. Each card reads as prose, the way a prompt
/// actually is, with only the claim state as chrome (no cover art, no stat
/// strip). Claim and release are real writes (`AO3ChallengeActions.claimPrompt`
/// / `releasePrompt`); posting a brand-new prompt has no client endpoint at
/// all — `AO3ChallengeActions.swift` has no method for it — so "New prompt"
/// is an honest "Opens AO3" row rather than a form this app can't submit.
/// "Fill it" is the same story: filling someone else's claimed prompt means
/// posting a whole new work, which this screen doesn't attempt either, so it
/// too opens the meme on AO3 instead of gating the participant from writing.
struct PromptMemeView: View {
    let collectionSlug: String
    var collectionTitle: String = ""

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @Environment(AppRouter.self) private var router

    @State private var prompts: [AO3PromptMemePrompt] = []
    @State private var currentPage: Int = 1
    @State private var totalPages: Int = 1
    @State private var filterSelection: PromptFilter = .all
    @State private var closeDateText: String = ""
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
            let loggedInName = auth.username?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return prompts.filter { prompt in
                if prompt.claimedByCurrentUser { return true }
                guard let loggedInName, !loggedInName.isEmpty else { return false }
                return prompt.displayedOwner?.lowercased() == loggedInName
            }
        }
    }

    var body: some View {
        List {
            Section {
                header.pageBodyRow(top: 20, gutter: selfGuttered)
                filterSegment.pageBodyRow(top: 14, gutter: gutter)
            }

            if let actionErrorMessage {
                Section {
                    actionErrorCard(actionErrorMessage).pageBodyRow(top: 8, gutter: gutter)
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
        #if os(macOS)
        .navigationTitle("Prompts")
        #endif
        .subjectScreenWash(palette: palette)
        .task { await loadPromptsIfNeeded() }
        .refreshable { await loadPrompts(page: 1) }
    }

    // MARK: - Header & Filter

    private var subtitleText: String {
        var line = "\(prompts.count) prompt\(prompts.count == 1 ? "" : "s") · \(unclaimedCount) unclaimed"
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
            SectionRuleHeader(title: "Prompts", count: filteredPrompts.count)
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

        Section {
            SectionRuleHeader(title: "At AO3")
                .pageBodyRow(top: 18, gutter: selfGuttered)
            escapeHatchPanel.pageBodyRow(top: 8, gutter: gutter)
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
            HStack(spacing: 7) {
                if !prompt.title.isEmpty {
                    Text(prompt.title.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .tracking(9 * 0.11)
                        .foregroundStyle(palette.accent)
                        .lineLimit(1)
                }

                Text(prompt.isClaimed ? "claimed" : "unclaimed")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(9 * 0.05)
                    .foregroundStyle(Color.secondary.opacity(0.6))
            }

            Text(prompt.promptText)
                .font(.system(size: 14.5))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !prompt.tagSummary.isEmpty {
                Text(prompt.tagSummary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.secondary.opacity(0.65))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Text(prompt.isAnonymous ? "Posted anonymously" : (prompt.displayedOwner ?? "Unknown poster"))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

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
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(palette.accent)

                Spacer()

                promptActionButton(title: "Release", isProminent: false, isInFlight: isInFlight) {
                    Task { await release(prompt) }
                }
            } else if prompt.isClaimed {
                Spacer()

                promptActionButton(title: "Fill it", systemImage: "safari", isProminent: false, isInFlight: false) {
                    router.open(AO3ChallengeURL.promptMeme(slug: collectionSlug))
                }
            } else {
                Spacer()

                promptActionButton(title: "Claim", isProminent: true, isInFlight: isInFlight) {
                    Task { await claim(prompt) }
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
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isProminent ? palette.accentOnFill : palette.accent)
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(
                Capsule().fill(isProminent ? palette.accent : palette.accent.opacity(0.14))
            )
        }
        .buttonStyle(.plain)
        .disabled(isInFlight || promptInFlight != nil)
    }

    private var emptyFilteredCard: some View {
        VStack(spacing: 6) {
            Text("No \(filterSelection.rawValue.lowercased()) prompts")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            Text("No prompts on this page match the \"\(filterSelection.rawValue)\" filter.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .subjectPanel()
    }

    private var footnoteText: some View {
        Text("AO3 posts and claims prompts with no sign-up or matching step in between. "
            + "The app can claim a prompt for you and release your own claim; writing a fill for "
            + "someone else's claimed prompt, and posting a brand-new prompt, both happen on AO3 itself.")
            .font(.system(size: 11.5))
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

    private var escapeHatchPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(
                label: "New prompt",
                value: "Opens AO3",
                showsDisclosure: true
            ) {
                router.open(AO3ChallengeURL.promptMeme(slug: collectionSlug))
            }
        }
        .subjectPanel()
    }

    // MARK: - State Cards

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Loading prompts…")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }

    private func failureCard(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text("Couldn't load prompts")
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadPrompts(page: currentPage) }
            }
            .buttonStyle(.bordered)
            .tint(palette.accent)
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
                .font(.system(size: 12.5))
                .foregroundStyle(Color.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                actionErrorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
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
        // not a mislabelled sign-up date. Fetched once; it doesn't change page to
        // page or after a claim/release.
        if closeDateText.isEmpty,
           let settingsRequest = try? auth.authenticatedRequest(
               for: AO3ChallengeURL.promptMemeEdit(slug: collectionSlug)
           ),
           let form = try? await AO3Client.shared.challengeSettings(slug: collectionSlug, request: settingsRequest),
           let closeDate = form.settings.signupsCloseAt.date {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            closeDateText = "open until \(formatter.string(from: closeDate))"
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
            phase = .failed(error.localizedDescription)
        }
    }

    private func claim(_ prompt: AO3PromptMemePrompt) async {
        promptInFlight = prompt.id
        actionErrorMessage = nil
        do {
            try await auth.claimPrompt(slug: collectionSlug, promptID: prompt.id)
            await loadPrompts(page: currentPage)
        } catch {
            actionErrorMessage = "Couldn't claim that prompt: \(error.localizedDescription)"
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
            actionErrorMessage = "Couldn't release that prompt: \(error.localizedDescription)"
        }
        promptInFlight = nil
    }
}
